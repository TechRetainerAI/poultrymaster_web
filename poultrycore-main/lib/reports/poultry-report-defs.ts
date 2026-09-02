// =============================================================================
// Advanced Poultry Reports — render definitions.
//
// One entry per report describing its summary cards, table columns and which
// filters apply. The shared <PoultryReportView> reads these so every report
// page stays tiny and consistent. Formatting goes through a small context
// (money / number / percent / date) injected by the view.
// =============================================================================

import type { PoultryReportSlug } from "@/lib/api/poultry-reports"
import { buildCashFlowAnalysis } from "@/lib/cash/cash-flow-analysis"
import { categoryLabel } from "@/lib/cash/cash-flow"

export interface FmtCtx {
  money: (n: number | null | undefined) => string
  num: (n: number | null | undefined) => string
  pct: (n: number | null | undefined) => string
  date: (s: string | null | undefined) => string
  text: (s: unknown) => string
}

export type Accent = "green" | "rose" | "indigo"

/** Backend numerics arrive as numbers or numeric strings; normalise once. */
const num = (v: unknown): number => {
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

type RawBucket = { label?: string; amount?: unknown; sharePercent?: unknown; movements?: unknown }

/** Normalise a bucket list from the API, dropping anything empty. */
const buckets = (list: unknown): Array<{ label: string; amount: number; sharePercent: number | null; movements: number }> =>
  (Array.isArray(list) ? (list as RawBucket[]) : [])
    .map((b) => ({
      // Through the shared vocabulary, so a bucket is named the same here as on
      // the Cash Flow page. Raw enums like "OwnerInjection" would otherwise
      // reach the screen verbatim.
      label: categoryLabel((b?.label ?? "").toString()),
      amount: num(b?.amount),
      sharePercent: b?.sharePercent == null ? null : num(b.sharePercent),
      movements: num(b?.movements),
    }))
    .filter((b) => b.amount > 0)

/** Bucket list -> breakdown bars. The backend already sorted and shared them. */
const bars = (list: unknown) =>
  buckets(list).map((b) => ({
    label: b.label,
    value: (_s: any, c: FmtCtx) => c.money(b.amount),
    percent: () => b.sharePercent,
  }))

/** Largest bucket as a card value: "Feed — 4,200.00", or a dash when none. */
const topBucketLabel = (list: unknown, c: FmtCtx): string => {
  const top = buckets(list)[0]
  return top ? `${top.label} — ${c.money(top.amount)}` : "—"
}

export interface CardDef {
  label: string
  value: (summary: any, ctx: FmtCtx) => string
  accent?: Accent | ((summary: any) => Accent | undefined)
  /**
   * A caveat printed under the value. For figures whose scope differs from the
   * report's date range — a balance that is as-of-now while everything beside
   * it is for the period. Without it the reader assumes one scope for the row.
   */
  note?: string
}

export interface ColumnDef {
  header: string
  align?: "left" | "right"
  /** Returns a display string for the cell. */
  cell: (row: any, ctx: FmtCtx) => string
  /** Render the value as a status badge instead of plain text. */
  badge?: boolean
}

/** A single labelled bar in a breakdown section (rendered below the table). */
export interface BreakdownBar {
  label: string
  value: (summary: any, ctx: FmtCtx) => string
  /** Share of the group total, 0–100, or null when the total is zero. */
  percent: (summary: any) => number | null
}

/** A grouped breakdown (e.g. "Revenue breakdown", "Expense breakdown"). */
export interface BreakdownGroup {
  title: string
  accent: "green" | "rose"
  total?: (summary: any, ctx: FmtCtx) => string
  /**
   * Fixed bars, or a function returning them.
   *
   * Most reports know their categories at build time (Feed, Labour, Other) and
   * pass an array. Cash Flow Detail does not — its categories are whatever the
   * farm actually spends on — so it derives the bars from the summary instead.
   */
  items: BreakdownBar[] | ((summary: any) => BreakdownBar[])
}

/** One plain-English reading of the figures, rendered above the breakdown. */
export interface AnalysisDef {
  title: string
  /** Built from the summary; `fmt` is the report's own currency formatter. */
  items: (summary: any, fmt: (n: number) => string) => Array<{
    id: string
    tone: "good" | "watch" | "neutral"
    title: string
    detail: string
  }>
}

export interface PoultryReportDef {
  slug: PoultryReportSlug
  title: string
  description: string
  filters: {
    flock?: boolean
    customer?: boolean
    supplier?: boolean
    category?: boolean
    includeClosedFlocks?: boolean
  }
  cards: CardDef[]
  columns: ColumnDef[]
  /** Optional grouped breakdown rendered below the detail table. */
  breakdown?: BreakdownGroup[]
  /** Optional narrative analysis, rendered above the breakdown. */
  analysis?: AnalysisDef
  /**
   * Render the detail rows as scorecards instead of a table — one Revenue card
   * and one Expenses & Profit card per row. Intended for the Profit & Loss
   * reports where a wide table reads better as cards.
   */
  tableAsCards?: boolean
  /**
   * When `tableAsCards` is set on a multi-row report, this column's value labels
   * each row's card pair (e.g. "Flock"). Its column is not shown inside a card.
   */
  cardRowLabel?: string
}

const profitAccent = (n: number) => (n >= 0 ? "green" : "rose") as Accent
const pctOf = (part: number, whole: number) => (whole ? (part / whole) * 100 : null)

export const POULTRY_REPORT_DEFS: Record<PoultryReportSlug, PoultryReportDef> = {
  // 1 -------------------------------------------------------------------------
  "farm-summary": {
    slug: "farm-summary",
    title: "Poultry Farm Summary Report",
    description: "High-level snapshot of poultry operations for the selected period.",
    filters: { flock: true, includeClosedFlocks: true },
    cards: [
      { label: "Total eggs produced", value: (s, c) => c.num(s.totalEggsProduced) },
      { label: "Saleable eggs", value: (s, c) => c.num(s.saleableEggs), accent: "green" },
      { label: "Broken / rejected", value: (s, c) => c.num(s.brokenRejectedEggs), accent: "rose" },
      { label: "Active flocks", value: (s, c) => c.num(s.activeFlocks) },
      { label: "Active birds", value: (s, c) => c.num(s.activeBirds) },
      { label: "Deaths", value: (s, c) => c.num(s.deaths), accent: "rose" },
      { label: "Feed consumed (kg)", value: (s, c) => c.num(s.feedConsumedKg) },
      { label: "Sales revenue", value: (s, c) => c.money(s.salesRevenue), accent: "green" },
      { label: "Expenses", value: (s, c) => c.money(s.expenses), accent: "rose" },
      { label: "Estimated profit", value: (s, c) => c.money(s.estimatedProfit), accent: (s) => profitAccent(s.estimatedProfit) },
      { label: "Cash collected", value: (s, c) => c.money(s.cashCollected) },
      { label: "Customer receivables", value: (s, c) => c.money(s.customerReceivables) },
    ],
    columns: [
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Starting birds", align: "right", cell: (r, c) => c.num(r.startingBirds) },
      { header: "Current birds", align: "right", cell: (r, c) => c.num(r.currentBirds) },
      { header: "Eggs", align: "right", cell: (r, c) => c.num(r.eggsProduced) },
      { header: "Broken/rej.", align: "right", cell: (r, c) => c.num(r.brokenRejectedEggs) },
      { header: "Prod. %", align: "right", cell: (r, c) => c.pct(r.eggProductionPercent) },
      { header: "Feed (kg)", align: "right", cell: (r, c) => c.num(r.feedConsumedKg) },
      { header: "Deaths", align: "right", cell: (r, c) => c.num(r.deaths) },
      { header: "Sales", align: "right", cell: (r, c) => c.money(r.salesRevenue) },
      { header: "Expenses", align: "right", cell: (r, c) => c.money(r.expensesAllocated) },
      { header: "Profit/Loss", align: "right", cell: (r, c) => c.money(r.estimatedProfit) },
    ],
  },

  // 2 -------------------------------------------------------------------------
  "daily-egg-production": {
    slug: "daily-egg-production",
    title: "Poultry Daily Egg Production Report",
    description: "Egg production by day and flock, including collection times and breakages.",
    filters: { flock: true },
    cards: [
      { label: "Total eggs", value: (s, c) => c.num(s.totalEggs), accent: "green" },
      { label: "Avg eggs / day", value: (s, c) => c.num(s.averageEggsPerDay) },
      { label: "Best day", value: (s, c) => `${c.date(s.bestProductionDay)} (${c.num(s.bestProductionDayEggs)})` },
      { label: "Lowest day", value: (s, c) => `${c.date(s.lowestProductionDay)} (${c.num(s.lowestProductionDayEggs)})` },
      { label: "Total broken eggs", value: (s, c) => c.num(s.totalBrokenEggs), accent: "rose" },
      { label: "Avg production %", value: (s, c) => c.pct(s.averageProductionPercent) },
    ],
    columns: [
      { header: "Date", cell: (r, c) => c.date(r.date) },
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Age (wks)", align: "right", cell: (r, c) => c.num(r.ageInWeeks) },
      { header: "1st Pick", align: "right", cell: (r, c) => c.num(r.morningEggs) },
      { header: "2nd Pick", align: "right", cell: (r, c) => c.num(r.middayEggs) },
      { header: "3rd Pick", align: "right", cell: (r, c) => c.num(r.eveningEggs) },
      { header: "4th Pick", align: "right", cell: (r, c) => c.num(r.fourthPickEggs) },
      { header: "Total eggs", align: "right", cell: (r, c) => c.num(r.totalEggs) },
      { header: "Broken", align: "right", cell: (r, c) => c.num(r.brokenEggs) },
      { header: "Saleable", align: "right", cell: (r, c) => c.num(r.saleableEggs) },
      { header: "Prod. %", align: "right", cell: (r, c) => c.pct(r.eggProductionPercent) },
      { header: "Notes", cell: (r, c) => c.text(r.notes) },
    ],
  },

  // 3 -------------------------------------------------------------------------
  "flock-production-summary": {
    slug: "flock-production-summary",
    title: "Poultry Flock Production Summary Report",
    description: "Compare production performance across flocks.",
    filters: { flock: true, includeClosedFlocks: true },
    cards: [
      { label: "Active flocks", value: (s, c) => c.num(s.activeFlocks) },
      { label: "Best producing flock", value: (s, c) => c.text(s.bestProducingFlock) },
      { label: "Lowest producing flock", value: (s, c) => c.text(s.lowestProducingFlock) },
      { label: "Total eggs", value: (s, c) => c.num(s.totalEggs), accent: "green" },
      { label: "Avg eggs / flock", value: (s, c) => c.num(s.averageEggsPerFlock) },
      { label: "Avg production %", value: (s, c) => c.pct(s.averageProductionPercent) },
    ],
    columns: [
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Age (wks)", align: "right", cell: (r, c) => c.num(r.flockAgeWeeks) },
      { header: "Birds placed", align: "right", cell: (r, c) => c.num(r.birdsPlaced) },
      { header: "Current birds", align: "right", cell: (r, c) => c.num(r.currentBirds) },
      { header: "Total eggs", align: "right", cell: (r, c) => c.num(r.totalEggs) },
      { header: "Avg daily", align: "right", cell: (r, c) => c.num(r.averageDailyEggs) },
      { header: "Peak daily", align: "right", cell: (r, c) => c.num(r.peakDailyEggs) },
      { header: "Broken", align: "right", cell: (r, c) => c.num(r.brokenEggs) },
      { header: "Prod. %", align: "right", cell: (r, c) => c.pct(r.productionPercent) },
      { header: "Feed (kg)", align: "right", cell: (r, c) => c.num(r.feedConsumedKg) },
      { header: "Deaths", align: "right", cell: (r, c) => c.num(r.deaths) },
      { header: "Status", cell: (r, c) => c.text(r.status), badge: true },
    ],
  },

  // 4 -------------------------------------------------------------------------
  "hen-day-production": {
    slug: "hen-day-production",
    title: "Poultry Hen-Day Production Report",
    description: "Production relative to live birds (eggs ÷ live birds × 100).",
    filters: { flock: true },
    cards: [
      { label: "Avg hen-day %", value: (s, c) => c.pct(s.averageHenDayPercent), accent: "green" },
      { label: "Highest hen-day %", value: (s, c) => c.pct(s.highestHenDayPercent) },
      { label: "Lowest hen-day %", value: (s, c) => c.pct(s.lowestHenDayPercent), accent: "rose" },
      { label: "Flocks below target", value: (s, c) => c.num(s.flocksBelowTarget) },
    ],
    columns: [
      { header: "Date", cell: (r, c) => c.date(r.date) },
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Live birds", align: "right", cell: (r, c) => c.num(r.liveBirds) },
      { header: "Eggs", align: "right", cell: (r, c) => c.num(r.eggsProduced) },
      { header: "Hen-day %", align: "right", cell: (r, c) => c.pct(r.henDayPercent) },
      { header: "Status", cell: (r, c) => c.text(r.status), badge: true },
    ],
  },

  // 5 -------------------------------------------------------------------------
  mortality: {
    slug: "mortality",
    title: "Poultry Mortality Report",
    description: "Bird deaths, daily and cumulative mortality percentages.",
    filters: { flock: true },
    cards: [
      { label: "Total deaths", value: (s, c) => c.num(s.totalDeaths), accent: "rose" },
      { label: "Avg daily deaths", value: (s, c) => c.num(s.averageDailyDeaths) },
      { label: "Highest mortality day", value: (s, c) => `${c.date(s.highestMortalityDay)} (${c.num(s.highestMortalityDayDeaths)})` },
      { label: "Cumulative mortality %", value: (s, c) => c.pct(s.cumulativeMortalityPercent), accent: "rose" },
      { label: "Flocks with high mortality", value: (s, c) => c.num(s.flocksWithHighMortality) },
    ],
    columns: [
      { header: "Date", cell: (r, c) => c.date(r.date) },
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Opening birds", align: "right", cell: (r, c) => c.num(r.openingBirds) },
      { header: "Deaths", align: "right", cell: (r, c) => c.num(r.deaths) },
      { header: "Closing birds", align: "right", cell: (r, c) => c.num(r.closingBirds) },
      { header: "Daily mort. %", align: "right", cell: (r, c) => c.pct(r.dailyMortalityPercent) },
      { header: "Cumulative %", align: "right", cell: (r, c) => c.pct(r.cumulativeMortalityPercent) },
      { header: "Notes", cell: (r, c) => c.text(r.notes) },
    ],
  },

  // 6 -------------------------------------------------------------------------
  "birds-on-hand": {
    slug: "birds-on-hand",
    title: "Poultry Birds on Hand Report",
    description: "Current bird count and reconciliation by flock.",
    filters: { flock: true, includeClosedFlocks: true },
    cards: [
      { label: "Total birds placed", value: (s, c) => c.num(s.totalBirdsPlaced) },
      { label: "Current live birds", value: (s, c) => c.num(s.currentLiveBirds), accent: "green" },
      { label: "Total deaths", value: (s, c) => c.num(s.totalDeaths), accent: "rose" },
      { label: "Total culls", value: (s, c) => c.num(s.totalCulls) },
      { label: "Sold / transferred out", value: (s, c) => c.num(s.totalBirdsSoldTransferred) },
      { label: "Bird variance", value: (s, c) => c.num(s.birdVariance) },
    ],
    columns: [
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Placed", align: "right", cell: (r, c) => c.num(r.birdsPlaced) },
      { header: "Transfers in", align: "right", cell: (r, c) => c.num(r.transfersIn) },
      { header: "Deaths", align: "right", cell: (r, c) => c.num(r.deaths) },
      { header: "Culls", align: "right", cell: (r, c) => c.num(r.culls) },
      { header: "Sold", align: "right", cell: (r, c) => c.num(r.birdsSold) },
      { header: "Transfers out", align: "right", cell: (r, c) => c.num(r.transfersOut) },
      { header: "Expected", align: "right", cell: (r, c) => c.num(r.expectedBirdsOnHand) },
      { header: "Recorded", align: "right", cell: (r, c) => c.num(r.currentRecordedBirds) },
      { header: "Variance", align: "right", cell: (r, c) => c.num(r.variance) },
      { header: "Status", cell: (r, c) => c.text(r.status), badge: true },
    ],
  },

  // 7 -------------------------------------------------------------------------
  "feed-usage": {
    slug: "feed-usage",
    title: "Poultry Feed Usage Report",
    description: "Feed consumed by flock, date and feed type.",
    filters: { flock: true },
    cards: [
      { label: "Total feed consumed (kg)", value: (s, c) => c.num(s.totalFeedConsumedKg) },
      { label: "Avg feed / day (kg)", value: (s, c) => c.num(s.averageFeedPerDayKg) },
      { label: "Avg feed / bird (kg)", value: (s, c) => c.num(s.averageFeedPerBirdKg) },
      { label: "Highest feed flock", value: (s, c) => c.text(s.highestFeedConsumingFlock) },
      { label: "Feed wastage (kg)", value: (s, c) => c.num(s.feedWastageKg) },
    ],
    columns: [
      { header: "Date", cell: (r, c) => c.date(r.date) },
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Feed type", cell: (r, c) => c.text(r.feedType) },
      { header: "Issued (kg)", align: "right", cell: (r, c) => c.num(r.feedIssuedKg) },
      { header: "Returned (kg)", align: "right", cell: (r, c) => c.num(r.feedReturnedKg) },
      { header: "Consumed (kg)", align: "right", cell: (r, c) => c.num(r.feedConsumedKg) },
      { header: "Live birds", align: "right", cell: (r, c) => c.num(r.liveBirds) },
      { header: "Feed/bird", align: "right", cell: (r, c) => c.num(r.feedPerBirdKg) },
      { header: "Eggs", align: "right", cell: (r, c) => c.num(r.eggsProduced) },
      { header: "Feed/egg", align: "right", cell: (r, c) => c.num(r.feedPerEggKg) },
    ],
  },

  // 8 -------------------------------------------------------------------------
  "feed-inventory-balance": {
    slug: "feed-inventory-balance",
    title: "Poultry Feed Inventory Balance Report",
    description: "Current feed stock position and estimated days remaining.",
    filters: {},
    cards: [
      { label: "Total feed stock (kg)", value: (s, c) => c.num(s.totalFeedStockKg) },
      { label: "Feed stock value", value: (s, c) => c.money(s.totalFeedStockValue) },
      { label: "Low-stock items", value: (s, c) => c.num(s.lowStockItems) },
      { label: "Out-of-stock items", value: (s, c) => c.num(s.outOfStockItems), accent: "rose" },
      { label: "Est. days remaining", value: (s, c) => c.num(s.estimatedDaysRemaining) },
    ],
    columns: [
      { header: "Feed item", cell: (r, c) => c.text(r.feedItem) },
      { header: "Category", cell: (r, c) => c.text(r.category) },
      { header: "Issued (kg)", align: "right", cell: (r, c) => c.num(r.issuedKg) },
      { header: "Current (kg)", align: "right", cell: (r, c) => c.num(r.currentStockKg) },
      { header: "Unit cost", align: "right", cell: (r, c) => c.money(r.unitCost) },
      { header: "Stock value", align: "right", cell: (r, c) => c.money(r.stockValue) },
      { header: "Days left", align: "right", cell: (r, c) => c.num(r.estimatedDaysRemaining) },
      { header: "Status", cell: (r, c) => c.text(r.status), badge: true },
    ],
  },

  // 9 -------------------------------------------------------------------------
  "feed-cost-per-egg": {
    slug: "feed-cost-per-egg",
    title: "Poultry Feed Cost Per Egg Report",
    description: "How feed cost relates to egg production, by flock.",
    filters: { flock: true, includeClosedFlocks: true },
    cards: [
      { label: "Total feed cost", value: (s, c) => c.money(s.totalFeedCost), accent: "rose" },
      { label: "Total eggs", value: (s, c) => c.num(s.totalEggs) },
      { label: "Avg feed cost / egg", value: (s, c) => c.money(s.averageFeedCostPerEgg) },
      { label: "Avg feed cost / crate", value: (s, c) => c.money(s.averageFeedCostPerCrate) },
      { label: "Most expensive flock", value: (s, c) => c.text(s.mostExpensiveFlock) },
    ],
    columns: [
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Feed (kg)", align: "right", cell: (r, c) => c.num(r.feedConsumedKg) },
      { header: "Avg unit cost", align: "right", cell: (r, c) => c.money(r.averageFeedUnitCost) },
      { header: "Total feed cost", align: "right", cell: (r, c) => c.money(r.totalFeedCost) },
      { header: "Eggs", align: "right", cell: (r, c) => c.num(r.eggsProduced) },
      { header: "Cost / egg", align: "right", cell: (r, c) => c.money(r.feedCostPerEgg) },
      { header: "Cost / crate", align: "right", cell: (r, c) => c.money(r.feedCostPerCrate) },
      { header: "Prod. %", align: "right", cell: (r, c) => c.pct(r.productionPercent) },
      { header: "Status", cell: (r, c) => c.text(r.status), badge: true },
    ],
  },

  // 10 ------------------------------------------------------------------------
  "egg-stock-balance": {
    slug: "egg-stock-balance",
    title: "Poultry Egg Stock Balance Report",
    description: "Egg inventory on hand, in eggs and crate equivalents.",
    filters: {},
    cards: [
      { label: "Total eggs in stock", value: (s, c) => c.num(s.totalEggsInStock), accent: "green" },
      { label: "Total crates", value: (s, c) => c.num(s.totalCrates) },
      { label: "Loose eggs", value: (s, c) => c.num(s.looseEggs) },
      { label: "Saleable eggs", value: (s, c) => c.num(s.saleableEggs) },
      { label: "Broken / rejected", value: (s, c) => c.num(s.brokenRejectedEggs), accent: "rose" },
      { label: "Stock value", value: (s, c) => c.money(s.stockValue) },
    ],
    columns: [
      { header: "Product / grade", cell: (r, c) => c.text(r.productGrade) },
      { header: "Opening", align: "right", cell: (r, c) => c.num(r.openingStock) },
      { header: "Produced", align: "right", cell: (r, c) => c.num(r.productionAdded) },
      { header: "Sold", align: "right", cell: (r, c) => c.num(r.salesRemoved) },
      { header: "Losses/adj.", align: "right", cell: (r, c) => c.num(r.lossesAdjustments) },
      { header: "Current (eggs)", align: "right", cell: (r, c) => c.num(r.currentStockEggs) },
      { header: "Crates", align: "right", cell: (r, c) => c.num(r.currentStockCrates) },
      { header: "Loose", align: "right", cell: (r, c) => c.num(r.looseEggs) },
      { header: "Status", cell: (r, c) => c.text(r.status), badge: true },
    ],
  },

  // 11 ------------------------------------------------------------------------
  "egg-sales": {
    slug: "egg-sales",
    title: "Poultry Egg Sales Report",
    description: "Egg sales by date, customer and product. Paid/unpaid cover sales made in the selected period — for all-time receivables use the Customer Balance report.",
    filters: { flock: true, customer: true },
    cards: [
      { label: "Total sales revenue", value: (s, c) => c.money(s.totalSalesRevenue), accent: "green" },
      { label: "Total eggs sold", value: (s, c) => c.num(s.totalEggsSold) },
      { label: "Paid in period", value: (s, c) => c.money(s.totalPaid), accent: "green" },
      { label: "Unpaid in period", value: (s, c) => c.money(s.totalUnpaid), accent: "rose" },
      { label: "Top customer", value: (s, c) => c.text(s.topCustomer) },
    ],
    columns: [
      { header: "Date", cell: (r, c) => c.date(r.date) },
      { header: "Sale #", align: "right", cell: (r, c) => c.num(r.saleId) },
      { header: "Customer", cell: (r, c) => c.text(r.customer) },
      { header: "Product", cell: (r, c) => c.text(r.productGrade) },
      { header: "Qty", align: "right", cell: (r, c) => c.num(r.quantitySold) },
      { header: "Unit price", align: "right", cell: (r, c) => c.money(r.unitPrice) },
      { header: "Total", align: "right", cell: (r, c) => c.money(r.totalAmount) },
      { header: "Paid", align: "right", cell: (r, c) => c.money(r.amountPaid) },
      { header: "Balance", align: "right", cell: (r, c) => c.money(r.balance) },
      { header: "Status", cell: (r, c) => c.text(r.paymentStatus), badge: true },
    ],
  },

  // 12 ------------------------------------------------------------------------
  "customer-balance": {
    slug: "customer-balance",
    title: "Poultry Customer Balance Report",
    description: "Customer receivables from poultry sales — all-time outstanding up to the end date, not just the selected period.",
    filters: { customer: true },
    cards: [
      { label: "Customers with balance", value: (s, c) => c.num(s.customersWithBalance) },
      { label: "Total receivables (all time)", value: (s, c) => c.money(s.totalReceivables), accent: "rose" },
      { label: "Overdue amount", value: (s, c) => c.money(s.overdueAmount) },
      { label: "Highest owing customer", value: (s, c) => c.text(s.highestOwingCustomer) },
    ],
    columns: [
      { header: "Customer", cell: (r, c) => c.text(r.customer) },
      { header: "Phone", cell: (r, c) => c.text(r.contactPhone) },
      { header: "Total sales", align: "right", cell: (r, c) => c.money(r.totalSales) },
      { header: "Total paid", align: "right", cell: (r, c) => c.money(r.totalPaid) },
      { header: "Balance", align: "right", cell: (r, c) => c.money(r.currentBalance) },
      // Real figures since migration 223 — both were hardcoded to null before,
      // because sales carried no customer link and no notion of due date.
      { header: "Overdue", align: "right", cell: (r, c) => c.money(r.overdueAmount) },
      { header: "Open sales", align: "right", cell: (r, c) => c.num(r.openSaleCount) },
      { header: "Last sale", cell: (r, c) => c.date(r.lastSaleDate) },
      { header: "Last payment", cell: (r, c) => c.date(r.lastPaymentDate) },
      { header: "Status", cell: (r, c) => c.text(r.status), badge: true },
    ],
  },

  // 12b -----------------------------------------------------------------------
  "supplier-balance": {
    slug: "supplier-balance",
    title: "Poultry Supplier Balance Report",
    description:
      "What the farm owes suppliers on raw-material purchases and flock batches — all-time outstanding up to the end date, not just the selected period.",
    filters: { supplier: true },
    cards: [
      { label: "Suppliers owed", value: (s, c) => c.num(s.suppliersWithBalance) },
      { label: "Total payables (all time)", value: (s, c) => c.money(s.totalPayables), accent: "rose" },
      { label: "Overdue amount", value: (s, c) => c.money(s.overdueAmount) },
      { label: "Largest payable", value: (s, c) => c.text(s.highestOwedSupplier) },
    ],
    columns: [
      { header: "Supplier", cell: (r, c) => c.text(r.supplier) },
      { header: "Phone", cell: (r, c) => c.text(r.contactPhone) },
      { header: "Total purchases", align: "right", cell: (r, c) => c.money(r.totalPurchases) },
      { header: "Total paid", align: "right", cell: (r, c) => c.money(r.totalPaid) },
      { header: "Balance", align: "right", cell: (r, c) => c.money(r.currentBalance) },
      { header: "Overdue", align: "right", cell: (r, c) => c.money(r.overdueAmount) },
      { header: "Open purchases", align: "right", cell: (r, c) => c.num(r.openPurchaseCount) },
      { header: "Oldest purchase", cell: (r, c) => c.date(r.oldestPurchaseDate) },
      { header: "Last payment", cell: (r, c) => c.date(r.lastPaymentDate) },
      { header: "Status", cell: (r, c) => c.text(r.status), badge: true },
    ],
  },

  // 13 ------------------------------------------------------------------------
  "expense-summary": {
    slug: "expense-summary",
    title: "Poultry Expense Summary Report",
    description: "Poultry farm expenses by category and flock.",
    filters: { flock: true, supplier: true, category: true },
    cards: [
      { label: "Total expenses", value: (s, c) => c.money(s.totalExpenses), accent: "rose" },
      { label: "Paid expenses", value: (s, c) => c.money(s.paidExpenses) },
      { label: "Unpaid expenses", value: (s, c) => c.money(s.unpaidExpenses) },
      { label: "Largest category", value: (s, c) => c.text(s.largestExpenseCategory) },
      { label: "Avg daily expense", value: (s, c) => c.money(s.averageDailyExpense) },
    ],
    columns: [
      { header: "Date", cell: (r, c) => c.date(r.date) },
      { header: "Ref #", align: "right", cell: (r, c) => c.num(r.expenseId) },
      { header: "Category", cell: (r, c) => c.text(r.category) },
      { header: "Description", cell: (r, c) => c.text(r.description) },
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Supplier", cell: (r, c) => c.text(r.supplier) },
      { header: "Amount", align: "right", cell: (r, c) => c.money(r.amount) },
      { header: "Method", cell: (r, c) => c.text(r.paymentMethod) },
      // Where the expense came from — raw-material purchase, flock batch, driver
      // return, or blank when it was entered by hand. Replaces the old Status
      // column, which was the constant "Paid" on every row.
      { header: "Source", cell: (r, c) => c.text(r.sourceType) },
    ],
  },

  // 14 ------------------------------------------------------------------------
  "cash-movement": {
    slug: "cash-movement",
    title: "Poultry Cash Movement Report",
    description: "Cash inflows and outflows for poultry operations.",
    filters: {},
    cards: [
      // Order is the arithmetic, left to right: opening + in - out = net, for
      // the selected period. Cash at hand sits last because it is the only
      // as-of-now figure in the row and does not belong inside that sum.
      { label: "Opening cash balance", value: (s, c) => c.money(s.openingCashBalance) },
      { label: "Total inflows", value: (s, c) => c.money(s.totalInflows), accent: "green" },
      { label: "Total outflows", value: (s, c) => c.money(s.totalOutflows), accent: "rose" },
      { label: "Net cash movement", value: (s, c) => c.money(s.netCashMovement), accent: (s) => profitAccent(s.netCashMovement) },
      // Was "Ending balance", which read as "cash at the end of the range". It
      // never was: 231 derives openingbalance as cashathand - (in - out)
      // (231_PoultryCashFlowRows.postgres.sql:284), so opening + in - out
      // collapses back to cash at hand exactly. All time, and it does not move
      // when the date filter does — hence the note, and the position.
      {
        label: "Cash at hand",
        value: (s, c) => c.money(s.endingBalance),
        note: "All time — not affected by the date filter",
      },
    ],
    columns: [
      { header: "Date", cell: (r, c) => c.date(r.date) },
      { header: "Account", cell: (r, c) => c.text(r.cashAccount) },
      { header: "Source", cell: (r, c) => c.text(r.sourceType) },
      { header: "Reference", cell: (r, c) => c.text(r.reference) },
      { header: "Description", cell: (r, c) => c.text(r.description) },
      { header: "Inflow", align: "right", cell: (r, c) => c.money(r.inflow) },
      { header: "Outflow", align: "right", cell: (r, c) => c.money(r.outflow) },
      { header: "Balance", align: "right", cell: (r, c) => c.money(r.balanceAfter) },
    ],
  },

  // 14b -----------------------------------------------------------------------
  // Cash Movement says WHAT moved. This says what it was FOR — the ledger alone
  // cannot, since every expense in the company lands as sourcetype 'Expense'.
  // Migration 233 supplies the category; the analysis is the point of the page.
  "cash-flow-detail": {
    slug: "cash-flow-detail",
    title: "Poultry Cash Flow Detail",
    description: "Where cash came from, what it went on, and how the period compares.",
    filters: {},
    cards: [
      { label: "Money in", value: (s, c) => c.money(s.moneyIn), accent: "green" },
      { label: "Money out", value: (s, c) => c.money(s.moneyOut), accent: "rose" },
      { label: "Net cash flow", value: (s, c) => c.money(s.netCashFlow), accent: (s) => profitAccent(s.netCashFlow) },
      { label: "Biggest cost", value: (s, c) => topBucketLabel(s.moneyOutByCategory, c) },
      // The only as-of-now figure in the row, so it sits last and says so —
      // the same treatment Cash Movement's card got.
      {
        label: "Cash at hand",
        value: (s, c) => c.money(s.cashAtHand),
        note: "All time — not affected by the date filter",
      },
    ],
    analysis: {
      title: "Analysis",
      // Pure, unit-tested, and shared with nothing else yet — the sentences make
      // claims about somebody's money, so they are tested rather than trusted.
      items: (s, fmt) => buildCashFlowAnalysis({
        moneyIn: num(s.moneyIn), moneyOut: num(s.moneyOut), netCashFlow: num(s.netCashFlow),
        cashAtHand: num(s.cashAtHand),
        offLedgerIn: num(s.offLedgerIn), offLedgerOut: num(s.offLedgerOut),
        transferVolume: num(s.transferVolume),
        movementCount: num(s.movementCount), daysInPeriod: num(s.daysInPeriod),
        previousMoneyIn: num(s.previousMoneyIn), previousMoneyOut: num(s.previousMoneyOut),
        previousNetCashFlow: num(s.previousNetCashFlow),
        moneyInByCategory: buckets(s.moneyInByCategory),
        moneyOutByCategory: buckets(s.moneyOutByCategory),
      }, fmt),
    },
    breakdown: [
      {
        title: "Money in by source",
        accent: "green",
        total: (s, c) => c.money(s.moneyIn),
        items: (s) => bars(s.moneyInByCategory),
      },
      {
        title: "Money out by category",
        accent: "rose",
        total: (s, c) => c.money(s.moneyOut),
        items: (s) => bars(s.moneyOutByCategory),
      },
    ],
    columns: [
      { header: "Date", cell: (r, c) => c.date(r.date) },
      { header: "Category", cell: (r, c) => c.text(categoryLabel(r.category)) },
      { header: "Account", cell: (r, c) => c.text(r.cashAccount) },
      { header: "Reference", cell: (r, c) => c.text(r.reference) },
      { header: "Description", cell: (r, c) => c.text(r.description) },
      { header: "In", align: "right", cell: (r, c) => (r.inflow ? c.money(r.inflow) : "—") },
      { header: "Out", align: "right", cell: (r, c) => (r.outflow ? c.money(r.outflow) : "—") },
      // Company-wide cash after each row, not the account's own balance — the
      // rows span several accounts plus money that reached none.
      { header: "Running cash", align: "right", cell: (r, c) => c.money(r.runningBalance) },
    ],
  },

  // 15 ------------------------------------------------------------------------
  "profit-loss-by-flock": {
    slug: "profit-loss-by-flock",
    title: "Poultry Profit and Loss by Flock Report",
    description: "Revenue, expenses and profit attributed to each flock.",
    filters: { flock: true, includeClosedFlocks: true },
    // Each flock shows a Revenue card + an Expenses & Profit card, under its name.
    tableAsCards: true,
    cardRowLabel: "Flock",
    cards: [
      { label: "Total revenue", value: (s, c) => c.money(s.totalRevenue), accent: "green" },
      { label: "Total expenses", value: (s, c) => c.money(s.totalExpenses), accent: "rose" },
      { label: "Net profit", value: (s, c) => c.money(s.netProfit), accent: (s) => profitAccent(s.netProfit) },
      { label: "Most profitable flock", value: (s, c) => c.text(s.mostProfitableFlock) },
      { label: "Least profitable flock", value: (s, c) => c.text(s.leastProfitableFlock) },
    ],
    columns: [
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Egg revenue", align: "right", cell: (r, c) => c.money(r.eggRevenue) },
      { header: "Feed cost", align: "right", cell: (r, c) => c.money(r.feedCost) },
      { header: "Medicine", align: "right", cell: (r, c) => c.money(r.medicineVaccineCost) },
      { header: "Labour", align: "right", cell: (r, c) => c.money(r.laborCost) },
      { header: "Other exp.", align: "right", cell: (r, c) => c.money(r.otherExpenses) },
      { header: "Total revenue", align: "right", cell: (r, c) => c.money(r.totalRevenue) },
      { header: "Total cost", align: "right", cell: (r, c) => c.money(r.totalCost) },
      { header: "Net profit", align: "right", cell: (r, c) => c.money(r.netProfit) },
      { header: "Profit/egg", align: "right", cell: (r, c) => c.money(r.profitPerEgg) },
      { header: "Status", cell: (r, c) => c.text(r.status), badge: true },
    ],
    breakdown: [
      {
        title: "Revenue breakdown",
        accent: "green",
        total: (s, c) => c.money(s.totalRevenue),
        items: [
          { label: "Egg sales", value: (s, c) => c.money(s.eggRevenue), percent: (s) => pctOf(s.eggRevenue, s.totalRevenue) },
          { label: "Bird sales", value: (s, c) => c.money(s.birdSalesRevenue), percent: (s) => pctOf(s.birdSalesRevenue, s.totalRevenue) },
          { label: "Other revenue", value: (s, c) => c.money(s.otherRevenue), percent: (s) => pctOf(s.otherRevenue, s.totalRevenue) },
        ],
      },
      {
        title: "Expense breakdown",
        accent: "rose",
        total: (s, c) => c.money(s.totalExpenses),
        items: [
          { label: "Feed", value: (s, c) => c.money(s.feedCost), percent: (s) => pctOf(s.feedCost, s.totalExpenses) },
          { label: "Medicine & vaccines", value: (s, c) => c.money(s.medicineVaccineCost), percent: (s) => pctOf(s.medicineVaccineCost, s.totalExpenses) },
          { label: "Labour", value: (s, c) => c.money(s.laborCost), percent: (s) => pctOf(s.laborCost, s.totalExpenses) },
          { label: "Other expenses", value: (s, c) => c.money(s.otherExpenses), percent: (s) => pctOf(s.otherExpenses, s.totalExpenses) },
        ],
      },
    ],
  },

  // 15b -----------------------------------------------------------------------
  "profit-loss": {
    slug: "profit-loss",
    title: "Poultry Profit and Loss Report",
    description: "Company-wide revenue, expenses and net profit for the selected period.",
    filters: {},
    // Company-wide P&L is a single row — show its figures as scorecards.
    tableAsCards: true,
    cards: [
      { label: "Total revenue", value: (s, c) => c.money(s.totalRevenue), accent: "green" },
      { label: "Total expenses", value: (s, c) => c.money(s.totalExpenses), accent: "rose" },
      { label: "Net profit", value: (s, c) => c.money(s.netProfit), accent: (s) => profitAccent(s.netProfit) },
    ],
    columns: [
      { header: "Egg revenue", align: "right", cell: (r, c) => c.money(r.eggRevenue) },
      { header: "Bird sales", align: "right", cell: (r, c) => c.money(r.birdSalesRevenue) },
      { header: "Other rev.", align: "right", cell: (r, c) => c.money(r.otherRevenue) },
      { header: "Total revenue", align: "right", cell: (r, c) => c.money(r.totalRevenue) },
      { header: "Feed cost", align: "right", cell: (r, c) => c.money(r.feedCost) },
      { header: "Medicine", align: "right", cell: (r, c) => c.money(r.medicineVaccineCost) },
      { header: "Labour", align: "right", cell: (r, c) => c.money(r.laborCost) },
      { header: "Other exp.", align: "right", cell: (r, c) => c.money(r.otherExpenses) },
      { header: "Total cost", align: "right", cell: (r, c) => c.money(r.totalCost) },
      { header: "Net profit", align: "right", cell: (r, c) => c.money(r.netProfit) },
      { header: "Status", cell: (r, c) => c.text(r.status), badge: true },
    ],
    breakdown: [
      {
        title: "Revenue breakdown",
        accent: "green",
        total: (s, c) => c.money(s.totalRevenue),
        items: [
          { label: "Egg sales", value: (s, c) => c.money(s.eggRevenue), percent: (s) => pctOf(s.eggRevenue, s.totalRevenue) },
          { label: "Bird sales", value: (s, c) => c.money(s.birdSalesRevenue), percent: (s) => pctOf(s.birdSalesRevenue, s.totalRevenue) },
          { label: "Other revenue", value: (s, c) => c.money(s.otherRevenue), percent: (s) => pctOf(s.otherRevenue, s.totalRevenue) },
        ],
      },
      {
        title: "Expense breakdown",
        accent: "rose",
        total: (s, c) => c.money(s.totalExpenses),
        items: [
          { label: "Feed", value: (s, c) => c.money(s.feedCost), percent: (s) => pctOf(s.feedCost, s.totalExpenses) },
          { label: "Medicine & vaccines", value: (s, c) => c.money(s.medicineVaccineCost), percent: (s) => pctOf(s.medicineVaccineCost, s.totalExpenses) },
          { label: "Labour", value: (s, c) => c.money(s.laborCost), percent: (s) => pctOf(s.laborCost, s.totalExpenses) },
          { label: "Other expenses", value: (s, c) => c.money(s.otherExpenses), percent: (s) => pctOf(s.otherExpenses, s.totalExpenses) },
        ],
      },
    ],
  },

  // 16 ------------------------------------------------------------------------
  "cost-per-egg": {
    slug: "cost-per-egg",
    title: "Poultry Cost Per Egg Report",
    description: "Total allocated cost per egg, by flock.",
    filters: { flock: true, includeClosedFlocks: true },
    cards: [
      { label: "Total eggs produced", value: (s, c) => c.num(s.totalEggsProduced) },
      { label: "Total direct costs", value: (s, c) => c.money(s.totalDirectCosts) },
      { label: "Total allocated costs", value: (s, c) => c.money(s.totalAllocatedCosts), accent: "rose" },
      { label: "Avg cost / egg", value: (s, c) => c.money(s.averageCostPerEgg) },
      { label: "Avg cost / crate", value: (s, c) => c.money(s.averageCostPerCrate) },
    ],
    columns: [
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Eggs", align: "right", cell: (r, c) => c.num(r.eggsProduced) },
      { header: "Feed cost", align: "right", cell: (r, c) => c.money(r.feedCost) },
      { header: "Medicine", align: "right", cell: (r, c) => c.money(r.medicineVaccineCost) },
      { header: "Labour", align: "right", cell: (r, c) => c.money(r.laborCost) },
      { header: "Other", align: "right", cell: (r, c) => c.money(r.otherAllocatedCost) },
      { header: "Total cost", align: "right", cell: (r, c) => c.money(r.totalCost) },
      { header: "Cost / egg", align: "right", cell: (r, c) => c.money(r.costPerEgg) },
      { header: "Cost / crate", align: "right", cell: (r, c) => c.money(r.costPerCrate) },
      { header: "Margin / egg", align: "right", cell: (r, c) => c.money(r.marginPerEgg) },
    ],
  },

  // 17 ------------------------------------------------------------------------
  "vaccination-schedule": {
    slug: "vaccination-schedule",
    title: "Poultry Vaccination Schedule Report",
    description: "Recorded and upcoming vaccinations.",
    filters: { flock: true },
    cards: [
      { label: "Upcoming", value: (s, c) => c.num(s.upcoming) },
      { label: "Due today", value: (s, c) => c.num(s.dueToday) },
      { label: "Overdue / missed", value: (s, c) => c.num(s.overdueMissed), accent: "rose" },
      { label: "Completed", value: (s, c) => c.num(s.completed), accent: "green" },
    ],
    columns: [
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Vaccine", cell: (r, c) => c.text(r.vaccine) },
      { header: "Disease", cell: (r, c) => c.text(r.disease) },
      { header: "Scheduled", cell: (r, c) => c.date(r.scheduledDate) },
      { header: "Actual", cell: (r, c) => c.date(r.actualDate) },
      { header: "Administered by", cell: (r, c) => c.text(r.administeredBy) },
      { header: "Status", cell: (r, c) => c.text(r.status), badge: true },
      { header: "Notes", cell: (r, c) => c.text(r.notes) },
    ],
  },

  // 18 ------------------------------------------------------------------------
  "medicine-usage": {
    slug: "medicine-usage",
    title: "Poultry Medicine Usage Report",
    description: "Medicines used by flock and date.",
    filters: { flock: true },
    cards: [
      { label: "Total medicine cost", value: (s, c) => c.money(s.totalMedicineCost) },
      { label: "Number of treatments", value: (s, c) => c.num(s.numberOfTreatments) },
      { label: "Most used medicine", value: (s, c) => c.text(s.mostUsedMedicine) },
      { label: "Flocks under treatment", value: (s, c) => c.num(s.flocksUnderTreatment) },
      { label: "Expiring medicine", value: (s, c) => c.num(s.expiringMedicine) },
    ],
    columns: [
      { header: "Date", cell: (r, c) => c.date(r.date) },
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Medicine", cell: (r, c) => c.text(r.medicine) },
      { header: "Dosage", cell: (r, c) => c.text(r.dosage) },
      { header: "Qty used", align: "right", cell: (r, c) => c.num(r.quantityUsed) },
      { header: "Total cost", align: "right", cell: (r, c) => c.money(r.totalCost) },
      { header: "Administered by", cell: (r, c) => c.text(r.administeredBy) },
      { header: "Notes", cell: (r, c) => c.text(r.notes) },
    ],
  },

  // 19 ------------------------------------------------------------------------
  "missing-daily-records": {
    slug: "missing-daily-records",
    title: "Poultry Missing Daily Records Report",
    description: "Active flocks missing required daily records.",
    filters: { flock: true },
    cards: [
      { label: "Active flocks", value: (s, c) => c.num(s.activeFlocks) },
      { label: "Missing production records", value: (s, c) => c.num(s.missingProductionRecords), accent: "rose" },
      { label: "Missing feed records", value: (s, c) => c.num(s.missingFeedRecords), accent: "rose" },
      { label: "Missing health records", value: (s, c) => c.num(s.missingHealthRecords) },
      { label: "Complete flock-days", value: (s, c) => c.num(s.completeFlockDays), accent: "green" },
    ],
    columns: [
      { header: "Date", cell: (r, c) => c.date(r.date) },
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Production?", cell: (r, c) => (r.hasProductionRecord ? "Yes" : "No") },
      { header: "Feed?", cell: (r, c) => (r.hasFeedUsage ? "Yes" : "No") },
      { header: "Bird update?", cell: (r, c) => (r.hasMortalityUpdate ? "Yes" : "No") },
      { header: "Health note?", cell: (r, c) => (r.hasHealthNote ? "Yes" : "No") },
      { header: "Missing", cell: (r, c) => c.text(r.missingItems) },
      { header: "Status", cell: (r, c) => c.text(r.status), badge: true },
    ],
  },

  // 20 ------------------------------------------------------------------------
  "end-of-flock": {
    slug: "end-of-flock",
    title: "Poultry End-of-Flock Report",
    description: "Final lifecycle performance for each flock.",
    filters: { flock: true, includeClosedFlocks: true },
    cards: [
      { label: "Birds placed", value: (s, c) => c.num(s.birdsPlaced) },
      { label: "Birds remaining", value: (s, c) => c.num(s.birdsRemaining) },
      { label: "Total eggs", value: (s, c) => c.num(s.totalEggs), accent: "green" },
      { label: "Total feed (kg)", value: (s, c) => c.num(s.totalFeedConsumedKg) },
      { label: "Total revenue", value: (s, c) => c.money(s.totalRevenue), accent: "green" },
      { label: "Total cost", value: (s, c) => c.money(s.totalCost), accent: "rose" },
      { label: "Net profit", value: (s, c) => c.money(s.netProfit), accent: (s) => profitAccent(s.netProfit) },
      { label: "Mortality %", value: (s, c) => c.pct(s.mortalityPercent), accent: "rose" },
      { label: "Feed cost / egg", value: (s, c) => c.money(s.feedCostPerEgg) },
      { label: "Profit / bird", value: (s, c) => c.money(s.profitPerBird) },
    ],
    columns: [
      { header: "Flock", cell: (r, c) => c.text(r.flockName) },
      { header: "Placed", cell: (r, c) => c.date(r.placementDate) },
      { header: "Age (wks)", align: "right", cell: (r, c) => c.num(r.flockAgeWeeks) },
      { header: "Birds placed", align: "right", cell: (r, c) => c.num(r.birdsPlaced) },
      { header: "Deaths", align: "right", cell: (r, c) => c.num(r.totalDeaths) },
      { header: "Remaining", align: "right", cell: (r, c) => c.num(r.finalBirdsRemaining) },
      { header: "Eggs", align: "right", cell: (r, c) => c.num(r.totalEggsProduced) },
      { header: "Feed (kg)", align: "right", cell: (r, c) => c.num(r.totalFeedConsumedKg) },
      { header: "Revenue", align: "right", cell: (r, c) => c.money(r.totalRevenue) },
      { header: "Cost", align: "right", cell: (r, c) => c.money(r.totalCost) },
      { header: "Net profit", align: "right", cell: (r, c) => c.money(r.netProfit) },
      { header: "Mort. %", align: "right", cell: (r, c) => c.pct(r.mortalityPercent) },
      { header: "Status", cell: (r, c) => c.text(r.status), badge: true },
    ],
  },
}
