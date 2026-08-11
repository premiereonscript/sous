-- pgTAP tests for the dietary/allergy hard filter (T4) in candidate_recipes.
-- Runs via `supabase test db`, inside a rolled-back transaction.
--
-- NOTE ON LIMITS: candidate_recipes orders by `coalesce(last_used_on, epoch),
-- random()` and truncates to p_limit. On a fresh stack every seeded recipe has
-- last_used_on = null, so the ordering is pure random() over the whole catalog.
-- Any assertion that a fixture is PRESENT must therefore pass a limit larger
-- than the catalog, or it fails intermittently for no code reason. Absence
-- assertions are safe at any limit.

begin;
select plan(17);

-- ---------------------------------------------------------------------------
-- Fixtures: never-used recipes covering each filter path.
insert into ingredients (id, name_canonical, allergens) values
  ('a0000000-0000-0000-0000-0000000000f1', 'test_tofu',   '{soy}'),
  ('a0000000-0000-0000-0000-0000000000f2', 'test_pork',   '{}'),
  ('a0000000-0000-0000-0000-0000000000f3', 'test_cashew', '{tree_nuts}'),
  ('a0000000-0000-0000-0000-0000000000f4', 'test_plain',  '{}');

insert into recipes (id, title, cuisine_tag, source, base_servings, dietary_tags) values
  ('b0000000-0000-0000-0000-0000000000f1', 'Test Veg',  'other', 'curated', 4, '{vegetarian,vegan,contains_soy}'),
  ('b0000000-0000-0000-0000-0000000000f2', 'Test Pork', 'other', 'curated', 4, '{contains_pork}'),
  -- Deliberately MIS-TAGGED: carries no contains_nuts even though its
  -- ingredient is a tree nut. The filter must catch it via the ingredient.
  ('b0000000-0000-0000-0000-0000000000f3', 'Test Mistagged Nut', 'other', 'curated', 4, '{vegetarian}'),
  -- UNCLASSIFIED: no dietary_tags at all, like an LLM variant or a
  -- user-added recipe. Must never reach a household with a restriction.
  ('b0000000-0000-0000-0000-0000000000f4', 'Test Untagged', 'other', 'curated', 4, '{}');

-- A variant recipe: created by the customize flow, never a planning candidate.
insert into recipes (id, title, cuisine_tag, source, base_servings, dietary_tags, is_variant) values
  ('b0000000-0000-0000-0000-0000000000f5', 'Test Variant', 'other', 'curated', 4, '{vegetarian,vegan}', true);

insert into recipe_ingredients (recipe_id, ingredient_id, quantity, unit) values
  ('b0000000-0000-0000-0000-0000000000f1', 'a0000000-0000-0000-0000-0000000000f1', 1, 'block'),
  ('b0000000-0000-0000-0000-0000000000f2', 'a0000000-0000-0000-0000-0000000000f2', 1, 'lb'),
  ('b0000000-0000-0000-0000-0000000000f3', 'a0000000-0000-0000-0000-0000000000f3', 1, 'cup'),
  ('b0000000-0000-0000-0000-0000000000f4', 'a0000000-0000-0000-0000-0000000000f4', 1, 'each'),
  ('b0000000-0000-0000-0000-0000000000f5', 'a0000000-0000-0000-0000-0000000000f4', 1, 'each');

-- Households with different constraints.
insert into households (id, name) values
  ('c0000000-0000-0000-0000-0000000000fn', 'None'),
  ('c0000000-0000-0000-0000-0000000000fv', 'Veg'),
  ('c0000000-0000-0000-0000-0000000000fx', 'ExclName'),
  ('c0000000-0000-0000-0000-0000000000fs', 'ExclAllergen'),
  ('c0000000-0000-0000-0000-0000000000fk', 'NutAllergy'),
  ('c0000000-0000-0000-0000-0000000000fp', 'NutWordAllergy');
insert into household_preferences (household_id, dietary_restrictions, excluded_ingredients) values
  ('c0000000-0000-0000-0000-0000000000fn', '{}',           '{}'),
  ('c0000000-0000-0000-0000-0000000000fv', '{vegetarian}', '{}'),
  ('c0000000-0000-0000-0000-0000000000fx', '{}',           '{test_pork}'),
  ('c0000000-0000-0000-0000-0000000000fs', '{}',           '{soy}'),
  ('c0000000-0000-0000-0000-0000000000fk', '{no_nuts}',    '{}'),
  -- The everyday word, not the token the data uses ('tree_nuts').
  ('c0000000-0000-0000-0000-0000000000fp', '{}',           '{nuts}');

-- ---------------------------------------------------------------------------
-- 1. No restrictions: both basic test recipes are candidates.
select is(
  (select count(*)::int from candidate_recipes(28, 1000, 'c0000000-0000-0000-0000-0000000000fn')
     where title in ('Test Veg', 'Test Pork')),
  2, 'no restrictions: both test recipes are candidates');

-- 2 & 3. Vegetarian household: the pork recipe is filtered out, veg stays.
select is(
  (select count(*)::int from candidate_recipes(28, 1000, 'c0000000-0000-0000-0000-0000000000fv')
     where title = 'Test Pork'),
  0, 'vegetarian: pork recipe is hard-filtered out');
select is(
  (select count(*)::int from candidate_recipes(28, 1000, 'c0000000-0000-0000-0000-0000000000fv')
     where title = 'Test Veg'),
  1, 'vegetarian: vegetarian recipe remains');

-- 4. Excluded ingredient by name: pork recipe dropped.
select is(
  (select count(*)::int from candidate_recipes(28, 1000, 'c0000000-0000-0000-0000-0000000000fx')
     where title = 'Test Pork'),
  0, 'excluded_ingredients by name: pork recipe dropped');

-- 5. Excluded by allergen tag ('soy' matches the tofu ingredient's allergen).
select is(
  (select count(*)::int from candidate_recipes(28, 1000, 'c0000000-0000-0000-0000-0000000000fs')
     where title = 'Test Veg'),
  0, 'excluded_ingredients by allergen: soy drops the tofu recipe');

-- 6. REGRESSION (20260726000800): a variant recipe is never a candidate. The
--    v5 rewrite dropped this predicate; every LLM customization re-entered the
--    planning pool, carrying no dietary_tags.
select is(
  (select count(*)::int from candidate_recipes(28, 1000, 'c0000000-0000-0000-0000-0000000000fn')
     where title = 'Test Variant'),
  0, 'is_variant recipes are never planning candidates');

-- 7 & 8. FAIL CLOSED: an unclassified recipe is safe for nobody with a
--    restriction, but still fine for a household with none.
select is(
  (select count(*)::int from candidate_recipes(28, 1000, 'c0000000-0000-0000-0000-0000000000fn')
     where title = 'Test Untagged'),
  1, 'unrestricted household still sees an untagged recipe');
select is(
  (select count(*)::int from candidate_recipes(28, 1000, 'c0000000-0000-0000-0000-0000000000fv')
     where title = 'Test Untagged'),
  0, 'restricted household never sees an UNCLASSIFIED recipe (fail closed)');

-- 9. Two independent sources: a recipe mis-tagged at the recipe level is still
--    caught by its ingredient allergens.
select is(
  (select count(*)::int from candidate_recipes(28, 1000, 'c0000000-0000-0000-0000-0000000000fk')
     where title = 'Test Mistagged Nut'),
  0, 'no_nuts catches a recipe whose contains_nuts tag is missing');

-- 10. Vocabulary bridge: the recipe tag says contains_nuts, the ingredient says
--     tree_nuts, and the household typed the everyday word "nuts".
select is(
  (select count(*)::int from candidate_recipes(28, 1000, 'c0000000-0000-0000-0000-0000000000fp')
     where title = 'Test Mistagged Nut'),
  0, 'excluding the word "nuts" reaches the tree_nuts allergen token');

-- 11. A null household id means no filtering, and must not error.
select cmp_ok(
  (select count(*)::int from candidate_recipes(28, 1000, null)),
  '>', 0, 'a null household id returns an unfiltered pool');

-- 12 & 13. The seeded catalog leaves a vegan household a usable pool (T18):
--     at least 6 vegan mains, and no pork dish sneaks in.
insert into households (id, name) values ('c0000000-0000-0000-0000-0000000000fw', 'Vegan');
insert into household_preferences (household_id, dietary_restrictions) values
  ('c0000000-0000-0000-0000-0000000000fw', '{vegan}');
select cmp_ok(
  (select count(*)::int from candidate_recipes(28, 1000, 'c0000000-0000-0000-0000-0000000000fw')),
  '>=', 6, 'vegan household has at least 6 candidate recipes (T18 catalog balance)');
select is(
  (select count(*)::int from candidate_recipes(28, 1000, 'c0000000-0000-0000-0000-0000000000fw')
     where title = 'Carnitas Bowls'),
  0, 'vegan household never sees the pork carnitas');

-- ---------------------------------------------------------------------------
-- 14-17. diet_conflict guards the customize path — the one place an ingredient
--    reaches a household's week without going through candidate_recipes.
select ok(
  diet_conflict('c0000000-0000-0000-0000-0000000000fk', 'test_cashew') is not null,
  'no_nuts household: adding a tree-nut ingredient is refused');

select ok(
  diet_conflict('c0000000-0000-0000-0000-0000000000fp', 'test_cashew') is not null,
  'a household excluding the word "nuts" is protected from a tree_nuts ingredient');

select ok(
  diet_conflict('c0000000-0000-0000-0000-0000000000fx', 'test_pork') is not null,
  'an explicitly excluded ingredient is refused by name');

select ok(
  diet_conflict('c0000000-0000-0000-0000-0000000000fn', 'test_cashew') is null,
  'a household with no restrictions can add anything');

select * from finish();
rollback;
