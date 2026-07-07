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
        public int? FlockId { get; set; }
        public string? SaleDescription { get; set; }
        public bool Paid { get; set; } = true;
        /// <summary>Running total of payments recorded against this sale (migration 145).</summary>
        public decimal AmountPaid { get; set; }
        /// <summary>Egg size (Inside / Tee / Serum / Small / Medium / etc.). Nullable; required only for egg sales tracked by size.</summary>
        public string? Size { get; set; }
        /// <summary>Optional cash account this sale is received into (posts a cash-in when the sale is paid).</summary>
        public int? PoultryCashAccountId { get; set; }
        public DateTime CreatedDate { get; set; }

    }
}
