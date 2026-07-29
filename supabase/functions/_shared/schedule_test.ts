// Tests for timezone-aware kickoff scheduling (T12).
// Run: deno test supabase/functions/_shared/schedule_test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import { localDayHour, WEEKDAYS } from "./schedule.ts";

const t = new Date("2026-08-07T12:00:00Z"); // noon UTC

Deno.test("UTC returns the raw UTC weekday + hour", () => {
  const { day, hour } = localDayHour("UTC", t);
  assertEquals(hour, 12);
  assertEquals(day, WEEKDAYS[t.getUTCDay()]);
});

Deno.test("timezones shift the local hour correctly", () => {
  assertEquals(localDayHour("America/Los_Angeles", t).hour, 5); // PDT, UTC-7
  assertEquals(localDayHour("Asia/Tokyo", t).hour, 21); // UTC+9
});

Deno.test("crossing midnight rolls the local weekday back a day", () => {
  const early = new Date("2026-08-07T01:00:00Z"); // Fri 01:00 UTC
  const la = localDayHour("America/Los_Angeles", early); // Thu 18:00 PDT
  assertEquals(la.hour, 18);
  assertEquals(la.day, "thu");
});

Deno.test("an unknown timezone falls back to UTC", () => {
  const { day, hour } = localDayHour("Not/AZone", t);
  assertEquals(hour, 12);
  assert(WEEKDAYS.includes(day));
});
