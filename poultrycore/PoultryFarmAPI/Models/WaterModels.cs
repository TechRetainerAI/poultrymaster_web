using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public class WaterProductModel
    {
        [Key]
        public int WaterProductId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(150)]
        public string Name { get; set; } = string.Empty;

        [StringLength(60)]
        public string? Sku { get; set; }

        public int? SizeMl { get; set; }

        [StringLength(30)]
        public string? Unit { get; set; }

        [Range(0, double.MaxValue)]
        public decimal UnitPrice { get; set; }

        public bool IsActive { get; set; } = true;

        // Migration 063: classifies products so finished goods are surfaced in
        // sales/production, while raw/packaging materials power recipes only.
        // Values: FinishedGood | RawMaterial | PackagingMaterial | Other.
        [StringLength(30)]
        public string ProductType { get; set; } = "FinishedGood";

        [StringLength(500)]
        public string? Notes { get; set; }

        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Computed by spWaterProduct_GetById / GetAll
        public int StockOnHand { get; set; }

        // Migration 084: sachet-water support.
        // BaseUnit is the smallest sellable unit (e.g. 'Sachet'). When
        // IsSachetProduct=1, stock and sale-line BaseQuantity are stored in
        // sachets so the same product can be sold by bag or by sachet without
        // decimal drift.
        [StringLength(20)] public string? BaseUnit { get; set; }
        public int?     SachetsPerBag { get; set; }
        public decimal? BagPrice      { get; set; }
        public decimal? SachetPrice   { get; set; }
        public bool     IsSachetProduct { get; set; }
    }

    public class WaterCustomerModel
    {
        [Key]
        public int WaterCustomerId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(150)]
        public string Name { get; set; } = string.Empty;

        [StringLength(50)]
        public string? ContactPhone { get; set; }

        [EmailAddress]
        [StringLength(150)]
        public string? ContactEmail { get; set; }

        [StringLength(300)]
        public string? Address { get; set; }

        [StringLength(100)]
        public string? City { get; set; }

        [StringLength(500)]
        public string? Notes { get; set; }

        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }

        public decimal OutstandingBalance { get; set; }

        // Migration 082: system-managed default customers used as the posting
        // target for Summary-only delivery sales and walk-in / unassigned-credit
        // sales. The delete SP refuses to remove rows where IsSystemGenerated=1.
        [StringLength(40)] public string? CustomerType        { get; set; }
        [StringLength(40)] public string? DefaultCustomerType { get; set; }
        public bool IsDefaultCustomer { get; set; }
        public bool IsSystemGenerated { get; set; }
        public bool IsActive { get; set; } = true;
    }

    // Returned by spWaterCustomer_CreateDefaults — one row per default type.
    public class WaterDefaultCustomerResult
    {
        public int    WaterCustomerId     { get; set; }
        public string DefaultCustomerType { get; set; } = string.Empty;
        public string Name                { get; set; } = string.Empty;
        public bool   WasCreated          { get; set; }
    }

    public class WaterStockTransactionModel
    {
        [Key]
        public int StockTxnId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        public int WaterProductId { get; set; }

        public string? ProductName { get; set; }

        [Required]
        [StringLength(30)]
        public string TxnType { get; set; } = "Restock"; // 'Restock' | 'Adjust' | 'Sale' | 'Return'

        public int Quantity { get; set; }

        public decimal? UnitCost { get; set; }

        public int? RelatedSaleId { get; set; }

        [StringLength(300)]
        public string? Note { get; set; }

        public DateTime CreatedDate { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class WaterSaleItemModel
    {
        public int WaterSaleItemId { get; set; }
        public int WaterSaleId { get; set; }

        [Required]
        public int WaterProductId { get; set; }

        public string? ProductName { get; set; }

        [Range(1, int.MaxValue)]
        public int Quantity { get; set; }

        [Range(0, double.MaxValue)]
        public decimal UnitPrice { get; set; }

        public decimal LineTotal { get; set; }

        // Migration 084: 'Bag' | 'Sachet' (free-text so future units don't need
        // a model change). BaseQuantity is the equivalent in BaseUnit (sachets
        // for sachet products) and powers stock deductions.
        [StringLength(20)] public string? SellingUnit  { get; set; }
        [StringLength(20)] public string? BaseUnit     { get; set; }
        public decimal? BaseQuantity { get; set; }
    }

    public class WaterSaleModel
    {
        [Key]
        public int WaterSaleId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int? WaterCustomerId { get; set; }
        public string? CustomerName { get; set; }

        public DateTime SaleDate { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }

        [StringLength(30)]
        public string Status { get; set; } = "Pending";

        [StringLength(500)]
        public string? Notes { get; set; }

        public DateTime CreatedDate { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? UpdatedDate { get; set; }

        // Populated by GetById / Create
        public List<WaterSaleItemModel> Items { get; set; } = new();
    }

    // Request payload for POST /api/WaterSale
    public class CreateWaterSaleRequest
    {
        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int? WaterCustomerId { get; set; }

        public DateTime? SaleDate { get; set; }

        [StringLength(500)]
        public string? Notes { get; set; }

        public string? CreatedBy { get; set; }

        [Required]
        [MinLength(1)]
        public List<WaterSaleItemModel> Items { get; set; } = new();
    }

    public class WaterPaymentModel
    {
        [Key]
        public int WaterPaymentId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        public int WaterSaleId { get; set; }

        [Range(0.01, double.MaxValue)]
        public decimal Amount { get; set; }

        [StringLength(40)]
        public string? PaymentMethod { get; set; }

        public DateTime PaymentDate { get; set; }

        [StringLength(120)]
        public string? Reference { get; set; }

        [StringLength(300)]
        public string? Note { get; set; }

        public DateTime CreatedDate { get; set; }
        public string? CreatedBy { get; set; }
        public string? CustomerName { get; set; }
    }

    public class WaterDashboardSummaryModel
    {
        public int ActiveProducts { get; set; }
        public int TotalCustomers { get; set; }
        public int TotalStockOnHand { get; set; }
        public decimal SalesToday { get; set; }
        public decimal SalesThisMonth { get; set; }
        public decimal OutstandingReceivables { get; set; }
    }
}
