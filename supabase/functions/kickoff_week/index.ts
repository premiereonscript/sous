// kickoff_week — the Friday 6pm job (SPEC §9.3 / §9.5).
// Triggered by pg_cron via pg_net, gated by a shared secret header. For each
// household conversation: a short Sous greeting, then propose next week.
//
// Returns 200 immediately and does the (slow, LLM-bound) work in the background
// so pg_net's 5s client timeout never trips. Edge runtime keeps the worker
// alive until waitUntil settles.
//
// (Day-7 scope: greeting + propose. The full recap-last-week summary is a
// later addition; users can rate dishes any time via chat.)

import { dbClient } from "../_shared/db.ts";
import { proposePlan, sendCurrentPlan } from "../_shared/planner.ts";
import { sendMessage } from "../_shared/telegram.ts";
import { localDayHour } from "../_shared/schedule.ts";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;

const GREETING = "Fresh dinners incoming ☕ — pulling your week together, one sec.\n" +
  "(Rate last week's hits any time — just tell me, e.g. “the tacos were a 5”.)";

Deno.serve(async (req: Request): Promise<Response> => {
  const secret = req.headers.get("x-kickoff-secret");
  if (!secret || secret !== Deno.env.get("KICKOFF_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }

  // The hourly cron sends {"scheduled": true}: only kick off households whose
  // LOCAL plan_day/plan_hour is right now. Manual triggers (trigger_kickoff_now,
  // an empty body) force every household immediately.
  const body = await req.json().catch(() => ({} as Record<string, unknown>));
  const scheduled = (body as { scheduled?: unknown })?.scheduled === true;

  const work = runKickoff(scheduled).catch((e) => console.error("kickoff failed", e));
  if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(work);

  return new Response(JSON.stringify({ ok: true, scheduled }), {
    headers: { "content-type": "application/json" },
  });
});

async function runKickoff(scheduled: boolean): Promise<void> {
  const db = dbClient();
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN")!;

  // Which households are due right now (all of them for a manual/forced run).
  const due = new Set<string>();
  if (scheduled) {
    const now = new Date();
    const { data: households } = await db.from("households").select("id, timezone");
    const { data: prefs } = await db
      .from("household_preferences")
      .select("household_id, plan_day, plan_hour");
    const prefById = new Map(
      ((prefs ?? []) as { household_id: string; plan_day: string; plan_hour: number }[])
        .map((p) => [p.household_id, p]),
    );
    for (const h of (households ?? []) as { id: string; timezone: string }[]) {
      const p = prefById.get(h.id);
      const planDay = p?.plan_day ?? "fri";
      const planHour = p?.plan_hour ?? 18;
      const { day, hour } = localDayHour(h.timezone ?? "America/Los_Angeles", now);
      if (day === planDay && hour === planHour) due.add(h.id);
    }
    if (due.size === 0) return; // nothing scheduled this hour
  }

  const { data: convos } = await db
    .from("conversations")
    .select("id, household_id, telegram_chat_id")
    .order("created_at", { ascending: true });

  // Group conversations by household. A household can have more than one chat
  // (e.g. each parent's DM + a family group chat).
  type Convo = { id: string; household_id: string; telegram_chat_id: number };
  const byHousehold = new Map<string, Convo[]>();
  for (const c of (convos ?? []) as Convo[]) {
    if (scheduled && !due.has(c.household_id)) continue; // not this household's hour
    const list = byHousehold.get(c.household_id) ?? [];
    list.push(c);
    byHousehold.set(c.household_id, list);
  }

  for (const [, hhConvos] of byHousehold) {
    // Greet every chat.
    for (const c of hhConvos) {
      await db.from("messages").insert({ conversation_id: c.id, direction: "out", text: GREETING });
      await sendMessage(botToken, c.telegram_chat_id, GREETING);
    }

    // Generate the week ONCE (proposePlan upserts one meal_plan per household +
    // sends the cards/list to this chat), then fan the SAME plan out to the
    // household's other chats so none is left empty or with stale buttons.
    const [first, ...rest] = hhConvos;
    await proposePlan(first.id);
    if (rest.length === 0) continue;

    const { data: f } = await db
      .from("conversations")
      .select("active_plan_id")
      .eq("id", first.id)
      .maybeSingle();
    const planId = f?.active_plan_id as string | undefined;
    if (!planId) continue;
    for (const c of rest) {
      await db.from("conversations").update({ active_plan_id: planId }).eq("id", c.id);
      await sendCurrentPlan(c.id);
    }
  }
}
