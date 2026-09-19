// =============================================================================
// Financial Activity — API client.
//
// Reads /api/Poultry/financial-activity, built by migration 290 over the SAME
// functions Cash Flow and Profit & Loss read. That is what lets this page
// explain why the two disagree instead of becoming a third opinion.
//
// The one rule that governs every field here: Money In is not Revenue and Money
// Out is not Expense. They are separate numbers because they answer separate
// questions, and nothing in this file derives one from the other.
// =============================================================================

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"

/** Operating | Financing | Owner | Capital | Inventory | Transfer. */
export type FinancialActivityType =
  | "Operating" | "Financing" | "Owner" | "Capital" | "Inventory" | "Transfer"
  // Migration 308. Its own activity rather than Financing: Financing is money
  // the business RAISED, and an advance to a worker runs the other way.
  | "EmployeeLoan"

/**
 * Which asset, debt or capital balance an event moved. Not a chart of accounts —
 * only positions this database actually tracks and an owner already understands.
 */
export interface FinancialPositionChange {
  positionType: string
  positionName: string
  increaseAmount: number
  decreaseAmount: number
  explanation?: string | null
}

export interface FinancialActivityRow {
  /** Stable identity of the business event, e.g. "Sale:2166", "LoanPayment:5". */
  eventKey: string
  /** The day the event belongs to (yyyy-mm-dd once sliced). */
  businessDate: string
  /**
   * Wall-clock time exactly as recorded. The column is `timestamp without time
   * zone` holding the company's own local time, so this string must be read as
   * written — never passed through `new Date()` for display, which would shift
   * it by the browser's offset.
   */
  occurredAt: string
  activityType: FinancialActivityType | string
  type: string
  category: string
  description?: string | null
  sourceType?: string | null
  sourceId?: number | null
  sourceNumber?: string | null

  /** Actual money that entered the company. Never revenue. */
  moneyIn: number
  /** Actual money that left the company. Never an expense. */
  moneyOut: number
  /** Recognised at the sale, not at collection. */
  revenue: number
  /** Recognised when the cost belongs, which may be long after it was paid. */
  expense: number
  /** revenue − expense. Money movement is never part of it. */
  profitImpact: number
  /** Cash position after this event; unchanged by non-cash events. */
  runningCash: number

  isCashActivity: boolean
  isNonCashActivity: boolean
  isInternalTransfer: boolean

  cashAccountId?: number | null
  cashAccountName?: string | null
  partyName?: string | null
  plLine?: string | null
  status?: string | null

  positionChanges: FinancialPositionChange[]
}

export interface FinancialActivitySummary {
  moneyIn: number
  moneyOut: number
  netCashFlow: number
  openingCash: number
  closingCash: number
  revenue: number
  expense: number
  netProfit: number
  eventCount: number
  cashEvents: number
  nonCashEvents: number
}

export interface FinancialActivityResponse {
  farmId: string | null
  fromDate: string | null
  toDate: string | null
  summary: FinancialActivitySummary
  rows: FinancialActivityRow[]
}

const EMPTY_SUMMARY: FinancialActivitySummary = {
  moneyIn: 0, moneyOut: 0, netCashFlow: 0, openingCash: 0, closingCash: 0,
  revenue: 0, expense: 0, netProfit: 0, eventCount: 0, cashEvents: 0, nonCashEvents: 0,
}

const num = (v: unknown): number => {
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

export async function getPoultryFinancialActivity(
  opts?: { fromDate?: string; toDate?: string; farmId?: string },
): Promise<FinancialActivityResponse> {
  const farmId = opts?.farmId ?? getUserContext().farmId ?? ""
  const qs = new URLSearchParams({ farmId })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)

  const path = `/Poultry/financial-activity?${qs.toString()}`
  const res = await fetch(farmApiUrl(path), { method: "GET", headers: getAuthHeaders() })
  if (!res.ok) {
    const text = await res.text().catch(() => "")
    throw new Error(explainHttpError("GET", path, res.status, text))
  }

  const raw = await res.json()
  const s = raw?.summary ?? {}
  return {
    farmId: raw?.farmId ?? farmId,
    fromDate: raw?.fromDate ?? null,
    toDate: raw?.toDate ?? null,
    summary: {
      ...EMPTY_SUMMARY,
      moneyIn: num(s.moneyIn),
      moneyOut: num(s.moneyOut),
      netCashFlow: num(s.netCashFlow),
      openingCash: num(s.openingCash),
      closingCash: num(s.closingCash),
      revenue: num(s.revenue),
      expense: num(s.expense),
      netProfit: num(s.netProfit),
      eventCount: num(s.eventCount),
      cashEvents: num(s.cashEvents),
      nonCashEvents: num(s.nonCashEvents),
    },
    rows: Array.isArray(raw?.rows)
      ? raw.rows.map((r: any): FinancialActivityRow => ({
          eventKey: r.eventKey ?? "",
          businessDate: r.businessDate ?? "",
          occurredAt: r.occurredAt ?? "",
          activityType: r.activityType ?? "Operating",
          type: r.type ?? "",
          category: r.category ?? "",
          description: r.description ?? null,
          sourceType: r.sourceType ?? null,
          sourceId: r.sourceId == null ? null : num(r.sourceId),
          sourceNumber: r.sourceNumber ?? null,
          moneyIn: num(r.moneyIn),
          moneyOut: num(r.moneyOut),
          revenue: num(r.revenue),
          expense: num(r.expense),
          profitImpact: num(r.profitImpact),
          runningCash: num(r.runningCash),
          isCashActivity: !!r.isCashActivity,
          isNonCashActivity: !!r.isNonCashActivity,
          isInternalTransfer: !!r.isInternalTransfer,
          cashAccountId: r.cashAccountId == null ? null : num(r.cashAccountId),
          cashAccountName: r.cashAccountName ?? null,
          partyName: r.partyName ?? null,
          plLine: r.plLine ?? null,
          status: r.status ?? null,
          positionChanges: Array.isArray(r.positionChanges)
            ? r.positionChanges.map((p: any): FinancialPositionChange => ({
                positionType: p.positionType ?? "",
                positionName: p.positionName ?? "",
                increaseAmount: num(p.increaseAmount),
                decreaseAmount: num(p.decreaseAmount),
                explanation: p.explanation ?? null,
              }))
            : [],
        }))
      : [],
  }
}

// ---------------------------------------------------------------------------
// Display helpers, kept here so the page and any export agree on wording.
// ---------------------------------------------------------------------------

/** Business-friendly name for a position. */
export const POSITION_LABELS: Record<string, string> = {
  Cash: "Cash",
  CustomerReceivable: "Customer Receivable",
  SupplierPayable: "Supplier Payable",
  Inventory: "Inventory",
  CapitalAsset: "Capital Assets",
  AccumulatedDepreciation: "Accumulated Depreciation",
  LoanLiability: "Loan Liability",
  OwnerCapital: "Owner Capital",
  // Deliberately NOT folded into CustomerReceivable: money owed for something
  // sold and money lent to staff are collected differently and mean different
  // things, and an owner reading "Customer Receivable" should not find the
  // storeman's advance inside it. Spec section 63, migration 308.
  EmployeeLoanReceivable: "Employee Loan Receivable",
}

export const positionLabel = (t: string): string => POSITION_LABELS[t] ?? t

/**
 * Where an event's source record lives, so a row can be opened. Returns null
 * where the module has no detail page to open — a link that 404s is worse than
 * no link.
 */
export function activitySourceLink(row: FinancialActivityRow): { href: string; label: string } | null {
  const id = row.sourceId
  switch (row.sourceType) {
    case "Sale":                        return { href: "/sales", label: "View sale" }
    case "CustomerPayment":             return { href: "/poultry-payments", label: "View payment" }
    case "SupplierPayment":             return { href: "/supplier-payments", label: "View supplier payment" }
    case "Expense":                     return { href: "/expenses", label: "View expense" }
    case "LoanReceived":
    case "LoanPayment":                 return { href: "/poultry-loans", label: "View loan" }
    case "OwnerContribution":
    case "OwnerDraw":                   return { href: "/poultry-owner-money", label: "View owner money" }
    case "CashTransfer":                return { href: "/poultry-cash-transfers", label: "View transfer" }
    case "CapitalAsset":
    case "CapitalAssetCost":
    case "AssetDepreciation":
      return id ? { href: `/poultry-assets`, label: "View capital assets" } : null
    case "PoultryRawMaterialPurchase":  return { href: "/poultry-raw-materials?tab=purchases", label: "View purchase" }
    case "PoultryFeedConsumption":      return { href: "/feed-inventory-tracker", label: "View feed movements" }
    case "PoultryMedicationConsumption":return { href: "/medication-tracker", label: "View medication" }
    case "PoultryInternalUsage":        return { href: "/poultry-internal-use", label: "View internal use" }
    case "Payroll":                     return { href: "/poultry-payroll", label: "View payroll" }
    case "MainFlockBatch":              return { href: "/flocks", label: "View flock batch" }
    default:                            return null
  }
}

/**
 * The stored timestamp is company-local wall clock in a `timestamp without time
 * zone` column. Formatting it through Date would apply the BROWSER's offset and
 * move an evening entry to the previous day for anyone west of the farm, so the
 * string is sliced instead.
 */
export function formatActivityMoment(occurredAt: string): string {
  const s = (occurredAt || "").trim()
  if (!s) return "—"
  const [datePart, timePartRaw] = s.split("T")
  const [y, m, d] = (datePart || "").split("-")
  if (!y || !m || !d) return s
  const dayText = `${m}/${d}/${y}`
  const timePart = (timePartRaw || "").slice(0, 5)
  if (!timePart || timePart === "00:00") return dayText
  const [hhStr, mm] = timePart.split(":")
  const hh = Number(hhStr)
  const suffix = hh >= 12 ? "PM" : "AM"
  const h12 = hh % 12 === 0 ? 12 : hh % 12
  return `${dayText} ${h12}:${mm} ${suffix}`
}
