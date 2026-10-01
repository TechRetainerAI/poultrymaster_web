// Daily Farm Closing / management control (migration 333).
//
// Every rule -- what each section sums, which checks block, what a close stores,
// what a reopen records -- lives in the sppoultrydailyclosing_* functions and is
// covered by the migration's self-test. This file sends parameters and maps
// rows. It deliberately does not re-add, re-classify or re-check anything: the
// point of the feature is that the closing agrees with the reports it summarises.

using System.Data;
using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryDailyClosingControlService
    {
        /// <summary>Live workspace + the closing row + its stored snapshot + history.</summary>
        Task<PoultryClosingDayView> GetDayAsync(string farmId, DateTime? businessDate);

        /// <summary>
        /// Throws PostgresException P0002 when already closed, P0003 when a
        /// blocking check fails, P0001 for a future date.
        /// </summary>
        Task<PoultryCloseDayResult> CloseAsync(string farmId, DateTime businessDate, string? closedBy, string? notes);

        Task<IReadOnlyList<PoultryClosingHistoryRow>> GetHistoryAsync(string farmId, DateTime? from, DateTime? to);
        Task<JsonElement?> GetEventSnapshotAsync(string farmId, long eventId);
        Task<PoultryClosingPolicy> GetPolicyAsync(string farmId);
        Task SetPolicyAsync(PoultryClosingPolicy p, string? updatedBy);
        Task<DailyClosingStatus> GetStatusAsync(string farmId, DateTime? businessDate);
    }

    public class PoultryDailyClosingControlService : IPoultryDailyClosingControlService
    {
        private readonly string _cs;
        public PoultryDailyClosingControlService(string cs) => _cs = cs;

        public async Task<PoultryClosingDayView> GetDayAsync(string farmId, DateTime? businessDate)
        {
            using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            // One snapshot for all three reads, so a close landing in between
            // cannot give a live view, a closing row and a history that disagree.
            await using var tx = await c.BeginTransactionAsync(IsolationLevel.RepeatableRead);

            // The workspace decides the date (company today when none is given)
            // and refuses a future one; everything after reads that same date.
            JsonElement live;
            using (var cmd = new NpgsqlCommand(
                       "SELECT sppoultrydailyclosing_workspace(p_farmid => @FarmId::text, p_businessdate => @Date::date)::text", c, tx))
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@Date", businessDate.HasValue ? businessDate.Value.Date : DBNull.Value);
                live = ParseJson((string)(await cmd.ExecuteScalarAsync())!)!.Value;
            }

            var date = DateTime.Parse(live.GetProperty("businessDate").GetString()!).Date;
            var view = new PoultryClosingDayView { FarmId = farmId, BusinessDate = date, Live = live };

            using (var cmd = new NpgsqlCommand(
                       "SELECT * FROM sppoultrydailyclosing_getfordate(p_farmid => @FarmId::text, p_businessdate => @Date::date)", c, tx))
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@Date", date);
                using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    view.Closing = new PoultryClosingRecord
                    {
                        PoultryDailyClosingId = r.GetInt32(r.GetOrdinal("poultrydailyclosingid")),
                        ClosingDate = r.GetDateTime(r.GetOrdinal("closingdate")),
                        Status = r.GetString(r.GetOrdinal("status")),
                        ManagerNotes = Str(r, "managernotes"),
                        RejectionReason = Str(r, "rejectionreason"),
                        CreatedBy = Str(r, "createdby"),
                        SubmittedBy = Str(r, "submittedby"),
                        SubmittedAt = Date(r, "submittedat"),
                        ClosedAtUtc = Utc(r, "closedatutc"),
                        ClosedBy = Str(r, "closedby"),
                        CloseVersion = r.GetInt32(r.GetOrdinal("closeversion")),
                        WarningsAtClose = Int(r, "warningsatclose"),
                        LastReopenedAtUtc = Utc(r, "lastreopenedatutc"),
                        LastReopenedBy = Str(r, "lastreopenedby"),
                        LastReopenReason = Str(r, "lastreopenreason"),
                    };
                    view.AtClose = ParseJson(Str(r, "closingsnapshot"));
                }
            }

            using (var cmd = new NpgsqlCommand(
                       "SELECT * FROM sppoultrydailyclosing_events(p_farmid => @FarmId::text, p_businessdate => @Date::date)", c, tx))
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@Date", date);
                using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    view.History.Add(new PoultryClosingEvent
                    {
                        EventId = r.GetInt64(r.GetOrdinal("eventid")),
                        PoultryDailyClosingId = r.GetInt32(r.GetOrdinal("poultrydailyclosingid")),
                        EventType = r.GetString(r.GetOrdinal("eventtype")),
                        FromStatus = Str(r, "fromstatus"),
                        ToStatus = Str(r, "tostatus"),
                        Actor = Str(r, "actor"),
                        Reason = Str(r, "reason"),
                        CloseVersion = Int(r, "closeversion"),
                        WarningCount = Int(r, "warningcount"),
                        OccurredAtUtc = Utc(r, "occurredatutc") ?? DateTime.MinValue,
                        HasSnapshot = r.GetBoolean(r.GetOrdinal("hassnapshot")),
                    });
                }
            }

            await tx.CommitAsync();
            return view;
        }

        public async Task<PoultryCloseDayResult> CloseAsync(string farmId, DateTime businessDate, string? closedBy, string? notes)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrydailyclosing_close(p_farmid => @FarmId::text, p_businessdate => @Date::date, "
                + "p_closedby => @ClosedBy::text, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Date", businessDate.Date);
            cmd.Parameters.AddWithValue("@ClosedBy", (object?)closedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", string.IsNullOrWhiteSpace(notes) ? DBNull.Value : notes.Trim());
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) throw new InvalidOperationException("Closing the day returned no result.");
            return new PoultryCloseDayResult
            {
                PoultryDailyClosingId = r.GetInt32(r.GetOrdinal("poultrydailyclosingid")),
                CloseVersion = r.GetInt32(r.GetOrdinal("closeversion")),
                WarningCount = r.GetInt32(r.GetOrdinal("warningcount")),
                ClosedAtUtc = Utc(r, "closedatutc") ?? DateTime.UtcNow,
            };
        }

        public async Task<IReadOnlyList<PoultryClosingHistoryRow>> GetHistoryAsync(string farmId, DateTime? from, DateTime? to)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrydailyclosing_history(p_farmid => @FarmId::text, p_fromdate => @From::date, p_todate => @To::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@From", from.HasValue ? from.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@To", to.HasValue ? to.Value.Date : DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<PoultryClosingHistoryRow>();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryClosingHistoryRow
                {
                    PoultryDailyClosingId = r.GetInt32(r.GetOrdinal("poultrydailyclosingid")),
                    ClosingDate = r.GetDateTime(r.GetOrdinal("closingdate")),
                    Status = r.GetString(r.GetOrdinal("status")),
                    ClosedAtUtc = Utc(r, "closedatutc"),
                    ClosedBy = Str(r, "closedby"),
                    CloseVersion = r.GetInt32(r.GetOrdinal("closeversion")),
                    WarningsAtClose = Int(r, "warningsatclose"),
                    ReopenCount = r.GetInt32(r.GetOrdinal("reopencount")),
                    LastReopenedAtUtc = Utc(r, "lastreopenedatutc"),
                    LastReopenReason = Str(r, "lastreopenreason"),
                    Revenue = Dec(r, "revenue"),
                    MoneyIn = Dec(r, "moneyin"),
                    MoneyOut = Dec(r, "moneyout"),
                    NetCashFlow = Dec(r, "netcashflow"),
                    EggsProduced = Dec(r, "eggsproduced"),
                    MissingFlocks = Int(r, "missingflocks"),
                    HasSnapshot = r.GetBoolean(r.GetOrdinal("hassnapshot")),
                });
            }
            return list;
        }

        public async Task<JsonElement?> GetEventSnapshotAsync(string farmId, long eventId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrydailyclosing_eventsnapshot(p_farmid => @FarmId::text, p_eventid => @EventId::bigint)::text", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@EventId", eventId);
            await c.OpenAsync();
            return ParseJson(await cmd.ExecuteScalarAsync() as string);
        }

        public async Task<PoultryClosingPolicy> GetPolicyAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydailyclosingpolicy_get(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new PoultryClosingPolicy { FarmId = farmId };
            return new PoultryClosingPolicy
            {
                FarmId = farmId,
                MissingProduction = r.GetString(r.GetOrdinal("missingproduction")),
                UnpostedProduction = r.GetString(r.GetOrdinal("unpostedproduction")),
                ImpossibleBirdCounts = r.GetString(r.GetOrdinal("impossiblebirdcounts")),
                PendingDriverReturns = r.GetString(r.GetOrdinal("pendingdriverreturns")),
                NegativeStock = r.GetString(r.GetOrdinal("negativestock")),
                CashDifference = r.GetString(r.GetOrdinal("cashdifference")),
                CashDifferenceTolerance = r.GetDecimal(r.GetOrdinal("cashdifferencetolerance")),
                RequireCashCount = r.GetBoolean(r.GetOrdinal("requirecashcount")),
                LowFeedDays = r.GetDecimal(r.GetOrdinal("lowfeeddays")),
                UnusualMortalityPct = r.GetDecimal(r.GetOrdinal("unusualmortalitypct")),
                IsCustomised = r.GetBoolean(r.GetOrdinal("iscustomised")),
                UpdatedBy = Str(r, "updatedby"),
                UpdatedAtUtc = Utc(r, "updatedatutc"),
            };
        }

        public async Task SetPolicyAsync(PoultryClosingPolicy p, string? updatedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrydailyclosingpolicy_set(p_farmid => @FarmId::text, "
                + "p_missingproduction => @MissingProduction::text, p_unpostedproduction => @UnpostedProduction::text, "
                + "p_impossiblebirdcounts => @ImpossibleBirdCounts::text, p_pendingdriverreturns => @PendingDriverReturns::text, "
                + "p_negativestock => @NegativeStock::text, p_cashdifference => @CashDifference::text, "
                + "p_cashdifferencetolerance => @Tolerance::numeric, p_requirecashcount => @RequireCashCount::boolean, "
                + "p_lowfeeddays => @LowFeedDays::numeric, p_unusualmortalitypct => @MortalityPct::numeric, "
                + "p_updatedby => @UpdatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", p.FarmId);
            cmd.Parameters.AddWithValue("@MissingProduction", p.MissingProduction);
            cmd.Parameters.AddWithValue("@UnpostedProduction", p.UnpostedProduction);
            cmd.Parameters.AddWithValue("@ImpossibleBirdCounts", p.ImpossibleBirdCounts);
            cmd.Parameters.AddWithValue("@PendingDriverReturns", p.PendingDriverReturns);
            cmd.Parameters.AddWithValue("@NegativeStock", p.NegativeStock);
            cmd.Parameters.AddWithValue("@CashDifference", p.CashDifference);
            cmd.Parameters.AddWithValue("@Tolerance", p.CashDifferenceTolerance);
            cmd.Parameters.AddWithValue("@RequireCashCount", p.RequireCashCount);
            cmd.Parameters.AddWithValue("@LowFeedDays", p.LowFeedDays);
            cmd.Parameters.AddWithValue("@MortalityPct", p.UnusualMortalityPct);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)updatedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<DailyClosingStatus> GetStatusAsync(string farmId, DateTime? businessDate)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrydailyclosing_statusfordate(p_farmid => @FarmId::text, p_businessdate => @Date::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Date", businessDate.HasValue ? businessDate.Value.Date : DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            return new DailyClosingStatus
            {
                FarmId = farmId,
                Module = "poultry",
                BusinessDate = r.GetDateTime(r.GetOrdinal("businessdate")),
                CompanyToday = r.GetDateTime(r.GetOrdinal("companytoday")),
                ClosingStatus = r.GetString(r.GetOrdinal("closingstatus")),
                WorkflowStatus = Str(r, "workflowstatus"),
                ClosedAtUtc = Utc(r, "closedatutc"),
                ClosedBy = Str(r, "closedby"),
            };
        }

        // ---- mapping helpers ----------------------------------------------

        private static JsonElement? ParseJson(string? json)
        {
            if (string.IsNullOrWhiteSpace(json)) return null;
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.Clone();
        }

        private static string? Str(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetValue(i).ToString();
        }

        private static int? Int(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i));
        }

        private static decimal? Dec(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetDecimal(i);
        }

        private static DateTime? Date(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetDateTime(i);
        }

        /// <summary>timestamptz columns, normalised to Kind=Utc whatever the Npgsql timestamp mode.</summary>
        private static DateTime? Utc(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            if (r.IsDBNull(i)) return null;
            var d = r.GetDateTime(i);
            return d.Kind == DateTimeKind.Utc ? d : DateTime.SpecifyKind(d.ToUniversalTime(), DateTimeKind.Utc);
        }
    }

    /// <summary>
    /// Answers "is this company's day closed?" for one module. Business Office
    /// asks every company through DailyClosingStatusController without knowing
    /// its type; Water and Generic plug in by registering their own provider.
    /// </summary>
    public interface IDailyClosingStatusProvider
    {
        string Module { get; }
        Task<DailyClosingStatus> GetStatusAsync(string farmId, DateTime? businessDate);
    }

    public class PoultryDailyClosingStatusProvider : IDailyClosingStatusProvider
    {
        private readonly IPoultryDailyClosingControlService _svc;
        public PoultryDailyClosingStatusProvider(IPoultryDailyClosingControlService svc) => _svc = svc;
        public string Module => "poultry";
        public Task<DailyClosingStatus> GetStatusAsync(string farmId, DateTime? businessDate)
            => _svc.GetStatusAsync(farmId, businessDate);
    }
}
