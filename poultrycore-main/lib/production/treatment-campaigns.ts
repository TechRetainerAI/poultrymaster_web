// Pure helpers for Treatment Campaigns (migration 339). No React, no fetch —
// covered by treatment-campaigns.test.ts.
//
// The software records and orchestrates treatment; it does not prescribe it.
// No dose, duration or withdrawal period is built in anywhere here: a dose is
// the farm's own figure (typed on the campaign or saved for the product), and a
// suggested quantity is plain arithmetic on it, shown for review. Actual is
// what posts, and it is always the farmer's to type.

export type DoseBasis = "PerBird" | "Per1000Birds" | "PerFlock"

export const DOSE_BASES: { key: DoseBasis; label: string; short: string }[] = [
  { key: "PerBird", label: "per bird per day", short: "/bird" },
  { key: "Per1000Birds", label: "per 1,000 birds per day", short: "/1,000 birds" },
  { key: "PerFlock", label: "per flock per day", short: "/flock" },
]

export function isDoseBasis(v: unknown): v is DoseBasis {
  return v === "PerBird" || v === "Per1000Birds" || v === "PerFlock"
}

export function doseBasisLabel(b: string | null | undefined): string {
  return DOSE_BASES.find((x) => x.key === b)?.label ?? ""
}

/** "0.5 L per 1,000 birds per day" — the dose exactly as the farm set it. */
export function describeDose(
  dose: number | null | undefined, basis: string | null | undefined, unit: string | null | undefined,
): string | null {
  if (dose == null || !isDoseBasis(basis)) return null
  return `${fmtQty(dose)}${unit ? ` ${unit}` : ""} ${doseBasisLabel(basis)}`
}

/**
 * Plain arithmetic on the farm's own dose — the same rule as the server's
 * fnpoultrytreatment_suggest. null when there is no dose, or no bird count to
 * multiply by: never a stand-in figure.
 */
export function suggestQuantity(
  dose: number | null | undefined, basis: string | null | undefined, birds: number | null | undefined,
): number | null {
  const d = Number(dose)
  if (dose == null || !Number.isFinite(d) || d <= 0 || !isDoseBasis(basis)) return null
  if (basis === "PerFlock") return round4(d)
  const b = Number(birds)
  if (birds == null || !Number.isFinite(b) || b <= 0) return null
  return basis === "PerBird" ? round4(d * b) : round4((d * b) / 1000)
}

/** "2.5" → 2.5; "", "abc", negatives → null. Quantities are typed text. */
export function parseQty(text: string | null | undefined): number | null {
  const t = (text ?? "").trim()
  if (t === "") return null
  const n = Number(t)
  if (!Number.isFinite(n) || n < 0) return null
  return round4(n)
}

export function fmtQty(n: number | null | undefined, unit?: string | null): string {
  if (n == null || !Number.isFinite(Number(n))) return "—"
  const s = Number(n).toLocaleString(undefined, { maximumFractionDigits: 4 })
  return unit ? `${s} ${unit}` : s
}

function round4(n: number): number {
  return Math.round(n * 10000) / 10000
}

// ---------------------------------------------------------------------------
// Campaign status
// ---------------------------------------------------------------------------

export type CampaignStatus = "Scheduled" | "InProgress" | "Completed" | "Cancelled"

export function statusLabel(s: string): string {
  return s === "InProgress" ? "In Progress" : s
}

export function statusStyle(s: string): string {
  switch (s) {
    case "Scheduled": return "border-sky-200 bg-sky-50 text-sky-700"
    case "InProgress": return "border-amber-200 bg-amber-50 text-amber-800"
    case "Completed": return "border-emerald-200 bg-emerald-50 text-emerald-700"
    case "Cancelled": return "border-slate-200 bg-slate-100 text-slate-600"
    default: return "border-slate-200 bg-white text-slate-600"
  }
}

/** Inclusive day count of a YYYY-MM-DD range; 0 when the range is invalid. */
export function daysInclusive(start: string, end: string): number {
  const a = Date.parse(`${start}T00:00:00Z`)
  const b = Date.parse(`${end}T00:00:00Z`)
  if (!Number.isFinite(a) || !Number.isFinite(b) || b < a) return 0
  return Math.round((b - a) / 86_400_000) + 1
}

/** YYYY-MM-DD + n days, in calendar days (no time zone drift). */
export function addDays(date: string, n: number): string {
  const t = Date.parse(`${date.slice(0, 10)}T00:00:00Z`)
  if (!Number.isFinite(t)) return date
  return new Date(t + n * 86_400_000).toISOString().slice(0, 10)
}

/** The days a treatment can be recorded for: start..min(end, today). */
export function recordableDays(start: string, end: string, today: string): string[] {
  const last = end < today ? end : today
  const n = daysInclusive(start, last)
  return Array.from({ length: n }, (_, i) => addDays(start, i))
}

/**
 * Withdrawal runs from the LAST dose actually given, by the farm's own number
 * of days. null when no period is set or nothing has been given yet.
 */
export function withdrawalUntil(lastDose: string | null | undefined, days: number | null | undefined): string | null {
  if (!lastDose || days == null || !Number.isFinite(Number(days))) return null
  return addDays(lastDose.slice(0, 10), Number(days))
}

// ---------------------------------------------------------------------------
// The day grid
// ---------------------------------------------------------------------------

export interface TreatmentDayRow {
  flockId: number
  flockName: string
  houseName: string | null
  isClosed: boolean
  recordCount: number
  productionRecordId: number | null
  birds: number | null
  doseQuantity: number | null
  doseBasis: string | null
  suggestedQuantity: number | null
  thisItemQuantity: number
  postedQuantity: number | null
  notes: string | null
}

export type DayRowState = "ok" | "posted" | "closed" | "noRecord" | "duplicate"

/** Only an open flock with exactly one production record for the date can be dosed. */
export function dayRowState(r: Pick<TreatmentDayRow, "isClosed" | "recordCount" | "postedQuantity">): DayRowState {
  if (r.postedQuantity != null) return "posted"
  if (r.isClosed) return "closed"
  if (r.recordCount === 1) return "ok"
  return r.recordCount === 0 ? "noRecord" : "duplicate"
}

export interface DayEntry {
  state: DayRowState
  actualText: string
}

export function dayTotals(available: number, rows: DayEntry[]) {
  const actual = rows
    .filter((r) => r.state === "ok")
    .reduce((s, r) => s + (parseQty(r.actualText) ?? 0), 0)
  return { available: round4(available), actual: round4(actual), remaining: round4(available - actual) }
}

/** Why the day cannot be posted yet, or null when it can. */
export function dayPostBlocker(
  totals: { actual: number; remaining: number },
  rows: DayEntry[],
  opts: { alreadyPosted: boolean; campaignOpen: boolean; inWindow: boolean },
): string | null {
  if (!opts.campaignOpen) return "This campaign is closed — no more treatment can be recorded on it."
  if (!opts.inWindow) return "Pick a date inside the campaign's dates, up to today."
  if (opts.alreadyPosted) return "This day is already recorded. Reverse it in Treatment days to record it again."
  if (rows.some((r) => r.state === "ok" && r.actualText.trim() !== "" && parseQty(r.actualText) == null)) {
    return "One of the quantities is not a number."
  }
  if (totals.actual <= 0) return "Enter the quantity given for at least one flock."
  if (totals.remaining < -0.00005) return "That is more than the stock on hand."
  return null
}
