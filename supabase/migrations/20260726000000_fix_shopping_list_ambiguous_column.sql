-- Fix generate_shopping_list: the RETURNS TABLE OUT-parameter names
-- (ingredient, quantity, unit, source) collide with real column names of the
-- same name referenced in the function body. PL/pgSQL resolves that as an
-- ambiguous variable-vs-column reference, so every call has thrown
-- "column reference \"quantity\" is ambiguous" (42702) since day one — the
-- app swallows the RPC error and silently renders an empty shopping list.
--
-- `#variable_conflict use_column` tells PL/pgSQL to prefer the table column
-- whenever a name collides with one of this function's own OUT parameters,
-- with no change to the function's signature or callers.
create or replace function generate_shopping_list(p_plan_id uuid)
returns table (ingredient text, quantity numeric, unit text, source text)
language plpgsql
as $$
#variable_conflict use_column
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
