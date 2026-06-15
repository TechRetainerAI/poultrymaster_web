using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericCompanyService : IGenericCompanyService
    {
        private readonly string _connectionString;

        public GenericCompanyService(string connectionString)
        {
            _connectionString = connectionString;
        }

        // =================================================================
        // BusinessCategories
        // =================================================================
        public async Task<List<BusinessCategoryModel>> GetBusinessCategoriesAsync()
        {
            var list = new List<BusinessCategoryModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spBusinessCategory_GetAll", conn) { CommandType = CommandType.StoredProcedure };

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new BusinessCategoryModel
                {
                    BusinessCategoryId = reader.GetInt32(reader.GetOrdinal("BusinessCategoryId")),
                    Name               = reader.GetString(reader.GetOrdinal("Name")),
                    Description        = reader.IsDBNull(reader.GetOrdinal("Description")) ? null : reader.GetString(reader.GetOrdinal("Description")),
                    SortOrder          = reader.GetInt32(reader.GetOrdinal("SortOrder")),
                    IsActive           = reader.GetBoolean(reader.GetOrdinal("IsActive")),
                    CreatedAt          = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                    UpdatedAt          = reader.IsDBNull(reader.GetOrdinal("UpdatedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("UpdatedAt")),
                });
            }
            return list;
        }

        // =================================================================
        // Profile + setup
        // =================================================================
        public async Task<GenericCompanyProfileModel?> SetupAsync(GenericCompanySetupRequest req)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCompany_Setup", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@BusinessCategoryId",  (object?)req.BusinessCategoryId  ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BusinessDescription", (object?)req.BusinessDescription ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultCurrency",     (object?)req.DefaultCurrency     ?? (object)"GHC");
            cmd.Parameters.AddWithValue("@OpeningCashBalance",  (object?)req.OpeningCashBalance  ?? (object)0m);
            cmd.Parameters.AddWithValue("@BusinessStartDate",   (object?)req.BusinessStartDate   ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MainLocation",        (object?)req.MainLocation        ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OwnerName",           (object?)req.OwnerName           ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PhoneNumber",         (object?)req.PhoneNumber         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",               (object?)req.Notes               ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync()) return ReadProfile(reader);
            return null;
        }

        public async Task<GenericCompanyProfileModel?> GetProfileAsync(string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCompany_GetProfile", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync()) return ReadProfile(reader);
            return null;
        }

        public async Task<GenericCompanyProfileModel?> UpdateProfileAsync(string farmId, GenericCompanyUpdateRequest req)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCompany_UpdateProfile", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@BusinessCategoryId",  (object?)req.BusinessCategoryId  ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BusinessDescription", (object?)req.BusinessDescription ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultCurrency",     (object?)req.DefaultCurrency     ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OpeningCashBalance",  (object?)req.OpeningCashBalance  ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BusinessStartDate",   (object?)req.BusinessStartDate   ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MainLocation",        (object?)req.MainLocation        ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OwnerName",           (object?)req.OwnerName           ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PhoneNumber",         (object?)req.PhoneNumber         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",               (object?)req.Notes               ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync()) return ReadProfile(reader);
            return null;
        }

        // =================================================================
        // Expense categories
        // =================================================================
        public async Task<List<GenericExpenseCategoryModel>> GetExpenseCategoriesAsync(string farmId)
        {
            var list = new List<GenericExpenseCategoryModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericExpenseCategory_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericExpenseCategoryModel
                {
                    GenericExpenseCategoryId = reader.GetInt32(reader.GetOrdinal("GenericExpenseCategoryId")),
                    FarmId                   = reader.GetString(reader.GetOrdinal("FarmId")),
                    Name                     = reader.GetString(reader.GetOrdinal("Name")),
                    Description              = reader.IsDBNull(reader.GetOrdinal("Description")) ? null : reader.GetString(reader.GetOrdinal("Description")),
                    IsActive                 = reader.GetBoolean(reader.GetOrdinal("IsActive")),
                    IsDeleted                = reader.GetBoolean(reader.GetOrdinal("IsDeleted")),
                    CreatedAt                = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                    UpdatedAt                = reader.IsDBNull(reader.GetOrdinal("UpdatedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("UpdatedAt")),
                });
            }
            return list;
        }

        public async Task<int> InsertExpenseCategoryAsync(GenericExpenseCategoryModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericExpenseCategory_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateExpenseCategoryAsync(GenericExpenseCategoryModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericExpenseCategory_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericExpenseCategoryId", m.GenericExpenseCategoryId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteExpenseCategoryAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericExpenseCategory_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericExpenseCategoryId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =================================================================
        // Cash accounts
        // =================================================================
        public async Task<List<GenericCashAccountModel>> GetCashAccountsAsync(string farmId)
        {
            var list = new List<GenericCashAccountModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashAccount_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericCashAccountModel
                {
                    GenericCashAccountId = reader.GetInt32(reader.GetOrdinal("GenericCashAccountId")),
                    FarmId               = reader.GetString(reader.GetOrdinal("FarmId")),
                    AccountName          = reader.GetString(reader.GetOrdinal("AccountName")),
                    AccountType          = reader.GetString(reader.GetOrdinal("AccountType")),
                    OpeningBalance       = reader.GetDecimal(reader.GetOrdinal("OpeningBalance")),
                    CurrentBalance       = reader.GetDecimal(reader.GetOrdinal("CurrentBalance")),
                    AllowNegativeBalance = reader.GetBoolean(reader.GetOrdinal("AllowNegativeBalance")),
                    IsActive             = reader.GetBoolean(reader.GetOrdinal("IsActive")),
                    Notes                = reader.IsDBNull(reader.GetOrdinal("Notes")) ? null : reader.GetString(reader.GetOrdinal("Notes")),
                    CreatedAt            = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                    UpdatedAt            = reader.IsDBNull(reader.GetOrdinal("UpdatedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("UpdatedAt")),
                    NegativeBalancePolicy = HasCol(reader, "NegativeBalancePolicy") && !reader.IsDBNull(reader.GetOrdinal("NegativeBalancePolicy"))
                                            ? reader.GetString(reader.GetOrdinal("NegativeBalancePolicy")) : "DoNotAllow",
                    NegativeBalanceLimit  = HasCol(reader, "NegativeBalanceLimit") && !reader.IsDBNull(reader.GetOrdinal("NegativeBalanceLimit"))
                                            ? reader.GetDecimal(reader.GetOrdinal("NegativeBalanceLimit")) : 0m,
                    LastReconciledAt      = HasCol(reader, "LastReconciledAt") && !reader.IsDBNull(reader.GetOrdinal("LastReconciledAt"))
                                            ? reader.GetDateTime(reader.GetOrdinal("LastReconciledAt")) : (DateTime?)null,
                    LastReconciledBalance = HasCol(reader, "LastReconciledBalance") && !reader.IsDBNull(reader.GetOrdinal("LastReconciledBalance"))
                                            ? reader.GetDecimal(reader.GetOrdinal("LastReconciledBalance")) : (decimal?)null,
                });
            }
            return list;
        }

        private static bool HasCol(SqlDataReader r, string name)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        public async Task<int> InsertCashAccountAsync(GenericCashAccountModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashAccount_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@AccountName", m.AccountName);
            cmd.Parameters.AddWithValue("@AccountType", m.AccountType);
            cmd.Parameters.AddWithValue("@OpeningBalance", m.OpeningBalance);
            cmd.Parameters.AddWithValue("@AllowNegativeBalance", m.AllowNegativeBalance);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@NegativeBalancePolicy", string.IsNullOrWhiteSpace(m.NegativeBalancePolicy) ? DBNull.Value : m.NegativeBalancePolicy);
            cmd.Parameters.AddWithValue("@NegativeBalanceLimit", m.NegativeBalanceLimit);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateCashAccountAsync(GenericCashAccountModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashAccount_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericCashAccountId", m.GenericCashAccountId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@AccountName", m.AccountName);
            cmd.Parameters.AddWithValue("@AccountType", m.AccountType);
            cmd.Parameters.AddWithValue("@AllowNegativeBalance", m.AllowNegativeBalance);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@NegativeBalancePolicy", string.IsNullOrWhiteSpace(m.NegativeBalancePolicy) ? DBNull.Value : m.NegativeBalancePolicy);
            cmd.Parameters.AddWithValue("@NegativeBalanceLimit", m.NegativeBalanceLimit);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteCashAccountAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashAccount_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericCashAccountId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =================================================================
        // Read-only lookup lists
        // =================================================================
        public async Task<List<GenericCustomerTypeModel>> GetCustomerTypesAsync(string farmId)
        {
            var list = new List<GenericCustomerTypeModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCustomerType_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericCustomerTypeModel
                {
                    GenericCustomerTypeId = reader.GetInt32(reader.GetOrdinal("GenericCustomerTypeId")),
                    FarmId                = reader.GetString(reader.GetOrdinal("FarmId")),
                    Name                  = reader.GetString(reader.GetOrdinal("Name")),
                    IsActive              = reader.GetBoolean(reader.GetOrdinal("IsActive")),
                    CreatedAt             = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                    UpdatedAt             = reader.IsDBNull(reader.GetOrdinal("UpdatedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("UpdatedAt")),
                });
            }
            return list;
        }

        public async Task<List<GenericSupplierTypeModel>> GetSupplierTypesAsync(string farmId)
        {
            var list = new List<GenericSupplierTypeModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSupplierType_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericSupplierTypeModel
                {
                    GenericSupplierTypeId = reader.GetInt32(reader.GetOrdinal("GenericSupplierTypeId")),
                    FarmId                = reader.GetString(reader.GetOrdinal("FarmId")),
                    Name                  = reader.GetString(reader.GetOrdinal("Name")),
                    IsActive              = reader.GetBoolean(reader.GetOrdinal("IsActive")),
                    CreatedAt             = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                    UpdatedAt             = reader.IsDBNull(reader.GetOrdinal("UpdatedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("UpdatedAt")),
                });
            }
            return list;
        }

        public async Task<List<GenericPaymentMethodModel>> GetPaymentMethodsAsync(string farmId)
        {
            var list = new List<GenericPaymentMethodModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericPaymentMethod_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericPaymentMethodModel
                {
                    GenericPaymentMethodId = reader.GetInt32(reader.GetOrdinal("GenericPaymentMethodId")),
                    FarmId                 = reader.GetString(reader.GetOrdinal("FarmId")),
                    Name                   = reader.GetString(reader.GetOrdinal("Name")),
                    IsActive               = reader.GetBoolean(reader.GetOrdinal("IsActive")),
                    CreatedAt              = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                    UpdatedAt              = reader.IsDBNull(reader.GetOrdinal("UpdatedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("UpdatedAt")),
                });
            }
            return list;
        }

        // =================================================================
        // Farm type lookup (used by controllers to enforce Type='Generic').
        // =================================================================
        public async Task<string?> GetFarmTypeAsync(string farmId)
        {
            // Uses spFarm_GetType (migration 042). The runtime app user has
            // EXECUTE on dbo procs but NOT direct SELECT on dbo.Farms, so a
            // raw "SELECT Type FROM dbo.Farms" fails with SQL error 229.
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spFarm_GetType", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return result == null || result == DBNull.Value ? null : (string)result;
        }

        // =================================================================
        // Helpers
        // =================================================================
        private static GenericCompanyProfileModel ReadProfile(SqlDataReader r) => new()
        {
            GenericCompanyProfileId      = r.GetInt32(r.GetOrdinal("GenericCompanyProfileId")),
            FarmId                       = r.GetString(r.GetOrdinal("FarmId")),
            BusinessCategoryId           = r.IsDBNull(r.GetOrdinal("BusinessCategoryId")) ? null : r.GetInt32(r.GetOrdinal("BusinessCategoryId")),
            BusinessCategoryNameSnapshot = r.IsDBNull(r.GetOrdinal("BusinessCategoryNameSnapshot")) ? null : r.GetString(r.GetOrdinal("BusinessCategoryNameSnapshot")),
            BusinessCategoryName         = HasColumn(r, "BusinessCategoryName") && !r.IsDBNull(r.GetOrdinal("BusinessCategoryName")) ? r.GetString(r.GetOrdinal("BusinessCategoryName")) : null,
            BusinessDescription          = r.IsDBNull(r.GetOrdinal("BusinessDescription")) ? null : r.GetString(r.GetOrdinal("BusinessDescription")),
            DefaultCurrency              = r.GetString(r.GetOrdinal("DefaultCurrency")),
            OpeningCashBalance           = r.GetDecimal(r.GetOrdinal("OpeningCashBalance")),
            BusinessStartDate            = r.IsDBNull(r.GetOrdinal("BusinessStartDate")) ? null : r.GetDateTime(r.GetOrdinal("BusinessStartDate")),
            MainLocation                 = r.IsDBNull(r.GetOrdinal("MainLocation")) ? null : r.GetString(r.GetOrdinal("MainLocation")),
            OwnerName                    = r.IsDBNull(r.GetOrdinal("OwnerName")) ? null : r.GetString(r.GetOrdinal("OwnerName")),
            PhoneNumber                  = r.IsDBNull(r.GetOrdinal("PhoneNumber")) ? null : r.GetString(r.GetOrdinal("PhoneNumber")),
            Notes                        = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt                    = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                    = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        private static bool HasColumn(SqlDataReader r, string name)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (r.GetName(i).Equals(name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }
}
