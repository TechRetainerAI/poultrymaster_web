// The structured water Profit & Loss and its drilldowns (migration 316).
//
// WHAT THIS IS, AND WHAT IT IS NOT
// -------------------------------
// It is an ANALYTICAL LAYER over spwaterreport_periodpnl, not a replacement for
// it. Revenue, direct cost, losses and NET PROFIT are that function's own
// figures, unchanged. The statement below itemises them; it does not recompute
// them.
//
// That is the opposite of the poultry side, where migration 272 rebuilt the P&L
// on the classification model. Water's P&L is an older mix -- driver-return
// collections as income, cash-basis raw materials, production-batch costs,
// losses from two other tables -- and rebuilding it would have RESTATED what the
// company reports as profit. The analysis was wanted; the restatement was not.
//
// ONE ROW SHAPE FOR EVERY DRILLDOWN
// ---------------------------------
// Unlike poultry, which has six drilldown row types, every water drilldown
// answers the same four questions -- when, which record, who, and how much --
// so they share WaterPlDetailRow. Six near-identical DTOs would only be six
// places for the columns to drift apart.

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// Which band of the statement a line belongs to.
    ///
    /// Revenue, DirectCost, OperatingExpense, OtherCost and Loss are PROFIT --
    /// together they reproduce periodpnl's net profit exactly, and the check file
    /// asserts it. Financing and CapitalInvestment are informational: the cash
    /// moved and the profit did not.
    /// </summary>
    public static class WaterPlSection
    {
        public const string Revenue = "Revenue";
        public const string DirectCost = "DirectCost";
        public const string OperatingExpense = "OperatingExpense";
        public const string OtherCost = "OtherCost";
        public const string Loss = "Loss";
        public const string Financing = "Financing";
        public const string CapitalInvestment = "CapitalInvestment";
    }

    /// <summary>Which drilldown a line opens. Maps to one SQL function each.</summary>
    public static class WaterPlDetailKind
    {
        public const string Revenue = "revenue";
        public const string DirectCost = "directcost";
        public const string Expense = "expense";
        public const string Loss = "loss";
        public const string Financing = "financing";
        public const string Capital = "capital";
        public const string Depreciation = "depreciation";
    }

    public class WaterPlLine
    {
        /// <summary>One of <see cref="WaterPlSection"/>.</summary>
        public string Section { get; set; } = "";
        /// <summary>The key a drilldown is requested by: StorefrontSales, RawMaterials, …</summary>
        public string LineKey { get; set; } = "";
        public string LineLabel { get; set; } = "";
        public decimal Amount { get; set; }
        /// <summary>Printing order. The caller never has to know it.</summary>
        public int SortOrder { get; set; }
        /// <summary>True for Financing and CapitalInvestment. Never inside a profit total.</summary>
        public bool IsInformational { get; set; }
        /// <summary>How many source records are behind the figure.</summary>
        public int EntryCount { get; set; }
    }

    public class WaterPlSummary
    {
        public DateTime StartDate { get; set; }
        public DateTime EndDate { get; set; }

        public decimal StorefrontSales { get; set; }
        /// <summary>Driver-return COLLECTIONS, not sales. See the migration header.</summary>
        public decimal DeliveryCollections { get; set; }
        public decimal TotalRevenue { get; set; }

        /// <summary>Cash paid for raw materials. periodpnl's basis, not accrual.</summary>
        public decimal RawMaterials { get; set; }
        public decimal ProductionCost { get; set; }
        public decimal TotalDirectCosts { get; set; }

        public decimal GrossProfit { get; set; }
        public decimal GrossMarginPercent { get; set; }

        public decimal TotalOperatingExpenses { get; set; }
        /// <summary>Depreciation, loan interest and fees — below operating profit.</summary>
        public decimal TotalOtherCosts { get; set; }
        public decimal OperatingProfit { get; set; }
        public decimal OperatingMarginPercent { get; set; }

        public decimal ProductionLosses { get; set; }
        public decimal DriverShortages { get; set; }
        public decimal TotalLosses { get; set; }

        /// <summary>periodpnl's OWN net profit. Not recomputed here.</summary>
        public decimal NetProfit { get; set; }
        public decimal NetMarginPercent { get; set; }

        // ---- informational: the cash moved, the profit did not ----------
        public decimal OwnerContributions { get; set; }
        public decimal OwnerDraws { get; set; }
        public decimal NetOwnerFunding { get; set; }
        public decimal LoansReceived { get; set; }
        public decimal LoanPrincipalRepaid { get; set; }
        public decimal NetBorrowing { get; set; }
        public decimal TotalCapitalInvestments { get; set; }

        public int BagsProduced { get; set; }
        public int BagsSold { get; set; }
        public decimal AvgProfitPerBag { get; set; }

        /// <summary>
        /// Capital-asset purchases sitting INSIDE the expense pool, because
        /// periodpnl counts every approved expense except raw materials. Zero on
        /// a company that has never bought one. Non-zero means the P&L is
        /// charging a purchase that poultry's P&L would exclude — the screen
        /// says so rather than hiding it.
        /// </summary>
        public decimal CapitalInExpenses { get; set; }

        /// <summary>Source records behind the profit bands.</summary>
        public int EntryCount { get; set; }
    }

    /// <summary>The report in one call: the headline figures and the statement.</summary>
    public class WaterProfitLossReport
    {
        public WaterPlSummary Summary { get; set; } = new();
        public List<WaterPlLine> Lines { get; set; } = new();
    }

    /// <summary>
    /// One row behind a figure. Shared by every drilldown: when it happened,
    /// which record it is, who it involved, what it was, and how much.
    /// </summary>
    public class WaterPlDetailRow
    {
        public DateTime? EntryDate { get; set; }
        public string? Reference { get; set; }
        public string? Party { get; set; }
        public string? Detail { get; set; }
        public decimal Amount { get; set; }
    }
}
