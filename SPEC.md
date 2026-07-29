# Sous — Product Spec

A personal Telegram-bot meal planner that replaces HelloFresh for one family.
Friday evening, the bot opens a thread, gathers feedback on last week,
proposes five dinners (Mon–Fri), iterates, and hands back a shopping list
split between the farmers market and the grocery store — ready for the
Saturday market run.

---

## Council

This spec was drafted by a council of agents, orchestrated:

- **Product Manager** — scope, JTBD, MVP cuts, success metrics
- **Staff Engineer** — architecture, data model, LLM integration, build order
- **UX Designer** — conversation design, recipe card anatomy, microcopy
- **Security Analyst** — threat model, auth, secrets, prompt-injection defense
- **Hacker Entrepreneur** — ship-fast discipline, skip list, V2 trap warnings

The Hacker Entrepreneur gets the first and last word, on purpose.

---

## 0. The Pitch (write this on a sticky note)

> *"A Telegram bot that texts my wife on Friday evening, plans next week's
> five dinners around what our family actually liked last week, and hands me
> a shopping list split between the farmers market and the grocery store —
> so we get the HelloFresh feeling without the HelloFresh price, packaging,
> or sad chicken."*

**This is a prompt + a cron + a Telegram bot.** It is not an app, a platform,
or a startup. One household, two users, one job: make weekly meal planning
15 minutes instead of 45.

If anything in this spec doesn't directly serve that sentence, it's out.

---

## 1. Confirmed Constraints

Answers locked in by the requester. The rest of the spec is calibrated to
these — anything earlier that conflicts is superseded here.

| # | Constraint | Value |
|---|---|---|
| 1 | Dietary restrictions | None — go wild |
| 2 | Messenger | **Telegram** |
| 3 | Meals planned per week | **5 dinners only** (Mon–Fri); weekends DIY |
| 4 | Weeknight (Mon–Thu) cook-time cap | **45 minutes** active time |
| 5 | Kids in household | **A 2½-year-old + a 9-month-old** |
| 6 | Weekly budget cap | **~$250/wk** (farmers market + grocery combined) |
| 7 | Weekly ping timing | **Friday evening** (so the Saturday market trip is pre-mapped) |

## 2. Product Vision

Replace HelloFresh for one family with a smarter, cheaper, toddler-aware
weekly meal plan that respects how they actually shop: farmers market on
Saturday, grocery pickup mid-week, eggs from the backyard. The product runs
the Friday-evening planning conversation — it learns what hit, proposes
next week's five dinners, and hands back a split shopping list ready for
Saturday's market run — so meal planning stops being a chore one spouse
silently absorbs. Creative Mexican / Asian / Italian-leaning recipes,
ingredient overlap for cost, and adult-meal-with-toddler-variant by
default. Single shared source of truth for both spouses in a chat thread
they're already in.

---

## 3. Personas

**Primary — Requester (planner-in-chief).** Drives setup, owns the taste
profile, comfortable in chat tools. Adventurous palate, high spice
tolerance, wants creative recipes that don't feel like weeknight survival
cooking. Pain: HelloFresh got worse and he's the one who has to fix it.

**Co-user — Wife.** Equal authority in the shared thread; her vetoes and
approvals count the same as his. Probably more sensitive to cook time on
weeknights and to what the toddlers will actually eat. Needs to swap a
meal without "going into an app."

**Secondary consumers — a 2½-year-old + a 9-month-old.** The toddler: low
spice tolerance, texture-sensitive, repetition-tolerant; needs meat / protein
pulled before chili and aromatics hit the pan, and choking shapes
quartered. The baby (9mo): eats soft, mashed, **unsalted** portions pulled
before salt/spice/acid, **no honey** (under 12mo), strict choking-hazard
rules. Whole grapes, whole nuts, popcorn, raw hard veg cubes are blocked in
code (see §10.7). They don't use the product; they're constraints on it.

---

## 4. Jobs To Be Done

- When it's Friday evening, I want the system to start the planning
  conversation, so the Saturday market trip is pre-mapped and I'm not the
  one who has to remember.
- When last week's meals are still fresh in our memory, I want to capture
  what worked and what didn't, so next week gets better automatically.
- When I see next week's proposal, I want to swap or veto a meal in one
  message, so planning takes minutes not an hour.
- When the plan is locked, I want a shopping list split by where I'll buy
  each item, so Saturday market and mid-week pickup are both one pass.
- When a meal is spicy or aromatic, I want a toddler-friendly variant
  baked into the recipe, so I'm not cooking two dinners from scratch.
- When we've had a cuisine recently, I want the system to avoid repeating
  it, so the week feels varied.
- When my tastes evolve, I want to update preferences without re-onboarding,
  so the plan keeps learning.
- When my wife edits the plan, I want to see her edits in the same thread,
  so we never disagree about what we're eating Thursday.

---

## 5. MVP Scope (v1)

- **Friday 6pm scheduled ping** into one shared Telegram chat.
- Recap prompt: "How was last week?" with structured tag picker + optional
  free text, per meal.
- Proposal of **5 dinners (Mon–Fri)** as recipe cards: title, cuisine,
  est. cook time, ingredients, toddler variant note. Weekends are DIY /
  leftovers / market-fresh — bot does not plan Sat or Sun.
- Inline edit loop in chat: swap meal N, regenerate one slot, lock plan.
- Shopping list generation, split into **Farmers Market** and **Grocery**
  sections, with eggs auto-excluded.
- Taste profile: liked / disliked ingredients, cuisine weights, spice
  ceiling for the 1–3y toddlers, 45-min weeknight cook-time cap.
  Editable via `/preferences` or just by telling the bot in chat.
- Recipe history log so the generator can dedupe.
- Both spouses are first-class in the thread — no "owner" account semantics;
  most recent action wins, conflicts surfaced (see §7).

### Messenger: Telegram

Confirmed. Bot API is dramatically simpler than Slack, native inline
keyboards for tag pickers, mobile-first, free.

---

## 6. Explicitly Out of Scope for v1

- Breakfast planning (handled in-house with pancakes, waffles, backyard eggs)
- Vons / any grocer pickup ordering integration
- Multi-household / multi-tenant support
- Nutrition tracking, macros, calorie counting
- Payment, billing, subscriptions
- Recipe authoring UI
- Native mobile app
- Web dashboard
- Pantry inventory tracking beyond declared staples
- Cost estimation per meal
- AI-generated food photos
- Voice messages

---

## 7. UX & Conversation Design

### 7.1 Interaction Principles

- **Chat-native, tap-first.** Inline buttons for 90% of decisions; free text
  is always accepted but never required.
- **Two-person aware, last-write-wins with receipts.** Either spouse can
  respond. When they conflict, the bot surfaces it ("Sam approved, Alex
  swapped — going with the swap, holler if wrong").
- **Resumable, not nagging.** One ping Friday 6pm. One soft nudge Saturday
  9am if the plan's still draft. Then it waits.
- **Show the why.** Every proposal includes a one-line rationale ("you
  liked this in March; uses the cilantro from market").
- **Toddler-first, not toddler-afterthought.** The kid variant is part of
  the card, not a footnote.

### 7.2 The Friday Conversation — Scripted Walkthrough

> **Sous** — *Fri 6:02 PM*
>
> Morning Alex & Sam ☕ Ready to plan the week?
>
> Quick recap first — how'd last week's menu land?
>
> [Start recap]  [Skip to planning]  [We're traveling]

> **Sous**
>
> *Mon — Chicken tinga tacos* 🌮 — how'd it go?
>
> [👍]  [👎]  [😴 leftovers]  [👶 kids loved]  [🌶️ too spicy]

> **Alex**: 👶 kids loved
>
> **Sam**: 🌶️ too spicy

> **Sous**
>
> Noted — tinga stays in rotation, dialing the heat down a notch next
> time. On to *Tue — miso salmon bowls*...

*(repeats per meal)*

> **Sous**
>
> Got it. Here's the proposal for **Mon May 25 – Fri May 29**. Tap any card
> to swap or edit.
>
> ━━━━━━━━━━━━━━━━━━━
> 🌮 *Mon · Carnitas Bowls*
> *Mexican · 35 min · serves 4 + toddler*
>
> Slow-cooked pork shoulder, lime rice, black beans, pickled onion, cotija.
>
> *Why:* Sam asked for more pork in March; uses oranges from market.
>
> 👶 *Toddler:* pull a portion of pork + rice before the lime-chili finish.
>
> 🥚 Pantry: eggs ✓
>
> [✅ Approve]  [🔄 Swap]  [✏️ Tweak]  [👀 Full recipe]
> ━━━━━━━━━━━━━━━━━━━

*(four more cards, same format)*

> **Sam**: 🔄 Swap on Wednesday

> **Sous**
>
> Swapping *Wed — Thai basil chicken*. Same vibe or different?
>
> [🌶️ Same vibe, different dish]  [🍝 Italian instead]  [🌮 Mexican instead]  [🎲 Surprise me]  [✏️ Tell me what you want]

> **Sam**: 🍝 Italian instead

> **Sous**
>
> 🍝 *Wed · Cacio e Pepe with Blistered Tomatoes*
> *Italian · 25 min · serves 4 + toddler*
>
> *Why:* fast weeknight, market tomatoes are peaking.
>
> 👶 *Toddler:* plain buttered pasta + tomatoes on the side.
>
> [✅ Take it]  [🔄 Try another]  [👀 Full recipe]

> **Alex**: ✅ Take it

> **Sous**
>
> Locked in. One more look?
>
> *Mon* Carnitas Bowls
> *Tue* Miso Salmon Bowls
> *Wed* Cacio e Pepe ← *new*
> *Thu* Chicken Larb Lettuce Cups
> *Fri* Sheet-Pan Sausage & Peppers
>
> *Sat & Sun:* DIY — leftovers, market-fresh, or eggs from the coop 🍳
>
> [✅ Lock the week]  [🔄 One more change]

> **Alex**: ✅ Lock the week

> **Sous**
>
> Locked. Shopping list incoming 🛒
>
> ━━━━━━━━━━━━━━━━━━━
> 🧺 *FARMERS MARKET*
>
> *Produce*
> ⬜ Cilantro — 2 bunches
> ⬜ Limes — 8
> ⬜ Oranges — 4
> ⬜ Tomatoes — 1.5 lb
> ⬜ Thai basil — 1 bunch
> ⬜ Romaine hearts — 2
>
> *Protein*
> ⬜ Pork shoulder — 3 lb
>
> ━━━━━━━━━━━━━━━━━━━
> 🏬 *GROCERY*
>
> *Pantry*
> ⬜ Black beans — 2 cans
> ⬜ Cotija — 4 oz
> ⬜ Pecorino — 4 oz
> ⬜ Bucatini — 1 lb
>
> *Refrigerated*
> ⬜ Salmon — 1.25 lb
> ⬜ Italian sausage — 1 lb
> ⬜ Ground chicken — 1 lb
>
> 🥚 *Skipped (you have it):* eggs
>
> [✓ Mark items]  [📄 Printable]  [🛒 Send to Vons *(v2)*]
> ━━━━━━━━━━━━━━━━━━━

### 7.3 Recipe Card Anatomy

Every card, every time, in this order:

1. **Cuisine emoji + Day + Title** — bold title.
2. **Meta line** — *cuisine · cook time · serves N + toddler*.
3. **One-sentence description** — ingredients + style, no marketing voice.
4. **Why line** — rationale tied to feedback, season, or pantry.
5. **Toddler variant** — 👶 prefix, action-first ("pull a portion
   before...").
6. **Pantry callout** — 🥚 or 🐔 line listing assumed-available items.
7. **Action row** — `[✅ Approve] [🔄 Swap] [✏️ Tweak] [👀 Full recipe]`.

Collapsed by default = everything above. Expanded ("Full recipe") = full
ingredient list with quantities, numbered steps with the toddler-pull step
bolded inline. Never bury the toddler variant in the expanded view — it's
load-bearing.

### 7.4 Voice + Tone — meet "Sous"

Sous is the friend who went to culinary school, has a toddler, and texts
in lowercase but knows when to use a capital. Warm, competent, mildly
opinionated. Knows your kitchen. Doesn't apologize, doesn't gush, doesn't
say "Great choice!"

- **Bad:** "Great selection! I've curated a wonderful Italian-inspired
  pasta dish that I think you'll absolutely love!"
- **Good:** "Cacio e pepe — 25 min, market tomatoes are peaking. Take it?"
- **The fix:** lead with the dish, give one real reason, end with a
  question. No adjectives doing emotional labor.

### 7.5 Handling Edits + Ambiguity

**Day reference is unambiguous → just do it.**
> Sam: "swap Wednesday"
> Sous: *Swapping Wed — Thai basil chicken. Same vibe or different?*

**Vague modifier → apply, don't ask, show the work.**
> Alex: "less spicy this week"
> Sous: *Toning down the heat across the board — swapping larb for a
> milder version, dialing tinga to medium. Holler if I overcorrected.*

Default to action with a visible undo. Asking "how spicy on a scale of
1–10" is the corporate-survey vibe we're avoiding.

**Spouses disagree in-thread.**
> Sous: *Tie. Sam's swap wins (last word rule 😉) — want to swap, Alex, or
> override?* [Override → keep it]  [Let Sam pick]

The bot names the conflict, picks a default (most recent action), and
offers a one-tap override. Never silently picks a winner.

### 7.6 Edge States

- **First Friday, no history.** Three quick onboarding questions: proteins
  you eat, hard nos, spice scale.
- **Sunday catch-up.** Friday ping went unanswered through Sat morning.
  *"No reply yet — want me to lock the proposal as-is so you can hit the
  market Monday for a short week, or rework it?"* Options:
  `[Lock as-is]` `[Short week]` `[Skip, we'll wing it]`.
- **Travel week.** *"Skipping May 25–29. See you Friday May 30?"*
- **Hard veto.** Twice-flagged dish prompts *"Want to retire this one?"* →
  permanent block list.

### 7.7 Visual Identity

- **Bot name:** **Sous** (sous chef). One syllable, taps once. Backup: *Mise*.
- **Avatar:** single line-drawn wooden spoon on warm cream background.
- **Emoji palette:** 🌮 Mexican · 🍜 Asian · 🍝 Italian · 👶 toddler ·
  🥚 pantry · 🧺 market · 🏬 grocery · ✅ 🔄 ✏️ for actions. That's the
  whole vocabulary — consistency over variety.

---

## 8. Recipe Generation Rules

- **5 dinners per week** (Mon–Fri). Weekends are flex; bot does not plan
  them.
- **Cuisine mix:** all 3 of {Mexican, Asian, Italian} represented per week;
  no cuisine on two consecutive days. (With only 5 slots and 3 cuisines,
  this means the typical week is roughly 2-2-1 across the three.)
- **Ingredient overlap:** ≥ 3 ingredients must appear in 2+ meals per week
  (cost optimization at the 5-meal scale; the original ≥ 4 was sized for a
  10-meal week).
- **No recipe repeats within a 4-week window.**
- **Every meal with spice > toddler ceiling MUST declare a toddler variant.**
- **Weeknight (Mon–Thu) meals cap at 45 min active cook time.** Friday
  may stretch to ~75 min if the dish earns it (weekend energy).
- **Weekly budget cap: ~$250 combined** across farmers market + grocery.
  Hard rule: max 8 net-new non-pantry ingredients per week; the score
  function (§9.4) weights ingredient overlap to push toward this naturally.
- **Eggs are a free ingredient** (laying chickens) — prefer recipes that
  use them when overlap is otherwise weak.
- **≥ 1 leftover-friendly meal per week** (scales to Saturday lunch).
- **Down-weight (don't ban) any meal tagged "flopped" or
  "too-spicy-for-kids" twice in history.**

### Feedback Schema

Tag chips + optional free text, per meal, per spouse. Tags: `loved-it`,
`meh`, `flopped`, `too-spicy`, `too-bland`, `kids-loved-it`,
`kids-rejected`, `leftovers-rocked`, `too-much-work`. Tags are one-tap on
mobile, structured enough to feed the generator's weighting, and free text
catches the long tail.

---

## 9. Architecture

**One Supabase project. Three Edge Functions. One scheduled cron.**

```
                  +----------------------+
                  |  Telegram (group)    |
                  |   spouse A + B       |
                  +----------+-----------+
                             |
                webhook POST | replies via Bot API
                             v
                  +----------------------+
                  | Edge Fn: tg_webhook  |  <-- messaging adapter
                  +----------+-----------+
                             |
                             v
                  +----------------------+        +-----------------+
                  | Edge Fn: orchestrator|<------>|  Anthropic API  |
                  |  (intent + state)    |        | Sonnet 4.6 /    |
                  +----+-----+-----+-----+        | Haiku 4.5 /     |
                       |     |     |              | Opus 4.7        |
                       v     v     v              +-----------------+
              +------------------------------+
              |   Supabase Postgres          |
              | households, users, recipes,  |
              | plans, shopping_lists,       |
              | conversations, messages,     |
              | taste_profile, feedback      |
              +---------------+--------------+
                              ^
                              | pg_cron @ Fri 18:00 PT
                              |
                  +-----------+-----------+
                  | Edge Fn: kickoff_week |
                  +-----------------------+
```

### 9.1 Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Runtime | TypeScript on Supabase Edge Functions (Deno) | Same project as DB, zero glue, free tier covers this household, Anthropic TS SDK is first-class. |
| Database | Supabase Postgres (with `pgvector` later) | Single vendor, free tier, RLS built-in. |
| Auth | None for end users; service-role from Edge Fns | Two hard-coded `telegram_id`s in `users`. Closed system. |
| LLM | Claude `claude-haiku-4-5` (intent), `claude-sonnet-4-6` (workhorse), `claude-opus-4-7` (rare recipe-generation fallback) | Cheap classification + capable orchestration + heavyweight reasoning only when starved of candidates. |
| Scheduling | Supabase `pg_cron` + `pg_net` | Already in the project, no second vendor. |
| Hosting | Supabase Edge Functions | Free. Free subdomain. Done. |

### 9.2 Data Model

All tables: `id uuid primary key default gen_random_uuid()`,
`created_at timestamptz default now()` unless noted. RLS enabled on every
household-scoped table; service-role bypasses, and that's the only caller.

- **`households`**: `name text`, `timezone text default 'America/Los_Angeles'`.
- **`users`**: `household_id fk`, `display_name`, `role text check (role in ('adult','toddler'))`, `telegram_id bigint unique`, `birthdate date null`.
- **`taste_profile`**: `user_id fk`, `dimension text` (`spice_tolerance`, `dislike`, `restriction`, `loves`), `value jsonb`, `confidence real default 0.7`, `updated_at`. One row per (user, dimension, value).
- **`ingredients`**: `name_canonical text unique`, `aliases text[]`, `unit_default text`, `source_hint text check (source_hint in ('farmers_market','grocery','either'))`, `seasonal_months int[] null`, `is_free boolean default false` (eggs = true).
- **`recipes`**: `title`, `cuisine_tag text check (cuisine_tag in ('mexican','asian','italian','other'))`, `body_md`, `time_minutes int`, `toddler_variant_notes text null`, `source text check (source in ('llm_generated','curated'))`, `last_used_on date null`, `times_used int default 0`, `embedding vector(1024) null`.
- **`recipe_ingredients`**: `recipe_id`, `ingredient_id`, `quantity numeric`, `unit text`, `optional boolean default false`. PK `(recipe_id, ingredient_id)`.
- **`meal_plans`**: `household_id`, `week_of date` (Monday), `status text check (status in ('draft','proposed','locked','archived'))`, `locked_at timestamptz null`. Unique `(household_id, week_of)`.
- **`meal_plan_items`**: `plan_id`, `day date`, `slot text check (slot in ('dinner'))` (v1 dinners only; widen later if lunches return), `recipe_id`, `toddler_variant_active boolean default true`, `position int`. Unique `(plan_id, day, slot)`.
- **`feedback`**: `plan_item_id`, `rater_user_id`, `rating int check (rating between 1 and 5)`, `tags text[]`, `free_text text`.
- **`shopping_lists`**: `plan_id unique`, `generated_at`.
- **`shopping_list_items`**: `list_id`, `ingredient_id`, `quantity`, `unit`, `source text check (source in ('farmers_market','grocery'))`, `checked boolean default false`.
- **`conversations`**: `household_id`, `telegram_chat_id bigint unique`, `active_plan_id`, `state text` (`idle`, `awaiting_feedback`, `proposing`, `editing`, `locked`), `state_payload jsonb`.
- **`messages`**: `conversation_id`, `direction text check (direction in ('in','out'))`, `sender_user_id null`, `text`, `tool_calls jsonb null`, `telegram_update_id bigint unique`.

### 9.3 Core Flows

**Friday 6pm job:**
1. `pg_cron` calls Edge Function `kickoff_week`.
2. Load household + last week's `meal_plan` and its `feedback`.
3. Haiku call: classify any unrated items into "liked / meh / hated" from
   free-text feedback collected during the week.
4. Sonnet call #1: summarize last week ("you ate 4 of 5, skipped Tuesday
   for takeout, toddlers rejected the curry"). Short, narrated.
5. Planner: SQL query selects candidate recipes (rotation, seasonality,
   cuisine balance — see §9.4).
6. Sonnet call #2 with `propose_plan` tool: picks 5 dinners (Mon–Fri)
   from candidates, writes a draft plan via tool calls.
7. Post the proposal to Telegram as one message with inline keyboard
   buttons.

**User reply:**
1. Webhook fires, persists inbound message, resolves conversation.
2. Haiku intent classify:
   `feedback | swap | add_dislike | lock | smalltalk | shopping_question`.
3. Route to Sonnet with the full tool set and current draft plan in context.
4. Sonnet calls one or more of `swap_meal`, `set_taste_pref`,
   `regenerate_day`, `lock_plan`.
5. Each tool call is a DB write. Re-render plan, post diff back to Telegram.

**Lock + shopping list:**
1. `lock_plan` tool flips `meal_plans.status` → `locked`.
2. Pure SQL job (no LLM): aggregate `recipe_ingredients` across all
   `meal_plan_items`, sum quantities by `ingredient_id`, exclude `is_free`,
   group by `source_hint` (`either` defaults to `grocery` unless seasonal
   in current month → `farmers_market`).
3. Write `shopping_lists` + `shopping_list_items`.
4. Post two messages: "Farmers market" and "Grocery", each with toggle
   buttons.

### 9.4 LLM Integration Details

**Prompt caching** (Anthropic native cache-control):
- Static system prompt (role, rules, output format) — cached.
- Full `taste_profile` snapshot — rebuilt + re-cached only when it changes
  (track `taste_profile_version` int on `households`).
- Last 12 weeks of recipe titles + ratings as a compact text block —
  cached weekly.
- **Don't cache:** current draft plan, inbound user turn, tool results.

Expected cache hit rate > 80% on Friday session messages.

**Tools** (JSON schemas, all called by Sonnet unless noted):
- `propose_plan({ week_of, items: [{day, slot, recipe_id_or_new, toddler_variant_active}] })`
- `swap_meal({ plan_item_id, new_recipe_id_or_new })`
- `regenerate_day({ plan_id, day })`
- `set_taste_pref({ user_id, dimension, value, confidence })`
- `record_feedback({ plan_item_id, rater_user_id, rating, tags, free_text })`
- `lock_plan({ plan_id })`
- `generate_recipe({ constraints })` — **only this tool routes to Opus
  4.7**; everything else stays on Sonnet.

**Recipe rotation (DB, not vibes):**
```sql
select r.* from recipes r
where r.last_used_on is null
   or r.last_used_on < current_date - interval '28 days'
order by coalesce(r.last_used_on, '1970-01-01') asc, random()
limit 40;
```
Those 40 are the menu Sonnet picks from. If fewer than ~20 survive
secondary filters (seasonality, dislikes, cuisine balance), Sonnet calls
`generate_recipe` to top up; new recipes persist with `source='llm_generated'`.

**Ingredient overlap algorithm** (Postgres function
`score_candidates(plan_draft jsonb)`):
```
chosen = []
for slot in 5 slots (Mon–Fri):
  score(r) = base_novelty(r)
           + 0.5 * |ingredients(r) ∩ ingredients(chosen)|
           - 0.6 * cuisine_repeat_penalty(r, chosen)
           - 0.3 * dislike_overlap(r, taste_profile)
           - 0.4 * over_45min_penalty(r)  // Mon–Thu only
  pick top-K=5 by score, let Sonnet choose final
  append to chosen
```
Overlap weight bumped from 0.4 → 0.5 vs. the 10-meal version: with only 5
slots, every shared ingredient matters more for the $250 budget.
This is the bit that prevents "buy a whole bunch of cilantro for one
Tuesday recipe."

**Toddler variants** live inside the recipe row as `toddler_variant_notes`
markdown ("skip chiles, serve rice plain, shred chicken finer"). Same
ingredient list — the variant is a preparation fork, not a separate recipe.

### 9.5 Scheduled Jobs

- **`kickoff_week`** — `0 18 * * 5 America/Los_Angeles` (Fri 6pm) —
  propose next week's plan.
- **`nag_unlocked`** — `0 9 * * 6` (Sat 9am) — if Friday's plan still
  `draft` by Saturday morning, soft nudge in the thread so the market run
  isn't blocked.
- **`archive_old_plans`** — `0 3 * * 1` — flip last week's `locked` plans
  to `archived`, bump `recipes.last_used_on` and `times_used`.
- **`weekly_taste_compaction`** — `0 4 * * 1` — Haiku call to dedupe and
  merge `taste_profile` rows.

### 9.6 Idempotency, Retries, Failure Modes

- **Friday job double-fire:** `meal_plans` has `unique(household_id,
  week_of)`. The Edge Function does `insert ... on conflict do nothing
  returning id`; if no row returned, exit. Telegram post is gated on the
  insert succeeding.
- **Telegram down:** orchestrator always commits state to Postgres *before*
  attempting the Telegram send. On send failure, mark the outbound
  `message` row as un-sent and retry on next inbound or via a 5-minute
  flush cron.
- **Webhook delivery dupes:** Telegram retries on non-2xx; the webhook
  upserts on `messages.telegram_update_id` (unique). Reject dupes fast.
- **Malformed LLM JSON / tool args:** use Anthropic tool-use (structured),
  not free-form JSON parsing. If a tool call fails schema validation,
  return the error as a tool result and let Sonnet retry — cap at 2
  retries per turn, then post "I got confused, can you rephrase?" to the
  thread.
- **Recipe references unknown ingredient:** `generate_recipe` resolves
  ingredients against `ingredients.name_canonical` + `aliases`; unknowns
  get inserted with `source_hint='either'` and flagged for review.

### 9.7 Local Dev + Deploy

- **Local:** `supabase start` (Postgres + Edge runtime in Docker),
  `supabase functions serve` for hot reload, `ngrok http 54321` to expose
  the webhook for the dev bot (separate token from prod).
- **Deploy:** `supabase db push` for migrations,
  `supabase functions deploy tg_webhook orchestrator kickoff_week`.
- **Secrets:** `supabase secrets set ANTHROPIC_API_KEY=... TELEGRAM_BOT_TOKEN=... TELEGRAM_ALLOWED_CHAT_IDS=...`. Never in code. `.env.local`
  gitignored for dev.
- **CI:** one `.github/workflows/deploy.yml` (~40 lines) — on push to
  `main`: `deno check`, `deno test`, then `supabase db push` and
  `supabase functions deploy` via `SUPABASE_ACCESS_TOKEN` repo secret.

### 9.8 Estimated Monthly Cost

| Item | Cost |
|---|---|
| Supabase free tier | $0 |
| Anthropic API (~$1.00/Fri session + ~$0.20/wk Haiku + occasional Opus) — slightly lower at 5 dinners vs. 10 meals | $5–7 |
| Telegram Bot API | $0 |
| Domain / TLS | $0 |
| **Total** | **~$5–7/mo** |

If it ever crosses **$15/mo**, something is wrong — check token bloat
(full conversation history in prompts) before scaling anything.

---

## 10. Security

### 10.1 Threat Model

Personal tool with a tiny attack surface and near-zero attacker motivation.
Realistic threats, in priority order:

1. **Credential leakage causing cost-bombing** — Anthropic key scraped from
   a public commit, $4k bill overnight.
2. **Embarrassing data exposure** — kids' names, allergies, household
   routines via a misconfigured RLS policy and a leaked anon key.
3. **V2 Vons account suspension** — for ToS-violating automation.

Calibrated to "decent hygiene for a personal tool." No SOC2, no SIEM.

### 10.2 Authentication & Authorization

- **Household onboarding:** admin inserts both spouses' Telegram `chat_id`s
  via one-time SQL seed.
- **Telegram identity check:** every incoming update's `message.from.id`
  is checked against `allowed_chat_ids`. Unknown IDs get **silent 200**
  (no oracle).
- **RLS** enabled on every household-scoped table:
  ```sql
  alter table meal_plans enable row level security;
  create policy hh_isolation on meal_plans
    for all using (household_id = current_setting('app.household_id')::uuid);
  ```
  Edge Functions set `app.household_id` via `set_config` after looking up
  `chat_id → household_id`. **Anon key has no direct table access.**
- **Admin tier:** the requester is the only Supabase dashboard user.
  Enable 2FA on Supabase, GitHub, and Anthropic accounts.

### 10.3 Secrets Management

| Secret | Lives in | Never in |
|---|---|---|
| Telegram bot token | Edge Fn env (`TELEGRAM_BOT_TOKEN`) | repo, client, logs |
| Telegram webhook secret | Edge Fn env (`TG_WEBHOOK_SECRET`) | repo |
| Anthropic API key | Edge Fn env (`ANTHROPIC_API_KEY`) | repo, client |
| Supabase service role | Edge Fn env (auto-injected) | client, repo |
| V2 Vons creds | `pgcrypto`-encrypted column, key in Supabase Vault | logs, plaintext, LLM prompts |

- **Rotation:** Telegram + Anthropic every 6 months or on suspected leak.
- **Pre-commit hook:** install `gitleaks` or `trufflehog`. Catches the
  90% case.
- **`.gitignore`:**
  ```
  .env
  .env.*
  !.env.example
  supabase/.env
  *.pem
  *.key
  ```

### 10.4 Webhook & API Hardening

- **Telegram webhook:** set `secret_token` on `setWebhook`; reject requests
  with mismatched `X-Telegram-Bot-Api-Secret-Token`.
- **Chat ID allowlist:** hard check inside Edge Function before any DB or
  LLM work.
- **Rate limit:** per chat_id, 30 messages/hour, 5 LLM-invoking
  messages/hour.
- **Cost guardrails:** `max_tokens=4096` per call. Daily cap: 20 LLM
  calls / 200k tokens. Kill switch via `system_flags.llm_enabled=false`
  — flippable from the Supabase dashboard in 10 seconds.

### 10.5 Prompt-Injection Defenses

- **Strict role separation:** system prompt is a static string in code.
  User text **only** ever appears in `{role: "user", content: ...}`. Never
  f-string user input into the system prompt.
- **Framing wrapper for user content:**
  ```
  <user_message from="wife" chat_id="123">
  {{ verbatim message }}
  </user_message>
  ```
  System prompt declares anything inside these tags is untrusted data,
  not instructions.
- **External content** (V2 recipe scraping, Vons HTML): strip tags + any
  pattern matching `(ignore|disregard).{0,40}(previous|above|prior)`,
  wrap in `<external_data source="vons.com">...</external_data>`.
- **Tool allowlist:** orchestrator rejects any `tool_use` whose name isn't
  in the allowlist. **No `execute_sql`, no `exec_shell`, no `fetch_url`
  tool ever exists.**
- **Output validation:** every tool call's args JSON-schema-validated
  before execution.
- **Never `eval`** LLM-emitted code.

### 10.6 Data Handling & Retention

- **Stored:** meal plans, ratings, free-text feedback, taste profile,
  conversation history (last 90 days, then auto-purge cron).
- **Sensitive:** kids' names, allergies. Treat as PII even though no
  regulator cares. Don't email, don't log, don't put in error messages.
- **Sent to Anthropic:** taste profile JSON + last 4 weeks of feedback
  summaries + current week's draft. **Not** raw conversation history older
  than current session, **not** real names — use `spouse_a / spouse_b /
  kid_1` tokens, mapped back client-side.
- **Anthropic settings:** default US region. Don't opt into data-sharing
  programs.
- **Backups:** Supabase auto-backups + monthly CSV export cron emailed to
  admin (disaster recovery + "right to my data").

### 10.7 AI-Specific Risks

- **Kid-unsafe recipes for a 2½-year-old + a 9-month-old.** Active block-list
  in code (calibrated to the youngest = 9mo, so infant rules now dominate):
  - **Honey → BLOCKED** for the baby's portion (under 12mo; botulism risk).
    Revisit after the baby turns 1 (≈ 8 months out).
  - Baby portion must be **soft / mashed and unsalted**, pulled before salt,
    spice, or acid hits the pan.
  - Whole grapes, cherry tomatoes whole, whole olives → must be quartered
  - Whole nuts, hard nut chunks, popcorn → blocked
  - Raw hard veg cubes (carrot, apple) → blocked unless cooked or grated
  - Undercooked egg dishes (mayo, hollandaise, soft-yolk poach) → flagged
  - Hot dogs / sausages → must be split lengthwise + sliced
  Mitigation: code-side `unsafe_for_age` table, indexed by min-age,
  post-filters every proposal. **Don't trust the model to remember.**
  (Currently enforced via prompts; the `unsafe_for_age` post-filter table is
  not yet built — see build notes.)
- **Budget creep** — model proposes 14 exotic ingredients. Hard rule: max
  8 net-new non-pantry ingredients per week, weekly target spend
  **≤ $250** (farmers market + grocery combined). Cost is estimated from
  `ingredients.avg_price` × `quantity`; over-budget plans fail the
  post-filter and Sonnet retries.
- **Stale-preference drift** — separate `hard_dislikes` table (binary
  block) from `soft_preferences` (hints). Hard dislikes enforced in code,
  not prompt.

### 10.8 Monitoring + Runbooks

Daily digest email: tokens used, plans generated, errors. Runbooks
(saved as `SECURITY.md` in the repo):

**Telegram bot token leaked**
1. BotFather → `/revoke` to mint new token.
2. Update `TELEGRAM_BOT_TOKEN` in Supabase env; redeploy.
3. Re-call `setWebhook` with new token + freshly rotated webhook secret.

**Anthropic API key leaked**
1. Anthropic console → revoke; set a low spend cap.
2. Mint new key, update env, redeploy.
3. Audit last 7 days; flip `llm_enabled=false` until audit done.

**Supabase service role leaked**
1. Rotate in dashboard (Settings → API → Reset).
2. Update env, redeploy.
3. Review `auth.audit_log_entries` for last 24h.

### 10.9 Pre-Launch Security Checklist

- [ ] `.env*` in `.gitignore`; `gitleaks` pre-commit installed and tested.
- [ ] No secret in `git log -p --all | grep -iE "(sk-|bot[0-9]+:|service_role)"`.
- [ ] RLS enabled on every household-scoped table; verified by anon-key
      probe.
- [ ] Service-role key not in any client bundle.
- [ ] `setWebhook` called with `secret_token`; Edge Fn rejects mismatch.
- [ ] `allowed_chat_ids` has exactly two entries; unknown IDs silent 200.
- [ ] Per-chat rate limit + daily LLM cap wired and tripped in test.
- [ ] `llm_enabled` kill switch tested.
- [ ] System prompt static; user text only in `<user_message>` tags.
- [ ] Tool allowlist enforced; unknown names rejected.
- [ ] Kid-unsafe ingredient post-filter unit-tested.
- [ ] `hard_dislikes` block enforced in code.
- [ ] 2FA on Anthropic, Supabase, GitHub.
- [ ] Conversation history 90-day purge cron scheduled.
- [ ] Daily cost-digest email arrives at admin inbox.
- [ ] `SECURITY.md` runbooks committed.

---

## 11. Build Order — First Week Walking Skeleton

1. **Day 1 AM — repo + bot echo.** `supabase init`, `tg_webhook` Edge
   Function that verifies the chat ID and echoes. `setWebhook` with the
   secret. Confirm both spouses can hit it from the group chat.
2. **Day 1 PM — schema v1.** Migrations for `households`, `users`,
   `conversations`, `messages`. Seed two `users` with real Telegram IDs.
3. **Day 2 — orchestrator stub.** Edge Function persists inbound, calls
   Sonnet with a trivial system prompt, replies in-thread. No tools yet.
   You now have Claude in your family group.
4. **Day 3 — recipes + planner SQL.** Migrations for `recipes`,
   `ingredients`, `recipe_ingredients`. Seed 25 dinner recipes by hand
   (~8 each Mexican/Asian/Italian + 1 misc). Write `score_candidates`.
5. **Day 4 — `propose_plan` tool.** Add `meal_plans`, `meal_plan_items`.
   Wire Sonnet tool use. Manually trigger from a CLI script: it should
   write a draft 5-dinner plan and post it.
6. **Day 5 — `swap_meal` + `lock_plan`.** End-to-end editing works.
7. **Day 6 — shopping list.** Deterministic SQL aggregation, two grouped
   messages. No LLM in this path.
8. **Day 7 — schedule it.** `pg_cron` + `pg_net` → `kickoff_week` at
   Fri 6pm PT. Add `feedback` and a simple "rate last week" prompt. Ship.

Everything else — `taste_profile` learning, `generate_recipe` via Opus,
seasonality, Vons — is week two and beyond. **Don't build it now.**

---

## 12. Sequencing After Week 1

- **Week 2:** Save winners (`recipes.times_used`, `last_used_on` bumps).
  Friday prompt now references prior loved meals. Toddler-variant column
  surfaces in plan output.
- **Week 3:** Pantry / leftover awareness. She can text mid-week "still
  have half the rotisserie chicken" and the bot stores a note for next
  Friday. Eggs always assumed unlimited.
- **Week 4:** Polish the rough edge she's complained about most. *Ask
  her, don't guess.*

Each iteration ships before Friday's ping. Each Friday is the real test.

---

## 13. V2 Backlog (rough priority)

1. **Vons pickup integration** (with V2 trap caveats below).
2. **Seasonal farmers-market awareness** — bias proposals toward what's
   actually in season locally.
3. **Smarter pantry tracking** — remember half-used jars, opened
   condiments, frozen leftovers.
4. **Per-meal cost estimate + weekly grocery-spend trend vs. HelloFresh
   baseline.**
5. **"Cook mode"** — step-by-step recipe view triggered from the chat.
6. **Photo-based feedback** ("send a pic of the plate, kids ate around
   the broccoli").
7. **Guest mode** — adjust portions when in-laws are visiting.
8. **Voice input** for feedback while doing dishes.
9. **Shareable recipe cards** if a meal becomes a household classic.

### The V2 Vons Trap — read this before starting

Vons will eat this project alive. Their login has 2FA, captcha, and a ToS
that likely prohibits automation. You will spend three weekends debugging
Puppeteer at 11pm and your wife will start asking why the bot is broken.

**V2 escape hatch:** the bot formats the grocery list as a clean
newline-separated text block optimized for paste-into-Vons-search. He
copy-pastes once. Total added effort: 90 seconds. Total engineering effort
to support it: zero. If after 3 months he *still* wants real automation,
revisit.

If you do build the integration:
- **No headless auto-checkout.** Always require explicit "yes, order it"
  in the Telegram thread from a known chat_id.
- Prefer "open this pre-filled cart link in your browser" over a headless
  POST.
- Audit log every cart mutation to a `vons_actions` table; retain 1 year.
- Throttle to human-plausible rates; back off on CAPTCHA or 429.
- If Albertsons offers an official API, prefer that even at higher build
  cost.

---

## 14. Skip List — what you are NOT building

Hacker entrepreneur's gospel:

1. Web dashboard. Telegram is the UI. Forever.
2. OAuth / user accounts. Hardcoded allowed `chat_id`s.
3. End-user RLS complexity. Service-role from one Edge Function, period.
4. Recipe DB with images. Text-only V1; LLM generates fresh as needed.
5. Nutrition calculator. Your wife knows what's healthy.
6. Ingredient inventory tracking. She'll tell the bot what's in the fridge.
7. Seasonality awareness in V1. The LLM kind of knows. Good enough.
8. Taste-profile editor UI. Edit JSON or tell the bot in chat.
9. Multi-family / sharing. No.
10. Meal photos / image generation. Token-expensive, useless.
11. Voice transcription. Text replies until she asks for voice.
12. Analytics dashboards. `select * from meal_plans order by week_of desc`
    is your analytics.

---

## 15. Personal Project Discipline

Three rules to keep this from turning into a startup nobody asked for:

1. **No feature she hasn't asked for in 2 weeks of real use.** Backlog
   goes in `someday.md`. Most of it dies there. Good.
2. **No refactor before week 4 of real use.** Ugly code that ships beats
   clean code that doesn't.
3. **Don't show friends until a full season of use.** The second someone
   says "you should make this a startup," it stops being yours.

### The Wife Test — north star

**When she replies to the Friday ping, does it feel like texting a
friend who happens to be a great meal planner, or filling out a form?**

After Friday #2, ask her: *"On a scale of 1–5, did this feel like a
conversation or a chore?"* If under 4, the prompt is wrong, not the code.

---

## 16. Success Metrics

| Metric | Target |
|---|---|
| Plan-lock latency (median minutes from Friday ping → "lock it") | < 20 min |
| Edit rate (% of proposed meals surviving without swap) | ≥ 70% by week 6 |
| Dual approval rate (weeks both spouses engaged positively) | ≥ 80% |
| HelloFresh replacement rate | 4 / 4 weeks by month 2 |
| Weekly spend adherence (% of weeks within $250 cap) | ≥ 90% by month 2 |
| Kid-eat rate (% of dinners not tagged `kids-rejected`) | ≥ 60% |

---

## 17. Next Up — Things to Decide Before Coding

All seven launch-blocker questions are answered (see §1). What's left,
roughly in order of when you'll hit them:

1. **Telegram bot handle.** Pick a name + username for BotFather
   (suggested: `@SousChefBot` or similar; whatever's available).
2. **Pantry staples** beyond eggs — what to auto-omit from every shopping
   list (olive oil, salt, garlic, onions, rice, soy sauce, etc.). One
   question in onboarding, editable via `/pantry`.
3. **Seed recipes (×25).** Pick 8 dinners each from Mexican / Asian /
   Italian + 1 wildcard, in a recipes.md or as SQL seeds. The bot can
   draft these for you in V0 if it's easier.
4. **Avatar art for Sous.** Optional. The line-drawn wooden spoon was a
   sketch; if you want something specific, decide before deploy.
5. **Anthropic + Supabase account ownership** — confirm both are under
   your personal email, not a work account; 2FA enabled on each.
