-- Sous — T4: server-side dietary/allergy hard filter on the candidate pool.
--
-- candidate_recipes v4: same signature + return shape as v3, but when a
-- p_household_id is passed it also drops any recipe that violates the
-- household's dietary_restrictions or excluded_ingredients (read from
-- household_preferences). This is a HARD filter: diet + allergy safety must not
-- depend on the LLM honoring a soft request in a prompt.
--
-- dietary_restrictions use canonical keys (set by onboarding):
--   vegetarian, vegan, pescatarian, gluten_free, dairy_free, halal, kosher,
--   no_pork, no_beef, no_poultry, no_shellfish, no_fish, no_nuts, no_soy, no_egg
-- excluded_ingredients are matched by ingredient name OR by allergen tag, so
-- "peanuts" / "shellfish" / a specific disliked ingredient all work.

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
as $$
  with pref as (
    select
      coalesce(hp.dietary_restrictions, '{}') as diets,
      coalesce(hp.excluded_ingredients, '{}') as excluded
    from (select 1) one
    left join household_preferences hp on hp.household_id = p_household_id
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
  where (r.last_used_on is null
     or r.last_used_on < current_date - (p_window_days || ' days')::interval)
    and not exists (
      select 1 from recipe_exclusions x
      where x.recipe_id = r.id
        and (p_household_id is null or x.household_id = p_household_id)
    )
    -- Dietary hard filter. Each line is a no-op unless the household set that
    -- restriction; then the recipe must satisfy it to remain in the pool.
    and (not ('vegetarian'   = any(pref.diets)) or 'vegetarian' = any(r.dietary_tags))
    and (not ('vegan'        = any(pref.diets)) or 'vegan'      = any(r.dietary_tags))
    and (not ('pescatarian'  = any(pref.diets)) or not (r.dietary_tags && array['contains_pork','contains_beef','contains_poultry']))
    and (not ('gluten_free'  = any(pref.diets)) or not ('contains_gluten'    = any(r.dietary_tags)))
    and (not ('dairy_free'   = any(pref.diets)) or not ('contains_dairy'     = any(r.dietary_tags)))
    and (not ('halal'        = any(pref.diets)) or not ('contains_pork'      = any(r.dietary_tags)))
    and (not ('kosher'       = any(pref.diets)) or not (r.dietary_tags && array['contains_pork','contains_shellfish']))
    and (not ('no_pork'      = any(pref.diets)) or not ('contains_pork'      = any(r.dietary_tags)))
    and (not ('no_beef'      = any(pref.diets)) or not ('contains_beef'      = any(r.dietary_tags)))
    and (not ('no_poultry'   = any(pref.diets)) or not ('contains_poultry'   = any(r.dietary_tags)))
    and (not ('no_shellfish' = any(pref.diets)) or not ('contains_shellfish' = any(r.dietary_tags)))
    and (not ('no_fish'      = any(pref.diets)) or not ('contains_fish'      = any(r.dietary_tags)))
    and (not ('no_nuts'      = any(pref.diets)) or not ('contains_nuts'      = any(r.dietary_tags)))
    and (not ('no_soy'       = any(pref.diets)) or not ('contains_soy'       = any(r.dietary_tags)))
    and (not ('no_egg'       = any(pref.diets)) or not ('contains_egg'       = any(r.dietary_tags)))
    -- Excluded ingredients: drop recipes using an avoided ingredient (matched
    -- by canonical name or by allergen tag).
    and not exists (
      select 1
      from recipe_ingredients ri2
      join ingredients i2 on i2.id = ri2.ingredient_id
      where ri2.recipe_id = r.id
        and (i2.name_canonical = any(pref.excluded) or i2.allergens && pref.excluded)
    )
  group by r.id
  order by coalesce(r.last_used_on, '1970-01-01') asc, random()
  limit p_limit;
$$;
