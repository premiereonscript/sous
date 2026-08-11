// Tests for pure planner rendering helpers: configurable shopping sources (T6)
// and graceful cuisine labels (T8).
//
// Run: deno test supabase/functions/_shared/planner_test.ts

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { arrangeDays, cuisineLabel, DAY_KEYS, renderShoppingList } from "./planner.ts";
import { DEFAULT_PREFS, describeHousehold } from "./household.ts";

const rows = [
  { ingredient: "carrot", quantity: 2, unit: "each", source: "farmers_market" },
  { ingredient: "rice", quantity: 1, unit: "bag", source: "grocery" },
];

Deno.test("default single-source household gets ONE bucket with everything", () => {
  const out = renderShoppingList("2026-08-03", rows, [], ["Grocery"]);
  assertStringIncludes(out, "Grocery");
  assertStringIncludes(out, "carrot"); // market item still shows
  assertStringIncludes(out, "rice");
  assert(!out.includes("Farmers Market"), "single-source list must not split out a market section");
});

Deno.test("a two-source household splits market vs grocery, with its own labels", () => {
  const out = renderShoppingList("2026-08-03", rows, [], ["Farmers Market", "Grocery"]);
  assertStringIncludes(out, "Farmers Market");
  assertStringIncludes(out, "Grocery");
  // carrot (farmers_market) appears under the market label, before Grocery.
  assert(out.indexOf("carrot") < out.indexOf("🏬"), "market items come before the grocery section");
});

Deno.test("custom store labels are honored", () => {
  const out = renderShoppingList("2026-08-03", rows, [], ["Costco"]);
  assertStringIncludes(out, "Costco");
});

Deno.test("free-staples footer only shows when there are free staples", () => {
  assert(!renderShoppingList("2026-08-03", rows, [], ["Grocery"]).includes("Skipped"));
  assertStringIncludes(
    renderShoppingList("2026-08-03", rows, ["eggs"], ["Grocery"]),
    "Skipped (you have): eggs",
  );
});

Deno.test("cuisineLabel falls back to a title-cased tag for unknown cuisines", () => {
  assertEquals(cuisineLabel("mexican"), "Mexican");
  assertEquals(cuisineLabel("indian"), "Indian"); // not in the label map, fallback
  assertEquals(cuisineLabel("middle_eastern"), "Middle Eastern");
});

Deno.test("two stores with no farmers market don't produce a duplicate label", () => {
  // Regression: marketLabel and groceryLabel both resolved to sources[0], so
  // the list printed "Costco" twice — once over an empty section, because the
  // seasonal farmers_market hint means nothing to a household without a market.
  const out = renderShoppingList("2026-08-03", rows, [], ["Costco", "Trader Joes"]);
  assertEquals(out.match(/Costco/g)?.length, 1, "Costco must appear exactly once");
  assertStringIncludes(out, "Trader Joes");
  assert(!out.includes("(nothing)"), "must not render an empty phantom section");
  assertStringIncludes(out, "carrot");
  assertStringIncludes(out, "rice");
});

Deno.test("a third store is never silently dropped", () => {
  // Regression: only sources[0] and the first non-market label were rendered,
  // so "Butcher" vanished from the list entirely.
  const out = renderShoppingList("2026-08-03", rows, [], [
    "Farmers Market",
    "Grocery",
    "Butcher",
  ]);
  assertStringIncludes(out, "Farmers Market");
  assertStringIncludes(out, "Grocery");
  assertStringIncludes(out, "Butcher");
});

Deno.test("the shopping list header honors the household's locale", () => {
  // Regression: every other date got desc.locale threaded through, but this
  // header kept the en-US default — so a Spanish household saw a localized
  // plan header and a US-formatted date on the list right beneath it.
  const es = renderShoppingList("2026-08-03", rows, [], ["Grocery"], "es-ES");
  const en = renderShoppingList("2026-08-03", rows, [], ["Grocery"], "en-US");
  assertStringIncludes(en, "Aug 3");
  assert(!es.includes("Aug 3"), `expected a localized date, got: ${es.split("\n")[0]}`);
});

Deno.test("a bad locale already in the DB degrades instead of throwing", () => {
  // fmt() was the only Intl call without a guard; "es_ES" threw RangeError and
  // took out the whole send after the plan row had been written.
  const out = renderShoppingList("2026-08-03", rows, [], ["Grocery"], "es_ES");
  assertStringIncludes(out, "Aug 3");
});

// ---- arrangeDays ---------------------------------------------------------

const cand = (time: number, cuisine: string) => ({
  cand: {
    id: crypto.randomUUID(),
    title: `${cuisine} ${time}`,
    cuisine_tag: cuisine,
    time_minutes: time,
    description: "",
    toddler_variant_notes: null,
    ingredients: [],
    avg_rating: null,
    rating_count: 0,
  },
  why: "",
});

const descWith = (over: Partial<ReturnType<typeof describeHousehold>>) => ({
  ...describeHousehold({ ...DEFAULT_PREFS }),
  ...over,
});

Deno.test("plan_days shorter than the meal count never yields an undefined day", () => {
  // Regression: days.slice(0, n) was shorter than n, so the tail arrived as
  // `day: undefined` — which dayDate() turns into indexOf(-1), shifting the
  // date a day earlier, and the card rendered "undefined".
  const picked = [cand(20, "asian"), cand(20, "italian"), cand(20, "mexican")];
  const out = arrangeDays(picked, descWith({ planDays: ["sat", "sun"] }));
  assertEquals(out.length, 3);
  for (const o of out) {
    assert(DAY_KEYS.includes(o.day), `not a real day key: ${JSON.stringify(o.day)}`);
  }
  assertEquals(new Set(out.map((o) => o.day)).size, 3, "days must be distinct");
});

Deno.test("junk in plan_days is discarded rather than rendered", () => {
  const picked = [cand(20, "asian"), cand(20, "italian")];
  const out = arrangeDays(picked, descWith({ planDays: ["monday", "Sat", ""] }));
  for (const o of out) {
    assert(DAY_KEYS.includes(o.day), `not a real day key: ${JSON.stringify(o.day)}`);
  }
});

Deno.test("a valid plan_days list is still honored in order", () => {
  const picked = [cand(20, "asian"), cand(20, "italian")];
  const out = arrangeDays(picked, descWith({ planDays: ["sat", "sun"] }));
  assertEquals(out.map((o) => o.day), ["sat", "sun"]);
});

Deno.test("the weeknight cap and cuisine rule are per-household", () => {
  // avoidConsecutiveCuisine off => two asian dishes may sit next to each other.
  const picked = [cand(20, "asian"), cand(20, "asian")];
  const out = arrangeDays(picked, descWith({ avoidConsecutiveCuisine: false }));
  assertEquals(out.length, 2);
  for (const o of out) assert(DAY_KEYS.includes(o.day));
});
