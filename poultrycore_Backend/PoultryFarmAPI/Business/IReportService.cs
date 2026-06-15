using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IReportService
    {
        Task<List<ReportResultModel>> GetReportAsync(ReportRequestModel request);
    }
}
