// Water Owner Money (migration 258).
//
// Money the owner puts into the company and money the owner takes out. Neither
// is trading: a contribution is not revenue and a draw is not an expense, which
// is why this service posts nothing but the record and its single cash
// movement. The SP is where that guarantee lives; this file only sends
// parameters.
//
// The water twin of WaterOwnerMoneyService, parameter for parameter.

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterOwnerMoneyService
    {
        Task<List<WaterOwnerMoneyModel>> GetAllAsync(
            string farmId, string? type, DateTime? from, DateTime? to, string? status);

        Task<WaterOwnerMoneySummary> GetSummaryAsync(string farmId, DateTime? from, DateTime? to);

        /// <summary>Records a Contribution or a Draw. Returns the new id.</summary>
        Task<int> RecordAsync(WaterOwnerMoneyRecordRequest r);

        /// <summary>
        /// Undoes a posted record with one opposite cash row. The original is
        /// kept; the reason is required and lands in the audit trail.
        /// </summary>
        Task ReverseAsync(int id, string farmId, string reason, string? reversedBy);
    }

    public class WaterOwnerMoneyService : IWaterOwnerMoneyService
    {
        private readonly string _cs;
        public WaterOwnerMoneyService(string cs) => _cs = cs;

        private static object Db(object? v) => v ?? DBNull.Value;

        private static string? Str(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetString(i);
        }

        private static int? IntN(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i));
        }

        private static DateTime? DateN(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetDateTime(i);
        }

        public async Task<List<WaterOwnerMoneyModel>> GetAllAsync(
            string farmId, string? type, DateTime? from, DateTime? to, string? status)
        {
            var list = new List<WaterOwnerMoneyModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwaterownermoney_getall(p_farmid => @FarmId::text, p_type => @Type::text, p_from => @From::date, p_to => @To::date, p_status => @Status::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Type", Db(type));
            cmd.Parameters.AddWithValue("@From", from.HasValue ? from.Value.Date : (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@To", to.HasValue ? to.Value.Date : (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", Db(status));
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterOwnerMoneyModel
                {
                    WaterOwnerMoneyId = r.GetInt32(r.GetOrdinal("WaterOwnerMoneyId")),
                    FarmId = r.GetString(r.GetOrdinal("FarmId")),
                    TransactionNumber = Str(r, "TransactionNumber"),
                    TransactionDate = r.GetDateTime(r.GetOrdinal("TransactionDate")),
                    TransactionType = r.GetString(r.GetOrdinal("TransactionType")),
                    Amount = r.GetDecimal(r.GetOrdinal("Amount")),
                    WaterCashAccountId = r.GetInt32(r.GetOrdinal("WaterCashAccountId")),
                    AccountName = Str(r, "AccountName"),
                    PaymentMethod = Str(r, "PaymentMethod"),
                    OwnerUserId = Str(r, "OwnerUserId"),
                    OwnerName = Str(r, "OwnerName"),
                    ReferenceNumber = Str(r, "ReferenceNumber"),
                    Notes = Str(r, "Notes"),
                    Status = r.GetString(r.GetOrdinal("Status")),
                    WaterCashTransactionId = IntN(r, "WaterCashTransactionId"),
                    ReversalCashTransactionId = IntN(r, "ReversalCashTransactionId"),
                    CreatedBy = Str(r, "CreatedBy"),
                    CreatedAt = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                    ReversedBy = Str(r, "ReversedBy"),
                    ReversedAt = DateN(r, "ReversedAt"),
                    ReversalReason = Str(r, "ReversalReason"),
                });
            }
            return list;
        }

        public async Task<WaterOwnerMoneySummary> GetSummaryAsync(string farmId, DateTime? from, DateTime? to)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwaterownermoney_summary(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@From", from.HasValue ? from.Value.Date : (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@To", to.HasValue ? to.Value.Date : (object)DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new WaterOwnerMoneySummary();
            return new WaterOwnerMoneySummary
            {
                TotalContributions = r.GetDecimal(r.GetOrdinal("TotalContributions")),
                TotalDraws = r.GetDecimal(r.GetOrdinal("TotalDraws")),
                NetFunding = r.GetDecimal(r.GetOrdinal("NetFunding")),
                PeriodContributions = r.GetDecimal(r.GetOrdinal("PeriodContributions")),
                PeriodDraws = r.GetDecimal(r.GetOrdinal("PeriodDraws")),
                ContributionCount = r.GetInt32(r.GetOrdinal("ContributionCount")),
                DrawCount = r.GetInt32(r.GetOrdinal("DrawCount")),
            };
        }

        public async Task<int> RecordAsync(WaterOwnerMoneyRecordRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spwaterownermoney_record("
                + "p_farmid => @FarmId::text,"
                + "p_transactiontype => @Type::text,"
                + "p_amount => @Amount::numeric,"
                + "p_watercashaccountid => @AccountId::int,"
                + "p_transactiondate => @Date::timestamp,"
                + "p_paymentmethod => @Method::text,"
                + "p_owneruserid => @OwnerUserId::text,"
                + "p_ownername => @OwnerName::text,"
                + "p_referencenumber => @Reference::text,"
                + "p_notes => @Notes::text,"
                + "p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@Type", q.TransactionType);
            cmd.Parameters.AddWithValue("@Amount", q.Amount);
            cmd.Parameters.AddWithValue("@AccountId", q.WaterCashAccountId);
            cmd.Parameters.AddWithValue("@Date",
                q.TransactionDate.HasValue ? q.TransactionDate.Value : (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@Method", Db(q.PaymentMethod));
            cmd.Parameters.AddWithValue("@OwnerUserId", Db(q.OwnerUserId));
            cmd.Parameters.AddWithValue("@OwnerName", Db(q.OwnerName));
            cmd.Parameters.AddWithValue("@Reference", Db(q.ReferenceNumber));
            cmd.Parameters.AddWithValue("@Notes", Db(q.Notes));
            cmd.Parameters.AddWithValue("@CreatedBy", Db(q.CreatedBy));
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ReverseAsync(int id, string farmId, string reason, string? reversedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spwaterownermoney_reverse(p_waterownermoneyid => @Id::int, p_farmid => @FarmId::text, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Reason", reason);
            cmd.Parameters.AddWithValue("@ReversedBy", Db(reversedBy));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
