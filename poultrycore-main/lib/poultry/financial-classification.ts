// What KIND of cost is this, and where does it belong? (migrations 269-272)
//
// The server decides all of it. `financialCostType`, `plLine`, `plSection` and
// every label arrive resolved on the row, and nothing here re-derives them --
// this file is only the frontend's matching vocabulary: the badge wording, the
// colours, and the sentences that explain why profit and cash are allowed to
// differ.
//
// The one rule worth stating plainly, because every screen here depends on it:
//
//   MONEY PAID is not EXPENSE, and EXPENSE is not MONEY PAID.
//
// A capital asset and an inventory purchase under consumption costing both move
// cash without being this period's cost. Depreciation and consumed feed are both
// this period's cost without moving cash.

/** The five kinds. Spelled exactly as the database stores and checks them. */
export const COST_TYPES = [
  "OperatingExpense",
  "InventoryPurchase",
  "CapitalAsset",
  "NonCashExpense",
  "FinancingExpense",
] as const

export type FinancialCostType = (typeof COST_TYPES)[number]

/** Short enough for a badge. */
export function costTypeLabel(t: string | null | undefined): string {
  switch (t) {
    case "OperatingExpense": return "Operating"
    case "InventoryPurchase": return "Inventory"
    case "CapitalAsset": return "Capital"
    case "NonCashExpense": return "Non-cash"
    case "FinancingExpense": return "Financing"
    default: return "Operating"
  }
}

/**
 * What each one means, in the terms an owner thinks in. Every sentence says what
 * happens to PROFIT and what happens to CASH, because the difference between the
 * two is the only thing these badges exist to communicate.
 */
export const COST_TYPE_HELP: Record<string, string> = {
  OperatingExpense:
    "A running cost of the business. It is charged against profit for this period, whether or not it has been paid yet.",
  InventoryPurchase:
    "Stock bought for later use. Cash may have left, but the cost reaches Profit & Loss as the stock is used, not when it was bought.",
  CapitalAsset:
    "A major long-term purchase. Cash may have left, but the cost is not charged against this period's profit — it is recognised over time through depreciation.",
  NonCashExpense:
    "A cost with no payment behind it. It reduces profit and moves no money at all.",
  FinancingExpense:
    "The cost of borrowing — interest and fees. It is charged against profit; repaying the loan principal itself is not a cost.",
}

/** Badge colours, so every screen colours a cost type the same way. */
export const COST_TYPE_CLASS: Record<string, string> = {
  OperatingExpense: "border-slate-300 bg-slate-50 text-slate-700",
  InventoryPurchase: "border-sky-300 bg-sky-50 text-sky-700",
  CapitalAsset: "border-indigo-300 bg-indigo-50 text-indigo-700",
  NonCashExpense: "border-violet-300 bg-violet-50 text-violet-700",
  FinancingExpense: "border-amber-300 bg-amber-50 text-amber-700",
}

/**
 * Whether a row is charged against profit at all.
 *
 * A row that is NOT must never be shown as an operating expense merely because
 * it lives in a table called `expense` -- that is exactly the mislabelling §25
 * is about.
 */
export function isInProfit(plSection: string | null | undefined): boolean {
  return !!plSection && plSection !== "Excluded"
}

export function plSectionLabel(s: string | null | undefined): string {
  switch (s) {
    case "DirectCost": return "Direct production cost"
    case "OperatingExpense": return "Operating expense"
    case "OtherCost": return "Depreciation & financing"
    case "Excluded": return "Not charged to profit"
    default: return "—"
  }
}

// ------------------------------------------------------------- asset status ---

export function assetStatusLabel(s: string | null | undefined): string {
  switch (s) {
    case "Draft": return "Not in service"
    case "Active": return "In service"
    case "FullyDepreciated": return "Fully depreciated"
    case "Disposed": return "Disposed"
    case "Reversed": return "Reversed"
    default: return s ?? "—"
  }
}

export const ASSET_STATUS_CLASS: Record<string, string> = {
  Draft: "border-slate-300 bg-slate-50 text-slate-700",
  Active: "border-emerald-300 bg-emerald-50 text-emerald-700",
  FullyDepreciated: "border-sky-300 bg-sky-50 text-sky-700",
  Disposed: "border-amber-300 bg-amber-50 text-amber-800",
  Reversed: "border-red-300 bg-red-50 text-red-700",
}

// ------------------------------------------------------------------ wording ---

/**
 * The box §45 asks for. It is deliberately concrete: an abstract statement that
 * "profit is not cash flow" teaches nobody anything, and the four examples are
 * the four cases a farm actually meets.
 */
export const PROFIT_VS_CASH_TITLE = "Profit is not the same as cash flow"

export const PROFIT_VS_CASH_BODY =
  "Profit measures the revenue and costs that belong to the selected period. Cash Flow measures the money that actually entered and left the company. They are both right, and they can differ."

export const CASH_NOT_PROFIT_EXAMPLES = [
  "Buying stock you will use later — the cash leaves now, the cost lands as you use it",
  "Buying a building or machine — the cash leaves now, the cost spreads over its useful life",
  "Repaying loan principal — money you are giving back, not a cost",
  "Owner draws — the owner taking money out, not a business cost",
]

export const PROFIT_NOT_CASH_EXAMPLES = [
  "Depreciation — a real cost of this period that moves no money",
  "Stock bought earlier and used now — the cost lands now, the cash left months ago",
  "A bill you have received but not yet paid — the cost is yours the day it is incurred",
]

/** Shown above the Financing & Owner Activity section. §42, near enough verbatim. */
export const FINANCING_SECTION_NOTE =
  "These transactions affect company cash but are excluded from profit, because they represent owner funding, withdrawals or financing rather than operating revenue or operating expenses."

/** Shown above Capital Investments. §44. */
export const CAPITAL_SECTION_NOTE =
  "Capital investments affect cash but are not charged against profit in the period they are bought. Their cost is recognised over time through depreciation."

/**
 * Replaces the old "expenses by category keyword; anything unrecognised falls
 * under Other". §70.
 */
export const PL_METHOD_NOTE =
  "Profit & Loss uses structured revenue, expense, inventory-cost, depreciation and financing classifications. Cash movements such as owner funding, loan principal, inventory bought under consumption costing, and capital investments may affect Cash Flow without affecting profit."

export function legacyNote(legacy: number, classified: number): string | null {
  if (legacy <= 0) return null
  const total = legacy + classified
  return `${legacy} of ${total} cost record${total === 1 ? "" : "s"} in this period predate structured classification and are placed by their category. Newer records carry their classification explicitly.`
}

/** §46 — the little "Cost Recognition" note at the top of the P&L. */
export function recognitionSummaryLine(
  method: string | null | undefined,
  hasOverrides: boolean,
): string {
  const base = method === "EXPENSE_WHEN_CONSUMED" ? "Expense when consumed" : "Expense when purchased"
  return hasOverrides ? `${base} (farm default)` : base
}

export const ITEM_OVERRIDE_TOOLTIP =
  "Some inventory items use their own treatment instead of the farm default."

// ------------------------------------------------------------ depreciation ---

/**
 * The convention, in one sentence, because a farmer WILL ask why a machine
 * bought on the 28th was charged a whole month.
 */
export const DEPRECIATION_CONVENTION_NOTE =
  "Depreciation is charged for the whole month an asset goes into service and for every whole month after it. Amounts are not split part-way through a month."

export const DEPRECIATION_NONCASH_NOTE =
  "Depreciation reduces profit and the asset's book value. It moves no money: no cash account, no supplier and no payment are affected."

export const BOOK_VALUE_TOOLTIP =
  "What the asset is still worth on the books: what it cost, less the depreciation charged so far. It never falls below the residual value."

export const ORIGINAL_COST_TOOLTIP =
  "Everything capitalised into this asset — the purchase, plus any further costs added to it."
