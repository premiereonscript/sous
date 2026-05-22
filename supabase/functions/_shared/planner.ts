// Planner — propose a 5-dinner week (SPEC §8 rules, §9.3 Friday flow, §9.4).
//
// Flow: pull rotation candidates (candidate_recipes SQL) -> Sonnet picks 5 via
// the forced `propose_plan` tool -> validate against candidates -> write a
// 'proposed' meal_plan + items -> post §7.3 recipe cards to the chat.
//
// Day 5 adds the [Approve]/[Swap]/[Lock] inline keyboards + swap_meal/lock_plan.

import { dbClient } from "./db.ts";
import { completeRaw } from "./anthropic.ts";
import {
  editMessageText,
  escapeHtml as esc,
  type InlineKeyboard,
  sendMessage,
} from "./telegram.ts";
import {
  describeHousehold,
  getPreferences,
  type HouseholdDescription,
} from "./household.ts";

const swapButton = (itemId: string): InlineKeyboard => ({
  inline_keyboard: [[{ text: "🔄 Swap this dish", callback_data: `s:${itemId}` }]],
});
const lockButton = (planId: string): InlineKeyboard => ({
  inline_keyboard: [[{ text: "✅ Lock the week", callback_data: `l:${planId}` }]],
});

const PLANNER_MODEL = "claude-sonnet-4-6"; // SPEC §9.1

const CUISINE_EMOJI: Record<string, string> = {
  mexican: "🌮",
  asian: "🍜",
  italian: "🍝",
  other: "🍽️",
};
const CUISINE_LABEL: Record<string, string> = {
  mexican: "Mexican",
  asian: "Asian",
  italian: "Italian",
  other: "Other",
};
// Up to 7 dinners; the household picks how many (meals_per_week). The first N
// weekdays are used. Mon–Thu are "weeknights" (≤45 min); Fri/Sat/Sun can stretch.
const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
type DayKey = typeof DAY_KEYS[number];
const DAY_LABEL: Record<DayKey, string> = {
  mon: "Mon",
  tue: "Tue",
  wed: "Wed",
  thu: "Thu",
  fri: "Fri",
  sat: "Sat",
  sun: "Sun",
};
const WEEKNIGHTS = new Set<DayKey>(["mon", "tue", "wed", "thu"]);

interface Candidate {
  id: string;
  title: string;
  cuisine_tag: string;
  time_minutes: number;
  description: string;
  toddler_variant_notes: string | null;
  ingredients: string[];
  avg_rating: number | null;
  rating_count: number;
}

interface RecipeFull {
  id: string;
  title: string;
  cuisine_tag: string;
  time_minutes: number;
  body_md: string;
  toddler_variant_notes: string | null;
}

interface ShoppingRow {
  ingredient: string;
  quantity: number;
  unit: string;
  source: string;
}

interface WeekItem {
  recipe_id: string;
  day: string;
  recipes: { title: string; cuisine_tag: string } | null;
}

interface PlanItemInput {
  day: DayKey;
  recipe_id: string;
  why: string;
}

export async function proposePlan(conversationId: string): Promise<void> {
  const db = dbClient();
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN")!;

  const { data: convo } = await db
    .from("conversations")
    .select("id, household_id, telegram_chat_id")
    .eq("id", conversationId)
    .maybeSingle();
  if (!convo) {
    console.error("planner: conversation not found", conversationId);
    return;
  }

  const desc = describeHousehold(await getPreferences(db, convo.household_id));

  const { data: candData, error: candErr } = await db.rpc("candidate_recipes", {
    p_window_days: 28,
    p_limit: 40,
  });
  if (candErr) console.error("planner: candidate_recipes failed", candErr);
  const candidates = (candData ?? []) as Candidate[];
  // Plan as many dinners as they asked for, capped by what's in rotation.
  const n = Math.max(1, Math.min(desc.mealsPerWeek, candidates.length, 7));
  if (candidates.length === 0) {
    await sendMessage(
      botToken,
      convo.telegram_chat_id,
      "i don't have any recipes in rotation to plan with yet.",
    );
    return;
  }

  const weekOf = nextMonday();
  const { toolUses } = await completeRaw({
    apiKey: Deno.env.get("ANTHROPIC_API_KEY")!,
    model: PLANNER_MODEL,
    system: plannerSystem(candidates, weekOf, desc, n),
    messages: [{
      role: "user",
      content:
        `Plan ${n} dinner${n > 1 ? "s" : ""} for the week of ${weekOf}. Call propose_plan with exactly ${n} item${n > 1 ? "s" : ""}, choosing only from the candidate recipe_ids above.`,
    }],
    tools: [proposePlanTool(n)],
    toolChoice: { type: "tool", name: "propose_plan" },
    maxTokens: 2048,
  });

  const call = toolUses.find((t) => t.name === "propose_plan");
  const rawItems = (call?.input?.items ?? []) as PlanItemInput[];

  // Collect the distinct recipes the model picked (we assign days ourselves
  // below). The "why" travels with the recipe.
  const byId = new Map(candidates.map((c) => [c.id, c]));
  const seen = new Set<string>();
  const picked: { cand: Candidate; why: string }[] = [];
  for (const item of rawItems) {
    const cand = byId.get(item.recipe_id);
    if (!cand || seen.has(cand.id)) continue;
    seen.add(cand.id);
    picked.push({ cand, why: (item.why ?? "").trim() });
    if (picked.length === n) break;
  }

  if (picked.length === 0) {
    await sendMessage(
      botToken,
      convo.telegram_chat_id,
      "i botched that plan — give me a sec and ask again?",
    );
    return;
  }

  // Deterministically arrange across Mon–Fri so the §8 hard rules always hold:
  // no cuisine on consecutive days, and >45 min dishes only on Friday.
  const chosen = arrangeDays(picked);

  // Write a 'proposed' plan (replace any existing draft for the week).
  const { data: plan } = await db
    .from("meal_plans")
    .upsert(
      { household_id: convo.household_id, week_of: weekOf, status: "proposed" },
      { onConflict: "household_id,week_of" },
    )
    .select("id")
    .single();
  if (!plan) {
    console.error("planner: failed to upsert meal_plan");
    return;
  }
  await db.from("meal_plan_items").delete().eq("plan_id", plan.id);
  await db.from("meal_plan_items").insert(
    chosen.map((c, idx) => ({
      plan_id: plan.id,
      day: dayDate(weekOf, c.day),
      slot: "dinner",
      recipe_id: c.cand.id,
      position: idx,
    })),
  );

  // Fetch full recipe bodies (instructions) for the chosen dishes.
  const chosenIds = chosen.map((c) => c.cand.id);
  const { data: fullRows } = await db
    .from("recipes")
    .select("id, title, cuisine_tag, time_minutes, body_md, toddler_variant_notes")
    .in("id", chosenIds);
  const fullById = new Map(
    ((fullRows ?? []) as RecipeFull[]).map((r) => [r.id, r]),
  );

  // Map each chosen recipe to its meal_plan_item id (for the Swap buttons).
  const { data: items } = await db
    .from("meal_plan_items")
    .select("id, recipe_id")
    .eq("plan_id", plan.id);
  const itemIdByRecipe = new Map(
    ((items ?? []) as { id: string; recipe_id: string }[]).map((i) => [
      i.recipe_id,
      i.id,
    ]),
  );

  // One HTML message per card (full instructions + toddler version), each its
  // own readable bubble with a Swap button (SPEC §7.2 / §7.3).
  const post = async (text: string, markup?: InlineKeyboard) => {
    await db.from("messages").insert({
      conversation_id: convo.id,
      direction: "out",
      text,
    });
    return await sendMessage(botToken, convo.telegram_chat_id, text, "HTML", markup);
  };

  const lastDay = chosen[chosen.length - 1].day;
  const babyLine = desc.hasBaby
    ? `\n🍼 <i>Baby: pull a plain, soft, unsalted spoonful before salt/spice/acid — no honey.</i>`
    : "";
  await post(
    `🗒️ <b>Your week · ${esc(fmt(weekOf))}–${esc(fmt(dayDate(weekOf, lastDay)))}</b>\n` +
      `${chosen.length} dinner${chosen.length > 1 ? "s" : ""} below, then the shopping list. Tap 🔄 to swap any dish.${babyLine}`,
  );

  for (const c of chosen) {
    const itemId = itemIdByRecipe.get(c.cand.id);
    await post(
      renderCard(c, fullById.get(c.cand.id), desc),
      itemId ? swapButton(itemId) : undefined,
    );
  }

  // Build + post the total purchase list (SPEC §7.2 / §9.3).
  const { data: listRows } = await db.rpc("generate_shopping_list", {
    p_plan_id: plan.id,
  });
  const listMsgId = await post(
    renderShoppingList(weekOf, (listRows ?? []) as ShoppingRow[]),
  );

  // Lock prompt, with the button.
  const lockMsgId = await post(
    "Looks right? Lock it in for the week 👇",
    lockButton(plan.id),
  );

  // Remember the editable message ids for swap/lock updates.
  await db
    .from("conversations")
    .update({
      active_plan_id: plan.id,
      state: "proposing",
      state_payload: { shopping_msg_id: listMsgId, lock_msg_id: lockMsgId },
    })
    .eq("id", convo.id);
}

// ---- swap one dish (callback `s:<item_id>`) -----------------------------
const SWAP_MEAL_TOOL = {
  name: "swap_meal",
  description:
    "Replace one day's dinner with a different candidate recipe. Choose a recipe_id from the candidate list that keeps the week valid.",
  input_schema: {
    type: "object",
    properties: {
      recipe_id: { type: "string", description: "uuid of a candidate recipe" },
      why: { type: "string", description: "one short rationale for the swap" },
    },
    required: ["recipe_id", "why"],
  },
};

export async function swapMeal(
  conversationId: string,
  itemId: string,
  cardMessageId?: number,
): Promise<void> {
  const db = dbClient();
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN")!;

  const { data: convo } = await db
    .from("conversations")
    .select("id, household_id, telegram_chat_id, state_payload")
    .eq("id", conversationId)
    .maybeSingle();
  if (!convo) return;
  const desc = describeHousehold(await getPreferences(db, convo.household_id));

  const { data: item } = await db
    .from("meal_plan_items")
    .select("id, day, plan_id, recipe_id")
    .eq("id", itemId)
    .maybeSingle();
  if (!item) return;

  const { data: plan } = await db
    .from("meal_plans")
    .select("week_of")
    .eq("id", item.plan_id)
    .maybeSingle();

  // The current week (titles + cuisines) and the candidate pool minus this week.
  const { data: weekRaw } = await db
    .from("meal_plan_items")
    .select("recipe_id, day, recipes(title, cuisine_tag)")
    .eq("plan_id", item.plan_id);
  // Normalize the embedded relation (supabase-js types it as an array).
  const week: WeekItem[] = (weekRaw ?? []).map((w: Record<string, unknown>) => {
    const r = Array.isArray(w.recipes) ? w.recipes[0] : w.recipes;
    return {
      recipe_id: w.recipe_id as string,
      day: w.day as string,
      recipes: r ? { title: String(r.title), cuisine_tag: String(r.cuisine_tag) } : null,
    };
  });
  const inPlan = new Set(week.map((w) => w.recipe_id));

  const { data: candData } = await db.rpc("candidate_recipes", {
    p_window_days: 28,
    p_limit: 40,
  });
  const base = ((candData ?? []) as Candidate[]).filter((c) => !inPlan.has(c.id));
  if (base.length === 0) {
    await sendMessage(
      botToken,
      convo.telegram_chat_id,
      "i'm out of fresh options that keep the week varied — try locking or tell me what you want.",
    );
    return;
  }

  const dayKey = dateToDayKey(item.day);

  // Hard-enforce the §8 rules the model treats as soft: no cuisine on
  // consecutive days, and Mon–Thu stay ≤45 min. Fall back to the full pool
  // only if filtering leaves nothing.
  const sorted = [...week].sort((a, b) => (a.day < b.day ? -1 : 1));
  const idx = sorted.findIndex((w) => w.recipe_id === item.recipe_id);
  const neighborCuisines = new Set<string>();
  if (idx > 0) neighborCuisines.add(sorted[idx - 1].recipes?.cuisine_tag ?? "");
  if (idx >= 0 && idx < sorted.length - 1) {
    neighborCuisines.add(sorted[idx + 1].recipes?.cuisine_tag ?? "");
  }
  const isWeeknight = ["mon", "tue", "wed", "thu"].includes(dayKey);
  let pool = base.filter((c) =>
    !neighborCuisines.has(c.cuisine_tag) && (!isWeeknight || c.time_minutes <= 45)
  );
  if (pool.length === 0) pool = base;
  const { toolUses } = await completeRaw({
    apiKey: Deno.env.get("ANTHROPIC_API_KEY")!,
    model: PLANNER_MODEL,
    system: swapSystem(pool, week, dayKey),
    messages: [{
      role: "user",
      content:
        `Swap ${DAY_LABEL[dayKey]}'s dinner for a different candidate. Call swap_meal.`,
    }],
    tools: [SWAP_MEAL_TOOL],
    toolChoice: { type: "tool", name: "swap_meal" },
    maxTokens: 1024,
  });
  const call = toolUses.find((t) => t.name === "swap_meal");
  let cand = pool.find((c) => c.id === call?.input?.recipe_id);
  let why = String(call?.input?.why ?? "").trim();
  if (!cand) {
    cand = pool[Math.floor(Math.random() * pool.length)];
    why = why || "fresh pick to keep the week varied";
  }

  await db.from("meal_plan_items").update({ recipe_id: cand.id }).eq("id", item.id);

  const { data: full } = await db
    .from("recipes")
    .select("id, title, cuisine_tag, time_minutes, body_md, toddler_variant_notes")
    .eq("id", cand.id)
    .maybeSingle();

  // Replace the card in place if we came from a button tap; otherwise (a
  // natural-language swap) post a fresh card.
  const cardText = renderCard(
    { day: dayKey, cand, why },
    full as RecipeFull | undefined,
    desc,
  );
  if (cardMessageId) {
    await editMessageText(
      botToken,
      convo.telegram_chat_id,
      cardMessageId,
      cardText,
      "HTML",
      swapButton(item.id),
    );
  } else {
    await sendMessage(
      botToken,
      convo.telegram_chat_id,
      `🔄 New pick for ${DAY_LABEL[dayKey]}:\n\n${cardText}`,
      "HTML",
      swapButton(item.id),
    );
  }

  // Keep the shopping list accurate.
  const { data: listRows } = await db.rpc("generate_shopping_list", {
    p_plan_id: item.plan_id,
  });
  const listMsgId = (convo.state_payload as { shopping_msg_id?: number })?.shopping_msg_id;
  if (listMsgId && plan) {
    await editMessageText(
      botToken,
      convo.telegram_chat_id,
      listMsgId,
      renderShoppingList(plan.week_of, (listRows ?? []) as ShoppingRow[]),
      "HTML",
    );
  }
  await db.from("messages").insert({
    conversation_id: conversationId,
    direction: "out",
    text: `[swapped ${DAY_LABEL[dayKey]} → ${cand.title}]`,
  });
}

// ---- lock the week (callback `l:<plan_id>`) -----------------------------
export async function lockPlan(
  conversationId: string,
  planId: string,
): Promise<void> {
  const db = dbClient();
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN")!;

  const { data: convo } = await db
    .from("conversations")
    .select("id, telegram_chat_id, state_payload")
    .eq("id", conversationId)
    .maybeSingle();
  if (!convo) return;

  const { data: plan } = await db
    .from("meal_plans")
    .update({ status: "locked", locked_at: new Date().toISOString() })
    .eq("id", planId)
    .select("id, week_of")
    .maybeSingle();
  if (!plan) return;

  await db.from("conversations").update({ state: "locked" }).eq("id", conversationId);

  // Finalize the shopping list (reflect any swaps).
  const { data: listRows } = await db.rpc("generate_shopping_list", {
    p_plan_id: planId,
  });
  const payload = convo.state_payload as {
    shopping_msg_id?: number;
    lock_msg_id?: number;
  };
  if (payload?.shopping_msg_id) {
    await editMessageText(
      botToken,
      convo.telegram_chat_id,
      payload.shopping_msg_id,
      renderShoppingList(plan.week_of, (listRows ?? []) as ShoppingRow[]),
      "HTML",
    );
  }
  if (payload?.lock_msg_id) {
    await editMessageText(
      botToken,
      convo.telegram_chat_id,
      payload.lock_msg_id,
      "✅ <b>Locked for the week.</b> Shopping list above is final — see you at the market 🧺",
      "HTML",
      { inline_keyboard: [] },
    );
  }
  await db.from("messages").insert({
    conversation_id: conversationId,
    direction: "out",
    text: "[plan locked]",
  });
}

function swapSystem(
  pool: Candidate[],
  weekItems: WeekItem[],
  dayKey: DayKey,
): string {
  const week = weekItems
    .map((w) =>
      `${DAY_LABEL[dateToDayKey(w.day)]}: ${w.recipes?.title ?? "?"} (${w.recipes?.cuisine_tag ?? "?"})`
    )
    .join("\n");
  const menu = pool
    .map((c) => {
      const rating = c.avg_rating != null ? `rated ${c.avg_rating}/5` : "unrated";
      return `- ${c.id} | ${CUISINE_LABEL[c.cuisine_tag] ?? c.cuisine_tag} | ${c.time_minutes}min | ${rating} | ${c.title}`;
    })
    .join("\n");
  return `You are adjusting one dinner in an existing week for Goodbye Fresh. Replace ${DAY_LABEL[dayKey]}'s dinner.

Current week:
${week}

Replacement candidates (pick one recipe_id, none are already in the week):
${menu}

Keep the week valid (SPEC §8): don't repeat a cuisine on consecutive days, keep ${DAY_LABEL[dayKey]} ≤45 min if it's Mon–Thu, favor 4–5/5 ratings, and keep variety. Then call swap_meal.`;
}

// Order the picked recipes into Mon..Fri so no two adjacent days share a
// cuisine and any >45-min dish lands on Friday. Brute force (≤120 perms).
function arrangeDays(
  picked: { cand: Candidate; why: string }[],
): { day: DayKey; cand: Candidate; why: string }[] {
  const n = picked.length;
  const days = DAY_KEYS.slice(0, n);
  const valid = (perm: number[]): boolean => {
    for (let i = 0; i < n; i++) {
      const cand = picked[perm[i]].cand;
      if (WEEKNIGHTS.has(days[i]) && cand.time_minutes > 45) return false; // weeknight cap
      if (i > 0 && picked[perm[i - 1]].cand.cuisine_tag === cand.cuisine_tag) {
        return false; // no consecutive cuisine
      }
    }
    return true;
  };
  for (const perm of permutations([...Array(n).keys()])) {
    if (valid(perm)) {
      return perm.map((pi, i) => ({ day: days[i], ...picked[pi] }));
    }
  }
  // No arrangement satisfies every rule — keep the model's order.
  return picked.map((p, i) => ({ day: days[i], ...p }));
}

function permutations(arr: number[]): number[][] {
  if (arr.length <= 1) return [arr];
  const out: number[][] = [];
  for (let i = 0; i < arr.length; i++) {
    const rest = [...arr.slice(0, i), ...arr.slice(i + 1)];
    for (const p of permutations(rest)) out.push([arr[i], ...p]);
  }
  return out;
}

function dateToDayKey(dateStr: string): DayKey {
  const dow = new Date(`${dateStr}T00:00:00Z`).getUTCDay(); // 0 Sun..6 Sat
  const map: Record<number, DayKey> = {
    1: "mon",
    2: "tue",
    3: "wed",
    4: "thu",
    5: "fri",
    6: "sat",
    0: "sun",
  };
  return map[dow] ?? "mon";
}

// ---- natural-language entry points (no button/message id) ----------------

// "lock it" — lock the conversation's active plan.
export async function lockActivePlan(conversationId: string): Promise<void> {
  const db = dbClient();
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN")!;
  const { data: convo } = await db
    .from("conversations")
    .select("active_plan_id, telegram_chat_id")
    .eq("id", conversationId)
    .maybeSingle();
  if (!convo?.active_plan_id) {
    await sendMessage(
      botToken,
      convo?.telegram_chat_id ?? 0,
      "no active plan to lock yet — say “plan the week” and I'll put one together.",
    );
    return;
  }
  await lockPlan(conversationId, convo.active_plan_id);
}

// "swap wednesday" — swap a given day's dinner in the active plan.
export async function swapByDay(
  conversationId: string,
  dayKey: DayKey,
): Promise<void> {
  const db = dbClient();
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN")!;
  const { data: convo } = await db
    .from("conversations")
    .select("active_plan_id, telegram_chat_id")
    .eq("id", conversationId)
    .maybeSingle();
  if (!convo?.active_plan_id) {
    await sendMessage(
      botToken,
      convo?.telegram_chat_id ?? 0,
      "there's no plan to change yet — say “plan the week” first.",
    );
    return;
  }
  // Find the meal_plan_item for that weekday in the active plan.
  const { data: items } = await db
    .from("meal_plan_items")
    .select("id, day")
    .eq("plan_id", convo.active_plan_id);
  const match = (items ?? []).find(
    (i: { id: string; day: string }) => dateToDayKey(i.day) === dayKey,
  );
  if (!match) {
    await sendMessage(
      botToken,
      convo.telegram_chat_id,
      `i don't see a ${DAY_LABEL[dayKey]} dinner in the current plan.`,
    );
    return;
  }
  await swapMeal(conversationId, match.id); // no message id -> posts a fresh card
}

function renderCard(
  c: { day: DayKey; cand: Candidate; why: string },
  full: RecipeFull | undefined,
  desc: HouseholdDescription,
): string {
  const cand = c.cand;
  const emoji = CUISINE_EMOJI[cand.cuisine_tag] ?? "🍽️";
  const cuisine = CUISINE_LABEL[cand.cuisine_tag] ?? "Other";
  const stars = cand.avg_rating != null
    ? `  ${"★".repeat(Math.round(cand.avg_rating))}`
    : "";

  // body_md = description paragraph, then a blank line, then numbered steps.
  const body = full?.body_md ?? cand.description;
  const [intro, ...rest] = body.split("\n\n");
  const steps = rest.join("\n\n").trim();

  const lines: string[] = [];
  lines.push(`${emoji} <b>${esc(DAY_LABEL[c.day])} · ${esc(cand.title)}</b>`);
  lines.push(
    `<i>${esc(cuisine)} · ${cand.time_minutes} min · ${esc(desc.serving)}</i>${stars}`,
  );
  if (c.why) {
    lines.push("");
    lines.push(`💡 <i>${esc(c.why.trim())}</i>`);
  }
  lines.push("");
  lines.push(esc(intro.trim()));
  if (steps) {
    lines.push("");
    lines.push("👩‍🍳 <b>Make it</b>");
    lines.push(formatSteps(steps));
  }

  // Kid version (the prep fork) — only when there are kids in the household.
  const kidNote = full?.toddler_variant_notes ?? cand.toddler_variant_notes;
  if (desc.hasKids && kidNote) {
    lines.push("");
    lines.push(desc.hasBaby ? "👶 <b>For the little ones</b>" : "👶 <b>For the kids</b>");
    lines.push(esc(kidNote.trim()));
  }
  if (cand.ingredients?.includes("eggs")) {
    lines.push("");
    lines.push("🥚 <i>uses eggs from the coop</i>");
  }
  return lines.join("\n");
}

// "1. text" -> "<b>1.</b> text", everything escaped, one step per line.
function formatSteps(steps: string): string {
  return steps
    .split("\n")
    .filter((l) => l.trim())
    .map((line) => {
      const m = line.match(/^(\d+)\.\s*(.*)$/);
      return m ? `<b>${m[1]}.</b> ${esc(m[2])}` : esc(line);
    })
    .join("\n");
}

function renderShoppingList(weekOf: string, rows: ShoppingRow[]): string {
  const line = (r: ShoppingRow) =>
    `⬜ ${esc(r.ingredient)} — <b>${trimNum(r.quantity)} ${esc(r.unit)}</b>`;
  const section = (rs: ShoppingRow[]) =>
    rs.length ? rs.map(line).join("\n") : "<i>(nothing)</i>";

  const market = rows.filter((r) => r.source === "farmers_market");
  const grocery = rows.filter((r) => r.source === "grocery");

  return [
    `🛒 <b>Shopping list · week of ${esc(fmt(weekOf))}</b>`,
    "",
    "🧺 <b>Farmers Market</b>",
    section(market),
    "",
    "🏬 <b>Grocery</b>",
    section(grocery),
    "",
    "🥚 <i>Skipped (you have them): eggs</i>",
  ].join("\n");
}

function trimNum(n: number): string {
  return Number.isInteger(n) ? String(n) : String(Number(n.toFixed(2)));
}

// ---- propose_plan tool schema (SPEC §9.4) -------------------------------
// We assign days ourselves (arrangeDays), so the tool just returns N distinct
// recipe picks. Built per-request so minItems/maxItems match the meal count.
function proposePlanTool(n: number) {
  return {
    name: "propose_plan",
    description:
      `Write the draft dinner plan for the week. Provide exactly ${n} distinct items, each referencing a candidate recipe_id.`,
    input_schema: {
      type: "object",
      properties: {
        items: {
          type: "array",
          minItems: n,
          maxItems: n,
          items: {
            type: "object",
            properties: {
              recipe_id: {
                type: "string",
                description: "uuid of a recipe from the candidate list",
              },
              why: {
                type: "string",
                description:
                  "one short rationale tied to variety, season, ingredient overlap, or feedback",
              },
            },
            required: ["recipe_id", "why"],
          },
        },
      },
      required: ["items"],
    },
  };
}

function plannerSystem(
  candidates: Candidate[],
  weekOf: string,
  desc: HouseholdDescription,
  n: number,
): string {
  const menu = candidates
    .map((c) => {
      const rating = c.avg_rating != null
        ? `rated ${c.avg_rating}/5 (${c.rating_count})`
        : "unrated";
      return `- ${c.id} | ${CUISINE_LABEL[c.cuisine_tag] ?? c.cuisine_tag} | ${c.time_minutes}min | ${rating} | ${c.title} | ingredients: ${c.ingredients.join(", ")}`;
    })
    .join("\n");
  const budgetLine = desc.weeklyBudget
    ? `they shop one farmers-market + grocery run, ~$${desc.weeklyBudget}/week`
    : "they shop one farmers-market + grocery run";
  return `You are the planner for this household, choosing ${n} dinner${n > 1 ? "s" : ""} for the week. Today is ${
    new Date().toISOString().slice(0, 10)
  }; you are planning the week of ${weekOf}.

${desc.context}

Pick ONLY from these candidate recipes (use the recipe_id verbatim):
${menu}

Rules, in priority order:
1. Exactly ${n} distinct recipes.
2. Cuisine variety: lean into the cuisines they like; spread cuisines across the week (we'll order the days so none repeat back-to-back).
3. Weeknight cook time: most picks should be ≤45 min active; one longer "project" dish is fine.
4. Ingredient overlap for cost: prefer a set where several ingredients repeat across 2+ meals (${budgetLine}). Eggs are free (backyard chickens) — a mild plus.
5. Include at least one leftover-friendly dinner.
6. Kid-safe where relevant: picks carry a kid variant, and a plain soft portion can be pulled for any baby — favor dishes where that's easy.
7. Ratings: strongly prefer dishes rated 4–5/5; avoid 1–2/5 unless variety forces it (down-weight, don't ban). Treat "unrated" as neutral and fine to try.

Then call propose_plan with ${n} items. Each "why" is one honest, specific line (variety, season, overlap, or a callback) — no marketing voice.`;
}

// ---- date helpers --------------------------------------------------------
function nextMonday(d = new Date()): string {
  const dow = d.getUTCDay(); // 0 Sun .. 6 Sat
  let delta = (1 - dow + 7) % 7;
  if (delta === 0) delta = 7; // always the upcoming Monday, not today
  const m = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + delta));
  return m.toISOString().slice(0, 10);
}

function dayDate(weekOf: string, day: DayKey): string {
  const offset = DAY_KEYS.indexOf(day);
  const [y, mo, da] = weekOf.split("-").map(Number);
  const d = new Date(Date.UTC(y, mo - 1, da + offset));
  return d.toISOString().slice(0, 10);
}

function fmt(iso: string): string {
  const [y, mo, da] = iso.split("-").map(Number);
  const d = new Date(Date.UTC(y, mo - 1, da));
  return d.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  });
}
