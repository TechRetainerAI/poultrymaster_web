using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericReportService
    {
        Task<GenericDashboardModel> GetDashboardAsync(string farmId, DateTime? asOf);
        Task<GenericPeriodPnLModel> GetPeriodPnLAsync(string farmId, DateTime fromDate, DateTime toDate);

        Task<List<GenericSalesByProductRow>>  GetSalesByProductAsync(string farmId, DateTime fromDate, DateTime toDate);
        Task<List<GenericSalesByCustomerRow>> GetSalesByCustomerAsync(string farmId, DateTime fromDate, DateTime toDate);
        Task<List<GenericExpenseByCategoryRow>> GetExpensesByCategoryAsync(string farmId, DateTime fromDate, DateTime toDate);

        Task<GenericInventoryValueReport> GetInventoryValueAsync(string farmId);
        Task<GenericCashSummaryReport>    GetCashSummaryAsync(string farmId, DateTime fromDate, DateTime toDate);
    }
}
