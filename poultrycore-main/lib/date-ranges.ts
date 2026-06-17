/**
 * Named report periods (James 2026-06-10) — a single source of truth for the
 * "period dropdown" shown next to From/To date filters across every report.
 *
 * periodToRange() turns a period key into an inclusive { from, to } pair of
 * yyyy-mm-dd strings. "custom" returns null (the user edits From/To by hand);
 * "allTime" returns a very wide range so report SPs that require dates still
 * work.
 */

export type PeriodKey =
  | "today" | "yesterday"
  | "thisWeek" | "lastWeek" | "last7"
  | "thisMonth" | "lastMonth" | "last30"
  | "thisQuarter" | "lastQuarter"
  | "thisYear" | "lastYear" | "ytd"
  | "custom" | "allTime"

export const PERIOD_GROUPS: { label: string; options: { value: PeriodKey; label: string }[] }[] = [
  { label: "Day", options: [
    { value: "today", label: "Today" },
    { value: "yesterday", label: "Yesterday" },
  ] },
  { label: "Week", options: [
    { value: "thisWeek", label: "This Week" },
    { value: "lastWeek", label: "Last Week" },
    { value: "last7", label: "Last 7 Days" },
  ] },
  { label: "Month", options: [
    { value: "thisMonth", label: "This Month" },
    { value: "lastMonth", label: "Last Month" },
    { value: "last30", label: "Last 30 Days" },
  ] },
  { label: "Quarter", options: [
    { value: "thisQuarter", label: "This Quarter" },
    { value: "lastQuarter", label: "Last Quarter" },
  ] },
  { label: "Year", options: [
    { value: "thisYear", label: "This Year" },
    { value: "lastYear", label: "Last Year" },
    { value: "ytd", label: "Year to Date" },
  ] },
  { label: "Other", options: [
    { value: "custom", label: "Custom Date Range" },
    { value: "allTime", label: "All Time" },
  ] },
]

function iso(d: Date): string {
  // Local-date ISO (yyyy-mm-dd) — avoids the UTC shift that toISOString() causes.
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, "0")
  const day = String(d.getDate()).padStart(2, "0")
  return `${y}-${m}-${day}`
}
function addDays(d: Date, n: number): Date { const x = new Date(d); x.setDate(x.getDate() + n); return x }
// Monday-based start of week.
function startOfWeek(d: Date): Date {
  const x = new Date(d); const dow = (x.getDay() + 6) % 7; return addDays(x, -dow)
}

export type DateRange = { from: string; to: string }

/**
 * Resolve a period key to an inclusive date range. Returns null for "custom"
 * (caller keeps the user's manual From/To). `today` lets callers pass a fixed
 * reference date (defaults to now).
 */
export function periodToRange(period: PeriodKey, today: Date = new Date()): DateRange | null {
  const t = new Date(today.getFullYear(), today.getMonth(), today.getDate())
  const y = t.getFullYear(), m = t.getMonth()
  switch (period) {
    case "today":      return { from: iso(t), to: iso(t) }
    case "yesterday":  { const d = addDays(t, -1); return { from: iso(d), to: iso(d) } }
    case "thisWeek":   { const s = startOfWeek(t); return { from: iso(s), to: iso(addDays(s, 6)) } }
    case "lastWeek":   { const s = addDays(startOfWeek(t), -7); return { from: iso(s), to: iso(addDays(s, 6)) } }
    case "last7":      return { from: iso(addDays(t, -6)), to: iso(t) }
    case "thisMonth":  return { from: iso(new Date(y, m, 1)), to: iso(new Date(y, m + 1, 0)) }
    case "lastMonth":  return { from: iso(new Date(y, m - 1, 1)), to: iso(new Date(y, m, 0)) }
    case "last30":     return { from: iso(addDays(t, -29)), to: iso(t) }
    case "thisQuarter": { const q = Math.floor(m / 3); return { from: iso(new Date(y, q * 3, 1)), to: iso(new Date(y, q * 3 + 3, 0)) } }
    case "lastQuarter": { const q = Math.floor(m / 3) - 1; const yy = q < 0 ? y - 1 : y; const qq = (q + 4) % 4; return { from: iso(new Date(yy, qq * 3, 1)), to: iso(new Date(yy, qq * 3 + 3, 0)) } }
    case "thisYear":   return { from: iso(new Date(y, 0, 1)), to: iso(new Date(y, 11, 31)) }
    case "lastYear":   return { from: iso(new Date(y - 1, 0, 1)), to: iso(new Date(y - 1, 11, 31)) }
    case "ytd":        return { from: iso(new Date(y, 0, 1)), to: iso(t) }
    case "allTime":    return { from: "2000-01-01", to: iso(t) }
    case "custom":     return null
    default:           return null
  }
}

/**
 * Default range for a report on first load. Returns a range that EXACTLY matches
 * a named preset (default "Last 30 Days") so the Period dropdown shows that
 * preset on load instead of falling back to "Custom Date Range". Use this for a
 * page's initial fromDate/toDate state.
 */
export function defaultReportRange(period: PeriodKey = "last30"): DateRange {
  return periodToRange(period) ?? { from: iso(addDays(new Date(), -29)), to: iso(new Date()) }
}

/**
 * Best-effort: given a from/to pair, return the period key that produced it
 * (so a dropdown can reflect the current range), else "custom".
 */
export function rangeToPeriod(from: string, to: string, today: Date = new Date()): PeriodKey {
  for (const g of PERIOD_GROUPS) {
    for (const o of g.options) {
      if (o.value === "custom") continue
      const r = periodToRange(o.value, today)
      if (r && r.from === from && r.to === to) return o.value
    }
  }
  return "custom"
}
