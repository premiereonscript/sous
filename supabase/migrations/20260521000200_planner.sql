-- Goodbye Fresh — planner candidate selection (SPEC §9.4 rotation query).
-- Returns rotation-eligible recipes (not used in the last `p_window_days`),
-- each with its short description and the set of ingredient names so the model
-- can reason about cuisine spread and ingredient overlap (cost).

create or replace function candidate_recipes(
  p_window_days int default 28,
  p_limit int default 40
)
returns table (
  id                    uuid,
  title                 text,
  cuisine_tag           text,
  time_minutes          int,
  description           text,
  toddler_variant_notes text,
  last_used_on          date,
  ingredients           text[]
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
    ) as ingredients
  from recipes r
  left join recipe_ingredients ri on ri.recipe_id = r.id
  left join ingredients i on i.id = ri.ingredient_id
  where r.last_used_on is null
     or r.last_used_on < current_date - (p_window_days || ' days')::interval
  group by r.id
  order by coalesce(r.last_used_on, '1970-01-01') asc, random()
  limit p_limit;
$$;
