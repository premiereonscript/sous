# Contributing to Sous

Sous is a small, self-hosted project. Issues and pull requests are welcome, and
so is a fork that goes its own way — this is meant to be a starting point for
your own kitchen, not a product you have to use as shipped.

## Running the whole thing locally

You need [Deno](https://deno.land) and Docker (for the local Supabase stack).

```bash
supabase db start            # applies every migration + seeds the catalog
deno task check              # type-check the edge functions
deno task test               # unit tests for the pure logic in _shared
deno task lint
```

For the database tests, enable pgTAP once per local database — it is deliberately
not a migration, so a test framework never lands in anyone's production project:

```bash
psql "postgresql://postgres:postgres@localhost:54322/postgres" \
  -c 'create extension if not exists pgtap with schema extensions;'
supabase test db
```

To drive the bot end to end you also need a Telegram bot token and an Anthropic
key — see [`SETUP.md`](./SETUP.md). Point a throwaway bot at a local tunnel:

```bash
supabase functions serve tg_webhook --env-file supabase/functions/.env
ngrok http 54321
```

CI runs the type-check, unit tests, lint, and the pgTAP suite on every PR.

## The one rule that matters

**Diet and allergy handling is enforced in SQL, and it fails closed.** If you
touch `candidate_recipes`, `diet_conflict`, `diet_rules`, or anything that
writes `dietary_tags` / `allergens`, add a pgTAP case that proves the unsafe
recipe is *excluded*. A test asserting the happy path still works is not enough
— the failure mode here is a recipe silently reaching someone with an allergy,
and it has happened once already (see [`ROADMAP.md`](./ROADMAP.md)).

Two specifics that are easy to get wrong:

- A recipe with empty `dietary_tags` is **unclassified, not safe**. Never write
  a filter that treats a missing tag as permission.
- Recipe-level `contains_*` tags and ingredient-level `allergens` are separate,
  hand-maintained lists. The filter checks both on purpose. Don't collapse them.

## Good first contributions

These are real gaps, roughly easiest first:

- **More plant-based mains.** The catalog has 6 vegan mains against a 28-day
  reuse window, so a vegan household runs dry after one week. Follow the pattern
  in `20260728000400_seed_plant_based_mains.sql`, and tag both the recipe and
  every new ingredient.
- **Case-insensitive `free_staples` matching.** `generate_shopping_list`
  compares `i.name_canonical = any(v_free)` exactly, so "Eggs" silently does
  nothing. Lowercase both sides on read and write.
- **Kid-safety in code.** The `unsafe_for_age` block-list (SPEC §10.7) is
  prompt-enforced only. Diet already has the SQL pattern to copy.
- **Fixed-string i18n.** Locale drives replies, money and dates, but the literal
  labels ("Shopping list", day names) are English.
- **Tighten `diet_conflict`.** It catches allergen and avoid-list violations on
  the customize path, but not a diet with no allergen behind it (vegetarian,
  halal, no-pork), and not an ingredient the catalog has never seen.

## Adding recipes

An `ingredients` row per new item (with `allergens`), a `recipes` row (with
`base_servings` and `dietary_tags`), and its `recipe_ingredients`. Put them in a
new timestamped migration rather than editing a seed that has already shipped —
the seeds use `on conflict do nothing`, so edits to them never reach a database
that has already run them.

## Style

- Deno defaults; `deno task lint` and `deno fmt` are the arbiters.
- Comments explain **why**, not what. The repo leans on this heavily — if a
  line looks odd, the comment should say what would break without it.
- Commit messages: what changed and why it mattered. Long is fine.

## Reporting a security issue

Don't open a public issue. The threat model is in SPEC.md §10; the short version
is that `TELEGRAM_ALLOWED_CHAT_IDS` is the entire authorization model, and every
deploy is someone's own Supabase project holding their own keys.
