namespace PoultryFarmAPIWeb.Models
{
    public class ExpenseModel
    {
        public string? FarmId { get; set; }
        public string UserId { get; set; } = string.Empty;
        public int ExpenseId { get; set; }
        public DateTime ExpenseDate { get; set; }
        public string Category { get; set; } = string.Empty;
        public string? Description { get; set; }
        public decimal Amount { get; set; }
        public string? PaymentMethod { get; set; }
        public int? FlockId { get; set; }
        public DateTime CreatedDate { get; set; }
        public string? Supplier { get; set; }

        /// <summary>The supplier this expense is owed to. Free-text
        /// <see cref="Supplier"/> stays the display name; this is what makes the
        /// row a payable — without it the expense can still be unpaid, it simply
        /// has nobody to owe, so it never reaches Supplier Balances.</summary>
        public int? SupplierId { get; set; }

        /// <summary>Read-only, resolved from SupplierId.</summary>
        public string? SupplierName { get; set; }

        /// <summary>Cash actually paid against this expense.
        ///
        /// NULL on the way IN means "paid in full" — the shape every row written
        /// before migration 238 has, and the shape every SP that does not know
        /// about payment state still writes. On the way OUT it is always
        /// resolved, so a reader can never mistake "paid in full" for "paid
        /// nothing".</summary>
        public decimal? AmountPaid { get; set; }

        /// <summary>Read-only: Amount - AmountPaid, never negative.</summary>
        public decimal Balance { get; set; }

        /// <summary>Read-only, generated in SQL: Paid | PartiallyPaid | Unpaid |
        /// NonCash. Derived from the amounts, so it cannot disagree with them.</summary>
        public string? PaymentStatus { get; set; }

        /// <summary>When the supplier expects to be paid. Beats the supplier's
        /// default payment terms on Supplier Balances where it is set.</summary>
        public DateTime? DueDate { get; set; }

        /// <summary>Read-only: which workflow created this row (Payroll,
        /// PoultryInternalUsage, PoultryRawMaterialPurchase, …). NULL means it was
        /// entered by hand on the Expenses page.</summary>
        public string? SourceType { get; set; }

        public int? SourceId { get; set; }

        /// <summary>Optional cash account this expense is paid from. When set, a
        /// CashOut is posted to that PoultryCashAccount (reversed on edit/delete).</summary>
        public int? PoultryCashAccountId { get; set; }

        /// <summary>Optional receipt image. JSON: base64 string.</summary>
        public byte[]? AttachmentImage { get; set; }

        public string? AttachmentContentType { get; set; }

        public bool HasAttachmentImage { get; set; }

        /// <summary>When true on PUT, attachment columns are updated or cleared.</summary>
        public bool SetAttachmentImage { get; set; }
    }
}
