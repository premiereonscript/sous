#!/usr/bin/env bash
# Sous — guided setup. Deploys your own private instance.
# See SETUP.md for what each step does and the manual fallback.
set -euo pipefail

say()  { printf '\n\033[1;36m== %s\033[0m\n' "$1"; }
ask()  { local p="$1" v; read -r -p "$p: " v; printf '%s' "$v"; }
asks() { local p="$1" v; read -r -s -p "$p: " v; echo >&2; printf '%s' "$v"; }
rand() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40; }

cd "$(dirname "$0")"
mkdir -p supabase/.temp

command -v supabase >/dev/null || {
  echo "Supabase CLI not found. Install: brew install supabase/tap/supabase"; exit 1; }
supabase projects list >/dev/null 2>&1 || {
  echo "Not logged in. Run: supabase login"; exit 1; }

say "Sous setup"
echo "Have ready: Supabase project ref + DB password, Telegram bot token (BotFather),"
echo "and an Anthropic API key. (Create the Supabase project + bot first — see SETUP.md.)"

PROJECT_REF=$(ask "Supabase project ref")
DB_PASSWORD=$(asks "Supabase DB password")
BOT_TOKEN=$(asks "Telegram bot token")
ANTHROPIC_KEY=$(asks "Anthropic API key")
WEBHOOK_SECRET=$(rand)
KICKOFF_SECRET=$(rand)
printf '%s' "$WEBHOOK_SECRET" > supabase/.temp/.webhook-secret
printf '%s' "$KICKOFF_SECRET" > supabase/.temp/.kickoff-secret

say "Linking project"
supabase link --project-ref "$PROJECT_REF" --password "$DB_PASSWORD"

say "Applying database (schema + 58-recipe catalog)"
echo "y" | SUPABASE_DB_PASSWORD="$DB_PASSWORD" supabase db push

say "Setting function secrets"
supabase secrets set \
  TELEGRAM_BOT_TOKEN="$BOT_TOKEN" \
  ANTHROPIC_API_KEY="$ANTHROPIC_KEY" \
  TG_WEBHOOK_SECRET="$WEBHOOK_SECRET" \
  KICKOFF_SECRET="$KICKOFF_SECRET"

say "Deploying functions (no Docker; --use-api)"
supabase functions deploy tg_webhook   --no-verify-jwt --use-api
supabase functions deploy orchestrator                 --use-api
supabase functions deploy kickoff_week --no-verify-jwt --use-api
supabase functions deploy send_list    --no-verify-jwt --use-api

say "Finding your Telegram chat id"
echo "Open your bot in Telegram, tap Start, and send it any message."
read -r -p "Press Enter once you've sent a message... " _
CHAT_ID=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates" \
  | grep -o '"from":{"id":[0-9]*' | grep -o '[0-9]*' | head -1 || true)
if [ -z "${CHAT_ID:-}" ]; then
  echo "Couldn't read an update automatically."
  CHAT_ID=$(ask "Enter your Telegram numeric id manually")
fi
echo "Using chat id: $CHAT_ID"
supabase secrets set TELEGRAM_ALLOWED_CHAT_IDS="$CHAT_ID"

say "Registering the webhook"
curl -s "https://api.telegram.org/bot${BOT_TOKEN}/setWebhook" \
  --data-urlencode "url=https://${PROJECT_REF}.supabase.co/functions/v1/tg_webhook" \
  --data-urlencode "secret_token=${WEBHOOK_SECRET}" \
  -d 'allowed_updates=["message","edited_message","callback_query"]'
echo

say "Done 🥄"
echo "Message your bot \"plan the week\" to try it."
echo
echo "Optional — enable the Friday auto-plan: run this in the Supabase SQL Editor:"
echo "  select vault.create_secret('https://${PROJECT_REF}.supabase.co', 'project_url')"
echo "    where not exists (select 1 from vault.secrets where name='project_url');"
echo "  select vault.create_secret('${KICKOFF_SECRET}', 'kickoff_secret')"
echo "    where not exists (select 1 from vault.secrets where name='kickoff_secret');"
