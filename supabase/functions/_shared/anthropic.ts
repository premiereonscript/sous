// Minimal Anthropic Messages API client (REST, no SDK dependency).
// Tools + prompt caching arrive with the planner (SPEC §9.4); this is text-only.

export type Role = "user" | "assistant";
export interface Msg {
  role: Role;
  content: string;
}

// Collapse consecutive same-role turns and ensure the list starts with a user
// turn — the Anthropic API requires strict user/assistant alternation.
export function normalize(msgs: Msg[]): Msg[] {
  const out: Msg[] = [];
  for (const m of msgs) {
    if (!m.content) continue;
    const last = out[out.length - 1];
    if (last && last.role === m.role) last.content += "\n" + m.content;
    else out.push({ role: m.role, content: m.content });
  }
  while (out.length && out[0].role !== "user") out.shift();
  return out;
}

export interface ToolUse {
  id: string;
  name: string;
  input: Record<string, unknown>;
}

// Full call: returns the raw content blocks, joined text, and any tool_use
// blocks. Pass `tools` + `toolChoice` to force structured output (SPEC §9.4).
// `messages` accepts raw Anthropic message objects (string or block content)
// so callers can append tool_use / tool_result turns.
export async function completeRaw(opts: {
  apiKey: string;
  model: string;
  system: string;
  messages: unknown[];
  tools?: unknown[];
  toolChoice?: unknown;
  maxTokens?: number;
}): Promise<{ text: string; toolUses: ToolUse[]; content: unknown[] }> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": opts.apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: opts.model,
      max_tokens: opts.maxTokens ?? 2048,
      system: opts.system,
      messages: opts.messages,
      ...(opts.tools ? { tools: opts.tools } : {}),
      ...(opts.toolChoice ? { tool_choice: opts.toolChoice } : {}),
    }),
  });
  if (!res.ok) {
    console.error("anthropic error", res.status, await res.text());
    return { text: "", toolUses: [], content: [] };
  }
  const data = await res.json();
  const blocks = data.content ?? [];
  const text = blocks
    .filter((b: { type: string }) => b.type === "text")
    .map((b: { text: string }) => b.text)
    .join("")
    .trim();
  const toolUses: ToolUse[] = blocks
    .filter((b: { type: string }) => b.type === "tool_use")
    .map((b: { id: string; name: string; input: Record<string, unknown> }) => ({
      id: b.id,
      name: b.name,
      input: b.input,
    }));
  return { text, toolUses, content: blocks };
}

export async function complete(opts: {
  apiKey: string;
  model: string;
  system: string;
  messages: Msg[];
  maxTokens?: number;
}): Promise<string> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": opts.apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: opts.model,
      max_tokens: opts.maxTokens ?? 1024,
      system: opts.system,
      messages: opts.messages,
    }),
  });
  if (!res.ok) {
    console.error("anthropic error", res.status, await res.text());
    return "";
  }
  const data = await res.json();
  return (data.content ?? [])
    .filter((b: { type: string }) => b.type === "text")
    .map((b: { text: string }) => b.text)
    .join("")
    .trim();
}
