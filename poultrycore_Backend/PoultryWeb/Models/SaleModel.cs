namespace PoultryWeb.Models
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
        public DateTime CreatedDate { get; set; }
    }
}
