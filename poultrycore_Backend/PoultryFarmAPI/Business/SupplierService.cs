using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class SupplierService : ISupplierService
    {
        private readonly string _connectionString;

        public SupplierService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<int> Insert(SupplierModel model)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spSupplier_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@UserId", model.UserId);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@Name", model.Name);
            cmd.Parameters.AddWithValue("@ContactEmail", (object?)model.ContactEmail ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ContactPhone", (object?)model.ContactPhone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Address", (object?)model.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@City", (object?)model.City ?? DBNull.Value);
            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return Convert.ToInt32(result);
        }

        public async Task Update(SupplierModel model)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spSupplier_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@UserId", model.UserId);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@SupplierId", model.SupplierId);
            cmd.Parameters.AddWithValue("@Name", model.Name);
            cmd.Parameters.AddWithValue("@ContactEmail", (object?)model.ContactEmail ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ContactPhone", (object?)model.ContactPhone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Address", (object?)model.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@City", (object?)model.City ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<SupplierModel?> GetById(int supplierId, string userId, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spSupplier_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@SupplierId", supplierId);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
                return ReadSupplier(reader);
            return null;
        }

        public async Task<List<SupplierModel>> GetAll(string userId, string farmId)
        {
            var list = new List<SupplierModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spSupplier_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
                list.Add(ReadSupplier(reader));
            return list;
        }

        public async Task Delete(int supplierId, string userId, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spSupplier_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@SupplierId", supplierId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static SupplierModel ReadSupplier(SqlDataReader reader)
        {
            return new SupplierModel
            {
                SupplierId = reader.GetInt32(reader.GetOrdinal("SupplierId")),
                Name = reader.GetString(reader.GetOrdinal("Name")),
                ContactEmail = reader.IsDBNull(reader.GetOrdinal("ContactEmail")) ? null : reader.GetString(reader.GetOrdinal("ContactEmail")),
                ContactPhone = reader.IsDBNull(reader.GetOrdinal("ContactPhone")) ? null : reader.GetString(reader.GetOrdinal("ContactPhone")),
                Address = reader.IsDBNull(reader.GetOrdinal("Address")) ? null : reader.GetString(reader.GetOrdinal("Address")),
                City = reader.IsDBNull(reader.GetOrdinal("City")) ? null : reader.GetString(reader.GetOrdinal("City")),
                CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                FarmId = reader.IsDBNull(reader.GetOrdinal("FarmId")) ? "" : reader.GetString(reader.GetOrdinal("FarmId")),
                UserId = "",
            };
        }
    }
}
