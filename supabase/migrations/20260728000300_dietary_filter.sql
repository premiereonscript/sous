-- Sous — T4: server-side dietary/allergy hard filter on the candidate pool.
--
-- candidate_recipes v5: same signature + return shape as v4, but when a
-- p_household_id is passed it also drops any recipe that violates the
-- household's dietary_restrictions or excluded_ingredients (read from
-- household_preferences). This is a HARD filter: diet + allergy safety must not
-- depend on the LLM honoring a soft request in a prompt.
--
-- SAFETY DESIGN — three properties this filter must hold:
--
--   1. FAIL CLOSED. A recipe with no dietary_tags is UNCLASSIFIED, not safe. A
--      household with any restriction never sees an unclassified recipe. (The
--      earlier draft checked only `not ('contains_x' = any(dietary_tags))`,
--      which passes trivially for an untagged row — so LLM-generated variants
--      and user-added recipes sailed through every allergy check.)
--   2. TWO INDEPENDENT SOURCES. Recipe-level `contains_*` tags are curated by
--      hand and can drift from the ingredient-level `allergens` they summarize.
--      Both are checked, so a mis-tagged recipe is still caught by its
--      ingredients.
--   3. NO VARIANTS. `is_variant` recipes are one-off LLM customizations written
--      by customizeMeal with no tags at all; they are never planning candidates.
--      (This predicate was added in 20260726000800 and MUST survive every later
--      rewrite of this function.)
--
-- One rules table drives everything, so adding a diet is one row rather than an
-- edit in six places. Diets are either REQUIRED-tag (vegetarian: the recipe must
-- carry the tag) or FORBIDDEN-tag (no_nuts: the recipe must not), and a diet may
-- have several forbidden rows.
--
-- Vocabulary note: recipes.dietary_tags say `contains_nuts` while
-- ingredients.allergens say `tree_nuts`. Both are mapped here rather than
-- renamed, so neither existing dataset has to be rewritten.

-- ---------------------------------------------------------------------------
-- The rules, as data. Both candidate_recipes (which filters the planning pool)
-- and diet_conflict (which guards the customize path, the one place
-- ingredients enter a week without passing through candidate_recipes) read
-- this table, so the two can never disagree about what a diet key means.
create table if not exists diet_rules (
  diet_key           text not null,
  required_tag       text,
  forbidden_tag      text,
  forbidden_allergen text
);

-- A plain PK can't work here: forbidden_tag is null for the required-tag diets
-- (vegetarian/vegan) and a PK column can't be null, and Postgres rejects
-- expressions inside a PRIMARY KEY. A unique index over the coalesced columns
-- gives the same idempotency for the `on conflict do nothing` below.
create unique index if not exists diet_rules_key
  on diet_rules (diet_key, coalesce(required_tag, ''), coalesce(forbidden_tag, ''));

insert into diet_rules (diet_key, required_tag, forbidden_tag, forbidden_allergen) values
  ('vegetarian',   'vegetarian', null,                 null),
  ('vegan',        'vegan',      null,                 null),
  ('pescatarian',  null,         'contains_pork',      null),
  ('pescatarian',  null,         'contains_beef',      null),
  ('pescatarian',  null,         'contains_poultry',   null),
  ('gluten_free',  null,         'contains_gluten',    'gluten'),
  ('dairy_free',   null,         'contains_dairy',     'dairy'),
  ('halal',        null,         'contains_pork',      null),
  ('kosher',       null,         'contains_pork',      null),
  ('kosher',       null,         'contains_shellfish', 'shellfish'),
  ('no_pork',      null,         'contains_pork',      null),
  ('no_beef',      null,         'contains_beef',      null),
  ('no_poultry',   null,         'contains_poultry',   null),
  ('no_shellfish', null,         'contains_shellfish', 'shellfish'),
  ('no_fish',      null,         'contains_fish',      'fish'),
  ('no_nuts',      null,         'contains_nuts',      'tree_nuts'),
  ('no_soy',       null,         'contains_soy',       'soy'),
  ('no_egg',       null,         'contains_egg',       'egg'),
  ('no_sesame',    null,         'contains_sesame',    'sesame')
on conflict do nothing;

-- Everyday words a household actually types, mapped to the token the data uses.
create table if not exists allergen_synonyms (
  word  text primary key,
  token text not null
);

insert into allergen_synonyms (word, token) values
  ('nuts',        'tree_nuts'),
  ('tree nuts',   'tree_nuts'),
  ('treenuts',    'tree_nuts'),
  ('peanut',      'tree_nuts'),
  ('peanuts',     'tree_nuts'),
  ('wheat',       'gluten'),
  ('milk',        'dairy'),
  ('eggs',        'egg'),
  ('soya',        'soy'),
  ('prawns',      'shellfish'),
  ('shrimp',      'shellfish'),
  ('sesame seed', 'sesame')
on conflict do nothing;

drop function if exists candidate_recipes(int, int, uuid);
create function candidate_recipes(
  p_window_days int default 28,
  p_limit int default 40,
  p_household_id uuid default null
)
returns table (
  id                    uuid,
  title                 text,
  cuisine_tag           text,
  time_minutes          int,
  description           text,
  toddler_variant_notes text,
  last_used_on          date,
  ingredients           text[],
  avg_rating            numeric,
  rating_count          int
)
language sql
stable
security invoker
set search_path = public
as $$
  with pref as (
    select
      -- Normalize on read so 'Vegetarian' / ' no_nuts ' from an LLM tool call
      -- still match. Writers also normalize; this is belt and braces.
      coalesce((
        select array_agg(lower(btrim(d)))
        from unnest(coalesce(hp.dietary_restrictions, '{}'::text[])) d
      ), '{}'::text[]) as diets,
      coalesce((
        select array_agg(lower(btrim(e)))
        from unnest(coalesce(hp.excluded_ingredients, '{}'::text[])) e
      ), '{}'::text[]) as excluded
    from (select 1) one
    left join household_preferences hp on hp.household_id = p_household_id
  ),
  -- Free-text exclusions are matched against ingredient names, aliases and
  -- allergen tokens. allergen_synonyms lets a household that types the everyday
  -- word ("nuts", "peanuts", "wheat") reach the token the data actually uses.
  excluded_terms as (
    select term from unnest((select excluded from pref)) term
    union
    select s.token
    from unnest((select excluded from pref)) term
    join allergen_synonyms s on s.word = term
  )
  select
    r.id,
    r.title,
    r.cuisine_tag,
    r.time_minutes,
    split_part(r.body_md, E'\n', 1) as description,
    r.toddler_variant_notes,
    r.last_used_on,
    coalesce(
      array_agg(distinct i.name_canonical)
        filter (where i.name_canonical is not null),
      '{}'
    ) as ingredients,
    round(avg(rr.rating), 1) as avg_rating,
    count(distinct rr.id)::int as rating_count
  from recipes r
  cross join pref
  left join recipe_ingredients ri on ri.recipe_id = r.id
  left join ingredients i on i.id = ri.ingredient_id
  left join recipe_ratings rr on rr.recipe_id = r.id
  -- One-off LLM customizations are never planning candidates (20260726000800).
  where coalesce(r.is_variant, false) = false
    and (r.last_used_on is null
     or r.last_used_on < current_date - (p_window_days || ' days')::interval)
    and not exists (
      select 1 from recipe_exclusions x
      where x.recipe_id = r.id
        and (p_household_id is null or x.household_id = p_household_id)
    )
    -- (1) FAIL CLOSED: a restricted household never sees an unclassified recipe.
    and (pref.diets = '{}'::text[] or coalesce(r.dietary_tags, '{}'::text[]) <> '{}'::text[])
    -- (2) Every required tag the household's diets demand is present.
    and not exists (
      select 1 from diet_rules ru
      where ru.diet_key = any(pref.diets)
        and ru.required_tag is not null
        and not (ru.required_tag = any(r.dietary_tags))
    )
    -- (3) No forbidden tag on the recipe.
    and not exists (
      select 1 from diet_rules ru
      where ru.diet_key = any(pref.diets)
        and ru.forbidden_tag is not null
        and ru.forbidden_tag = any(r.dietary_tags)
    )
    -- (4) ...and independently, no forbidden allergen on its ingredients, so a
    --     recipe whose curated tags are wrong is still caught.
    and not exists (
      select 1
      from diet_rules ru
      join recipe_ingredients ri3 on ri3.recipe_id = r.id
      join ingredients i3 on i3.id = ri3.ingredient_id
      where ru.diet_key = any(pref.diets)
        and ru.forbidden_allergen is not null
        and ru.forbidden_allergen = any(i3.allergens)
    )
    -- (5) Excluded ingredients: by canonical name, alias, or allergen token.
    and not exists (
      select 1
      from recipe_ingredients ri2
      join ingredients i2 on i2.id = ri2.ingredient_id
      where ri2.recipe_id = r.id
        and (
          lower(i2.name_canonical) in (select term from excluded_terms)
          or exists (
            select 1 from unnest(coalesce(i2.aliases, '{}')) a
            where lower(a) in (select term from excluded_terms)
          )
          or exists (
            select 1 from unnest(coalesce(i2.allergens, '{}')) g
            where lower(g) in (select term from excluded_terms)
          )
        )
    )
  group by r.id
  order by coalesce(r.last_used_on, '1970-01-01') asc, random()
  limit p_limit;
$$;

-- Match the repo's convention for the trigger_* helpers: nothing here is meant
-- to be reachable with the anon key over PostgREST.
revoke all on function candidate_recipes(int, int, uuid) from public, anon, authenticated;

-- Supporting indexes for the array containment above (the seq scan is fine on a
-- 58-recipe starter catalog, but this function is on the critical path of every
-- plan proposal and swap, and users are invited to add their own recipes).
create index if not exists recipes_dietary_tags_idx  on recipes    using gin (dietary_tags);
create index if not exists ingredients_allergens_idx on ingredients using gin (allergens);

-- ---------------------------------------------------------------------------
-- diet_conflict: does adding this ingredient break the household's rules?
--
-- customizeMeal is the ONE path where an ingredient enters a household's week
-- without passing through candidate_recipes: the model proposes ingredient
-- changes, they are written onto a variant recipe, and the plan item is
-- repointed at it. Until now the only thing standing between "add peanut
-- sauce" and a peanut-allergic household was prompt text — which ROADMAP
-- principle 3 explicitly says diet and allergy safety must never rely on.
--
-- Returns a human-readable reason, or null when the ingredient is fine.
--
-- SCOPE: this catches allergen-token and explicit-exclusion violations — the
-- safety-critical set. It cannot catch a vegetarian household being offered
-- bacon, because there is no allergen token for "meat"; the model is still
-- instructed about that, and the recipe itself was already diet-filtered when
-- it was chosen.
create or replace function diet_conflict(
  p_household_id uuid,
  p_ingredient text
)
returns text
language sql
stable
security invoker
set search_path = public
as $$
  with pref as (
    select
      coalesce((
        select array_agg(lower(btrim(d)))
        from unnest(coalesce(hp.dietary_restrictions, '{}'::text[])) d
      ), '{}'::text[]) as diets,
      coalesce((
        select array_agg(lower(btrim(e)))
        from unnest(coalesce(hp.excluded_ingredients, '{}'::text[])) e
      ), '{}'::text[]) as excluded
    from (select 1) one
    left join household_preferences hp on hp.household_id = p_household_id
  ),
  term as (select lower(btrim(p_ingredient)) as name),
  excluded_terms as (
    select t from unnest((select excluded from pref)) t
    union
    select s.token
    from unnest((select excluded from pref)) t
    join allergen_synonyms s on s.word = t
  ),
  -- The ingredient may not exist yet (the customize flow creates rows on the
  -- fly), in which case only the name-based checks below can fire.
  known as (
    select i.* from ingredients i, term
     where lower(i.name_canonical) = term.name
        or exists (
          select 1 from unnest(coalesce(i.aliases, '{}'::text[])) a
          where lower(a) = term.name
        )
  )
  select reason from (
    -- 1. The household named this ingredient (or one of its synonyms) directly.
    select format('%s is on the household''s avoid list', p_ingredient) as reason
     where (select name from term) in (select t from excluded_terms)
        or exists (
          select 1 from allergen_synonyms s, term
          where s.word = term.name and s.token in (select t from excluded_terms)
        )
        or exists (
          select 1 from known k
          where exists (
            select 1 from unnest(coalesce(k.allergens, '{}'::text[])) g
            where lower(g) in (select t from excluded_terms)
          )
        )
    union all
    -- 2. A known ingredient carries an allergen one of their diets forbids.
    select format(
      '%s contains %s, which the household''s %s rule forbids',
      p_ingredient, ru.forbidden_allergen, ru.diet_key
    )
      from known k
      join diet_rules ru on ru.forbidden_allergen = any(k.allergens)
      cross join pref
     where ru.diet_key = any(pref.diets)
  ) hits
  limit 1;
$$;

revoke all on function diet_conflict(uuid, text) from public, anon, authenticated;
