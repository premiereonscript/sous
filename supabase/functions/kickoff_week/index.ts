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
import { proposePlan } from "../_shared/planner.ts";
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

  // A household can have more than one Telegram chat attached (e.g. a DM and
  // a group chat) — proposePlan upserts ONE meal_plan per (household_id,
  // week_of), so running it again for the same household mid-loop deletes
  // and replaces the first chat's picks: that chat is left with recipe
  // cards, a shopping list, and Swap/Lock buttons pointing at meal_plan_items
  // that no longer exist. Until every attached chat gets the plan fanned out
  // (not just the one that runs first), only kick off once per household.
  const seenHouseholds = new Set<string>();
  for (
    const c of (convos ?? []) as {
      id: string;
      household_id: string;
      telegram_chat_id: number;
    }[]
  ) {
    if (scheduled && !due.has(c.household_id)) continue; // not this household's hour
    if (seenHouseholds.has(c.household_id)) {
      console.warn(
        `kickoff: skipping conversation ${c.id} — household ${c.household_id} already kicked off this run`,
      );
      continue;
    }
    seenHouseholds.add(c.household_id);

    await db.from("messages").insert({
      conversation_id: c.id,
      direction: "out",
      text: GREETING,
    });
    await sendMessage(botToken, c.telegram_chat_id, GREETING);
    await proposePlan(c.id);
  }
}
