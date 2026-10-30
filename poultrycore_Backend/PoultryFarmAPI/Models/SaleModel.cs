namespace PoultryFarmAPIWeb.Models
{
    public class SaleModel
    {
        public string FarmId { get; set; }
        public string UserId { get; set; }
        public int SaleId { get; set; }
        public DateTime SaleDate { get; set; }
        public string Product { get; set; } = string.Empty;
        public decimal Quantity { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal TotalAmount { get; set; }
        public string? PaymentMethod { get; set; }
        public string? CustomerName { get; set; }
        /// <summary>
        /// Link to Customer (migration 223). Optional on the way in: when it is
        /// null the SP resolves it from CustomerName, creating the customer if
        /// that name is new -- so a sale entered the old way still lands on the
        /// Customer Balances page. A blank name means a walk-in and stays null.
        /// </summary>
        public int? CustomerId { get; set; }
        public int? FlockId { get; set; }
        /// <summary>
        /// 366: the bird batch the sale is attributed to. Optional. A flock
        /// implies its own batch (set by the database); this is for a sale
        /// attributed to a batch without one flock.
        /// </summary>
        public int? BatchId { get; set; }
        public string? SaleDescription { get; set; }
        public bool Paid { get; set; } = true;
        /// <summary>Running total of payments recorded against this sale (migration 145).</summary>
        public decimal AmountPaid { get; set; }
        /// <summary>Egg size (Inside / Tee / Serum / Small / Medium / etc.). Nullable; required only for egg sales tracked by size.</summary>
        public string? Size { get; set; }
        /// <summary>Optional cash account this sale is received into (posts a cash-in when the sale is paid).</summary>
        public int? PoultryCashAccountId { get; set; }
        /// <summary>
        /// Egg class sold (migration 341): a sized egg product id, or 0 for
        /// Unsorted / General. On an edit, null means "leave the class as it
        /// is". Read back as null for Unsorted. Stock is deducted from this
        /// class only, and a delete restores the same class.
        /// </summary>
        public int? EggProductId { get; set; }
        /// <summary>Sale number shared by the lines of one multi-size sale (SG-00001).</summary>
        public string? SaleGroupNo { get; set; }
        public DateTime CreatedDate { get; set; }

        // ---- 351: posted sales are immutable; a wrong one is reversed ----
        /// <summary>Posted | Reversed. A sale posts when it is saved.</summary>
        public string Status { get; set; } = "Posted";
        public DateTime? ReversedAt { get; set; }
        public string? ReversedBy { get; set; }
        public string? ReversalReason { get; set; }
        public int? SaleReversalId { get; set; }
        /// <summary>On a corrected sale: the reversed sale it replaces. Sent on create to link them.</summary>
        public int? CorrectsSaleId { get; set; }
        /// <summary>On a reversed sale: the sale that corrected it, if any.</summary>
        public int? CorrectedBySaleId { get; set; }

        // ---- 358: one sale, many lines ----
        /// <summary>Number of lines in the sale (1 for an ordinary sale).</summary>
        public int LineCount { get; set; } = 1;
        /// <summary>What was sold inside the sale, in entry order. Read-only: lines are written when the sale posts.</summary>
        public List<SaleLineModel> Lines { get; set; } = new();
    }

    /// <summary>One product / egg class inside a sale (migration 358). Not a sale of its own.</summary>
    public class SaleLineModel
    {
        public int SaleLineId { get; set; }
        public int LineNo { get; set; }
        public string Product { get; set; } = string.Empty;
        /// <summary>Egg class sold on this line; null = Unsorted / General.</summary>
        public int? EggProductId { get; set; }
        public string? Size { get; set; }
        public decimal Quantity { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal TotalAmount { get; set; }
    }

    /// <summary>POST api/Sale/{id}/reverse.</summary>
    public class SaleReverseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string? UserId { get; set; }
        /// <summary>Wrong customer, Wrong quantity, Wrong price, Duplicate sale, Wrong product, Entered by mistake, Other.</summary>
        public string? ReasonCode { get; set; }
        public string Reason { get; set; } = string.Empty;
        /// <summary>What to do with each payment: key = payment group id (or "AT-SALE"), value = KeepAsCredit | ReversePayment.</summary>
        public Dictionary<string, string>? PaymentHandling { get; set; }
        /// <summary>The preview's fingerprint; the reversal is refused if the sale changed since.</summary>
        public string? ExpectedFingerprint { get; set; }
        /// <summary>A retried request returns the reversal it already made.</summary>
        public string? IdempotencyKey { get; set; }
    }

    /// <summary>POST api/Poultry/customer-payments/apply-credit.</summary>
    public class CustomerCreditApplyRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int CustomerId { get; set; }
        public int SaleId { get; set; }
        public decimal Amount { get; set; }
        public string? CreatedBy { get; set; }
    }

    /// <summary>POST api/Poultry/customer-payments/refunds.</summary>
    public class CustomerRefundRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int CustomerId { get; set; }
        public decimal Amount { get; set; }
        public int PoultryCashAccountId { get; set; }
        public string? PaymentMethod { get; set; }
        public DateTime? RefundDate { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
        /// <summary>367: refund out of this one credit (a payment row). Null = oldest credit first.</summary>
        public int? PoultryPaymentId { get; set; }
    }

    /// <summary>
    /// 369: a customer debt -- what a customer owes WITHOUT a sale (owed before
    /// the system, historical, external, migration, adjustment). No sale, no
    /// revenue, no stock, no cash. Paid through the ordinary customer payment.
    /// </summary>
    public class CustomerDebtRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int CustomerId { get; set; }
        public decimal Amount { get; set; }
        public DateTime? DebtDate { get; set; }
        /// <summary>OpeningBalance | HistoricalDebt | Adjustment | Migration | ExternalTransaction | Other</summary>
        public string EntryType { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class CustomerDebtReverseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
        public string? ReversedBy { get; set; }
    }

    public class CustomerDebtRow
    {
        public int DebtId { get; set; }
        public string DebtNumber { get; set; } = string.Empty;
        public int CustomerId { get; set; }
        public string? CustomerName { get; set; }
        public decimal Amount { get; set; }
        public decimal Paid { get; set; }
        public decimal Balance { get; set; }
        public DateTime? DebtDate { get; set; }
        public string EntryType { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = "Posted";
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    /// <summary>367: reverse a refund entered by mistake (or money returned).</summary>
    public class CustomerRefundReverseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
        public string? ReversedBy { get; set; }
    }

    /// <summary>367: one credit event -- a payment row that holds or held customer credit.</summary>
    public class CustomerCreditEventRow
    {
        public int PoultryPaymentId { get; set; }
        public Guid? PaymentGroupId { get; set; }
        public string? PaymentNumber { get; set; }
        public DateTime? CreditDate { get; set; }
        public int CustomerId { get; set; }
        public string? CustomerName { get; set; }
        public string Source { get; set; } = string.Empty;
        public string? SourceType { get; set; }
        public int? SaleId { get; set; }
        public string? SaleGroupNo { get; set; }
        public string? Reference { get; set; }
        public decimal OriginalAmount { get; set; }
        public decimal Applied { get; set; }
        public decimal Refunded { get; set; }
        public decimal Available { get; set; }
        public string Status { get; set; } = string.Empty;
        /// <summary>Added by hand (opening credit, advance, credit note): reversed from Customer Credits.</summary>
        public bool IsManual { get; set; }
        public int? PoultryCashAccountId { get; set; }
    }

    /// <summary>
    /// 363: credit created by hand -- an opening balance, a deposit (real cash
    /// in) or a credit note (a cost). Never a typed balance.
    /// </summary>
    public class ManualCreditRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int CustomerId { get; set; }
        /// <summary>OpeningCredit | Deposit | CreditNote</summary>
        public string Kind { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public DateTime? CreditDate { get; set; }
        /// <summary>Deposit only: the account the money was received into.</summary>
        public int? PoultryCashAccountId { get; set; }
        public string? PaymentMethod { get; set; }
        public string? Reference { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
    }

    public class ManualCreditReverseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
        public string? ReversedBy { get; set; }
    }

    public class ManualCreditRow
    {
        public Guid PaymentGroupId { get; set; }
        public int PoultryPaymentId { get; set; }
        public string? PaymentNumber { get; set; }
        public string Kind { get; set; } = string.Empty;
        public DateTime? CreditDate { get; set; }
        public int CustomerId { get; set; }
        public string? CustomerName { get; set; }
        public decimal Amount { get; set; }
        public decimal Used { get; set; }
        public decimal Refunded { get; set; }
        public decimal Remaining { get; set; }
        public string Status { get; set; } = "Posted";
        public int? PoultryCashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public string? PaymentMethod { get; set; }
        public string? Reference { get; set; }
        public string? Reason { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class CustomerCreditRow
    {
        public int PoultryPaymentId { get; set; }
        public Guid? PaymentGroupId { get; set; }
        public string? PaymentNumber { get; set; }
        public DateTime? PaymentDate { get; set; }
        public decimal Amount { get; set; }
        public decimal Unapplied { get; set; }
        public string? SourceType { get; set; }
        public int SaleId { get; set; }
        public string? SaleStatus { get; set; }
        public int? PoultryCashAccountId { get; set; }
    }

    public class CustomerCreditSummaryRow
    {
        public int CustomerId { get; set; }
        public string CustomerName { get; set; } = string.Empty;
        public decimal AvailableCredit { get; set; }
        public int PaymentCount { get; set; }
        /// <summary>What the customer still owes on active sales -- shown beside the credit, never netted.</summary>
        public decimal Outstanding { get; set; }
    }

    public class CustomerRefundRow
    {
        public int RefundId { get; set; }
        public string RefundNumber { get; set; } = string.Empty;
        public int CustomerId { get; set; }
        public string? CustomerName { get; set; }
        public decimal Amount { get; set; }
        public DateTime RefundDate { get; set; }
        public int PoultryCashAccountId { get; set; }
        public string? AccountName { get; set; }
        public string? PaymentMethod { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string Status { get; set; } = "Posted";
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? PaymentNumbers { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversedBy { get; set; }
        public string? ReversalReason { get; set; }
        public DateTime? ReversalDate { get; set; }
    }
}
