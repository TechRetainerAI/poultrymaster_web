using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // Concrete implementation using ADO.NET and Stored Procedures, mirroring CustomerService.
    public class MainFlockBatchService : IMainFlockBatchService
    {
        private readonly string _connectionString;

        public MainFlockBatchService(string connectionString)
        {
            _connectionString = connectionString;
        }

        private static bool HasColumn(SqlDataReader reader, string name)
        {
            for (int i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), name, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }

        private MainFlockBatchModel MapFromReader(SqlDataReader reader)
        {
            var model = new MainFlockBatchModel
            {
                BatchId = reader.GetInt32(reader.GetOrdinal("BatchId")),
                FarmId = reader.GetString(reader.GetOrdinal("FarmId")),
                UserId = reader.GetString(reader.GetOrdinal("UserId")),
                BatchCode = reader.GetString(reader.GetOrdinal("BatchCode")),
                BatchName = reader.GetString(reader.GetOrdinal("BatchName")),
                Breed = reader.GetString(reader.GetOrdinal("Breed")),
                NumberOfBirds = reader.GetInt32(reader.GetOrdinal("NumberOfBirds")),
                StartDate = reader.GetDateTime(reader.GetOrdinal("StartDate")),
                CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate"))
            };

            // Optional columns added in migration 021 — tolerate older sp shapes during rollout.
            if (HasColumn(reader, "Status"))
            {
                int o = reader.GetOrdinal("Status");
                model.Status = reader.IsDBNull(o) ? "active" : reader.GetString(o);
            }
            if (HasColumn(reader, "CostPerChick"))
            {
                int o = reader.GetOrdinal("CostPerChick");
                model.CostPerChick = reader.IsDBNull(o) ? 0m : reader.GetDecimal(o);
            }
            if (HasColumn(reader, "DollarConversionRate"))
            {
                int o = reader.GetOrdinal("DollarConversionRate");
                model.DollarConversionRate = reader.IsDBNull(o) ? (decimal?)null : reader.GetDecimal(o);
            }
            if (HasColumn(reader, "TotalCost"))
            {
                int o = reader.GetOrdinal("TotalCost");
                model.TotalCost = reader.IsDBNull(o) ? 0m : reader.GetDecimal(o);
            }
            if (HasColumn(reader, "AmountPaid"))
            {
                int o = reader.GetOrdinal("AmountPaid");
                model.AmountPaid = reader.IsDBNull(o) ? 0m : reader.GetDecimal(o);
            }
            if (HasColumn(reader, "SupplierType"))
            {
                int o = reader.GetOrdinal("SupplierType");
                model.SupplierType = reader.IsDBNull(o) ? string.Empty : reader.GetString(o);
            }
            if (HasColumn(reader, "SupplierId"))
            {
                int o = reader.GetOrdinal("SupplierId");
                model.SupplierId = reader.IsDBNull(o) ? (int?)null : reader.GetInt32(o);
            }
            if (HasColumn(reader, "SupplierName"))
            {
                int o = reader.GetOrdinal("SupplierName");
                model.SupplierName = reader.IsDBNull(o) ? string.Empty : reader.GetString(o);
            }
            if (HasColumn(reader, "Notes"))
            {
                int o = reader.GetOrdinal("Notes");
                model.Notes = reader.IsDBNull(o) ? null : reader.GetString(o);
            }

            return model;
        }

        public async Task<int> Insert(MainFlockBatchModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spMainFlockBatch_Insert", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@BatchCode", model.BatchCode);
                cmd.Parameters.AddWithValue("@BatchName", model.BatchName);
                cmd.Parameters.AddWithValue("@Breed", model.Breed);
                cmd.Parameters.AddWithValue("@NumberOfBirds", model.NumberOfBirds);
                cmd.Parameters.AddWithValue("@StartDate", model.StartDate);
                cmd.Parameters.AddWithValue("@Status", (object?)model.Status ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@CostPerChick", model.CostPerChick);
                cmd.Parameters.AddWithValue("@TotalCost", model.TotalCost);
                cmd.Parameters.AddWithValue("@AmountPaid", model.AmountPaid);
                cmd.Parameters.AddWithValue("@SupplierType", (object?)model.SupplierType ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@SupplierId", (object?)model.SupplierId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Notes", (object?)model.Notes ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@DollarConversionRate", (object?)model.DollarConversionRate ?? DBNull.Value);

                await conn.OpenAsync();
                var result = await cmd.ExecuteScalarAsync();
                // ExecuteScalarAsync returns the identity value (BatchId) from the stored procedure.
                return Convert.ToInt32(result);
            }
            catch (Exception ex)
            {
                // In a real application, you would log 'ex' details.
                throw new Exception("Error inserting Main Flock Batch record.", ex);
            }
        }

        public async Task Update(MainFlockBatchModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spMainFlockBatch_Update", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@BatchId", model.BatchId);
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@BatchCode", model.BatchCode);
                cmd.Parameters.AddWithValue("@BatchName", model.BatchName);
                cmd.Parameters.AddWithValue("@Breed", model.Breed);
                cmd.Parameters.AddWithValue("@NumberOfBirds", model.NumberOfBirds);
                cmd.Parameters.AddWithValue("@StartDate", model.StartDate);
                cmd.Parameters.AddWithValue("@Status", (object?)model.Status ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@CostPerChick", model.CostPerChick);
                cmd.Parameters.AddWithValue("@TotalCost", model.TotalCost);
                cmd.Parameters.AddWithValue("@AmountPaid", model.AmountPaid);
                cmd.Parameters.AddWithValue("@SupplierType", (object?)model.SupplierType ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@SupplierId", (object?)model.SupplierId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Notes", (object?)model.Notes ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@DollarConversionRate", (object?)model.DollarConversionRate ?? DBNull.Value);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error updating Main Flock Batch ID={model.BatchId}.", ex);
            }
        }

        public async Task<MainFlockBatchModel?> GetById(int batchId, string userId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spMainFlockBatch_GetById", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@BatchId", batchId);
                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return MapFromReader(reader);
                }
                return null;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error retrieving Main Flock Batch ID={batchId}.", ex);
            }
        }

        public async Task<List<MainFlockBatchModel>> GetAll(string userId, string farmId)
        {
            try
            {
                var list = new List<MainFlockBatchModel>();
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spMainFlockBatch_GetAll", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(MapFromReader(reader));
                }
                return list;
            }
            catch (Exception ex)
            {
                throw new Exception("Error retrieving all Main Flock Batches.", ex);
            }
        }

        public async Task Delete(int batchId, string userId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spMainFlockBatch_Delete", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@BatchId", batchId);
                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error deleting Main Flock Batch ID={batchId}.", ex);
            }
        }
    }
}
