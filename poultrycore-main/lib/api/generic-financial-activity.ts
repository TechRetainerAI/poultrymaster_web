// =============================================================================
// Generic Financial Activity — API client.
//
// Reads /api/generic-company/{farmId}/financial-activity, built by migration
// 419 over the SAME functions Cash Flow and Profit & Loss read. The types and
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

export async function getGenericFinancialActivity(
  opts?: { fromDate?: string; toDate?: string; farmId?: string },
): Promise<FinancialActivityResponse> {
  const farmId = opts?.farmId ?? getUserContext().farmId ?? ""
  const qs = new URLSearchParams()
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)

  const path = `/generic-company/${encodeURIComponent(farmId)}/financial-activity${qs.toString() ? `?${qs.toString()}` : ""}`
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

/** Where an event's source record lives, for Generic company pages. */
export function genericActivitySourceLink(row: FinancialActivityRow): { href: string; label: string } | null {
  switch (row.sourceType) {
    case "Receipt":
    case "CustomerPayment":         return { href: "/generic-customer-payments", label: "View payment" }
    case "SaleResidual":
    case "Sale":                    return { href: "/generic-sales", label: "View sale" }
    case "Expense":                 return { href: "/generic-expenses", label: "View expense" }
    case "Payroll":                 return { href: "/generic-payroll", label: "View payroll" }
    case "OwnerInjection":
    case "Withdrawal":
    case "OwnerContribution":
    case "OwnerDraw":               return { href: "/generic-owner-money", label: "View owner money" }
    case "LoanReceived":
    case "LoanRepayment":           return { href: "/generic-loans", label: "View loan" }
    case "CashTransfer":            return { href: "/generic-cash-transfers", label: "View transfer" }
    case "CapitalAsset":
    case "AssetDepreciation":       return { href: "/generic-assets", label: "View capital assets" }
    case "SupplierPayment":         return { href: "/generic-supplier-payments", label: "View supplier payment" }
    case "StaffPayment":            return { href: "/generic-staff-payments", label: "View staff payment" }
    default:                        return null
  }
}
