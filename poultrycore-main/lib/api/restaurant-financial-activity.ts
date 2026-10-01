// =============================================================================
// Restaurant Financial Activity — API client (migration 335).
//
// Reads /api/Restaurant/financial-activity, built over the SAME functions the
// Restaurant Cash Flow and Profit & Loss pages read, and returns Poultry's
// shapes (lib/api/poultry-financial-activity.ts), so the page and its display
// helpers are shared word for word. Money In is not Revenue and Money Out is not
// Expense; nothing here derives one from the other.
// =============================================================================

import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"
import type {
  FinancialActivityResponse, FinancialActivityRow, FinancialPositionChange,
} from "./poultry-financial-activity"

const num = (v: unknown): number => {
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

export async function getRestaurantFinancialActivity(
  opts?: { fromDate?: string; toDate?: string },
): Promise<FinancialActivityResponse> {
  const farmId = getUserContext().farmId ?? ""
  const qs = new URLSearchParams({ farmId })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  const res = await fetch(farmApiUrl(`/Restaurant/financial-activity?${qs.toString()}`), { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  const raw = await res.json()
  const s = raw?.summary ?? {}
  return {
    farmId: raw?.farmId ?? farmId,
    fromDate: raw?.fromDate ?? null,
    toDate: raw?.toDate ?? null,
    summary: {
      moneyIn: num(s.moneyIn), moneyOut: num(s.moneyOut), netCashFlow: num(s.netCashFlow),
      openingCash: num(s.openingCash), closingCash: num(s.closingCash), revenue: num(s.revenue),
      expense: num(s.expense), netProfit: num(s.netProfit), eventCount: num(s.eventCount),
      cashEvents: num(s.cashEvents), nonCashEvents: num(s.nonCashEvents),
    },
    rows: Array.isArray(raw?.rows)
      ? raw.rows.map((r: any): FinancialActivityRow => ({
          eventKey: r.eventKey ?? "", businessDate: r.businessDate ?? "", occurredAt: r.occurredAt ?? "",
          createdAt: r.createdAt ?? null, activityType: r.activityType ?? "Operating", type: r.type ?? "",
          category: r.category ?? "", description: r.description ?? null, sourceType: r.sourceType ?? null,
          sourceId: r.sourceId == null ? null : num(r.sourceId), sourceNumber: r.sourceNumber ?? null,
          moneyIn: num(r.moneyIn), moneyOut: num(r.moneyOut), revenue: num(r.revenue), expense: num(r.expense),
          profitImpact: num(r.profitImpact), runningCash: num(r.runningCash),
          isCashActivity: !!r.isCashActivity, isNonCashActivity: !!r.isNonCashActivity,
          isInternalTransfer: !!r.isInternalTransfer,
          cashAccountId: r.cashAccountId == null ? null : num(r.cashAccountId),
          cashAccountName: r.cashAccountName ?? null, partyName: r.partyName ?? null,
          plLine: r.plLine ?? null, status: r.status ?? null,
          positionChanges: Array.isArray(r.positionChanges)
            ? r.positionChanges.map((p: any): FinancialPositionChange => ({
                positionType: p.positionType ?? "", positionName: p.positionName ?? "",
                increaseAmount: num(p.increaseAmount), decreaseAmount: num(p.decreaseAmount),
                explanation: p.explanation ?? null,
              }))
            : [],
        }))
      : [],
  }
}

/** Where a Restaurant event's source record lives, or null when it has no page. */
export function restaurantActivitySourceLink(row: FinancialActivityRow): { href: string; label: string } | null {
  switch (row.sourceType) {
    case "Order":
    case "OrderRefund":                 return { href: "/restaurant-orders", label: "View orders" }
    case "OrderPayment":
    case "OrderPaymentReversal":
    case "CustomerPayment":
    case "CustomerPaymentReversal":     return { href: "/restaurant-payments", label: "View payment" }
    case "SupplierPayment":
    case "SupplierPaymentReversal":     return { href: "/restaurant-supplier-payments", label: "View supplier payment" }
    case "Expense":
    case "ExpenseReversal":             return { href: "/restaurant-expenses", label: "View expense" }
    case "StockPurchase":
    case "StockPurchaseReversal":       return { href: "/restaurant-inventory?tab=purchases", label: "View purchase" }
    case "StockUse":                    return { href: "/restaurant-deferred-costs", label: "View deferred inventory cost" }
    case "LoanReceived":
    case "LoanReceivedReversal":
    case "LoanRepayment":
    case "LoanRepaymentReversal":       return { href: "/restaurant-loans", label: "View loan" }
    case "OwnerContribution":
    case "OwnerDraw":                   return { href: "/restaurant-owner-money", label: "View owner money" }
    case "CashTransfer":                return { href: "/restaurant-cash-transfers", label: "View transfer" }
    case "AssetPurchase":
    case "AssetPurchaseReversal":
    case "AssetDisposal":
    case "Depreciation":                return { href: "/restaurant-assets", label: "View capital assets" }
    case "Payroll":                     return { href: "/restaurant-payroll", label: "View payroll" }
    case "EmployeeLoanDisbursement":
    case "EmployeeLoanReversal":
    case "EmployeeLoanRepayment":
    case "EmployeeLoanRepaymentReversal": return { href: "/restaurant-staff-loans", label: "View staff loan" }
    default:                            return null
  }
}
