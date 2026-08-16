using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class DashboardService : IDashboardService
    {
        private readonly string _connectionString;

        public DashboardService(string connectionString)
        {
            _connectionString = connectionString;
        }

        // Modified method signature to accept a userId parameter.
        public async Task<DashboardViewModel> GetSummaryAsync(string farmId)
        {
            try
            {
                var model = new DashboardViewModel();

                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spdashboard_getsummary_rs1(p_farmid => @FarmId::text); SELECT * FROM spdashboard_getsummary_rs2(p_farmid => @FarmId::text); SELECT * FROM spdashboard_getsummary_rs3(p_farmid => @FarmId::text); SELECT * FROM spdashboard_getsummary_rs4(p_farmid => @FarmId::text); SELECT * FROM spdashboard_getsummary_rs5(p_farmid => @FarmId::text)", conn);
                // Pass the userId to the stored procedure.
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();

                if (await reader.ReadAsync())
                {
                    model.TotalEggsToday = reader.GetInt32(0);
                    model.FeedUsedTodayKg = reader.GetDecimal(1);
                    model.SalesToday = reader.GetDecimal(2);
                    model.ExpensesToday = reader.GetDecimal(3);
                    model.ActiveFlocks = reader.GetInt32(4);
                }

                if (await reader.NextResultAsync())
                {
                    while (await reader.ReadAsync())
                    {
                        model.EggChart.Add(new ChartPoint
                        {
                            Label = reader.GetString(0),
                            Value = reader.GetInt32(1)
                        });
                    }
                }

                if (await reader.NextResultAsync())
                {
                    while (await reader.ReadAsync())
                    {
                        model.FeedChart.Add(new ChartPoint
                        {
                            Label = reader.GetString(0),
                            Value = reader.GetDecimal(1)
                        });
                    }
                }

                if (await reader.NextResultAsync())
                {
                    while (await reader.ReadAsync())
                    {
                        model.SalesChart.Add(new ChartPoint
                        {
                            Label = reader.GetString(0),
                            Value = reader.GetDecimal(1)
                        });
                    }
                }

                if (await reader.NextResultAsync())
                {
                    while (await reader.ReadAsync())
                    {
                        model.ExpensesChart.Add(new ChartPoint
                        {
                            Label = reader.GetString(0),
                            Value = reader.GetDecimal(1)
                        });
                    }
                }

                return model;
            }
            catch (Exception ex)
            {
                throw new Exception("Error retrieving dashboard summary.", ex);
            }
        }
    }
}
