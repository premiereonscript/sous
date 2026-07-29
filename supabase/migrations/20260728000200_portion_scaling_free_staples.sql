-- Sous — T3 (portion scaling) + T5 (per-household free staples).
--
-- Rewrites generate_shopping_list so quantities scale to the household's size
-- instead of hardcoding the original family's amounts, and so "we already have
-- this, don't buy it" is a per-household fact rather than a global flag.
--
-- Scaling: each recipe carries base_servings (T2). We multiply its ingredient
-- quantities by (servings_needed / base_servings), where servings_needed =
-- adults + kids aged >= 12 months (babies under 1 don't eat dinner). Falls back
-- to 4 when a household has no preferences row yet.
--
-- Free staples: household_preferences.free_staples lists ingredient names the
-- household gets for free / already keeps, which are omitted from the list. This
-- replaces the global ingredients.is_free flag (eggs = the author's backyard
-- chickens), which we now retire so a fresh clone gets eggs ON its list. The
-- author's household keeps eggs off via free_staples = {eggs} (set in T1).

-- Retire the global free-ingredient assumption; exclusion is now per-household.
update ingredients set is_free = false where is_free = true;

create or replace function generate_shopping_list(p_plan_id uuid)
returns table (ingredient text, quantity numeric, unit text, source text)
language plpgsql
as $$
#variable_conflict use_column
declare
  v_list_id      uuid;
  v_household_id uuid;
  v_servings     numeric;
  v_free         text[];
begin
  select mp.household_id into v_household_id
    from meal_plans mp where mp.id = p_plan_id;

  -- servings_needed = adults + kids >= 12 months old.
  select hp.adults
       + coalesce((
           select count(*)
           from jsonb_array_elements(hp.kids) k
           where (k->>'age_months')::int >= 12
         ), 0)
    into v_servings
  from household_preferences hp
  where hp.household_id = v_household_id;
  v_servings := coalesce(v_servings, 4);
  if v_servings < 1 then v_servings := 1; end if;

  select coalesce(hp.free_staples, '{}')
    into v_free
  from household_preferences hp
  where hp.household_id = v_household_id;
  v_free := coalesce(v_free, '{}');

  delete from shopping_lists where plan_id = p_plan_id; -- cascades to items
  insert into shopping_lists (plan_id) values (p_plan_id) returning id into v_list_id;

  insert into shopping_list_items (list_id, ingredient_id, quantity, unit, source)
  select v_list_id, agg.ingredient_id, agg.qty, agg.unit, agg.source
  from (
    select
      ri.ingredient_id,
      round(sum(ri.quantity * (v_servings / nullif(r.base_servings, 0)))::numeric, 2) as qty,
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
    join recipes r            on r.id = mpi.recipe_id
    join ingredients i        on i.id = ri.ingredient_id
    where mpi.plan_id = p_plan_id
      and not (i.name_canonical = any (v_free))    -- per-household free staples
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
