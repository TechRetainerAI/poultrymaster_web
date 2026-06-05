using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericServiceCatalogService : IGenericServiceCatalogService
    {
        private readonly string _connectionString;
        public GenericServiceCatalogService(string connectionString) => _connectionString = connectionString;

        // ====================================================================
        // Categories
        // ====================================================================
        public async Task<List<GenericServiceCategoryModel>> GetCategoriesAsync(string farmId)
        {
            var list = new List<GenericServiceCategoryModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericServiceCategory_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadCategory(reader));
            return list;
        }

        public async Task<int> InsertCategoryAsync(GenericServiceCategoryModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericServiceCategory_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateCategoryAsync(GenericServiceCategoryModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericServiceCategory_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericServiceCategoryId", m.GenericServiceCategoryId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteCategoryAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericServiceCategory_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericServiceCategoryId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ====================================================================
        // Services
        // ====================================================================
        public async Task<List<GenericServiceModel>> GetAllAsync(string farmId)
        {
            var list = new List<GenericServiceModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericService_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadService(reader));
            return list;
        }

        public async Task<GenericServiceModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericService_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericServiceId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? ReadService(reader) : null;
        }

        public async Task<int> InsertAsync(GenericServiceModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericService_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@GenericServiceCategoryId", (object?)m.GenericServiceCategoryId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ServiceName", m.ServiceName);
            cmd.Parameters.AddWithValue("@DefaultPrice", m.DefaultPrice);
            cmd.Parameters.AddWithValue("@EstimatedCost", (object?)m.EstimatedCost ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DurationMinutes", (object?)m.DurationMinutes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AssignedStaffId", (object?)m.AssignedStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(GenericServiceModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericService_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericServiceId", m.GenericServiceId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@GenericServiceCategoryId", (object?)m.GenericServiceCategoryId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ServiceName", m.ServiceName);
            cmd.Parameters.AddWithValue("@DefaultPrice", m.DefaultPrice);
            cmd.Parameters.AddWithValue("@EstimatedCost", (object?)m.EstimatedCost ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DurationMinutes", (object?)m.DurationMinutes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AssignedStaffId", (object?)m.AssignedStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericService_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericServiceId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ====================================================================
        // Helpers
        // ====================================================================
        private static GenericServiceCategoryModel ReadCategory(SqlDataReader r) => new()
        {
            GenericServiceCategoryId = r.GetInt32(r.GetOrdinal("GenericServiceCategoryId")),
            FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
            Name                     = r.GetString(r.GetOrdinal("Name")),
            Description              = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
            IsActive                 = r.GetBoolean(r.GetOrdinal("IsActive")),
            IsDeleted                = r.GetBoolean(r.GetOrdinal("IsDeleted")),
            CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        private static GenericServiceModel ReadService(SqlDataReader r) => new()
        {
            GenericServiceId         = r.GetInt32(r.GetOrdinal("GenericServiceId")),
            FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
            GenericServiceCategoryId = r.IsDBNull(r.GetOrdinal("GenericServiceCategoryId")) ? null : r.GetInt32(r.GetOrdinal("GenericServiceCategoryId")),
            CategoryName             = r.IsDBNull(r.GetOrdinal("CategoryName")) ? null : r.GetString(r.GetOrdinal("CategoryName")),
            ServiceName              = r.GetString(r.GetOrdinal("ServiceName")),
            DefaultPrice             = r.GetDecimal(r.GetOrdinal("DefaultPrice")),
            EstimatedCost            = r.IsDBNull(r.GetOrdinal("EstimatedCost")) ? null : r.GetDecimal(r.GetOrdinal("EstimatedCost")),
            DurationMinutes          = r.IsDBNull(r.GetOrdinal("DurationMinutes")) ? null : r.GetInt32(r.GetOrdinal("DurationMinutes")),
            AssignedStaffId          = r.IsDBNull(r.GetOrdinal("AssignedStaffId")) ? null : r.GetInt32(r.GetOrdinal("AssignedStaffId")),
            IsActive                 = r.GetBoolean(r.GetOrdinal("IsActive")),
            IsDeleted                = r.GetBoolean(r.GetOrdinal("IsDeleted")),
            Notes                    = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }
}
