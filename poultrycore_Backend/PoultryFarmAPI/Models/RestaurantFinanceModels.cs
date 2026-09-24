// =============================================================================
// Restaurant finance (migration 323) -- read models and request bodies.
//
// Read models are filled by RestaurantFinanceService.ReadAll<T>, which matches a
// property to the function's result column by name, ignoring case
// (CashAccountId <- cashaccountid). Keep property names equal to the column
// names in 323 with the words capitalised, or the value silently stays default.
//
// Every class name is prefixed "Restaurant..." and unique across the API:
// Swagger keys schemas by class name, and a duplicate 500s the whole document.
// =============================================================================

namespace PoultryFarmAPIWeb.Models
{
    public class RestaurantCashAccount
    {
        public int CashAccountId { get; set; }
        public string Name { get; set; } = "";
        public string AccountType { get; set; } = "";
        public string? DefaultFor { get; set; }
        public decimal OpeningBalance { get; set; }
        public decimal CurrentBalance { get; set; }
        public decimal LedgerBalance { get; set; }
        public bool AllowNegative { get; set; }
        public bool IsActive { get; set; }
        public string? Notes { get; set; }
        public DateTime? LastCountedAt { get; set; }
        public decimal? LastCountedBalance { get; set; }
        public int? OpenShiftId { get; set; }
        public string? OpenShiftNumber { get; set; }
        public string? OpenShiftOpenedBy { get; set; }
        public DateTime? OpenShiftOpenedAt { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class RestaurantCashLedgerRow
    {
        public int CashTxnId { get; set; }
        public DateTime TxnDate { get; set; }
        public string TxnType { get; set; } = "";
        public string SourceType { get; set; } = "";
        public int? SourceId { get; set; }
        public decimal Amount { get; set; }
        public decimal RunningBalance { get; set; }
        public string? Description { get; set; }
        public int? ShiftId { get; set; }
        public int? ReversesId { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class RestaurantCashShift
    {
        public int ShiftId { get; set; }
        public string? ShiftNumber { get; set; }
        public int CashAccountId { get; set; }
        public string TillName { get; set; } = "";
        public string Status { get; set; } = "";
        public DateTime OpenedAt { get; set; }
        public string? OpenedBy { get; set; }
        public decimal OpeningFloat { get; set; }
        public decimal OpeningBalance { get; set; }
        public DateTime? ClosedAt { get; set; }
        public string? ClosedBy { get; set; }
        public decimal? ExpectedCash { get; set; }
        public decimal? CountedCash { get; set; }
        public decimal? Variance { get; set; }
        public decimal DropAmount { get; set; }
        public decimal? ClosingBalance { get; set; }
        public decimal CurrentBalance { get; set; }
        public decimal CashSales { get; set; }
        public string? Notes { get; set; }
        public string? CloseNotes { get; set; }
    }

    public class RestaurantShiftCloseResult
    {
        public decimal ExpectedCash { get; set; }
        public decimal CountedCash { get; set; }
        public decimal Variance { get; set; }
        public decimal DropAmount { get; set; }
        public decimal ClosingBalance { get; set; }
    }

    public class RestaurantZReportLine
    {
        public string Section { get; set; } = "";
        public string Label { get; set; } = "";
        public long TxnCount { get; set; }
        public decimal Amount { get; set; }
        public int SortOrder { get; set; }
    }

    public class RestaurantCashTransfer
    {
        public int TransferId { get; set; }
        public string? TransferNumber { get; set; }
        public int FromAccountId { get; set; }
        public string FromAccountName { get; set; } = "";
        public int ToAccountId { get; set; }
        public string ToAccountName { get; set; } = "";
        public decimal Amount { get; set; }
        public DateTime TransferDate { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = "";
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class RestaurantOwnerMoneyEntry
    {
        public int OwnerMoneyId { get; set; }
        public string? EntryNumber { get; set; }
        public string EntryType { get; set; } = "";
        public int CashAccountId { get; set; }
        public string AccountName { get; set; } = "";
        public decimal Amount { get; set; }
        public DateTime EntryDate { get; set; }
        public string? OwnerName { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = "";
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class RestaurantLoan
    {
        public int LoanId { get; set; }
        public string? LoanNumber { get; set; }
        public string LenderName { get; set; } = "";
        public decimal Principal { get; set; }
        public decimal AmountReceived { get; set; }
        public int? ReceivedAccountId { get; set; }
        public string? ReceivedAccountName { get; set; }
        public DateTime LoanDate { get; set; }
        public decimal? InterestRate { get; set; }
        public DateTime? DueDate { get; set; }
        public decimal OutstandingPrincipal { get; set; }
        public decimal PrincipalRepaid { get; set; }
        public decimal InterestPaid { get; set; }
        public decimal FeesPaid { get; set; }
        public string Status { get; set; } = "";
        public bool IsOverdue { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? CancelReason { get; set; }
    }

    public class RestaurantLoanPayment
    {
        public int LoanPaymentId { get; set; }
        public int LoanId { get; set; }
        public string? LoanNumber { get; set; }
        public string? LenderName { get; set; }
        public DateTime PaymentDate { get; set; }
        public int CashAccountId { get; set; }
        public string AccountName { get; set; } = "";
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public decimal FeeAmount { get; set; }
        public decimal TotalAmount { get; set; }
        public string Status { get; set; } = "";
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class RestaurantCashCount
    {
        public int CountId { get; set; }
        public int CashAccountId { get; set; }
        public string AccountName { get; set; } = "";
        public DateTime CountDate { get; set; }
        public decimal SystemBalance { get; set; }
        public decimal CountedBalance { get; set; }
        public decimal Difference { get; set; }
        public string Status { get; set; } = "";
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class RestaurantDailyClosingPreview
    {
        public DateTime ClosingDate { get; set; }
        public bool IsClosed { get; set; }
        public DateTime? LastClosedDate { get; set; }
        public long OrderCount { get; set; }
        public decimal NetSales { get; set; }
        public decimal Discounts { get; set; }
        public decimal TaxCollected { get; set; }
        public decimal ServiceCharge { get; set; }
        public decimal DeliveryFees { get; set; }
        public decimal Refunds { get; set; }
        public decimal Tips { get; set; }
        public decimal TakingsCash { get; set; }
        public decimal TakingsCard { get; set; }
        public decimal TakingsMobile { get; set; }
        public decimal TakingsGiftCard { get; set; }
        public decimal TakingsOther { get; set; }
        public decimal Expenses { get; set; }
        public decimal MoneyIn { get; set; }
        public decimal MoneyOut { get; set; }
        public decimal CashVariance { get; set; }
        public long OpenShifts { get; set; }
        public long OpenOrders { get; set; }
        public long UnpaidOrders { get; set; }
    }

    public class RestaurantDailyClosing
    {
        public int ClosingId { get; set; }
        public DateTime ClosingDate { get; set; }
        public string Status { get; set; } = "";
        public int OrderCount { get; set; }
        public decimal NetSales { get; set; }
        public decimal TaxCollected { get; set; }
        public decimal MoneyIn { get; set; }
        public decimal MoneyOut { get; set; }
        public decimal CashVariance { get; set; }
        public string? Notes { get; set; }
        public string? ClosedBy { get; set; }
        public DateTime ClosedAt { get; set; }
        public string? ReopenedBy { get; set; }
        public DateTime? ReopenedAt { get; set; }
        public string? ReopenReason { get; set; }
    }

    public class RestaurantPnlLine
    {
        public string Section { get; set; } = "";
        public string LineKey { get; set; } = "";
        public string Label { get; set; } = "";
        public decimal Amount { get; set; }
        public int SortOrder { get; set; }
    }

    // ---- migration 324: report reads ----------------------------------------

    /// <summary>One account's position over a period. Opening + in - out + transfers in - transfers out = closing.</summary>
    public class RestaurantLedgerPeriodRow
    {
        public int CashAccountId { get; set; }
        public string Name { get; set; } = "";
        public string AccountType { get; set; } = "";
        public bool IsActive { get; set; }
        public decimal OpeningBalance { get; set; }
        public decimal MoneyIn { get; set; }
        public decimal MoneyOut { get; set; }
        public decimal TransfersIn { get; set; }
        public decimal TransfersOut { get; set; }
        public decimal ClosingBalance { get; set; }
        public decimal CurrentBalance { get; set; }
        public decimal LedgerBalance { get; set; }
        public long TxnCount { get; set; }
        public DateTime? LastCountedAt { get; set; }
        public decimal? LastCountedBalance { get; set; }
    }

    /// <summary>A ledger row across accounts; RunningBalance is that account's.</summary>
    public class RestaurantLedgerRow
    {
        public int CashTxnId { get; set; }
        public DateTime TxnDate { get; set; }
        public int CashAccountId { get; set; }
        public string AccountName { get; set; } = "";
        public string TxnType { get; set; } = "";
        public string SourceType { get; set; } = "";
        public int? SourceId { get; set; }
        public decimal Amount { get; set; }
        public decimal RunningBalance { get; set; }
        public bool IsInternal { get; set; }
        public string? Description { get; set; }
        public int? ShiftId { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class RestaurantTakingsByAccountRow
    {
        public string AccountName { get; set; } = "";
        public string AccountType { get; set; } = "";
        public string PaymentMethod { get; set; } = "";
        public long PaymentCount { get; set; }
        public decimal Takings { get; set; }
        public decimal Tips { get; set; }
        public decimal Refunds { get; set; }
        public decimal NetTotal { get; set; }
    }

    public class RestaurantCashBridgeLine
    {
        public int SortOrder { get; set; }
        public string LineKey { get; set; } = "";
        public string Label { get; set; } = "";
        public decimal Amount { get; set; }
        public string Kind { get; set; } = "";
        public string? Explanation { get; set; }
    }

    // ---- request bodies -----------------------------------------------------

    public class RestaurantCashAccountCreateRequest
    {
        public string FarmId { get; set; } = "";
        public string Name { get; set; } = "";
        public string AccountType { get; set; } = "CashBox";
        public decimal OpeningBalance { get; set; }
        public bool AllowNegative { get; set; }
        public string? DefaultFor { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantCashAccountUpdateRequest
    {
        public string Name { get; set; } = "";
        public string AccountType { get; set; } = "CashBox";
        public bool AllowNegative { get; set; }
        public bool IsActive { get; set; } = true;
        public string? DefaultFor { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantShiftOpenRequest
    {
        public int TillAccountId { get; set; }
        public decimal OpeningFloat { get; set; }
        public int? FloatFromAccountId { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantShiftCloseRequest
    {
        public decimal CountedCash { get; set; }
        public decimal DropAmount { get; set; }
        public int? DropToAccountId { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantTransferRequest
    {
        public int FromAccountId { get; set; }
        public int ToAccountId { get; set; }
        public decimal Amount { get; set; }
        public DateTime? TransferDate { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantReverseRequest
    {
        public string Reason { get; set; } = "";
    }

    public class RestaurantOwnerMoneyRequest
    {
        public string EntryType { get; set; } = "Contribution";
        public int CashAccountId { get; set; }
        public decimal Amount { get; set; }
        public DateTime? EntryDate { get; set; }
        public string? OwnerName { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantLoanCreateRequest
    {
        public string LenderName { get; set; } = "";
        public decimal Principal { get; set; }
        public decimal AmountReceived { get; set; }
        public int? ReceivedAccountId { get; set; }
        public DateTime? LoanDate { get; set; }
        public decimal? InterestRate { get; set; }
        public DateTime? DueDate { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantLoanRepayRequest
    {
        public int CashAccountId { get; set; }
        public decimal Principal { get; set; }
        public decimal Interest { get; set; }
        public decimal Fees { get; set; }
        public DateTime? PaymentDate { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantCashCountRequest
    {
        public int CashAccountId { get; set; }
        public decimal Counted { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantDayCloseRequest
    {
        public DateTime ClosingDate { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantDayReopenRequest
    {
        public DateTime ClosingDate { get; set; }
        public string Reason { get; set; } = "";
    }

    public class RestaurantRefundRequest
    {
        public decimal Amount { get; set; }
        public string PaymentMethod { get; set; } = "Cash";
        public string Reason { get; set; } = "";
        public int? CashAccountId { get; set; }
        public int? ShiftId { get; set; }
    }
}
