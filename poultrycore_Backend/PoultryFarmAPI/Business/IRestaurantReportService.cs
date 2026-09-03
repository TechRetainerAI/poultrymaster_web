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
    }
}
