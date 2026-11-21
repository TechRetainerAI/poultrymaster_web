// =============================================================================
// Water Financial Activity — API client (migration 461; same shape as Generic 419).
//
// Reads /api/Water/financial-activity?farmId=, built by migration 461 over the
// SAME functions Water Cash Flow and Profit & Loss read. The types and
// display helpers are re-exported from the poultry module, which defined the
// shared shapes.
// =============================================================================

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"

// Re-export the shared types and helpers — the DTOs are identical across rails.
export type {
  FinancialActivityType, FinancialPositionChange, FinancialActivityRow,
  FinancialActivitySummary, FinancialActivityResponse,
} from "./poultry-financial-activity"

export {
  POSITION_LABELS, positionLabel, formatActivityMoment,
} from "./poultry-financial-activity"

import type {
  FinancialActivityResponse, FinancialActivityRow, FinancialPositionChange,
} from "./poultry-financial-activity"

const EMPTY_SUMMARY = {
  moneyIn: 0, moneyOut: 0, netCashFlow: 0, openingCash: 0, closingCash: 0,
  revenue: 0, expense: 0, netProfit: 0, eventCount: 0, cashEvents: 0, nonCashEvents: 0,
}

const num = (v: unknown): number => {
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

export async function getWaterFinancialActivity(
  opts?: { fromDate?: string; toDate?: string; farmId?: string },
): Promise<FinancialActivityResponse> {
  const farmId = opts?.farmId ?? getUserContext().farmId ?? ""
  const qs = new URLSearchParams()
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)

  qs.append("farmId", farmId)
  const path = `/Water/financial-activity?${qs.toString()}`
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
          createdAt: r.createdAt ?? null,
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

/** Where an event's source record lives, for Water company pages. */
export function waterActivitySourceLink(row: FinancialActivityRow): { href: string; label: string } | null {
  switch (row.sourceType) {
    case "Receipt":
    case "ReceiptReversal":         return { href: "/water-payments", label: "View payment" }
    case "CustomerRefund":
    case "CustomerRefundReversal":  return { href: "/water-customer-credits", label: "View refund" }
    case "Sale":
    case "SaleResidual":            return row.sourceId ? { href: `/water-sales?saleId=${row.sourceId}`, label: "View sale" } : { href: "/water-sales", label: "View sales" }
    case "DeliveryReturn":          return { href: "/water-driver-returns", label: "View driver return" }
    case "Expense":                 return { href: "/water-expenses", label: "View expense" }
    case "ExpensePayment":
    case "SupplierPurchasePayment":
    case "SupplierAdvanceOrDebt":
    case "SupplierPaymentReversal": return { href: "/water-supplier-payments", label: "View supplier payment" }
    case "SupplierRefund":
    case "SupplierRefundReversal":  return { href: "/water-supplier-credits", label: "View refund" }
    case "DirectCost":              return { href: "/water-profit-loss", label: "View on P&L" }
    case "Loss":                    return { href: "/water-loss-records", label: "View losses" }
    case "OwnerMoney":              return { href: "/water-owner-money", label: "View owner money" }
    case "Loan":
    case "LoanPayment":             return { href: "/water-loans", label: "View loan" }
    case "EmployeeLoan":
    case "EmployeeLoanRepayment":   return { href: "/water-employee-loans", label: "View advance" }
    case "EmployeeCredit":
    case "EmployeeCreditReversal":  return { href: "/water-employee-credit", label: "View employee credit" }
    default:                        return null
  }
}
