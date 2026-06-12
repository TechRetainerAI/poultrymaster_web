using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class WaterCustomerService : IWaterCustomerService
    {
        private readonly string _connectionString;

        public WaterCustomerService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<int> Insert(WaterCustomerModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterCustomer_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@ContactPhone", (object?)m.ContactPhone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ContactEmail", (object?)m.ContactEmail ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Address", (object?)m.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@City", (object?)m.City ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task Update(WaterCustomerModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterCustomer_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterCustomerId", m.WaterCustomerId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@ContactPhone", (object?)m.ContactPhone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ContactEmail", (object?)m.ContactEmail ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Address", (object?)m.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@City", (object?)m.City ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<WaterCustomerModel?> GetById(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterCustomer_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterCustomerId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync()) return Read(reader, includeOutstanding: false);
            return null;
        }

        public async Task<List<WaterCustomerModel>> GetAll(string farmId)
        {
            var list = new List<WaterCustomerModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterCustomer_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(Read(reader, includeOutstanding: true));
            return list;
        }

        public async Task Delete(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterCustomer_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterCustomerId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // Migration 082 — ensure the 3 default customers exist for this farm.
        public async Task<List<WaterDefaultCustomerResult>> CreateDefaultsAsync(string farmId)
        {
            var list = new List<WaterDefaultCustomerResult>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterCustomer_CreateDefaults", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterDefaultCustomerResult
                {
                    WaterCustomerId     = r.GetInt32(r.GetOrdinal("WaterCustomerId")),
                    DefaultCustomerType = r.GetString(r.GetOrdinal("DefaultCustomerType")),
                    Name                = r.GetString(r.GetOrdinal("Name")),
                    WasCreated          = r.GetBoolean(r.GetOrdinal("WasCreated")),
                });
            }
            return list;
        }

        public async Task<WaterCustomerModel?> GetDefaultAsync(string farmId, string defaultCustomerType)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterCustomer_GetDefault", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@DefaultCustomerType", defaultCustomerType);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return null;
            return new WaterCustomerModel
            {
                WaterCustomerId     = r.GetInt32(r.GetOrdinal("WaterCustomerId")),
                FarmId              = r.GetString(r.GetOrdinal("FarmId")),
                Name                = r.GetString(r.GetOrdinal("Name")),
                CustomerType        = HasColumn(r, "CustomerType") && !r.IsDBNull(r.GetOrdinal("CustomerType")) ? r.GetString(r.GetOrdinal("CustomerType")) : null,
                DefaultCustomerType = HasColumn(r, "DefaultCustomerType") && !r.IsDBNull(r.GetOrdinal("DefaultCustomerType")) ? r.GetString(r.GetOrdinal("DefaultCustomerType")) : null,
                IsDefaultCustomer   = HasColumn(r, "IsDefaultCustomer") && r.GetBoolean(r.GetOrdinal("IsDefaultCustomer")),
                IsSystemGenerated   = HasColumn(r, "IsSystemGenerated") && r.GetBoolean(r.GetOrdinal("IsSystemGenerated")),
                IsActive            = !HasColumn(r, "IsActive") || r.GetBoolean(r.GetOrdinal("IsActive")),
            };
        }

        private static WaterCustomerModel Read(SqlDataReader r, bool includeOutstanding) => new()
        {
            WaterCustomerId    = r.GetInt32(r.GetOrdinal("WaterCustomerId")),
            FarmId             = r.GetString(r.GetOrdinal("FarmId")),
            Name               = r.GetString(r.GetOrdinal("Name")),
            ContactPhone       = r.IsDBNull(r.GetOrdinal("ContactPhone")) ? null : r.GetString(r.GetOrdinal("ContactPhone")),
            ContactEmail       = r.IsDBNull(r.GetOrdinal("ContactEmail")) ? null : r.GetString(r.GetOrdinal("ContactEmail")),
            Address            = r.IsDBNull(r.GetOrdinal("Address")) ? null : r.GetString(r.GetOrdinal("Address")),
            City               = r.IsDBNull(r.GetOrdinal("City")) ? null : r.GetString(r.GetOrdinal("City")),
            Notes              = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedDate        = r.GetDateTime(r.GetOrdinal("CreatedDate")),
            UpdatedDate        = r.IsDBNull(r.GetOrdinal("UpdatedDate")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedDate")),
            OutstandingBalance = includeOutstanding && HasColumn(r, "OutstandingBalance") && !r.IsDBNull(r.GetOrdinal("OutstandingBalance"))
                                    ? r.GetDecimal(r.GetOrdinal("OutstandingBalance")) : 0m,
            // Migration 082 — tolerate older DBs that haven't been migrated yet.
            CustomerType        = HasColumn(r, "CustomerType") && !r.IsDBNull(r.GetOrdinal("CustomerType")) ? r.GetString(r.GetOrdinal("CustomerType")) : null,
            DefaultCustomerType = HasColumn(r, "DefaultCustomerType") && !r.IsDBNull(r.GetOrdinal("DefaultCustomerType")) ? r.GetString(r.GetOrdinal("DefaultCustomerType")) : null,
            IsDefaultCustomer   = HasColumn(r, "IsDefaultCustomer") && r.GetBoolean(r.GetOrdinal("IsDefaultCustomer")),
            IsSystemGenerated   = HasColumn(r, "IsSystemGenerated") && r.GetBoolean(r.GetOrdinal("IsSystemGenerated")),
            IsActive            = !HasColumn(r, "IsActive") || r.GetBoolean(r.GetOrdinal("IsActive")),
        };

        private static bool HasColumn(SqlDataReader r, string name)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (r.GetName(i).Equals(name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }
}
