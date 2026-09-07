// =============================================================================
// Cash Flow — the shapes returned by /api/{rail}/cash-flow.
//
// Deliberately says nothing about cash accounts, ledgers, transfers or
// reconciliation. Cash Flow reports what the business earned and spent; where
// the money currently sits is the Cash Accounts module's question.
// =============================================================================

namespace PoultryFarmAPIWeb.Models
{
    public class CashFlowRow
    {
        /// <summary>Id within its own source table, not globally unique.</summary>
        public int Id { get; set; }
        /// <summary>Receipt | SaleResidual | Expense | Adjustment.</summary>
        public string RowSource { get; set; } = string.Empty;
        public string SourceType { get; set; } = string.Empty;
        public int? SourceId { get; set; }
        /// <summary>OperatingIn | OperatingOut | FinancingIn | FinancingOut.</summary>
        public string FlowGroup { get; set; } = string.Empty;
        /// <summary>What the money was for. Expense category, or Sales / capital type.</summary>
        public string Category { get; set; } = string.Empty;
        public DateTime TransactionDate { get; set; }
        public string? Description { get; set; }
        /// <summary>Informational only. Cash Flow never filters or totals by account.</summary>
        public int? CashAccountId { get; set; }
        /// <summary>Signed: positive in, negative out.</summary>
        public decimal Amount { get; set; }
        public decimal Inflow { get; set; }
        public decimal Outflow { get; set; }
    }

    public class CashFlowSummary
    {
        public decimal MoneyIn { get; set; }
        public decimal MoneyOut { get; set; }
        public decimal NetCashFlow { get; set; }

        /// <summary>
        /// Everything eligible that happened before the period opened. Measured
        /// from the same transactions, not read from an account balance.
        /// </summary>
        public decimal OpeningCash { get; set; }

        /// <summary>
        /// OpeningCash + MoneyIn - MoneyOut. True by construction.
        /// NOT the sum of cash account balances, and not expected to equal it --
        /// the gap between the two is what reconciliation exists to explain.
        /// </summary>
        public decimal ClosingCash { get; set; }

        public decimal OperatingIn { get; set; }
        public decimal OperatingOut { get; set; }
        public decimal FinancingIn { get; set; }
        public decimal FinancingOut { get; set; }

        public int MovementCount { get; set; }
    }

    public class CashFlowResponse
    {
        public string? FarmId { get; set; }
        public DateTime? FromDate { get; set; }
        public DateTime? ToDate { get; set; }
        public CashFlowSummary Summary { get; set; } = new();
        public List<CashFlowRow> Rows { get; set; } = new();
    }
}
