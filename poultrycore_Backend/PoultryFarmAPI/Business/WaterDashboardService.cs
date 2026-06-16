using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class WaterDashboardService : IWaterDashboardService
    {
        private readonly string _connectionString;

        public WaterDashboardService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<WaterDashboardSummaryModel> GetSummary(string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterDashboard_Summary", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync()) return new WaterDashboardSummaryModel();

            return new WaterDashboardSummaryModel
            {
                ActiveProducts         = reader.GetInt32(reader.GetOrdinal("ActiveProducts")),
                TotalCustomers         = reader.GetInt32(reader.GetOrdinal("TotalCustomers")),
                TotalStockOnHand       = Convert.ToInt32(reader.GetValue(reader.GetOrdinal("TotalStockOnHand"))),
                SalesToday             = reader.GetDecimal(reader.GetOrdinal("SalesToday")),
                SalesThisMonth         = reader.GetDecimal(reader.GetOrdinal("SalesThisMonth")),
                OutstandingReceivables = reader.GetDecimal(reader.GetOrdinal("OutstandingReceivables")),
            };
        }
    }
}
