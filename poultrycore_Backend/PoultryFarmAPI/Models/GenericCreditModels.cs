namespace PoultryFarmAPIWeb.Models
{
    public class GenericCustomerCreditModel
    {
        public int GenericCustomerCreditId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int GenericCustomerId { get; set; }
        public string? CustomerName { get; set; }
        public string CreditType { get; set; } = "Overpayment";
        public decimal Amount { get; set; }
        public decimal RemainingBalance { get; set; }
        public DateTime CreditDate { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = "Active";
        public DateTime CreatedAt { get; set; }
    }

    public class GenericCustomerCreditCreateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int GenericCustomerId { get; set; }
        public string CreditType { get; set; } = "Overpayment";
        public decimal Amount { get; set; }
        public DateTime? CreditDate { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericSupplierCreditModel
    {
        public int GenericSupplierCreditId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int GenericSupplierId { get; set; }
        public string? SupplierName { get; set; }
        public string CreditType { get; set; } = "Advance";
        public decimal Amount { get; set; }
        public decimal RemainingBalance { get; set; }
        public DateTime CreditDate { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = "Active";
        public DateTime CreatedAt { get; set; }
    }

    public class GenericSupplierCreditCreateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int GenericSupplierId { get; set; }
        public string CreditType { get; set; } = "Advance";
        public decimal Amount { get; set; }
        public DateTime? CreditDate { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericDeferredCostRow
    {
        public int GenericProductId { get; set; }
        public string ProductName { get; set; } = string.Empty;
        public decimal TotalPurchased { get; set; }
        public decimal TotalSoldCost { get; set; }
        public decimal DeferredBalance { get; set; }
        public decimal CurrentStock { get; set; }
    }
}
