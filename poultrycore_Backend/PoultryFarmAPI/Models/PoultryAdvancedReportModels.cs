using System;
using System.Collections.Generic;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Advanced Poultry Reports — DTOs / view models
    // -------------------------------------------------------------------------
    // These power the 20 NEW poultry-only reports exposed under
    // /api/poultry/reports/*. They are brand-new and additive: nothing here
    // touches the existing poultry, water or generic report DTOs.
    //
    // All reports are scoped by FarmId (the poultry company/farm) and are only
    // served when the farm's Type is Poultry (see PoultryAdvancedReportsController).
    //
    // Naming is deliberately poultry-specific so the codebase stays clear.
    // =========================================================================

    /// <summary>
    /// Shared request filter for every advanced poultry report. Only the
    /// relevant fields are used per report — none are required on every report.
    /// The frontend resolves date presets (Today / This Week / …) into
    /// StartDate + EndDate before calling, but DatePreset is carried through so
    /// it can be echoed back in AppliedFilters.
    /// </summary>
    public class PoultryReportFilterDto
    {
        public string? FarmId { get; set; }
        public string? CompanyId { get; set; }
        public string? UserId { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public string? DatePreset { get; set; }
        public int? FlockId { get; set; }
        public int? CustomerId { get; set; }
        /// <summary>Legacy poultry Sale rows link to a customer by name, not id.</summary>
        public string? CustomerName { get; set; }
        public int? ProductId { get; set; }
        public int? SupplierId { get; set; }
        /// <summary>Legacy poultry Expense rows store the supplier/payee as free text.</summary>
        public string? SupplierName { get; set; }
        public string? Status { get; set; }
        public bool IncludeClosedFlocks { get; set; }
        public bool IncludeInactiveItems { get; set; }
    }

    /// <summary>
    /// Uniform response envelope for every advanced poultry report. TSummary is
    /// the summary-card payload; TRow is the detail-table row type.
    /// </summary>
    public class PoultryReportResponse<TSummary, TRow>
    {
        public string ReportName { get; set; } = string.Empty;
        public string? FarmId { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public DateTime GeneratedAt { get; set; } = DateTime.UtcNow;
        public int EggsPerCrate { get; set; } = PoultryReportConstants.DefaultEggsPerCrate;
        public TSummary? Summary { get; set; }
        public List<TRow> Rows { get; set; } = new();
        /// <summary>Non-fatal notices, e.g. "Medicine cost is not tracked yet."</summary>
        public List<string> Warnings { get; set; } = new();
        /// <summary>Echo of the filters actually applied (for the PDF letterhead).</summary>
        public Dictionary<string, string?> AppliedFilters { get; set; } = new();
    }

    public static class PoultryReportConstants
    {
        /// <summary>
        /// Centralised eggs-per-crate. Used for all crate conversions so the
        /// value is defined in exactly one place. (A tray/crate in Ghana = 30.)
        /// </summary>
        public const int DefaultEggsPerCrate = 30;
    }

    // -------------------------------------------------------------------------
    // 1. Farm Summary
    // -------------------------------------------------------------------------
    public class PoultryFarmSummaryReportSummary
    {
        public long TotalEggsProduced { get; set; }
        public long SaleableEggs { get; set; }
        public long BrokenRejectedEggs { get; set; }
        public int ActiveFlocks { get; set; }
        public int ActiveBirds { get; set; }
        public int Deaths { get; set; }
        public decimal FeedConsumedKg { get; set; }
        public decimal? FeedCost { get; set; }
        public decimal SalesRevenue { get; set; }
        public decimal Expenses { get; set; }
        public decimal EstimatedProfit { get; set; }
        public decimal? CashCollected { get; set; }
        public decimal? CustomerReceivables { get; set; }
    }

    public class PoultryFarmSummaryReportRow
    {
        public int? FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public int StartingBirds { get; set; }
        public int CurrentBirds { get; set; }
        public long EggsProduced { get; set; }
        public long BrokenRejectedEggs { get; set; }
        public double? EggProductionPercent { get; set; }
        public decimal FeedConsumedKg { get; set; }
        public int Deaths { get; set; }
        public decimal SalesRevenue { get; set; }
        public decimal ExpensesAllocated { get; set; }
        public decimal EstimatedProfit { get; set; }
    }

    // -------------------------------------------------------------------------
    // 2. Daily Egg Production
    // -------------------------------------------------------------------------
    public class PoultryDailyEggProductionReportSummary
    {
        public long TotalEggs { get; set; }
        public double AverageEggsPerDay { get; set; }
        public DateTime? BestProductionDay { get; set; }
        public long BestProductionDayEggs { get; set; }
        public DateTime? LowestProductionDay { get; set; }
        public long LowestProductionDayEggs { get; set; }
        public long TotalBrokenEggs { get; set; }
        public double? AverageProductionPercent { get; set; }
    }

    public class PoultryDailyEggProductionReportRow
    {
        public DateTime Date { get; set; }
        public int? FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public int? AgeInWeeks { get; set; }
        public int MorningEggs { get; set; }
        public int MiddayEggs { get; set; }
        public int EveningEggs { get; set; }
        public long TotalEggs { get; set; }
        public int BrokenEggs { get; set; }
        public long SaleableEggs { get; set; }
        public double? EggProductionPercent { get; set; }
        public string? Notes { get; set; }
    }

    // -------------------------------------------------------------------------
    // 3. Flock Production Summary
    // -------------------------------------------------------------------------
    public class PoultryFlockProductionSummaryReportSummary
    {
        public int ActiveFlocks { get; set; }
        public string? BestProducingFlock { get; set; }
        public string? LowestProducingFlock { get; set; }
        public long TotalEggs { get; set; }
        public double AverageEggsPerFlock { get; set; }
        public double? AverageProductionPercent { get; set; }
    }

    public class PoultryFlockProductionSummaryReportRow
    {
        public int? FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public int? FlockAgeWeeks { get; set; }
        public int BirdsPlaced { get; set; }
        public int CurrentBirds { get; set; }
        public long TotalEggs { get; set; }
        public double AverageDailyEggs { get; set; }
        public long PeakDailyEggs { get; set; }
        public long BrokenEggs { get; set; }
        public double? ProductionPercent { get; set; }
        public decimal FeedConsumedKg { get; set; }
        public int Deaths { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    // -------------------------------------------------------------------------
    // 4. Hen-Day Production
    // -------------------------------------------------------------------------
    public class PoultryHenDayProductionReportSummary
    {
        public double? AverageHenDayPercent { get; set; }
        public double? HighestHenDayPercent { get; set; }
        public double? LowestHenDayPercent { get; set; }
        public int FlocksBelowTarget { get; set; }
    }

    public class PoultryHenDayProductionReportRow
    {
        public DateTime Date { get; set; }
        public int? FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public int LiveBirds { get; set; }
        public long EggsProduced { get; set; }
        public double? HenDayPercent { get; set; }
        public double? TargetPercent { get; set; }
        public double? Variance { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    // -------------------------------------------------------------------------
    // 5. Mortality
    // -------------------------------------------------------------------------
    public class PoultryMortalityReportSummary
    {
        public int TotalDeaths { get; set; }
        public double AverageDailyDeaths { get; set; }
        public DateTime? HighestMortalityDay { get; set; }
        public int HighestMortalityDayDeaths { get; set; }
        public double? CumulativeMortalityPercent { get; set; }
        public int FlocksWithHighMortality { get; set; }
    }

    public class PoultryMortalityReportRow
    {
        public DateTime Date { get; set; }
        public int? FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public int? OpeningBirds { get; set; }
        public int Deaths { get; set; }
        public int? Culls { get; set; }
        public int? BirdsSoldTransferred { get; set; }
        public int? ClosingBirds { get; set; }
        public double? DailyMortalityPercent { get; set; }
        public double? CumulativeMortalityPercent { get; set; }
        public string? Notes { get; set; }
    }

    // -------------------------------------------------------------------------
    // 6. Birds on Hand
    // -------------------------------------------------------------------------
    public class PoultryBirdsOnHandReportSummary
    {
        public int TotalBirdsPlaced { get; set; }
        public int CurrentLiveBirds { get; set; }
        public int TotalDeaths { get; set; }
        public int TotalCulls { get; set; }
        public int TotalBirdsSoldTransferred { get; set; }
        public int? BirdVariance { get; set; }
    }

    public class PoultryBirdsOnHandReportRow
    {
        public int? FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public int BirdsPlaced { get; set; }
        public int? TransfersIn { get; set; }
        public int Deaths { get; set; }
        public int? Culls { get; set; }
        public int? BirdsSold { get; set; }
        public int? TransfersOut { get; set; }
        public int ExpectedBirdsOnHand { get; set; }
        public int CurrentRecordedBirds { get; set; }
        public int Variance { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    // -------------------------------------------------------------------------
    // 7. Feed Usage
    // -------------------------------------------------------------------------
    public class PoultryFeedUsageReportSummary
    {
        public decimal TotalFeedConsumedKg { get; set; }
        public decimal AverageFeedPerDayKg { get; set; }
        public decimal? AverageFeedPerBirdKg { get; set; }
        public string? HighestFeedConsumingFlock { get; set; }
        public decimal? FeedWastageKg { get; set; }
    }

    public class PoultryFeedUsageReportRow
    {
        public DateTime Date { get; set; }
        public int? FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public string FeedType { get; set; } = string.Empty;
        public decimal? FeedIssuedKg { get; set; }
        public decimal? FeedReturnedKg { get; set; }
        public decimal FeedConsumedKg { get; set; }
        public int? LiveBirds { get; set; }
        public decimal? FeedPerBirdKg { get; set; }
        public long? EggsProduced { get; set; }
        public decimal? FeedPerEggKg { get; set; }
        public string? Notes { get; set; }
    }

    // -------------------------------------------------------------------------
    // 8. Feed Inventory Balance
    // -------------------------------------------------------------------------
    public class PoultryFeedInventoryBalanceReportSummary
    {
        public decimal TotalFeedStockKg { get; set; }
        public decimal? TotalFeedStockValue { get; set; }
        public int LowStockItems { get; set; }
        public int OutOfStockItems { get; set; }
        public double? EstimatedDaysRemaining { get; set; }
    }

    public class PoultryFeedInventoryBalanceReportRow
    {
        public string FeedItem { get; set; } = string.Empty;
        public string? Category { get; set; }
        public decimal? OpeningStockKg { get; set; }
        public decimal ReceivedKg { get; set; }
        public decimal IssuedKg { get; set; }
        public decimal AdjustmentsKg { get; set; }
        public decimal CurrentStockKg { get; set; }
        public string Unit { get; set; } = "kg";
        public decimal? UnitCost { get; set; }
        public decimal? StockValue { get; set; }
        public decimal? ReorderLevelKg { get; set; }
        public double? EstimatedDaysRemaining { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    // -------------------------------------------------------------------------
    // 9. Feed Cost Per Egg
    // -------------------------------------------------------------------------
    public class PoultryFeedCostPerEggReportSummary
    {
        public decimal? TotalFeedCost { get; set; }
        public long TotalEggs { get; set; }
        public decimal? AverageFeedCostPerEgg { get; set; }
        public decimal? AverageFeedCostPerCrate { get; set; }
        public string? MostExpensiveFlock { get; set; }
    }

    public class PoultryFeedCostPerEggReportRow
    {
        public int? FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public decimal FeedConsumedKg { get; set; }
        public decimal? AverageFeedUnitCost { get; set; }
        public decimal? TotalFeedCost { get; set; }
        public long EggsProduced { get; set; }
        public decimal? FeedCostPerEgg { get; set; }
        public decimal? FeedCostPerCrate { get; set; }
        public double? ProductionPercent { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    // -------------------------------------------------------------------------
    // 10. Egg Stock Balance
    // -------------------------------------------------------------------------
    public class PoultryEggStockBalanceReportSummary
    {
        public long TotalEggsInStock { get; set; }
        public long TotalCrates { get; set; }
        public int LooseEggs { get; set; }
        public long SaleableEggs { get; set; }
        public long? BrokenRejectedEggs { get; set; }
        public decimal? StockValue { get; set; }
    }

    public class PoultryEggStockBalanceReportRow
    {
        public string ProductGrade { get; set; } = string.Empty;
        public long OpeningStock { get; set; }
        public long ProductionAdded { get; set; }
        public long SalesRemoved { get; set; }
        public long LossesAdjustments { get; set; }
        public long CurrentStockEggs { get; set; }
        public long CurrentStockCrates { get; set; }
        public int LooseEggs { get; set; }
        public decimal? AverageSellingPrice { get; set; }
        public decimal? StockValue { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    // -------------------------------------------------------------------------
    // 11. Egg Sales
    // -------------------------------------------------------------------------
    public class PoultryEggSalesReportSummary
    {
        public decimal TotalSalesRevenue { get; set; }
        public decimal TotalEggsSold { get; set; }
        public long TotalCratesSold { get; set; }
        public decimal TotalPaid { get; set; }
        public decimal TotalUnpaid { get; set; }
        public string? TopCustomer { get; set; }
    }

    public class PoultryEggSalesReportRow
    {
        public DateTime Date { get; set; }
        public int SaleId { get; set; }
        public string? Customer { get; set; }
        public string? ProductGrade { get; set; }
        public decimal QuantitySold { get; set; }
        public string? Unit { get; set; }
        public long? EggsEquivalent { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }
        public string PaymentStatus { get; set; } = string.Empty;
        public string? PaymentMethod { get; set; }
    }

    // -------------------------------------------------------------------------
    // 12. Customer Balance
    // -------------------------------------------------------------------------
    public class PoultryCustomerBalanceReportSummary
    {
        public int CustomersWithBalance { get; set; }
        public decimal TotalReceivables { get; set; }
        public decimal? OverdueAmount { get; set; }
        public string? HighestOwingCustomer { get; set; }
    }

    public class PoultryCustomerBalanceReportRow
    {
        public int? CustomerId { get; set; }
        public string Customer { get; set; } = string.Empty;
        public decimal TotalSales { get; set; }
        public decimal TotalPaid { get; set; }
        public decimal CurrentBalance { get; set; }
        public DateTime? LastSaleDate { get; set; }
        public DateTime? LastPaymentDate { get; set; }
        public decimal? OverdueAmount { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    // -------------------------------------------------------------------------
    // 13. Expense Summary
    // -------------------------------------------------------------------------
    public class PoultryExpenseSummaryReportSummary
    {
        public decimal TotalExpenses { get; set; }
        public decimal PaidExpenses { get; set; }
        public decimal UnpaidExpenses { get; set; }
        public string? LargestExpenseCategory { get; set; }
        public decimal AverageDailyExpense { get; set; }
    }

    public class PoultryExpenseSummaryReportRow
    {
        public DateTime Date { get; set; }
        public int ExpenseId { get; set; }
        public string Category { get; set; } = string.Empty;
        public string? Description { get; set; }
        public string? FlockName { get; set; }
        public string? Supplier { get; set; }
        public decimal Amount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }
        public string? PaymentMethod { get; set; }
        public string Status { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
    }

    // -------------------------------------------------------------------------
    // 14. Cash Movement
    // -------------------------------------------------------------------------
    public class PoultryCashMovementReportSummary
    {
        public decimal? OpeningCashBalance { get; set; }
        public decimal TotalInflows { get; set; }
        public decimal TotalOutflows { get; set; }
        public decimal? EndingBalance { get; set; }
        public decimal NetCashMovement { get; set; }
    }

    public class PoultryCashMovementReportRow
    {
        public DateTime Date { get; set; }
        public string? CashAccount { get; set; }
        public string SourceType { get; set; } = string.Empty;
        public string? Reference { get; set; }
        public string? Description { get; set; }
        public decimal Inflow { get; set; }
        public decimal Outflow { get; set; }
        public decimal? BalanceAfter { get; set; }
        public string? CreatedBy { get; set; }
        public string? Status { get; set; }
    }

    // -------------------------------------------------------------------------
    // 15. Profit & Loss by Flock
    // -------------------------------------------------------------------------
    public class PoultryProfitLossByFlockReportSummary
    {
        public decimal TotalRevenue { get; set; }
        public decimal TotalExpenses { get; set; }
        public decimal GrossProfit { get; set; }
        public decimal NetProfit { get; set; }
        public string? MostProfitableFlock { get; set; }
        public string? LeastProfitableFlock { get; set; }
        // Category totals (across all flocks in scope) for the breakdown section.
        public decimal EggRevenue { get; set; }
        public decimal BirdSalesRevenue { get; set; }
        public decimal OtherRevenue { get; set; }
        public decimal FeedCost { get; set; }
        public decimal MedicineVaccineCost { get; set; }
        public decimal LaborCost { get; set; }
        public decimal OtherExpenses { get; set; }
    }

    public class PoultryProfitLossByFlockReportRow
    {
        public int? FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public decimal EggRevenue { get; set; }
        public decimal BirdSalesRevenue { get; set; }
        public decimal OtherRevenue { get; set; }
        public decimal? FeedCost { get; set; }
        public decimal? MedicineVaccineCost { get; set; }
        public decimal? LaborCost { get; set; }
        public decimal OtherExpenses { get; set; }
        public decimal TotalRevenue { get; set; }
        public decimal TotalCost { get; set; }
        public decimal GrossProfit { get; set; }
        public decimal NetProfit { get; set; }
        public decimal? ProfitPerBirdPlaced { get; set; }
        public decimal? ProfitPerEgg { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    // -------------------------------------------------------------------------
    // 15b. Profit & Loss (company-wide — all sales/expenses, not per flock)
    // -------------------------------------------------------------------------
    public class PoultryProfitLossReportSummary
    {
        public decimal TotalRevenue { get; set; }
        public decimal TotalExpenses { get; set; }
        public decimal GrossProfit { get; set; }
        public decimal NetProfit { get; set; }
        public decimal? NetMarginPercent { get; set; }
        // Category amounts, echoed for the breakdown section below the table.
        public decimal EggRevenue { get; set; }
        public decimal BirdSalesRevenue { get; set; }
        public decimal OtherRevenue { get; set; }
        public decimal FeedCost { get; set; }
        public decimal MedicineVaccineCost { get; set; }
        public decimal LaborCost { get; set; }
        public decimal OtherExpenses { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    /// <summary>
    /// One wide company row (mirrors the per-flock P&amp;L table layout, minus the
    /// flock column). Revenue and cost components across, then net profit + status.
    /// </summary>
    public class PoultryProfitLossReportRow
    {
        public string Scope { get; set; } = string.Empty;       // e.g. the date range
        public decimal EggRevenue { get; set; }
        public decimal BirdSalesRevenue { get; set; }
        public decimal OtherRevenue { get; set; }
        public decimal TotalRevenue { get; set; }
        public decimal FeedCost { get; set; }
        public decimal MedicineVaccineCost { get; set; }
        public decimal LaborCost { get; set; }
        public decimal OtherExpenses { get; set; }
        public decimal TotalCost { get; set; }
        public decimal GrossProfit { get; set; }
        public decimal NetProfit { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    // -------------------------------------------------------------------------
    // 16. Cost Per Egg
    // -------------------------------------------------------------------------
    public class PoultryCostPerEggReportSummary
    {
        public long TotalEggsProduced { get; set; }
        public decimal TotalDirectCosts { get; set; }
        public decimal TotalAllocatedCosts { get; set; }
        public decimal? AverageCostPerEgg { get; set; }
        public decimal? AverageCostPerCrate { get; set; }
    }

    public class PoultryCostPerEggReportRow
    {
        public int? FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public long EggsProduced { get; set; }
        public decimal? FeedCost { get; set; }
        public decimal? MedicineVaccineCost { get; set; }
        public decimal? LaborCost { get; set; }
        public decimal OtherAllocatedCost { get; set; }
        public decimal TotalCost { get; set; }
        public decimal? CostPerEgg { get; set; }
        public decimal? CostPerCrate { get; set; }
        public decimal? SellingPricePerEgg { get; set; }
        public decimal? MarginPerEgg { get; set; }
    }

    // -------------------------------------------------------------------------
    // 17. Vaccination Schedule
    // -------------------------------------------------------------------------
    public class PoultryVaccinationScheduleReportSummary
    {
        public int Upcoming { get; set; }
        public int DueToday { get; set; }
        public int OverdueMissed { get; set; }
        public int Completed { get; set; }
    }

    public class PoultryVaccinationScheduleReportRow
    {
        public int? FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public string? Vaccine { get; set; }
        public string? Disease { get; set; }
        public string? RecommendedAgeOrDate { get; set; }
        public DateTime? ScheduledDate { get; set; }
        public DateTime? ActualDate { get; set; }
        public string? Dose { get; set; }
        public string? Route { get; set; }
        public string Status { get; set; } = string.Empty;
        public string? AdministeredBy { get; set; }
        public string? Notes { get; set; }
    }

    // -------------------------------------------------------------------------
    // 18. Medicine Usage
    // -------------------------------------------------------------------------
    public class PoultryMedicineUsageReportSummary
    {
        public decimal? TotalMedicineCost { get; set; }
        public int NumberOfTreatments { get; set; }
        public string? MostUsedMedicine { get; set; }
        public int FlocksUnderTreatment { get; set; }
        public int? ExpiringMedicine { get; set; }
    }

    public class PoultryMedicineUsageReportRow
    {
        public DateTime Date { get; set; }
        public int? FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public string? Medicine { get; set; }
        public string? SymptomsCondition { get; set; }
        public string? Dosage { get; set; }
        public decimal? QuantityUsed { get; set; }
        public decimal? UnitCost { get; set; }
        public decimal? TotalCost { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public string? WithdrawalPeriod { get; set; }
        public string? AdministeredBy { get; set; }
        public string? Notes { get; set; }
    }

    // -------------------------------------------------------------------------
    // 19. Missing Daily Records
    // -------------------------------------------------------------------------
    public class PoultryMissingDailyRecordsReportSummary
    {
        public int ActiveFlocks { get; set; }
        public int MissingProductionRecords { get; set; }
        public int MissingFeedRecords { get; set; }
        public int? MissingHealthRecords { get; set; }
        public int CompleteFlockDays { get; set; }
    }

    public class PoultryMissingDailyRecordsReportRow
    {
        public DateTime Date { get; set; }
        public int? FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public bool HasProductionRecord { get; set; }
        public bool HasFeedUsage { get; set; }
        public bool HasMortalityUpdate { get; set; }
        public bool? HasHealthNote { get; set; }
        public string MissingItems { get; set; } = string.Empty;
        public string? AssignedEmployee { get; set; }
        public string Status { get; set; } = string.Empty;
    }

    // -------------------------------------------------------------------------
    // 20. End-of-Flock
    // -------------------------------------------------------------------------
    public class PoultryEndOfFlockReportSummary
    {
        public int BirdsPlaced { get; set; }
        public int BirdsRemaining { get; set; }
        public int BirdsSoldOrDead { get; set; }
        public long TotalEggs { get; set; }
        public decimal TotalFeedConsumedKg { get; set; }
        public decimal TotalRevenue { get; set; }
        public decimal TotalCost { get; set; }
        public decimal NetProfit { get; set; }
        public double? MortalityPercent { get; set; }
        public decimal? FeedCostPerEgg { get; set; }
        public decimal? ProfitPerBird { get; set; }
    }

    public class PoultryEndOfFlockReportRow
    {
        public int? FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public DateTime? PlacementDate { get; set; }
        public DateTime? ClosingDate { get; set; }
        public int? FlockAgeWeeks { get; set; }
        public int BirdsPlaced { get; set; }
        public int TotalDeaths { get; set; }
        public int? Culls { get; set; }
        public int? BirdsSoldTransferred { get; set; }
        public int FinalBirdsRemaining { get; set; }
        public long TotalEggsProduced { get; set; }
        public long SaleableEggs { get; set; }
        public long BrokenRejectedEggs { get; set; }
        public long PeakProductionDay { get; set; }
        public double? AverageProductionPercent { get; set; }
        public decimal TotalFeedConsumedKg { get; set; }
        public decimal? FeedCost { get; set; }
        public decimal? MedicineVaccineCost { get; set; }
        public decimal? LaborCost { get; set; }
        public decimal OtherCost { get; set; }
        public decimal EggSalesRevenue { get; set; }
        public decimal BirdSalesRevenue { get; set; }
        public decimal OtherRevenue { get; set; }
        public decimal TotalRevenue { get; set; }
        public decimal TotalCost { get; set; }
        public decimal NetProfit { get; set; }
        public decimal? ProfitPerBirdPlaced { get; set; }
        public decimal? ProfitPerEgg { get; set; }
        public double? MortalityPercent { get; set; }
        public string Status { get; set; } = string.Empty;
    }
}
