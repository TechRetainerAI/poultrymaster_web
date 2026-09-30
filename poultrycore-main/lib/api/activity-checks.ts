// Missing Activity Detector — "which expected farm activities are not done yet?"
//
// Client for GET /ActivityChecks (Farm API, migration 332). Everything the
// report says is DERIVED on the server from records that already exist; there
// are no task rows behind it, so there is nothing to create, dismiss or sync
// from here — fix the underlying record and the next read reflects it.
//
// The business date comes back FROM the server, computed in the company's own
// timezone. Callers must display report.businessDate rather than asking the
// browser what day it is (see lib/api/company-time.ts for why).

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

export type ActivitySeverity = "Information" | "Warning" | "Critical"
export type ActivityCheckStatus = "Complete" | "Incomplete" | "NotApplicable"
export type ActivityItemState = "Missing" | "AwaitingPosting"

export interface ActivityCheckItem {
  /** e.g. "flock". Pairs with subjectId. */
  subjectType: string
  subjectId: number
  label: string
  /** The bird batch, for a flock. */
  groupLabel: string | null
  /** The house / pen, for a flock. */
  locationLabel: string | null
  state: ActivityItemState
  severity: ActivitySeverity | null
  /** "yyyy-MM-ddT00:00:00" — a DATE; read it with the helpers, never new Date(). */
  lastCompletedDate: string | null
  daysOutstanding: number
  /** A record already in flight (e.g. an unposted batch production entry). */
  relatedRecordType: string | null
  relatedRecordId: number | null
  relatedRecordStatus: string | null
}

export interface ActivityCheckResult {
  key: string
  module: string
  title: string
  requiredPermission: string
  status: ActivityCheckStatus
  severity: ActivitySeverity | null
  severityReason: string | null
  expectedCount: number
  completedCount: number
  outstandingCount: number
  /** Check-specific counters, e.g. { awaitingPosting, duplicateFlocks }. */
  counters: Record<string, number>
  /** Only the OUTSTANDING subjects. */
  items: ActivityCheckItem[]
}

export interface ActivityCompletenessReport {
  farmId: string
  module: string | null
  businessDate: string
  companyToday: string
  companyLocalDateTime: string
  timeZoneId: string
  generatedAtUtc: string
  severity: ActivitySeverity | null
  checks: ActivityCheckResult[]
  hiddenCheckCount: number
}

/** The server refused: the caller may see none of this company's checks. */
export class ActivityChecksForbiddenError extends Error {
  constructor(message = "You do not have permission to view activity checks for this company.") {
    super(message)
    this.name = "ActivityChecksForbiddenError"
  }
}

/**
 * The report for the active company. `businessDate` ("yyyy-MM-dd") is optional
 * and defaults, on the server, to the company's today.
 *
 * `async` so a missing company rejects instead of throwing synchronously into
 * a render (same reasoning as getCompanyTimeContext).
 */
export async function getActivityChecks(businessDate?: string): Promise<ActivityCompletenessReport> {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")

  const qs = new URLSearchParams({ farmId })
  if (businessDate) qs.set("businessDate", businessDate)
  const path = `/ActivityChecks?${qs.toString()}`

  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    if (res.status === 403) throw new ActivityChecksForbiddenError()
    throw new Error(explainHttpError("GET", path, res.status, t))
  }
  return (await res.json()) as ActivityCompletenessReport
}

export interface MissingProductionDate {
  /** "yyyy-MM-ddT00:00:00" — a business DATE. */
  date: string
  pendingBatchRecordId: number | null
  pendingBatchStatus: string | null
}

export interface FlockMissingProductionDates {
  flockId: number
  businessDate: string
  windowDays: number
  /** Newest first. */
  dates: MissingProductionDate[]
}

/**
 * Every missing production day for one flock within the last `days` days
 * (server clamps 1..366), not just the current run — older gaps included.
 */
export async function getFlockMissingProductionDates(
  flockId: number,
  businessDate?: string,
  days = 30,
): Promise<FlockMissingProductionDates> {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  const qs = new URLSearchParams({ farmId, flockId: String(flockId), days: String(days) })
  if (businessDate) qs.set("businessDate", businessDate)
  const path = `/ActivityChecks/production/missing-dates?${qs.toString()}`
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(explainHttpError("GET", path, res.status, t))
  }
  return (await res.json()) as FlockMissingProductionDates
}

export interface MissingProductionEntry {
  /** "yyyy-MM-ddT00:00:00" — a business DATE. */
  date: string
  flockId: number
  flockName: string
  batchName: string | null
  houseName: string | null
  pendingBatchRecordId: number | null
  pendingBatchStatus: string | null
}

export interface MissingProductionByDate {
  businessDate: string
  windowDays: number
  /** Newest date first. */
  entries: MissingProductionEntry[]
}

/** Every missing (date, flock) farm-wide in the last `days` days (migration 334). */
export async function getMissingProductionByDate(businessDate?: string, days = 30): Promise<MissingProductionByDate> {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  const qs = new URLSearchParams({ farmId, days: String(days) })
  if (businessDate) qs.set("businessDate", businessDate)
  const path = `/ActivityChecks/production/missing-by-date?${qs.toString()}`
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(explainHttpError("GET", path, res.status, t))
  }
  return (await res.json()) as MissingProductionByDate
}
