// send_list — post the current plan's shopping list to each household chat on
// demand, WITHOUT regenerating the week (non-destructive). Same shared-secret
// gate as kickoff_week; triggered by trigger_send_list_now() or any caller with
// the kickoff secret. Returns 200 immediately, does the sends in the background.

import { dbClient } from "../_shared/db.ts";
import { sendShoppingList } from "../_shared/planner.ts";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;

Deno.serve((req: Request): Response => {
  const secret = req.headers.get("x-kickoff-secret");
  if (!secret || secret !== Deno.env.get("KICKOFF_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }

  const work = runSendList().catch((e) => console.error("send_list failed", e));
  if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(work);

  return new Response(JSON.stringify({ ok: true }), {
    headers: { "content-type": "application/json" },
  });
});

async function runSendList(): Promise<void> {
  const db = dbClient();
  const { data: convos } = await db
    .from("conversations")
    .select("id")
    .order("created_at", { ascending: true });

  for (const c of (convos ?? []) as { id: string }[]) {
    await sendShoppingList(c.id);
  }
}
