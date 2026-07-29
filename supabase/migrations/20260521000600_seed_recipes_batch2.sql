-- Sous — seed recipes, batch 2 (recipes 26–50).
-- Brings the catalog to 50: +8 Mexican, +8 Asian, +8 Italian, +1 wildcard.
-- Same idempotent pattern as recipes.sql. Reuses the ingredient catalog and
-- adds the new ingredients these dishes need. Units are kept consistent with
-- batch 1 (clove / cup / each / lb / oz / can / pack / bunch / pint / jar) so
-- the shopping-list aggregation can sum quantities per ingredient.

begin;

-- ---- new ingredients ------------------------------------------------------
insert into ingredients (name_canonical, aliases, unit_default, source_hint, seasonal_months, is_free) values
  ('beef chuck',            '{chuck roast,stew beef}',  'lb',   'grocery',        null,         false),
  ('ground pork',           '{}',                       'lb',   'grocery',        null,         false),
  ('corn',                  '{corn on the cob}',        'each', 'farmers_market', '{6,7,8,9}',  false),
  ('green olives',          '{castelvetrano}',          'jar',  'grocery',        null,         false),
  ('lo mein noodles',       '{egg noodles}',            'pack', 'grocery',        null,         false),
  ('thai green curry paste','{green curry paste}',      'jar',  'grocery',        null,         false),
  ('snap peas',             '{sugar snap peas}',        'lb',   'farmers_market', null,         false),
  ('panko',                 '{breadcrumbs}',            'box',  'grocery',        null,         false),
  ('pesto',                 '{basil pesto}',            'jar',  'grocery',        null,         false),
  ('kale',                  '{lacinato kale}',          'bunch','farmers_market', null,         false),
  ('gnocchi',               '{}',                       'pack', 'grocery',        null,         false),
  ('linguine',              '{}',                       'lb',   'grocery',        null,         false),
  ('parsley',               '{flat-leaf parsley}',      'bunch','farmers_market', null,         false),
  ('cannellini beans',      '{white beans}',            'can',  'grocery',        null,         false),
  ('pancetta',              '{guanciale}',              'oz',   'grocery',        null,         false),
  ('eggplant',              '{aubergine}',              'each', 'farmers_market', '{7,8,9}',    false),
  ('chickpeas',             '{garbanzo beans}',         'can',  'grocery',        null,         false),
  ('harissa',               '{}',                       'jar',  'grocery',        null,         false)
on conflict (name_canonical) do nothing;

-- ---- recipes --------------------------------------------------------------
insert into recipes (title, cuisine_tag, body_md, time_minutes, toddler_variant_notes, source)
select v.title, v.cuisine_tag, v.body_md, v.time_minutes, v.toddler_variant_notes, 'curated'
from (values
  -- Mexican
  ('Chicken Enchiladas Verde', 'mexican',
   E'Shredded chicken rolled in corn tortillas under a tangy tomatillo sauce and melted cheese.\n\n1. Poach and shred chicken thighs.\n2. Blend roasted tomatillo, onion, garlic and cilantro into a verde sauce.\n3. Roll chicken in softened tortillas, cover with sauce + cheese, bake until bubbling.',
   45, E'Roll a cheese-and-chicken enchilada with barely any sauce; the verde is mild but tangy. Cool and cut into strips.'),
  ('Beef Barbacoa Tacos', 'mexican',
   E'Chuck slow-braised with chipotle and lime until it falls apart, in warm corn tortillas. Friday project.\n\n1. Braise beef chuck with chipotle, cumin, onion and garlic until shreddable (~2.5h, hands-off).\n2. Shred and crisp.\n3. Build tacos with cilantro and a squeeze of lime.',
   70, E'Pull plain shredded beef before the chipotle braise reduces, or rinse a portion. Serve on a soft tortilla cut small.'),
  ('Shrimp & Avocado Tostadas', 'mexican',
   E'Crisp tostadas piled with quick shrimp, avocado, cabbage and lime crema.\n\n1. Sear shrimp with a little cumin.\n2. Mash avocado; shred cabbage; thin sour cream with lime.\n3. Layer on crisped corn tortillas.',
   25, E'Chop a few plain shrimp small and serve with mashed avocado on a soft tortilla — skip the crisp tostada shell for little ones.'),
  ('Huevos Rancheros', 'mexican',
   E'Fried eggs over warm tortillas, black beans and a quick ranchero tomato sauce. Eggs from the coop.\n\n1. Simmer crushed tomatoes with onion, garlic and a little jalapeno into ranchero sauce.\n2. Warm beans and tortillas; fry eggs.\n3. Plate eggs over tortillas, spoon sauce, top with cotija.',
   25, E'Scramble an egg fully and serve with plain beans and a soft tortilla — hold the ranchero sauce. No jalapeno on their plate.'),
  ('Pork Chile Verde Burritos', 'mexican',
   E'Pork shoulder simmered in tomatillo verde, wrapped with rice into fat burritos. Friday project.\n\n1. Braise pork with tomatillo, onion and garlic until tender (~1.5h).\n2. Shred; cook rice.\n3. Fill flour tortillas with pork, rice and cilantro; griddle seam-side down.',
   70, E'Reserve plain shredded pork + rice and roll a small mild burrito before the verde reduces.'),
  ('Turkey Taco Skillet', 'mexican',
   E'One-skillet ground turkey with peppers and black beans, scooped into tortillas.\n\n1. Brown turkey with chili powder; add pepper, onion and beans.\n2. Simmer to meld.\n3. Spoon into warm tortillas; finish with cotija.',
   25, E'Reserve plain turkey + beans before the chili powder. Serve with a soft tortilla cut into strips.'),
  ('Esquites Chicken Bowls', 'mexican',
   E'Mexican street-corn bowls with seared chicken, charred corn, cotija and lime over rice.\n\n1. Char corn; cook rice.\n2. Sear chicken breast; slice.\n3. Toss corn with lime, a little chili and cotija; build bowls.',
   30, E'Plain sliced chicken + rice + corn cut off the cob (sliced small). Hold the chili and lime dressing.'),
  ('Fish Veracruz', 'mexican',
   E'White fish poached in a bright tomato sauce with olives and lime, over rice.\n\n1. Build a tomato sauce with onion, garlic and olives.\n2. Nestle in fish; simmer until just cooked.\n3. Finish with lime; serve over rice.',
   35, E'Poach a plain piece of fish in a little sauce-free broth; serve over rice. Quarter or omit the olives (choking shape).'),

  -- Asian
  ('Chicken Teriyaki Donburi', 'asian',
   E'Glazed chicken thighs over rice with a soft scallion finish — a fast rice bowl.\n\n1. Simmer soy, mirin and brown sugar into teriyaki.\n2. Sear chicken; glaze.\n3. Slice over rice; top with scallion (and an egg if you like).',
   30, E'Reserve plain chicken + rice before glazing. A fully-cooked egg on top is fine for them.'),
  ('Pork Fried Rice', 'asian',
   E'Ground pork fried with day-old rice, egg, peas and carrot.\n\n1. Scramble eggs; set aside.\n2. Brown pork; add garlic, carrot and peas.\n3. Add cold rice, soy and sesame oil; fold eggs back in, finish with scallion.',
   25, E'Scoop out plain rice + egg + peas before the soy goes heavy.'),
  ('Sesame Ginger Salmon', 'asian',
   E'Roasted salmon in a sesame-ginger soy glaze with broccoli over rice.\n\n1. Whisk soy, sesame oil, ginger and garlic.\n2. Roast salmon and broccoli, brushing with glaze.\n3. Serve over rice with sesame seeds.',
   30, E'Reserve a plain salmon piece + soft broccoli + rice, glaze on the side. Flake and check for bones.'),
  ('Vegetable Lo Mein', 'asian',
   E'Chewy noodles tossed with broccoli, carrot and pepper in a quick garlic-ginger soy. Meatless.\n\n1. Boil noodles.\n2. Stir-fry broccoli, carrot and pepper with garlic and ginger.\n3. Toss with noodles, soy and sesame oil; finish with scallion.',
   25, E'Plain buttered noodles + soft veg; sauce on the side.'),
  ('Thai Green Curry Chicken', 'asian',
   E'Chicken thighs simmered in a fragrant green coconut curry with peppers, over rice.\n\n1. Cook rice.\n2. Brown chicken; add onion, garlic.\n3. Stir in green curry paste, then coconut milk and peppers; simmer; finish with basil.',
   40, E'Reserve plain browned chicken + rice before the curry paste. The coconut sauce without paste also works.'),
  ('Beef & Snap Pea Stir-Fry', 'asian',
   E'Quick-seared flank steak with crunchy snap peas in a light soy glaze over rice.\n\n1. Slice steak thin, toss with cornstarch.\n2. Sear; add garlic, ginger, snap peas.\n3. Glaze with soy + a splash of water; finish sesame oil over rice.',
   30, E'Reserve plain beef + snap peas (cut small) + rice, sauce on the side.'),
  ('Miso-Glazed Cod', 'asian',
   E'Sweet-savory miso-glazed cod with tender bok choy over rice.\n\n1. Whisk miso + mirin.\n2. Broil cod with glaze until caramelized.\n3. Saute bok choy; serve over rice with scallion.',
   30, E'Reserve a plain (unglazed) piece of cod + rice + soft bok choy. Flake and check for bones.'),
  ('Chicken Katsu', 'asian',
   E'Panko-crusted crispy chicken cutlets, sliced over rice with shredded cabbage.\n\n1. Bread chicken in flour, egg, then panko.\n2. Pan-fry until golden; rest and slice.\n3. Serve over rice with cabbage.',
   40, E'A toddler favorite — plain katsu sliced into strips and cooled, with rice. Skip any sauce.'),

  -- Italian
  ('Chicken Parmesan', 'italian',
   E'Crispy breaded chicken under tomato sauce and melted mozzarella over spaghetti.\n\n1. Bread chicken (flour, egg, panko); pan-fry.\n2. Top with crushed-tomato sauce and mozzarella; bake to melt.\n3. Serve over spaghetti with parmesan.',
   45, E'Reserve a plain breaded chicken strip (no sauce) + buttered noodles. Slice small.'),
  ('Pesto Pasta with Cherry Tomatoes', 'italian',
   E'Penne tossed with basil pesto and blistered cherry tomatoes.\n\n1. Cook penne, saving pasta water.\n2. Blister tomatoes in olive oil with garlic.\n3. Toss pasta with pesto, a splash of water and tomatoes; finish with parmesan.',
   20, E'Plain buttered pasta + tomatoes on the side; pesto can be strong, so go light or skip for them.'),
  ('Sausage & Kale Orecchiette', 'italian',
   E'Italian sausage and wilted kale tossed with pasta and parmesan.\n\n1. Brown crumbled sausage.\n2. Wilt kale with garlic in the drippings.\n3. Toss with pasta, a splash of pasta water and parmesan.',
   35, E'Plain buttered pasta with a little finely-chopped sausage; skip the kale if it''s a hard sell.'),
  ('Gnocchi Margherita Bake', 'italian',
   E'Pillowy gnocchi baked in tomato sauce with fresh mozzarella and basil.\n\n1. Simmer crushed tomatoes with garlic.\n2. Fold in gnocchi; top with mozzarella.\n3. Bake until bubbling; finish with basil.',
   35, E'Toddler-friendly and soft. Serve a small, cooled portion; the cheese keeps it mild.'),
  ('Shrimp Scampi Linguine', 'italian',
   E'Garlicky lemon-butter shrimp over linguine with parsley.\n\n1. Cook linguine.\n2. Saute shrimp in garlic butter; add lemon and a splash of pasta water.\n3. Toss with pasta and parsley.',
   25, E'Plain buttered linguine + a few chopped shrimp. Hold the lemon-garlic sauce if it''s too punchy.'),
  ('Minestrone', 'italian',
   E'A cozy vegetable-and-bean soup with pasta and parmesan. Meatless.\n\n1. Soften carrot, onion and garlic.\n2. Add crushed tomatoes, beans and broth; simmer.\n3. Cook pasta in the pot; finish with spinach and parmesan.',
   40, E'Naturally soft and mild — great for toddlers. Serve a small bowl, maybe with extra pasta and beans.'),
  ('Spaghetti Carbonara', 'italian',
   E'Silky egg-and-pecorino sauce with crisp pancetta and black pepper. Eggs from the coop.\n\n1. Crisp pancetta.\n2. Cook spaghetti; whisk eggs with pecorino.\n3. Off heat, toss pasta with egg mixture and pasta water until creamy; lots of pepper.',
   25, E'Reserve plain buttered spaghetti before the egg sauce and pepper. The carbonara egg is cooked by the hot pasta, which is fine for them too.'),
  ('Eggplant Parmesan', 'italian',
   E'Breaded eggplant layered with tomato sauce and cheese. Friday project. Meatless.\n\n1. Bread and bake eggplant slices until crisp.\n2. Layer with crushed-tomato sauce, mozzarella and parmesan.\n3. Bake until golden and bubbling.',
   55, E'Cheesy and mild — serve a small, cooled portion cut up.'),

  -- Wildcard
  ('Sheet-Pan Harissa Chicken & Chickpeas', 'other',
   E'Spiced harissa chicken roasted with chickpeas, peppers and potatoes on one sheet.\n\n1. Toss chicken, chickpeas, potato and pepper with harissa, lemon, garlic and oil.\n2. Roast until chicken is cooked and chickpeas crisp.\n3. Finish with a squeeze of lemon.',
   45, E'Reserve plain chicken + soft potato + a few chickpeas before tossing with harissa (it''s spicy). Cut potato small.')
) as v(title, cuisine_tag, body_md, time_minutes, toddler_variant_notes)
where not exists (select 1 from recipes r where r.title = v.title);

-- ---- recipe ingredients ---------------------------------------------------
insert into recipe_ingredients (recipe_id, ingredient_id, quantity, unit, optional)
select r.id, i.id, v.quantity, v.unit, v.optional
from (values
  -- Chicken Enchiladas Verde
  ('Chicken Enchiladas Verde','chicken thighs',1.5,'lb',false),
  ('Chicken Enchiladas Verde','tomatillo',1,'lb',false),
  ('Chicken Enchiladas Verde','corn tortillas',1,'pack',false),
  ('Chicken Enchiladas Verde','mozzarella',6,'oz',false),
  ('Chicken Enchiladas Verde','yellow onion',1,'each',false),
  ('Chicken Enchiladas Verde','garlic',3,'clove',false),
  ('Chicken Enchiladas Verde','cilantro',1,'bunch',false),
  ('Chicken Enchiladas Verde','ground cumin',1,'tsp',false),
  -- Beef Barbacoa Tacos
  ('Beef Barbacoa Tacos','beef chuck',3,'lb',false),
  ('Beef Barbacoa Tacos','chipotle in adobo',2,'tbsp',false),
  ('Beef Barbacoa Tacos','lime',4,'each',false),
  ('Beef Barbacoa Tacos','yellow onion',1,'each',false),
  ('Beef Barbacoa Tacos','garlic',4,'clove',false),
  ('Beef Barbacoa Tacos','cilantro',1,'bunch',false),
  ('Beef Barbacoa Tacos','corn tortillas',1,'pack',false),
  ('Beef Barbacoa Tacos','ground cumin',1,'tsp',false),
  -- Shrimp & Avocado Tostadas
  ('Shrimp & Avocado Tostadas','shrimp',1.25,'lb',false),
  ('Shrimp & Avocado Tostadas','corn tortillas',1,'pack',false),
  ('Shrimp & Avocado Tostadas','avocado',2,'each',false),
  ('Shrimp & Avocado Tostadas','green cabbage',0.5,'each',false),
  ('Shrimp & Avocado Tostadas','lime',3,'each',false),
  ('Shrimp & Avocado Tostadas','sour cream',6,'oz',false),
  ('Shrimp & Avocado Tostadas','cilantro',1,'bunch',false),
  -- Huevos Rancheros
  ('Huevos Rancheros','eggs',8,'each',false),
  ('Huevos Rancheros','corn tortillas',1,'pack',false),
  ('Huevos Rancheros','black beans',1,'can',false),
  ('Huevos Rancheros','crushed tomatoes',1,'can',false),
  ('Huevos Rancheros','jalapeno',1,'each',true),
  ('Huevos Rancheros','cotija',3,'oz',false),
  ('Huevos Rancheros','cilantro',1,'bunch',false),
  -- Pork Chile Verde Burritos
  ('Pork Chile Verde Burritos','pork shoulder',2.5,'lb',false),
  ('Pork Chile Verde Burritos','tomatillo',1,'lb',false),
  ('Pork Chile Verde Burritos','flour tortillas',1,'pack',false),
  ('Pork Chile Verde Burritos','white rice',1,'cup',false),
  ('Pork Chile Verde Burritos','yellow onion',1,'each',false),
  ('Pork Chile Verde Burritos','garlic',4,'clove',false),
  ('Pork Chile Verde Burritos','cilantro',1,'bunch',false),
  -- Turkey Taco Skillet
  ('Turkey Taco Skillet','ground turkey',1.25,'lb',false),
  ('Turkey Taco Skillet','bell pepper',1,'each',false),
  ('Turkey Taco Skillet','yellow onion',1,'each',false),
  ('Turkey Taco Skillet','black beans',1,'can',false),
  ('Turkey Taco Skillet','corn tortillas',1,'pack',false),
  ('Turkey Taco Skillet','chili powder',2,'tsp',false),
  ('Turkey Taco Skillet','cotija',3,'oz',false),
  -- Esquites Chicken Bowls
  ('Esquites Chicken Bowls','chicken breast',1.25,'lb',false),
  ('Esquites Chicken Bowls','corn',4,'each',false),
  ('Esquites Chicken Bowls','cotija',3,'oz',false),
  ('Esquites Chicken Bowls','lime',3,'each',false),
  ('Esquites Chicken Bowls','chili powder',1,'tsp',false),
  ('Esquites Chicken Bowls','cilantro',1,'bunch',false),
  ('Esquites Chicken Bowls','white rice',1.5,'cup',false),
  ('Esquites Chicken Bowls','sour cream',4,'oz',false),
  -- Fish Veracruz
  ('Fish Veracruz','white fish fillets',1.25,'lb',false),
  ('Fish Veracruz','crushed tomatoes',1,'can',false),
  ('Fish Veracruz','green olives',0.5,'jar',false),
  ('Fish Veracruz','yellow onion',1,'each',false),
  ('Fish Veracruz','garlic',3,'clove',false),
  ('Fish Veracruz','lime',2,'each',false),
  ('Fish Veracruz','white rice',1.5,'cup',false),

  -- Chicken Teriyaki Donburi
  ('Chicken Teriyaki Donburi','chicken thighs',1.5,'lb',false),
  ('Chicken Teriyaki Donburi','soy sauce',3,'tbsp',false),
  ('Chicken Teriyaki Donburi','mirin',2,'tbsp',false),
  ('Chicken Teriyaki Donburi','brown sugar',1,'tbsp',false),
  ('Chicken Teriyaki Donburi','white rice',1.5,'cup',false),
  ('Chicken Teriyaki Donburi','scallion',1,'bunch',false),
  ('Chicken Teriyaki Donburi','eggs',4,'each',true),
  -- Pork Fried Rice
  ('Pork Fried Rice','ground pork',1,'lb',false),
  ('Pork Fried Rice','white rice',2,'cup',false),
  ('Pork Fried Rice','eggs',3,'each',false),
  ('Pork Fried Rice','peas',1,'bag',false),
  ('Pork Fried Rice','carrot',2,'each',false),
  ('Pork Fried Rice','scallion',1,'bunch',false),
  ('Pork Fried Rice','garlic',4,'clove',false),
  ('Pork Fried Rice','soy sauce',3,'tbsp',false),
  ('Pork Fried Rice','sesame oil',1,'tbsp',false),
  -- Sesame Ginger Salmon
  ('Sesame Ginger Salmon','salmon',1.25,'lb',false),
  ('Sesame Ginger Salmon','soy sauce',3,'tbsp',false),
  ('Sesame Ginger Salmon','sesame oil',1,'tbsp',false),
  ('Sesame Ginger Salmon','fresh ginger',1,'each',false),
  ('Sesame Ginger Salmon','garlic',3,'clove',false),
  ('Sesame Ginger Salmon','broccoli',1,'head',false),
  ('Sesame Ginger Salmon','white rice',1.5,'cup',false),
  ('Sesame Ginger Salmon','sesame seeds',1,'tbsp',false),
  -- Vegetable Lo Mein
  ('Vegetable Lo Mein','lo mein noodles',1,'pack',false),
  ('Vegetable Lo Mein','broccoli',1,'head',false),
  ('Vegetable Lo Mein','carrot',2,'each',false),
  ('Vegetable Lo Mein','bell pepper',1,'each',false),
  ('Vegetable Lo Mein','garlic',4,'clove',false),
  ('Vegetable Lo Mein','fresh ginger',1,'each',false),
  ('Vegetable Lo Mein','soy sauce',3,'tbsp',false),
  ('Vegetable Lo Mein','sesame oil',1,'tbsp',false),
  ('Vegetable Lo Mein','scallion',1,'bunch',false),
  -- Thai Green Curry Chicken
  ('Thai Green Curry Chicken','chicken thighs',1.5,'lb',false),
  ('Thai Green Curry Chicken','coconut milk',1,'can',false),
  ('Thai Green Curry Chicken','thai green curry paste',2,'tbsp',false),
  ('Thai Green Curry Chicken','bell pepper',2,'each',false),
  ('Thai Green Curry Chicken','yellow onion',1,'each',false),
  ('Thai Green Curry Chicken','garlic',3,'clove',false),
  ('Thai Green Curry Chicken','white rice',1.5,'cup',false),
  ('Thai Green Curry Chicken','thai basil',1,'bunch',false),
  -- Beef & Snap Pea Stir-Fry
  ('Beef & Snap Pea Stir-Fry','flank steak',1.25,'lb',false),
  ('Beef & Snap Pea Stir-Fry','snap peas',0.75,'lb',false),
  ('Beef & Snap Pea Stir-Fry','garlic',4,'clove',false),
  ('Beef & Snap Pea Stir-Fry','fresh ginger',1,'each',false),
  ('Beef & Snap Pea Stir-Fry','soy sauce',3,'tbsp',false),
  ('Beef & Snap Pea Stir-Fry','white rice',1.5,'cup',false),
  ('Beef & Snap Pea Stir-Fry','sesame oil',1,'tbsp',false),
  ('Beef & Snap Pea Stir-Fry','cornstarch',1,'tbsp',false),
  -- Miso-Glazed Cod
  ('Miso-Glazed Cod','white fish fillets',1.25,'lb',false),
  ('Miso-Glazed Cod','miso paste',3,'tbsp',false),
  ('Miso-Glazed Cod','mirin',2,'tbsp',false),
  ('Miso-Glazed Cod','white rice',1.5,'cup',false),
  ('Miso-Glazed Cod','bok choy',3,'each',false),
  ('Miso-Glazed Cod','scallion',1,'bunch',false),
  -- Chicken Katsu
  ('Chicken Katsu','chicken breast',1.5,'lb',false),
  ('Chicken Katsu','panko',1,'box',false),
  ('Chicken Katsu','eggs',2,'each',false),
  ('Chicken Katsu','white rice',1.5,'cup',false),
  ('Chicken Katsu','green cabbage',0.5,'each',false),
  ('Chicken Katsu','soy sauce',2,'tbsp',false),

  -- Chicken Parmesan
  ('Chicken Parmesan','chicken breast',1.5,'lb',false),
  ('Chicken Parmesan','panko',1,'box',false),
  ('Chicken Parmesan','eggs',2,'each',false),
  ('Chicken Parmesan','crushed tomatoes',1,'can',false),
  ('Chicken Parmesan','mozzarella',6,'oz',false),
  ('Chicken Parmesan','parmesan',3,'oz',false),
  ('Chicken Parmesan','spaghetti',1,'lb',false),
  ('Chicken Parmesan','garlic',3,'clove',false),
  -- Pesto Pasta with Cherry Tomatoes
  ('Pesto Pasta with Cherry Tomatoes','penne',1,'lb',false),
  ('Pesto Pasta with Cherry Tomatoes','pesto',0.5,'jar',false),
  ('Pesto Pasta with Cherry Tomatoes','cherry tomatoes',1,'pint',false),
  ('Pesto Pasta with Cherry Tomatoes','parmesan',3,'oz',false),
  ('Pesto Pasta with Cherry Tomatoes','garlic',2,'clove',false),
  -- Sausage & Kale Orecchiette
  ('Sausage & Kale Orecchiette','italian sausage',1,'lb',false),
  ('Sausage & Kale Orecchiette','kale',1,'bunch',false),
  ('Sausage & Kale Orecchiette','penne',1,'lb',false),
  ('Sausage & Kale Orecchiette','garlic',4,'clove',false),
  ('Sausage & Kale Orecchiette','parmesan',3,'oz',false),
  ('Sausage & Kale Orecchiette','olive oil',2,'tbsp',false),
  -- Gnocchi Margherita Bake
  ('Gnocchi Margherita Bake','gnocchi',2,'pack',false),
  ('Gnocchi Margherita Bake','crushed tomatoes',1,'can',false),
  ('Gnocchi Margherita Bake','fresh mozzarella',8,'oz',false),
  ('Gnocchi Margherita Bake','fresh basil',1,'bunch',false),
  ('Gnocchi Margherita Bake','garlic',3,'clove',false),
  -- Shrimp Scampi Linguine
  ('Shrimp Scampi Linguine','shrimp',1.25,'lb',false),
  ('Shrimp Scampi Linguine','linguine',1,'lb',false),
  ('Shrimp Scampi Linguine','garlic',5,'clove',false),
  ('Shrimp Scampi Linguine','lemon',2,'each',false),
  ('Shrimp Scampi Linguine','butter',3,'tbsp',false),
  ('Shrimp Scampi Linguine','parsley',1,'bunch',false),
  -- Minestrone
  ('Minestrone','cannellini beans',2,'can',false),
  ('Minestrone','crushed tomatoes',1,'can',false),
  ('Minestrone','carrot',2,'each',false),
  ('Minestrone','yellow onion',1,'each',false),
  ('Minestrone','garlic',3,'clove',false),
  ('Minestrone','penne',0.5,'lb',false),
  ('Minestrone','parmesan',3,'oz',false),
  ('Minestrone','baby spinach',1,'bag',false),
  -- Spaghetti Carbonara
  ('Spaghetti Carbonara','spaghetti',1,'lb',false),
  ('Spaghetti Carbonara','eggs',4,'each',false),
  ('Spaghetti Carbonara','pecorino romano',4,'oz',false),
  ('Spaghetti Carbonara','pancetta',4,'oz',false),
  ('Spaghetti Carbonara','black pepper',1,'tbsp',false),
  ('Spaghetti Carbonara','garlic',2,'clove',false),
  -- Eggplant Parmesan
  ('Eggplant Parmesan','eggplant',2,'each',false),
  ('Eggplant Parmesan','crushed tomatoes',1,'can',false),
  ('Eggplant Parmesan','mozzarella',8,'oz',false),
  ('Eggplant Parmesan','parmesan',3,'oz',false),
  ('Eggplant Parmesan','panko',1,'box',false),
  ('Eggplant Parmesan','eggs',2,'each',false),
  ('Eggplant Parmesan','garlic',3,'clove',false),

  -- Sheet-Pan Harissa Chicken & Chickpeas
  ('Sheet-Pan Harissa Chicken & Chickpeas','chicken thighs',1.5,'lb',false),
  ('Sheet-Pan Harissa Chicken & Chickpeas','chickpeas',2,'can',false),
  ('Sheet-Pan Harissa Chicken & Chickpeas','harissa',2,'tbsp',false),
  ('Sheet-Pan Harissa Chicken & Chickpeas','bell pepper',1,'each',false),
  ('Sheet-Pan Harissa Chicken & Chickpeas','lemon',2,'each',false),
  ('Sheet-Pan Harissa Chicken & Chickpeas','yukon potato',1,'lb',false),
  ('Sheet-Pan Harissa Chicken & Chickpeas','garlic',4,'clove',false),
  ('Sheet-Pan Harissa Chicken & Chickpeas','olive oil',3,'tbsp',false)
) as v(recipe_title, ingredient_name, quantity, unit, optional)
join recipes r on r.title = v.recipe_title
join ingredients i on i.name_canonical = v.ingredient_name
on conflict (recipe_id, ingredient_id) do nothing;

commit;
