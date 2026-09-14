// =============================================================================
// Financial Activity — the shapes returned by /api/Poultry/financial-activity.
//
// One row per business EVENT, carrying every effect that event had: cash,
// revenue, expense, profit and the financial positions it moved. The point of
// the report is that those are different things, so they are different fields
// and nothing here is derived from anything else at read time.
//
// Built by migration 290 over the existing cash-flow and P&L functions. See that
// file's header for why there is no projection table.
// =============================================================================

namespace PoultryFarmAPIWeb.Models
{
    public class FinancialActivityRow
    {
        /// <summary>
        /// Stable identity of the business event ("Sale:2166", "LoanPayment:5").
        /// Used to attach position changes and to keep one event to one row.
        /// </summary>
        public string EventKey { get; set; } = "";

        /// <summary>The day the event belongs to, in the company's own calendar.</summary>
        public DateTime BusinessDate { get; set; }

        /// <summary>
        /// Wall-clock time as recorded. These are `timestamp without time zone`
        /// columns holding company-local time, so this must NOT be treated as
        /// UTC or re-offset on the way to the browser.
        /// </summary>
        public DateTime OccurredAt { get; set; }

        /// <summary>Operating | Financing | Owner | Capital | Inventory | Transfer.</summary>
        public string ActivityType { get; set; } = "";

        public string Type { get; set; } = "";
        public string Category { get; set; } = "";
        public string? Description { get; set; }

        public string? SourceType { get; set; }
        public int? SourceId { get; set; }
        public string? SourceNumber { get; set; }

        /// <summary>Actual money that entered the company. Never revenue.</summary>
        public decimal MoneyIn { get; set; }
        /// <summary>Actual money that left the company. Never an expense.</summary>
        public decimal MoneyOut { get; set; }
        /// <summary>Income recognised for Profit &amp; Loss, at the sale — not at collection.</summary>
        public decimal Revenue { get; set; }
        /// <summary>Cost recognised for Profit &amp; Loss, which may be long after it was paid for.</summary>
        public decimal Expense { get; set; }
        /// <summary>Revenue − Expense for this event. Money movement is never part of it.</summary>
        public decimal ProfitImpact { get; set; }
        /// <summary>Company cash position after this event; unchanged by non-cash events.</summary>
        public decimal RunningCash { get; set; }

        public bool IsCashActivity { get; set; }
        public bool IsNonCashActivity { get; set; }
        public bool IsInternalTransfer { get; set; }

        public int? CashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        /// <summary>Customer or supplier, whichever the event has.</summary>
        public string? PartyName { get; set; }
        /// <summary>The P&amp;L line this landed on (Feed, Depreciation, LoanInterest…).</summary>
        public string? PlLine { get; set; }
        public string? Status { get; set; }

        /// <summary>What this event did to the farm's assets, debts and capital.</summary>
        public List<FinancialPositionChange> PositionChanges { get; set; } = new();
    }

    /// <summary>
    /// One financial position moved by an event. Not a journal line: there are no
    /// debits, credits or accounts here, only positions an owner already
    /// understands and that this database actually tracks.
    /// </summary>
    public class FinancialPositionChange
    {
        /// <summary>Cash | CustomerReceivable | SupplierPayable | Inventory | CapitalAsset | AccumulatedDepreciation | LoanLiability | OwnerCapital.</summary>
        public string PositionType { get; set; } = "";
        /// <summary>Which one — the lender, the customer, the account.</summary>
        public string PositionName { get; set; } = "";
        public decimal IncreaseAmount { get; set; }
        public decimal DecreaseAmount { get; set; }
        public string? Explanation { get; set; }
    }

    public class FinancialActivitySummary
    {
        public decimal MoneyIn { get; set; }
        public decimal MoneyOut { get; set; }
        public decimal NetCashFlow { get; set; }
        public decimal OpeningCash { get; set; }
        public decimal ClosingCash { get; set; }
        public decimal Revenue { get; set; }
        public decimal Expense { get; set; }
        public decimal NetProfit { get; set; }
        public int EventCount { get; set; }
        public int CashEvents { get; set; }
        public int NonCashEvents { get; set; }
    }

    public class FinancialActivityResponse
    {
        public string? FarmId { get; set; }
        public DateTime? FromDate { get; set; }
        public DateTime? ToDate { get; set; }
        public FinancialActivitySummary Summary { get; set; } = new();
        public List<FinancialActivityRow> Rows { get; set; } = new();
    }
}
