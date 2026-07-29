# Edge Functions — Sous

Developer reference for the three functions. For deploying your own instance,
see the repo root [`SETUP.md`](../../SETUP.md).

## `tg_webhook` (Telegram entry point)

Verifies the `X-Telegram-Bot-Api-Secret-Token` header and a chat allowlist,
self-provisions the household + sender on first contact, persists the inbound
message to `messages` (dedup on `telegram_update_id`), then routes it and
returns `200` immediately (work runs in `EdgeRuntime.waitUntil`). Unknown
senders and bad secrets get a silent `200` (no oracle, SPEC §10.2 / §10.4).

Routing: `/plan` is a fast-path; otherwise `_shared/intent.ts` (Haiku) classifies
into plan / swap / lock / chat. `callback_query` taps (🔄 Swap, ✅ Lock) are
handled here too. Deploy with `--no-verify-jwt`.

## `orchestrator` (conversational reply)

Loads recent turns, asks Sonnet (`claude-sonnet-4-6`) for a reply as **Sous**
(persona in `_shared/persona.ts`), with the `rate_meal` tool so chatted ratings
get recorded. Shared core in `_shared/orchestrate.ts`, also callable as a
standalone HTTP entry. JWT verification stays on (called with the service-role
key).

## `kickoff_week` (Friday cron)

Secret-gated (`x-kickoff-secret`) entry the `pg_cron` job calls each Friday.
Sends a greeting and proposes the week per conversation. Returns `200` fast and
does the work in `EdgeRuntime.waitUntil` so pg_net's 5s timeout never trips.
Deploy with `--no-verify-jwt`.

## `_shared`

| File | Role |
|---|---|
| `db.ts` | service-role Supabase client (bypasses RLS) |
| `anthropic.ts` | Messages API client (text + tool use) |
| `telegram.ts` | sendMessage / editMessageText / answerCallbackQuery |
| `persona.ts` | Sous voice (Joshua-Weissman-flavored) |
| `intent.ts` | Haiku intent classification |
| `planner.ts` | propose / swap / lock + recipe cards + shopping list |
| `orchestrate.ts` | conversational reply + rate_meal |
| `env.ts` | bot token / webhook secret / allowlist |

## Local development

```bash
supabase functions serve tg_webhook --env-file supabase/functions/.env
# expose for the dev bot's webhook:
ngrok http 54321
```
Copy `.env.example` → `.env` and fill it in (gitignored).
