using Microsoft.Extensions.Logging;
using PoultryFarmAPIWeb.Models;
using System.Data;
using System.Data.SqlClient;
using System.Text;
using System.Text.Json;

namespace PoultryFarmAPIWeb.Business
{
    public class EggProductionService : IEggProductionService
    {
        private readonly string _connectionString;
        private readonly ILogger<EggProductionService> _logger;

        private static string? ReadOptionalString(SqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? null : reader.GetString(i);
            }
            return null;
        }

        private static int? ReadOptionalInt32(SqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? (int?)null : reader.GetInt32(i);
            }
            return null;
        }

        public EggProductionService(string connectionString, ILogger<EggProductionService> logger)
        {
            _connectionString = connectionString;
            _logger = logger;
        }

        public async Task<int> Insert(EggProductionModel model)
        {
            _logger.LogInformation("EggProductionService.Insert called with model: {Model}", JsonSerializer.Serialize(model));
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spEggProduction_Insert", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.Add("@FlockId", SqlDbType.Int).Value = model.FlockId;
                cmd.Parameters.Add("@ProductionDate", SqlDbType.Date).Value = model.ProductionDate;
                cmd.Parameters.Add("@EggCount", SqlDbType.Int).Value = model.EggCount;
                cmd.Parameters.Add("@Production9AM", SqlDbType.Int).Value = model.Production9AM;
                cmd.Parameters.Add("@Production12PM", SqlDbType.Int).Value = model.Production12PM;
                cmd.Parameters.Add("@Production4PM", SqlDbType.Int).Value = model.Production4PM;
                cmd.Parameters.Add("@BrokenEggs", SqlDbType.Int).Value = (object?)model.BrokenEggs ?? DBNull.Value;
                cmd.Parameters.Add("@Notes", SqlDbType.NVarChar, -1).Value = (object?)model.Notes ?? DBNull.Value;
                cmd.Parameters.Add("@UserId", SqlDbType.NVarChar, -1).Value = model.UserId ?? (object)DBNull.Value;
                cmd.Parameters.Add("@FarmId", SqlDbType.NVarChar, -1).Value = model.FarmId ?? (object)DBNull.Value;
                cmd.Parameters.Add("@EggGrade", SqlDbType.NVarChar, 50).Value = (object?)model.EggGrade ?? DBNull.Value;

                var sb = new StringBuilder();
                sb.AppendLine("Executing spEggProduction_Insert with parameters:");
                foreach (SqlParameter p in cmd.Parameters)
                {
                    sb.AppendLine($"  {p.ParameterName}: {p.Value}");
                }
                _logger.LogInformation(sb.ToString());

                await conn.OpenAsync();
                var result = await cmd.ExecuteScalarAsync();
                _logger.LogInformation("Successfully inserted EggProduction record. New ID: {Result}", result);
                return Convert.ToInt32(result);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error inserting EggProduction record.");
                throw new Exception("Error inserting EggProduction record.", ex);
            }
        }

        public async Task Update(EggProductionModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spEggProduction_Update", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@ProductionId", model.ProductionId);
                cmd.Parameters.AddWithValue("@FlockId", model.FlockId);
                cmd.Parameters.AddWithValue("@ProductionDate", model.ProductionDate);
                cmd.Parameters.AddWithValue("@EggCount", model.EggCount);
                cmd.Parameters.AddWithValue("@Production9AM", model.Production9AM);
                cmd.Parameters.AddWithValue("@Production12PM", model.Production12PM);
                cmd.Parameters.AddWithValue("@Production4PM", model.Production4PM);
                cmd.Parameters.AddWithValue("@BrokenEggs", (object?)model.BrokenEggs ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Notes", (object?)model.Notes ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@UserId", model.UserId ?? (object)DBNull.Value);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId ?? (object)DBNull.Value);
                cmd.Parameters.AddWithValue("@EggGrade", (object?)model.EggGrade ?? DBNull.Value);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error updating EggProduction record ID={model.ProductionId}.", ex);
            }
        }

        public async Task<EggProductionModel?> GetById(int productionId, string userId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spEggProduction_GetById", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@ProductionId", productionId);
                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();

                if (await reader.ReadAsync())
                {
                    var model = new EggProductionModel
                    {
                        ProductionId = reader.GetInt32(reader.GetOrdinal("ProductionId")),
                        FlockId = reader.GetInt32(reader.GetOrdinal("FlockId")),
                        ProductionDate = reader.GetDateTime(reader.GetOrdinal("ProductionDate")),
                        EggCount = reader.GetInt32(reader.GetOrdinal("EggCount")),
                        Production9AM = reader.IsDBNull(reader.GetOrdinal("Production9AM")) ? 0 : reader.GetInt32(reader.GetOrdinal("Production9AM")),
                        Production12PM = reader.IsDBNull(reader.GetOrdinal("Production12PM")) ? 0 : reader.GetInt32(reader.GetOrdinal("Production12PM")),
                        Production4PM = reader.IsDBNull(reader.GetOrdinal("Production4PM")) ? 0 : reader.GetInt32(reader.GetOrdinal("Production4PM")),
                        BrokenEggs = reader.IsDBNull(reader.GetOrdinal("BrokenEggs"))
                            ? null
                            : reader.GetInt32(reader.GetOrdinal("BrokenEggs")),
                        Notes = reader.IsDBNull(reader.GetOrdinal("Notes"))
                            ? null
                            : reader.GetString(reader.GetOrdinal("Notes")),
                        EggGrade = ReadOptionalString(reader, "EggGrade"),
                        UserId = reader.GetString(reader.GetOrdinal("UserId")),
                        FarmId = reader.IsDBNull(reader.GetOrdinal("FarmId")) ? null : reader.GetString(reader.GetOrdinal("FarmId"))
                    };
                    model.TotalProduction = model.Production9AM + model.Production12PM + model.Production4PM;
                    return model;
                }
                return null;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error retrieving EggProduction record ID={productionId}.", ex);
            }
        }

        public async Task<List<EggProductionModel>> GetAll(string userId, string farmId)
        {
            try
            {
                var list = new List<EggProductionModel>();
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spEggProduction_GetAll", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var p9 = reader.IsDBNull(reader.GetOrdinal("Production9AM")) ? 0 : reader.GetInt32(reader.GetOrdinal("Production9AM"));
                    var p12 = reader.IsDBNull(reader.GetOrdinal("Production12PM")) ? 0 : reader.GetInt32(reader.GetOrdinal("Production12PM"));
                    var p4 = reader.IsDBNull(reader.GetOrdinal("Production4PM")) ? 0 : reader.GetInt32(reader.GetOrdinal("Production4PM"));
                    var totalFromRow = ReadOptionalInt32(reader, "TotalProduction");
                    var ep = new EggProductionModel
                    {
                        ProductionId = reader.GetInt32(reader.GetOrdinal("ProductionId")),
                        FlockId = reader.GetInt32(reader.GetOrdinal("FlockId")),
                        FlockName = ReadOptionalString(reader, "FlockName") ?? "Unknown Flock",
                        ProductionDate = reader.GetDateTime(reader.GetOrdinal("ProductionDate")),
                        EggCount = reader.GetInt32(reader.GetOrdinal("EggCount")),
                        Production9AM = p9,
                        Production12PM = p12,
                        Production4PM = p4,
                        TotalProduction = totalFromRow ?? p9 + p12 + p4,
                        BrokenEggs = reader.IsDBNull(reader.GetOrdinal("BrokenEggs"))
                            ? null
                            : reader.GetInt32(reader.GetOrdinal("BrokenEggs")),
                        Notes = reader.IsDBNull(reader.GetOrdinal("Notes"))
                            ? null
                            : reader.GetString(reader.GetOrdinal("Notes")),
                        EggGrade = ReadOptionalString(reader, "EggGrade"),
                        UserId = reader.GetString(reader.GetOrdinal("UserId")),
                        FarmId = reader.IsDBNull(reader.GetOrdinal("FarmId")) ? null : reader.GetString(reader.GetOrdinal("FarmId"))
                    };
                    list.Add(ep);
                }
                return list;
            }
            catch (Exception ex)
            {
                throw new Exception("Error retrieving all EggProduction records.", ex);
            }
        }

        public async Task<List<EggProductionModel>> GetByFlockId(int flockId, string userId, string farmId)
        {
            try
            {
                var list = new List<EggProductionModel>();
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spEggProduction_GetByFlock", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@FlockId", flockId);
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var ep = new EggProductionModel
                    {
                        ProductionId = reader.GetInt32(reader.GetOrdinal("ProductionId")),
                        FlockId = reader.GetInt32(reader.GetOrdinal("FlockId")),
                        ProductionDate = reader.GetDateTime(reader.GetOrdinal("ProductionDate")),
                        EggCount = reader.GetInt32(reader.GetOrdinal("EggCount")),
                        BrokenEggs = reader.IsDBNull(reader.GetOrdinal("BrokenEggs"))
                            ? null
                            : reader.GetInt32(reader.GetOrdinal("BrokenEggs")),
                        Notes = reader.IsDBNull(reader.GetOrdinal("Notes"))
                            ? null
                            : reader.GetString(reader.GetOrdinal("Notes")),
                        EggGrade = ReadOptionalString(reader, "EggGrade"),
                        FarmId = reader.IsDBNull(reader.GetOrdinal("FarmId")) ? null : reader.GetString(reader.GetOrdinal("FarmId"))
                    };
                    list.Add(ep);
                }
                return list;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error retrieving EggProduction records for Flock ID={flockId}.", ex);
            }
        }

        public async Task Delete(int productionId, string userId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spEggProduction_Delete", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@ProductionId", productionId);
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error deleting EggProduction record ID={productionId}.", ex);
            }
        }
    }
}
