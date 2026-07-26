-- "Never suggest this again." Distinct from a 1-star rating (which only
-- down-weights): an exclusion hard-removes a recipe from the candidate pool.
-- Set when the household tells Sous to stop suggesting a dish.
create table if not exists recipe_exclusions (
  household_id uuid not null references households(id) on delete cascade,
  recipe_id    uuid not null references recipes(id) on delete cascade,
  reason       text,
  created_at   timestamptz not null default now(),
  primary key (household_id, recipe_id)
);

alter table recipe_exclusions enable row level security;
create policy hh_isolation on recipe_exclusions
  for all using (household_id = app_household_id());

-- ---------------------------------------------------------------------------
-- candidate_recipes v3: same signature/return as v2 plus an optional
-- p_household_id. When passed, recipes that household has excluded are dropped
-- from the pool. Defaulted to null so any existing positional/named callers
-- keep working unchanged.
drop function if exists candidate_recipes(int, int);
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
  where (r.last_used_on is null
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
