// Pure helpers for Days of Supply (migration 337). No React, no fetch —
// covered by days-of-supply.test.ts. Every figure comes from the server; this
// only words and colours it, and never produces NaN or Infinity.

import { formatShortDate, toBusinessDate } from "@/lib/activity/completeness"

export type SupplyStatus =
  | "Negative" | "OutOfStock" | "Critical" | "Warning" | "Healthy" | "InsufficientHistory" | "NoRecentUsage"

export interface StockSupplyRow {
  poultryRawMaterialItemId: number
  itemName: string
  category: string | null
  unitOfMeasure: string | null
  purchaseUnitOfMeasure: string | null
  unitsPerPurchaseUnit: number | null
  currentQuantity: number
  minimumStockAlert: number | null
  belowReorder: boolean
  businessDate: string
  windowFrom: string
  windowTo: string
  lookbackDays: number
  windowDays: number
  consumedQty: number
  usageDays: number
  avgDailyUsage: number | null
  daysOfSupply: number | null
  estimatedStockout: string | null
  status: SupplyStatus
  severityRank: number
  criticalDays: number
  warningDays: number
  expectedDailyUsage: number | null
}

/** Statuses that ask someone to act. */
export const ACTIONABLE: SupplyStatus[] = ["Negative", "OutOfStock", "Critical", "Warning"]

export function isActionable(s: SupplyStatus): boolean {
  return ACTIONABLE.includes(s)
}

export interface StatusStyle {
  label: string
  badge: string
  tone: "bad" | "warn" | "good" | "muted"
}

export function supplyStatusStyle(s: SupplyStatus): StatusStyle {
  switch (s) {
    case "Negative": return { label: "Negative stock", badge: "bg-rose-100 text-rose-700 border-rose-200", tone: "bad" }
    case "OutOfStock": return { label: "Out of stock", badge: "bg-rose-100 text-rose-700 border-rose-200", tone: "bad" }
    case "Critical": return { label: "Critical", badge: "bg-rose-100 text-rose-700 border-rose-200", tone: "bad" }
    case "Warning": return { label: "Warning", badge: "bg-amber-100 text-amber-800 border-amber-200", tone: "warn" }
    case "Healthy": return { label: "Healthy", badge: "bg-emerald-100 text-emerald-700 border-emerald-200", tone: "good" }
    case "InsufficientHistory": return { label: "Not enough history", badge: "bg-slate-100 text-slate-600 border-slate-200", tone: "muted" }
    default: return { label: "No recent usage", badge: "bg-slate-100 text-slate-600 border-slate-200", tone: "muted" }
  }
}

function num(n: number | null | undefined, digits = 1): string {
  const v = Number(n)
  if (n == null || !Number.isFinite(v)) return "—"
  return v.toLocaleString(undefined, { maximumFractionDigits: digits })
}

export function qtyWithUnit(n: number | null | undefined, unit: string | null | undefined, digits = 1): string {
  const s = num(n, digits)
  return s === "—" ? s : `${s}${unit ? ` ${unit}` : ""}`
}

/** "2.9 days remaining", or the state in words — never a number that is not real. */
export function daysText(r: Pick<StockSupplyRow, "status" | "daysOfSupply">): string {
  switch (r.status) {
    case "Negative": return "Stock is below zero — correct the count"
    case "OutOfStock": return "Out of stock"
    case "InsufficientHistory": return "Not enough history yet"
    case "NoRecentUsage": return "No recent usage"
    default: {
      const d = Number(r.daysOfSupply)
      if (r.daysOfSupply == null || !Number.isFinite(d)) return "—"
      return `${num(d)} day${d === 1 ? "" : "s"} remaining`
    }
  }
}

/** "Estimated stock-out: Oct 2" — always labelled an estimate. */
export function stockoutText(r: Pick<StockSupplyRow, "estimatedStockout" | "status">): string | null {
  if (r.status === "Negative") return null
  const d = toBusinessDate(r.estimatedStockout)
  return d ? `Estimated stock-out: ${formatShortDate(d)}` : null
}

/** How the figure was worked out, in one sentence. */
export function explainAverage(r: StockSupplyRow): string {
  const unit = r.unitOfMeasure ?? ""
  if (r.status === "InsufficientHistory") {
    return `Stocked for only ${r.windowDays} day${r.windowDays === 1 ? "" : "s"} — at least a few days of use are needed for an estimate.`
  }
  if (r.consumedQty <= 0) {
    return `Nothing used from ${formatShortDate(r.windowFrom)} to ${formatShortDate(r.windowTo)}.`
  }
  const over = r.windowDays < r.lookbackDays ? `${r.windowDays} days (since it was first stocked)` : `the last ${r.windowDays} days`
  return `${qtyWithUnit(r.consumedQty, unit)} used over ${over}, ${formatShortDate(r.windowFrom)}–${formatShortDate(r.windowTo)}: about ${qtyWithUnit(r.avgDailyUsage, unit, 2)} a day.`
}

/** "≈ 36 bags" when the item is bought in a bigger unit than it is used in. */
export function purchaseUnitEquivalent(
  qty: number | null | undefined,
  r: Pick<StockSupplyRow, "unitsPerPurchaseUnit" | "purchaseUnitOfMeasure" | "unitOfMeasure">,
): string | null {
  const per = Number(r.unitsPerPurchaseUnit)
  const q = Number(qty)
  if (qty == null || !Number.isFinite(q) || !Number.isFinite(per) || per <= 1) return null
  if (!r.purchaseUnitOfMeasure || r.purchaseUnitOfMeasure === r.unitOfMeasure) return null
  return `≈ ${num(q / per)} ${r.purchaseUnitOfMeasure}`
}

/** Opens the Raw Materials purchase dialog with the item chosen. Never buys anything by itself. */
export function restockHref(itemId: number): string {
  return `/poultry-supply-purchases?purchase=1&itemId=${itemId}`
}

/** Sort for display: most urgent first, then fewest days, then name. */
export function sortBySeverity<T extends Pick<StockSupplyRow, "severityRank" | "daysOfSupply" | "itemName">>(rows: T[]): T[] {
  return [...rows].sort((a, b) =>
    a.severityRank - b.severityRank ||
    (a.daysOfSupply ?? Number.MAX_VALUE) - (b.daysOfSupply ?? Number.MAX_VALUE) ||
    a.itemName.localeCompare(b.itemName))
}
