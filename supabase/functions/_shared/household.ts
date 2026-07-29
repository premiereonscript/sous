// Household preferences — loaded once per request and turned into the dynamic
// context the persona + planner reason against (replaces hardcoded constraints).

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

export interface Kid {
  age_months: number;
}
export interface Preferences {
  adults: number;
  kids: Kid[];
  meals_per_week: number;
  monthly_budget_usd: number | null;
  // ISO 4217 currency + BCP-47 locale for formatting money/dates, and the
  // measurement system the LLM should generate quantities in.
  currency: string;
  unit_system: string; // "imperial" | "metric"
  locale: string;
  cuisines: string[];
  // Canonical diet keys the household needs honored (vegetarian, halal, no_pork,
  // …). Enforced as a hard filter in candidate_recipes — not just a prompt hint.
  dietary_restrictions: string[];
  // Specific ingredient names / allergen words to always avoid.
  excluded_ingredients: string[];
  // Ingredient names the household already has / gets for free, so they're kept
  // off the shopping list (e.g. eggs for a household with backyard chickens).
  // Empty by default — no assumption that anyone has a free source.
  free_staples: string[];
  // Chef voice: "weissman" (default), "neutral", or "warm".
  persona_style: string;
  // Shopping-list section labels, in order. Default a single "Grocery" bucket;
  // a household that also shops a market uses ["Farmers Market","Grocery"].
  shopping_sources: string[];
  // Planning rules (were hardcoded to the author's Mon–Thu ≤45-min schedule).
  weeknight_cap_minutes: number;
  weeknight_days: string[];
  plan_days: string[] | null; // explicit days to plan; null = first N weekdays
  avoid_consecutive_cuisine: boolean;
  onboarded: boolean;
}

export const DEFAULT_PREFS: Preferences = {
  adults: 2,
  kids: [],
  meals_per_week: 5,
  monthly_budget_usd: null,
  currency: "USD",
  unit_system: "imperial",
  locale: "en-US",
  cuisines: [],
  dietary_restrictions: [],
  excluded_ingredients: [],
  free_staples: [],
  persona_style: "weissman",
  shopping_sources: ["Grocery"],
  weeknight_cap_minutes: 45,
  weeknight_days: ["mon", "tue", "wed", "thu"],
  plan_days: null,
  avoid_consecutive_cuisine: true,
  onboarded: false,
};

export async function getPreferences(
  db: SupabaseClient,
  householdId: string,
): Promise<Preferences> {
  const { data } = await db
    .from("household_preferences")
    .select("*")
    .eq("household_id", householdId)
    .maybeSingle();
  if (!data) return { ...DEFAULT_PREFS };
  return {
    adults: data.adults ?? 2,
    kids: (data.kids ?? []) as Kid[],
    meals_per_week: data.meals_per_week ?? 5,
    monthly_budget_usd: data.monthly_budget_usd ?? null,
    currency: (data.currency ?? "USD") as string,
    unit_system: (data.unit_system ?? "imperial") as string,
    locale: (data.locale ?? "en-US") as string,
    cuisines: (data.cuisines ?? []) as string[],
    dietary_restrictions: (data.dietary_restrictions ?? []) as string[],
    excluded_ingredients: (data.excluded_ingredients ?? []) as string[],
    free_staples: (data.free_staples ?? []) as string[],
    persona_style: (data.persona_style ?? "weissman") as string,
    shopping_sources: (data.shopping_sources ?? ["Grocery"]) as string[],
    weeknight_cap_minutes: (data.weeknight_cap_minutes ?? 45) as number,
    weeknight_days: (data.weeknight_days ?? ["mon", "tue", "wed", "thu"]) as string[],
    plan_days: (data.plan_days ?? null) as string[] | null,
    avoid_consecutive_cuisine: data.avoid_consecutive_cuisine ?? true,
    onboarded: !!data.onboarded,
  };
}

// Partial update to a household's preferences — only the provided fields
// change. Used by the chat agent so cuisines/budget/meals/kids can be edited
// any time, not just during first-run onboarding.
export interface PreferenceUpdate {
  adults?: number;
  kids?: Kid[];
  meals_per_week?: number;
  monthly_budget_usd?: number | null;
  cuisines?: string[];
  dietary_restrictions?: string[];
  excluded_ingredients?: string[];
  free_staples?: string[];
  persona_style?: string;
  currency?: string;
  unit_system?: string;
  locale?: string;
  shopping_sources?: string[];
}

export async function updatePreferences(
  db: SupabaseClient,
  householdId: string,
  patch: PreferenceUpdate,
): Promise<Preferences> {
  const current = await getPreferences(db, householdId);
  const next: Preferences = { ...current, onboarded: true };
  if (patch.adults !== undefined) next.adults = patch.adults;
  if (patch.kids !== undefined) next.kids = patch.kids;
  if (patch.meals_per_week !== undefined) next.meals_per_week = patch.meals_per_week;
  if (patch.monthly_budget_usd !== undefined) {
    next.monthly_budget_usd = patch.monthly_budget_usd;
  }
  if (patch.cuisines !== undefined) next.cuisines = patch.cuisines;
  if (patch.dietary_restrictions !== undefined) {
    next.dietary_restrictions = patch.dietary_restrictions;
  }
  if (patch.excluded_ingredients !== undefined) {
    next.excluded_ingredients = patch.excluded_ingredients;
  }
  if (patch.free_staples !== undefined) next.free_staples = patch.free_staples;
  if (patch.persona_style !== undefined) next.persona_style = patch.persona_style;
  if (patch.currency !== undefined) next.currency = patch.currency;
  if (patch.unit_system !== undefined) next.unit_system = patch.unit_system;
  if (patch.locale !== undefined) next.locale = patch.locale;
  if (patch.shopping_sources !== undefined) next.shopping_sources = patch.shopping_sources;

  const { error } = await db.from("household_preferences").upsert(
    {
      household_id: householdId,
      adults: next.adults,
      kids: next.kids,
      meals_per_week: next.meals_per_week,
      monthly_budget_usd: next.monthly_budget_usd,
      currency: next.currency,
      unit_system: next.unit_system,
      locale: next.locale,
      cuisines: next.cuisines,
      dietary_restrictions: next.dietary_restrictions,
      excluded_ingredients: next.excluded_ingredients,
      free_staples: next.free_staples,
      persona_style: next.persona_style,
      shopping_sources: next.shopping_sources,
      onboarded: true,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "household_id" },
  );
  if (error) console.error("updatePreferences failed", error);
  return next;
}

export interface HouseholdDescription {
  serving: string; // e.g. "serves 2 adults + 2 kids"
  context: string; // multi-line block for the system prompt
  hasBaby: boolean; // any kid < 12 months
  hasKids: boolean;
  mealsPerWeek: number;
  weeklyBudget: number | null;
  freeStaples: string[]; // ingredients the household already has (off the list)
  personaStyle: string; // chef voice: weissman | neutral | warm
  currency: string;
  unitSystem: string;
  locale: string;
  weeknightCapMinutes: number;
  weeknightDays: string[];
  planDays: string[] | null;
  avoidConsecutiveCuisine: boolean;
  shoppingSources: string[];
}

const WEEKS_PER_MONTH = 4.345;

// Format an amount in the household's currency + locale (e.g. "$230", "€230").
export function formatMoney(amount: number, currency = "USD", locale = "en-US"): string {
  try {
    return new Intl.NumberFormat(locale, {
      style: "currency",
      currency,
      maximumFractionDigits: 0,
    }).format(amount);
  } catch {
    return `${currency} ${Math.round(amount)}`;
  }
}

export function describeHousehold(p: Preferences): HouseholdDescription {
  const hasBaby = p.kids.some((k) => k.age_months < 12);
  const hasKids = p.kids.length > 0;
  const weeklyBudget = p.monthly_budget_usd != null
    ? Math.round(p.monthly_budget_usd / WEEKS_PER_MONTH)
    : null;

  const people = [adultsPhrase(p.adults), ...p.kids.map(kidPhrase)];
  const peopleSentence = joinList(people);
  const serving = hasKids
    ? `serves ${p.adults} + ${p.kids.length} kid${p.kids.length > 1 ? "s" : ""}`
    : `serves ${p.adults}`;

  const lines = [`This household:`, `- People: ${peopleSentence}.`];
  lines.push(`- Dinners to plan per week: ${p.meals_per_week}.`);
  if (weeklyBudget) {
    lines.push(
      `- Grocery budget: ~${formatMoney(weeklyBudget, p.currency, p.locale)}/week (from ${
        formatMoney(p.monthly_budget_usd!, p.currency, p.locale)
      }/month).`,
    );
  }
  if (p.unit_system === "metric") {
    lines.push("- Use METRIC units (g, kg, ml, L, °C) in recipes and the shopping list.");
  }
  if (p.cuisines.length) {
    lines.push(`- Cuisines they like: ${joinList(p.cuisines)}.`);
  }
  const avoid = [...p.dietary_restrictions, ...p.excluded_ingredients];
  if (avoid.length) {
    lines.push(
      `- Dietary rules (HARD — never suggest anything that violates these; already filtered from your options): ${joinList(avoid)}.`,
    );
  }
  if (p.free_staples.length) {
    lines.push(
      `- Already have (don't add to the shopping list, a mild cost plus): ${joinList(p.free_staples)}.`,
    );
  }

  const safety: string[] = [];
  if (hasBaby) {
    safety.push(
      "There's a baby under 1: pull a plain, soft, mashed, UNSALTED portion before salt/spice/acid; NO honey; no choking shapes.",
    );
  }
  if (p.kids.some((k) => k.age_months >= 12 && k.age_months <= 48)) {
    safety.push(
      "There's a toddler: low spice, and quarter/halve choking shapes (whole grapes, nuts, popcorn, coins of sausage).",
    );
  }
  if (safety.length) lines.push(`Food safety: ${safety.join(" ")}`);

  return {
    serving,
    context: lines.join("\n"),
    hasBaby,
    hasKids,
    mealsPerWeek: p.meals_per_week,
    weeklyBudget,
    freeStaples: p.free_staples,
    personaStyle: p.persona_style,
    currency: p.currency,
    unitSystem: p.unit_system,
    locale: p.locale,
    weeknightCapMinutes: p.weeknight_cap_minutes,
    weeknightDays: p.weeknight_days,
    planDays: p.plan_days,
    avoidConsecutiveCuisine: p.avoid_consecutive_cuisine,
    shoppingSources: p.shopping_sources,
  };
}

function adultsPhrase(n: number): string {
  if (n === 1) return "one adult";
  if (n === 2) return "two adults";
  return `${n} adults`;
}

function kidPhrase(k: Kid): string {
  const m = k.age_months;
  if (m < 12) return `a ${m}-month-old baby`;
  const yrs = m / 12;
  const rounded = Math.round(yrs * 2) / 2; // nearest half-year
  const label = Number.isInteger(rounded)
    ? `${rounded}`
    : `${Math.floor(rounded)}½`;
  return `a ${label}-year-old`;
}

function joinList(items: string[]): string {
  if (items.length <= 1) return items.join("");
  if (items.length === 2) return `${items[0]} and ${items[1]}`;
  return `${items.slice(0, -1).join(", ")}, and ${items[items.length - 1]}`;
}
