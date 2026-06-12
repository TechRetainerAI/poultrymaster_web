using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IDashboardService
    {
        Task<DashboardViewModel> GetSummaryAsync(string farmId);
    }

}
