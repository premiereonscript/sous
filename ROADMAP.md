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
   pattern.
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

---

## What the codebase already got right

`household_preferences` (adults + `kids[]` ages + meals/week + freeform cuisines),
RLS + `app_household_id()` isolation, and the `recipe_exclusions` pattern are all
well-abstracted. Most of Tier 1/2 is bringing the *rest* of the schema up to that
same standard.

## Status

Tracked in the session task board (T1–T16). Work lands on the
`generalize-for-public` branch; nothing goes to `main` or public without the
owner's explicit approval.
