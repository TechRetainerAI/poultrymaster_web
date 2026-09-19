using PoultryFarmAPIWeb.Models;
namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantReportService
    {
        Task<DailySalesReport> GetDailySalesAsync(string farmId, DateTime date);
        Task<List<SalesByItemRow>> GetSalesByItemAsync(string farmId, DateTime from, DateTime to);
        Task<List<SalesByCategoryRow>> GetSalesByCategoryAsync(string farmId, DateTime from, DateTime to);
        Task<List<SalesByHourRow>> GetSalesByHourAsync(string farmId, DateTime date);
        Task<List<RevenueTrendRow>> GetRevenueTrendAsync(string farmId, DateTime from, DateTime to);
        Task<List<FoodCostRow>> GetFoodCostReportAsync(string farmId);
        Task<List<ServerPerformanceRow>> GetServerPerformanceAsync(string farmId, DateTime from, DateTime to);
        Task<List<KpiAlertModel>> ListKpiAlertsAsync(string farmId);
        Task<int> InsertKpiAlertAsync(string farmId, string name, string metric, string op, decimal threshold, bool enabled);
        Task DeleteKpiAlertAsync(int id, string farmId);

        // ---------------------------------------------------------------------
        // Migration 298. Appended rather than placed among the originals so a
        // diff of this file shows exactly what the second pass added.
        //
        // Every one of these is (farmId, from, to) apart from stock on hand,
        // which is a position rather than a period. That uniformity is what lets
        // the frontend drive all of them from a single date-range control.
        // ---------------------------------------------------------------------
        Task<SalesSummaryReport> GetSalesSummaryAsync(string farmId, DateTime from, DateTime to);
        Task<List<PaymentMethodRow>> GetPaymentMethodsAsync(string farmId, DateTime from, DateTime to);
        Task<PnlSummary> GetPnlSummaryAsync(string farmId, DateTime from, DateTime to);
        Task<List<PnlExpenseRow>> GetPnlExpensesAsync(string farmId, DateTime from, DateTime to);
        Task<List<KitchenPerformanceRow>> GetKitchenPerformanceAsync(string farmId, DateTime from, DateTime to);
        Task<List<TableTurnoverRow>> GetTableTurnoverAsync(string farmId, DateTime from, DateTime to);
        Task<List<TipsRow>> GetTipsAsync(string farmId, DateTime from, DateTime to);
        Task<List<DeliveryPerformanceRow>> GetDeliveryPerformanceAsync(string farmId, DateTime from, DateTime to);
        Task<List<DiscountRow>> GetDiscountsAsync(string farmId, DateTime from, DateTime to);
        Task<List<VoidRow>> GetVoidsAsync(string farmId, DateTime from, DateTime to);
        Task<List<StockOnHandRow>> GetStockOnHandAsync(string farmId);
        Task<List<WasteDetailRow>> GetWasteDetailAsync(string farmId, DateTime from, DateTime to);
        Task<List<ExpenseReportRow>> GetExpenseReportAsync(string farmId, DateTime from, DateTime to);
        Task<List<MenuEngineeringRow>> GetMenuEngineeringAsync(string farmId, DateTime from, DateTime to);
        Task<CustomerRetentionReport> GetCustomerRetentionAsync(string farmId, DateTime from, DateTime to);
        Task<List<ChannelRow>> GetChannelAsync(string farmId, DateTime from, DateTime to);
        Task<List<EventsReportRow>> GetEventsReportAsync(string farmId, DateTime from, DateTime to);
        Task<List<FeedbackReportRow>> GetFeedbackReportAsync(string farmId, DateTime from, DateTime to);
    }
}
