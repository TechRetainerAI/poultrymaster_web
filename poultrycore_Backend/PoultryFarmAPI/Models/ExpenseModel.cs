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

        /// <summary>Optional receipt image. JSON: base64 string.</summary>
        public byte[]? AttachmentImage { get; set; }

        public string? AttachmentContentType { get; set; }

        public bool HasAttachmentImage { get; set; }

        /// <summary>When true on PUT, attachment columns are updated or cleared.</summary>
        public bool SetAttachmentImage { get; set; }
    }
}
