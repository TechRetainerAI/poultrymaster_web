namespace PoultryFarmAPIWeb.Models
{
    public class LoyaltySettingsModel
    {
        public int LoyaltySettingId { get; set; } public string FarmId { get; set; } = "";
        public bool IsEnabled { get; set; } public decimal PointsPerCurrencyUnit { get; set; } = 1;
        public decimal PointsRedemptionRate { get; set; } = 0.01m; public int MinimumRedeemPoints { get; set; } = 100;
        public int PointsExpiryDays { get; set; } = 365; public bool TiersEnabled { get; set; }
        public int BronzeThreshold { get; set; } public int SilverThreshold { get; set; } = 500;
        public int GoldThreshold { get; set; } = 1000; public int PlatinumThreshold { get; set; } = 2500;
        public decimal BronzeMultiplier { get; set; } = 1; public decimal SilverMultiplier { get; set; } = 1.5m;
        public decimal GoldMultiplier { get; set; } = 2; public decimal PlatinumMultiplier { get; set; } = 3;
        public int ReferralBonus { get; set; } = 50;
        public DateTime CreatedAt { get; set; } public DateTime? UpdatedAt { get; set; }
    }
    public class LoyaltyAccountModel
    {
        public int LoyaltyAccountId { get; set; } public string FarmId { get; set; } = "";
        public int? CustomerId { get; set; } public string CustomerName { get; set; } = "";
        public string? CustomerPhone { get; set; } public int TotalPoints { get; set; }
        public int LifetimePoints { get; set; } public string CurrentTier { get; set; } = "Bronze";
        public string? ReferralCode { get; set; } public int? ReferredBy { get; set; }
        public DateTime CreatedAt { get; set; } public DateTime? UpdatedAt { get; set; }
    }
    public class PointTransactionModel
    {
        public int PointTransactionId { get; set; } public string TransactionType { get; set; } = "";
        public int Points { get; set; } public string? Description { get; set; }
        public int? OrderId { get; set; } public DateTime CreatedAt { get; set; }
    }
    public class LoyaltyStatsModel { public long TotalMembers { get; set; } public long TotalPointsOutstanding { get; set; } public long BronzeCount { get; set; } public long SilverCount { get; set; } public long GoldCount { get; set; } public long PlatinumCount { get; set; } }
    public class NotificationModel
    {
        public int NotificationId { get; set; } public string FarmId { get; set; } = "";
        public string Type { get; set; } = ""; public string Title { get; set; } = "";
        public string Message { get; set; } = ""; public string Severity { get; set; } = "Info";
        public bool IsRead { get; set; } public string? TargetUserId { get; set; }
        public string? TargetRole { get; set; } public int? RelatedId { get; set; }
        public string? RelatedType { get; set; } public DateTime CreatedAt { get; set; }
    }
    public class NotificationSettingsModel
    {
        public int NotificationSettingId { get; set; } public string FarmId { get; set; } = "";
        public bool EmailEnabled { get; set; } = true; public bool SmsEnabled { get; set; }
        public bool PushEnabled { get; set; } public bool LowStockAlerts { get; set; } = true;
        public bool NewOrderAlerts { get; set; } = true; public bool ReservationAlerts { get; set; } = true;
        public bool KpiAlerts { get; set; } = true; public bool ShiftReminders { get; set; } = true;
        public DateTime CreatedAt { get; set; } public DateTime? UpdatedAt { get; set; }
    }
    public class EventModel
    {
        public int EventId { get; set; } public string FarmId { get; set; } = "";
        public string? EventNumber { get; set; } public string Name { get; set; } = "";
        public string EventType { get; set; } = ""; public DateTime EventDate { get; set; }
        public string? StartTime { get; set; } public string? EndTime { get; set; }
        public int GuestCount { get; set; } public string? Venue { get; set; }
        public string Status { get; set; } = "Inquiry";
        public string? ContactName { get; set; } public string? ContactPhone { get; set; }
        public string? ContactEmail { get; set; } public string? PackageName { get; set; }
        public decimal PricePerHead { get; set; } public decimal TotalAmount { get; set; }
        public decimal DepositAmount { get; set; } public bool DepositPaid { get; set; }
        public decimal BalanceDue { get; set; }
        public string? SpecialRequests { get; set; } public string? DietaryNotes { get; set; }
        public string? Notes { get; set; } public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; } public DateTime? UpdatedAt { get; set; }
    }
    public class GiftCardModel
    {
        public int GiftCardId { get; set; } public string FarmId { get; set; } = "";
        public string CardNumber { get; set; } = ""; public string CardType { get; set; } = "Digital";
        public decimal InitialBalance { get; set; } public decimal CurrentBalance { get; set; }
        public string? PurchaserName { get; set; } public string? PurchaserPhone { get; set; }
        public string? RecipientName { get; set; } public string Status { get; set; } = "Active";
        public DateTime? ExpiryDate { get; set; } public DateTime CreatedAt { get; set; }
    }
    public class GiftCardTxModel
    {
        public int GiftCardTxId { get; set; } public string TransactionType { get; set; } = "";
        public decimal Amount { get; set; } public decimal BalanceAfter { get; set; }
        public int? OrderId { get; set; } public string? Notes { get; set; }
        public string? ProcessedBy { get; set; } public DateTime CreatedAt { get; set; }
    }
    public class GiftCardStatsModel { public long TotalCards { get; set; } public long ActiveCards { get; set; } public decimal TotalIssued { get; set; } public decimal TotalOutstanding { get; set; } public decimal TotalRedeemed { get; set; } }
    public class GiftCardRedeemResult { public bool Success { get; set; } public decimal NewBalance { get; set; } public string Message { get; set; } = ""; }
    public class ExpenseCategoryModel { public int ExpenseCategoryId { get; set; } public string FarmId { get; set; } = ""; public string Name { get; set; } = ""; public bool IsActive { get; set; } = true; public int SortOrder { get; set; } }
    public class RestaurantExpenseModel
    {
        public int ExpenseId { get; set; } public string FarmId { get; set; } = "";
        public DateTime ExpenseDate { get; set; } public int? CategoryId { get; set; }
        public string? CategoryName { get; set; } public string Description { get; set; } = "";
        public decimal Amount { get; set; } public string PaymentMethod { get; set; } = "Cash";
        public string? SupplierName { get; set; } public string? ReceiptRef { get; set; }
        public string Status { get; set; } = "Approved"; public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }
    public class ReceiptTemplateModel
    {
        public int ReceiptTemplateId { get; set; } public string FarmId { get; set; } = "";
        public string? HeaderText { get; set; } public string? FooterText { get; set; }
        public bool ShowLogo { get; set; } = true; public bool ShowTaxDetails { get; set; } = true;
        public bool ShowServerNames { get; set; } = true;
        public string ThanksMessage { get; set; } = "Thank you for dining with us!";
        public DateTime CreatedAt { get; set; } public DateTime? UpdatedAt { get; set; }
    }
    public class RestaurantStaffModel
    {
        public int RestaurantStaffId { get; set; } public string FarmId { get; set; } = "";
        public string FirstName { get; set; } = ""; public string LastName { get; set; } = "";
        public string? Phone { get; set; } public string? Email { get; set; }
        public string Role { get; set; } = "Other"; public string SalaryType { get; set; } = "Monthly";
        public decimal BasePay { get; set; } public bool IsActive { get; set; } = true;
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; } public DateTime? UpdatedAt { get; set; }
    }
}
