-- One-time backfill: the rotation fix (mark_recipes_used) only stamps
-- last_used_on going forward, but 10 weeks / 45 dinners of history were served
-- while the column sat null. Without seeding it, the very next plan would still
-- see a full pool and could re-pick a recently-served dish (e.g. Baked Ziti,
-- which ran 8 of the last 10 weeks). Seed last_used_on/times_used from the
-- actual meal_plan_items history so the rotation window has memory immediately.
update recipes r
set last_used_on = sub.last_day,
    times_used   = sub.uses
from (
  select recipe_id, max(day)::date as last_day, count(*)::int as uses
  from meal_plan_items
  group by recipe_id
) sub
where r.id = sub.recipe_id;
