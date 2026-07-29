-- pgTAP tests for the generalization work (portion scaling + per-household free
-- staples). Runs via `supabase test db` (local stack / CI), inside a rolled-back
-- transaction. Validates the SQL that unit tests can't reach.

begin;
select plan(4);

-- ---------------------------------------------------------------------------
-- Fixtures: one shared recipe (base_servings = 4) whose only bought ingredient
-- is "test_eggs" (4 each), used by three households with different make-ups.
insert into ingredients (id, name_canonical, unit_default, source_hint, is_free)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'test_eggs', 'each', 'grocery', false);

insert into recipes (id, title, cuisine_tag, source, base_servings)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'Test Egg Bake', 'other', 'curated', 4);

insert into recipe_ingredients (recipe_id, ingredient_id, quantity, unit)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001', 4, 'each');

-- Household A: 2 adults, no kids, no free staples.
insert into households (id, name) values ('cccccccc-0000-0000-0000-00000000000a', 'A');
insert into household_preferences (household_id, adults, kids, free_staples)
values ('cccccccc-0000-0000-0000-00000000000a', 2, '[]'::jsonb, '{}');
insert into meal_plans (id, household_id, week_of)
values ('dddddddd-0000-0000-0000-00000000000a', 'cccccccc-0000-0000-0000-00000000000a', date '2026-08-03');
insert into meal_plan_items (plan_id, day, recipe_id)
values ('dddddddd-0000-0000-0000-00000000000a', date '2026-08-03', 'bbbbbbbb-0000-0000-0000-000000000001');

-- Household B: 2 adults, no kids, but eggs are a free staple.
insert into households (id, name) values ('cccccccc-0000-0000-0000-00000000000b', 'B');
insert into household_preferences (household_id, adults, kids, free_staples)
values ('cccccccc-0000-0000-0000-00000000000b', 2, '[]'::jsonb, '{test_eggs}');
insert into meal_plans (id, household_id, week_of)
values ('dddddddd-0000-0000-0000-00000000000b', 'cccccccc-0000-0000-0000-00000000000b', date '2026-08-03');
insert into meal_plan_items (plan_id, day, recipe_id)
values ('dddddddd-0000-0000-0000-00000000000b', date '2026-08-03', 'bbbbbbbb-0000-0000-0000-000000000001');

-- Household C: 2 adults + a 30-month toddler + a 6-month baby.
insert into households (id, name) values ('cccccccc-0000-0000-0000-00000000000c', 'C');
insert into household_preferences (household_id, adults, kids, free_staples)
values ('cccccccc-0000-0000-0000-00000000000c', 2,
        '[{"age_months":30},{"age_months":6}]'::jsonb, '{}');
insert into meal_plans (id, household_id, week_of)
values ('dddddddd-0000-0000-0000-00000000000c', 'cccccccc-0000-0000-0000-00000000000c', date '2026-08-03');
insert into meal_plan_items (plan_id, day, recipe_id)
values ('dddddddd-0000-0000-0000-00000000000c', date '2026-08-03', 'bbbbbbbb-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- 1. A fresh (non-chicken) household gets eggs ON the list — the old code
--    silently dropped them for everyone.
select isnt(
  (select quantity from generate_shopping_list('dddddddd-0000-0000-0000-00000000000a')
     where ingredient = 'test_eggs'),
  null,
  'default household: eggs appear on the shopping list'
);

-- 2. ...scaled to household size: 4 (base 4 servings) * (2 adults / 4) = 2.
select is(
  (select quantity from generate_shopping_list('dddddddd-0000-0000-0000-00000000000a')
     where ingredient = 'test_eggs'),
  2::numeric,
  'default 2-adult household: quantity scaled to 2 of base 4'
);

-- 3. A household that flags eggs as a free staple has them omitted.
select is(
  (select count(*)::int from generate_shopping_list('dddddddd-0000-0000-0000-00000000000b')
     where ingredient = 'test_eggs'),
  0,
  'free-staple eggs are omitted from the list'
);

-- 4. Kids >= 12mo count toward servings, babies < 12mo do not:
--    2 adults + 1 toddler = 3 servings; 4 * (3/4) = 3.
select is(
  (select quantity from generate_shopping_list('dddddddd-0000-0000-0000-00000000000c')
     where ingredient = 'test_eggs'),
  3::numeric,
  'toddler counts toward servings, baby under 1 does not (qty 3)'
);

select * from finish();
rollback;
