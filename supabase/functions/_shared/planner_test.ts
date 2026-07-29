// Tests for pure planner rendering helpers: configurable shopping sources (T6)
// and graceful cuisine labels (T8).
//
// Run: deno test supabase/functions/_shared/planner_test.ts

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { cuisineLabel, renderShoppingList } from "./planner.ts";

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
