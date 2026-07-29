// Tests for the swappable persona (T10). Guards two things: the voice carries
// NO assumptions about any one kitchen, and style selection falls back safely.
//
// Run: deno test supabase/functions/_shared/persona_test.ts

import { assert, assertStringIncludes } from "jsr:@std/assert@1";
import { PERSONAS, personaVoice, SOUS_VOICE, sousSystem } from "./persona.ts";

Deno.test("no persona voice bakes in the original family's lifestyle", () => {
  const banned = ["farmers market", "farmers-market", "backyard", "chicken", "weekends are usually diy"];
  for (const [style, voice] of Object.entries(PERSONAS)) {
    const lower = voice.toLowerCase();
    for (const phrase of banned) {
      assert(!lower.includes(phrase), `persona "${style}" must not mention "${phrase}"`);
    }
  }
});

Deno.test("persona selection resolves known styles and falls back to default", () => {
  assertStringIncludes(personaVoice("weissman"), "Joshua Weissman");
  assertStringIncludes(personaVoice("neutral"), "clear, friendly");
  assertStringIncludes(personaVoice("warm"), "warm, encouraging");
  // Unknown / missing style => default voice.
  assert(personaVoice("does-not-exist") === SOUS_VOICE);
  assert(personaVoice(undefined) === SOUS_VOICE);
  assert(personaVoice(null) === SOUS_VOICE);
});

Deno.test("sousSystem composes the chosen voice with the household context", () => {
  const sys = sousSystem("This household: 2 adults.", "neutral");
  assertStringIncludes(sys, "clear, friendly"); // neutral voice
  assertStringIncludes(sys, "This household: 2 adults."); // context
});
