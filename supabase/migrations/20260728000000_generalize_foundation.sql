-- Sous — generalization foundation (ROADMAP T1).
--
-- Adds the per-household config surface that later migrations + edge-function
-- changes read from, so a fresh household is no longer locked into the original
-- family's kitchen (backyard eggs, farmers-market split, USD/imperial, a fixed
-- cuisine set, a Mon–Thu ≤45-min schedule, one persona).
--
-- SAFETY (ROADMAP principle 1): every change here is additive, and the data
-- step at the bottom pins ANY already-existing household to its current
-- behavior. On a fresh clone no households exist yet at migrate time, so new
-- households get the generic defaults below. On the author's live instance the
-- one existing household keeps eggs-free + the farmers-market/grocery split.

-- ---------------------------------------------------------------------------
-- household_preferences: new config columns (all with neutral defaults).
alter table household_preferences
  -- Diet & allergies. dietary_restrictions are named diets (vegetarian, vegan,
  -- pescatarian, halal, kosher, gluten_free, dairy_free, …); excluded_ingredients
  -- are free-text ingredient names to hard-avoid (allergies, dislikes).
  add column if not exists dietary_restrictions text[]  not null default '{}',
  add column if not exists excluded_ingredients text[]  not null default '{}',
  -- Ingredients the household gets for free / already has, so they're omitted
  -- from the shopping list. Replaces the global ingredients.is_free flag.
  add column if not exists free_staples        text[]  not null default '{}',
  -- Ordered shopping-list section labels. Default: one plain "Grocery" bucket.
  add column if not exists shopping_sources    text[]  not null default '{Grocery}',
  -- Money & measurement.
  add column if not exists currency            text    not null default 'USD',
  add column if not exists unit_system         text    not null default 'imperial'
    check (unit_system in ('imperial','metric')),
  -- Weeknight schedule + planning rules.
  add column if not exists weeknight_cap_minutes int   not null default 45,
  add column if not exists weeknight_days      text[]  not null default '{mon,tue,wed,thu}',
  add column if not exists plan_days           text[],  -- null = auto-fill first N weekdays
  add column if not exists avoid_consecutive_cuisine boolean not null default true,
  -- Voice + locale.
  add column if not exists persona_style       text    not null default 'bold',
  add column if not exists locale              text    not null default 'en-US',
  -- Weekly kickoff timing, interpreted in households.timezone (T12).
  add column if not exists plan_day            text    not null default 'fri',
  add column if not exists plan_hour           int     not null default 18
    check (plan_hour between 0 and 23);

-- ---------------------------------------------------------------------------
-- recipes: portion basis + structured diet tags (values populated in T2).
alter table recipes
  add column if not exists base_servings int    not null default 4,
  add column if not exists dietary_tags  text[] not null default '{}';

-- ingredients: allergen tags for structured filtering (values populated in T2).
alter table ingredients
  add column if not exists allergens text[] not null default '{}';

-- ---------------------------------------------------------------------------
-- Loosen the CHECK constraints that hardcoded one family's worldview so later
-- tasks can use arbitrary values. Dropping a CHECK only widens what's allowed —
-- existing rows stay valid. Names are Postgres's auto-generated defaults.
alter table recipes             drop constraint if exists recipes_cuisine_tag_check;         -- T8: any cuisine
alter table ingredients         drop constraint if exists ingredients_source_hint_check;     -- T6: any store/source
alter table shopping_list_items drop constraint if exists shopping_list_items_source_check;  -- T6: any store/source

-- ---------------------------------------------------------------------------
-- Neutral default timezone.
--
-- 20260521000100 defaulted households.timezone to 'America/Los_Angeles' — one
-- region's clock for every deploy on earth. Onboarding now asks where the
-- household lives and writes the real zone, so this default only covers the gap
-- before that answer arrives. UTC is the honest placeholder.
alter table households alter column timezone set default 'UTC';

-- ---------------------------------------------------------------------------
-- Preserve the live instance (ROADMAP principle 1).
--
-- The author's deployed database has one household that predates all of this
-- and must keep behaving exactly as before: eggs off the shopping list (they
-- keep chickens) and the farmers-market/grocery split.
--
-- This MUST NOT touch anyone else. An earlier draft ran a bare
--   update household_preferences set free_staples = array['eggs'], ...
-- with no WHERE, justified by "on a fresh clone no rows exist yet". That holds
-- for a clone, and fails for the realistic case: a public user deploys,
-- onboards their household, then pulls a later release and runs `db push` —
-- and silently inherits someone else's kitchen, losing eggs from their list.
--
-- So gate on something only the pre-generalization instance can satisfy: the
-- household predates this work. Sous was private until this branch, so no
-- public deploy can have created a household before the cutoff, while the
-- author's has existed for months. (ingredients.is_free is NOT a usable
-- fingerprint here — it is true on every database seeded before
-- 20260728000200, including a public user's, which is exactly the case this
-- guard exists to protect.)
--
-- Written as insert-or-update because household_preferences rows are created
-- lazily (getPreferences returns defaults when absent), so a plain UPDATE could
-- silently match nothing and quietly change the live bot's behavior.
insert into household_preferences (household_id, free_staples, shopping_sources)
select h.id, array['eggs'], array['Farmers Market','Grocery']
  from households h
 where h.created_at < timestamptz '2026-07-28 00:00:00+00'
    on conflict (household_id) do update
   set free_staples     = excluded.free_staples,
       shopping_sources = excluded.shopping_sources;

-- ---------------------------------------------------------------------------
-- Two seeded recipe descriptions asserted the author's backyard chickens
-- ("Eggs from the coop.") and were rendered verbatim onto every household's
-- recipe card. The seed files no longer contain the phrase, but the seeds use
-- `on conflict do nothing`, so an already-seeded database keeps the old text
-- until it is rewritten here.
update recipes
   set body_md = replace(body_md, ' Eggs from the coop.', '')
 where body_md like '%Eggs from the coop.%';
