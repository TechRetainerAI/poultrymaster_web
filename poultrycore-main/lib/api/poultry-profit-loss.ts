// The structured Poultry Profit & Loss (migration 272).
//
//   Revenue
//   − Direct Production Costs   = Gross Profit
//   − Operating Expenses        = Operating Profit
//   − Depreciation & Financing  = Net Profit
//
// and, beside it and never inside it, Financing & Owner Activity and Capital
// Investments: money that moved and profit that did not.
//
// The report is ONE call. The drilldowns are separate calls, because nobody
// opens every line and a period with ten thousand expenses should not ship all
// of them to draw four cards.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"
import type { PoultryAssetDepreciation } from "./poultry-assets"

export type PlSection =
  | "Revenue"
  | "DirectCost"
  | "OperatingExpense"
  | "OtherCost"
  | "Financing"
  | "CapitalInvestment"

export interface PoultryProfitLossLine {
  section: PlSection
  /** The key a drilldown is requested by: Feed, Payroll, EggSales, ... */
  lineKey: string
  lineLabel: string
  amount: number
  sortOrder: number
  /** True for Financing and CapitalInvestment. Never inside a profit total. */
  isInformational: boolean
  entryCount: number
}

export interface PoultryProfitLossReport {
  startDate: string
  endDate: string

  eggSales: number
  birdSales: number
  manureSales: number
  feedSales: number
  otherRevenue: number
  totalRevenue: number

  feedCost: number
  medicationCost: number
  directLabour: number
  productionSupplies: number
  flockCost: number
  otherDirectCosts: number
  totalDirectCosts: number

  grossProfit: number
  /** Null on zero revenue: there is no percentage of nothing. */
  grossMarginPercent?: number | null

  payroll: number
  utilities: number
  transport: number
  repairsMaintenance: number
  administration: number
  marketing: number
  /** Everything operating that is not one of the six above; broken out in `lines`. */
  otherOperatingExpenses: number
  totalOperatingExpenses: number

  operatingProfit: number
  operatingMarginPercent?: number | null

  depreciation: number
  loanInterest: number
  loanFees: number
  otherFinancingCosts: number
  totalOtherCosts: number

  netProfit: number
  netMarginPercent?: number | null
  status: "Profit" | "Loss" | "Break-even"

  // Informational: cash moved, profit did not.
  ownerContributions: number
  ownerDraws: number
  netOwnerFunding: number
  loansReceived: number
  loanPrincipalRepaid: number
  netBorrowing: number
  totalCapitalInvestments: number

  feedRecognitionMethod?: string | null
  medicationRecognitionMethod?: string | null
  hasItemOverrides: boolean
  recognitionConfigured: boolean

  /** How many cost rows in the period were placed by inference, not by a stated classification. */
  legacyExpenses: number
  classifiedExpenses: number

  lines: PoultryProfitLossLine[]
}

export interface PoultryPlExpenseRow {
  expenseId: number
  expenseDate: string
  category?: string | null
  description?: string | null
  amount: number
  supplierName?: string | null
  sourceType?: string | null
  sourceLabel?: string | null
  paymentMethod?: string | null
  paymentStatus?: string | null
  costType?: string | null
  plLine?: string | null
  plLineLabel?: string | null
  poultryCapitalAssetId?: number | null
  isLegacy: boolean
}

export interface PoultryPlRevenueRow {
  saleId: number
  saleDate: string
  product?: string | null
  customerName?: string | null
  quantity: number
  unitPrice: number
  totalAmount: number
  amountPaid: number
  paymentMethod?: string | null
  revenueLine?: string | null
  revenueLabel?: string | null
}

export interface PoultryPlInventoryRow {
  expenseId: number
  expenseDate: string
  itemName?: string | null
  itemCategory?: string | null
  description?: string | null
  amount: number
  sourceType?: string | null
  sourceLabel?: string | null
  /**
   * Expense when purchased | Expense when consumed | Recorded directly.
   * The column that stops a mixed period reading as double counting.
   */
  recognition?: string | null
  sourceId?: number | null
  quantity?: number | null
  unitOfMeasure?: string | null
  /** How many purchase lots a consumption drew from. Null for a purchase. */
  costLayers?: number | null
}

export interface PoultryPlFinancingRow {
  lineKey?: string | null
  entryDate: string
  reference?: string | null
  party?: string | null
  description?: string | null
  amount: number
  entryId: number
}

export interface PoultryPlCapitalRow {
  poultryCapitalAssetCostId: number
  poultryCapitalAssetId: number
  assetNumber?: string | null
  assetName?: string | null
  categoryName?: string | null
  costDate: string
  description?: string | null
  costCategory?: string | null
  amount: number
  supplierName?: string | null
  expenseId?: number | null
  assetStatus?: string | null
  originalCost: number
  currentBookValue: number
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

function range(opts?: { startDate?: string; endDate?: string }) {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.startDate) qs.append("startDate", opts.startDate)
  if (opts?.endDate) qs.append("endDate", opts.endDate)
  return qs
}

/** Defaults to the current month server-side when no dates are given. */
export const getPoultryProfitLoss = (opts?: { startDate?: string; endDate?: string }) =>
  jget<PoultryProfitLossReport>(`/Poultry/profit-loss?${range(opts).toString()}`)

export const getPoultryPlExpenses = (opts: { startDate?: string; endDate?: string; lineKey?: string }) => {
  const qs = range(opts)
  if (opts.lineKey) qs.append("lineKey", opts.lineKey)
  return jget<PoultryPlExpenseRow[]>(`/Poultry/profit-loss/expenses?${qs.toString()}`)
}

export const getPoultryPlRevenue = (opts: { startDate?: string; endDate?: string; lineKey?: string }) => {
  const qs = range(opts)
  if (opts.lineKey) qs.append("lineKey", opts.lineKey)
  return jget<PoultryPlRevenueRow[]>(`/Poultry/profit-loss/revenue?${qs.toString()}`)
}

/** Feed or Medication, with the recognition each row came from. */
export const getPoultryPlInventory = (opts: { startDate?: string; endDate?: string; lineKey: string }) => {
  const qs = range(opts)
  qs.append("lineKey", opts.lineKey)
  return jget<PoultryPlInventoryRow[]>(`/Poultry/profit-loss/inventory?${qs.toString()}`)
}

export const getPoultryPlDepreciation = (opts?: { startDate?: string; endDate?: string }) =>
  jget<PoultryAssetDepreciation[]>(`/Poultry/profit-loss/depreciation?${range(opts).toString()}`)

/** Interest, fees, owner money and loan principal. Principal is NOT a cost. */
export const getPoultryPlFinancing = (opts: { startDate?: string; endDate?: string; lineKey?: string }) => {
  const qs = range(opts)
  if (opts.lineKey) qs.append("lineKey", opts.lineKey)
  return jget<PoultryPlFinancingRow[]>(`/Poultry/profit-loss/financing?${qs.toString()}`)
}

export const getPoultryPlCapital = (opts?: { startDate?: string; endDate?: string }) =>
  jget<PoultryPlCapitalRow[]>(`/Poultry/profit-loss/capital-investments?${range(opts).toString()}`)

/**
 * Which drilldown a line uses. Feed and Medication get the richer inventory view
 * because they are the two lines that can be fed by two different recognitions
 * at once; everything else is a plain list of the rows behind the figure.
 */
export function drilldownKindFor(section: PlSection, lineKey: string):
  "revenue" | "inventory" | "depreciation" | "financing" | "capital" | "expenses" {
  if (section === "Revenue") return "revenue"
  if (section === "CapitalInvestment") return "capital"
  if (section === "Financing") return "financing"
  if (lineKey === "Depreciation") return "depreciation"
  if (lineKey === "LoanInterest" || lineKey === "LoanFees") return "financing"
  if (lineKey === "Feed" || lineKey === "Medication") return "inventory"
  return "expenses"
}
