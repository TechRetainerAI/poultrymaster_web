using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class CashAdjustmentService : ICashAdjustmentService
    {
        private readonly string _connectionString;

        public CashAdjustmentService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<List<CashAdjustmentModel>> GetAllAsync(string farmId)
        {
            try
            {
                var list = new List<CashAdjustmentModel>();
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spCashAdjustment_GetAll", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(ReadModel(reader));
                }
                return list;
            }
            catch (Exception ex)
            {
                throw new Exception("Error retrieving cash adjustments.", ex);
            }
        }

        public async Task<CashAdjustmentModel?> GetByIdAsync(int adjustmentId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spCashAdjustment_GetById", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };
                cmd.Parameters.AddWithValue("@AdjustmentId", adjustmentId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                    return ReadModel(reader);
                return null;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error retrieving cash adjustment ID={adjustmentId}.", ex);
            }
        }

        public async Task<int> InsertAsync(CashAdjustmentModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spCashAdjustment_Insert", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@AdjustmentDate", model.AdjustmentDate);
                cmd.Parameters.AddWithValue("@AdjustmentType", model.AdjustmentType);
                cmd.Parameters.AddWithValue("@Amount", model.Amount);
                cmd.Parameters.AddWithValue("@Description", (object?)model.Description ?? DBNull.Value);
                await conn.OpenAsync();
                var result = await cmd.ExecuteScalarAsync();
                return Convert.ToInt32(result);
            }
            catch (Exception ex)
            {
                throw new Exception("Error inserting cash adjustment.", ex);
            }
        }

        public async Task UpdateAsync(CashAdjustmentModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spCashAdjustment_Update", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };
                cmd.Parameters.AddWithValue("@AdjustmentId", model.AdjustmentId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@AdjustmentDate", model.AdjustmentDate);
                cmd.Parameters.AddWithValue("@AdjustmentType", model.AdjustmentType);
                cmd.Parameters.AddWithValue("@Amount", model.Amount);
                cmd.Parameters.AddWithValue("@Description", (object?)model.Description ?? DBNull.Value);
                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error updating cash adjustment ID={model.AdjustmentId}.", ex);
            }
        }

        public async Task DeleteAsync(int adjustmentId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spCashAdjustment_Delete", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };
                cmd.Parameters.AddWithValue("@AdjustmentId", adjustmentId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error deleting cash adjustment ID={adjustmentId}.", ex);
            }
        }

        private static CashAdjustmentModel ReadModel(SqlDataReader reader)
        {
            return new CashAdjustmentModel
            {
                AdjustmentId = reader.GetInt32(reader.GetOrdinal("AdjustmentId")),
                UserId = reader.GetString(reader.GetOrdinal("UserId")),
                FarmId = reader.GetString(reader.GetOrdinal("FarmId")),
                AdjustmentDate = reader.GetDateTime(reader.GetOrdinal("AdjustmentDate")),
                AdjustmentType = reader.GetString(reader.GetOrdinal("AdjustmentType")),
                Amount = reader.GetDecimal(reader.GetOrdinal("Amount")),
                Description = reader.IsDBNull(reader.GetOrdinal("Description")) ? null : reader.GetString(reader.GetOrdinal("Description")),
                CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate"))
            };
        }
    }
}
