// tg_webhook — Telegram webhook for Goodbye Fresh (SPEC §9.3 messaging adapter).
//
// Verify the webhook secret + chat allowlist, persist the inbound message
// (dedup on telegram_update_id, SPEC §9.6), then hand off to the orchestrator
// which generates and sends the reply. Always returns a fast 200.

import { getEnv } from "../_shared/env.ts";
import { dbClient } from "../_shared/db.ts";
import { runOrchestrator } from "../_shared/orchestrate.ts";
import {
  lockActivePlan,
  lockPlan,
  proposePlan,
  swapByDay,
  swapMeal,
} from "../_shared/planner.ts";
import { classifyIntent } from "../_shared/intent.ts";
import { answerCallbackQuery } from "../_shared/telegram.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

// Supabase Edge runtime keeps the worker alive until waitUntil's promise settles.
declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;

const env = getEnv();

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return ok();

  // 1. Webhook secret (SPEC §10.4). Mismatch -> silent 200, no oracle.
  const secret = req.headers.get("x-telegram-bot-api-secret-token");
  if (!env.webhookSecret || secret !== env.webhookSecret) return ok();

  let update: TelegramUpdate;
  try {
    update = await req.json();
  } catch {
    return ok();
  }

  // Inline-button taps (🔄 Swap / ✅ Lock).
  const cb = update.callback_query;
  if (cb) {
    const cbChatId = cb.message?.chat?.id;
    const cbIds = [cbChatId, cb.from?.id]
      .filter((v): v is number => typeof v === "number")
      .map(String);
    if (!cbChatId || !cbIds.some((id) => env.allowedChatIds.includes(id))) {
      return ok();
    }
    await answerCallbackQuery(env.botToken, cb.id); // stop the spinner fast

    const db = dbClient();
    const conversationId = await resolveConversation(db, cbChatId);
    const data = cb.data ?? "";
    const msgId = cb.message?.message_id ?? 0;
    if (conversationId) {
      let work: Promise<unknown> | null = null;
      if (data.startsWith("s:")) {
        work = swapMeal(conversationId, data.slice(2), msgId);
      } else if (data.startsWith("l:")) {
        work = lockPlan(conversationId, data.slice(2));
      }
      if (work) {
        const w = work.catch((e) => console.error("callback work failed", e));
        if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(w);
        else await w;
      }
    }
    return ok();
  }

  const msg = update.message ?? update.edited_message;
  const chatId = msg?.chat?.id;
  const fromId = msg?.from?.id;
  const fromName = msg?.from?.first_name;
  const text = msg?.text ?? "";

  // 2. Allowlist (SPEC §10.2): pass if the chat or the sender is known.
  const ids = [chatId, fromId]
    .filter((v): v is number => typeof v === "number")
    .map(String);
  if (!chatId || !ids.some((id) => env.allowedChatIds.includes(id))) return ok();
  if (!text) return ok();

  const db = dbClient();
  // First allowed message self-provisions the household + the sender's user
  // row, so a new deployer never has to hand-edit SQL.
  const conversationId = await resolveConversation(db, chatId);
  if (!conversationId) return ok();

  // 3. Record inbound, deduping on telegram_update_id (Telegram retries on non-2xx).
  const senderUserId = await ensureUser(db, fromId, fromName);
  const { error } = await db.from("messages").insert({
    conversation_id: conversationId,
    direction: "in",
    sender_user_id: senderUserId,
    text,
    telegram_update_id: update.update_id ?? null,
  });
  if (error) {
    if (error.code === "23505") return ok(); // duplicate delivery
    console.error("record inbound failed", error);
  }

  // 4. Route. `/plan` is a fast-path; otherwise classify intent with Haiku.
  //    plan/swap/lock get dispatched directly; everything else (chat, ratings)
  //    goes to the conversational orchestrator. Run in the background so we
  //    return 200 fast (Telegram retries on slow/non-2xx responses).
  const work = routeMessage(conversationId, text.trim())
    .catch((e) => console.error("background work failed", e));
  if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(work);
  else await work;

  return ok();
});

// Dispatch a text message: explicit /plan, else Haiku-classified intent.
async function routeMessage(conversationId: string, text: string): Promise<void> {
  if (/^\/plan\b/i.test(text)) return proposePlan(conversationId);

  const { intent, day } = await classifyIntent(text);
  if (intent === "plan") return proposePlan(conversationId);
  if (intent === "lock") return lockActivePlan(conversationId);
  if (intent === "swap" && day) return swapByDay(conversationId, day);
  // chat, ratings, or an under-specified swap -> conversational orchestrator.
  await runOrchestrator(conversationId);
}

async function resolveConversation(
  db: SupabaseClient,
  chatId: number,
): Promise<string | null> {
  const { data } = await db
    .from("conversations")
    .select("id")
    .eq("telegram_chat_id", chatId)
    .maybeSingle();
  if (data) return data.id;

  // Attach to the household, creating it on the very first message.
  const householdId = await ensureHousehold(db);
  const { data: created } = await db
    .from("conversations")
    .insert({ household_id: householdId, telegram_chat_id: chatId, state: "idle" })
    .select("id")
    .single();
  return created?.id ?? null;
}

// The single household, created on first contact (SPEC §5 — one household, v1).
async function ensureHousehold(db: SupabaseClient): Promise<string> {
  const { data } = await db
    .from("households")
    .select("id")
    .order("created_at")
    .limit(1)
    .maybeSingle();
  if (data) return data.id;
  const { data: created } = await db
    .from("households")
    .insert({ name: "My household" })
    .select("id")
    .single();
  return created!.id;
}

// Upsert the sender as an adult user (rater for ratings). Self-provisions so a
// new deployer never seeds users by hand.
async function ensureUser(
  db: SupabaseClient,
  fromId: number | undefined,
  fromName: string | undefined,
): Promise<string | null> {
  if (!fromId) return null;
  const { data } = await db
    .from("users")
    .select("id")
    .eq("telegram_id", fromId)
    .maybeSingle();
  if (data) return data.id;

  const householdId = await ensureHousehold(db);
  const { data: created, error } = await db
    .from("users")
    .insert({
      household_id: householdId,
      display_name: fromName ?? "Someone",
      role: "adult",
      telegram_id: fromId,
    })
    .select("id")
    .single();
  if (error) {
    console.error("ensureUser failed", error);
    return null;
  }
  return created?.id ?? null;
}

function ok(): Response {
  return new Response("ok", { status: 200 });
}

interface TelegramUpdate {
  update_id?: number;
  message?: TelegramMessage;
  edited_message?: TelegramMessage;
  callback_query?: {
    id: string;
    from?: { id: number };
    message?: { chat?: { id: number }; message_id?: number };
    data?: string;
  };
}
interface TelegramMessage {
  chat?: { id: number };
  from?: { id: number; first_name?: string };
  text?: string;
}
