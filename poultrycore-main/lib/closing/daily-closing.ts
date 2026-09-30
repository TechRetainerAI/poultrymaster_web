// Pure helpers for the Daily Closing page (migration 333). No React, no fetch —
// covered by daily-closing.test.ts.
//
// Business dates are "yyyy-MM-dd" strings and stay strings; see the note in
// lib/activity/completeness.ts about why `new Date()` is not used on them.

import type {
  CheckSection,
  CheckStatus,
  ClosingCheck,
  ClosingRecord,
  ClosingWorkspace,
} from "@/lib/api/poultry-daily-closing"
import { shiftBusinessDate, toBusinessDate } from "@/lib/activity/completeness"

/** What the owner sees. "Approved" is the workflow's word; "Closed" is the meaning. */
export function closingStatusLabel(record: Pick<ClosingRecord, "status"> | null | undefined): string {
  switch (record?.status) {
    case "Approved":
      return "Closed"
    case "Submitted":
      return "Awaiting approval"
    case "Rejected":
      return "Rejected"
    case "Draft":
      return "Open"
    default:
      return "Not closed"
  }
}

export interface CloseReadiness {
  canClose: boolean
  blockers: ClosingCheck[]
  warnings: ClosingCheck[]
  complete: ClosingCheck[]
  /** Why the button is disabled, in one sentence; null when it is not. */
  reason: string | null
}

export function closeReadiness(
  ws: Pick<ClosingWorkspace, "checklist">,
  record: Pick<ClosingRecord, "status"> | null | undefined,
): CloseReadiness {
  const blockers = ws.checklist.filter((c) => c.status === "Blocking")
  const warnings = ws.checklist.filter((c) => c.status === "Warning")
  const complete = ws.checklist.filter((c) => c.status === "Complete")
  let reason: string | null = null
  if (record?.status === "Approved") reason = "This day is already closed."
  else if (blockers.length === 1) reason = "1 blocking check must be resolved first."
  else if (blockers.length > 1) reason = `${blockers.length} blocking checks must be resolved first.`
  return { canClose: reason === null, blockers, warnings, complete, reason }
}

export const SECTION_ORDER: CheckSection[] = ["production", "sales", "cash", "inventory", "expenses", "outstanding", "alerts"]

export const SECTION_LABELS: Record<CheckSection, string> = {
  production: "Production",
  sales: "Sales",
  cash: "Cash",
  inventory: "Inventory",
  expenses: "Expenses",
  outstanding: "Outstanding items",
  alerts: "Alerts",
}

export function checkIcon(status: CheckStatus): "check" | "warning" | "block" {
  return status === "Complete" ? "check" : status === "Warning" ? "warning" : "block"
}

/**
 * Where a checklist item's "Action" goes. The server sends a key, not a URL,
 * so routes live in one place on the client. Unknown keys get no link rather
 * than a guessed one.
 */
export function closingActionHref(action: string | null | undefined, businessDate: string): string | null {
  const date = toBusinessDate(businessDate)
  switch (action) {
    case "missing-production":
      return date ? `/poultry-farm-completeness?date=${date}` : "/poultry-farm-completeness"
    case "unposted-batches":
      return "/batch-production-records"
    case "production-records":
      return "/production-records"
    case "cash-count":
      return "/poultry-cash-reconciliation"
    case "inventory":
      return "/poultry-raw-materials"
    case "customer-balances":
      return "/customer-balances"
    case "driver-returns":
      return "/poultry-driver-returns"
    case "previous-day": {
      const prev = date ? shiftBusinessDate(date, -1) : null
      return prev ? `/poultry-daily-closing?date=${prev}` : null
    }
    default:
      return null
  }
}

export type FigureKind = "money" | "count" | "quantity"

export interface TrackedFigure {
  section: CheckSection
  label: string
  kind: FigureKind
  read: (ws: ClosingWorkspace) => number | null | undefined
}

/**
 * The figures compared between the State At Closing and the Current Corrected
 * State. These are the headline numbers the closing summary reports; if one of
 * them moved after the day was closed, the owner needs to see it.
 */
export const TRACKED_FIGURES: TrackedFigure[] = [
  { section: "production", label: "Production records", kind: "count", read: (w) => w.production.records },
  { section: "production", label: "Missing production", kind: "count", read: (w) => w.production.missingFlocks },
  { section: "production", label: "Eggs produced", kind: "count", read: (w) => w.production.eggsProduced },
  { section: "production", label: "Mortality", kind: "count", read: (w) => w.production.mortality },
  { section: "production", label: "Feed used (kg)", kind: "quantity", read: (w) => w.production.feedKg },
  { section: "sales", label: "Sales", kind: "money", read: (w) => w.sales.revenue },
  { section: "sales", label: "Credit sales", kind: "money", read: (w) => w.sales.creditSales },
  { section: "sales", label: "Payments received", kind: "money", read: (w) => w.sales.paymentsReceived },
  { section: "cash", label: "Money in", kind: "money", read: (w) => w.cash.moneyIn },
  { section: "cash", label: "Money out", kind: "money", read: (w) => w.cash.moneyOut },
  { section: "cash", label: "Net cash flow", kind: "money", read: (w) => w.cash.netCashFlow },
  { section: "expenses", label: "Expenses", kind: "money", read: (w) => w.expenses.total },
]

export interface FigureChange {
  section: CheckSection
  label: string
  kind: FigureKind
  atClose: number
  current: number
  delta: number
}

function num(v: number | null | undefined): number {
  const n = Number(v ?? 0)
  return Number.isFinite(n) ? n : 0
}

/**
 * What changed after the day was closed. Money is compared to the cent so
 * floating-point noise never reports a phantom correction.
 */
export function diffClosingState(
  atClose: ClosingWorkspace | null | undefined,
  current: ClosingWorkspace | null | undefined,
): FigureChange[] {
  if (!atClose || !current) return []
  const out: FigureChange[] = []
  for (const f of TRACKED_FIGURES) {
    const a = num(f.read(atClose))
    const c = num(f.read(current))
    const scale = f.kind === "money" ? 100 : 1000
    if (Math.round(a * scale) === Math.round(c * scale)) continue
    out.push({ section: f.section, label: f.label, kind: f.kind, atClose: a, current: c, delta: Math.round((c - a) * scale) / scale })
  }
  return out
}

/** "September 20, 2026" from "2026-09-20", without the browser's timezone. */
export function formatLongDate(value: string | null | undefined): string {
  const d = toBusinessDate(value)
  if (!d) return "—"
  const [y, m, day] = d.split("-").map(Number)
  const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December"]
  return `${MONTHS[m - 1]} ${day}, ${y}`
}

/** "Production: Complete" / "Production: 3 flocks missing" for the closing summary. */
export function productionSummaryLine(ws: Pick<ClosingWorkspace, "production">): string {
  const p = ws.production
  if (p.expectedFlocks === 0) return "No flocks expected"
  if (p.missingFlocks === 0) return "Complete"
  return `${p.missingFlocks} of ${p.expectedFlocks} flocks missing`
}
