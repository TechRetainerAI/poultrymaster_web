using System.Data;
using System.Data.SqlClient;
using PoultryWeb.Models;

namespace PoultryWeb.Business
{
    public interface IReportWebApiService
    {
        Task<byte[]> ExportCsvAsync(ReportRequestModel request);
        Task<byte[]> ExportPdfAsync(ReportRequestModel request);
        Task<byte[]> ExportExcelAsync(ReportRequestModel request);
    }
}
