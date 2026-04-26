using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class ReportService : IReportService
    {
        private readonly string _connectionString;

        public ReportService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<List<ReportResultModel>> GetReportAsync(ReportRequestModel request)
        {
            try
            {
                string storedProc = request.ReportType switch
                {
                    "EggProduction" => "spReport_EggProduction",
                    "Sales" => "spReport_Sales",
                    "Expenses" => "spReport_Expenses",
                    _ => throw new ArgumentException("Invalid Report Type")
                };

                if (request.StartDate < new DateTime(1753, 1, 1))
                    request.StartDate = DateTime.Today.AddDays(-7);

                if (request.EndDate < new DateTime(1753, 1, 1))
                    request.EndDate = DateTime.Today;

                var results = new List<ReportResultModel>();
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand(storedProc, conn)
                {
                    CommandType = CommandType.StoredProcedure
                };

                cmd.Parameters.AddWithValue("@StartDate", request.StartDate);
                cmd.Parameters.AddWithValue("@EndDate", request.EndDate);
                cmd.Parameters.AddWithValue("@FlockId", (object?)request.FlockId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@CustomerId", (object?)request.CustomerId ?? DBNull.Value);
                //cmd.Parameters.AddWithValue("@UserId", request.UserId);
                cmd.Parameters.AddWithValue("@FarmId", request.FarmId); // ✅ Add FarmId

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    results.Add(new ReportResultModel
                    {
                        UserId = request.UserId,
                        FarmId = reader[0].ToString(),
                        Column1 = reader[1].ToString(),
                        Column2 = reader[2].ToString(),
                        Column3 = reader[3].ToString(),
                        Column4 = reader[4].ToString(),
                        Column5 = reader[5].ToString()
                    });
                }

                return results;
            }
            catch (Exception ex)
            {
                throw new Exception("Error retrieving report.", ex);
            }
        }
    }
}
