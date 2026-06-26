// =============================================================================
// Advanced Poultry Reports — frontend API client + types.
//
// Calls the 20 new poultry-only endpoints under /api/poultry/reports/* (via the
// same-origin proxy). Every call is scoped by the active farmId from
// getUserContext(). Brand-new and additive — does not touch lib/api/report.ts,
// water.ts or generic.ts.
// =============================================================================

import { buildApiUrl, getAuthHeaders, getUserContext } from "./config"

/** Uniform response envelope returned by every advanced poultry report. */
export interface PoultryReportResponse<TSummary = any, TRow = any> {
  reportName: string
  farmId?: string | null
  startDate?: string | null
  endDate?: string | null
  generatedAt: string
  eggsPerCrate: number
  summary: TSummary | null
  rows: TRow[]
  warnings: string[]
  appliedFilters: Record<string, string | null>
}

/** Filters accepted by the report endpoints (only the relevant ones are sent). */
export interface PoultryReportParams {
  startDate?: string
  endDate?: string
  datePreset?: string
  flockId?: number | null
  customerName?: string | null
  supplierName?: string | null
  includeClosedFlocks?: boolean
}

/** Every advanced-poultry report slug (matches the backend route + frontend route). */
export type PoultryReportSlug =
  | "farm-summary"
  | "daily-egg-production"
  | "flock-production-summary"
  | "hen-day-production"
  | "mortality"
  | "birds-on-hand"
  | "feed-usage"
  | "feed-inventory-balance"
  | "feed-cost-per-egg"
  | "egg-stock-balance"
  | "egg-sales"
  | "customer-balance"
  | "expense-summary"
  | "cash-movement"
  | "profit-loss-by-flock"
  | "cost-per-egg"
  | "vaccination-schedule"
  | "medicine-usage"
  | "missing-daily-records"
  | "end-of-flock"

/**
 * Generic fetch for any advanced poultry report. The active farmId is read from
 * localStorage (getUserContext) and sent on the query string, matching the
 * other poultry API modules.
 */
export async function fetchPoultryReport<TSummary = any, TRow = any>(
  slug: PoultryReportSlug,
  params: PoultryReportParams = {}
): Promise<PoultryReportResponse<TSummary, TRow>> {
  const { farmId, userId } = getUserContext()
  const qs = new URLSearchParams()
  if (farmId) qs.set("farmId", farmId)
  if (userId) qs.set("userId", userId)
  if (params.startDate) qs.set("startDate", params.startDate)
  if (params.endDate) qs.set("endDate", params.endDate)
  if (params.datePreset) qs.set("datePreset", params.datePreset)
  if (params.flockId != null) qs.set("flockId", String(params.flockId))
  if (params.customerName) qs.set("customerName", params.customerName)
  if (params.supplierName) qs.set("supplierName", params.supplierName)
  if (params.includeClosedFlocks) qs.set("includeClosedFlocks", "true")

  const url = buildApiUrl(`/poultry/reports/${slug}?${qs.toString()}`)
  const res = await fetch(url, { method: "GET", headers: getAuthHeaders() })
  if (!res.ok) {
    let message = `Report request failed (${res.status})`
    try {
      const body = await res.json()
      if (body?.message) message = body.message
    } catch {
      /* ignore */
    }
    throw new Error(message)
  }
  return (await res.json()) as PoultryReportResponse<TSummary, TRow>
}

// -----------------------------------------------------------------------------
// Summary + row interfaces (mirror the backend DTOs; camelCase).
// -----------------------------------------------------------------------------

export interface PoultryFarmSummaryReportSummary {
  totalEggsProduced: number; saleableEggs: number; brokenRejectedEggs: number
  activeFlocks: number; activeBirds: number; deaths: number
  feedConsumedKg: number; feedCost: number | null; salesRevenue: number
  expenses: number; estimatedProfit: number; cashCollected: number | null
  customerReceivables: number | null
}
export interface PoultryFarmSummaryReportRow {
  flockId: number | null; flockName: string; startingBirds: number; currentBirds: number
  eggsProduced: number; brokenRejectedEggs: number; eggProductionPercent: number | null
  feedConsumedKg: number; deaths: number; salesRevenue: number; expensesAllocated: number
  estimatedProfit: number
}

export interface PoultryDailyEggProductionReportSummary {
  totalEggs: number; averageEggsPerDay: number; bestProductionDay: string | null
  bestProductionDayEggs: number; lowestProductionDay: string | null
  lowestProductionDayEggs: number; totalBrokenEggs: number; averageProductionPercent: number | null
}
export interface PoultryDailyEggProductionReportRow {
  date: string; flockId: number | null; flockName: string; ageInWeeks: number | null
  morningEggs: number; middayEggs: number; eveningEggs: number; totalEggs: number
  brokenEggs: number; saleableEggs: number; eggProductionPercent: number | null; notes: string | null
}

export interface PoultryFlockProductionSummaryReportSummary {
  activeFlocks: number; bestProducingFlock: string | null; lowestProducingFlock: string | null
  totalEggs: number; averageEggsPerFlock: number; averageProductionPercent: number | null
}
export interface PoultryFlockProductionSummaryReportRow {
  flockId: number | null; flockName: string; flockAgeWeeks: number | null; birdsPlaced: number
  currentBirds: number; totalEggs: number; averageDailyEggs: number; peakDailyEggs: number
  brokenEggs: number; productionPercent: number | null; feedConsumedKg: number; deaths: number; status: string
}

export interface PoultryHenDayProductionReportSummary {
  averageHenDayPercent: number | null; highestHenDayPercent: number | null
  lowestHenDayPercent: number | null; flocksBelowTarget: number
}
export interface PoultryHenDayProductionReportRow {
  date: string; flockId: number | null; flockName: string; liveBirds: number
  eggsProduced: number; henDayPercent: number | null; targetPercent: number | null
  variance: number | null; status: string
}

export interface PoultryMortalityReportSummary {
  totalDeaths: number; averageDailyDeaths: number; highestMortalityDay: string | null
  highestMortalityDayDeaths: number; cumulativeMortalityPercent: number | null; flocksWithHighMortality: number
}
export interface PoultryMortalityReportRow {
  date: string; flockId: number | null; flockName: string; openingBirds: number | null
  deaths: number; culls: number | null; birdsSoldTransferred: number | null; closingBirds: number | null
  dailyMortalityPercent: number | null; cumulativeMortalityPercent: number | null; notes: string | null
}

export interface PoultryBirdsOnHandReportSummary {
  totalBirdsPlaced: number; currentLiveBirds: number; totalDeaths: number
  totalCulls: number; totalBirdsSoldTransferred: number; birdVariance: number | null
}
export interface PoultryBirdsOnHandReportRow {
  flockId: number | null; flockName: string; birdsPlaced: number; transfersIn: number | null
  deaths: number; culls: number | null; birdsSold: number | null; transfersOut: number | null
  expectedBirdsOnHand: number; currentRecordedBirds: number; variance: number; status: string
}

export interface PoultryFeedUsageReportSummary {
  totalFeedConsumedKg: number; averageFeedPerDayKg: number; averageFeedPerBirdKg: number | null
  highestFeedConsumingFlock: string | null; feedWastageKg: number | null
}
export interface PoultryFeedUsageReportRow {
  date: string; flockId: number | null; flockName: string; feedType: string
  feedIssuedKg: number | null; feedReturnedKg: number | null; feedConsumedKg: number
  liveBirds: number | null; feedPerBirdKg: number | null; eggsProduced: number | null
  feedPerEggKg: number | null; notes: string | null
}

export interface PoultryFeedInventoryBalanceReportSummary {
  totalFeedStockKg: number; totalFeedStockValue: number | null; lowStockItems: number
  outOfStockItems: number; estimatedDaysRemaining: number | null
}
export interface PoultryFeedInventoryBalanceReportRow {
  feedItem: string; category: string | null; openingStockKg: number | null; receivedKg: number
  issuedKg: number; adjustmentsKg: number; currentStockKg: number; unit: string
  unitCost: number | null; stockValue: number | null; reorderLevelKg: number | null
  estimatedDaysRemaining: number | null; status: string
}

export interface PoultryFeedCostPerEggReportSummary {
  totalFeedCost: number | null; totalEggs: number; averageFeedCostPerEgg: number | null
  averageFeedCostPerCrate: number | null; mostExpensiveFlock: string | null
}
export interface PoultryFeedCostPerEggReportRow {
  flockId: number | null; flockName: string; feedConsumedKg: number; averageFeedUnitCost: number | null
  totalFeedCost: number | null; eggsProduced: number; feedCostPerEgg: number | null
  feedCostPerCrate: number | null; productionPercent: number | null; status: string
}

export interface PoultryEggStockBalanceReportSummary {
  totalEggsInStock: number; totalCrates: number; looseEggs: number; saleableEggs: number
  brokenRejectedEggs: number | null; stockValue: number | null
}
export interface PoultryEggStockBalanceReportRow {
  productGrade: string; openingStock: number; productionAdded: number; salesRemoved: number
  lossesAdjustments: number; currentStockEggs: number; currentStockCrates: number; looseEggs: number
  averageSellingPrice: number | null; stockValue: number | null; status: string
}

export interface PoultryEggSalesReportSummary {
  totalSalesRevenue: number; totalEggsSold: number; totalCratesSold: number
  totalPaid: number; totalUnpaid: number; topCustomer: string | null
}
export interface PoultryEggSalesReportRow {
  date: string; saleId: number; customer: string | null; productGrade: string | null
  quantitySold: number; unit: string | null; eggsEquivalent: number | null; unitPrice: number
  totalAmount: number; amountPaid: number; balance: number; paymentStatus: string; paymentMethod: string | null
}

export interface PoultryCustomerBalanceReportSummary {
  customersWithBalance: number; totalReceivables: number; overdueAmount: number | null; highestOwingCustomer: string | null
}
export interface PoultryCustomerBalanceReportRow {
  customerId: number | null; customer: string; totalSales: number; totalPaid: number
  currentBalance: number; lastSaleDate: string | null; lastPaymentDate: string | null
  overdueAmount: number | null; status: string
}

export interface PoultryExpenseSummaryReportSummary {
  totalExpenses: number; paidExpenses: number; unpaidExpenses: number
  largestExpenseCategory: string | null; averageDailyExpense: number
}
export interface PoultryExpenseSummaryReportRow {
  date: string; expenseId: number; category: string; description: string | null; flockName: string | null
  supplier: string | null; amount: number; amountPaid: number; balance: number
  paymentMethod: string | null; status: string; createdBy: string | null
}

export interface PoultryCashMovementReportSummary {
  openingCashBalance: number | null; totalInflows: number; totalOutflows: number
  endingBalance: number | null; netCashMovement: number
}
export interface PoultryCashMovementReportRow {
  date: string; cashAccount: string | null; sourceType: string; reference: string | null
  description: string | null; inflow: number; outflow: number; balanceAfter: number | null
  createdBy: string | null; status: string | null
}

export interface PoultryProfitLossByFlockReportSummary {
  totalRevenue: number; totalExpenses: number; grossProfit: number; netProfit: number
  mostProfitableFlock: string | null; leastProfitableFlock: string | null
}
export interface PoultryProfitLossByFlockReportRow {
  flockId: number | null; flockName: string; eggRevenue: number; birdSalesRevenue: number; otherRevenue: number
  feedCost: number | null; medicineVaccineCost: number | null; laborCost: number | null; otherExpenses: number
  totalRevenue: number; totalCost: number; grossProfit: number; netProfit: number
  profitPerBirdPlaced: number | null; profitPerEgg: number | null; status: string
}

export interface PoultryCostPerEggReportSummary {
  totalEggsProduced: number; totalDirectCosts: number; totalAllocatedCosts: number
  averageCostPerEgg: number | null; averageCostPerCrate: number | null
}
export interface PoultryCostPerEggReportRow {
  flockId: number | null; flockName: string; eggsProduced: number; feedCost: number | null
  medicineVaccineCost: number | null; laborCost: number | null; otherAllocatedCost: number
  totalCost: number; costPerEgg: number | null; costPerCrate: number | null
  sellingPricePerEgg: number | null; marginPerEgg: number | null
}

export interface PoultryVaccinationScheduleReportSummary {
  upcoming: number; dueToday: number; overdueMissed: number; completed: number
}
export interface PoultryVaccinationScheduleReportRow {
  flockId: number | null; flockName: string; vaccine: string | null; disease: string | null
  recommendedAgeOrDate: string | null; scheduledDate: string | null; actualDate: string | null
  dose: string | null; route: string | null; status: string; administeredBy: string | null; notes: string | null
}

export interface PoultryMedicineUsageReportSummary {
  totalMedicineCost: number | null; numberOfTreatments: number; mostUsedMedicine: string | null
  flocksUnderTreatment: number; expiringMedicine: number | null
}
export interface PoultryMedicineUsageReportRow {
  date: string; flockId: number | null; flockName: string; medicine: string | null
  symptomsCondition: string | null; dosage: string | null; quantityUsed: number | null; unitCost: number | null
  totalCost: number | null; startDate: string | null; endDate: string | null; withdrawalPeriod: string | null
  administeredBy: string | null; notes: string | null
}

export interface PoultryMissingDailyRecordsReportSummary {
  activeFlocks: number; missingProductionRecords: number; missingFeedRecords: number
  missingHealthRecords: number | null; completeFlockDays: number
}
export interface PoultryMissingDailyRecordsReportRow {
  date: string; flockId: number | null; flockName: string; hasProductionRecord: boolean
  hasFeedUsage: boolean; hasMortalityUpdate: boolean; hasHealthNote: boolean | null
  missingItems: string; assignedEmployee: string | null; status: string
}

export interface PoultryEndOfFlockReportSummary {
  birdsPlaced: number; birdsRemaining: number; birdsSoldOrDead: number; totalEggs: number
  totalFeedConsumedKg: number; totalRevenue: number; totalCost: number; netProfit: number
  mortalityPercent: number | null; feedCostPerEgg: number | null; profitPerBird: number | null
}
export interface PoultryEndOfFlockReportRow {
  flockId: number | null; flockName: string; placementDate: string | null; closingDate: string | null
  flockAgeWeeks: number | null; birdsPlaced: number; totalDeaths: number; culls: number | null
  birdsSoldTransferred: number | null; finalBirdsRemaining: number; totalEggsProduced: number
  saleableEggs: number; brokenRejectedEggs: number; peakProductionDay: number; averageProductionPercent: number | null
  totalFeedConsumedKg: number; feedCost: number | null; medicineVaccineCost: number | null; laborCost: number | null
  otherCost: number; eggSalesRevenue: number; birdSalesRevenue: number; otherRevenue: number
  totalRevenue: number; totalCost: number; netProfit: number; profitPerBirdPlaced: number | null
  profitPerEgg: number | null; mortalityPercent: number | null; status: string
}
