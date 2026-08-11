# Edge Functions — Sous

Developer reference for the four functions. For deploying your own instance,
see the repo root [`SETUP.md`](../../SETUP.md).

Model choice per call site — Haiku for intent routing, Sonnet for onboarding,
chat and planning — is overridable per deploy via `SOUS_INTENT_MODEL` /
`SOUS_CHAT_MODEL` / `SOUS_PLANNER_MODEL` (defaults in
[`.env.example`](./.env.example)).

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

Loads recent turns and the current week, then asks Sonnet for a reply as
**Sous** (voice in `_shared/persona.ts`, chosen per household from
`persona_style`). It is a small agent, not a one-shot chat: it can swap, plan
or lock a week, permanently exclude a dish, expand a recipe, record a rating,
and update household preferences. Shared core in `_shared/orchestrate.ts`, also
callable as a standalone HTTP entry. JWT verification stays on (called with the
service-role key).

## `kickoff_week` (hourly cron)

Secret-gated (`x-kickoff-secret`) entry that `pg_cron` calls **every hour**.
With `{"scheduled": true}` it kicks off only the households whose *local*
`plan_day`/`plan_hour` — interpreted in `households.timezone` — is the current
hour, so every household gets its plan at its own local time and DST needs no
special handling. A manual trigger with an empty body forces every household
immediately.

A household may have several chats (each person's DM plus a family group). The
week is generated once and fanned out to all of them, so no chat is left with
stale buttons pointing at replaced plan items. Returns `200` fast and does the
work in `EdgeRuntime.waitUntil` so pg_net's 5s timeout never trips. Deploy with
`--no-verify-jwt`.

## `send_list` (on-demand resend)

Re-posts the current shopping list or the current plan without regenerating
either. Called only by the `trigger_send_list_now()` / `trigger_send_plan_now()`
SQL helpers — the chat phrase *"send me the grocery list"* is served in-process
by the orchestrator's `send_shopping_list` tool, not by this function. Deploy
with `--no-verify-jwt`.

## `_shared`

| File | Role |
|---|---|
| `db.ts` | service-role Supabase client (bypasses RLS) |
| `anthropic.ts` | Messages API client (text + tool use) |
| `telegram.ts` | sendMessage / editMessageText / answerCallbackQuery |
| `persona.ts` | Sous voices — weissman (default), neutral, warm |
| `intent.ts` | Haiku intent classification |
| `planner.ts` | propose / swap / customize / lock + recipe cards + shopping list |
| `orchestrate.ts` | the conversational agent and its tools |
| `onboarding.ts` | first-run setup conversation + `save_setup` |
| `household.ts` | preferences read/write, prompt context, money + locale helpers |
| `diet.ts` | canonical diet keys; normalizes LLM output before it is persisted |
| `schedule.ts` | timezone validation + local weekday/hour for the kickoff |
| `env.ts` | bot token / webhook secret / allowlist |

## Local development

```bash
supabase functions serve tg_webhook --env-file supabase/functions/.env
# expose for the dev bot's webhook:
ngrok http 54321
```
Copy `.env.example` → `.env` and fill it in (gitignored).

## Tests

```bash
deno task check   # type-check every function entry point
deno task test    # unit tests for the pure logic in _shared
deno task lint    # style + lint rules
```
The SQL these functions call — portion scaling, free staples, the dietary hard
filter — is covered by pgTAP instead, in `supabase/tests/`, run with
`supabase test db` against a local stack.
