using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Restaurant Management System Models — Phase R1: Setup + Menu
    // =========================================================================

    // ---- Profile ----

    public class RestaurantProfileModel
    {
        [Key]
        public int RestaurantProfileId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(200)]
        public string RestaurantName { get; set; } = string.Empty;

        [StringLength(500)]
        public string? Address { get; set; }

        [StringLength(100)]
        public string? City { get; set; }

        [StringLength(100)]
        public string? Country { get; set; }

        [StringLength(50)]
        public string? Phone { get; set; }

        [StringLength(200)]
        public string? Email { get; set; }

        [StringLength(100)]
        public string? CuisineType { get; set; }

        [StringLength(200)]
        public string? ServiceTypes { get; set; }

        [StringLength(10)]
        public string OpeningTime { get; set; } = "08:00";

        [StringLength(10)]
        public string ClosingTime { get; set; } = "22:00";

        [StringLength(10)]
        public string DefaultCurrency { get; set; } = "GHS";

        public decimal TaxRate { get; set; }

        public decimal ServiceChargeRate { get; set; }

        [StringLength(50)]
        public string? TimeZone { get; set; }

        [StringLength(500)]
        public string? LogoUrl { get; set; }

        public string? Description { get; set; }

        public int SeatingCapacity { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ---- Menu Categories ----

    public class RestaurantMenuCategoryModel
    {
        [Key]
        public int MenuCategoryId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int? ParentCategoryId { get; set; }

        [Required]
        [StringLength(100)]
        public string Name { get; set; } = string.Empty;

        [StringLength(500)]
        public string? Description { get; set; }

        [StringLength(500)]
        public string? ImageUrl { get; set; }

        public int SortOrder { get; set; }

        public bool IsActive { get; set; } = true;

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ---- Menu Items ----

    public class RestaurantMenuItemModel
    {
        [Key]
        public int MenuItemId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int? MenuCategoryId { get; set; }
        public string? CategoryName { get; set; }

        [Required]
        [StringLength(200)]
        public string Name { get; set; } = string.Empty;

        public string? Description { get; set; }

        public decimal Price { get; set; }
        public decimal CostPrice { get; set; }

        [StringLength(500)]
        public string? ImageUrl { get; set; }

        public int PrepTime { get; set; }       // minutes
        public int? Calories { get; set; }
        public string? Allergens { get; set; }  // comma-separated

        [Range(0, 5)]
        public int SpicyLevel { get; set; }

        public bool IsVegetarian { get; set; }
        public bool IsVegan { get; set; }
        public bool IsGlutenFree { get; set; }
        public bool IsHalal { get; set; }
        public bool IsKosher { get; set; }
        public bool IsAvailable { get; set; } = true;
        public bool IsActive { get; set; } = true;

        public int SortOrder { get; set; }

        [StringLength(50)]
        public string? Sku { get; set; }

        [StringLength(50)]
        public string? Barcode { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ---- Modifier Groups ----

    public class RestaurantModifierGroupModel
    {
        [Key]
        public int ModifierGroupId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(100)]
        public string Name { get; set; } = string.Empty;

        [StringLength(500)]
        public string? Description { get; set; }

        public bool IsRequired { get; set; }

        public int MinSelections { get; set; }
        public int MaxSelections { get; set; } = 1;

        public int SortOrder { get; set; }
        public bool IsActive { get; set; } = true;

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ---- Modifiers ----

    public class RestaurantModifierModel
    {
        [Key]
        public int ModifierId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int ModifierGroupId { get; set; }
        public string? GroupName { get; set; }

        [Required]
        [StringLength(100)]
        public string Name { get; set; } = string.Empty;

        public decimal PriceAdjustment { get; set; }
        public bool IsDefault { get; set; }
        public bool IsAvailable { get; set; } = true;
        public int SortOrder { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ---- Menu Item <-> Modifier Group Junction ----

    public class RestaurantMenuItemModifierGroupModel
    {
        [Key]
        public int MenuItemModifierGroupId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int MenuItemId { get; set; }
        public int ModifierGroupId { get; set; }
        public string? GroupName { get; set; }
        public bool IsRequired { get; set; }
        public int MinSelections { get; set; }
        public int MaxSelections { get; set; }
        public int SortOrder { get; set; }
    }

    // ---- Combos / Meal Deals ----

    public class RestaurantComboModel
    {
        [Key]
        public int ComboId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(200)]
        public string Name { get; set; } = string.Empty;

        public string? Description { get; set; }

        public decimal Price { get; set; }

        [StringLength(500)]
        public string? ImageUrl { get; set; }

        public bool IsActive { get; set; } = true;
        public int SortOrder { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class RestaurantComboItemModel
    {
        [Key]
        public int ComboItemId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int ComboId { get; set; }
        public int? MenuItemId { get; set; }
        public string? MenuItemName { get; set; }
        public int? MenuCategoryId { get; set; }
        public string? CategoryName { get; set; }
        public int Quantity { get; set; } = 1;
        public int SortOrder { get; set; }
    }

    // ---- Menu Schedules ----

    public class RestaurantMenuScheduleModel
    {
        [Key]
        public int MenuScheduleId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(100)]
        public string Name { get; set; } = string.Empty;

        [Required]
        [StringLength(10)]
        public string StartTime { get; set; } = string.Empty;

        [Required]
        [StringLength(10)]
        public string EndTime { get; set; } = string.Empty;

        public string? DaysOfWeek { get; set; }

        public bool IsActive { get; set; } = true;

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class RestaurantMenuScheduleItemModel
    {
        [Key]
        public int MenuScheduleItemId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int MenuScheduleId { get; set; }
        public int MenuItemId { get; set; }
        public string? MenuItemName { get; set; }
        public decimal? OverridePrice { get; set; }
    }

    // ---- Item Tags ----

    public class RestaurantItemTagModel
    {
        [Key]
        public int ItemTagId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int MenuItemId { get; set; }

        [Required]
        [StringLength(50)]
        public string Tag { get; set; } = string.Empty;
    }

    // =========================================================================
    // Restaurant Management System Models — Phase R2: Floor Plan + POS
    // =========================================================================

    // ---- Floors ----

    public class RestaurantFloorModel
    {
        [Key]
        public int FloorId { get; set; }
        [Required]
        public string FarmId { get; set; } = string.Empty;
        [Required]
        [StringLength(100)]
        public string Name { get; set; } = string.Empty;
        public int FloorNumber { get; set; }
        public string? Description { get; set; }
        public bool IsActive { get; set; } = true;
        public int SortOrder { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public long TableCount { get; set; }
    }

    // ---- Tables ----

    public class RestaurantTableModel
    {
        [Key]
        public int TableId { get; set; }
        [Required]
        public string FarmId { get; set; } = string.Empty;
        public int? FloorId { get; set; }
        public string? FloorName { get; set; }
        [Required]
        [StringLength(20)]
        public string TableNumber { get; set; } = string.Empty;
        [StringLength(100)]
        public string? TableName { get; set; }
        public int Capacity { get; set; } = 4;
        [StringLength(20)]
        public string Shape { get; set; } = "Square";
        [StringLength(20)]
        public string Status { get; set; } = "Available";
        public int PositionX { get; set; }
        public int PositionY { get; set; }
        public int Width { get; set; } = 1;
        public int Height { get; set; } = 1;
        public bool IsActive { get; set; } = true;
        public int? CurrentOrderId { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ---- Orders ----

    public class RestaurantOrderModel
    {
        [Key]
        public int OrderId { get; set; }
        [Required]
        public string FarmId { get; set; } = string.Empty;
        public string OrderNumber { get; set; } = string.Empty;
        public string OrderType { get; set; } = "DineIn";
        public string Status { get; set; } = "Placed";
        public int? TableId { get; set; }
        public string? TableNumber { get; set; }
        public int? CustomerId { get; set; }
        public string? CustomerName { get; set; }
        public string? CustomerPhone { get; set; }
        public int Covers { get; set; } = 1;
        public decimal Subtotal { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal TaxAmount { get; set; }
        public decimal ServiceChargeAmount { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal PaidAmount { get; set; }
        public string PaymentStatus { get; set; } = "Unpaid";
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public string? ServedBy { get; set; }
        public string? CancelReason { get; set; }
        public string? RefundReason { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public DateTime? CompletedAt { get; set; }
        public long ItemCount { get; set; }
    }

    // ---- Order Items ----

    public class RestaurantOrderItemModel
    {
        [Key]
        public int OrderItemId { get; set; }
        [Required]
        public string FarmId { get; set; } = string.Empty;
        public int OrderId { get; set; }
        public int? MenuItemId { get; set; }
        public int? ComboId { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public int Quantity { get; set; } = 1;
        public decimal UnitPrice { get; set; }
        public decimal ModifierTotal { get; set; }
        public decimal LineTotal { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = "Pending";
        public int? SeatNumber { get; set; }
        public string? KdsStation { get; set; }
        public DateTime? SentToKitchenAt { get; set; }
        public DateTime? PrepStartedAt { get; set; }
        public DateTime? ReadyAt { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    // ---- Order Item Modifiers ----

    public class RestaurantOrderItemModifierModel
    {
        [Key]
        public int OrderItemModifierId { get; set; }
        [Required]
        public string FarmId { get; set; } = string.Empty;
        public int OrderItemId { get; set; }
        public int? ModifierId { get; set; }
        public string ModifierName { get; set; } = string.Empty;
        public decimal PriceAdjustment { get; set; }
        public int Quantity { get; set; } = 1;
    }

    // ---- Order Payments ----

    public class RestaurantOrderPaymentModel
    {
        [Key]
        public int OrderPaymentId { get; set; }
        [Required]
        public string FarmId { get; set; } = string.Empty;
        public int OrderId { get; set; }
        [Required]
        public string PaymentMethod { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public decimal TipAmount { get; set; }
        public string? Reference { get; set; }
        public string Status { get; set; } = "Completed";
        public string? ProcessedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    // ---- Discounts ----

    public class RestaurantDiscountModel
    {
        [Key]
        public int DiscountId { get; set; }
        [Required]
        public string FarmId { get; set; } = string.Empty;
        [Required]
        [StringLength(100)]
        public string Name { get; set; } = string.Empty;
        public string DiscountType { get; set; } = "Percentage";
        public decimal Value { get; set; }
        public string? CouponCode { get; set; }
        public bool IsAutoApply { get; set; }
        public decimal MinOrderAmount { get; set; }
        public decimal? MaxDiscountAmount { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ---- Order Discounts ----

    public class RestaurantOrderDiscountModel
    {
        [Key]
        public int OrderDiscountId { get; set; }
        [Required]
        public string FarmId { get; set; } = string.Empty;
        public int OrderId { get; set; }
        public int? DiscountId { get; set; }
        public string DiscountName { get; set; } = string.Empty;
        public string DiscountType { get; set; } = string.Empty;
        public decimal Value { get; set; }
        public decimal AppliedAmount { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    // ---- Request DTOs ----

    public class RestaurantOrderCreateRequest
    {
        [Required]
        public string FarmId { get; set; } = string.Empty;
        public string OrderType { get; set; } = "DineIn";
        public int? TableId { get; set; }
        public string? TableNumber { get; set; }
        public int? CustomerId { get; set; }
        public string? CustomerName { get; set; }
        public string? CustomerPhone { get; set; }
        public int Covers { get; set; } = 1;
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public string? ServedBy { get; set; }
    }

    public class RestaurantOrderItemCreateRequest
    {
        [Required]
        public string FarmId { get; set; } = string.Empty;
        public int OrderId { get; set; }
        public int? MenuItemId { get; set; }
        public int? ComboId { get; set; }
        [Required]
        public string ItemName { get; set; } = string.Empty;
        public int Quantity { get; set; } = 1;
        public decimal UnitPrice { get; set; }
        public string? Notes { get; set; }
        public int? SeatNumber { get; set; }
        public string? KdsStation { get; set; }
        public List<OrderItemModifierRequest>? Modifiers { get; set; }
    }

    public class OrderItemModifierRequest
    {
        public int? ModifierId { get; set; }
        public string ModifierName { get; set; } = string.Empty;
        public decimal PriceAdjustment { get; set; }
        public int Quantity { get; set; } = 1;
    }

    // =========================================================================
    // Restaurant Management System Models — Phase R3: KDS
    // =========================================================================

    public class RestaurantKdsStationModel
    {
        [Key]
        public int KdsStationId { get; set; }
        [Required]
        public string FarmId { get; set; } = string.Empty;
        [Required]
        [StringLength(100)]
        public string Name { get; set; } = string.Empty;
        [StringLength(10)]
        public string DisplayColor { get; set; } = "#3B82F6";
        public int SortOrder { get; set; }
        public bool IsExpo { get; set; }
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public long ItemCount { get; set; }
    }

    public class RestaurantKdsStationItemModel
    {
        [Key]
        public int KdsStationItemId { get; set; }
        [Required]
        public string FarmId { get; set; } = string.Empty;
        public int KdsStationId { get; set; }
        public int MenuItemId { get; set; }
        public string? MenuItemName { get; set; }
        public string? CategoryName { get; set; }
    }

    public class KdsQueueItemModel
    {
        public int OrderItemId { get; set; }
        public int OrderId { get; set; }
        public string OrderNumber { get; set; } = string.Empty;
        public string OrderType { get; set; } = string.Empty;
        public string? TableNumber { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = string.Empty;
        public int? SeatNumber { get; set; }
        public string? KdsStation { get; set; }
        public DateTime? SentToKitchenAt { get; set; }
        public DateTime? PrepStartedAt { get; set; }
        public DateTime? ReadyAt { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? Modifiers { get; set; }
        public double ElapsedMinutes { get; set; }
    }

    public class KdsStatsModel
    {
        public long PendingCount { get; set; }
        public long PreparingCount { get; set; }
        public long ReadyCount { get; set; }
        public double? AvgPrepMinutes { get; set; }
        public double? LongestWaitMinutes { get; set; }
    }

    // =========================================================================
    // Phase R4: Reservations & Waitlist
    // =========================================================================

    public class RestaurantReservationSettingsModel
    {
        [Key] public int ReservationSettingId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public int DefaultDurationMins { get; set; } = 90;
        public int MaxPartySizeOnline { get; set; } = 12;
        public int MinAdvanceHours { get; set; } = 1;
        public int MaxAdvanceDays { get; set; } = 30;
        public int SlotIntervalMins { get; set; } = 30;
        public int OverbookingBuffer { get; set; }
        public bool AutoConfirm { get; set; } = true;
        public int NoShowThresholdMins { get; set; } = 15;
        public string? CancellationPolicy { get; set; }
        public string? ConfirmationMessage { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class RestaurantReservationModel
    {
        [Key] public int ReservationId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public string ReservationNumber { get; set; } = string.Empty;
        public string Status { get; set; } = "Confirmed";
        public DateTime ReservationDate { get; set; }
        public string ReservationTime { get; set; } = string.Empty;
        public string? EndTime { get; set; }
        public int PartySize { get; set; } = 2;
        [Required] public string GuestName { get; set; } = string.Empty;
        public string? GuestPhone { get; set; }
        public string? GuestEmail { get; set; }
        public int? TableId { get; set; }
        public string? TableNumber { get; set; }
        public string? SpecialRequests { get; set; }
        public string? Occasion { get; set; }
        public string Source { get; set; } = "Phone";
        public bool IsVip { get; set; }
        public string? Notes { get; set; }
        public string? CancelReason { get; set; }
        public DateTime? SeatedAt { get; set; }
        public DateTime? CompletedAt { get; set; }
        public DateTime? NoShowMarkedAt { get; set; }
        public bool ReminderSent { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class RestaurantWaitlistModel
    {
        [Key] public int WaitlistId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public string GuestName { get; set; } = string.Empty;
        public string? GuestPhone { get; set; }
        public int PartySize { get; set; } = 2;
        public int EstimatedWaitMins { get; set; } = 15;
        public string Status { get; set; } = "Waiting";
        public string? Notes { get; set; }
        public int? QuotedWaitMins { get; set; }
        public DateTime? NotifiedAt { get; set; }
        public DateTime? SeatedAt { get; set; }
        public int? TableId { get; set; }
        public string? TableNumber { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public double? ActualWaitMins { get; set; }
    }

    public class ReservationStatsModel
    {
        public long TotalCount { get; set; }
        public long ConfirmedCount { get; set; }
        public long SeatedCount { get; set; }
        public long CompletedCount { get; set; }
        public long CancelledCount { get; set; }
        public long NoShowCount { get; set; }
        public long TotalCovers { get; set; }
        public double NoShowRate { get; set; }
    }

    public class WaitlistStatsModel
    {
        public long WaitingCount { get; set; }
        public long NotifiedCount { get; set; }
        public double? AvgWaitMins { get; set; }
        public double? LongestWaitMins { get; set; }
        public long TotalCovers { get; set; }
    }

    public class AutoAssignTableResult
    {
        public int TableId { get; set; }
        public string TableNumber { get; set; } = string.Empty;
        public int Capacity { get; set; }
    }

    // =========================================================================
    // Phase R5: Online Ordering
    // =========================================================================

    public class RestaurantOnlineOrderingSettingsModel
    {
        [Key] public int OnlineOrderingSettingId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public bool IsEnabled { get; set; }
        public bool AllowDineInQr { get; set; } = true;
        public bool AllowTakeaway { get; set; } = true;
        public bool AllowDelivery { get; set; } = true;
        public decimal MinOrderAmount { get; set; }
        public int MaxOrdersPerSlot { get; set; }
        public int SlotDurationMins { get; set; } = 30;
        public int EstimatedPrepMinsDine { get; set; } = 15;
        public int EstimatedPrepMinsTake { get; set; } = 20;
        public int EstimatedPrepminsDeliv { get; set; } = 30;
        public string DeliveryFeeType { get; set; } = "Fixed";
        public decimal DeliveryFeeAmount { get; set; }
        public decimal? FreeDeliveryAbove { get; set; }
        public decimal MaxDeliveryDistanceKm { get; set; } = 10;
        public bool AcceptingOrders { get; set; } = true;
        public string? PausedReason { get; set; }
        public string? WelcomeMessage { get; set; }
        public string? TermsAndConditions { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class RestaurantQrCodeModel
    {
        [Key] public int QrCodeId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public int? TableId { get; set; }
        public string TableNumber { get; set; } = string.Empty;
        public string QrToken { get; set; } = string.Empty;
        public bool IsActive { get; set; } = true;
        public int ScanCount { get; set; }
        public DateTime? LastScannedAt { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class RestaurantPromoCodeModel
    {
        [Key] public int PromoCodeId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public string Code { get; set; } = string.Empty;
        public string? Description { get; set; }
        public string DiscountType { get; set; } = "Percentage";
        public decimal DiscountValue { get; set; }
        public decimal MinOrderAmount { get; set; }
        public decimal? MaxDiscountAmount { get; set; }
        public int MaxUses { get; set; }
        public int CurrentUses { get; set; }
        public DateTime? ValidFrom { get; set; }
        public DateTime? ValidUntil { get; set; }
        public bool IsActive { get; set; } = true;
        public string? ChannelRestriction { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class RestaurantDeliveryAddressModel
    {
        [Key] public int DeliveryAddressId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public string? CustomerPhone { get; set; }
        public string? CustomerEmail { get; set; }
        public string Label { get; set; } = "Home";
        [Required] public string AddressLine1 { get; set; } = string.Empty;
        public string? AddressLine2 { get; set; }
        public string? City { get; set; }
        public string? PostalCode { get; set; }
        public decimal? Latitude { get; set; }
        public decimal? Longitude { get; set; }
        public string? DeliveryNotes { get; set; }
        public bool IsDefault { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class PromoValidationResult
    {
        public bool Valid { get; set; }
        public int PromoCodeId { get; set; }
        public string DiscountType { get; set; } = string.Empty;
        public decimal DiscountValue { get; set; }
        public decimal? MaxDiscountAmount { get; set; }
        public decimal CalculatedDiscount { get; set; }
        public string Message { get; set; } = string.Empty;
    }

    public class ThrottleCheckResult
    {
        public bool CanAccept { get; set; }
        public int CurrentCount { get; set; }
        public int MaxPerSlot { get; set; }
        public string Message { get; set; } = string.Empty;
    }

    public class PublicMenuItemModel
    {
        public int MenuItemId { get; set; }
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
        public decimal Price { get; set; }
        public string? ImageUrl { get; set; }
        public int PrepTime { get; set; }
        public int? Calories { get; set; }
        public string? Allergens { get; set; }
        public int SpicyLevel { get; set; }
        public bool IsVegetarian { get; set; }
        public bool IsVegan { get; set; }
        public bool IsGlutenFree { get; set; }
        public bool IsHalal { get; set; }
        public bool IsKosher { get; set; }
        public int CategoryId { get; set; }
        public string CategoryName { get; set; } = string.Empty;
    }

    public class PublicCategoryModel
    {
        public int MenuCategoryId { get; set; }
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
        public string? ImageUrl { get; set; }
        public int SortOrder { get; set; }
    }

    public class OrderTrackingModel
    {
        public int OrderId { get; set; }
        public string OrderNumber { get; set; } = string.Empty;
        public string OrderType { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public string? TableNumber { get; set; }
        public decimal TotalAmount { get; set; }
        public string PaymentStatus { get; set; } = string.Empty;
        public DateTime? EstimatedReadyTime { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class OnlineOrderCreateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public string OrderType { get; set; } = "Takeaway";
        public int? TableId { get; set; }
        public string? TableNumber { get; set; }
        public string? CustomerName { get; set; }
        public string? CustomerPhone { get; set; }
        public int Covers { get; set; } = 1;
        public string? Notes { get; set; }
        public string? OnlineSource { get; set; }
        public string? DeliveryAddress { get; set; }
        public decimal DeliveryFee { get; set; }
        public int? PromoCodeId { get; set; }
        public string? PromoCode { get; set; }
        public decimal PromoDiscount { get; set; }
        public List<OnlineOrderItemRequest>? Items { get; set; }
    }

    public class OnlineOrderItemRequest
    {
        public int MenuItemId { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public int Quantity { get; set; } = 1;
        public decimal UnitPrice { get; set; }
        public string? Notes { get; set; }
        public List<OrderItemModifierRequest>? Modifiers { get; set; }
    }
}
