using System.Data;
using Npgsql;
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericexpense_getall(p_farmid => @FarmId::text, p_status => @Status::text, p_fromdate => @FromDate::timestamp, p_todate => @ToDate::timestamp)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericexpense_getbyid(p_genericexpenseid => @GenericExpenseId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@GenericExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? ReadExpense(reader) : null;
        }

        public async Task<int> InsertAsync(GenericExpenseModel m)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericexpense_insert(p_farmid => @FarmId::text, p_expensedate => @ExpenseDate::timestamp, p_genericexpensecategoryid => @GenericExpenseCategoryId::int, p_genericsupplierid => @GenericSupplierId::int, p_description => @Description::text, p_amount => @Amount::numeric, p_paidto => @PaidTo::text, p_paymentmethod => @PaymentMethod::text, p_genericcashaccountid => @GenericCashAccountId::int, p_receipturl => @ReceiptUrl::text, p_branchid => @BranchId::int, p_staffid => @StaffId::int, p_notes => @Notes::text, p_createdby => @CreatedBy::text, p_amountpaid => @AmountPaid::numeric, p_duedate => @DueDate::date)", conn);
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
            cmd.Parameters.AddWithValue("@AmountPaid", (object?)m.AmountPaid ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DueDate", m.DueDate.HasValue ? m.DueDate.Value.Date : (object)DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        // 448: edit. Draft / Rejected: everything (Rejected goes back to Draft).
        // Approved: the money is re-posted; locked once a supplier payment is applied.
        public async Task UpdateAsync(int id, GenericExpenseModel m, string? updatedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT spgenericexpense_update(p_genericexpenseid => @Id::int, p_farmid => @FarmId::text, p_expensedate => @ExpenseDate::timestamp, p_genericexpensecategoryid => @CategoryId::int, p_genericsupplierid => @SupplierId::int, p_description => @Description::text, p_amount => @Amount::numeric, p_paidto => @PaidTo::text, p_paymentmethod => @PaymentMethod::text, p_genericcashaccountid => @CashAccountId::int, p_receipturl => @ReceiptUrl::text, p_notes => @Notes::text, p_amountpaid => @AmountPaid::numeric, p_duedate => @DueDate::date, p_updatedby => @UpdatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@ExpenseDate", m.ExpenseDate == default ? (object)DBNull.Value : m.ExpenseDate);
            cmd.Parameters.AddWithValue("@CategoryId", m.GenericExpenseCategoryId);
            cmd.Parameters.AddWithValue("@SupplierId", (object?)m.GenericSupplierId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Amount", m.Amount);
            cmd.Parameters.AddWithValue("@PaidTo", (object?)m.PaidTo ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaymentMethod", m.PaymentMethod);
            cmd.Parameters.AddWithValue("@CashAccountId", (object?)m.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ReceiptUrl", (object?)m.ReceiptUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AmountPaid", (object?)m.AmountPaid ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DueDate", m.DueDate.HasValue ? m.DueDate.Value.Date : (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)updatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // 448: Draft / Rejected are removed; an Approved one gives its cash back
        // and comes off the supplier first.
        public async Task DeleteAsync(int id, string farmId, string? reason, string? deletedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT spgenericexpense_delete(p_genericexpenseid => @Id::int, p_farmid => @FarmId::text, p_reason => @Reason::text, p_deletedby => @By::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", (object?)deletedBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericexpense_approve(p_genericexpenseid => @GenericExpenseId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", conn);
            cmd.Parameters.AddWithValue("@GenericExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task RejectAsync(int id, string farmId, string rejectionReason, string? approvedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericexpense_reject(p_genericexpenseid => @GenericExpenseId::int, p_farmid => @FarmId::text, p_rejectionreason => @RejectionReason::text, p_approvedby => @ApprovedBy::text)", conn);
            cmd.Parameters.AddWithValue("@GenericExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@RejectionReason", rejectionReason);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static GenericExpenseModel ReadExpense(NpgsqlDataReader r) => new()
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
            AmountPaid               = r.IsDBNull(r.GetOrdinal("AmountPaid")) ? null : r.GetDecimal(r.GetOrdinal("AmountPaid")),
            DueDate                  = r.IsDBNull(r.GetOrdinal("DueDate")) ? null : r.GetDateTime(r.GetOrdinal("DueDate")),
            PaymentStatus            = r.IsDBNull(r.GetOrdinal("PaymentStatus")) ? null : r.GetString(r.GetOrdinal("PaymentStatus")),
            SourceType               = r.IsDBNull(r.GetOrdinal("SourceType")) ? null : r.GetString(r.GetOrdinal("SourceType")),
            CashAccountName          = r.IsDBNull(r.GetOrdinal("CashAccountName")) ? null : r.GetString(r.GetOrdinal("CashAccountName")),
            PaymentsApplied          = r.IsDBNull(r.GetOrdinal("PaymentsApplied")) ? 0 : r.GetDecimal(r.GetOrdinal("PaymentsApplied")),
        };
    }
}
