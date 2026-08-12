// First-run onboarding (Sous). A brand-new household talks to Sous, who
// collects their setup conversationally and saves it via the save_setup tool.
// Once saved, the household is marked onboarded and normal routing takes over.

import { dbClient } from "./db.ts";
import { completeRaw, normalize, type Msg } from "./anthropic.ts";
import { sendMessage } from "./telegram.ts";
import { SOUS_VOICE } from "./persona.ts";
import { DIET_KEYS, normalizeDiet } from "./diet.ts";
import { normalizeTimezone } from "./schedule.ts";

const MODEL = Deno.env.get("SOUS_CHAT_MODEL") ?? "claude-sonnet-4-6";

const DIET_LIST = DIET_KEYS.join(", ");

const ONBOARDING_SYSTEM = SOUS_VOICE + `

RIGHT NOW you're setting up a brand-new household — you don't know them yet, and you can't plan anything until you do. Collect these, conversationally (a couple at a time, not an interrogation), in your usual punchy voice:
1. How many adults.
2. Any kids, and each kid's age — precise enough to tell a baby (<1yr) from a toddler; ask in months for under-2s.
3. How many dinners they want planned per week (1–7; most pick 5).
4. Their monthly grocery budget (a dollar amount).
5. What cuisines / kinds of food they love.
6. Any dietary restrictions or allergies for ANYONE in the household — this one matters, ask it plainly (e.g. "anyone vegetarian, allergies, foods you avoid?"). Map their answer to save_setup's dietary_restrictions using ONLY these keys: ${DIET_LIST}. For a specific ingredient they avoid that isn't one of those keys (a named allergy or hard dislike), put the ingredient name in excluded_ingredients. If they have none, pass empty arrays — but you must still ask.
7. Roughly where they live, so the weekly plan lands at a sensible local hour. Ask casually ("what city are you in?" / "what timezone are you in?") — you only need enough to pick an IANA timezone, and you must convert it yourself (e.g. "Berlin" -> Europe/Berlin, "Austin" -> America/Chicago, "EST" -> America/New_York). Never ask them for an IANA string.

Open with a short, warm Sous-style hello + your first question or two. As soon as you have ALL SEVEN, call save_setup with structured values (convert kid ages to months). Do NOT call it early or guess — ask, especially about allergies. After it's saved, you'll be told; then hype them up and tell them to say "plan my week" when ready.

IMPORTANT — if they name ANY allergy or dietary restriction in step 6, say this plainly once, in your own voice, before moving on: you filter recipes on it every week, but you're working from a recipe catalog and not from the actual packages in their kitchen, so they should still read labels — and for a severe allergy they should not rely on you alone. Say it once, warmly, without lecturing or repeating it later.`;

const SAVE_SETUP_TOOL = {
  name: "save_setup",
  description:
    "Save the household's setup. Only call once you have ALL of: number of adults, every kid's age, dinners per week, monthly grocery budget, preferred cuisines, dietary restrictions/allergies (ask even if the answer is none), and their timezone.",
  input_schema: {
    type: "object",
    properties: {
      adults: { type: "integer", minimum: 1 },
      kids: {
        type: "array",
        description: "one entry per child; empty array if none",
        items: {
          type: "object",
          properties: { age_months: { type: "integer", minimum: 0, maximum: 215 } },
          required: ["age_months"],
        },
      },
      meals_per_week: { type: "integer", minimum: 1, maximum: 7 },
      monthly_budget_usd: { type: "number", minimum: 0 },
      cuisines: { type: "array", items: { type: "string" } },
      dietary_restrictions: {
        type: "array",
        description:
          `canonical diet keys the whole household needs honored; empty if none. Allowed: ${DIET_LIST}`,
        items: { type: "string", enum: [...DIET_KEYS] },
      },
      excluded_ingredients: {
        type: "array",
        description:
          "specific ingredient names (or allergen words like 'peanuts') to always avoid, beyond the canonical diet keys; empty if none",
        items: { type: "string" },
      },
      timezone: {
        type: "string",
        description:
          "IANA timezone name you inferred from where they said they live, e.g. Europe/Berlin, America/Chicago, Asia/Tokyo. Never ask the household for this string — convert it from their city or region yourself.",
      },
    },
    required: [
      "adults", "kids", "meals_per_week", "monthly_budget_usd", "cuisines",
      "dietary_restrictions", "timezone",
    ],
  },
};

export async function runOnboarding(conversationId: string): Promise<void> {
  const db = dbClient();
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN")!;
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")!;

  const { data: convo } = await db
    .from("conversations")
    .select("id, household_id, telegram_chat_id")
    .eq("id", conversationId)
    .maybeSingle();
  if (!convo) return;

  const { data: history } = await db
    .from("messages")
    .select("direction, text, created_at")
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: false })
    .limit(16);
  const turns: Msg[] = normalize(
    (history ?? []).reverse().map((m: { direction: string; text: string | null }) => ({
      role: m.direction === "in" ? "user" : "assistant",
      content: m.text ?? "",
    })),
  );

  const first = await completeRaw({
    apiKey,
    model: MODEL,
    system: ONBOARDING_SYSTEM,
    messages: turns.length ? turns : [{ role: "user", content: "(new chat)" }],
    tools: [SAVE_SETUP_TOOL],
    maxTokens: 1024,
  });

  let reply = first.text;

  const call = first.toolUses.find((t) => t.name === "save_setup");
  if (call) {
    await saveSetup(db, convo.household_id, call.input);
    await db.from("conversations").update({ state: "idle" }).eq("id", conversationId);

    const second = await completeRaw({
      apiKey,
      model: MODEL,
      system: ONBOARDING_SYSTEM,
      messages: [
        ...turns,
        { role: "assistant", content: first.content },
        {
          role: "user",
          content: [{
            type: "tool_result",
            tool_use_id: call.id,
            content: "saved — setup complete. Welcome them and tell them to say \"plan my week\" when ready.",
          }],
        },
      ],
      tools: [SAVE_SETUP_TOOL],
      maxTokens: 512,
    });
    reply = second.text || "you're all set 🍳 say \"plan my week\" whenever you're ready.";
  }

  reply = reply || "give me one sec...";
  await db.from("messages").insert({
    conversation_id: conversationId,
    direction: "out",
    text: reply,
  });
  await sendMessage(botToken, convo.telegram_chat_id, reply);
}

async function saveSetup(
  db: ReturnType<typeof dbClient>,
  householdId: string,
  input: Record<string, unknown>,
): Promise<void> {
  const adults = clampInt(input.adults, 1, 12, 2);
  const meals = clampInt(input.meals_per_week, 1, 7, 5);
  const budget = typeof input.monthly_budget_usd === "number"
    ? input.monthly_budget_usd
    : Number(input.monthly_budget_usd) || null;
  const kids = Array.isArray(input.kids)
    ? (input.kids as { age_months?: unknown }[])
      .map((k) => ({ age_months: clampInt(k?.age_months, 0, 215, 0) }))
    : [];
  const cuisines = Array.isArray(input.cuisines)
    ? (input.cuisines as unknown[]).map((c) => String(c)).filter(Boolean)
    : [];
  // The tool schema declares an enum, but the API does not enforce it — a model
  // that writes "nut_free" instead of "no_nuts" would be persisted verbatim and
  // then match nothing in the SQL filter, leaving the household believing an
  // allergy is enforced when it is not. Normalize server-side; anything we
  // can't map to a canonical key becomes an ingredient exclusion rather than
  // being dropped.
  const { dietary_restrictions, excluded_ingredients, unrecognized } = normalizeDiet(
    input.dietary_restrictions,
    input.excluded_ingredients,
  );
  if (unrecognized.length) {
    console.warn(
      `saveSetup: unrecognized diet keys kept as ingredient exclusions: ${unrecognized.join(", ")}`,
    );
  }

  const { error } = await db.from("household_preferences").upsert(
    {
      household_id: householdId,
      adults,
      kids,
      meals_per_week: meals,
      monthly_budget_usd: budget,
      cuisines,
      dietary_restrictions,
      excluded_ingredients,
      onboarded: true,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "household_id" },
  );
  if (error) console.error("saveSetup failed", error);

  // Timezone lives on households, not household_preferences, and drives which
  // hour the weekly kickoff fires in (see kickoff_week + 20260728000500). Left
  // unset it would fall back to the column default, which is one region's
  // 6pm for everyone on earth.
  const tz = normalizeTimezone(input.timezone);
  if (tz) {
    const { error: tzError } = await db
      .from("households")
      .update({ timezone: tz })
      .eq("id", householdId);
    if (tzError) console.error("saveSetup: timezone update failed", tzError);
  } else {
    console.warn(`saveSetup: ignoring invalid timezone ${JSON.stringify(input.timezone)}`);
  }
}

function clampInt(v: unknown, lo: number, hi: number, dflt: number): number {
  const n = Math.round(Number(v));
  if (!Number.isFinite(n)) return dflt;
  return Math.min(hi, Math.max(lo, n));
}
