// Environment for the Sous Edge Functions.
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
    // Comma-separated Telegram IDs allowed to use this deploy's bot: each
    // person's user id and/or a group chat id. One deploy = one household, so
    // every allowed id belongs to the same household; all others are dropped
    // (SPEC §10.2).
    allowedChatIds: (Deno.env.get("TELEGRAM_ALLOWED_CHAT_IDS") ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
  };
}
