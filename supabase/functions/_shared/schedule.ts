// Scheduling helpers for the timezone-aware weekly kickoff (T12).

export const WEEKDAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];

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
