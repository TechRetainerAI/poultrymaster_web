// Poultry Cash Account services (port of the Water finance cash module).
// Each service maps 1:1 to its spPoultryCash* SP family (migration 129). The
// transactional SPs (transfer approve, adjust) handle multi-table writes inside
// SQL Server; the C# side just sends params.

using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // ====================================================================
    // Cash accounts (+ transactions read)
    // ====================================================================
    public interface IPoultryCashAccountService
    {
        Task<List<PoultryCashAccountModel>> GetAllAsync(string farmId);
        Task<PoultryCashAccountModel?>      GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(PoultryCashAccountModel m);
        Task       UpdateAsync(PoultryCashAccountModel m);
        Task       DeleteAsync(int id, string farmId);
        Task       ReconcileBalanceAsync(string farmId);
        Task       AdjustAsync(int id, string farmId, decimal amount, string reason, string? createdBy);
        Task<List<PoultryCashTransactionModel>> GetTransactionsAsync(
            string farmId, int? cashAccountId, DateTime? fromDate, DateTime? toDate);
    }

    public class PoultryCashAccountService : IPoultryCashAccountService
    {
        private readonly string _cs;
        public PoultryCashAccountService(string cs) => _cs = cs;

        public async Task<List<PoultryCashAccountModel>> GetAllAsync(string farmId)
        {
            var list = new List<PoultryCashAccountModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryCashAccount_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<PoultryCashAccountModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryCashAccount_GetById", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(PoultryCashAccountModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryCashAccount_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@AccountName", m.AccountName);
            cmd.Parameters.AddWithValue("@AccountType", m.AccountType);
            cmd.Parameters.AddWithValue("@OpeningBalance", m.OpeningBalance);
            cmd.Parameters.AddWithValue("@AllowNegativeBalance", m.AllowNegativeBalance);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(PoultryCashAccountModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryCashAccount_Update", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", m.PoultryCashAccountId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@AccountName", m.AccountName);
            cmd.Parameters.AddWithValue("@AccountType", m.AccountType);
            cmd.Parameters.AddWithValue("@AllowNegativeBalance", m.AllowNegativeBalance);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryCashAccount_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReconcileBalanceAsync(string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryCashAccount_ReconcileBalance", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task AdjustAsync(int id, string farmId, decimal amount, string reason, string? createdBy)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryCashAccount_Adjust", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Amount", amount);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<PoultryCashTransactionModel>> GetTransactionsAsync(
            string farmId, int? cashAccountId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryCashTransactionModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryCashTransaction_GetByFarm", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", (object?)cashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",   (object?)toDate   ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryCashTransactionModel
                {
                    PoultryCashTransactionId = r.GetInt32(r.GetOrdinal("PoultryCashTransactionId")),
                    FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
                    PoultryCashAccountId     = r.GetInt32(r.GetOrdinal("PoultryCashAccountId")),
                    AccountName              = r.IsDBNull(r.GetOrdinal("AccountName")) ? null : r.GetString(r.GetOrdinal("AccountName")),
                    TransactionDate          = r.GetDateTime(r.GetOrdinal("TransactionDate")),
                    TransactionType          = r.GetString(r.GetOrdinal("TransactionType")),
                    SourceType               = r.IsDBNull(r.GetOrdinal("SourceType")) ? null : r.GetString(r.GetOrdinal("SourceType")),
                    SourceId                 = r.IsDBNull(r.GetOrdinal("SourceId")) ? null : r.GetInt32(r.GetOrdinal("SourceId")),
                    Amount                   = r.GetDecimal(r.GetOrdinal("Amount")),
                    BalanceAfterTransaction  = r.IsDBNull(r.GetOrdinal("BalanceAfterTransaction")) ? null : r.GetDecimal(r.GetOrdinal("BalanceAfterTransaction")),
                    Description              = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
                    CreatedBy                = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
                    ApprovedBy               = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
                    ApprovedAt               = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
                    CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                });
            }
            return list;
        }

        private static PoultryCashAccountModel Read(SqlDataReader r) => new()
        {
            PoultryCashAccountId = r.GetInt32(r.GetOrdinal("PoultryCashAccountId")),
            FarmId               = r.GetString(r.GetOrdinal("FarmId")),
            AccountName          = r.GetString(r.GetOrdinal("AccountName")),
            AccountType          = r.GetString(r.GetOrdinal("AccountType")),
            OpeningBalance       = r.GetDecimal(r.GetOrdinal("OpeningBalance")),
            CurrentBalance       = r.GetDecimal(r.GetOrdinal("CurrentBalance")),
            AllowNegativeBalance = r.GetBoolean(r.GetOrdinal("AllowNegativeBalance")),
            IsActive             = r.GetBoolean(r.GetOrdinal("IsActive")),
            Notes                = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt            = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt            = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // ====================================================================
    // Cash transfers
    // ====================================================================
    public interface IPoultryCashTransferService
    {
        Task<List<PoultryCashTransferModel>> GetAllAsync(string farmId, string? status);
        Task<PoultryCashTransferModel?>      GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(PoultryCashTransferModel m);
        Task       ApproveAsync(int id, string farmId, string? approvedBy);
        Task       CancelAsync(int id, string farmId);
    }

    public class PoultryCashTransferService : IPoultryCashTransferService
    {
        private readonly string _cs;
        public PoultryCashTransferService(string cs) => _cs = cs;

        public async Task<List<PoultryCashTransferModel>> GetAllAsync(string farmId, string? status)
        {
            var list = new List<PoultryCashTransferModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryCashTransfer_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<PoultryCashTransferModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryCashTransfer_GetById", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(PoultryCashTransferModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryCashTransfer_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FromPoultryCashAccountId", m.FromPoultryCashAccountId);
            cmd.Parameters.AddWithValue("@ToPoultryCashAccountId",   m.ToPoultryCashAccountId);
            cmd.Parameters.AddWithValue("@Amount", m.Amount);
            cmd.Parameters.AddWithValue("@TransferDate",
                m.TransferDate == default ? (object)DBNull.Value : m.TransferDate);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryCashTransfer_Approve", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryCashTransfer_Cancel", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static PoultryCashTransferModel Read(SqlDataReader r) => new()
        {
            PoultryCashTransferId    = r.GetInt32(r.GetOrdinal("PoultryCashTransferId")),
            FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
            FromPoultryCashAccountId = r.GetInt32(r.GetOrdinal("FromPoultryCashAccountId")),
            FromAccountName          = r.IsDBNull(r.GetOrdinal("FromAccountName")) ? null : r.GetString(r.GetOrdinal("FromAccountName")),
            ToPoultryCashAccountId   = r.GetInt32(r.GetOrdinal("ToPoultryCashAccountId")),
            ToAccountName            = r.IsDBNull(r.GetOrdinal("ToAccountName")) ? null : r.GetString(r.GetOrdinal("ToAccountName")),
            TransferDate             = r.GetDateTime(r.GetOrdinal("TransferDate")),
            Amount                   = r.GetDecimal(r.GetOrdinal("Amount")),
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
