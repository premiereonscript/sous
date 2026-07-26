-- The rotation window in candidate_recipes() (exclude anything used in the
-- last N days) has never had anything to filter on: recipes.last_used_on and
-- times_used are declared in the schema but nothing has ever written to them.
-- Result: the candidate pool never shrinks, and the planner (which is told to
-- favor rated dishes) keeps re-picking the same few recipes every week.
--
-- Called from proposePlan (one row per chosen dish) and swapMeal (one row)
-- right after the pick is written to meal_plan_items, so "used" means
-- "assigned to a day," not "explicitly locked" — most weeks are never
-- explicitly locked in practice.
create or replace function mark_recipes_used(p_updates jsonb)
returns void
language sql
as $$
  update recipes r
  set last_used_on = u.day::date,
      times_used = r.times_used + 1
  from jsonb_to_recordset(p_updates) as u(id uuid, day date)
  where r.id = u.id;
$$;
