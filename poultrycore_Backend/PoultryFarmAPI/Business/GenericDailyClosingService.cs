using System.Data;
using Npgsql;
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericdailyclosing_getall(p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date, p_status => @Status::text, p_branchid => @BranchId::int)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericdailyclosing_getbyid(p_genericdailyclosingid => @GenericDailyClosingId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@GenericDailyClosingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? ReadClosing(reader) : null;
        }

        public async Task<int> InsertAsync(string farmId, GenericDailyClosingCreateRequest req, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericdailyclosing_insert(p_farmid => @FarmId::text, p_closingdate => @ClosingDate::date, p_branchid => @BranchId::int, p_openingcash => @OpeningCash::numeric, p_actualcashcounted => @ActualCashCounted::numeric, p_managernotes => @ManagerNotes::text, p_differencereason => @DifferenceReason::text, p_createdby => @CreatedBy::text)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericdailyclosing_submit(p_genericdailyclosingid => @GenericDailyClosingId::int, p_farmid => @FarmId::text, p_actualcashcounted => @ActualCashCounted::numeric, p_managernotes => @ManagerNotes::text, p_differencereason => @DifferenceReason::text, p_submittedby => @SubmittedBy::text)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericdailyclosing_approve(p_genericdailyclosingid => @GenericDailyClosingId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", conn);
            cmd.Parameters.AddWithValue("@GenericDailyClosingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task RejectAsync(int id, string farmId, string rejectionReason, string? approvedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericdailyclosing_reject(p_genericdailyclosingid => @GenericDailyClosingId::int, p_farmid => @FarmId::text, p_rejectionreason => @RejectionReason::text, p_approvedby => @ApprovedBy::text)", conn);
            cmd.Parameters.AddWithValue("@GenericDailyClosingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@RejectionReason", rejectionReason);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static GenericDailyClosingModel ReadClosing(NpgsqlDataReader r) => new()
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
