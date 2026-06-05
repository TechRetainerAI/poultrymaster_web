using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericDailyClosingService : IGenericDailyClosingService
    {
        private readonly string _connectionString;
        public GenericDailyClosingService(string connectionString) => _connectionString = connectionString;

        public async Task<List<GenericDailyClosingModel>> GetAllAsync(string farmId, DateTime? fromDate, DateTime? toDate, string? status, int? branchId)
        {
            var list = new List<GenericDailyClosingModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericDailyClosing_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",   (object?)toDate   ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status",   (object?)status   ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BranchId", (object?)branchId ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadClosing(reader));
            return list;
        }

        public async Task<GenericDailyClosingModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericDailyClosing_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericDailyClosingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? ReadClosing(reader) : null;
        }

        public async Task<int> InsertAsync(string farmId, GenericDailyClosingCreateRequest req, string? createdBy)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericDailyClosing_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ClosingDate", req.ClosingDate);
            cmd.Parameters.AddWithValue("@BranchId", (object?)req.BranchId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OpeningCash", (object?)req.OpeningCash ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ActualCashCounted", req.ActualCashCounted);
            cmd.Parameters.AddWithValue("@ManagerNotes", (object?)req.ManagerNotes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DifferenceReason", (object?)req.DifferenceReason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<GenericDailyClosingModel?> SubmitAsync(int id, string farmId, GenericDailyClosingSubmitRequest req, string? submittedBy)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericDailyClosing_Submit", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericDailyClosingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ActualCashCounted", (object?)req.ActualCashCounted ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ManagerNotes", (object?)req.ManagerNotes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DifferenceReason", (object?)req.DifferenceReason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SubmittedBy", (object?)submittedBy ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? ReadClosing(reader) : null;
        }

        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericDailyClosing_Approve", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericDailyClosingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task RejectAsync(int id, string farmId, string rejectionReason, string? approvedBy)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericDailyClosing_Reject", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericDailyClosingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@RejectionReason", rejectionReason);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static GenericDailyClosingModel ReadClosing(SqlDataReader r) => new()
        {
            GenericDailyClosingId     = r.GetInt32(r.GetOrdinal("GenericDailyClosingId")),
            FarmId                    = r.GetString(r.GetOrdinal("FarmId")),
            BranchId                  = r.IsDBNull(r.GetOrdinal("BranchId")) ? null : r.GetInt32(r.GetOrdinal("BranchId")),
            ClosingDate               = r.GetDateTime(r.GetOrdinal("ClosingDate")),
            OpeningCash               = r.GetDecimal(r.GetOrdinal("OpeningCash")),
            TotalSales                = r.GetDecimal(r.GetOrdinal("TotalSales")),
            TotalCustomerPayments     = r.GetDecimal(r.GetOrdinal("TotalCustomerPayments")),
            TotalCashIn               = r.GetDecimal(r.GetOrdinal("TotalCashIn")),
            TotalExpenses             = r.GetDecimal(r.GetOrdinal("TotalExpenses")),
            TotalPurchasesPaid        = r.GetDecimal(r.GetOrdinal("TotalPurchasesPaid")),
            TotalSupplierPayments     = r.GetDecimal(r.GetOrdinal("TotalSupplierPayments")),
            TotalPayrollPaid          = r.GetDecimal(r.GetOrdinal("TotalPayrollPaid")),
            TotalCashOut              = r.GetDecimal(r.GetOrdinal("TotalCashOut")),
            ExpectedCash              = r.GetDecimal(r.GetOrdinal("ExpectedCash")),
            ActualCashCounted         = r.GetDecimal(r.GetOrdinal("ActualCashCounted")),
            CashDifference            = r.GetDecimal(r.GetOrdinal("CashDifference")),
            CreditSales               = r.GetDecimal(r.GetOrdinal("CreditSales")),
            CustomerDebtTotal         = r.GetDecimal(r.GetOrdinal("CustomerDebtTotal")),
            SupplierDebtTotal         = r.GetDecimal(r.GetOrdinal("SupplierDebtTotal")),
            InventoryAdjustmentsCount = r.GetInt32(r.GetOrdinal("InventoryAdjustmentsCount")),
            ManagerNotes              = r.IsDBNull(r.GetOrdinal("ManagerNotes")) ? null : r.GetString(r.GetOrdinal("ManagerNotes")),
            DifferenceReason          = r.IsDBNull(r.GetOrdinal("DifferenceReason")) ? null : r.GetString(r.GetOrdinal("DifferenceReason")),
            Status                    = r.GetString(r.GetOrdinal("Status")),
            CreatedBy                 = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            SubmittedBy               = r.IsDBNull(r.GetOrdinal("SubmittedBy")) ? null : r.GetString(r.GetOrdinal("SubmittedBy")),
            SubmittedAt               = r.IsDBNull(r.GetOrdinal("SubmittedAt")) ? null : r.GetDateTime(r.GetOrdinal("SubmittedAt")),
            ApprovedBy                = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt                = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            RejectionReason           = r.IsDBNull(r.GetOrdinal("RejectionReason")) ? null : r.GetString(r.GetOrdinal("RejectionReason")),
            CreatedAt                 = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                 = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }
}
