using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericSupplierService : IGenericSupplierService
    {
        private readonly string _connectionString;
        public GenericSupplierService(string connectionString) => _connectionString = connectionString;

        // ====================================================================
        // Suppliers
        // ====================================================================
        public async Task<List<GenericSupplierModel>> GetAllAsync(string farmId)
        {
            var list = new List<GenericSupplierModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSupplier_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadSupplier(reader));
            return list;
        }

        public async Task<GenericSupplierModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSupplier_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericSupplierId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? ReadSupplier(reader) : null;
        }

        public async Task<int> InsertAsync(GenericSupplierModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSupplier_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@SupplierName", m.SupplierName);
            cmd.Parameters.AddWithValue("@SupplierType", m.SupplierType);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)m.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Location", (object?)m.Location ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Address", (object?)m.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaymentTermsDays", m.PaymentTermsDays);
            cmd.Parameters.AddWithValue("@OpeningBalance", m.OpeningBalance);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(GenericSupplierModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSupplier_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericSupplierId", m.GenericSupplierId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@SupplierName", m.SupplierName);
            cmd.Parameters.AddWithValue("@SupplierType", m.SupplierType);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)m.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Location", (object?)m.Location ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Address", (object?)m.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaymentTermsDays", m.PaymentTermsDays);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSupplier_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericSupplierId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<GenericSupplierOwedRowModel>> GetOwedToThemAsync(string farmId)
        {
            var list = new List<GenericSupplierOwedRowModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSupplier_GetOwedToThem", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericSupplierOwedRowModel
                {
                    GenericSupplierId = reader.GetInt32(reader.GetOrdinal("GenericSupplierId")),
                    FarmId            = reader.GetString(reader.GetOrdinal("FarmId")),
                    SupplierName      = reader.GetString(reader.GetOrdinal("SupplierName")),
                    SupplierType      = reader.IsDBNull(reader.GetOrdinal("SupplierType")) ? null : reader.GetString(reader.GetOrdinal("SupplierType")),
                    PhoneNumber       = reader.IsDBNull(reader.GetOrdinal("PhoneNumber")) ? null : reader.GetString(reader.GetOrdinal("PhoneNumber")),
                    PaymentTermsDays  = reader.GetInt32(reader.GetOrdinal("PaymentTermsDays")),
                    CurrentBalance    = reader.GetDecimal(reader.GetOrdinal("CurrentBalance")),
                });
            }
            return list;
        }

        // ====================================================================
        // Ledger
        // ====================================================================
        public async Task<List<GenericSupplierLedgerEntryModel>> GetLedgerAsync(int supplierId, string farmId)
        {
            var list = new List<GenericSupplierLedgerEntryModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSupplierLedger_GetForSupplier", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericSupplierId", supplierId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericSupplierLedgerEntryModel
                {
                    GenericSupplierLedgerId = reader.GetInt64(reader.GetOrdinal("GenericSupplierLedgerId")),
                    FarmId                  = reader.GetString(reader.GetOrdinal("FarmId")),
                    GenericSupplierId       = reader.GetInt32(reader.GetOrdinal("GenericSupplierId")),
                    TransactionDate         = reader.GetDateTime(reader.GetOrdinal("TransactionDate")),
                    TransactionType         = reader.GetString(reader.GetOrdinal("TransactionType")),
                    PurchaseId              = reader.IsDBNull(reader.GetOrdinal("PurchaseId")) ? null : reader.GetInt32(reader.GetOrdinal("PurchaseId")),
                    ExpenseId               = reader.IsDBNull(reader.GetOrdinal("ExpenseId")) ? null : reader.GetInt32(reader.GetOrdinal("ExpenseId")),
                    PaymentId               = reader.IsDBNull(reader.GetOrdinal("PaymentId")) ? null : reader.GetInt32(reader.GetOrdinal("PaymentId")),
                    DebitAmount             = reader.GetDecimal(reader.GetOrdinal("DebitAmount")),
                    CreditAmount            = reader.GetDecimal(reader.GetOrdinal("CreditAmount")),
                    BalanceAfterTransaction = reader.GetDecimal(reader.GetOrdinal("BalanceAfterTransaction")),
                    Description             = reader.IsDBNull(reader.GetOrdinal("Description")) ? null : reader.GetString(reader.GetOrdinal("Description")),
                    CreatedBy               = reader.IsDBNull(reader.GetOrdinal("CreatedBy")) ? null : reader.GetString(reader.GetOrdinal("CreatedBy")),
                    CreatedAt               = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                });
            }
            return list;
        }

        // ====================================================================
        // Supplier payments
        // ====================================================================
        public async Task<List<GenericSupplierPaymentModel>> GetPaymentsAsync(string farmId, string? status)
        {
            var list = new List<GenericSupplierPaymentModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSupplierPayment_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadPayment(reader));
            return list;
        }

        public async Task<GenericSupplierPaymentModel?> GetPaymentByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSupplierPayment_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericSupplierPaymentId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? ReadPayment(reader) : null;
        }

        public async Task<int> InsertPaymentAsync(GenericSupplierPaymentModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSupplierPayment_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@GenericSupplierId", m.GenericSupplierId);
            cmd.Parameters.AddWithValue("@Amount", m.Amount);
            cmd.Parameters.AddWithValue("@PaymentMethod", m.PaymentMethod);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", (object?)m.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaidByStaffId", (object?)m.PaidByStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LinkedPurchaseId", (object?)m.LinkedPurchaseId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LinkedExpenseId", (object?)m.LinkedExpenseId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaymentDate",
                m.PaymentDate == default ? (object)DBNull.Value : m.PaymentDate);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ApprovePaymentAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSupplierPayment_Approve", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericSupplierPaymentId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelPaymentAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSupplierPayment_Cancel", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericSupplierPaymentId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ====================================================================
        // Helpers
        // ====================================================================
        private static GenericSupplierModel ReadSupplier(SqlDataReader r) => new()
        {
            GenericSupplierId = r.GetInt32(r.GetOrdinal("GenericSupplierId")),
            FarmId            = r.GetString(r.GetOrdinal("FarmId")),
            SupplierName      = r.GetString(r.GetOrdinal("SupplierName")),
            SupplierType      = r.GetString(r.GetOrdinal("SupplierType")),
            PhoneNumber       = r.IsDBNull(r.GetOrdinal("PhoneNumber")) ? null : r.GetString(r.GetOrdinal("PhoneNumber")),
            Email             = r.IsDBNull(r.GetOrdinal("Email")) ? null : r.GetString(r.GetOrdinal("Email")),
            Location          = r.IsDBNull(r.GetOrdinal("Location")) ? null : r.GetString(r.GetOrdinal("Location")),
            Address           = r.IsDBNull(r.GetOrdinal("Address")) ? null : r.GetString(r.GetOrdinal("Address")),
            PaymentTermsDays  = r.GetInt32(r.GetOrdinal("PaymentTermsDays")),
            OpeningBalance    = r.GetDecimal(r.GetOrdinal("OpeningBalance")),
            CurrentBalance    = r.GetDecimal(r.GetOrdinal("CurrentBalance")),
            IsActive          = r.GetBoolean(r.GetOrdinal("IsActive")),
            IsDeleted         = r.GetBoolean(r.GetOrdinal("IsDeleted")),
            Notes             = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt         = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt         = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        private static GenericSupplierPaymentModel ReadPayment(SqlDataReader r) => new()
        {
            GenericSupplierPaymentId = r.GetInt32(r.GetOrdinal("GenericSupplierPaymentId")),
            FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
            GenericSupplierId        = r.GetInt32(r.GetOrdinal("GenericSupplierId")),
            SupplierName             = r.IsDBNull(r.GetOrdinal("SupplierName")) ? null : r.GetString(r.GetOrdinal("SupplierName")),
            PaymentDate              = r.GetDateTime(r.GetOrdinal("PaymentDate")),
            Amount                   = r.GetDecimal(r.GetOrdinal("Amount")),
            PaymentMethod            = r.GetString(r.GetOrdinal("PaymentMethod")),
            GenericCashAccountId     = r.IsDBNull(r.GetOrdinal("GenericCashAccountId")) ? null : r.GetInt32(r.GetOrdinal("GenericCashAccountId")),
            PaidByStaffId            = r.IsDBNull(r.GetOrdinal("PaidByStaffId")) ? null : r.GetInt32(r.GetOrdinal("PaidByStaffId")),
            LinkedPurchaseId         = r.IsDBNull(r.GetOrdinal("LinkedPurchaseId")) ? null : r.GetInt32(r.GetOrdinal("LinkedPurchaseId")),
            LinkedExpenseId          = r.IsDBNull(r.GetOrdinal("LinkedExpenseId")) ? null : r.GetInt32(r.GetOrdinal("LinkedExpenseId")),
            Status                   = r.GetString(r.GetOrdinal("Status")),
            Notes                    = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy                = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy               = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt               = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }
}
