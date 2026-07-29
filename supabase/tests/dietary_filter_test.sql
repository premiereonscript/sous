-- pgTAP tests for the dietary/allergy hard filter (T4) in candidate_recipes.
-- Runs via `supabase test db`, inside a rolled-back transaction.

begin;
select plan(8);

-- ---------------------------------------------------------------------------
-- Fixtures: two never-used recipes — one vegetarian (tofu, soy), one pork.
insert into ingredients (id, name_canonical, allergens) values
  ('a0000000-0000-0000-0000-0000000000f1', 'test_tofu', '{soy}'),
  ('a0000000-0000-0000-0000-0000000000f2', 'test_pork', '{}');

insert into recipes (id, title, cuisine_tag, source, base_servings, dietary_tags) values
  ('b0000000-0000-0000-0000-0000000000f1', 'Test Veg',  'other', 'curated', 4, '{vegetarian,vegan,contains_soy}'),
  ('b0000000-0000-0000-0000-0000000000f2', 'Test Pork', 'other', 'curated', 4, '{contains_pork}');

insert into recipe_ingredients (recipe_id, ingredient_id, quantity, unit) values
  ('b0000000-0000-0000-0000-0000000000f1', 'a0000000-0000-0000-0000-0000000000f1', 1, 'block'),
  ('b0000000-0000-0000-0000-0000000000f2', 'a0000000-0000-0000-0000-0000000000f2', 1, 'lb');

-- Households with different constraints.
insert into households (id, name) values
  ('c0000000-0000-0000-0000-0000000000fn', 'None'),
  ('c0000000-0000-0000-0000-0000000000fv', 'Veg'),
  ('c0000000-0000-0000-0000-0000000000fx', 'ExclName'),
  ('c0000000-0000-0000-0000-0000000000fs', 'ExclAllergen');
insert into household_preferences (household_id, dietary_restrictions, excluded_ingredients) values
  ('c0000000-0000-0000-0000-0000000000fn', '{}',           '{}'),
  ('c0000000-0000-0000-0000-0000000000fv', '{vegetarian}', '{}'),
  ('c0000000-0000-0000-0000-0000000000fx', '{}',           '{test_pork}'),
  ('c0000000-0000-0000-0000-0000000000fs', '{}',           '{soy}');

-- ---------------------------------------------------------------------------
-- Helper expectation: candidate_recipes returns our two test recipes among a
-- household's options (subject to filtering). We check presence of each title.

-- 1 & 2. No restrictions: both recipes are candidates.
select is(
  (select count(*)::int from candidate_recipes(28, 40, 'c0000000-0000-0000-0000-0000000000fn')
     where title in ('Test Veg', 'Test Pork')),
  2, 'no restrictions: both test recipes are candidates');

-- 3 & 4. Vegetarian household: the pork recipe is filtered out, veg stays.
select is(
  (select count(*)::int from candidate_recipes(28, 40, 'c0000000-0000-0000-0000-0000000000fv')
     where title = 'Test Pork'),
  0, 'vegetarian: pork recipe is hard-filtered out');
select is(
  (select count(*)::int from candidate_recipes(28, 40, 'c0000000-0000-0000-0000-0000000000fv')
     where title = 'Test Veg'),
  1, 'vegetarian: vegetarian recipe remains');

-- 5. Excluded ingredient by name: pork recipe dropped.
select is(
  (select count(*)::int from candidate_recipes(28, 40, 'c0000000-0000-0000-0000-0000000000fx')
     where title = 'Test Pork'),
  0, 'excluded_ingredients by name: pork recipe dropped');

-- 6. Excluded by allergen tag ('soy' matches the tofu ingredient's allergen):
--    the vegetarian recipe is dropped for a soy-avoiding household.
select is(
  (select count(*)::int from candidate_recipes(28, 40, 'c0000000-0000-0000-0000-0000000000fs')
     where title = 'Test Veg'),
  0, 'excluded_ingredients by allergen: soy drops the tofu recipe');

-- 7 & 8. The seeded catalog leaves a vegan household a usable pool (T18):
--    at least 6 vegan mains, and no pork dish sneaks in.
insert into households (id, name) values ('c0000000-0000-0000-0000-0000000000fw', 'Vegan');
insert into household_preferences (household_id, dietary_restrictions) values
  ('c0000000-0000-0000-0000-0000000000fw', '{vegan}');
select cmp_ok(
  (select count(*)::int from candidate_recipes(28, 40, 'c0000000-0000-0000-0000-0000000000fw')),
  '>=', 6, 'vegan household has at least 6 candidate recipes (T18 catalog balance)');
select is(
  (select count(*)::int from candidate_recipes(28, 40, 'c0000000-0000-0000-0000-0000000000fw')
     where title = 'Carnitas Bowls'),
  0, 'vegan household never sees the pork carnitas');

select * from finish();
rollback;
