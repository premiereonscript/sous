-- Goodbye Fresh — seed recipes (Day 3–4 of the build order, SPEC §11/§17)
-- 25 curated dinners: 8 Mexican, 8 Asian, 8 Italian, 1 wildcard ("other").
--
-- Design notes:
--   * Ingredients are shared across recipes on purpose — rice, lime, garlic,
--     ginger, scallion, bell pepper, parmesan, etc. repeat so the §9.4 overlap
--     scorer has real overlap to find at the 5-meal / $250 scale.
--   * Every spicy/aromatic dish carries a toddler_variant_notes "pull a portion
--     before the heat" fork (SPEC §10.7). The variant is a prep fork, not a
--     separate recipe.
--   * source_hint routes each ingredient to the Farmers Market vs Grocery list
--     at lock time (SPEC §9.3). Fresh produce/herbs -> farmers_market; pantry,
--     canned, dairy, most proteins -> grocery. Eggs are is_free (the coop).
--   * Idempotent: re-running inserts nothing new. Safe to run after migrations.
--
-- Load:  psql "$DATABASE_URL" -f supabase/seeds/recipes.sql
--   or:  supabase db reset  (if wired into supabase/seed.sql)

begin;

-- ---------------------------------------------------------------------------
-- 1. Ingredients
-- ---------------------------------------------------------------------------
insert into ingredients (name_canonical, aliases, unit_default, source_hint, seasonal_months, is_free) values
  -- proteins
  ('pork shoulder',        '{pork butt,carnitas pork}',  'lb',     'farmers_market', null,            false),
  ('chicken breast',       '{}',                         'lb',     'grocery',        null,            false),
  ('chicken thighs',       '{boneless skinless thighs}', 'lb',     'grocery',        null,            false),
  ('ground chicken',       '{}',                         'lb',     'grocery',        null,            false),
  ('flank steak',          '{skirt steak}',              'lb',     'grocery',        null,            false),
  ('ground beef',          '{}',                         'lb',     'grocery',        null,            false),
  ('ground turkey',        '{}',                         'lb',     'grocery',        null,            false),
  ('salmon',               '{salmon fillet}',            'lb',     'grocery',        null,            false),
  ('white fish fillets',   '{cod,tilapia,mahi}',         'lb',     'grocery',        null,            false),
  ('shrimp',               '{prawns}',                   'lb',     'grocery',        null,            false),
  ('italian sausage',      '{}',                         'lb',     'grocery',        null,            false),
  -- produce + herbs (farmers market)
  ('yellow onion',         '{onion}',                    'each',   'farmers_market', null,            false),
  ('red onion',            '{}',                         'each',   'farmers_market', null,            false),
  ('garlic',               '{}',                         'head',   'farmers_market', null,            false),
  ('cilantro',             '{coriander}',                'bunch',  'farmers_market', null,            false),
  ('lime',                 '{}',                         'each',   'farmers_market', null,            false),
  ('lemon',                '{}',                         'each',   'farmers_market', null,            false),
  ('bell pepper',          '{capsicum}',                 'each',   'farmers_market', '{7,8,9,10}',    false),
  ('cherry tomatoes',      '{grape tomatoes}',           'pint',   'farmers_market', '{6,7,8,9}',     false),
  ('roma tomato',          '{plum tomato}',              'each',   'farmers_market', '{6,7,8,9}',     false),
  ('tomatillo',            '{}',                         'lb',     'farmers_market', null,            false),
  ('avocado',              '{}',                         'each',   'farmers_market', null,            false),
  ('green cabbage',        '{}',                         'each',   'farmers_market', null,            false),
  ('romaine hearts',       '{romaine lettuce}',          'each',   'farmers_market', null,            false),
  ('cucumber',             '{}',                         'each',   'farmers_market', null,            false),
  ('scallion',             '{green onion}',              'bunch',  'farmers_market', null,            false),
  ('fresh ginger',         '{ginger}',                   'each',   'farmers_market', null,            false),
  ('thai basil',           '{}',                         'bunch',  'farmers_market', null,            false),
  ('fresh basil',          '{basil}',                    'bunch',  'farmers_market', '{6,7,8,9}',     false),
  ('fresh mint',           '{mint}',                     'bunch',  'farmers_market', null,            false),
  ('broccoli',             '{}',                         'head',   'farmers_market', null,            false),
  ('bok choy',             '{baby bok choy}',            'each',   'farmers_market', null,            false),
  ('baby spinach',         '{spinach}',                  'bag',    'farmers_market', null,            false),
  ('mushroom',             '{cremini,button mushroom}',  'lb',     'farmers_market', null,            false),
  ('sweet potato',         '{}',                         'each',   'farmers_market', '{9,10,11,12,1}',false),
  ('yukon potato',         '{yukon gold,potato}',        'lb',     'farmers_market', null,            false),
  ('carrot',               '{}',                         'each',   'farmers_market', null,            false),
  ('jalapeno',             '{}',                         'each',   'farmers_market', null,            false),
  ('thai chili',           '{birds eye chili}',          'each',   'farmers_market', null,            false),
  -- frozen
  ('peas',                 '{frozen peas}',              'bag',    'grocery',        null,            false),
  ('edamame',              '{frozen edamame}',           'bag',    'grocery',        null,            false),
  -- grains, pasta, tortillas
  ('white rice',           '{jasmine rice,long-grain rice}','lb',  'grocery',        null,            false),
  ('arborio rice',         '{risotto rice}',             'lb',     'grocery',        null,            false),
  ('corn tortillas',       '{}',                         'pack',   'grocery',        null,            false),
  ('flour tortillas',      '{}',                         'pack',   'grocery',        null,            false),
  ('bucatini',             '{spaghetti}',                'lb',     'grocery',        null,            false),
  ('spaghetti',            '{}',                         'lb',     'grocery',        null,            false),
  ('penne',                '{rigatoni}',                 'lb',     'grocery',        null,            false),
  ('ziti',                 '{}',                         'lb',     'grocery',        null,            false),
  ('flatbread',            '{naan,pizza crust}',         'each',   'grocery',        null,            false),
  ('polenta',              '{polenta tube}',             'each',   'grocery',        null,            false),
  -- canned + jarred
  ('black beans',          '{}',                         'can',    'grocery',        null,            false),
  ('hominy',               '{}',                         'can',    'grocery',        null,            false),
  ('enchilada sauce',      '{}',                         'can',    'grocery',        null,            false),
  ('chipotle in adobo',    '{}',                         'can',    'grocery',        null,            false),
  ('crushed tomatoes',     '{canned tomatoes}',          'can',    'grocery',        null,            false),
  ('coconut milk',         '{}',                         'can',    'grocery',        null,            false),
  ('thai red curry paste', '{red curry paste}',          'jar',    'grocery',        null,            false),
  ('sun-dried tomato',     '{}',                         'jar',    'grocery',        null,            false),
  -- sauces, oils, vinegars
  ('soy sauce',            '{tamari}',                   'bottle', 'grocery',        null,            false),
  ('fish sauce',           '{}',                         'bottle', 'grocery',        null,            false),
  ('sesame oil',           '{toasted sesame oil}',       'bottle', 'grocery',        null,            false),
  ('mirin',                '{}',                         'bottle', 'grocery',        null,            false),
  ('gochujang',            '{}',                         'jar',    'grocery',        null,            false),
  ('miso paste',           '{white miso}',               'tub',    'grocery',        null,            false),
  ('olive oil',            '{}',                         'bottle', 'grocery',        null,            false),
  ('vegetable oil',        '{neutral oil}',              'bottle', 'grocery',        null,            false),
  -- spices, baking, dry
  ('kosher salt',          '{salt}',                     'box',    'grocery',        null,            false),
  ('black pepper',         '{}',                         'jar',    'grocery',        null,            false),
  ('ground cumin',         '{cumin}',                    'jar',    'grocery',        null,            false),
  ('chili powder',         '{}',                         'jar',    'grocery',        null,            false),
  ('smoked paprika',       '{paprika}',                  'jar',    'grocery',        null,            false),
  ('dried oregano',        '{oregano}',                  'jar',    'grocery',        null,            false),
  ('sesame seeds',         '{}',                         'jar',    'grocery',        null,            false),
  ('brown sugar',          '{}',                         'bag',    'grocery',        null,            false),
  ('cornstarch',           '{}',                         'box',    'grocery',        null,            false),
  -- dairy + eggs
  ('cotija',               '{queso fresco}',             'oz',     'grocery',        null,            false),
  ('pecorino romano',      '{pecorino}',                 'oz',     'grocery',        null,            false),
  ('parmesan',             '{parmigiano}',               'oz',     'grocery',        null,            false),
  ('mozzarella',           '{shredded mozzarella}',      'oz',     'grocery',        null,            false),
  ('fresh mozzarella',     '{}',                         'oz',     'grocery',        null,            false),
  ('ricotta',              '{}',                         'oz',     'grocery',        null,            false),
  ('feta',                 '{}',                         'oz',     'grocery',        null,            false),
  ('heavy cream',          '{}',                         'cup',    'grocery',        null,            false),
  ('sour cream',           '{}',                         'oz',     'grocery',        null,            false),
  ('butter',               '{}',                         'stick',  'grocery',        null,            false),
  ('eggs',                 '{egg}',                      'each',   'either',         null,            true)
on conflict (name_canonical) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Recipes  (source = 'curated'; only inserted if title not already present)
-- ---------------------------------------------------------------------------
insert into recipes (title, cuisine_tag, body_md, time_minutes, toddler_variant_notes, source)
select v.title, v.cuisine_tag, v.body_md, v.time_minutes, v.toddler_variant_notes, 'curated'
from (values
  -- ---- Mexican (8) ----
  ('Carnitas Bowls', 'mexican',
   E'Slow-braised pork shoulder over lime rice and black beans, finished with pickled red onion and cotija.\n\n1. Season pork, braise with cumin, garlic and a splash of water until shreddable (~2.5h, mostly hands-off).\n2. Cook rice; warm black beans.\n3. Crisp shredded pork under the broiler.\n4. Quick-pickle red onion in lime juice. Build bowls; finish with cilantro and cotija.',
   35, E'Pull a portion of plain pork + rice + beans before the lime-chili finish. Skip cotija if cheese is new.'),
  ('Chicken Tinga Tacos', 'mexican',
   E'Shredded chicken simmered in a smoky chipotle-tomato sauce, piled into warm corn tortillas.\n\n1. Poach and shred chicken breast.\n2. Blend chipotle, crushed tomatoes, onion, garlic; simmer the sauce.\n3. Toss chicken in sauce.\n4. Warm tortillas; top with cilantro, cotija and a squeeze of lime.',
   40, E'Reserve plain shredded chicken before saucing — the chipotle is the heat. Serve on a soft tortilla cut small.'),
  ('Chili-Lime Shrimp Fajitas', 'mexican',
   E'Sheet-pan shrimp, peppers and onions in a chili-lime toss, wrapped in flour tortillas.\n\n1. Toss shrimp, sliced peppers and onion with chili powder, garlic, lime and oil.\n2. Roast hot until shrimp curl (~10 min).\n3. Char tortillas; build with cilantro and extra lime.',
   25, E'Set aside a few plain shrimp and soft peppers before the chili toss; chop shrimp small to avoid a choking shape.'),
  ('Black Bean & Sweet Potato Enchiladas', 'mexican',
   E'Roasted sweet potato and black beans rolled in corn tortillas under a mild enchilada sauce and melted cheese. Meatless.\n\n1. Roast diced sweet potato with cumin.\n2. Mash lightly with black beans and sauteed onion.\n3. Roll in softened tortillas, cover with sauce and cheese.\n4. Bake until bubbling.',
   45, E'Toddler-friendly as-is — a cheesy, mild roll. Cool and cut into strips; go light on sauce for the little plate.'),
  ('Carne Asada Bowls', 'mexican',
   E'Lime-and-cumin marinated flank steak, sliced over rice with avocado and a quick tomato-onion pico.\n\n1. Marinate flank steak in lime, garlic, cumin; sear hot, rest, slice against the grain.\n2. Cook rice.\n3. Dice tomato + red onion + cilantro for pico.\n4. Build bowls with avocado.',
   35, E'Reserve a few unseasoned steak strips + plain rice + mashed avocado. Slice steak thin and small.'),
  ('Baja Fish Tacos', 'mexican',
   E'Paprika-roasted white fish with a crisp cabbage slaw and lime crema in corn tortillas.\n\n1. Season fish with smoked paprika; roast or pan-sear.\n2. Shred cabbage; thin sour cream with lime for crema.\n3. Flake fish into warm tortillas; top with slaw, crema, cilantro.',
   30, E'Bake one plain fish piece, flake and check carefully for bones. Skip the slaw and crema; serve with a soft tortilla.'),
  ('Pork & Hominy Pozole Verde', 'mexican',
   E'A bright tomatillo-green pork and hominy stew, finished with cabbage, radish and lime. Friday project dish.\n\n1. Simmer pork shoulder until tender (~1h).\n2. Blend roasted tomatillo, onion, garlic, cilantro and (optional) jalapeno into a verde base.\n3. Combine with hominy; simmer.\n4. Serve with lime and shredded cabbage.',
   70, E'Pull plain shredded pork + hominy before adding the verde base. Omit jalapeno entirely for the kids'' bowls.'),
  ('Cheesy Beef & Pepper Quesadillas', 'mexican',
   E'Ground beef with sauteed peppers and onion, griddled into cheesy flour-tortilla quesadillas.\n\n1. Brown beef with a little chili powder; add diced peppers and onion.\n2. Layer with cheese in folded tortillas.\n3. Griddle until golden and melty; cut into wedges.',
   25, E'A reliable toddler win. Use the mild filling, cut into thin strips and let cool so the cheese sets.'),

  -- ---- Asian (8) ----
  ('Miso Salmon Bowls', 'asian',
   E'Miso-glazed roasted salmon over rice with cucumber, edamame and scallion.\n\n1. Whisk miso, mirin and a little soy into a glaze.\n2. Brush salmon and roast (~12 min).\n3. Cook rice; shell edamame; slice cucumber.\n4. Build bowls; finish with sesame seeds and scallion.',
   30, E'Reserve a plain (unglazed) piece of salmon — roast it alongside. Flake and check for bones; serve with rice and edamame.'),
  ('Thai Basil Chicken (Pad Krapow)', 'asian',
   E'Fast stir-fried ground chicken with garlic, chili and thai basil over rice, topped with a fried egg.\n\n1. Cook rice.\n2. Stir-fry garlic (and chili) then ground chicken in hot oil.\n3. Season with soy, fish sauce, a pinch of sugar; fold in thai basil.\n4. Fry eggs; serve over rice.',
   25, E'Pull plain cooked chicken + rice before the chili, fish sauce and basil go in. A fully-cooked (hard) fried egg is fine.'),
  ('Chicken Larb Lettuce Cups', 'asian',
   E'Zingy ground-chicken larb with lime, herbs and toasted rice, spooned into romaine cups.\n\n1. Toast a little rice and grind for nutty crunch (optional).\n2. Cook ground chicken; off heat toss with lime, fish sauce, scallion, mint and cilantro.\n3. Spoon into romaine; serve with steamed rice.',
   30, E'Reserve plain ground chicken + steamed rice before the lime/fish-sauce/herb toss. Skip the chili.'),
  ('Beef & Broccoli Stir-Fry', 'asian',
   E'Velveted flank steak and broccoli in a glossy garlic-ginger soy sauce over rice.\n\n1. Slice steak thin, toss with cornstarch.\n2. Cook rice; blanch or steam broccoli.\n3. Sear beef; add garlic, ginger, soy and a splash of water to glaze.\n4. Fold in broccoli; finish with sesame oil.',
   30, E'Reserve plain seared beef + soft broccoli + rice with the sauce on the side. Cut beef into small thin pieces.'),
  ('Coconut Chicken Curry', 'asian',
   E'Chicken thighs simmered in a mild coconut-red-curry sauce with peppers, over rice.\n\n1. Cook rice.\n2. Brown chicken thigh pieces; add onion, garlic, ginger.\n3. Stir in curry paste, then coconut milk and peppers; simmer until saucy.\n4. Finish with cilantro.',
   40, E'Reserve plain browned chicken + rice before the curry paste. The coconut sauce alone (no paste) also works for cautious eaters.'),
  ('Garlic-Ginger Shrimp Fried Rice', 'asian',
   E'Day-after rice fried with shrimp, egg, peas and carrot in a quick garlic-ginger soy.\n\n1. Scramble eggs; set aside.\n2. Stir-fry shrimp, then garlic, ginger, diced carrot and peas.\n3. Add cold rice; season with soy and sesame oil; fold eggs back in.\n4. Finish with scallion.',
   25, E'Scoop out plain rice + egg + peas before heavy soy. Chop shrimp small.'),
  ('Korean Beef Bulgogi Bowls', 'asian',
   E'Sweet-savory marinated flank steak seared hot, over rice with quick cucumber.\n\n1. Marinate thin-sliced steak in soy, brown sugar, sesame oil, garlic, ginger.\n2. Cook rice; smash-slice cucumber.\n3. Sear beef in batches until caramelized.\n4. Build bowls; (optional) gochujang on the side, sesame and scallion on top.',
   35, E'Reserve plain seared beef + rice before adding extra sauce. Keep gochujang off the kids'' bowls; slice beef small.'),
  ('Teriyaki Salmon & Bok Choy', 'asian',
   E'Glazed salmon and tender bok choy over rice in a homemade soy-mirin teriyaki.\n\n1. Simmer soy, mirin, brown sugar, ginger and garlic into a glaze.\n2. Cook rice; steam or saute bok choy.\n3. Roast or pan-sear salmon; spoon over glaze.\n4. Finish with sesame seeds.',
   30, E'Reserve a plain salmon piece + rice + soft bok choy leaves before glazing. Flake and check for bones.'),

  -- ---- Italian (8) ----
  ('Cacio e Pepe with Blistered Tomatoes', 'italian',
   E'Bucatini in a peppery pecorino emulsion with charred cherry tomatoes.\n\n1. Blister cherry tomatoes in olive oil; set aside.\n2. Toast cracked pepper; cook pasta, saving starchy water.\n3. Emulsify pecorino with butter and pasta water; toss with pasta.\n4. Top with tomatoes.',
   25, E'Plain buttered pasta with the tomatoes on the side. Hold the pepper for the little plate.'),
  ('Sheet-Pan Sausage & Peppers', 'italian',
   E'Italian sausage roasted with peppers and onions, served over crispy polenta rounds.\n\n1. Toss sliced peppers + onion with oil, garlic, oregano.\n2. Nestle sausages on top; roast until browned.\n3. Crisp polenta rounds; pile sausage and peppers over.',
   40, E'Slice a sausage lengthwise then into small half-moons (never coins). Serve with very soft peppers and a polenta round.'),
  ('Spaghetti & Turkey Meatballs', 'italian',
   E'Tender turkey meatballs in a simple tomato sauce over spaghetti.\n\n1. Mix turkey with egg, parmesan, garlic; roll small meatballs.\n2. Brown, then simmer in crushed-tomato sauce with oregano.\n3. Cook spaghetti; toss and top with parmesan.',
   40, E'Set aside a couple of plain small meatballs + buttered noodles. Quarter the meatballs so there is no round choking shape.'),
  ('Creamy Tuscan Chicken', 'italian',
   E'Seared chicken thighs in a parmesan cream with spinach and sun-dried tomato, over penne.\n\n1. Sear chicken; set aside.\n2. Build a cream sauce with garlic, sun-dried tomato, cream and parmesan; wilt spinach.\n3. Return chicken; serve over penne.',
   35, E'Reserve plain seared chicken + buttered penne before the cream sauce. Chop chicken small.'),
  ('Margherita Flatbread', 'italian',
   E'Crisp flatbread with fresh mozzarella, tomato and basil.\n\n1. Brush flatbread with garlic oil.\n2. Top with sliced fresh mozzarella and tomato.\n3. Bake hot until bubbling; finish with torn basil.',
   20, E'A toddler favorite. Cut into small squares and let cool so the cheese is not stringy-hot.'),
  ('Lemon Ricotta Pasta with Peas', 'italian',
   E'Silky lemon-ricotta sauce with sweet peas tossed through penne.\n\n1. Cook penne, saving pasta water.\n2. Stir ricotta, lemon zest/juice, parmesan and pasta water into a creamy sauce.\n3. Fold in peas; toss with pasta.',
   25, E'Naturally mild. Reserve plain buttered pasta + peas if the lemon is too tangy for them.'),
  ('Mushroom Risotto', 'italian',
   E'Creamy arborio risotto with sauteed mushrooms and parmesan. Friday stir-and-sip dish.\n\n1. Saute mushrooms; set aside.\n2. Toast arborio with onion and garlic; add warm stock a ladle at a time, stirring.\n3. Fold in mushrooms, butter and parmesan to finish.',
   50, E'Scoop out plain risotto before the final cheese-and-pepper hit. Soft and easy for little spoons.'),
  ('Baked Ziti', 'italian',
   E'Ziti baked in a beef-tomato sauce with ricotta and melted mozzarella.\n\n1. Brown beef with onion and garlic; simmer with crushed tomatoes and oregano.\n2. Boil ziti just shy of done.\n3. Layer pasta, sauce, ricotta, mozzarella; bake until golden.',
   45, E'Toddler-friendly. Serve a small, cooled portion cut up; the ricotta keeps it mild.'),

  -- ---- Wildcard (1) ----
  ('Sheet-Pan Greek Chicken & Potatoes', 'other',
   E'Lemon-oregano chicken thighs roasted with potatoes and peppers, finished with feta.\n\n1. Toss chicken, potato wedges and peppers with lemon, oregano, garlic and oil.\n2. Roast on one sheet until chicken is cooked and potatoes are crisp.\n3. Crumble feta over to finish.',
   45, E'Reserve plain chicken + soft potato before the lemon-heavy finish; skip the feta for the kids'' plate. Cut potato small and soft.')
) as v(title, cuisine_tag, body_md, time_minutes, toddler_variant_notes)
where not exists (select 1 from recipes r where r.title = v.title);

-- ---------------------------------------------------------------------------
-- 3. Recipe ingredients  (links resolved by name; idempotent on the PK)
-- ---------------------------------------------------------------------------
insert into recipe_ingredients (recipe_id, ingredient_id, quantity, unit, optional)
select r.id, i.id, v.quantity, v.unit, v.optional
from (values
  -- Carnitas Bowls
  ('Carnitas Bowls','pork shoulder',3,'lb',false),
  ('Carnitas Bowls','white rice',1.5,'cup',false),
  ('Carnitas Bowls','black beans',1,'can',false),
  ('Carnitas Bowls','red onion',1,'each',false),
  ('Carnitas Bowls','lime',4,'each',false),
  ('Carnitas Bowls','cilantro',1,'bunch',false),
  ('Carnitas Bowls','cotija',4,'oz',false),
  ('Carnitas Bowls','garlic',4,'clove',false),
  ('Carnitas Bowls','ground cumin',1,'tsp',false),
  ('Carnitas Bowls','olive oil',2,'tbsp',false),
  ('Carnitas Bowls','kosher salt',1,'tbsp',false),
  -- Chicken Tinga Tacos
  ('Chicken Tinga Tacos','chicken breast',1.5,'lb',false),
  ('Chicken Tinga Tacos','chipotle in adobo',2,'tbsp',false),
  ('Chicken Tinga Tacos','crushed tomatoes',1,'can',false),
  ('Chicken Tinga Tacos','yellow onion',1,'each',false),
  ('Chicken Tinga Tacos','garlic',3,'clove',false),
  ('Chicken Tinga Tacos','corn tortillas',1,'pack',false),
  ('Chicken Tinga Tacos','cilantro',1,'bunch',false),
  ('Chicken Tinga Tacos','cotija',3,'oz',false),
  ('Chicken Tinga Tacos','lime',3,'each',false),
  ('Chicken Tinga Tacos','olive oil',2,'tbsp',false),
  -- Chili-Lime Shrimp Fajitas
  ('Chili-Lime Shrimp Fajitas','shrimp',1.25,'lb',false),
  ('Chili-Lime Shrimp Fajitas','bell pepper',3,'each',false),
  ('Chili-Lime Shrimp Fajitas','yellow onion',1,'each',false),
  ('Chili-Lime Shrimp Fajitas','lime',3,'each',false),
  ('Chili-Lime Shrimp Fajitas','chili powder',2,'tsp',false),
  ('Chili-Lime Shrimp Fajitas','flour tortillas',1,'pack',false),
  ('Chili-Lime Shrimp Fajitas','garlic',3,'clove',false),
  ('Chili-Lime Shrimp Fajitas','olive oil',3,'tbsp',false),
  ('Chili-Lime Shrimp Fajitas','cilantro',1,'bunch',true),
  -- Black Bean & Sweet Potato Enchiladas
  ('Black Bean & Sweet Potato Enchiladas','sweet potato',2,'each',false),
  ('Black Bean & Sweet Potato Enchiladas','black beans',1,'can',false),
  ('Black Bean & Sweet Potato Enchiladas','enchilada sauce',1,'can',false),
  ('Black Bean & Sweet Potato Enchiladas','corn tortillas',1,'pack',false),
  ('Black Bean & Sweet Potato Enchiladas','mozzarella',6,'oz',false),
  ('Black Bean & Sweet Potato Enchiladas','yellow onion',1,'each',false),
  ('Black Bean & Sweet Potato Enchiladas','ground cumin',1,'tsp',false),
  ('Black Bean & Sweet Potato Enchiladas','cilantro',1,'bunch',true),
  -- Carne Asada Bowls
  ('Carne Asada Bowls','flank steak',1.5,'lb',false),
  ('Carne Asada Bowls','lime',4,'each',false),
  ('Carne Asada Bowls','cilantro',1,'bunch',false),
  ('Carne Asada Bowls','white rice',1.5,'cup',false),
  ('Carne Asada Bowls','avocado',2,'each',false),
  ('Carne Asada Bowls','roma tomato',2,'each',false),
  ('Carne Asada Bowls','red onion',1,'each',false),
  ('Carne Asada Bowls','garlic',3,'clove',false),
  ('Carne Asada Bowls','ground cumin',1,'tsp',false),
  ('Carne Asada Bowls','olive oil',2,'tbsp',false),
  -- Baja Fish Tacos
  ('Baja Fish Tacos','white fish fillets',1.25,'lb',false),
  ('Baja Fish Tacos','green cabbage',0.5,'each',false),
  ('Baja Fish Tacos','lime',3,'each',false),
  ('Baja Fish Tacos','sour cream',6,'oz',false),
  ('Baja Fish Tacos','corn tortillas',1,'pack',false),
  ('Baja Fish Tacos','smoked paprika',1,'tsp',false),
  ('Baja Fish Tacos','cilantro',1,'bunch',false),
  ('Baja Fish Tacos','olive oil',2,'tbsp',false),
  -- Pork & Hominy Pozole Verde
  ('Pork & Hominy Pozole Verde','pork shoulder',2,'lb',false),
  ('Pork & Hominy Pozole Verde','hominy',2,'can',false),
  ('Pork & Hominy Pozole Verde','tomatillo',1,'lb',false),
  ('Pork & Hominy Pozole Verde','yellow onion',1,'each',false),
  ('Pork & Hominy Pozole Verde','garlic',4,'clove',false),
  ('Pork & Hominy Pozole Verde','cilantro',1,'bunch',false),
  ('Pork & Hominy Pozole Verde','jalapeno',1,'each',true),
  ('Pork & Hominy Pozole Verde','lime',3,'each',false),
  ('Pork & Hominy Pozole Verde','ground cumin',1,'tsp',false),
  -- Cheesy Beef & Pepper Quesadillas
  ('Cheesy Beef & Pepper Quesadillas','ground beef',1,'lb',false),
  ('Cheesy Beef & Pepper Quesadillas','bell pepper',2,'each',false),
  ('Cheesy Beef & Pepper Quesadillas','yellow onion',1,'each',false),
  ('Cheesy Beef & Pepper Quesadillas','flour tortillas',1,'pack',false),
  ('Cheesy Beef & Pepper Quesadillas','mozzarella',6,'oz',false),
  ('Cheesy Beef & Pepper Quesadillas','chili powder',1,'tsp',false),
  ('Cheesy Beef & Pepper Quesadillas','olive oil',1,'tbsp',false),

  -- Miso Salmon Bowls
  ('Miso Salmon Bowls','salmon',1.25,'lb',false),
  ('Miso Salmon Bowls','miso paste',3,'tbsp',false),
  ('Miso Salmon Bowls','white rice',1.5,'cup',false),
  ('Miso Salmon Bowls','cucumber',1,'each',false),
  ('Miso Salmon Bowls','edamame',1,'bag',false),
  ('Miso Salmon Bowls','scallion',1,'bunch',false),
  ('Miso Salmon Bowls','mirin',2,'tbsp',false),
  ('Miso Salmon Bowls','soy sauce',2,'tbsp',false),
  ('Miso Salmon Bowls','sesame seeds',1,'tbsp',false),
  -- Thai Basil Chicken (Pad Krapow)
  ('Thai Basil Chicken (Pad Krapow)','ground chicken',1.25,'lb',false),
  ('Thai Basil Chicken (Pad Krapow)','thai basil',1,'bunch',false),
  ('Thai Basil Chicken (Pad Krapow)','garlic',5,'clove',false),
  ('Thai Basil Chicken (Pad Krapow)','thai chili',2,'each',true),
  ('Thai Basil Chicken (Pad Krapow)','white rice',1.5,'cup',false),
  ('Thai Basil Chicken (Pad Krapow)','soy sauce',2,'tbsp',false),
  ('Thai Basil Chicken (Pad Krapow)','fish sauce',1,'tbsp',false),
  ('Thai Basil Chicken (Pad Krapow)','brown sugar',1,'tsp',false),
  ('Thai Basil Chicken (Pad Krapow)','eggs',4,'each',false),
  ('Thai Basil Chicken (Pad Krapow)','vegetable oil',2,'tbsp',false),
  -- Chicken Larb Lettuce Cups
  ('Chicken Larb Lettuce Cups','ground chicken',1.25,'lb',false),
  ('Chicken Larb Lettuce Cups','lime',3,'each',false),
  ('Chicken Larb Lettuce Cups','fish sauce',2,'tbsp',false),
  ('Chicken Larb Lettuce Cups','fresh mint',1,'bunch',false),
  ('Chicken Larb Lettuce Cups','cilantro',1,'bunch',false),
  ('Chicken Larb Lettuce Cups','romaine hearts',2,'each',false),
  ('Chicken Larb Lettuce Cups','scallion',1,'bunch',false),
  ('Chicken Larb Lettuce Cups','thai chili',1,'each',true),
  ('Chicken Larb Lettuce Cups','white rice',1,'cup',false),
  -- Beef & Broccoli Stir-Fry
  ('Beef & Broccoli Stir-Fry','flank steak',1.25,'lb',false),
  ('Beef & Broccoli Stir-Fry','broccoli',1,'head',false),
  ('Beef & Broccoli Stir-Fry','garlic',4,'clove',false),
  ('Beef & Broccoli Stir-Fry','fresh ginger',1,'each',false),
  ('Beef & Broccoli Stir-Fry','soy sauce',3,'tbsp',false),
  ('Beef & Broccoli Stir-Fry','cornstarch',1,'tbsp',false),
  ('Beef & Broccoli Stir-Fry','white rice',1.5,'cup',false),
  ('Beef & Broccoli Stir-Fry','sesame oil',1,'tbsp',false),
  ('Beef & Broccoli Stir-Fry','vegetable oil',2,'tbsp',false),
  -- Coconut Chicken Curry
  ('Coconut Chicken Curry','chicken thighs',1.5,'lb',false),
  ('Coconut Chicken Curry','coconut milk',1,'can',false),
  ('Coconut Chicken Curry','thai red curry paste',2,'tbsp',false),
  ('Coconut Chicken Curry','bell pepper',2,'each',false),
  ('Coconut Chicken Curry','yellow onion',1,'each',false),
  ('Coconut Chicken Curry','garlic',3,'clove',false),
  ('Coconut Chicken Curry','fresh ginger',1,'each',false),
  ('Coconut Chicken Curry','white rice',1.5,'cup',false),
  ('Coconut Chicken Curry','cilantro',1,'bunch',true),
  -- Garlic-Ginger Shrimp Fried Rice
  ('Garlic-Ginger Shrimp Fried Rice','shrimp',1,'lb',false),
  ('Garlic-Ginger Shrimp Fried Rice','white rice',2,'cup',false),
  ('Garlic-Ginger Shrimp Fried Rice','eggs',3,'each',false),
  ('Garlic-Ginger Shrimp Fried Rice','peas',1,'bag',false),
  ('Garlic-Ginger Shrimp Fried Rice','carrot',2,'each',false),
  ('Garlic-Ginger Shrimp Fried Rice','scallion',1,'bunch',false),
  ('Garlic-Ginger Shrimp Fried Rice','garlic',4,'clove',false),
  ('Garlic-Ginger Shrimp Fried Rice','fresh ginger',1,'each',false),
  ('Garlic-Ginger Shrimp Fried Rice','soy sauce',3,'tbsp',false),
  ('Garlic-Ginger Shrimp Fried Rice','sesame oil',1,'tbsp',false),
  -- Korean Beef Bulgogi Bowls
  ('Korean Beef Bulgogi Bowls','flank steak',1.25,'lb',false),
  ('Korean Beef Bulgogi Bowls','soy sauce',3,'tbsp',false),
  ('Korean Beef Bulgogi Bowls','brown sugar',2,'tbsp',false),
  ('Korean Beef Bulgogi Bowls','sesame oil',1,'tbsp',false),
  ('Korean Beef Bulgogi Bowls','scallion',1,'bunch',false),
  ('Korean Beef Bulgogi Bowls','garlic',4,'clove',false),
  ('Korean Beef Bulgogi Bowls','fresh ginger',1,'each',false),
  ('Korean Beef Bulgogi Bowls','white rice',1.5,'cup',false),
  ('Korean Beef Bulgogi Bowls','cucumber',1,'each',false),
  ('Korean Beef Bulgogi Bowls','gochujang',1,'tbsp',true),
  ('Korean Beef Bulgogi Bowls','sesame seeds',1,'tbsp',false),
  -- Teriyaki Salmon & Bok Choy
  ('Teriyaki Salmon & Bok Choy','salmon',1.25,'lb',false),
  ('Teriyaki Salmon & Bok Choy','bok choy',3,'each',false),
  ('Teriyaki Salmon & Bok Choy','soy sauce',3,'tbsp',false),
  ('Teriyaki Salmon & Bok Choy','mirin',2,'tbsp',false),
  ('Teriyaki Salmon & Bok Choy','brown sugar',1,'tbsp',false),
  ('Teriyaki Salmon & Bok Choy','fresh ginger',1,'each',false),
  ('Teriyaki Salmon & Bok Choy','garlic',3,'clove',false),
  ('Teriyaki Salmon & Bok Choy','white rice',1.5,'cup',false),
  ('Teriyaki Salmon & Bok Choy','sesame seeds',1,'tbsp',false),

  -- Cacio e Pepe with Blistered Tomatoes
  ('Cacio e Pepe with Blistered Tomatoes','bucatini',1,'lb',false),
  ('Cacio e Pepe with Blistered Tomatoes','pecorino romano',4,'oz',false),
  ('Cacio e Pepe with Blistered Tomatoes','black pepper',1,'tbsp',false),
  ('Cacio e Pepe with Blistered Tomatoes','cherry tomatoes',1,'pint',false),
  ('Cacio e Pepe with Blistered Tomatoes','olive oil',2,'tbsp',false),
  ('Cacio e Pepe with Blistered Tomatoes','butter',2,'tbsp',false),
  -- Sheet-Pan Sausage & Peppers
  ('Sheet-Pan Sausage & Peppers','italian sausage',1,'lb',false),
  ('Sheet-Pan Sausage & Peppers','bell pepper',3,'each',false),
  ('Sheet-Pan Sausage & Peppers','yellow onion',1,'each',false),
  ('Sheet-Pan Sausage & Peppers','polenta',1,'each',false),
  ('Sheet-Pan Sausage & Peppers','olive oil',3,'tbsp',false),
  ('Sheet-Pan Sausage & Peppers','garlic',3,'clove',false),
  ('Sheet-Pan Sausage & Peppers','dried oregano',1,'tsp',false),
  -- Spaghetti & Turkey Meatballs
  ('Spaghetti & Turkey Meatballs','ground turkey',1.25,'lb',false),
  ('Spaghetti & Turkey Meatballs','spaghetti',1,'lb',false),
  ('Spaghetti & Turkey Meatballs','crushed tomatoes',1,'can',false),
  ('Spaghetti & Turkey Meatballs','parmesan',4,'oz',false),
  ('Spaghetti & Turkey Meatballs','garlic',4,'clove',false),
  ('Spaghetti & Turkey Meatballs','eggs',1,'each',false),
  ('Spaghetti & Turkey Meatballs','yellow onion',1,'each',false),
  ('Spaghetti & Turkey Meatballs','dried oregano',1,'tsp',false),
  ('Spaghetti & Turkey Meatballs','olive oil',2,'tbsp',false),
  -- Creamy Tuscan Chicken
  ('Creamy Tuscan Chicken','chicken thighs',1.5,'lb',false),
  ('Creamy Tuscan Chicken','baby spinach',1,'bag',false),
  ('Creamy Tuscan Chicken','sun-dried tomato',0.5,'jar',false),
  ('Creamy Tuscan Chicken','heavy cream',1,'cup',false),
  ('Creamy Tuscan Chicken','parmesan',3,'oz',false),
  ('Creamy Tuscan Chicken','garlic',4,'clove',false),
  ('Creamy Tuscan Chicken','penne',0.75,'lb',false),
  ('Creamy Tuscan Chicken','olive oil',2,'tbsp',false),
  -- Margherita Flatbread
  ('Margherita Flatbread','flatbread',2,'each',false),
  ('Margherita Flatbread','fresh mozzarella',8,'oz',false),
  ('Margherita Flatbread','roma tomato',3,'each',false),
  ('Margherita Flatbread','fresh basil',1,'bunch',false),
  ('Margherita Flatbread','olive oil',2,'tbsp',false),
  ('Margherita Flatbread','garlic',2,'clove',false),
  -- Lemon Ricotta Pasta with Peas
  ('Lemon Ricotta Pasta with Peas','penne',1,'lb',false),
  ('Lemon Ricotta Pasta with Peas','ricotta',8,'oz',false),
  ('Lemon Ricotta Pasta with Peas','lemon',2,'each',false),
  ('Lemon Ricotta Pasta with Peas','peas',1,'bag',false),
  ('Lemon Ricotta Pasta with Peas','parmesan',3,'oz',false),
  ('Lemon Ricotta Pasta with Peas','garlic',2,'clove',false),
  ('Lemon Ricotta Pasta with Peas','olive oil',2,'tbsp',false),
  -- Mushroom Risotto
  ('Mushroom Risotto','arborio rice',1.5,'cup',false),
  ('Mushroom Risotto','mushroom',1,'lb',false),
  ('Mushroom Risotto','parmesan',4,'oz',false),
  ('Mushroom Risotto','yellow onion',1,'each',false),
  ('Mushroom Risotto','garlic',3,'clove',false),
  ('Mushroom Risotto','butter',3,'tbsp',false),
  ('Mushroom Risotto','olive oil',2,'tbsp',false),
  -- Baked Ziti
  ('Baked Ziti','ziti',1,'lb',false),
  ('Baked Ziti','crushed tomatoes',1,'can',false),
  ('Baked Ziti','ricotta',8,'oz',false),
  ('Baked Ziti','mozzarella',8,'oz',false),
  ('Baked Ziti','ground beef',1,'lb',false),
  ('Baked Ziti','garlic',3,'clove',false),
  ('Baked Ziti','yellow onion',1,'each',false),
  ('Baked Ziti','dried oregano',1,'tsp',false),

  -- Sheet-Pan Greek Chicken & Potatoes
  ('Sheet-Pan Greek Chicken & Potatoes','chicken thighs',1.5,'lb',false),
  ('Sheet-Pan Greek Chicken & Potatoes','yukon potato',1.5,'lb',false),
  ('Sheet-Pan Greek Chicken & Potatoes','lemon',2,'each',false),
  ('Sheet-Pan Greek Chicken & Potatoes','dried oregano',2,'tsp',false),
  ('Sheet-Pan Greek Chicken & Potatoes','bell pepper',1,'each',false),
  ('Sheet-Pan Greek Chicken & Potatoes','feta',4,'oz',false),
  ('Sheet-Pan Greek Chicken & Potatoes','garlic',4,'clove',false),
  ('Sheet-Pan Greek Chicken & Potatoes','olive oil',3,'tbsp',false)
) as v(recipe_title, ingredient_name, quantity, unit, optional)
join recipes r on r.title = v.recipe_title
join ingredients i on i.name_canonical = v.ingredient_name
on conflict (recipe_id, ingredient_id) do nothing;

commit;

-- Sanity checks (uncomment to verify after load):
-- select cuisine_tag, count(*) from recipes where source='curated' group by 1;  -- mexican 8, asian 8, italian 8, other 1
-- select r.title, count(ri.*) ings from recipes r join recipe_ingredients ri on ri.recipe_id=r.id group by 1 order by 1;
-- select i.name_canonical, count(*) uses from ingredients i join recipe_ingredients ri on ri.ingredient_id=i.id group by 1 having count(*)>1 order by 2 desc;  -- shared ingredients
