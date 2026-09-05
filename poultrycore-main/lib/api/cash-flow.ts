// =============================================================================
// Cash Flow — API client, both rails.
//
// Reads /api/{Poultry|Water}/cash-flow, which is built on business transactions:
// customer receipts, expenses, and capital in and out.
//
// It deliberately does NOT read cash accounts, the cash ledger, transfers or
// reconciliation. Cash Flow answers "what did the business earn and spend";
// where the money currently sits is the Cash Accounts module's question, and
// keeping the two apart is what lets reconciliation check one against the other.
// =============================================================================

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"

export type CashFlowRail = "Poultry" | "Water"

/** OperatingIn | OperatingOut | FinancingIn | FinancingOut. */
export type FlowGroup = "OperatingIn" | "OperatingOut" | "FinancingIn" | "FinancingOut"

export interface CashFlowRow {
  /** Id within its own source table — NOT unique across sources. */
  id: number
  /** Receipt | SaleResidual | Expense | Adjustment. */
  rowSource: string
  sourceType: string
  sourceId: number | null
  flowGroup: FlowGroup | string
  /** What the money was for: expense category, "Sales", or the capital type. */
  category: string
  transactionDate: string
  description: string | null
  /** Informational only; Cash Flow never filters or totals by account. */
  cashAccountId: number | null
  /** Signed: positive in, negative out. */
  amount: number
  inflow: number
  outflow: number
}

export interface CashFlowSummary {
  moneyIn: number
  moneyOut: number
  netCashFlow: number
  /** Everything eligible before the period opened. Measured, not derived from a balance. */
  openingCash: number
  /**
   * openingCash + moneyIn − moneyOut, true by construction.
   * NOT the sum of cash account balances, and not expected to match it.
   */
  closingCash: number
  operatingIn: number
  operatingOut: number
  financingIn: number
  financingOut: number
  movementCount: number
}

export interface CashFlowResponse {
  farmId: string | null
  fromDate: string | null
  toDate: string | null
  summary: CashFlowSummary
  rows: CashFlowRow[]
}

const EMPTY_SUMMARY: CashFlowSummary = {
  moneyIn: 0, moneyOut: 0, netCashFlow: 0, openingCash: 0, closingCash: 0,
  operatingIn: 0, operatingOut: 0, financingIn: 0, financingOut: 0, movementCount: 0,
}

const num = (v: unknown): number => {
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

/**
 * Fetch the cash flow for a period.
 *
 * Dates are plain yyyy-mm-dd. The server widens the end date to cover the whole
 * day — a bare date binds to midnight and would otherwise drop everything
 * recorded on the final day of the range.
 */
export async function getCashFlow(
  rail: CashFlowRail,
  opts?: { fromDate?: string; toDate?: string; farmId?: string },
): Promise<CashFlowResponse> {
  const farmId = opts?.farmId ?? getUserContext().farmId ?? ""
  const qs = new URLSearchParams({ farmId })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)

  const path = `/${rail}/cash-flow?${qs.toString()}`
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
      operatingIn: num(s.operatingIn),
      operatingOut: num(s.operatingOut),
      financingIn: num(s.financingIn),
      financingOut: num(s.financingOut),
      movementCount: num(s.movementCount),
    },
    rows: Array.isArray(raw?.rows)
      ? raw.rows.map((r: any) => ({
          id: num(r.id),
          rowSource: r.rowSource ?? "",
          sourceType: r.sourceType ?? "",
          sourceId: r.sourceId == null ? null : num(r.sourceId),
          flowGroup: r.flowGroup ?? "",
          category: r.category ?? "Other",
          transactionDate: r.transactionDate ?? "",
          description: r.description ?? null,
          cashAccountId: r.cashAccountId == null ? null : num(r.cashAccountId),
          amount: num(r.amount),
          inflow: num(r.inflow),
          outflow: num(r.outflow),
        }))
      : [],
  }
}

/** Human label for a flow group. */
export const FLOW_GROUP_LABELS: Record<string, string> = {
  OperatingIn: "Operating income",
  OperatingOut: "Operating expense",
  FinancingIn: "Capital received",
  FinancingOut: "Capital withdrawn",
}

export const flowGroupLabel = (g: string): string => FLOW_GROUP_LABELS[g] ?? g

/** True when the group is money coming in. */
export const isInflowGroup = (g: string): boolean =>
  g === "OperatingIn" || g === "FinancingIn"
