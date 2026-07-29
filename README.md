# Sous 🥄

A personal **Telegram meal-planning bot** that replaces HelloFresh for one
family — your own private sous-chef named **Sous**, a chef with a
Joshua-Weissman streak. Friday evening it proposes your weeknight dinners, lets
you swap, customize, or lock them with a tap (or just by texting), and hands
back a shopping list split between the farmers market and the grocery store.

It is deliberately **not** a SaaS. There's no sign-up page. You deploy your
**own** private instance for **your** household — it's a prompt, a cron, and a
Telegram bot on top of Supabase. Total running cost is ~$5–7/month.

> Built around [`SPEC.md`](./SPEC.md) — read that for the full product thinking,
> data model, and threat model.

---

## What it does

Everything is a conversation — no commands, buttons optional.

- **First run:** Sous asks a few quick setup questions — how many people +
  kids' ages, dinners per week, monthly grocery budget, and the cuisines you
  like — and plans around your answers. Change any of them later just by saying
  so (*"we're 3 adults now"*, *"bump the budget to $1,300"*).
- It proposes your week as **recipe cards** — full instructions, a kid version,
  and (if you have a baby) a soft/unsalted, no-honey note.
- **Swap** a dish — tap 🔄 or text *"swap thursday for something vegetarian"*.
  It honors what you asked and keeps the week valid (no repeated cuisines
  back-to-back, weeknights ≤45 min).
- **Customize** a dish without swapping it — *"add sausage to the pesto pasta"*,
  *"make thursday gluten-free"*, *"leave off the cilantro"*. Sous rewrites that
  recipe and updates the shopping list, keeping the same dinner.
- **Exclude** for good — *"never make salmon cakes again"* permanently drops a
  dish (stronger than a low rating) and offers to replace it on the current week.
- **Rate by chatting** — *"the carnitas were a 5"* — and future plans favor
  what your household actually liked.
- **Lock** the week — tap ✅ or text *"lock it"* — to finalize the **shopping
  list**, split into 🧺 Farmers Market / 🏬 Grocery (eggs skipped — you have
  chickens).
- **Ask anytime** — *"send me the grocery list"* re-sends the current list;
  *"show me the full teriyaki recipe"* expands a full card.
- **Friday 6pm** (optional cron), Sous proactively proposes the next week.

## How it works

```
Telegram ─webhook─> tg_webhook ─> orchestrator ─┐ chat · rate · swap · customize ┐
   ▲                    │                        │ exclude · lock · expand · prefs │ Claude
   └───── replies ──────┤        └──> planner (propose / swap / customize / list) ┘ (Anthropic)
                        │
                        ▼
                Supabase Postgres ◄─ pg_cron (Fri 6pm) ──> kickoff_week
                        │
                        └─ triggers ──> send_list  (on-demand list / resend plan)
```

- **Runtime:** TypeScript on Supabase Edge Functions (Deno)
- **Data:** Supabase Postgres (RLS, pgvector-ready)
- **LLM:** Claude — Haiku (intent), Sonnet (planning/chat), Opus (fallback)
- **Schedule:** `pg_cron` + `pg_net`
- **Messaging:** Telegram Bot API

## Prerequisites

You'll create three free accounts and install one CLI:

| Need | Where | Cost |
|---|---|---|
| Supabase account + project | [supabase.com](https://supabase.com) | free tier |
| Telegram bot token | [@BotFather](https://t.me/BotFather) → `/newbot` | free |
| Anthropic API key | [console.anthropic.com](https://console.anthropic.com) | ~$5–7/mo usage |
| Supabase CLI | `brew install supabase/tap/supabase` | — |

## Set it up

You have three paths — pick one:

### 1. Let Claude Code do it for you (easiest)
Open this repo in [Claude Code](https://claude.com/claude-code) and say:

> *Set up Sous for me by following SETUP.md.*

It walks you through the human-only bits (creating the bot, pasting your keys)
and runs everything else itself. Even smoother: connect the **Supabase MCP**
first (SETUP.md → "Recommended for Claude Code") so the agent can apply
migrations and deploy functions directly.

### 2. One command
```bash
./setup.sh
```
Interactive — it links your Supabase project, runs migrations + the recipe
catalog, sets secrets, deploys the functions, captures your Telegram chat id,
and registers the webhook. You just paste your bot token, Anthropic key, and
send the bot one message.

### 3. By hand
Follow [`SETUP.md`](./SETUP.md) step by step. Same steps the script runs.

When you're done, message your bot **"hi"** — it'll walk you through a quick
setup (household, meals/week, budget, cuisines, and any diet/allergies), then
say **"plan my week."**

## Project layout

```
SPEC.md                      product spec, data model, threat model
SETUP.md                     step-by-step setup (human- and agent-followable)
setup.sh                     guided one-command setup
supabase/
  config.toml                Edge Function config (verify_jwt per function)
  migrations/                schema + planner SQL + recipe catalog (58 recipes)
  tests/                     pgTAP database tests (run via `supabase test db`)
  functions/
    tg_webhook/              Telegram webhook (auth, persist, route)
    orchestrator/            conversational agent — swap, customize, exclude,
                             rate, lock, expand recipe, update preferences
    kickoff_week/            hourly cron entry point (timezone-aware kickoff)
    send_list/               on-demand shopping list / resend current plan
    _shared/                 db, anthropic, telegram, planner, intent,
                             persona, household, onboarding, schedule
deno.json                    tasks: check / test / fmt / lint
.github/workflows/ci.yml     CI: deno check + test, and pgTAP on a live stack
```

## Make it yours

Sous adapts to your household — most of it just by **texting the bot**, no config
files. Onboarding asks the essentials; after that, tell Sous things like:

- **Diet & allergies** — *"we're vegetarian"*, *"no pork"*, *"peanut allergy"*.
  These are a **hard filter** on recipe selection, not a polite suggestion.
- **How you shop** — *"I just use one store"* (the default: a single grocery
  list) or *"I also shop a farmers market"* (splits the list). Labels are yours
  (*"call it Costco"*).
- **Free staples** — *"we have chickens, skip eggs"* keeps anything you already
  have off the list. Nothing is skipped by default.
- **Money & units** — *"budget is €900/month"*, *"use metric"*.
- **Schedule** — plan fewer/more dinners, cook longer on weeknights, or plan
  only certain days. The weekly kick-off fires at **your** local time.
- **Voice** — *"talk to me plainly"* (neutral) / *"be sweeter"* (warm) / the
  default high-energy chef.
- **Language** — *"responde en español"* switches replies to your language.

Deeper changes live in the repo:

- **Recipes** — the catalog is **58 dishes** in
  `supabase/migrations/*_seed_recipes*.sql` (+ plant-based mains). Add your own
  by following the same pattern — an `ingredients` row per new item, a `recipes`
  row (with `base_servings` + `dietary_tags`), and its `recipe_ingredients` —
  then `supabase db push`. Sous also creates recipe **variants** on the fly when
  you customize a dish in chat.
- **Models** — override `SOUS_INTENT_MODEL` / `SOUS_CHAT_MODEL` /
  `SOUS_PLANNER_MODEL` (see `.env.example`) for cost or model choice.

## Notes & limitations

- **Single household per deploy.** By design — one deploy serves one household
  (its members can each DM the bot and share a group chat; the weekly plan fans
  out to all of them). To run it for another family, deploy another instance.
- **English-first (v1).** Replies and generated content follow the household's
  language, and money/dates are localized — but the fixed UI strings (e.g. the
  "Shopping list" header) and the starter recipe catalog are English. Full
  translation is a good contribution.
- **Kid-safety is prompt-enforced.** The code-side `unsafe_for_age` block-list
  from the spec (§10.7) isn't built yet — a good first contribution. (Dietary
  and allergy avoidance *is* enforced in code, in `candidate_recipes`.)
- Costs are tiny but **real** — the Anthropic key bills per use. Set a spend cap.

## Tests

```bash
deno task check   # type-check the edge functions
deno task test    # unit tests (pure logic)
supabase test db  # pgTAP database tests (needs a local Supabase / Docker)
```
CI runs all three on every PR.

## License

MIT — see [`LICENSE`](./LICENSE).
