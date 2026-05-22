// Environment for the Goodbye Fresh Edge Functions.
// Secrets are set via `supabase secrets set ...` (SPEC §9.7) — never committed.

export interface Env {
  botToken: string;
  webhookSecret: string;
  allowedChatIds: string[];
}

export function getEnv(): Env {
  return {
    botToken: Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "",
    webhookSecret: Deno.env.get("TG_WEBHOOK_SECRET") ?? "",
    // Comma-separated Telegram IDs: the two spouses' user IDs and/or the group
    // chat id. SPEC §10.2 — exactly the known household, everything else dropped.
    allowedChatIds: (Deno.env.get("TELEGRAM_ALLOWED_CHAT_IDS") ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
  };
}
