using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericExpenseRecordService : IGenericExpenseRecordService
    {
        private readonly string _connectionString;
        public GenericExpenseRecordService(string connectionString) => _connectionString = connectionString;

        public async Task<List<GenericExpenseModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<GenericExpenseModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericExpense_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",   (object?)toDate   ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadExpense(reader));
            return list;
        }

        public async Task<GenericExpenseModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericExpense_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? ReadExpense(reader) : null;
        }

        public async Task<int> InsertAsync(GenericExpenseModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericExpense_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@ExpenseDate",
                m.ExpenseDate == default ? (object)DBNull.Value : m.ExpenseDate);
            cmd.Parameters.AddWithValue("@GenericExpenseCategoryId", m.GenericExpenseCategoryId);
            cmd.Parameters.AddWithValue("@GenericSupplierId", (object?)m.GenericSupplierId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Amount", m.Amount);
            cmd.Parameters.AddWithValue("@PaidTo", (object?)m.PaidTo ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaymentMethod", m.PaymentMethod);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", (object?)m.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ReceiptUrl", (object?)m.ReceiptUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BranchId", (object?)m.BranchId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StaffId", (object?)m.StaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericExpense_Approve", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task RejectAsync(int id, string farmId, string rejectionReason, string? approvedBy)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericExpense_Reject", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@RejectionReason", rejectionReason);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static GenericExpenseModel ReadExpense(SqlDataReader r) => new()
        {
            GenericExpenseId         = r.GetInt32(r.GetOrdinal("GenericExpenseId")),
            FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
            ExpenseDate              = r.GetDateTime(r.GetOrdinal("ExpenseDate")),
            GenericExpenseCategoryId = r.GetInt32(r.GetOrdinal("GenericExpenseCategoryId")),
            CategoryName             = r.IsDBNull(r.GetOrdinal("CategoryName")) ? null : r.GetString(r.GetOrdinal("CategoryName")),
            GenericSupplierId        = r.IsDBNull(r.GetOrdinal("GenericSupplierId")) ? null : r.GetInt32(r.GetOrdinal("GenericSupplierId")),
            SupplierName             = r.IsDBNull(r.GetOrdinal("SupplierName")) ? null : r.GetString(r.GetOrdinal("SupplierName")),
            Description              = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
            Amount                   = r.GetDecimal(r.GetOrdinal("Amount")),
            PaidTo                   = r.IsDBNull(r.GetOrdinal("PaidTo")) ? null : r.GetString(r.GetOrdinal("PaidTo")),
            PaymentMethod            = r.GetString(r.GetOrdinal("PaymentMethod")),
            GenericCashAccountId     = r.IsDBNull(r.GetOrdinal("GenericCashAccountId")) ? null : r.GetInt32(r.GetOrdinal("GenericCashAccountId")),
            ReceiptUrl               = r.IsDBNull(r.GetOrdinal("ReceiptUrl")) ? null : r.GetString(r.GetOrdinal("ReceiptUrl")),
            BranchId                 = r.IsDBNull(r.GetOrdinal("BranchId")) ? null : r.GetInt32(r.GetOrdinal("BranchId")),
            StaffId                  = r.IsDBNull(r.GetOrdinal("StaffId")) ? null : r.GetInt32(r.GetOrdinal("StaffId")),
            Status                   = r.GetString(r.GetOrdinal("Status")),
            Notes                    = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy                = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy               = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt               = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            RejectionReason          = r.IsDBNull(r.GetOrdinal("RejectionReason")) ? null : r.GetString(r.GetOrdinal("RejectionReason")),
            CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }
}
