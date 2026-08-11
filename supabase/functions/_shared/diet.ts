// Canonical diet vocabulary — the single source of truth for the keys that the
// SQL hard filter in 20260728000300_dietary_filter.sql knows how to enforce.
//
// This list was previously written out in five places (two prompts, two tool
// enums, and fifteen SQL predicates). A key that appears in a tool enum but not
// in the filter fails SILENTLY: the household is told their restriction is
// saved and no filtering happens. Import from here so that cannot drift.

export const DIET_KEYS = [
  "vegetarian",
  "vegan",
  "pescatarian",
  "gluten_free",
  "dairy_free",
  "halal",
  "kosher",
  "no_pork",
  "no_beef",
  "no_poultry",
  "no_shellfish",
  "no_fish",
  "no_nuts",
  "no_soy",
  "no_egg",
  "no_sesame",
] as const;

export type DietKey = typeof DIET_KEYS[number];

const KEY_SET = new Set<string>(DIET_KEYS);

// Common ways a model writes a key that isn't quite canonical. Anything not
// here and not canonical is treated as a free-text ingredient exclusion rather
// than dropped, because dropping it is the unsafe direction.
const ALIASES: Record<string, DietKey> = {
  veggie: "vegetarian",
  vegitarian: "vegetarian",
  "gluten-free": "gluten_free",
  glutenfree: "gluten_free",
  nut_free: "no_nuts",
  "nut-free": "no_nuts",
  no_peanuts: "no_nuts",
  no_tree_nuts: "no_nuts",
  "dairy-free": "dairy_free",
  lactose_free: "dairy_free",
  no_dairy: "dairy_free",
  no_gluten: "gluten_free",
  egg_free: "no_egg",
  no_eggs: "no_egg",
  no_seafood: "no_shellfish",
  pork_free: "no_pork",
};

export interface NormalizedDiet {
  /** Canonical keys the SQL filter can enforce. */
  dietary_restrictions: DietKey[];
  /** Free-text terms, including anything that wasn't a recognizable diet key. */
  excluded_ingredients: string[];
  /** Inputs we could not map to a key — surfaced so the user can be told. */
  unrecognized: string[];
}

const clean = (v: unknown): string[] =>
  Array.isArray(v) ? v.map((c) => String(c).trim().toLowerCase()).filter(Boolean) : [];

// Normalize whatever the LLM produced into something the hard filter enforces.
//
// The rule that matters: an unrecognized restriction is NEVER silently dropped.
// "no_peanuts" is not a canonical key, but a household that said it has a
// peanut allergy — so it lands in excluded_ingredients, where the filter
// matches it by ingredient name, alias and allergen token.
export function normalizeDiet(
  restrictions: unknown,
  excluded: unknown,
): NormalizedDiet {
  const diets = new Set<DietKey>();
  const extra = new Set<string>(clean(excluded));
  const unrecognized: string[] = [];

  for (const raw of clean(restrictions)) {
    const key = raw.replace(/\s+/g, "_");
    if (KEY_SET.has(key)) {
      diets.add(key as DietKey);
    } else if (ALIASES[key]) {
      diets.add(ALIASES[key]);
    } else {
      // Not a diet we can enforce structurally — keep it as an ingredient
      // exclusion so it still filters, and report it back.
      extra.add(raw.replace(/^no[_-]/, ""));
      unrecognized.push(raw);
    }
  }

  return {
    dietary_restrictions: [...diets],
    excluded_ingredients: [...extra],
    unrecognized,
  };
}
