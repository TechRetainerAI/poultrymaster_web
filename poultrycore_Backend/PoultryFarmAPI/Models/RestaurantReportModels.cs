namespace PoultryFarmAPIWeb.Models
{
    public class DailySalesReport
    {
        public long TotalOrders { get; set; } public long CompletedOrders { get; set; } public long CancelledOrders { get; set; }
        public decimal TotalRevenue { get; set; } public decimal TotalDiscount { get; set; } public decimal TotalTax { get; set; }
        public decimal TotalServiceCharge { get; set; } public decimal NetRevenue { get; set; }
        public decimal AvgTicket { get; set; } public long TotalCovers { get; set; }
        public long DineInCount { get; set; } public decimal DineInRevenue { get; set; }
        public long TakeawayCount { get; set; } public decimal TakeawayRevenue { get; set; }
        public long DeliveryCount { get; set; } public decimal DeliveryRevenue { get; set; }
        public decimal CashAmount { get; set; } public decimal CardAmount { get; set; }
        public decimal MobileAmount { get; set; } public decimal OtherAmount { get; set; }
    }
    public class SalesByItemRow { public int MenuItemId { get; set; } public string ItemName { get; set; } = ""; public long QuantitySold { get; set; } public decimal TotalRevenue { get; set; } public decimal AvgPrice { get; set; } public long OrderCount { get; set; } }
    public class SalesByCategoryRow { public string CategoryName { get; set; } = ""; public long ItemCount { get; set; } public long QuantitySold { get; set; } public decimal TotalRevenue { get; set; } }
    public class SalesByHourRow { public int HourOfDay { get; set; } public long OrderCount { get; set; } public decimal TotalRevenue { get; set; } public decimal AvgTicket { get; set; } }
    public class RevenueTrendRow { public DateTime ReportDate { get; set; } public long OrderCount { get; set; } public decimal TotalRevenue { get; set; } public decimal AvgTicket { get; set; } }
    public class FoodCostRow { public int MenuItemId { get; set; } public string ItemName { get; set; } = ""; public decimal SellingPrice { get; set; } public decimal RecipeCost { get; set; } public decimal FoodCostPercent { get; set; } public decimal Margin { get; set; } public string CategoryName { get; set; } = ""; }
    public class ServerPerformanceRow { public string ServedBy { get; set; } = ""; public long OrderCount { get; set; } public decimal TotalRevenue { get; set; } public decimal AvgTicket { get; set; } public long TotalCovers { get; set; } }
    public class KpiAlertModel { public int KpiAlertId { get; set; } public string FarmId { get; set; } = ""; public string Name { get; set; } = ""; public string Metric { get; set; } = ""; public string Operator { get; set; } = ">"; public decimal Threshold { get; set; } public bool IsEnabled { get; set; } = true; public DateTime? LastChecked { get; set; } public DateTime? LastTriggered { get; set; } public DateTime CreatedAt { get; set; } }
}
