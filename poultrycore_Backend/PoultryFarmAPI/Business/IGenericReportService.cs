using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericReportService
    {
        Task<GenericDashboardModel> GetDashboardAsync(string farmId, DateTime? asOf);
        Task<GenericPeriodPnLModel> GetPeriodPnLAsync(string farmId, DateTime fromDate, DateTime toDate);
        Task<List<GenericProfitLossEntry>> GetProfitLossEntriesAsync(string farmId, DateOnly from, DateOnly to, CancellationToken cancellationToken);

        Task<List<GenericSalesByProductRow>>  GetSalesByProductAsync(string farmId, DateTime fromDate, DateTime toDate);
        Task<List<GenericSalesByCustomerRow>> GetSalesByCustomerAsync(string farmId, DateTime fromDate, DateTime toDate);
        Task<List<GenericExpenseByCategoryRow>> GetExpensesByCategoryAsync(string farmId, DateTime fromDate, DateTime toDate);

        Task<GenericInventoryValueReport> GetInventoryValueAsync(string farmId);
        Task<GenericCashSummaryReport>    GetCashSummaryAsync(string farmId, DateTime fromDate, DateTime toDate);

        // Phase 4 (migration 442)
        Task<GenericFinancialPreviewModel> GetFinancialPreviewAsync(string farmId, int productId, decimal quantity, string transactionType);
        Task<GenericPnLBreakdownModel> GetPnLBreakdownAsync(string farmId, DateTime fromDate, DateTime toDate);
        Task<GenericItemCostReconciliationModel> GetItemCostReconciliationAsync(string farmId, int productId);

        // Phase 5 (migration 443)
        Task<List<GenericInventoryBalanceRow>> GetInventoryBalanceAsync(string farmId, DateTime fromDate, DateTime toDate);
        Task<List<GenericConsumptionRow>> GetInternalConsumptionAsync(string farmId, DateTime? fromDate, DateTime? toDate, string? category);
        Task<GenericConsumptionSummary> GetConsumptionSummaryAsync(string farmId, DateTime? fromDate, DateTime? toDate);
        Task<List<GenericReconciliationRow>> GetInventoryReconciliationAsync(string farmId);
        Task<List<GenericRestockForecastRow>> GetRestockForecastAsync(string farmId, int lookbackDays);
    }
}
