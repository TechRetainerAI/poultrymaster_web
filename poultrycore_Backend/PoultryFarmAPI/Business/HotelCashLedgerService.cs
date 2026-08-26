using Npgsql;

namespace PoultryFarmAPIWeb.Business
{
    public class HotelCashLedgerService : IHotelCashLedgerService
    {
        private readonly string _cs;
        private readonly ILogger<HotelCashLedgerService> _logger;

        // Default accounts auto-created per farm when first needed
        private static readonly Dictionary<string, (string Name, string Type)> DefaultAccounts = new()
        {
            ["FrontDesk"] = ("Front Desk Cash", "Cash"),
            ["Expenses"] = ("Expenses Account", "Cash"),
            ["POS"] = ("POS / Restaurant", "Cash"),
            ["Payroll"] = ("Payroll Account", "Cash"),
        };

        public HotelCashLedgerService(IConfiguration config, ILogger<HotelCashLedgerService> logger)
        {
            _cs = config.GetConnectionString("PoultryConn") ?? "";
            _logger = logger;
        }

        public async Task PostAsync(string farmId, string purpose, string txnType, decimal amount, string description, string? reference, string sourceType, int sourceId, string? createdBy)
        {
            if (amount <= 0) return;

            try
            {
                using var conn = new NpgsqlConnection(_cs);
                await conn.OpenAsync();
                using var txn = await conn.BeginTransactionAsync();

                // 1. Find or create the designated cash account
                int accountId = await GetOrCreateAccountAsync(conn, txn, farmId, purpose);

                // 2. Update the account balance
                string balanceSql = txnType == "Credit"
                    ? "UPDATE hotelcashaccounts SET currentbalance = currentbalance + @amt, updatedat = NOW() WHERE hotelcashaccountid = @id RETURNING currentbalance"
                    : "UPDATE hotelcashaccounts SET currentbalance = currentbalance - @amt, updatedat = NOW() WHERE hotelcashaccountid = @id RETURNING currentbalance";

                decimal balanceAfter;
                using (var cmd = new NpgsqlCommand(balanceSql, conn, txn))
                {
                    cmd.Parameters.AddWithValue("@amt", amount);
                    cmd.Parameters.AddWithValue("@id", accountId);
                    balanceAfter = Convert.ToDecimal(await cmd.ExecuteScalarAsync() ?? 0);
                }

                // 3. Insert the transaction record
                using (var cmd = new NpgsqlCommand(
                    "INSERT INTO hotelcashtransactions(farmid, hotelcashaccountid, txntype, amount, balanceafter, description, reference, sourcetype, sourceid, createdby) " +
                    "VALUES(@f, @acct, @type, @amt, @bal, @desc, @ref, @src, @srcid, @by)", conn, txn))
                {
                    cmd.Parameters.AddWithValue("@f", farmId);
                    cmd.Parameters.AddWithValue("@acct", accountId);
                    cmd.Parameters.AddWithValue("@type", txnType);
                    cmd.Parameters.AddWithValue("@amt", amount);
                    cmd.Parameters.AddWithValue("@bal", balanceAfter);
                    cmd.Parameters.AddWithValue("@desc", description);
                    cmd.Parameters.AddWithValue("@ref", (object?)reference ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@src", sourceType);
                    cmd.Parameters.AddWithValue("@srcid", sourceId);
                    cmd.Parameters.AddWithValue("@by", (object?)createdBy ?? DBNull.Value);
                    await cmd.ExecuteNonQueryAsync();
                }

                await txn.CommitAsync();
                _logger.LogInformation("Cash ledger: {TxnType} {Amount} to {Purpose} account (farm {FarmId}, {SourceType} #{SourceId})",
                    txnType, amount, purpose, farmId, sourceType, sourceId);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to post cash ledger entry for {Purpose}, {SourceType} #{SourceId}", purpose, sourceType, sourceId);
            }
        }

        private static async Task<int> GetOrCreateAccountAsync(NpgsqlConnection conn, NpgsqlTransaction txn, string farmId, string purpose)
        {
            // Try to find existing account with this purpose
            using (var cmd = new NpgsqlCommand("SELECT hotelcashaccountid FROM hotelcashaccounts WHERE farmid=@f AND purpose=@p LIMIT 1", conn, txn))
            {
                cmd.Parameters.AddWithValue("@f", farmId);
                cmd.Parameters.AddWithValue("@p", purpose);
                var result = await cmd.ExecuteScalarAsync();
                if (result != null && result != DBNull.Value) return Convert.ToInt32(result);
            }

            // Auto-create the default account
            var def = DefaultAccounts.GetValueOrDefault(purpose, (purpose, "Cash"));
            using (var cmd = new NpgsqlCommand(
                "INSERT INTO hotelcashaccounts(farmid, accountname, accounttype, openingbalance, currentbalance, purpose) " +
                "VALUES(@f, @n, @t, 0, 0, @p) RETURNING hotelcashaccountid", conn, txn))
            {
                cmd.Parameters.AddWithValue("@f", farmId);
                cmd.Parameters.AddWithValue("@n", def.Item1);
                cmd.Parameters.AddWithValue("@t", def.Item2);
                cmd.Parameters.AddWithValue("@p", purpose);
                return Convert.ToInt32(await cmd.ExecuteScalarAsync());
            }
        }
    }
}
