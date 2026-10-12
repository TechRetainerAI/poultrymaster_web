// Pure helpers for the Missing Activity Detector UI. No React, no fetch — kept
// here so the link-building and URL parsing that connect the dashboard to Batch
// Production Entry are covered by vitest (completeness.test.ts).
//
// Dates in this module are "yyyy-MM-dd" business dates and are handled as
// STRINGS. Passing one through `new Date()` would reinterpret it in the
// browser's zone and can shift it a day — the bug company-time.ts exists to
// remove.

import type {
  ActivityCheckItem,
  ActivityCheckResult,
  ActivityCompletenessReport,
  ActivitySeverity,
  MissingProductionEntry,
} from "@/lib/api/activity-checks"

/** Must match PoultryProductionCompletenessCheck.CheckKey on the Farm API. */
export const PRODUCTION_CHECK_KEY = "poultry.production.daily"

/** Query-string marker so Batch Production Entry knows why it was opened. */
export const MISSING_PRODUCTION_SOURCE = "missing-production"

/**
 * A missing-production link carries at most this many flock ids. Well above any
 * real farm's daily gap, and it keeps the URL from growing without bound.
 */
export const MAX_PREFILL_FLOCKS = 500

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

export function findCheck(
  report: ActivityCompletenessReport | null | undefined,
  key: string,
): ActivityCheckResult | null {
  return report?.checks.find((c) => c.key === key) ?? null
}

/** "2026-09-19T00:00:00" or "2026-09-19" → "2026-09-19"; anything else → null. */
export function toBusinessDate(value: string | null | undefined): string | null {
  const d = (value ?? "").slice(0, 10)
  if (!DATE_RE.test(d)) return null
  const [, m, day] = d.split("-").map(Number)
  if (m < 1 || m > 12 || day < 1 || day > 31) return null
  return d
}

/**
 * Moves a business date by whole days. Done in UTC on purpose: the input is a
 * calendar date with no zone, and UTC has no daylight-saving gaps to skip a day.
 */
export function shiftBusinessDate(value: string, days: number): string | null {
  const d = toBusinessDate(value)
  if (!d) return null
  const [y, m, day] = d.split("-").map(Number)
  const t = new Date(Date.UTC(y, m - 1, day + Math.trunc(days)))
  return t.toISOString().slice(0, 10)
}

/** "2026-09-19" → "Sep 19". Parsed by hand; see the note at the top. */
export function formatShortDate(value: string | null | undefined): string {
  const d = toBusinessDate(value)
  if (!d) return "—"
  const [, m, day] = d.split("-").map(Number)
  return `${MONTHS[m - 1]} ${day}`
}

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

/**
 * "2026-09-12" -> "Sat, Sep 12". The weekday comes from the calendar date in
 * UTC, which has no daylight-saving gaps, so it cannot drift with the
 * browser's zone the way new Date("2026-09-12").getDay() can.
 */
export function formatWeekdayDate(value: string | null | undefined): string {
  const d = toBusinessDate(value)
  if (!d) return "—"
  const [y, m, day] = d.split("-").map(Number)
  return `${WEEKDAYS[new Date(Date.UTC(y, m - 1, day)).getUTCDay()]}, ${formatShortDate(d)}`
}

/** "today" / "yesterday" / "5 days ago", counted between two business dates. */
export function daysAgoLabel(date: string, businessDate: string): string {
  const a = toBusinessDate(date)
  const b = toBusinessDate(businessDate)
  if (!a || !b) return ""
  const [ay, am, ad] = a.split("-").map(Number)
  const [by, bm, bd] = b.split("-").map(Number)
  const n = Math.round((Date.UTC(by, bm - 1, bd) - Date.UTC(ay, am - 1, ad)) / 86_400_000)
  if (n <= 0) return "today"
  if (n === 1) return "yesterday"
  return `${n} days ago`
}

export function formatDaysOutstanding(days: number): string {
  const n = Math.max(0, Math.trunc(days || 0))
  return `${n} day${n === 1 ? "" : "s"}`
}

/**
 * "17 / 20 recorded" — flocks recorded on ONE day. Deliberately not
 * "complete": the card shows earlier missing days beside it, and "4 / 4
 * complete" next to 28 missing records read as if nothing were left to do.
 */
export function completenessHeadline(check: Pick<ActivityCheckResult, "completedCount" | "expectedCount">): string {
  return `${check.completedCount} / ${check.expectedCount} recorded`
}

/**
 * Flocks that need production ENTERED. Flocks already in an unposted batch are
 * excluded: posting that batch is the fix, and entering them again would be
 * refused by spproductionbatchrecord_post as a duplicate once both exist.
 */
export function flocksNeedingEntry(check: ActivityCheckResult | null | undefined): ActivityCheckItem[] {
  return (check?.items ?? []).filter((i) => i.subjectType === "flock" && i.state === "Missing")
}

/**
 * "Complete Missing Production" → Batch Production Entry, pre-set to a custom
 * selection of exactly the missing flocks on the report's business date.
 * Returns null when there is nothing to enter.
 */
export function completeMissingProductionHref(
  businessDate: string,
  check: ActivityCheckResult | null | undefined,
): string | null {
  return batchEntryHref(businessDate, flocksNeedingEntry(check).map((i) => i.subjectId))
}

/**
 * Batch Production Entry for ONE date with these flocks pre-selected — the fix
 * when many flocks missed the same day. Null without a date or flocks.
 */
export function batchEntryHref(businessDate: string, flockIds: number[]): string | null {
  const date = toBusinessDate(businessDate)
  const ids = [...new Set(flockIds.filter((n) => Number.isSafeInteger(n) && n > 0))]
  if (!date || ids.length === 0) return null
  const qs = new URLSearchParams({
    date,
    flockIds: ids.slice(0, MAX_PREFILL_FLOCKS).join(","),
    source: MISSING_PRODUCTION_SOURCE,
  })
  return `/batch-production-records/new?${qs.toString()}`
}

/**
 * The normal production form, stepping through every missed day of ONE flock
 * oldest first ("Save & next missing day") — the fix when one flock is behind.
 */
export function flockStepThroughHref(flockId: number, asOf: string): string {
  const qs = new URLSearchParams({ flockId: String(flockId), catchUp: "1" })
  const d = toBusinessDate(asOf)
  if (d) qs.set("asOf", d)
  return `/production-records/new?${qs.toString()}`
}

export interface MissingDateGroup {
  date: string
  /** Flocks with nothing started for this date — Batch Production Entry covers these. */
  missing: MissingProductionEntry[]
  /** Unposted batch entries already covering some flocks on this date. */
  pendingBatches: { id: number; status: string | null; flocks: MissingProductionEntry[] }[]
}

/** Group the farm-wide list by date (keeps the server's newest-first order). */
export function groupMissingByDate(entries: MissingProductionEntry[]): MissingDateGroup[] {
  const groups: MissingDateGroup[] = []
  const byDate = new Map<string, MissingDateGroup>()
  for (const e of entries) {
    const date = toBusinessDate(e.date)
    if (!date) continue
    let g = byDate.get(date)
    if (!g) {
      g = { date, missing: [], pendingBatches: [] }
      byDate.set(date, g)
      groups.push(g)
    }
    if (e.pendingBatchRecordId == null) {
      g.missing.push(e)
    } else {
      let b = g.pendingBatches.find((x) => x.id === e.pendingBatchRecordId)
      if (!b) {
        b = { id: e.pendingBatchRecordId, status: e.pendingBatchStatus, flocks: [] }
        g.pendingBatches.push(b)
      }
      b.flocks.push(e)
    }
  }
  return groups
}

/**
 * The per-row action. A flock waiting on an unposted batch goes to THAT batch
 * (edit if still a draft, allocate/post otherwise); a plain missing flock opens
 * the single-record form for that flock and date.
 */
export function itemActionHref(item: ActivityCheckItem, businessDate: string): string {
  // More than one day behind: step through each missed day in the normal form.
  if (item.state === "Missing" && item.daysOutstanding > 1) return flockStepThroughHref(item.subjectId, businessDate)
  return missingDateHref(
    item.subjectId,
    businessDate,
    item.state === "AwaitingPosting" ? item.relatedRecordId : null,
    item.relatedRecordStatus,
  )
}

/**
 * The fix for one flock on one missing day: finish or post the batch entry that
 * already covers it, or record it individually on that date.
 */
export function missingDateHref(
  flockId: number,
  date: string,
  pendingBatchRecordId?: number | null,
  pendingBatchStatus?: string | null,
): string {
  if (pendingBatchRecordId != null) {
    return pendingBatchStatus === "Draft"
      ? `/batch-production-records/${pendingBatchRecordId}/edit`
      : `/batch-production-records/${pendingBatchRecordId}/allocate`
  }
  const qs = new URLSearchParams({ flockId: String(flockId) })
  const d = toBusinessDate(date)
  if (d) qs.set("date", d)
  return `/production-records/new?${qs.toString()}`
}

export function itemActionLabel(item: ActivityCheckItem): string {
  if (item.state === "Missing" && item.daysOutstanding > 1) return `Record batch(${item.daysOutstanding})`
  if (item.state !== "AwaitingPosting") return "Record"
  return item.relatedRecordStatus === "Draft" ? "Finish batch" : "Post batch"
}

export interface MissingProductionPrefill {
  date: string
  flockIds: number[]
}

/**
 * Reads what completeMissingProductionHref wrote. Anything malformed is dropped
 * rather than trusted: the flock ids are only ever used to PRE-TICK boxes in a
 * list the form loaded itself, so an id for another company's flock matches
 * nothing and has no effect.
 */
export function parseMissingProductionPrefill(
  params: { get(name: string): string | null } | null | undefined,
): MissingProductionPrefill | null {
  if (!params) return null
  const date = toBusinessDate(params.get("date"))
  const raw = params.get("flockIds") ?? ""
  const seen = new Set<number>()
  const flockIds: number[] = []
  for (const part of raw.split(",")) {
    const t = part.trim()
    if (!/^\d+$/.test(t)) continue
    const n = Number(t)
    if (!Number.isSafeInteger(n) || n <= 0 || seen.has(n)) continue
    seen.add(n)
    flockIds.push(n)
    if (flockIds.length >= MAX_PREFILL_FLOCKS) break
  }
  // No valid date means no prefill at all: pre-ticking flocks against the
  // browser's today would silently record the gap on the wrong day.
  if (!date) return null
  return { date, flockIds }
}

export interface SeverityStyle {
  label: string
  /** Badge / pill classes. */
  badge: string
  /** Left-border accent for the card. */
  accent: string
}

export function severityStyle(severity: ActivitySeverity | null | undefined): SeverityStyle {
  switch (severity) {
    case "Critical":
      return { label: "Critical", badge: "bg-red-100 text-red-700 border-red-200", accent: "border-l-red-500" }
    case "Warning":
      return { label: "Warning", badge: "bg-amber-100 text-amber-800 border-amber-200", accent: "border-l-amber-500" }
    case "Information":
      return { label: "Info", badge: "bg-sky-100 text-sky-700 border-sky-200", accent: "border-l-sky-500" }
    default:
      return { label: "Complete", badge: "bg-emerald-100 text-emerald-700 border-emerald-200", accent: "border-l-emerald-500" }
  }
}

/**
 * A `returnTo` query value, accepted only as a same-site path. Anything that
 * could leave the site ("//evil.com", "https://…", "/\\evil") is refused, so a
 * crafted link cannot turn "back to Farm Completeness" into an open redirect.
 */
export function safeReturnPath(raw: string | null | undefined): string | null {
  if (!raw) return null
  const v = raw.trim()
  if (!v.startsWith("/") || v.startsWith("//") || v.startsWith("/\\") || v.includes("\\")) return null
  if (/[\u0000-\u001f]/.test(v)) return null
  return v
}

/** Farm Completeness for a date — where the missing-production journeys return. */
export function farmCompletenessHref(businessDate?: string | null): string {
  const d = toBusinessDate(businessDate)
  return d ? `/poultry-farm-completeness?date=${d}` : "/poultry-farm-completeness"
}

export interface EarlierGapFlock {
  flockId: number
  flockName: string
  batchName: string | null
  houseName: string | null
  /** Missing days in the window (all earlier than the business date). */
  missingDays: number
  /** Newest missing date. */
  latestMissing: string
}

/**
 * Flocks that reported on the business date but still have EARLIER missing
 * days -- the ones the "By flock" list would otherwise leave out, because the
 * check's own items are only the flocks missing on that one day. Ordered by
 * most missing days first. `excludeFlockIds` are the flocks already listed.
 */
export function flocksWithEarlierGaps(
  entries: MissingProductionEntry[],
  excludeFlockIds: Iterable<number>,
): EarlierGapFlock[] {
  const skip = new Set(excludeFlockIds)
  const byFlock = new Map<number, EarlierGapFlock>()
  for (const e of entries) {
    if (skip.has(e.flockId)) continue
    const date = toBusinessDate(e.date)
    if (!date) continue
    const f = byFlock.get(e.flockId)
    if (!f) {
      byFlock.set(e.flockId, {
        flockId: e.flockId, flockName: e.flockName, batchName: e.batchName, houseName: e.houseName,
        missingDays: 1, latestMissing: date,
      })
    } else {
      f.missingDays++
      if (date > f.latestMissing) f.latestMissing = date
    }
  }
  return [...byFlock.values()].sort((a, b) => b.missingDays - a.missingDays || a.flockName.localeCompare(b.flockName))
}

/** The row action for such a flock: step through several days, or record the one. */
export function earlierGapActionHref(f: EarlierGapFlock, businessDate: string): string {
  return f.missingDays > 1 ? flockStepThroughHref(f.flockId, businessDate) : missingDateHref(f.flockId, f.latestMissing)
}
