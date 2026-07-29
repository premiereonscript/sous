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
  add column if not exists persona_style       text    not null default 'weissman',
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
-- Preserve the live instance (ROADMAP principle 1).
-- At migrate time the only household_preferences rows that can exist are on the
-- author's already-deployed database (fresh clones have none yet). Pin them to
-- the original behavior so the running bot is unchanged; new households created
-- later fall through to the generic defaults above.
update household_preferences
   set free_staples     = array['eggs'],
       shopping_sources = array['Farmers Market','Grocery'];
