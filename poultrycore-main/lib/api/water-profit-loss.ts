// The structured water Profit & Loss and its drilldowns (migration 316).
//
// WHAT THIS IS, AND WHAT IT IS NOT
// --------------------------------
// An ANALYTICAL LAYER over spwaterreport_periodpnl, not a replacement for it.
// Revenue, direct cost, losses and NET PROFIT are that function's own figures,
// unchanged. The statement itemises them; it does not recompute them.
//
// That is deliberately unlike the poultry side, where migration 272 rebuilt the
// P&L on the classification model. Water's P&L is an older mix -- driver-return
// collections as income, cash-basis raw materials, production-batch costs,
// losses from two other tables -- and rebuilding it would have RESTATED what the
// company reports as profit. The analysis was wanted; the restatement was not.
//
// Every figure on the statement is clickable, and each drilldown reads the same
// server function the figure was built from, so the two can never disagree.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

// ----- Types -----

/**
 * Revenue, DirectCost, OperatingExpense, OtherCost and Loss are PROFIT --
 * together they reproduce net profit exactly. Financing and CapitalInvestment
 * are informational: the cash moved and the profit did not.
 */
export type WaterPlSection =
  | "Revenue"
  | "DirectCost"
  | "OperatingExpense"
  | "OtherCost"
  | "Loss"
  | "Financing"
  | "CapitalInvestment"

/** Which drilldown a line opens. */
export type WaterPlDetailKind =
  | "revenue"
  | "directcost"
  | "expense"
  | "loss"
  | "financing"
  | "capital"
  | "depreciation"

export interface WaterPlLine {
  section: WaterPlSection
  /** The key a drilldown is requested by: StorefrontSales, RawMaterials, … */
  lineKey: string
  lineLabel: string
  amount: number
  sortOrder: number
  /** True for Financing and CapitalInvestment. Never inside a profit total. */
  isInformational: boolean
  entryCount: number
}

export interface WaterPlSummary {
  startDate: string
  endDate: string

  storefrontSales: number
  /** Driver-return COLLECTIONS, not sales. */
  deliveryCollections: number
  totalRevenue: number

  /** Cash PAID for raw materials — periodpnl's basis, not accrual. */
  rawMaterials: number
  productionCost: number
  totalDirectCosts: number

  grossProfit: number
  grossMarginPercent: number

  totalOperatingExpenses: number
  /** Depreciation, loan interest and fees — below operating profit. */
  totalOtherCosts: number
  operatingProfit: number
  operatingMarginPercent: number

  productionLosses: number
  driverShortages: number
  totalLosses: number

  /** periodpnl's OWN net profit. Not recomputed. */
  netProfit: number
  netMarginPercent: number

  ownerContributions: number
  ownerDraws: number
  netOwnerFunding: number
  loansReceived: number
  loanPrincipalRepaid: number
  netBorrowing: number
  totalCapitalInvestments: number

  bagsProduced: number
  bagsSold: number
  avgProfitPerBag: number

  /**
   * Capital-asset purchases sitting INSIDE the expense pool, because the water
   * P&L counts every approved expense except raw materials. Zero is healthy.
   * Non-zero means profit is being charged for a purchase the poultry P&L would
   * exclude — the page says so rather than hiding it.
   */
  capitalInExpenses: number

  entryCount: number
}

export interface WaterProfitLossReport {
  summary: WaterPlSummary
  lines: WaterPlLine[]
}

/** One row behind a figure. Every drilldown returns this shape. */
export interface WaterPlDetailRow {
  entryDate?: string | null
  reference?: string | null
  party?: string | null
  detail?: string | null
  amount: number
}

// ----- Helpers -----

function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function jget<T>(path: string): Promise<T> {
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(explainHttpError("GET", path, res.status, t))
  }
  return (await res.json()) as T
}

// ----- Reads -----

/** Summary and statement in one call, so the two cannot disagree. */
export const getWaterProfitLoss = (opts?: { startDate?: string; endDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.startDate) qs.append("startDate", opts.startDate)
  if (opts?.endDate) qs.append("endDate", opts.endDate)
  return jget<WaterProfitLossReport>(`/Water/profit-loss?${qs.toString()}`)
}

/**
 * The rows behind one figure. Omit `lineKey` for the whole band.
 *
 * Fetched only when a line is actually opened: a period with ten thousand
 * expenses should not ship all of them to draw four cards.
 */
export const getWaterPlDetail = (opts: {
  kind: WaterPlDetailKind
  lineKey?: string | null
  startDate?: string
  endDate?: string
}) => {
  const qs = new URLSearchParams({ farmId: activeFarmId(), kind: opts.kind })
  if (opts.lineKey) qs.append("lineKey", opts.lineKey)
  if (opts.startDate) qs.append("startDate", opts.startDate)
  if (opts.endDate) qs.append("endDate", opts.endDate)
  return jget<WaterPlDetailRow[]>(`/Water/profit-loss/detail?${qs.toString()}`)
}

/**
 * Which drilldown a statement line opens.
 *
 * Mirrors the server's own mapping. A line whose section has no drilldown
 * returns null and the figure is simply not clickable — better than a click
 * that opens an empty dialog.
 */
export function waterDrilldownKindFor(
  section: WaterPlSection,
  lineKey: string,
): WaterPlDetailKind | null {
  if (section === "Revenue") return "revenue"
  if (section === "DirectCost") return "directcost"
  if (section === "Loss") return "loss"
  if (section === "Financing") return "financing"
  if (section === "CapitalInvestment") return "capital"
  // Depreciation has a register behind it; every other cost line is an expense.
  if (lineKey === "Depreciation") return "depreciation"
  if (section === "OperatingExpense" || section === "OtherCost") return "expense"
  return null
}

/** The human name of a band, used for section headings. */
export const waterPlSectionLabel = (s: WaterPlSection): string =>
  s === "Revenue" ? "Revenue"
  : s === "DirectCost" ? "Direct Costs"
  : s === "OperatingExpense" ? "Operating Expenses"
  : s === "OtherCost" ? "Other Costs"
  : s === "Loss" ? "Losses"
  : s === "Financing" ? "Financing & Owner Activity"
  : "Capital Investments"
