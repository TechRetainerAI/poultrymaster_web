// Daily Farm Closing / management control — client for the Farm API endpoints
// added by migration 333 (api/Poultry/daily-closings/day, /close, /history,
// /policy, /events/{id}/snapshot).
//
// The workspace is built on the server as one document and a close stores that
// same document, so `live` and `atClose` below always have the same shape. The
// business date in it is the COMPANY's day; never substitute the browser's.
//
// The older Draft/Submit/Approve calls stay in lib/api/poultry-inventory.ts.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

export type CheckStatus = "Complete" | "Warning" | "Blocking"
export type CheckSection = "production" | "sales" | "cash" | "inventory" | "expenses" | "outstanding" | "alerts"

export interface ClosingCheck {
  key: string
  section: CheckSection
  status: CheckStatus
  title: string
  description: string | null
  /** A key the UI maps to a page (see closingActionHref) — never a URL. */
  action: string | null
}

export interface InventoryException {
  itemId: number
  item: string
  quantity: number
  unit?: string | null
  minimum?: number
  dailyUse?: number
  daysRemaining?: number
}

export interface ClosingWorkspace {
  farmId: string
  businessDate: string
  companyToday: string
  companyLocalTime: string
  timeZoneId: string
  currencySymbol: string | null
  generatedAtUtc: string
  production: {
    expectedFlocks: number
    reportedFlocks: number
    missingFlocks: number
    awaitingPosting: number
    duplicateFlocks: number
    records: number
    eggsProduced: number
    eggsDamaged: number
    goodEggs: number
    mortality: number
    feedKg: number
    medicationUsed: number
    productionCost: number
    unpostedBatches: { id: number; status: string; name: string }[]
    impossibleBirdCounts: { recordId: number; flockId: number; flock: string | null }[]
    unusualMortality: { flockId: number; flock: string | null; mortality: number; birds: number; pct: number }[]
  }
  sales: {
    count: number
    revenue: number
    cashSales: number
    creditSales: number
    paymentsReceived: number
    paymentsCount: number
    receivablesChange: number
  }
  cash: {
    moneyIn: number
    moneyOut: number
    netCashFlow: number
    openingCash: number
    closingCash: number
    reconciliations: number
    /** Only present when a cash count was POSTED for the day. */
    expectedCash: number | null
    actualCash: number | null
    difference: number | null
  }
  expenses: { count: number; total: number; cash: number; credit: number; nonCash: number }
  inventory: { lowFeed: InventoryException[]; lowStock: InventoryException[]; negativeStock: InventoryException[] }
  outstanding: {
    unpostedBatches: number
    draftDriverReturns: number
    loadingsWithoutReturn: number
    previousDayClosed: boolean
  }
  policy: ClosingPolicy & { isCustomised: boolean }
  checklist: ClosingCheck[]
  counts: { blocking: number; warning: number; complete: number }
}

export interface ClosingRecord {
  poultryDailyClosingId: number
  closingDate: string
  /** Draft | Submitted | Approved | Rejected — Approved means the day is closed. */
  status: string
  isClosed: boolean
  managerNotes: string | null
  rejectionReason: string | null
  createdBy: string | null
  submittedBy: string | null
  submittedAt: string | null
  closedAtUtc: string | null
  closedBy: string | null
  closeVersion: number
  warningsAtClose: number | null
  lastReopenedAtUtc: string | null
  lastReopenedBy: string | null
  lastReopenReason: string | null
}

export interface ClosingEvent {
  eventId: number
  poultryDailyClosingId: number
  eventType: "Created" | "Submitted" | "Rejected" | "Closed" | "Reopened" | "Recreated" | "Deleted"
  fromStatus: string | null
  toStatus: string | null
  actor: string | null
  reason: string | null
  closeVersion: number | null
  warningCount: number | null
  occurredAtUtc: string
  hasSnapshot: boolean
}

export interface ClosingDayView {
  farmId: string
  businessDate: string
  closing: ClosingRecord | null
  /** Current Corrected State. */
  live: ClosingWorkspace
  /** State At Closing — kept after a reopen. */
  atClose: ClosingWorkspace | null
  history: ClosingEvent[]
}

export interface ClosingHistoryRow {
  poultryDailyClosingId: number
  closingDate: string
  status: string
  isClosed: boolean
  closedAtUtc: string | null
  closedBy: string | null
  closeVersion: number
  warningsAtClose: number | null
  reopenCount: number
  lastReopenedAtUtc: string | null
  lastReopenReason: string | null
  revenue: number | null
  moneyIn: number | null
  moneyOut: number | null
  netCashFlow: number | null
  eggsProduced: number | null
  missingFlocks: number | null
  hasSnapshot: boolean
}

export type PolicyLevel = "Blocking" | "Warning"

export interface ClosingPolicy {
  missingProduction: PolicyLevel
  unpostedProduction: PolicyLevel
  impossibleBirdCounts: PolicyLevel
  pendingDriverReturns: PolicyLevel
  negativeStock: PolicyLevel
  cashDifference: PolicyLevel
  cashDifferenceTolerance: number
  requireCashCount: boolean
  lowFeedDays: number
  unusualMortalityPct: number
}

export interface CloseDayResult {
  poultryDailyClosingId: number
  closeVersion: number
  warningCount: number
  closedAtUtc: string
}

/** The API refused to close: a blocker, or the day is already closed. */
export class CloseDayConflictError extends Error {
  constructor(message: string, public readonly code: "Blocked" | "AlreadyClosed" | string) {
    super(message)
    this.name = "CloseDayConflictError"
  }
}

function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function readMessage(res: Response): Promise<{ message?: string; code?: string; raw: string }> {
  const raw = await res.text().catch(() => "")
  try {
    const j = JSON.parse(raw)
    return { message: j?.message ?? j?.Message, code: j?.code, raw }
  } catch {
    return { raw }
  }
}

async function call<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(farmApiUrl(path), {
    method,
    headers: getAuthHeaders(),
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const m = await readMessage(res)
    if (res.status === 409) throw new CloseDayConflictError(m.message ?? "The day could not be closed.", m.code ?? "")
    if ((res.status === 400 || res.status === 403) && m.message) throw new Error(m.message)
    throw new Error(explainHttpError(method, path, res.status, m.raw))
  }
  if (res.status === 204) return undefined as T
  const text = await res.text()
  return (text ? JSON.parse(text) : undefined) as T
}

/** `businessDate` "yyyy-MM-dd"; omitted means the company's today (server-decided). */
export async function getClosingDay(businessDate?: string): Promise<ClosingDayView> {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (businessDate) qs.set("businessDate", businessDate)
  return call<ClosingDayView>("GET", `/Poultry/daily-closings/day?${qs}`)
}

export async function closeBusinessDay(businessDate: string, notes?: string): Promise<CloseDayResult> {
  return call<CloseDayResult>("POST", `/Poultry/daily-closings/close`, {
    farmId: activeFarmId(),
    businessDate,
    notes: notes?.trim() || null,
  })
}

export async function reopenBusinessDay(closingId: number, reason: string): Promise<void> {
  return call<void>(
    "POST",
    `/Poultry/daily-closings/${closingId}/reopen?farmId=${encodeURIComponent(activeFarmId())}`,
    { reason },
  )
}

export async function getClosingHistory(fromDate?: string, toDate?: string): Promise<ClosingHistoryRow[]> {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (fromDate) qs.set("fromDate", fromDate)
  if (toDate) qs.set("toDate", toDate)
  return call<ClosingHistoryRow[]>("GET", `/Poultry/daily-closings/history?${qs}`)
}

export async function getClosingEventSnapshot(eventId: number): Promise<ClosingWorkspace> {
  return call<ClosingWorkspace>(
    "GET",
    `/Poultry/daily-closings/events/${eventId}/snapshot?farmId=${encodeURIComponent(activeFarmId())}`,
  )
}

export async function getClosingPolicy(): Promise<ClosingPolicy & { isCustomised: boolean }> {
  return call("GET", `/Poultry/daily-closings/policy?farmId=${encodeURIComponent(activeFarmId())}`)
}

export async function saveClosingPolicy(policy: ClosingPolicy): Promise<void> {
  return call<void>("PUT", `/Poultry/daily-closings/policy`, { ...policy, farmId: activeFarmId() })
}
