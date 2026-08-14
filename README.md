# Sous 🥄

A personal **Telegram meal-planning bot** that replaces a meal-kit
subscription — your own private sous-chef named **Sous**, who sounds however you
want them to. Once a week it proposes your dinners, lets you swap, customize, or
lock them with a tap (or just by texting), and hands back a shopping list built
for however you actually shop.

It is deliberately **not** a SaaS. There's no sign-up page. You deploy your
**own** private instance for **your** household — it's a prompt, a cron, and a
Telegram bot on top of Supabase. Total running cost is ~$5–7/month.

> Built around [`SPEC.md`](./SPEC.md) — read that for the full product thinking,
> data model, and threat model.

> ### ⚠️ Allergies: read this before you rely on it
>
> Sous filters recipes against the diets and allergies you give it, in SQL, and
> it refuses anything it can't positively classify. That makes it a **useful
> convenience, not a safety device.** It reasons over a recipe catalog, not over
> the actual food in your kitchen — it cannot see brands, substitutions,
> cross-contamination, or what a manufacturer changed last month.
>
> **Always read the actual labels.** If someone in your household has a severe
> or anaphylactic allergy, do not let this tool be the thing standing between
> them and a reaction.
>
> Two limits worth knowing concretely: when you customize a dish in chat, the
> guard blocks ingredients carrying a known allergen but cannot vouch for one
> the catalog has never seen; and diets with no allergen behind them
> (vegetarian, halal, no-pork) are enforced on the planning pool but not on that
> customize path. Both are tracked in [`ROADMAP.md`](./ROADMAP.md).

---

## What it does

Everything is a conversation — no commands, buttons optional.

- **First run:** Sous asks a few quick setup questions and plans around your
  answers: how many people + kids' ages, dinners per week, monthly grocery
  budget, cuisines you like, any dietary restrictions or allergies, and where
  you live (so the weekly plan lands at a sane local hour). Change any of them
  later just by saying so (*"we're 3 adults now"*, *"bump the budget to
  $1,300"*).
- It proposes your week as **recipe cards** — full instructions, a kid version,
  and (if you have a baby) a soft/unsalted, no-honey note.
- **Swap** a dish — tap 🔄 or text *"swap thursday for something vegetarian"*.
  It honors what you asked and keeps the week varied where the catalog allows:
  no repeated cuisines back-to-back, weeknights inside your cook-time cap. Both
  are adjustable, and both relax rather than fail when there aren't enough
  fresh options left.
- **Customize** a dish without swapping it — *"add sausage to the pesto pasta"*,
  *"make thursday gluten-free"*, *"leave off the cilantro"*. Sous rewrites that
  recipe and updates the shopping list, keeping the same dinner.
- **Exclude** for good — *"never make salmon cakes again"* permanently drops a
  dish (stronger than a low rating) and offers to replace it on the current week.
- **Rate by chatting** — *"the carnitas were a 5"* — and future plans favor
  what your household actually liked.
- **Lock** the week (tap ✅ or text *"lock it"*) to finalize the **shopping
  list**. One store by default; tell Sous you also shop a farmers market and it
  splits the list, using your own labels.
- **Ask anytime** — *"send me the grocery list"* re-sends the current list;
  *"show me the full teriyaki recipe"* expands a full card.
- **Weekly, on its own** (optional cron) — Sous proposes the next week at your
  household's local plan time (Friday 6pm by default, any timezone).

## How it works

```
Telegram ──webhook──> tg_webhook ──┐
   ▲                               │  in-process (EdgeRuntime.waitUntil)
   └───────── replies ─────────────┤
                                   ├──> orchestrate.ts ──┐  chat · rate · swap · prefs
                                   ├──> planner.ts ──────┴─> Claude (Anthropic)
                                   ▼
                           Supabase Postgres <── pg_cron (hourly) ──> kickoff_week
                                   │
                                   └── SQL triggers ──> send_list (resend list / plan)
```

`orchestrate.ts` and `planner.ts` run **inside** `tg_webhook`, not over HTTP.
The separate `orchestrator` Edge Function is a standalone entry point for the
same code, useful for debugging; nothing in the repo calls it.

- **Runtime:** TypeScript on Supabase Edge Functions (Deno)
- **Data:** Supabase Postgres (RLS, pgvector-ready)
- **LLM:** Claude — Haiku (intent routing), Sonnet (onboarding, chat, planning);
  every model id is overridable by env var
- **Schedule:** `pg_cron` + `pg_net`
- **Messaging:** Telegram Bot API

## Prerequisites

You'll create three accounts (two free, one metered) and install one CLI:

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
CONTRIBUTING.md              running it locally, good first issues, the one rule
ROADMAP.md                   what shipped, what the review caught, what's open
setup.sh                     guided one-command setup
supabase/
  config.toml                Edge Function config (verify_jwt per function)
  migrations/                schema + planner SQL + recipe catalog (158 recipes)
  tests/                     pgTAP database tests (run via `supabase test db`)
  functions/
    tg_webhook/              Telegram webhook (auth, persist, route)
    orchestrator/            conversational agent — swap, customize, exclude,
                             rate, lock, expand recipe, update preferences
    kickoff_week/            hourly cron entry point (timezone-aware kickoff)
    send_list/               on-demand shopping list / resend current plan
    _shared/                 db, anthropic, telegram, env, intent, persona,
                             household, onboarding, diet, schedule, planner,
                             orchestrate
deno.json                    tasks: check / test / fmt / lint
.github/workflows/ci.yml     CI: deno check + test, and pgTAP on a live stack
```

## Make it yours

Sous adapts to your household — most of it just by **texting the bot**, no config
files. Onboarding asks the essentials; after that, tell Sous things like:

- **Diet & allergies** — *"we're vegetarian"*, *"no pork"*, *"peanut allergy"*.
  These are a **hard filter** on recipe selection, not a polite suggestion.
  Sixteen diets are enforced structurally in SQL: vegetarian, vegan,
  pescatarian, gluten_free, dairy_free, halal, kosher, and no_pork / no_beef /
  no_poultry / no_shellfish / no_fish / no_nuts / no_soy / no_egg / no_sesame.
  Say something outside that list and Sous keeps it as a literal ingredient to
  avoid, and tells you that's what it did. That works for a named food
  (*"no duck"*); it does nothing for a diet with no single ingredient behind it
  (*"keto"*, *"low FODMAP"*) — those you'll need to manage by excluding dishes
  as they come up.
- **How you shop** — one list by default. Say *"I also shop a farmers market"*
  and Sous splits produce into its own section, labelled however you like. The
  split keys off the words *market* or *farmer*; two arbitrary store names
  (*"Costco and Trader Joe's"*) get one combined list headed with both.
- **Free staples** — *"we have chickens, skip eggs"* keeps anything you already
  have off the list. Nothing is skipped by default. Match the catalog's name for
  the ingredient (`eggs`, lowercase) — the filter compares exactly, so a near
  miss quietly does nothing.
- **Money & units** — *"budget is €900/month"*, *"use metric"*.
- **Schedule** — plan fewer/more dinners, cook longer on weeknights, or plan
  only certain days. The weekly plan arrives at **your** local time.
- **Voice** — three built-in tones: **bold** (the default — high-energy,
  opinionated, a bit theatrical), **neutral** (*"talk to me plainly"*), and
  **warm** (*"be sweeter"*). Or describe the chef you actually want and Sous
  keeps your wording: *"talk like a grumpy French chef"*, *"one line, no
  exclamation marks"*, *"more encouraging, I'm learning to cook"*. Tone only —
  no phrasing you pick can loosen a dietary rule.
- **Language** — *"responde en español"* switches replies to your language.

Deeper changes live in the repo:

- **Recipes** — the catalog is **158 dishes** across 18 cuisines, seeded by the
  `*_seed_recipes*.sql` migrations plus
  `20260812000000_seed_catalog_expansion.sql`. Add your own
  by following the same pattern — an `ingredients` row per new item, a `recipes`
  row (with `base_servings` + `dietary_tags`), and its `recipe_ingredients` —
  then `supabase db push`. Sous also creates recipe **variants** on the fly when
  you customize a dish in chat.

  **Tag what you add.** The allergy filter fails *closed*: a recipe with no
  `dietary_tags` is treated as unclassified, not as safe, so it is never offered
  to a household with any restriction. Give it the right `contains_*` tags, and
  give each new ingredient its `allergens` — the filter checks both, so a recipe
  whose tags are wrong is still caught by its ingredients.
- **Models** — override `SOUS_INTENT_MODEL` / `SOUS_CHAT_MODEL` /
  `SOUS_PLANNER_MODEL` (see `.env.example`) for cost or model choice.

## Notes & limitations

- **Single household per deploy.** By design — one deploy serves one household
  (its members can each DM the bot and share a group chat; the weekly plan fans
  out to all of them). To run it for another family, deploy another instance.
- **Cuisine coverage is uneven.** The catalog leans toward the cuisines it was
  seeded with. Every cuisine is a plain text tag, so widening it is just adding
  recipes — no schema change, no code change.
- **English-first (v1).** Replies and generated content follow the household's
  language, and money/dates are localized — but the fixed UI strings (e.g. the
  "Shopping list" header) and the starter recipe catalog are English. Full
  translation is a good contribution.
- **Diet and allergy avoidance is enforced in code**, not left to the model.
  `candidate_recipes` hard-filters the planning pool and fails closed: a recipe
  with no `dietary_tags` counts as unclassified, not safe, so a household with
  any restriction never sees it. `diet_conflict()` guards the customize path,
  the one route by which an ingredient could otherwise reach your week without
  passing that filter — but it is narrower. It blocks an added ingredient that
  carries a forbidden allergen or sits on your avoid list; a diet with no
  allergen behind it (vegetarian, halal, no-pork) is still prompt-enforced
  there, as is an ingredient the catalog has never seen. Tightening that is a
  good contribution.
- **Kid-safety is prompt-enforced.** The code-side `unsafe_for_age` block-list
  from the spec (§10.7) isn't built yet — a good first contribution.
- Costs are tiny but **real** — the Anthropic key bills per use. Set a spend cap.

## Tests

```bash
deno task check   # type-check the edge functions
deno task test    # unit tests (pure logic)
deno task lint    # style + lint rules
```

The SQL that unit tests can't reach — portion scaling, per-household free
staples, the dietary hard filter — is covered by pgTAP in `supabase/tests/`.
Those need a local stack (Docker) and the pgTAP extension, which is enabled per
database rather than by a migration, so a test framework never lands in
production:

```bash
supabase db start
psql "postgresql://postgres:postgres@localhost:54322/postgres" \
  -c 'create extension if not exists pgtap with schema extensions;'
supabase test db
```

CI runs all of it on every PR.

## Staying up to date

Your instance is yours — nothing auto-updates, and nobody can push anything to
it. When you want new recipes or fixes:

```bash
git pull
supabase db push                                          # only new migrations run
supabase functions deploy tg_webhook   --no-verify-jwt --use-api
supabase functions deploy orchestrator                 --use-api
supabase functions deploy kickoff_week --no-verify-jwt --use-api
supabase functions deploy send_list    --no-verify-jwt --use-api
```

Both steps are needed. `db push` updates the schema and recipes; the deploys
update the bot's behavior. Skipping the deploys leaves you on old code with a
new database, which looks like the update silently failed.

**Your data survives.** Migrations are additive, and every recipe seed is
guarded on title, so your preferences, ratings, exclusions, plan history and any
recipes you added yourself are left alone. Deploying is safe mid-week; an
in-progress plan keeps working.

If you forked rather than cloned, point at upstream once:

```bash
git remote add upstream https://github.com/premiereonscript/sous.git
git pull upstream main
```

**Check the account first if a deploy 403s.** `db push` authenticates against the
database, but `functions deploy` authenticates against your Supabase *account* —
so if you're logged into a different one, the schema updates and the code
doesn't. `supabase projects list` should show the project you're deploying to.

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for running the stack locally and a
list of good first issues, and [`ROADMAP.md`](./ROADMAP.md) for what's still
open. One rule worth reading before touching the SQL: the dietary filter fails
closed, and changes to it need a test proving the unsafe recipe is excluded.

## License

MIT — see [`LICENSE`](./LICENSE).
