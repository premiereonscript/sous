-- Goodbye Fresh — recipe ratings + shopping-list generation.
--
-- recipe_ratings: per-recipe 1-5 preference (5 = best), one row per (recipe,
-- rater). Distinct from the per-meal `feedback` table (weekly recap tags) —
-- this is the durable "how much do we like this dish" signal the planner uses.
--
-- candidate_recipes is extended to surface avg_rating + rating_count so the
-- planner can favor 4-5★ and down-weight 1-2★ (down-weight, not ban — §8).
--
-- generate_shopping_list aggregates the week's ingredients into a persisted,
-- source-split list (SPEC §9.3 lock step), excluding free items (eggs).

-- ---------------------------------------------------------------------------
create table if not exists recipe_ratings (
  id            uuid primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  household_id  uuid not null references households(id) on delete cascade,
  recipe_id     uuid not null references recipes(id) on delete cascade,
  rater_user_id uuid references users(id) on delete set null,
  rating        int not null check (rating between 1 and 5),
  note          text,
  updated_at    timestamptz not null default now(),
  unique (recipe_id, rater_user_id)
);
create index if not exists recipe_ratings_recipe_id_idx on recipe_ratings (recipe_id);

alter table recipe_ratings enable row level security;
create policy hh_isolation on recipe_ratings
  for all using (household_id = app_household_id());

-- ---------------------------------------------------------------------------
-- candidate_recipes v2: add avg_rating + rating_count.
drop function if exists candidate_recipes(int, int);
create function candidate_recipes(
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
  where r.last_used_on is null
     or r.last_used_on < current_date - (p_window_days || ' days')::interval
  group by r.id
  order by coalesce(r.last_used_on, '1970-01-01') asc, random()
  limit p_limit;
$$;

-- ---------------------------------------------------------------------------
-- generate_shopping_list: (re)build the persisted list for a plan and return it.
create or replace function generate_shopping_list(p_plan_id uuid)
returns table (ingredient text, quantity numeric, unit text, source text)
language plpgsql
as $$
declare
  v_list_id uuid;
begin
  delete from shopping_lists where plan_id = p_plan_id; -- cascades to items
  insert into shopping_lists (plan_id) values (p_plan_id) returning id into v_list_id;

  insert into shopping_list_items (list_id, ingredient_id, quantity, unit, source)
  select v_list_id, agg.ingredient_id, agg.qty, agg.unit, agg.source
  from (
    select
      ri.ingredient_id,
      sum(ri.quantity) as qty,
      ri.unit,
      case
        when i.source_hint = 'either' then
          case when extract(month from current_date)::int = any (i.seasonal_months)
               then 'farmers_market' else 'grocery' end
        when i.source_hint is null then 'grocery'
        else i.source_hint
      end as source
    from meal_plan_items mpi
    join recipe_ingredients ri on ri.recipe_id = mpi.recipe_id
    join ingredients i on i.id = ri.ingredient_id
    where mpi.plan_id = p_plan_id
      and not i.is_free
      and coalesce(ri.optional, false) = false
    group by ri.ingredient_id, ri.unit, i.source_hint, i.seasonal_months
  ) agg;

  return query
  select i.name_canonical, sli.quantity, sli.unit, sli.source
  from shopping_list_items sli
  join ingredients i on i.id = sli.ingredient_id
  where sli.list_id = v_list_id
  order by sli.source, i.name_canonical;
end;
$$;
