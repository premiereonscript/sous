# Roadmap — generalizing Sous for public use

Sous was built for one household and is being generalized so **any** family can
deploy their own instance. This document is the source of truth for that work.
It came out of a three-part audit (schema, function logic, prompts/persona) that
independently converged on the same hardcoded assumptions.

## Guiding principles

1. **Additive, non-breaking migrations.** The author already runs a live
   instance. Every migration must be backward-compatible, and a data step must
   pin the author's existing household to its current behavior (eggs free,
   farmers-market + grocery split) so the live bot is unchanged. New households
   get generic defaults.
2. **Config over hardcode.** Anything specific to one family's kitchen, region,
   diet, schedule, currency, or taste becomes a per-household preference (or a
   deployment env var), with a sensible neutral default.
3. **Server-enforced safety.** Dietary/allergy constraints are hard SQL filters
   on the candidate pool — never LLM best-effort. Copy the `recipe_exclusions`
   pattern. One exception exists today and is tracked in *Still open*: the
   customize path enforces allergens and the avoid list, but not diets that
   have no allergen behind them.
4. **Every phase ends green.** `deno check` clean; docs updated for what shipped.

## Severity legend

- **BLOCKER** — a stranger gets wrong or broken output.
- **FRICTION** — works, but feels built for someone else.
- **SCOPE** — a deliberate v1 decision to make and *document*.

---

## Tier 1 — Correctness (prerequisite for an honest public launch)

| ID | Work | Sev | Effort |
|----|------|-----|--------|
| T1 | Foundation schema migration + preserve-live-instance data step | — | M |
| T2 | Retag 50 seed recipes (`base_servings`, `dietary_tags`) + ingredient `allergens`; add meatless/vegan mains | BLOCKER | M |
| T3 | Portion scaling by household size in `generate_shopping_list` | BLOCKER | M |
| T4 | Dietary/allergy onboarding question + server-side hard filter | BLOCKER | M–L |
| T5 | Free-staples abstraction — kill hardcoded `"eggs"` string-matches | BLOCKER | S–M |

**Why Tier 1 gates launch:** without it a stranger gets the author's family's
exact quantities, silently loses eggs from their list, and a vegetarian/allergy
household cannot use the bot at all.

## Tier 2 — Personalization (makes it feel like general software)

| ID | Work | Sev | Effort |
|----|------|-----|--------|
| T6 | Configurable shopping sources (drop fixed farmers-market/grocery) | BLOCKER/FRICTION | M |
| T7 | Currency + units abstraction (`monthly_budget` + ISO currency, `unit_system`) | FRICTION | S–M |
| T8 | Cuisine taxonomy — drop 4-value CHECK, graceful labels | FRICTION | S |
| T9 | Planning-rule prefs (weeknight cap/days, plan days, cuisine-repeat) | FRICTION | S–M |
| T10 | Persona swappability + strip lifestyle claims from the voice | FRICTION | S |
| T11 | Model IDs → env config | FRICTION | trivial |
| T12 | Timezone-aware weekly kickoff (per-household day/hour) | BLOCKER (multi-tz) | M |
| T13 | Gate kid/toddler content on actual household kids | FRICTION | S |

## Tier 3 — Reach

| ID | Work | Sev | Effort |
|----|------|-----|--------|
| T14 | i18n / non-English support (locale, strings, translated persona) | SCOPE→BLOCKER | L |
| T15 | Multi-household-per-deploy + multi-chat kickoff fan-out | FRICTION | M |

## Cross-cutting

| ID | Work |
|----|------|
| T16 | Docs — README "Make it yours", SETUP config reference, SPEC v1 scope |
| T17 | Test suite — Deno unit tests, pgTAP database tests, CI |
| T18 | Catalog balance — 6 vegan + 2 vegetarian mains, so a plant-based household can get a first week at all |

---

## What the codebase already got right

`household_preferences` (adults + `kids[]` ages + meals/week + freeform cuisines),
RLS + `app_household_id()` isolation, and the `recipe_exclusions` pattern are all
well-abstracted. Most of Tier 1/2 is bringing the *rest* of the schema up to that
same standard.

## Status

**T1–T13 and T16–T18 shipped.** T14 (full i18n) and the multi-household half of
T15 were deliberately deferred — see *Still open*.

Every hardcoded assumption listed above is now a per-household preference with a
neutral default. Onboarding captures the seven that block a first plan
(household size, kids' ages, dinners per week, budget, cuisines, diet and
allergies, timezone); the rest default sensibly and are changeable by chat. The
kickoff day and hour are the exception — SQL only, for now.

## Pre-landing review findings

A review of the whole branch before landing found and fixed these. Recorded
because each is a failure mode worth re-checking against future changes:

- **A rewritten SQL function silently dropped a predicate from an earlier
  migration.** `candidate_recipes` was rebuilt from the v3 body and lost the
  `is_variant` exclusion added in v4, so one-off LLM customizations re-entered
  the planning pool.
- **Half of the dietary filter failed open.** The allergen checks passed any
  recipe merely *lacking* a `contains_*` tag, while the vegetarian/vegan checks
  required a tag — two halves of one filter disagreeing about what an untagged
  row means. Untagged now means unclassified, and is refused.
- **A "preserve the live instance" data step had no `WHERE` clause**, so any
  public deploy that onboarded and later pulled an update inherited the
  author's free staples and shopping split.
- **Preferences were readable but not writable.** Four planning-rule fields and
  the timezone had no write path anywhere, while the README advertised changing
  them by chat.

## Still open

- **Kid-safety in code.** The `unsafe_for_age` block-list (SPEC §10.7) is still
  prompt-enforced only. Diet and allergy avoidance *is* enforced in SQL.
- **Fixed UI strings are English.** Locale drives replies, generated content,
  money and dates, but not the literal labels ("Shopping list") or the starter
  catalog.
- **`diet_conflict` is narrower than the planning filter.** On the customize
  path it blocks an added ingredient carrying a forbidden allergen or sitting
  on the avoid list. A diet with no allergen behind it (vegetarian, halal,
  no_pork) and an ingredient the catalog has never seen both fall through to
  prompt enforcement. The planning pool itself is fully filtered.
- **Weekly plan day/hour is SQL-only.** `plan_day` and `plan_hour` are the last
  preferences with no conversational path. Everything else, timezone included,
  can be changed by texting the bot. Listed as a good first contribution.
- **One household per deploy.** A deliberate v1 boundary, not a gap — see the
  *Generalization note* at the top of SPEC.md. The multi-chat fan-out half of
  T15 did ship; multi-household-per-deploy did not.
