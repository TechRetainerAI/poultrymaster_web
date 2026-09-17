namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Row shapes for the report functions added in migration 298.
    //
    // A SEPARATE FILE, not an addition to RestaurantReportModels.cs, on purpose.
    // That file's classes are read by ordinal in RestaurantReportService, and
    // migration 292's post-mortem (see plan.md) records what ordinal reads cost
    // when a shared file is edited under them. Keeping the new shapes apart
    // means nothing in this file can shift a field the old readers depend on.
    //
    // Property order in every class below mirrors the RETURNS TABLE column order
    // of its function, because the service reads these by ordinal too. If you
    // reorder one, reorder the other in the same commit.
    // =========================================================================

    /// <summary>sprestaurant_report_sales_summary — the range-wide KPI header.</summary>
    public class SalesSummaryReport
    {
        public long TotalOrders { get; set; }
        public long CompletedOrders { get; set; }
        public long CancelledOrders { get; set; }
        public decimal GrossRevenue { get; set; }
        public decimal DiscountTotal { get; set; }
        public decimal TaxTotal { get; set; }
        public decimal ServiceChargeTotal { get; set; }
        public decimal NetRevenue { get; set; }
        public decimal AvgTicket { get; set; }
        public long CoversTotal { get; set; }
        public decimal RevenuePerCover { get; set; }
        public decimal TipsTotal { get; set; }
        public long DineInCount { get; set; }
        public decimal DineInRevenue { get; set; }
        public long TakeawayCount { get; set; }
        public decimal TakeawayRevenue { get; set; }
        public long DeliveryCount { get; set; }
        public decimal DeliveryRevenue { get; set; }
        public long ActiveDays { get; set; }
        public decimal AvgDailyRevenue { get; set; }
    }

    /// <summary>sprestaurant_report_payment_methods</summary>
    public class PaymentMethodRow
    {
        public string MethodName { get; set; } = "";
        public long TxnCount { get; set; }
        public decimal AmountTotal { get; set; }
        public decimal TipsTotal { get; set; }
        public decimal SharePct { get; set; }
        public decimal AvgTxn { get; set; }
    }

    /// <summary>sprestaurant_report_pnl_summary — always exactly one row.</summary>
    public class PnlSummary
    {
        public decimal Revenue { get; set; }
        public decimal Cogs { get; set; }
        public decimal GrossProfit { get; set; }
        public decimal GrossMarginPct { get; set; }
        public decimal ExpensesTotal { get; set; }
        public decimal NetProfit { get; set; }
        public decimal NetMarginPct { get; set; }
        public decimal FoodCostPct { get; set; }
        public decimal TipsTotal { get; set; }
        public long OrderCount { get; set; }
    }

    /// <summary>sprestaurant_report_pnl_expenses</summary>
    public class PnlExpenseRow
    {
        public string ExpenseCategory { get; set; } = "";
        public long EntryCount { get; set; }
        public decimal ExpenseTotal { get; set; }
        public decimal SharePct { get; set; }
    }

    /// <summary>sprestaurant_report_kitchen_performance</summary>
    public class KitchenPerformanceRow
    {
        public string StationName { get; set; } = "";
        public long ItemsMade { get; set; }
        public decimal AvgQueueMins { get; set; }
        public decimal AvgPrepMins { get; set; }
        public decimal AvgTicketMins { get; set; }
        public decimal MaxTicketMins { get; set; }
        public long OverTargetCount { get; set; }
        public string SlowestItem { get; set; } = "";
    }

    /// <summary>sprestaurant_report_table_turnover</summary>
    public class TableTurnoverRow
    {
        public string TableLabel { get; set; } = "";
        public int SeatCapacity { get; set; }
        public long OrderCount { get; set; }
        public long CoversServed { get; set; }
        public decimal RevenueTotal { get; set; }
        public decimal AvgDwellMins { get; set; }
        public long TradingDays { get; set; }
        public decimal TurnsPerDay { get; set; }
        public decimal RevenuePerCover { get; set; }
    }

    /// <summary>sprestaurant_report_tips</summary>
    public class TipsRow
    {
        public string WaiterName { get; set; } = "";
        public long OrderCount { get; set; }
        public decimal RevenueTotal { get; set; }
        public decimal TipsTotal { get; set; }
        public decimal TipPct { get; set; }
        public decimal AvgTip { get; set; }
        public long TippedOrders { get; set; }
    }

    /// <summary>sprestaurant_report_delivery_performance</summary>
    public class DeliveryPerformanceRow
    {
        public string DriverLabel { get; set; } = "";
        public long AssignmentCount { get; set; }
        public long DeliveredCount { get; set; }
        public long FailedCount { get; set; }
        public decimal AvgActualMins { get; set; }
        public decimal AvgEstimatedMins { get; set; }
        public long MeasuredCount { get; set; }
        public decimal OnTimePct { get; set; }
        public decimal TotalDistanceKm { get; set; }
        public decimal FeesTotal { get; set; }
        public decimal AvgRating { get; set; }
    }

    /// <summary>sprestaurant_report_discounts</summary>
    public class DiscountRow
    {
        public string DiscountLabel { get; set; } = "";
        public string DiscountKind { get; set; } = "";
        public long TimesApplied { get; set; }
        public long OrdersAffected { get; set; }
        public decimal DiscountTotal { get; set; }
        public decimal AvgDiscount { get; set; }
        public decimal GrossOnDiscounted { get; set; }
        public decimal EffectivePct { get; set; }
    }

    /// <summary>sprestaurant_report_voids</summary>
    public class VoidRow
    {
        public string VoidKind { get; set; } = "";
        public string VoidReason { get; set; } = "";
        public long VoidCount { get; set; }
        public decimal ValueLost { get; set; }
        public long CoversLost { get; set; }
        public decimal SharePct { get; set; }
    }

    /// <summary>sprestaurant_report_stock_on_hand — point in time, no date range.</summary>
    public class StockOnHandRow
    {
        public string IngredientName { get; set; } = "";
        public string IngredientCategory { get; set; } = "";
        public string StockUnit { get; set; } = "";
        public decimal OnHand { get; set; }
        public decimal ParLevel { get; set; }
        public decimal ReorderPoint { get; set; }
        public decimal UnitCost { get; set; }
        public decimal StockValue { get; set; }
        public string SupplierLabel { get; set; } = "";
        public string StorageLabel { get; set; } = "";
        public string StockStatus { get; set; } = "";
    }

    /// <summary>sprestaurant_report_waste_detail</summary>
    public class WasteDetailRow
    {
        public string WasteReason { get; set; } = "";
        public string ItemLabel { get; set; } = "";
        public string WasteUnit { get; set; } = "";
        public decimal QtyTotal { get; set; }
        public decimal CostTotal { get; set; }
        public long EntryCount { get; set; }
        public decimal SharePct { get; set; }
    }

    /// <summary>sprestaurant_report_expenses</summary>
    public class ExpenseReportRow
    {
        public string ExpenseCategory { get; set; } = "";
        public string SupplierLabel { get; set; } = "";
        public string MethodLabel { get; set; } = "";
        public long EntryCount { get; set; }
        public decimal ExpenseTotal { get; set; }
        public decimal SharePct { get; set; }
    }

    /// <summary>sprestaurant_report_menu_engineering</summary>
    public class MenuEngineeringRow
    {
        public string ItemLabel { get; set; } = "";
        public string CategoryLabel { get; set; } = "";
        public long QtySold { get; set; }
        public decimal RevenueTotal { get; set; }
        public decimal UnitCost { get; set; }
        public decimal UnitMargin { get; set; }
        public decimal MarginPct { get; set; }
        public decimal PopularityPct { get; set; }
        /// <summary>Star, Plowhorse, Puzzle, Dog, "No recipe" or Unclassified.</summary>
        public string MenuClass { get; set; } = "";
    }

    /// <summary>sprestaurant_report_customer_retention — always exactly one row.</summary>
    public class CustomerRetentionReport
    {
        public long IdentifiedCustomers { get; set; }
        public long WalkinOrders { get; set; }
        public long NewCustomers { get; set; }
        public long ReturningCustomers { get; set; }
        public decimal RepeatRatePct { get; set; }
        public decimal AvgVisits { get; set; }
        public decimal AvgSpend { get; set; }
        public decimal TopSpend { get; set; }
        public long LapsedCustomers { get; set; }
        public long VipCustomers { get; set; }
    }

    /// <summary>sprestaurant_report_channel</summary>
    public class ChannelRow
    {
        public string PlatformLabel { get; set; } = "";
        public long OrderCount { get; set; }
        public long RejectedCount { get; set; }
        public decimal GrossTotal { get; set; }
        public decimal CommissionTotal { get; set; }
        public decimal PlatformFeeTotal { get; set; }
        public decimal NetTotal { get; set; }
        public decimal CommissionPct { get; set; }
        public decimal AvgOrder { get; set; }
    }

    /// <summary>sprestaurant_report_events</summary>
    public class EventsReportRow
    {
        public string EventStatus { get; set; } = "";
        public long EventCount { get; set; }
        public long GuestTotal { get; set; }
        public decimal ContractedTotal { get; set; }
        public decimal DepositTotal { get; set; }
        public decimal DepositPaidTotal { get; set; }
        public decimal BalanceTotal { get; set; }
        public decimal AvgPerHead { get; set; }
    }

    /// <summary>sprestaurant_report_feedback</summary>
    public class FeedbackReportRow
    {
        public string SourceLabel { get; set; } = "";
        public long ResponseCount { get; set; }
        public decimal AvgOverall { get; set; }
        public decimal AvgFood { get; set; }
        public decimal AvgService { get; set; }
        public decimal AvgAmbience { get; set; }
        public long PromoterCount { get; set; }
        public long DetractorCount { get; set; }
        public long UnansweredCount { get; set; }
    }
}
