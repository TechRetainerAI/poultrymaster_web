// Restaurant suppliers, purchases, supplier payments and deferred inventory cost
// (migration 329). Supplier Balances / Supplier Payments reuse the shared
// BalanceModels DTOs, so the JSON contract is the one Poultry and Water answer.
// Names here are prefixed "Restaurant" so no nested/duplicate DTO name can clash
// in the Swagger document.

namespace PoultryFarmAPIWeb.Models
{
    public class RestaurantPurchaseCreateRequest
    {
        public int IngredientId { get; set; }
        public decimal Quantity { get; set; }
        public decimal TotalCost { get; set; }
        public DateTime? PurchaseDate { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public string? PaymentMethod { get; set; }
        /// <summary>Null = paid in full (or nothing, for Credit).</summary>
        public decimal? AmountPaid { get; set; }
        public int? CashAccountId { get; set; }
        public DateTime? DueDate { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantPurchaseReverseRequest
    {
        public string? Reason { get; set; }
    }

    public class RestaurantPurchase
    {
        public int PurchaseId { get; set; }
        public DateTime PurchaseDate { get; set; }
        public int IngredientId { get; set; }
        public string? IngredientName { get; set; }
        public string? Category { get; set; }
        public string? Unit { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public decimal Quantity { get; set; }
        public decimal UnitCost { get; set; }
        public decimal TotalCost { get; set; }
        public string? PaymentMethod { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Allocated { get; set; }
        public decimal Balance { get; set; }
        public string? PaymentStatus { get; set; }
        public DateTime? DueDate { get; set; }
        public int? CashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public string? CostMode { get; set; }
        public decimal RemainingQuantity { get; set; }
        public decimal DeferredTotalCost { get; set; }
        public decimal DeferredRemainingCost { get; set; }
        public string? Notes { get; set; }
        public string? Status { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class RestaurantCostMode
    {
        public string Category { get; set; } = "";
        public string CostMode { get; set; } = "EXPENSE_WHEN_PURCHASED";
        public int IngredientCount { get; set; }
        public bool IsConfigured { get; set; }
        public string? UpdatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class RestaurantCostModeRequest
    {
        public string Category { get; set; } = "";
        public string CostMode { get; set; } = "";
    }

    public class RestaurantDeferredPurchase
    {
        public int PurchaseId { get; set; }
        public DateTime PurchaseDate { get; set; }
        public int IngredientId { get; set; }
        public string? ItemName { get; set; }
        public string? Category { get; set; }
        public string? Unit { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public decimal PurchasedQuantity { get; set; }
        public decimal ConsumedQuantity { get; set; }
        public decimal RemainingQuantity { get; set; }
        public decimal OperationalCost { get; set; }
        public decimal DeferredTotalCost { get; set; }
        public decimal RecognizedCost { get; set; }
        public decimal DeferredRemainingCost { get; set; }
        public decimal RecognitionPercent { get; set; }
        public decimal AllocatedRecognizedCost { get; set; }
        public decimal RecognitionDrift { get; set; }
        public string? CostRecognitionMethod { get; set; }
        public string? RecognitionMethodLabel { get; set; }
        public string? Status { get; set; }
        public string? ExceptionReason { get; set; }
        public int RecognitionEvents { get; set; }
        public DateTime? LastRecognitionDate { get; set; }
        public string? CostingMethod { get; set; }
        public int? QueuePosition { get; set; }
        public decimal QuantityAheadInQueue { get; set; }
    }

    public class RestaurantDeferredSummary
    {
        public decimal RemainingDeferredCost { get; set; }
        public decimal RecognizedCost { get; set; }
        public decimal DeferredBasis { get; set; }
        public decimal OperationalCost { get; set; }
        public int PurchaseCount { get; set; }
        public int DeferredPurchases { get; set; }
        public int FullyRecognized { get; set; }
        public int NotRecognized { get; set; }
        public int Exceptions { get; set; }
        public decimal ExceptionDrift { get; set; }
        public decimal RecognitionPercent { get; set; }
        public int BlockedPurchases { get; set; }
        public decimal BlockedCost { get; set; }
    }

    public class RestaurantDeferredResponse
    {
        public RestaurantDeferredSummary Summary { get; set; } = new();
        public List<RestaurantDeferredPurchase> Purchases { get; set; } = new();
    }

    public class RestaurantDeferredHistory
    {
        public int DrawId { get; set; }
        public DateTime UsedDate { get; set; }
        public string? SourceType { get; set; }
        public string? SourceLabel { get; set; }
        public decimal QuantityDrawn { get; set; }
        public string? Unit { get; set; }
        public decimal UnitCostAtDraw { get; set; }
        public decimal OperationalCost { get; set; }
        public decimal RecognizedCost { get; set; }
        public string? RecognitionOutcome { get; set; }
        public bool IsReversed { get; set; }
    }

    public class RestaurantExpensePayment
    {
        public int ExpenseId { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }
        public string? PaymentStatus { get; set; }
        public DateTime? DueDate { get; set; }
        /// <summary>Migration 337: paid when the expense was recorded (what Edit changes).</summary>
        public decimal PaidAtEntry { get; set; }
        /// <summary>Migration 337: settled by supplier payments.</summary>
        public decimal Allocated { get; set; }
        /// <summary>Migration 337: the account its payment came out of, if any.</summary>
        public int? CashAccountId { get; set; }
    }

    public class RestaurantSupplierUpdateRequest
    {
        public string FarmId { get; set; } = "";
        public string Name { get; set; } = "";
        public string? ContactName { get; set; }
        public string? Phone { get; set; }
        public string? Email { get; set; }
        public string? Address { get; set; }
        public string? Category { get; set; }
        public string? Notes { get; set; }
        public bool IsActive { get; set; } = true;
    }
}
