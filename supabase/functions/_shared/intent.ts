// Intent classification (SPEC §9.3 "User reply" step 2) — a cheap Haiku call
// that routes a free-text message to plan / swap / lock / chat. Anything that
// isn't a clear planning verb falls through to chat (the conversational
// orchestrator, which also records ratings).

import { completeRaw } from "./anthropic.ts";

const INTENT_MODEL = "claude-haiku-4-5-20251001"; // SPEC §9.1

export type Intent = "plan" | "swap" | "lock" | "chat";
export type Day = "mon" | "tue" | "wed" | "thu" | "fri";

const ROUTE_TOOL = {
  name: "route",
  description: "Route the user's message to the right action.",
  input_schema: {
    type: "object",
    properties: {
      intent: {
        type: "string",
        enum: ["plan", "swap", "lock", "chat"],
        description:
          "plan = wants next week's dinners proposed; swap = wants to change one day's dinner; lock = confirm/finalize the week; chat = anything else, including rating a dish or general conversation",
      },
      day: {
        type: "string",
        enum: ["mon", "tue", "wed", "thu", "fri"],
        description: "for swap: which weekday's dinner to change, if named",
      },
    },
    required: ["intent"],
  },
};

export async function classifyIntent(
  text: string,
): Promise<{ intent: Intent; day?: Day }> {
  const { toolUses } = await completeRaw({
    apiKey: Deno.env.get("ANTHROPIC_API_KEY")!,
    model: INTENT_MODEL,
    system:
      `Classify the user's message for a household meal-planning bot. Use 'plan' only when they want a new week proposed ("plan next week", "what's for dinner this week"). Use 'swap' when they want to change a specific day's dinner ("swap wednesday", "something else for thursday") and include the day if named. Use 'lock' to finalize ("lock it", "looks good, lock the week"). Use 'chat' for everything else, including rating dishes ("the tacos were a 5") and general questions. Call route.`,
    messages: [{ role: "user", content: text.slice(0, 500) }],
    tools: [ROUTE_TOOL],
    toolChoice: { type: "tool", name: "route" },
    maxTokens: 256,
  });
  const input = toolUses.find((t) => t.name === "route")?.input ?? {};
  const intent = (input.intent as Intent) ?? "chat";
  const day = input.day as Day | undefined;
  return { intent, day };
}
