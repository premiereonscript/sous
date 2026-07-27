-- Recipe customization ("add meat to the pesto pasta", "swap cream for coconut
-- milk"): rather than mutate the shared curated recipe (which would change it
-- for every future week and past plan) or throw the dish away with a swap, we
-- fork a one-off VARIANT recipe with the tweak applied, and repoint just this
-- week's plan item to it.
--
-- Variants must never resurface as a future candidate pick, so flag them and
-- filter them out of candidate_recipes.
alter table recipes add column if not exists is_variant boolean not null default false;
alter table recipes add column if not exists parent_recipe_id uuid references recipes(id) on delete set null;

-- candidate_recipes v4: same signature/return as v3, now also excluding variants.
create or replace function candidate_recipes(
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
  left join recipe_ingredients ri on ri.recipe_id = r.id
  left join ingredients i on i.id = ri.ingredient_id
  left join recipe_ratings rr on rr.recipe_id = r.id
  where coalesce(r.is_variant, false) = false
    and (r.last_used_on is null
     or r.last_used_on < current_date - (p_window_days || ' days')::interval)
    and not exists (
      select 1 from recipe_exclusions x
      where x.recipe_id = r.id
        and (p_household_id is null or x.household_id = p_household_id)
    )
  group by r.id
  order by coalesce(r.last_used_on, '1970-01-01') asc, random()
  limit p_limit;
$$;
