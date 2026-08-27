using System.Threading.Tasks;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // Advanced Poultry Reports service — 20 brand-new, poultry-only reports.
    // Every method is scoped by FarmId (carried on the filter) and reads the
    // existing poultry source tables via dedicated spPoultryReport_* procedures.
    // Nothing here calls or alters any existing report service.
    // =========================================================================
    public interface IPoultryAdvancedReportService
    {
        Task<PoultryReportResponse<PoultryFarmSummaryReportSummary, PoultryFarmSummaryReportRow>>
            GetFarmSummaryAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryDailyEggProductionReportSummary, PoultryDailyEggProductionReportRow>>
            GetDailyEggProductionAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryFlockProductionSummaryReportSummary, PoultryFlockProductionSummaryReportRow>>
            GetFlockProductionSummaryAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryHenDayProductionReportSummary, PoultryHenDayProductionReportRow>>
            GetHenDayProductionAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryMortalityReportSummary, PoultryMortalityReportRow>>
            GetMortalityAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryBirdsOnHandReportSummary, PoultryBirdsOnHandReportRow>>
            GetBirdsOnHandAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryFeedUsageReportSummary, PoultryFeedUsageReportRow>>
            GetFeedUsageAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryFeedInventoryBalanceReportSummary, PoultryFeedInventoryBalanceReportRow>>
            GetFeedInventoryBalanceAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryFeedCostPerEggReportSummary, PoultryFeedCostPerEggReportRow>>
            GetFeedCostPerEggAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryEggStockBalanceReportSummary, PoultryEggStockBalanceReportRow>>
            GetEggStockBalanceAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryEggSalesReportSummary, PoultryEggSalesReportRow>>
            GetEggSalesAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryCustomerBalanceReportSummary, PoultryCustomerBalanceReportRow>>
            GetCustomerBalanceAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultrySupplierBalanceReportSummary, PoultrySupplierBalanceReportRow>>
            GetSupplierBalanceAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryExpenseSummaryReportSummary, PoultryExpenseSummaryReportRow>>
            GetExpenseSummaryAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryCashMovementReportSummary, PoultryCashMovementReportRow>>
            GetCashMovementAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryProfitLossByFlockReportSummary, PoultryProfitLossByFlockReportRow>>
            GetProfitLossByFlockAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryProfitLossReportSummary, PoultryProfitLossReportRow>>
            GetProfitLossAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryCostPerEggReportSummary, PoultryCostPerEggReportRow>>
            GetCostPerEggAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryVaccinationScheduleReportSummary, PoultryVaccinationScheduleReportRow>>
            GetVaccinationScheduleAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryMedicineUsageReportSummary, PoultryMedicineUsageReportRow>>
            GetMedicineUsageAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryMissingDailyRecordsReportSummary, PoultryMissingDailyRecordsReportRow>>
            GetMissingDailyRecordsAsync(PoultryReportFilterDto filter);

        Task<PoultryReportResponse<PoultryEndOfFlockReportSummary, PoultryEndOfFlockReportRow>>
            GetEndOfFlockAsync(PoultryReportFilterDto filter);
    }
}
