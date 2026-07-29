// First-run onboarding (Sous). A brand-new household talks to Sous, who
// collects their setup conversationally and saves it via the save_setup tool.
// Once saved, the household is marked onboarded and normal routing takes over.

import { dbClient } from "./db.ts";
import { completeRaw, normalize, type Msg } from "./anthropic.ts";
import { sendMessage } from "./telegram.ts";
import { SOUS_VOICE } from "./persona.ts";

const MODEL = Deno.env.get("SOUS_CHAT_MODEL") ?? "claude-sonnet-4-6";

const ONBOARDING_SYSTEM = SOUS_VOICE + `

RIGHT NOW you're setting up a brand-new household — you don't know them yet, and you can't plan anything until you do. Collect these, conversationally (a couple at a time, not an interrogation), in your usual punchy voice:
1. How many adults.
2. Any kids, and each kid's age — precise enough to tell a baby (<1yr) from a toddler; ask in months for under-2s.
3. How many dinners they want planned per week (1–7; most pick 5).
4. Their monthly grocery budget (a dollar amount).
5. What cuisines / kinds of food they love.
6. Any dietary restrictions or allergies for ANYONE in the household — this one matters, ask it plainly (e.g. "anyone vegetarian, allergies, foods you avoid?"). Map their answer to save_setup's dietary_restrictions using ONLY these keys: vegetarian, vegan, pescatarian, gluten_free, dairy_free, halal, kosher, no_pork, no_beef, no_poultry, no_shellfish, no_fish, no_nuts, no_soy, no_egg. For a specific ingredient they avoid that isn't one of those keys (a named allergy or hard dislike), put the ingredient name in excluded_ingredients. If they have none, pass empty arrays — but you must still ask.

Open with a short, warm Sous-style hello + your first question or two. As soon as you have ALL SIX, call save_setup with structured values (convert kid ages to months). Do NOT call it early or guess — ask, especially about allergies. After it's saved, you'll be told; then hype them up and tell them to say "plan my week" when ready.`;

const SAVE_SETUP_TOOL = {
  name: "save_setup",
  description:
    "Save the household's setup. Only call once you have ALL of: number of adults, every kid's age, dinners per week, monthly grocery budget, preferred cuisines, and dietary restrictions/allergies (ask even if the answer is none).",
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
          "canonical diet keys the whole household needs honored; empty if none. Allowed: vegetarian, vegan, pescatarian, gluten_free, dairy_free, halal, kosher, no_pork, no_beef, no_poultry, no_shellfish, no_fish, no_nuts, no_soy, no_egg",
        items: {
          type: "string",
          enum: [
            "vegetarian", "vegan", "pescatarian", "gluten_free", "dairy_free",
            "halal", "kosher", "no_pork", "no_beef", "no_poultry",
            "no_shellfish", "no_fish", "no_nuts", "no_soy", "no_egg",
          ],
        },
      },
      excluded_ingredients: {
        type: "array",
        description:
          "specific ingredient names (or allergen words like 'peanuts') to always avoid, beyond the canonical diet keys; empty if none",
        items: { type: "string" },
      },
    },
    required: [
      "adults", "kids", "meals_per_week", "monthly_budget_usd", "cuisines",
      "dietary_restrictions",
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
  const dietary_restrictions = Array.isArray(input.dietary_restrictions)
    ? (input.dietary_restrictions as unknown[]).map((c) => String(c)).filter(Boolean)
    : [];
  const excluded_ingredients = Array.isArray(input.excluded_ingredients)
    ? (input.excluded_ingredients as unknown[]).map((c) => String(c)).filter(Boolean)
    : [];

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
}

function clampInt(v: unknown, lo: number, hi: number, dflt: number): number {
  const n = Math.round(Number(v));
  if (!Number.isFinite(n)) return dflt;
  return Math.min(hi, Math.max(lo, n));
}
