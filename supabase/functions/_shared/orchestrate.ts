// Core orchestration (SPEC §9.3 "User reply"), shared so it can run either
// in-process from tg_webhook (via EdgeRuntime.waitUntil) or from the standalone
// orchestrator HTTP function.
//
// Day-2 conversation + a rate_meal tool: when the user says how much they liked
// a dish, Sous records a 1-5 recipe rating (5 = best) that feeds future planning.
// Haiku intent classification and the planning tools (swap/lock) come later.

import { dbClient } from "./db.ts";
import { completeRaw, type Msg, normalize } from "./anthropic.ts";
import { sendMessage } from "./telegram.ts";
import { sousSystem } from "./persona.ts";
import { describeHousehold, getPreferences } from "./household.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

const WORKHORSE_MODEL = "claude-sonnet-4-6"; // SPEC §9.1

const RATE_MEAL_TOOL = {
  name: "rate_meal",
  description:
    "Record the household's rating for a specific dish on a 1-5 scale (5 = best). Call this whenever the user expresses how much they liked or disliked a named dish — whether they give a number ('the carnitas were a 5') or clear sentiment you can map to 1-5 ('kids loved the ziti', 'the curry was a miss').",
  input_schema: {
    type: "object",
    properties: {
      recipe_title: {
        type: "string",
        description: "the dish name as the user referred to it",
      },
      rating: { type: "integer", minimum: 1, maximum: 5 },
      note: { type: "string", description: "optional short note (e.g. 'too spicy for kids')" },
    },
    required: ["recipe_title", "rating"],
  },
};

const RATE_INSTRUCTION =
  `\n\nIf the user signals how much they liked a specific dish, call rate_meal to log it (map clear sentiment to a 1-5 if they don't give a number), then acknowledge in one short line. Don't ask for a rating they didn't offer.`;

export async function runOrchestrator(conversationId: string): Promise<string> {
  const db = dbClient();

  const { data: convo } = await db
    .from("conversations")
    .select("id, household_id, telegram_chat_id")
    .eq("id", conversationId)
    .maybeSingle();
  if (!convo) {
    console.error("orchestrator: conversation not found", conversationId);
    return "";
  }

  // Build the system prompt from this household's onboarding preferences.
  const desc = describeHousehold(await getPreferences(db, convo.household_id));
  const SYSTEM = sousSystem(desc.context) + RATE_INSTRUCTION;

  // Who sent the latest inbound turn (the rater).
  const { data: lastIn } = await db
    .from("messages")
    .select("sender_user_id")
    .eq("conversation_id", conversationId)
    .eq("direction", "in")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  const raterId: string | null = lastIn?.sender_user_id ?? null;

  // Rolling transcript: last 10 turns, oldest first.
  const { data: history } = await db
    .from("messages")
    .select("direction, text, created_at")
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: false })
    .limit(10);
  const turns: Msg[] = normalize(
    (history ?? [])
      .reverse()
      .map((m: { direction: string; text: string | null }) => ({
        role: m.direction === "in" ? "user" : "assistant",
        content: m.text ?? "",
      })),
  );

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")!;
  const first = await completeRaw({
    apiKey,
    model: WORKHORSE_MODEL,
    system: SYSTEM,
    messages: turns.length ? turns : [{ role: "user", content: "(say hello)" }],
    tools: [RATE_MEAL_TOOL],
    maxTokens: 1024,
  });

  let reply = first.text;

  // Execute any tool calls, then ask the model for the natural-language reply.
  if (first.toolUses.length) {
    const toolResults = [];
    for (const tu of first.toolUses) {
      const content = tu.name === "rate_meal"
        ? await recordRating(db, convo.household_id, raterId, tu.input)
        : "unknown tool";
      toolResults.push({ type: "tool_result", tool_use_id: tu.id, content });
    }
    const second = await completeRaw({
      apiKey,
      model: WORKHORSE_MODEL,
      system: SYSTEM,
      messages: [
        ...turns,
        { role: "assistant", content: first.content },
        { role: "user", content: toolResults },
      ],
      tools: [RATE_MEAL_TOOL],
      maxTokens: 1024,
    });
    reply = second.text || reply;
  }

  reply = reply || "hm, my brain blanked for a sec — say that again?";

  // Persist outbound before sending (SPEC §9.6: state to DB first).
  await db.from("messages").insert({
    conversation_id: conversationId,
    direction: "out",
    text: reply,
  });
  await sendMessage(Deno.env.get("TELEGRAM_BOT_TOKEN")!, convo.telegram_chat_id, reply);

  return reply;
}

async function recordRating(
  db: SupabaseClient,
  householdId: string,
  raterId: string | null,
  input: Record<string, unknown>,
): Promise<string> {
  const title = String(input.recipe_title ?? "").trim();
  const rating = Number(input.rating);
  const note = input.note ? String(input.note) : null;
  if (!title || !(rating >= 1 && rating <= 5)) {
    return "could not record — need a dish name and a 1-5 rating";
  }
  if (!raterId) return "could not identify who is rating";

  const { data: rec } = await db
    .from("recipes")
    .select("id, title")
    .ilike("title", `%${title}%`)
    .limit(1)
    .maybeSingle();
  if (!rec) return `no recipe matched "${title}"`;

  const { error } = await db.from("recipe_ratings").upsert(
    {
      household_id: householdId,
      recipe_id: rec.id,
      rater_user_id: raterId,
      rating,
      note,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "recipe_id,rater_user_id" },
  );
  if (error) {
    console.error("rating upsert failed", error);
    return "hit a snag saving that rating";
  }
  return `recorded ${rec.title} = ${rating}/5`;
}
