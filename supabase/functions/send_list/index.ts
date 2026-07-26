// send_list — re-post the current plan to each household chat on demand,
// WITHOUT regenerating the week (non-destructive; the dishes don't change).
// Body {"mode":"plan"} sends the full recipe cards + shopping list; anything
// else (default) sends just the shopping list. Same shared-secret gate as
// kickoff_week; triggered by trigger_send_list_now() / trigger_send_plan_now().
// Returns 200 immediately, does the sends in the background.

import { dbClient } from "../_shared/db.ts";
import { sendCurrentPlan, sendShoppingList } from "../_shared/planner.ts";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;

Deno.serve(async (req: Request): Promise<Response> => {
  const secret = req.headers.get("x-kickoff-secret");
  if (!secret || secret !== Deno.env.get("KICKOFF_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }

  const body = await req.json().catch(() => ({} as Record<string, unknown>));
  const mode = (body as { mode?: string })?.mode === "plan" ? "plan" : "list";

  const work = runSend(mode).catch((e) => console.error("send_list failed", e));
  if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(work);

  return new Response(JSON.stringify({ ok: true, mode }), {
    headers: { "content-type": "application/json" },
  });
});

async function runSend(mode: "plan" | "list"): Promise<void> {
  const db = dbClient();
  const { data: convos } = await db
    .from("conversations")
    .select("id")
    .order("created_at", { ascending: true });

  for (const c of (convos ?? []) as { id: string }[]) {
    if (mode === "plan") await sendCurrentPlan(c.id);
    else await sendShoppingList(c.id);
  }
}
