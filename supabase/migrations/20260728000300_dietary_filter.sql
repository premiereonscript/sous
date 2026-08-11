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
        from unnest(coalesce(hp.dietary_restrictions, '{}')) d
      ), '{}') as diets,
      coalesce((
        select array_agg(lower(btrim(e)))
        from unnest(coalesce(hp.excluded_ingredients, '{}')) e
      ), '{}') as excluded
    from (select 1) one
    left join household_preferences hp on hp.household_id = p_household_id
  ),
  -- diet_key -> what the recipe must carry / must not carry / must not contain.
  rules(diet_key, required_tag, forbidden_tag, forbidden_allergen) as (
    values
      ('vegetarian',   'vegetarian', null::text,           null::text),
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
  ),
  -- Free-text exclusions are matched against ingredient names, aliases and
  -- allergen tokens. The synonym rows let a household that types the everyday
  -- word ("nuts", "peanuts", "wheat") reach the token the data actually uses.
  excluded_terms as (
    select term from unnest((select excluded from pref)) term
    union
    select syn.token
    from unnest((select excluded from pref)) term
    join (values
      ('nuts',        'tree_nuts'),
      ('tree nuts',   'tree_nuts'),
      ('treenuts',    'tree_nuts'),
      ('peanut',      'tree_nuts'),
      ('peanuts',     'tree_nuts'),
      ('wheat',       'gluten'),
      ('milk',        'dairy'),
      ('eggs',        'egg'),
      ('fish',        'fish'),
      ('soya',        'soy'),
      ('prawns',      'shellfish'),
      ('shrimp',      'shellfish'),
      ('sesame seed', 'sesame')
    ) as syn(word, token) on syn.word = term
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
    and (pref.diets = '{}' or r.dietary_tags <> '{}')
    -- (2) Every required tag the household's diets demand is present.
    and not exists (
      select 1 from rules ru
      where ru.diet_key = any(pref.diets)
        and ru.required_tag is not null
        and not (ru.required_tag = any(r.dietary_tags))
    )
    -- (3) No forbidden tag on the recipe.
    and not exists (
      select 1 from rules ru
      where ru.diet_key = any(pref.diets)
        and ru.forbidden_tag is not null
        and ru.forbidden_tag = any(r.dietary_tags)
    )
    -- (4) ...and independently, no forbidden allergen on its ingredients, so a
    --     recipe whose curated tags are wrong is still caught.
    and not exists (
      select 1
      from rules ru
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
