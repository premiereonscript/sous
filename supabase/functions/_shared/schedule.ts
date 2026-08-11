// Scheduling helpers for the timezone-aware weekly kickoff (T12).

export const WEEKDAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];

// Validate + canonicalize an IANA timezone, or null if we can't trust it.
//
// The onboarding model infers a zone from a city, so two failure modes matter.
// A plausible-looking miss ("Europe/Austin") must be caught before it is
// persisted, or localDayHour silently falls back to UTC and the kickoff drifts
// with no visible cause. Less obviously, ICU ACCEPTS bare abbreviations and
// resolves them to surprising places — "EST" becomes America/Panama, which
// does not observe DST, so a New York household would slip an hour for half
// the year. Require the Region/City form (or UTC) and store what ICU resolves.
export function normalizeTimezone(tz: unknown): string | null {
  if (typeof tz !== "string") return null;
  const raw = tz.trim();
  if (!raw) return null;
  if (raw.toUpperCase() === "UTC") return "UTC";
  if (!raw.includes("/")) return null; // abbreviation — ambiguous, often wrong
  try {
    return new Intl.DateTimeFormat("en-US", { timeZone: raw })
      .resolvedOptions().timeZone ?? raw;
  } catch {
    return null;
  }
}

export function isValidTimezone(tz: unknown): tz is string {
  return normalizeTimezone(tz) !== null;
}

// The household's local weekday ("fri") + hour (0-23) in its IANA timezone,
// at the given instant. Falls back to UTC for an unknown timezone.
export function localDayHour(tz: string, now: Date): { day: string; hour: number } {
  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      weekday: "short",
      hour: "numeric",
      hour12: false,
    }).formatToParts(now);
    const day = (parts.find((p) => p.type === "weekday")?.value ?? "").toLowerCase();
    const hour = parseInt(parts.find((p) => p.type === "hour")?.value ?? "0", 10) % 24;
    return { day, hour };
  } catch {
    return { day: WEEKDAYS[now.getUTCDay()], hour: now.getUTCHours() };
  }
}
