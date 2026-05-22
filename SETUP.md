# Setup

How to deploy your own Goodbye Fresh instance. Written to be followed by a
person **or** executed by an agent (e.g. Claude Code). Most of it is automated
by [`setup.sh`](./setup.sh); the steps below are the source of truth and the
manual fallback.

> **For an agent running this:** steps 1–3 need a human (creating accounts,
> BotFather, copying keys) — ask the user for those outputs. Steps 4–9 you can
> run yourself. Never commit any secret; they belong only in Supabase secrets /
> Vault and the gitignored `supabase/.temp/`.

---

## Prerequisites (human, one-time)

1. **Supabase account** → create a new project at
   [supabase.com/dashboard](https://supabase.com/dashboard). Note the
   **Project Ref** (the `abcd...` in the URL) and the **database password** you
   set.
2. **Telegram bot** → message [@BotFather](https://t.me/BotFather), send
   `/newbot`, pick a name + username. Copy the **bot token**
   (`12345:AA...`).
3. **Anthropic API key** → [console.anthropic.com](https://console.anthropic.com)
   → API Keys. Set a monthly spend cap while you're there.
4. **Supabase CLI** → `brew install supabase/tap/supabase` (or see
   [docs](https://supabase.com/docs/guides/cli)), then `supabase login`.

Have ready: `PROJECT_REF`, the DB password, `BOT_TOKEN`, `ANTHROPIC_API_KEY`.

---

## Recommended for Claude Code: connect the Supabase MCP

If an agent is doing the setup, the [Supabase MCP server](https://supabase.com/docs/guides/getting-started/mcp)
lets it apply migrations, run SQL, and deploy Edge Functions **directly** —
no copy-pasting CLI output. (Setting secrets and the Telegram webhook still use
the CLI/curl below; the MCP doesn't manage those.)

1. Create a **personal access token**:
   [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens).
2. Copy the template and point your shell at your project:
   ```bash
   cp .mcp.json.example .mcp.json          # .mcp.json is gitignored
   export SUPABASE_PROJECT_REF=<PROJECT_REF>
   export SUPABASE_ACCESS_TOKEN=<your-PAT>
   ```
   The committed `.mcp.json.example` holds **no secret** — it reads both values
   from these env vars.
3. The template is `read_only=true` (safe default). For the one-time deploy,
   change `read_only=true` → `read_only=false` in your `.mcp.json` URL so the
   agent can `apply_migration` + `deploy_edge_function`; flip it back after.
4. Restart Claude Code in this directory and run `/mcp` — you should see
   **supabase** connected. Then ask it to follow this file.

## Automated path (CLI)

```bash
./setup.sh
```
It runs steps 4–9 below and prompts for the values from the prerequisites.
Then jump to [Verify](#verify).

---

## Manual path

All commands run from the repo root. Replace `<PLACEHOLDERS>`.

### 4. Link the project
```bash
supabase link --project-ref <PROJECT_REF>      # prompts for DB password
```

### 5. Apply the database (schema + 50-recipe catalog)
```bash
supabase db push
```
This creates every table, RLS policy, the planner/shopping SQL functions, and
seeds the recipe catalog. No `psql` needed. (There is **no** household seed —
your household is created automatically on your first message.)

### 6. Set the function secrets
Generate two random secrets, then set all four:
```bash
WEBHOOK_SECRET=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40)
KICKOFF_SECRET=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40)

supabase secrets set \
  TELEGRAM_BOT_TOKEN='<BOT_TOKEN>' \
  ANTHROPIC_API_KEY='<ANTHROPIC_API_KEY>' \
  TG_WEBHOOK_SECRET="$WEBHOOK_SECRET" \
  KICKOFF_SECRET="$KICKOFF_SECRET"
```
Keep `WEBHOOK_SECRET` and `KICKOFF_SECRET` handy for the next steps.
(`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.)

### 7. Deploy the functions
`--use-api` bundles server-side (no Docker required).
```bash
supabase functions deploy tg_webhook   --no-verify-jwt --use-api
supabase functions deploy orchestrator                 --use-api
supabase functions deploy kickoff_week --no-verify-jwt --use-api
```

### 8. Capture your Telegram chat id and allow it
The bot only responds to allow-listed ids. Easiest way to find yours:

1. Open your bot in Telegram (the `t.me/<username>` link), tap **Start**, send
   any message.
2. Read the update (works only **before** the webhook is set):
   ```bash
   curl -s "https://api.telegram.org/bot<BOT_TOKEN>/getUpdates" \
     | grep -o '"from":{"id":[0-9]*' | grep -o '[0-9]*' | head -1
   ```
3. Allow that id (comma-separate multiple people):
   ```bash
   supabase secrets set TELEGRAM_ALLOWED_CHAT_IDS='<YOUR_CHAT_ID>'
   ```

### 9. Register the webhook
```bash
curl "https://api.telegram.org/bot<BOT_TOKEN>/setWebhook" \
  --data-urlencode "url=https://<PROJECT_REF>.supabase.co/functions/v1/tg_webhook" \
  --data-urlencode "secret_token=$WEBHOOK_SECRET" \
  -d 'allowed_updates=["message","edited_message","callback_query"]'
```

---

## Verify

Message your bot:
- **"hi"** → first run kicks off **onboarding**: it asks how many people +
  kids' ages, dinners per week, monthly budget, and cuisines, then saves them.
- **"plan my week"** → proposes that many dinners with Swap/Lock buttons + a
  shopping list, tuned to your answers.
- **"the carnitas were a 5"** → it logs a rating and reacts.
- Tap **🔄 Swap** / **✅ Lock** on the cards.

Check delivery health if nothing happens:
```bash
curl -s "https://api.telegram.org/bot<BOT_TOKEN>/getWebhookInfo"
# pending_update_count should be low; last_error_message should be empty
```

---

## Optional: Friday auto-plan (cron)

The `kickoff_week_friday` cron job is already scheduled by the migrations, but
it only fires once you store two secrets in **Supabase Vault** (so no secret
lives in the repo). Run this in the dashboard **SQL Editor** (or via `psql`):

```sql
select vault.create_secret('https://<PROJECT_REF>.supabase.co', 'project_url')
  where not exists (select 1 from vault.secrets where name = 'project_url');
select vault.create_secret('<KICKOFF_SECRET>', 'kickoff_secret')
  where not exists (select 1 from vault.secrets where name = 'kickoff_secret');
```

The schedule is `0 1 * * 6` UTC ≈ **Friday 6pm Pacific (PDT)**. Edit
`supabase/migrations/20260521000400_kickoff_cron.sql` (and re-`cron.schedule`)
for your timezone.

## Optional: group chats

To use the bot in a family group (not just a DM), add it to the group and
disable privacy mode so it can read messages:
[@BotFather](https://t.me/BotFather) → `/setprivacy` → your bot → **Disable**.
Then add each member's id (or the group's negative chat id) to
`TELEGRAM_ALLOWED_CHAT_IDS`.

---

## Rotating / revoking secrets

- **Bot token:** BotFather → `/revoke`, then redo steps 6–7 + 9.
- **Anthropic key:** revoke in the console, mint a new one, redo step 6 + 7.
- **Webhook/kickoff secrets:** regenerate, redo steps 6, 9 (and the Vault SQL).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Bot silent | id not in `TELEGRAM_ALLOWED_CHAT_IDS`, or webhook not set |
| `getWebhookInfo` shows a 401/secret error | `TG_WEBHOOK_SECRET` ≠ the `secret_token` you set in step 9 |
| Replies are empty / errors in logs | `ANTHROPIC_API_KEY` unset or out of credit |
| `db push` asks for Docker | add `--use-api` is for functions; for db push, ensure you're linked (step 4) |
| Friday plan never arrives | Vault secrets not set (see optional cron section) |
