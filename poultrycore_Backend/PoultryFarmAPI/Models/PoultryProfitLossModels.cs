// The structured Poultry Profit & Loss (migration 272).
//
//   Revenue
//   - Direct Production Costs   = GROSS PROFIT
//   - Operating Expenses        = OPERATING PROFIT
//   - Depreciation & Financing  = NET PROFIT
//
// and, beside it and never inside it, Financing & Owner Activity and Capital
// Investments. Those two are informational: they move cash and they are not
// profit, which is the whole distinction this phase exists to make.

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>One printed line of the statement, and the key its drilldown asks for.</summary>
    public class PoultryProfitLossLine
    {
        /// <summary>Revenue | DirectCost | OperatingExpense | OtherCost | Financing | CapitalInvestment.</summary>
        public string Section { get; set; } = string.Empty;
        /// <summary>The key a drilldown is requested by. Feed, Payroll, EggSales, ...</summary>
        public string LineKey { get; set; } = string.Empty;
        public string LineLabel { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        /// <summary>Print order. The caller never has to know it.</summary>
        public int SortOrder { get; set; }
        /// <summary>
        /// True for Financing and CapitalInvestment. An informational line is
        /// never in a profit total; showing it as if it were is the mistake.
        /// </summary>
        public bool IsInformational { get; set; }
        public int EntryCount { get; set; }
    }

    public class PoultryProfitLossReport
    {
        public DateTime StartDate { get; set; }
        public DateTime EndDate { get; set; }

        // ---- revenue --------------------------------------------------------
        public decimal EggSales { get; set; }
        public decimal BirdSales { get; set; }
        public decimal ManureSales { get; set; }
        public decimal FeedSales { get; set; }
        public decimal OtherRevenue { get; set; }
        public decimal TotalRevenue { get; set; }

        // ---- direct production costs ---------------------------------------
        public decimal FeedCost { get; set; }
        public decimal MedicationCost { get; set; }
        public decimal DirectLabour { get; set; }
        public decimal ProductionSupplies { get; set; }
        public decimal FlockCost { get; set; }
        public decimal OtherDirectCosts { get; set; }
        public decimal TotalDirectCosts { get; set; }

        public decimal GrossProfit { get; set; }
        /// <summary>Null on zero revenue: there is no percentage of nothing.</summary>
        public decimal? GrossMarginPercent { get; set; }

        // ---- operating expenses ---------------------------------------------
        public decimal Payroll { get; set; }
        public decimal Utilities { get; set; }
        public decimal Transport { get; set; }
        public decimal RepairsMaintenance { get; set; }
        public decimal Administration { get; set; }
        public decimal Marketing { get; set; }
        /// <summary>Everything operating that is not one of the six above. Broken out in Lines.</summary>
        public decimal OtherOperatingExpenses { get; set; }
        public decimal TotalOperatingExpenses { get; set; }

        public decimal OperatingProfit { get; set; }
        public decimal? OperatingMarginPercent { get; set; }

        // ---- below operating profit ------------------------------------------
        public decimal Depreciation { get; set; }
        public decimal LoanInterest { get; set; }
        public decimal LoanFees { get; set; }
        public decimal OtherFinancingCosts { get; set; }
        public decimal TotalOtherCosts { get; set; }

        public decimal NetProfit { get; set; }
        public decimal? NetMarginPercent { get; set; }
        /// <summary>Profit | Loss | Break-even, derived from NetProfit.</summary>
        public string Status { get; set; } = "Break-even";

        // ---- informational: cash moved, profit did not ------------------------
        public decimal OwnerContributions { get; set; }
        public decimal OwnerDraws { get; set; }
        public decimal NetOwnerFunding { get; set; }
        public decimal LoansReceived { get; set; }
        public decimal LoanPrincipalRepaid { get; set; }
        public decimal NetBorrowing { get; set; }
        public decimal TotalCapitalInvestments { get; set; }

        // ---- how the costs were recognised -----------------------------------
        public string? FeedRecognitionMethod { get; set; }
        public string? MedicationRecognitionMethod { get; set; }
        public bool HasItemOverrides { get; set; }
        public bool RecognitionConfigured { get; set; }

        /// <summary>
        /// How many expense rows in the period carry no STATED classification and
        /// were placed by inference. What lets the report say how much of itself
        /// is legacy mapping instead of claiming all of it is.
        /// </summary>
        public int LegacyExpenses { get; set; }
        public int ClassifiedExpenses { get; set; }

        public List<PoultryProfitLossLine> Lines { get; set; } = new();
    }

    // ---- drilldown rows -----------------------------------------------------

    public class PoultryProfitLossExpenseRow
    {
        public int ExpenseId { get; set; }
        public DateTime ExpenseDate { get; set; }
        public string? Category { get; set; }
        public string? Description { get; set; }
        public decimal Amount { get; set; }
        public string? SupplierName { get; set; }
        public string? SourceType { get; set; }
        public string? SourceLabel { get; set; }
        public string? PaymentMethod { get; set; }
        public string? PaymentStatus { get; set; }
        public string? CostType { get; set; }
        public string? PlLine { get; set; }
        public string? PlLineLabel { get; set; }
        public int? PoultryCapitalAssetId { get; set; }
        /// <summary>True when the row was classified by inference rather than stated.</summary>
        public bool IsLegacy { get; set; }
    }

    public class PoultryProfitLossRevenueRow
    {
        public int SaleId { get; set; }
        public DateTime SaleDate { get; set; }
        public string? Product { get; set; }
        public string? CustomerName { get; set; }
        public decimal Quantity { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal AmountPaid { get; set; }
        public string? PaymentMethod { get; set; }
        public string? RevenueLine { get; set; }
        public string? RevenueLabel { get; set; }
    }

    /// <summary>
    /// Feed and medication, with the one column that stops a mixed period reading
    /// as double counting: WHICH recognition put each row there.
    /// </summary>
    public class PoultryProfitLossInventoryRow
    {
        public int ExpenseId { get; set; }
        public DateTime ExpenseDate { get; set; }
        public string? ItemName { get; set; }
        public string? ItemCategory { get; set; }
        public string? Description { get; set; }
        public decimal Amount { get; set; }
        public string? SourceType { get; set; }
        public string? SourceLabel { get; set; }
        /// <summary>Expense when purchased | Expense when consumed | Recorded directly.</summary>
        public string? Recognition { get; set; }
        public int? SourceId { get; set; }
        public decimal? Quantity { get; set; }
        public string? UnitOfMeasure { get; set; }
        /// <summary>How many purchase lots a consumption drew from. Null for a purchase.</summary>
        public int? CostLayers { get; set; }
    }

    public class PoultryProfitLossFinancingRow
    {
        public string? LineKey { get; set; }
        public DateTime EntryDate { get; set; }
        public string? Reference { get; set; }
        public string? Party { get; set; }
        public string? Description { get; set; }
        public decimal Amount { get; set; }
        public int EntryId { get; set; }
    }

    public class PoultryProfitLossCapitalRow
    {
        public int PoultryCapitalAssetCostId { get; set; }
        public int PoultryCapitalAssetId { get; set; }
        public string? AssetNumber { get; set; }
        public string? AssetName { get; set; }
        public string? CategoryName { get; set; }
        public DateTime CostDate { get; set; }
        public string? Description { get; set; }
        public string? CostCategory { get; set; }
        public decimal Amount { get; set; }
        public string? SupplierName { get; set; }
        public int? ExpenseId { get; set; }
        public string? AssetStatus { get; set; }
        public decimal OriginalCost { get; set; }
        public decimal CurrentBookValue { get; set; }
    }
}
