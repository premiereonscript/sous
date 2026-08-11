// Tests for the canonical diet vocabulary + locale/timezone validation.
//
// These guard the seam where LLM tool output becomes a safety guarantee: the
// tool schema declares an enum, but the API does not enforce it, so anything
// that reaches the DB unvalidated silently becomes a no-op filter while the
// household is told their allergy is handled.
//
// Run: deno test supabase/functions/_shared/diet_test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import { DIET_KEYS, normalizeDiet } from "./diet.ts";
import { canonicalizeLocale } from "./household.ts";
import { localDayHour, normalizeTimezone, WEEKDAYS } from "./schedule.ts";

Deno.test("canonical keys pass through unchanged", () => {
  const r = normalizeDiet(["vegetarian", "no_nuts"], []);
  assertEquals(r.dietary_restrictions.sort(), ["no_nuts", "vegetarian"]);
  assertEquals(r.unrecognized, []);
});

Deno.test("case and whitespace are normalized", () => {
  const r = normalizeDiet([" Vegetarian ", "NO_EGG"], []);
  assertEquals(r.dietary_restrictions.sort(), ["no_egg", "vegetarian"]);
  assertEquals(r.unrecognized, []);
});

Deno.test("common model spellings map to canonical keys", () => {
  for (const [input, expected] of [
    ["nut_free", "no_nuts"],
    ["gluten-free", "gluten_free"],
    ["no_peanuts", "no_nuts"],
    ["vegitarian", "vegetarian"],
    ["lactose_free", "dairy_free"],
  ] as const) {
    const r = normalizeDiet([input], []);
    assertEquals(r.dietary_restrictions, [expected], `${input} should map to ${expected}`);
  }
});

Deno.test("an off-list restriction is NEVER silently dropped", () => {
  // The dangerous case: a key the SQL filter doesn't know becomes a no-op.
  // It must survive as an ingredient exclusion, which the filter DOES enforce.
  const r = normalizeDiet(["no_mushrooms"], []);
  assertEquals(r.dietary_restrictions, []);
  assert(
    r.excluded_ingredients.includes("mushrooms"),
    `expected mushrooms to be excluded, got ${JSON.stringify(r.excluded_ingredients)}`,
  );
  assertEquals(r.unrecognized, ["no_mushrooms"]);
});

Deno.test("explicit exclusions are preserved alongside diet keys", () => {
  const r = normalizeDiet(["vegan"], ["Cilantro", "peanuts"]);
  assertEquals(r.dietary_restrictions, ["vegan"]);
  assertEquals(r.excluded_ingredients.sort(), ["cilantro", "peanuts"]);
});

Deno.test("non-array / empty input yields empty arrays, not a crash", () => {
  for (const bad of [undefined, null, "vegetarian", 42, {}]) {
    const r = normalizeDiet(bad, bad);
    assertEquals(r.dietary_restrictions, []);
    assertEquals(r.excluded_ingredients, []);
  }
});

Deno.test("every declared key round-trips (tool enum matches the filter)", () => {
  const r = normalizeDiet([...DIET_KEYS], []);
  assertEquals(r.dietary_restrictions.length, DIET_KEYS.length);
  assertEquals(r.unrecognized, []);
});

Deno.test("a malformed locale never reaches Intl unguarded", () => {
  // es_ES with an underscore is a plausible model output and throws RangeError
  // in toLocaleDateString, which used to kill every subsequent plan send.
  assertEquals(canonicalizeLocale("es_ES"), "es-ES");
  assertEquals(canonicalizeLocale("es-ES"), "es-ES");
  assertEquals(canonicalizeLocale("  fr-FR "), "fr-FR");
  assertEquals(canonicalizeLocale("espanol!"), null);
  assertEquals(canonicalizeLocale("en US"), null);
  assertEquals(canonicalizeLocale(""), null);
});

Deno.test("anything canonicalizeLocale accepts is safe to format with", () => {
  for (const input of ["es_ES", "es-ES", "de-DE", "ja-JP", "pt_BR"]) {
    const loc = canonicalizeLocale(input);
    if (!loc) continue;
    // Must not throw — this is exactly the call planner.fmt() makes.
    new Date().toLocaleDateString(loc, { month: "short", day: "numeric", timeZone: "UTC" });
  }
});

Deno.test("timezone validation catches a plausible model hallucination", () => {
  assertEquals(normalizeTimezone("Europe/Berlin"), "Europe/Berlin");
  assertEquals(normalizeTimezone("America/Chicago"), "America/Chicago");
  assertEquals(normalizeTimezone(" utc "), "UTC");
  assertEquals(normalizeTimezone("Europe/Austin"), null); // city in the wrong region
  assertEquals(normalizeTimezone("Mars/Olympus"), null);
  assertEquals(normalizeTimezone(""), null);
  assertEquals(normalizeTimezone(undefined), null);
  assertEquals(normalizeTimezone(null), null);
});

Deno.test("bare abbreviations are rejected even though ICU accepts them", () => {
  // ICU resolves "EST" to America/Panama, which has no DST — a New York
  // household would silently slip an hour for half the year. "PST" resolves
  // correctly today, but the whole class is ambiguous, so refuse it and let
  // the model convert the city instead.
  for (const abbr of ["EST", "PST", "CST", "GMT", "PST8PDT"]) {
    assertEquals(normalizeTimezone(abbr), null, `${abbr} must be rejected`);
  }
});

Deno.test("anything normalizeTimezone accepts is safe for localDayHour", () => {
  for (const input of ["Europe/Berlin", "Asia/Tokyo", "America/New_York", "UTC"]) {
    const tz = normalizeTimezone(input);
    assert(tz, `${input} should normalize`);
    const { day, hour } = localDayHour(tz, new Date("2026-07-15T20:00:00Z"));
    assert(WEEKDAYS.includes(day), `bad weekday for ${tz}: ${day}`);
    assert(hour >= 0 && hour <= 23, `bad hour for ${tz}: ${hour}`);
  }
});
