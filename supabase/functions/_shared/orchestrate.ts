// Core orchestration (SPEC §9.3 "User reply") — the conversational brain, shared
// so it can run either in-process from tg_webhook (via EdgeRuntime.waitUntil) or
// from the standalone orchestrator HTTP function.
//
// This used to be a one-shot chat that could only log a rating — so any request
// that wasn't a clean plan/swap/lock command got sympathy and nothing else.
// It's now a small agent: it sees the current week + recent history and can
// actually act — swap a dish (honoring what was asked), plan or lock a week,
// permanently exclude a dish, update household preferences, or expand a recipe.

import { dbClient } from "./db.ts";
import { completeRaw, type Msg, normalize } from "./anthropic.ts";
import { sendMessage } from "./telegram.ts";
import { sousSystem } from "./persona.ts";
import {
  describeHousehold,
  getPreferences,
  type Kid,
  updatePreferences,
} from "./household.ts";
import {
  customizeMeal,
  DAY_KEYS,
  type DayKey,
  expandRecipe,
  lockActivePlan,
  proposePlan,
  sendShoppingList,
  swapByDay,
} from "./planner.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

const WORKHORSE_MODEL = "claude-sonnet-4-6"; // SPEC §9.1
const MAX_TOOL_ROUNDS = 5;

// ---- tools the chat agent can call ---------------------------------------
const TOOLS = [
  {
    name: "rate_meal",
    description:
      "Record the household's rating for a specific dish on a 1-5 scale (5 = best). Call whenever the user expresses how much they liked or disliked a named dish — a number ('carnitas were a 5') or clear sentiment ('kids loved the ziti', 'the curry was a miss').",
    input_schema: {
      type: "object",
      properties: {
        recipe_title: { type: "string", description: "the dish as the user referred to it" },
        rating: { type: "integer", minimum: 1, maximum: 5 },
        note: { type: "string", description: "optional short note" },
      },
      required: ["recipe_title", "rating"],
    },
  },
  {
    name: "swap_meal",
    description:
      "Replace one day's dinner in the CURRENT week's plan. Use when the user wants a different dish for a day ('swap thursday', 'something else wednesday', 'not fish tonight'). Put whatever they asked for into `request` verbatim ('something vegetarian', 'tacos', 'quick and cheap') so the replacement honors it. Posts a fresh recipe card itself.",
    input_schema: {
      type: "object",
      properties: {
        day: {
          type: "string",
          enum: [...DAY_KEYS],
          description: "which weekday's dinner to change",
        },
        request: {
          type: "string",
          description: "the user's own words for what they want instead, if any",
        },
      },
      required: ["day"],
    },
  },
  {
    name: "plan_week",
    description:
      "Propose next week's dinners. Use when the user wants a new week ('plan next week', 'what are we eating', 'give me a new plan'). Posts the full plan + shopping list itself.",
    input_schema: { type: "object", properties: {} },
  },
  {
    name: "lock_week",
    description:
      "Finalize/lock the current proposed week so the shopping list is final. Use for 'lock it', 'looks good', 'that works'.",
    input_schema: { type: "object", properties: {} },
  },
  {
    name: "exclude_recipe",
    description:
      "Permanently stop suggesting a dish — a hard 'never again', stronger than a bad rating. Use for 'stop giving us X', 'never make X again', 'we're done with X'. If that dish is on the current week, also call swap_meal for its day to replace it now.",
    input_schema: {
      type: "object",
      properties: {
        recipe_title: { type: "string" },
        reason: { type: "string", description: "optional short reason" },
      },
      required: ["recipe_title"],
    },
  },
  {
    name: "update_preferences",
    description:
      "Change the household's standing preferences (they persist and shape every future plan). Use for 'we like Thai now', 'bump us to 4 dinners a week', 'budget is $900/month', 'the baby is 11 months now'. Only include the fields that changed.",
    input_schema: {
      type: "object",
      properties: {
        adults: { type: "integer", minimum: 1 },
        kids: {
          type: "array",
          description: "FULL replacement list of kids, one entry each; [] for none",
          items: {
            type: "object",
            properties: { age_months: { type: "integer", minimum: 0, maximum: 215 } },
            required: ["age_months"],
          },
        },
        meals_per_week: { type: "integer", minimum: 1, maximum: 7 },
        monthly_budget_usd: { type: "number", minimum: 0 },
        cuisines: {
          type: "array",
          items: { type: "string" },
          description: "FULL replacement list of preferred cuisines",
        },
      },
    },
  },
  {
    name: "customize_meal",
    description:
      "Tweak ONE ingredient of a day's dinner while KEEPING the dish (don't swap it away). Use for 'add sausage to the pesto pasta', 'swap the cream for coconut milk', 'make thursday gluten-free', 'leave the cilantro off'. Rewrites the recipe + updates the grocery list. Put the user's change verbatim in `change`. (For a whole different dish, use swap_meal instead.)",
    input_schema: {
      type: "object",
      properties: {
        day: { type: "string", enum: [...DAY_KEYS], description: "which day's dinner to tweak" },
        change: { type: "string", description: "the requested change in the user's words" },
      },
      required: ["day", "change"],
    },
  },
  {
    name: "expand_recipe",
    description:
      "Send the full, detailed recipe for a dish — real ingredient quantities, step-by-step method, chef's tips. Use for 'full recipe for X', 'how do I make X', 'more detail on thursday'.",
    input_schema: {
      type: "object",
      properties: { recipe_title: { type: "string" } },
      required: ["recipe_title"],
    },
  },
  {
    name: "send_shopping_list",
    description:
      "Post the current week's shopping list as a fresh message (farmers market + grocery, always up to date with any swaps). Use ANY time the user asks for the list — 'send me the grocery list', 'what do I need to buy', 'updated shopping list', 'text me the list'. Never tell the user to scroll up; just send it.",
    input_schema: { type: "object", properties: {} },
  },
];

const AGENT_INSTRUCTION =
  `\n\nYou can DO things, not just talk — use the tools when the user wants an action (swap, plan, lock, rate, exclude, change preferences, a full recipe, or the shopping list). Some tools post their own message (a card, a plan, a recipe, the list); when they do, keep your own reply to one short line so you're not repeating what it shows. Never claim you did something without calling the matching tool.

Key rules:
- If they ask for the grocery/shopping list in ANY form, call send_shopping_list. NEVER say you can't send it and NEVER tell them to scroll up — the list is always available.
- Ingredient tweak vs. whole new dish: if they want to change ONE thing but keep the dish ("add sausage to the pesto pasta", "swap cream for coconut milk", "leave off the cilantro", "make it gluten-free"), use customize_meal — it rewrites that recipe and updates the grocery list. Only use swap_meal when they want a genuinely different dinner. Don't ask for a dish title you can look up yourself.
- You can see the current week and recent history below — use them to answer honestly (e.g. how often a dish has come up); never guess or wave it away.`;

export async function runOrchestrator(conversationId: string): Promise<string> {
  const db = dbClient();

  const { data: convo } = await db
    .from("conversations")
    .select("id, household_id, telegram_chat_id")
    .eq("id", conversationId)
    .maybeSingle();
  if (!convo) {
    console.error("orchestrator: conversation not found", conversationId);
    return "";
  }

  const desc = describeHousehold(await getPreferences(db, convo.household_id));
  const planCtx = await planContextBlock(db, convo.household_id);
  const SYSTEM = sousSystem(desc.context) +
    (planCtx ? `\n\n${planCtx}` : "") + AGENT_INSTRUCTION;

  // Who sent the latest inbound turn (the rater / actor).
  const { data: lastIn } = await db
    .from("messages")
    .select("sender_user_id")
    .eq("conversation_id", conversationId)
    .eq("direction", "in")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  const raterId: string | null = lastIn?.sender_user_id ?? null;

  // Rolling transcript: last 10 turns, oldest first.
  const { data: history } = await db
    .from("messages")
    .select("direction, text, created_at")
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: false })
    .limit(10);
  const turns: Msg[] = normalize(
    (history ?? [])
      .reverse()
      .map((m: { direction: string; text: string | null }) => ({
        role: m.direction === "in" ? "user" : "assistant",
        content: m.text ?? "",
      })),
  );

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY")!;
  // deno-lint-ignore no-explicit-any
  const messages: any[] = turns.length
    ? [...turns]
    : [{ role: "user", content: "(say hello)" }];

  let reply = "";
  for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
    const res = await completeRaw({
      apiKey,
      model: WORKHORSE_MODEL,
      system: SYSTEM,
      messages,
      tools: TOOLS,
      maxTokens: 1024,
    });
    reply = res.text || reply;
    if (!res.toolUses.length) break;

    // Execute every tool the model asked for, in order.
    const toolResults = [];
    for (const tu of res.toolUses) {
      const content = await runTool(db, convo, raterId, tu.name, tu.input);
      toolResults.push({ type: "tool_result", tool_use_id: tu.id, content });
    }
    messages.push({ role: "assistant", content: res.content });
    messages.push({ role: "user", content: toolResults });
  }

  reply = reply || "hm, my brain blanked for a sec — say that again?";

  // Persist outbound before sending (SPEC §9.6: state to DB first).
  await db.from("messages").insert({
    conversation_id: conversationId,
    direction: "out",
    text: reply,
  });
  await sendMessage(Deno.env.get("TELEGRAM_BOT_TOKEN")!, convo.telegram_chat_id, reply);

  return reply;
}

// ---- tool dispatch --------------------------------------------------------
interface Convo {
  id: string;
  household_id: string;
  telegram_chat_id: number;
}

async function runTool(
  db: SupabaseClient,
  convo: Convo,
  raterId: string | null,
  name: string,
  input: Record<string, unknown>,
): Promise<string> {
  try {
    switch (name) {
      case "rate_meal":
        return await recordRating(db, convo.household_id, raterId, input);
      case "swap_meal": {
        const day = asDay(input.day);
        if (!day) return "need a valid weekday to swap";
        const request = input.request ? String(input.request) : undefined;
        const newTitle = await swapByDay(convo.id, day, request);
        return newTitle
          ? `swapped ${day} to "${newTitle}" — its card was posted to the chat. If they want the recipe, call expand_recipe with that exact title.`
          : `couldn't swap ${day} — there may be no active plan or no fresh options; tell the user plainly`;
      }
      case "send_shopping_list": {
        const ok = await sendShoppingList(convo.id);
        return ok
          ? "posted the up-to-date shopping list to the chat"
          : "no active plan to build a list from";
      }
      case "customize_meal": {
        const day = asDay(input.day);
        if (!day) return "need a valid weekday to customize";
        const change = String(input.change ?? "").trim();
        if (!change) return "need to know what change to make";
        const newTitle = await customizeMeal(convo.id, day, change);
        return newTitle
          ? `updated ${day} to "${newTitle}" — its card was reposted and the grocery list refreshed`
          : `couldn't apply that change to ${day}; tell the user plainly`;
      }
      case "plan_week":
        await proposePlan(convo.id);
        return "posted a fresh plan + shopping list to the chat";
      case "lock_week":
        await lockActivePlan(convo.id);
        return "locked the week";
      case "exclude_recipe":
        return await excludeRecipe(db, convo.household_id, input);
      case "update_preferences":
        return await applyPreferenceUpdate(db, convo.household_id, input);
      case "expand_recipe": {
        const rec = await resolveRecipe(db, String(input.recipe_title ?? ""));
        if (!rec) return `no recipe matched "${input.recipe_title}"`;
        await expandRecipe(convo.id, rec.id);
        return `sent the full recipe for ${rec.title}`;
      }
      default:
        return "unknown tool";
    }
  } catch (e) {
    console.error(`tool ${name} failed`, e);
    return `that action hit a snag: ${String(e)}`;
  }
}

function asDay(v: unknown): DayKey | undefined {
  const s = String(v ?? "").toLowerCase().slice(0, 3);
  return (DAY_KEYS as readonly string[]).includes(s) ? (s as DayKey) : undefined;
}

async function resolveRecipe(
  db: SupabaseClient,
  title: string,
): Promise<{ id: string; title: string } | null> {
  const t = title.trim();
  if (!t) return null;
  const { data } = await db
    .from("recipes")
    .select("id, title")
    .ilike("title", `%${t}%`)
    .limit(1)
    .maybeSingle();
  return data ?? null;
}

async function recordRating(
  db: SupabaseClient,
  householdId: string,
  raterId: string | null,
  input: Record<string, unknown>,
): Promise<string> {
  const title = String(input.recipe_title ?? "").trim();
  const rating = Number(input.rating);
  const note = input.note ? String(input.note) : null;
  if (!title || !(rating >= 1 && rating <= 5)) {
    return "could not record — need a dish name and a 1-5 rating";
  }
  if (!raterId) return "could not identify who is rating";

  const rec = await resolveRecipe(db, title);
  if (!rec) return `no recipe matched "${title}"`;

  const { error } = await db.from("recipe_ratings").upsert(
    {
      household_id: householdId,
      recipe_id: rec.id,
      rater_user_id: raterId,
      rating,
      note,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "recipe_id,rater_user_id" },
  );
  if (error) {
    console.error("rating upsert failed", error);
    return "hit a snag saving that rating";
  }
  return `recorded ${rec.title} = ${rating}/5`;
}

async function excludeRecipe(
  db: SupabaseClient,
  householdId: string,
  input: Record<string, unknown>,
): Promise<string> {
  const rec = await resolveRecipe(db, String(input.recipe_title ?? ""));
  if (!rec) return `no recipe matched "${input.recipe_title}"`;
  const reason = input.reason ? String(input.reason) : null;

  const { error } = await db.from("recipe_exclusions").upsert(
    { household_id: householdId, recipe_id: rec.id, reason },
    { onConflict: "household_id,recipe_id" },
  );
  if (error) {
    console.error("exclude upsert failed", error);
    return "hit a snag excluding that one";
  }

  // Is it on the current week? Tell the model so it can offer to swap it now.
  const onDay = await recipeDayInActivePlan(db, householdId, rec.id);
  return onDay
    ? `excluded ${rec.title} for good. Heads up: it's on this week's plan (${onDay}) — call swap_meal for ${onDay} to replace it now.`
    : `excluded ${rec.title} for good — it won't be suggested again`;
}

// If a recipe is on the household's most recent plan, return its weekday key
// ("tue"), else null — so exclude can offer to swap it out of the live week.
async function recipeDayInActivePlan(
  db: SupabaseClient,
  householdId: string,
  recipeId: string,
): Promise<DayKey | null> {
  const { data: plan } = await db
    .from("meal_plans")
    .select("id")
    .eq("household_id", householdId)
    .order("week_of", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!plan) return null;
  const { data: item } = await db
    .from("meal_plan_items")
    .select("day")
    .eq("plan_id", plan.id)
    .eq("recipe_id", recipeId)
    .limit(1)
    .maybeSingle();
  if (!item?.day) return null;
  const dow = new Date(`${item.day}T00:00:00Z`).getUTCDay(); // 0 Sun..6 Sat
  const map: Record<number, DayKey> = {
    1: "mon", 2: "tue", 3: "wed", 4: "thu", 5: "fri", 6: "sat", 0: "sun",
  };
  return map[dow] ?? null;
}

async function applyPreferenceUpdate(
  db: SupabaseClient,
  householdId: string,
  input: Record<string, unknown>,
): Promise<string> {
  const patch: Record<string, unknown> = {};
  if (typeof input.adults === "number") patch.adults = Math.round(input.adults);
  if (typeof input.meals_per_week === "number") {
    patch.meals_per_week = Math.min(7, Math.max(1, Math.round(input.meals_per_week)));
  }
  if (input.monthly_budget_usd !== undefined) {
    patch.monthly_budget_usd = input.monthly_budget_usd === null
      ? null
      : Number(input.monthly_budget_usd);
  }
  if (Array.isArray(input.cuisines)) {
    patch.cuisines = (input.cuisines as unknown[]).map((c) => String(c)).filter(Boolean);
  }
  if (Array.isArray(input.kids)) {
    patch.kids = (input.kids as { age_months?: unknown }[])
      .map((k) => ({ age_months: Math.max(0, Math.min(215, Math.round(Number(k?.age_months) || 0))) }))
      .filter((k) => Number.isFinite(k.age_months)) as Kid[];
  }
  if (Object.keys(patch).length === 0) return "nothing to update";

  await updatePreferences(db, householdId, patch);
  return `updated preferences (${Object.keys(patch).join(", ")}) — future plans will use this`;
}

// ---- context the agent reasons over --------------------------------------
interface HistItem {
  day: string;
  recipes: { title: string; cuisine_tag: string } | null;
  meal_plans: { week_of: string; status: string } | null;
}

async function loadHistory(
  db: SupabaseClient,
  householdId: string,
  limit: number,
): Promise<HistItem[]> {
  const { data } = await db
    .from("meal_plan_items")
    .select("day, recipes(title, cuisine_tag), meal_plans!inner(week_of, status, household_id)")
    .eq("meal_plans.household_id", householdId)
    .order("day", { ascending: false })
    .limit(limit);
  return ((data ?? []) as Record<string, unknown>[]).map((r) => {
    const rec = Array.isArray(r.recipes) ? r.recipes[0] : r.recipes;
    const mp = Array.isArray(r.meal_plans) ? r.meal_plans[0] : r.meal_plans;
    return {
      day: String(r.day),
      recipes: rec
        ? { title: String((rec as Record<string, unknown>).title), cuisine_tag: String((rec as Record<string, unknown>).cuisine_tag) }
        : null,
      meal_plans: mp
        ? { week_of: String((mp as Record<string, unknown>).week_of), status: String((mp as Record<string, unknown>).status) }
        : null,
    };
  });
}

// Build a compact, truthful snapshot: the current week's dishes + how often
// each dish has actually come up lately. This is what lets Sous answer "why do
// we get ziti every week" with facts instead of a guess.
async function planContextBlock(
  db: SupabaseClient,
  householdId: string,
): Promise<string> {
  const items = await loadHistory(db, householdId, 60);
  if (!items.length) return "";

  // Newest week_of present = "this week's plan".
  const weeks = [...new Set(items.map((i) => i.meal_plans?.week_of).filter(Boolean))]
    .sort()
    .reverse();
  const currentWeek = weeks[0];
  const current = items
    .filter((i) => i.meal_plans?.week_of === currentWeek && i.recipes)
    .sort((a, b) => (a.day < b.day ? -1 : 1));
  const status = current[0]?.meal_plans?.status ?? "proposed";

  const currentLines = current
    .map((i) => `- ${i.day}: ${i.recipes!.title} (${i.recipes!.cuisine_tag})`)
    .join("\n");

  // Frequency over the last ~8 weeks of served dinners.
  const counts = new Map<string, number>();
  for (const i of items) {
    if (!i.recipes) continue;
    counts.set(i.recipes.title, (counts.get(i.recipes.title) ?? 0) + 1);
  }
  const repeated = [...counts.entries()]
    .filter(([, n]) => n >= 2)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8)
    .map(([t, n]) => `${t} ×${n}`)
    .join(", ");

  const parts = [
    `CURRENT WEEK (week of ${currentWeek}, ${status}):`,
    currentLines || "(no dishes yet)",
  ];
  if (repeated) {
    parts.push(
      `\nHOW OFTEN DISHES HAVE COME UP (recent history, use this to be honest about repeats): ${repeated}.`,
    );
  }
  return parts.join("\n");
}
