-- Sous — T2: structured diet/allergen tags + serving sizes for the seed catalog.
-- Runs after 20260728000000 (which added recipes.base_servings/dietary_tags and
-- ingredients.allergens). UPDATEs by title/name so it applies to both a fresh
-- clone's seeded rows and the author's existing catalog. dietary_tags carry two
-- kinds of fact: diet-compatibility (vegetarian/vegan/pescatarian/gluten_free/
-- dairy_free) and contains_* allergen/ingredient markers, both used by the
-- server-side dietary filter (T4).

-- Recipes: base_servings (scaling divisor, T3) + dietary_tags.
update recipes set base_servings = 8, dietary_tags = '{gluten_free,contains_pork,contains_dairy}' where title = 'Carnitas Bowls';
update recipes set base_servings = 5, dietary_tags = '{gluten_free,contains_poultry,contains_dairy}' where title = 'Chicken Tinga Tacos';
update recipes set base_servings = 4, dietary_tags = '{pescatarian,dairy_free,contains_shellfish,contains_gluten}' where title = 'Chili-Lime Shrimp Fajitas';
update recipes set base_servings = 4, dietary_tags = '{vegetarian,gluten_free,contains_dairy}' where title = 'Black Bean & Sweet Potato Enchiladas';
update recipes set base_servings = 5, dietary_tags = '{gluten_free,dairy_free,contains_beef}' where title = 'Carne Asada Bowls';
update recipes set base_servings = 4, dietary_tags = '{pescatarian,gluten_free,contains_fish,contains_dairy}' where title = 'Baja Fish Tacos';
update recipes set base_servings = 6, dietary_tags = '{gluten_free,dairy_free,contains_pork}' where title = 'Pork & Hominy Pozole Verde';
update recipes set base_servings = 4, dietary_tags = '{contains_beef,contains_gluten,contains_dairy}' where title = 'Cheesy Beef & Pepper Quesadillas';
update recipes set base_servings = 4, dietary_tags = '{pescatarian,dairy_free,contains_fish,contains_soy,contains_gluten}' where title = 'Miso Salmon Bowls';
update recipes set base_servings = 4, dietary_tags = '{dairy_free,contains_poultry,contains_fish,contains_egg,contains_soy,contains_gluten}' where title = 'Thai Basil Chicken (Pad Krapow)';
update recipes set base_servings = 4, dietary_tags = '{gluten_free,dairy_free,contains_poultry,contains_fish}' where title = 'Chicken Larb Lettuce Cups';
update recipes set base_servings = 4, dietary_tags = '{dairy_free,contains_beef,contains_soy,contains_gluten}' where title = 'Beef & Broccoli Stir-Fry';
update recipes set base_servings = 5, dietary_tags = '{gluten_free,dairy_free,contains_poultry}' where title = 'Coconut Chicken Curry';
update recipes set base_servings = 4, dietary_tags = '{pescatarian,dairy_free,contains_shellfish,contains_egg,contains_soy,contains_gluten}' where title = 'Garlic-Ginger Shrimp Fried Rice';
update recipes set base_servings = 4, dietary_tags = '{dairy_free,contains_beef,contains_soy,contains_gluten}' where title = 'Korean Beef Bulgogi Bowls';
update recipes set base_servings = 4, dietary_tags = '{pescatarian,dairy_free,contains_fish,contains_soy,contains_gluten}' where title = 'Teriyaki Salmon & Bok Choy';
update recipes set base_servings = 4, dietary_tags = '{vegetarian,contains_dairy,contains_gluten}' where title = 'Cacio e Pepe with Blistered Tomatoes';
update recipes set base_servings = 4, dietary_tags = '{dairy_free,gluten_free,contains_pork}' where title = 'Sheet-Pan Sausage & Peppers';
update recipes set base_servings = 4, dietary_tags = '{contains_poultry,contains_gluten,contains_dairy,contains_egg}' where title = 'Spaghetti & Turkey Meatballs';
update recipes set base_servings = 5, dietary_tags = '{contains_poultry,contains_dairy,contains_gluten}' where title = 'Creamy Tuscan Chicken';
update recipes set base_servings = 4, dietary_tags = '{vegetarian,contains_dairy,contains_gluten}' where title = 'Margherita Flatbread';
update recipes set base_servings = 4, dietary_tags = '{vegetarian,contains_dairy,contains_gluten}' where title = 'Lemon Ricotta Pasta with Peas';
update recipes set base_servings = 4, dietary_tags = '{vegetarian,gluten_free,contains_dairy}' where title = 'Mushroom Risotto';
update recipes set base_servings = 6, dietary_tags = '{contains_beef,contains_dairy,contains_gluten}' where title = 'Baked Ziti';
update recipes set base_servings = 5, dietary_tags = '{gluten_free,contains_poultry,contains_dairy}' where title = 'Sheet-Pan Greek Chicken & Potatoes';
update recipes set base_servings = 5, dietary_tags = '{contains_poultry,contains_dairy,gluten_free}' where title = 'Chicken Enchiladas Verde';
update recipes set base_servings = 8, dietary_tags = '{contains_beef,dairy_free,gluten_free}' where title = 'Beef Barbacoa Tacos';
update recipes set base_servings = 5, dietary_tags = '{pescatarian,contains_shellfish,contains_dairy,gluten_free}' where title = 'Shrimp & Avocado Tostadas';
update recipes set base_servings = 4, dietary_tags = '{vegetarian,contains_egg,contains_dairy,gluten_free}' where title = 'Huevos Rancheros';
update recipes set base_servings = 7, dietary_tags = '{contains_pork,contains_gluten,dairy_free}' where title = 'Pork Chile Verde Burritos';
update recipes set base_servings = 5, dietary_tags = '{contains_poultry,contains_dairy,gluten_free}' where title = 'Turkey Taco Skillet';
update recipes set base_servings = 5, dietary_tags = '{contains_poultry,contains_dairy,gluten_free}' where title = 'Esquites Chicken Bowls';
update recipes set base_servings = 5, dietary_tags = '{pescatarian,contains_fish,dairy_free,gluten_free}' where title = 'Fish Veracruz';
update recipes set base_servings = 5, dietary_tags = '{contains_poultry,contains_soy,contains_gluten,contains_egg,dairy_free}' where title = 'Chicken Teriyaki Donburi';
update recipes set base_servings = 4, dietary_tags = '{contains_pork,contains_egg,contains_soy,contains_gluten,dairy_free}' where title = 'Pork Fried Rice';
update recipes set base_servings = 5, dietary_tags = '{pescatarian,contains_fish,contains_soy,contains_gluten,dairy_free}' where title = 'Sesame Ginger Salmon';
update recipes set base_servings = 4, dietary_tags = '{vegetarian,vegan,dairy_free,contains_soy,contains_gluten}' where title = 'Vegetable Lo Mein';
update recipes set base_servings = 5, dietary_tags = '{contains_poultry,dairy_free,gluten_free}' where title = 'Thai Green Curry Chicken';
update recipes set base_servings = 5, dietary_tags = '{contains_beef,contains_soy,contains_gluten,dairy_free}' where title = 'Beef & Snap Pea Stir-Fry';
update recipes set base_servings = 5, dietary_tags = '{pescatarian,contains_fish,contains_soy,dairy_free,gluten_free}' where title = 'Miso-Glazed Cod';
update recipes set base_servings = 5, dietary_tags = '{contains_poultry,contains_gluten,contains_egg,contains_soy,dairy_free}' where title = 'Chicken Katsu';
update recipes set base_servings = 5, dietary_tags = '{contains_poultry,contains_gluten,contains_egg,contains_dairy}' where title = 'Chicken Parmesan';
update recipes set base_servings = 4, dietary_tags = '{vegetarian,contains_gluten,contains_dairy,contains_nuts}' where title = 'Pesto Pasta with Cherry Tomatoes';
update recipes set base_servings = 4, dietary_tags = '{contains_pork,contains_gluten,contains_dairy}' where title = 'Sausage & Kale Orecchiette';
update recipes set base_servings = 4, dietary_tags = '{vegetarian,contains_gluten,contains_dairy}' where title = 'Gnocchi Margherita Bake';
update recipes set base_servings = 5, dietary_tags = '{pescatarian,contains_shellfish,contains_gluten,contains_dairy}' where title = 'Shrimp Scampi Linguine';
update recipes set base_servings = 4, dietary_tags = '{vegetarian,contains_gluten,contains_dairy}' where title = 'Minestrone';
update recipes set base_servings = 4, dietary_tags = '{contains_pork,contains_gluten,contains_egg,contains_dairy}' where title = 'Spaghetti Carbonara';
update recipes set base_servings = 4, dietary_tags = '{vegetarian,contains_gluten,contains_dairy,contains_egg}' where title = 'Eggplant Parmesan';
update recipes set base_servings = 5, dietary_tags = '{contains_poultry,dairy_free,gluten_free}' where title = 'Sheet-Pan Harissa Chicken & Chickpeas';

-- Ingredient allergen tags (only ingredients that carry an allergen).
update ingredients set allergens = '{fish}' where name_canonical = 'salmon';
update ingredients set allergens = '{fish}' where name_canonical = 'white fish fillets';
update ingredients set allergens = '{shellfish}' where name_canonical = 'shrimp';
update ingredients set allergens = '{soy}' where name_canonical = 'edamame';
update ingredients set allergens = '{gluten}' where name_canonical = 'flour tortillas';
update ingredients set allergens = '{gluten}' where name_canonical = 'bucatini';
update ingredients set allergens = '{gluten}' where name_canonical = 'spaghetti';
update ingredients set allergens = '{gluten}' where name_canonical = 'penne';
update ingredients set allergens = '{gluten}' where name_canonical = 'ziti';
update ingredients set allergens = '{gluten}' where name_canonical = 'flatbread';
update ingredients set allergens = '{soy,gluten}' where name_canonical = 'soy sauce';
update ingredients set allergens = '{fish}' where name_canonical = 'fish sauce';
update ingredients set allergens = '{sesame}' where name_canonical = 'sesame oil';
update ingredients set allergens = '{soy}' where name_canonical = 'gochujang';
update ingredients set allergens = '{soy}' where name_canonical = 'miso paste';
update ingredients set allergens = '{sesame}' where name_canonical = 'sesame seeds';
update ingredients set allergens = '{dairy}' where name_canonical = 'cotija';
update ingredients set allergens = '{dairy}' where name_canonical = 'pecorino romano';
update ingredients set allergens = '{dairy}' where name_canonical = 'parmesan';
update ingredients set allergens = '{dairy}' where name_canonical = 'mozzarella';
update ingredients set allergens = '{dairy}' where name_canonical = 'fresh mozzarella';
update ingredients set allergens = '{dairy}' where name_canonical = 'ricotta';
update ingredients set allergens = '{dairy}' where name_canonical = 'feta';
update ingredients set allergens = '{dairy}' where name_canonical = 'heavy cream';
update ingredients set allergens = '{dairy}' where name_canonical = 'sour cream';
update ingredients set allergens = '{dairy}' where name_canonical = 'butter';
update ingredients set allergens = '{egg}' where name_canonical = 'eggs';
update ingredients set allergens = '{gluten,egg}' where name_canonical = 'lo mein noodles';
update ingredients set allergens = '{gluten}' where name_canonical = 'panko';
update ingredients set allergens = '{dairy,tree_nuts}' where name_canonical = 'pesto';
update ingredients set allergens = '{gluten}' where name_canonical = 'gnocchi';
update ingredients set allergens = '{gluten}' where name_canonical = 'linguine';

-- ---------------------------------------------------------------------------
-- Reconcile the two vocabularies.
--
-- Everything above is hand-maintained: recipes carry curated `contains_*` tags,
-- ingredients carry `allergens`. Those are separate lists written by hand, so
-- they drift — 'Vegetable Lo Mein' was tagged {vegetarian,vegan,...} while its
-- own 'lo mein noodles' carry {gluten,egg}, which would have served it to an
-- egg-allergic household and mislabeled it vegan.
--
-- Rather than fix that one row and wait for the next drift, DERIVE the recipe
-- tags from the ingredient data. These statements are idempotent and safe to
-- re-run, and they make ingredients.allergens the single source of truth for
-- anything an allergy filter depends on.

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
