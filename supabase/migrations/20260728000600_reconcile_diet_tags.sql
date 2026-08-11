-- Sous — reconcile recipe dietary_tags against ingredient allergens.
--
-- Runs LAST of the 20260728* set, after every seed migration (including the
-- plant-based mains in ...000400), so it covers the whole catalog rather than
-- only the rows that existed when the hand-written tags were applied.
--
-- Everything upstream is hand-maintained: recipes carry curated `contains_*`
-- tags, ingredients carry `allergens`. Two separate lists written by hand
-- drift, and this one had: 'Vegetable Lo Mein' was tagged {vegetarian,vegan,…}
-- while its own 'lo mein noodles' carry {gluten,egg} — which would have served
-- it to an egg-allergic household and mislabeled it vegan.
--
-- Rather than fix that one row and wait for the next drift, DERIVE the tags
-- from the ingredient data. These statements are idempotent and safe to re-run,
-- and they make ingredients.allergens the source of truth for anything the
-- allergy filter depends on. candidate_recipes still checks both independently,
-- so a recipe whose curated tags are wrong is caught by its ingredients.
--
-- Vocabulary note: ingredients say 'tree_nuts', recipes say 'contains_nuts'.
-- Mapped here rather than renaming either dataset.

-- 1. Add any contains_* tag implied by an ingredient's allergens.
update recipes r
   set dietary_tags = (
     select coalesce(array_agg(distinct t), '{}')
     from unnest(r.dietary_tags || array(
       select 'contains_' || case a when 'tree_nuts' then 'nuts' else a end
       from recipe_ingredients ri
       join ingredients i on i.id = ri.ingredient_id
       cross join unnest(i.allergens) a
       where ri.recipe_id = r.id
     )) t
   )
 where exists (
   select 1
   from recipe_ingredients ri
   join ingredients i on i.id = ri.ingredient_id
   where ri.recipe_id = r.id and array_length(i.allergens, 1) > 0
 );

-- 2. A dish whose ingredients include egg, dairy, fish or shellfish is not vegan.
update recipes r
   set dietary_tags = array_remove(r.dietary_tags, 'vegan')
 where 'vegan' = any(r.dietary_tags)
   and exists (
     select 1
     from recipe_ingredients ri
     join ingredients i on i.id = ri.ingredient_id
     where ri.recipe_id = r.id
       and i.allergens && array['egg','dairy','fish','shellfish']
   );

-- 3. ...and one with fish or shellfish is not vegetarian either.
update recipes r
   set dietary_tags = array_remove(r.dietary_tags, 'vegetarian')
 where 'vegetarian' = any(r.dietary_tags)
   and exists (
     select 1
     from recipe_ingredients ri
     join ingredients i on i.id = ri.ingredient_id
     where ri.recipe_id = r.id
       and i.allergens && array['fish','shellfish']
   );
