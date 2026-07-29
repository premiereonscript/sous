// Unit tests for describeHousehold — the pure surface that turns a household's
// preferences into the context the planner + persona reason against. These
// guard the generalization work: a default household must carry NO assumptions
// about the original family (no free eggs, no kids, no farmers market).
//
// Run: deno test supabase/functions/_shared/household_test.ts

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { describeHousehold, DEFAULT_PREFS, type Preferences } from "./household.ts";

function prefs(overrides: Partial<Preferences> = {}): Preferences {
  return { ...DEFAULT_PREFS, ...overrides };
}

Deno.test("default household makes no free-staple (egg) assumption", () => {
  const d = describeHousehold(prefs());
  assertEquals(d.freeStaples, []);
  assert(
    !d.context.toLowerCase().includes("egg"),
    "default context must not mention eggs",
  );
  assert(
    !d.context.toLowerCase().includes("already have"),
    "default context must not claim the household already has anything",
  );
});

Deno.test("free staples flow into the descriptor and context", () => {
  const d = describeHousehold(prefs({ free_staples: ["eggs", "honey"] }));
  assertEquals(d.freeStaples, ["eggs", "honey"]);
  assertStringIncludes(d.context, "Already have");
  assertStringIncludes(d.context, "eggs and honey");
});

Deno.test("no kids => no baby/toddler flags and no food-safety line", () => {
  const d = describeHousehold(prefs({ adults: 2, kids: [] }));
  assertEquals(d.hasKids, false);
  assertEquals(d.hasBaby, false);
  assertEquals(d.serving, "serves 2");
  assert(!d.context.includes("Food safety"), "no safety line without kids");
});

Deno.test("a baby under 1 sets hasBaby and injects the no-honey safety note", () => {
  const d = describeHousehold(prefs({ adults: 2, kids: [{ age_months: 8 }] }));
  assertEquals(d.hasBaby, true);
  assertEquals(d.hasKids, true);
  assertStringIncludes(d.context, "NO honey");
});

Deno.test("a toddler (>=12mo) counts as a kid but not a baby", () => {
  const d = describeHousehold(prefs({ adults: 2, kids: [{ age_months: 30 }] }));
  assertEquals(d.hasBaby, false);
  assertEquals(d.hasKids, true);
  assertStringIncludes(d.context, "toddler");
});

Deno.test("weekly budget is derived from the monthly figure", () => {
  const d = describeHousehold(prefs({ monthly_budget_usd: 1000 }));
  // 1000 / 4.345 ≈ 230
  assertEquals(d.weeklyBudget, 230);
  const none = describeHousehold(prefs({ monthly_budget_usd: null }));
  assertEquals(none.weeklyBudget, null);
});

Deno.test("no dietary rules => no dietary line in context", () => {
  const d = describeHousehold(prefs());
  assert(!d.context.includes("Dietary rules"));
});

Deno.test("dietary restrictions + excluded ingredients render as HARD rules", () => {
  const d = describeHousehold(prefs({
    dietary_restrictions: ["vegetarian", "no_nuts"],
    excluded_ingredients: ["cilantro"],
  }));
  assertStringIncludes(d.context, "Dietary rules (HARD");
  assertStringIncludes(d.context, "vegetarian");
  assertStringIncludes(d.context, "no_nuts");
  assertStringIncludes(d.context, "cilantro");
});

Deno.test("cuisines are listed when present, omitted when empty", () => {
  assertStringIncludes(
    describeHousehold(prefs({ cuisines: ["korean", "mexican"] })).context,
    "korean and mexican",
  );
  assert(
    !describeHousehold(prefs({ cuisines: [] })).context.includes("Cuisines they like"),
  );
});
