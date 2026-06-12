using PoultryWeb.Models;

namespace PoultryWeb.Business
{
    public interface IDashboardWebApiService
    {
        Task<DashboardViewModel> GetDashboardSummaryAsync();
    }

}
