using Npgsql;
using System;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Egg Cost &amp; Profit Analyzer (migration 481). A thin wrapper over the
    /// sppoultryeggcost_* functions: every call passes JSON through untouched.
    /// It only READS business records; the only rows it writes are the
    /// analyzer's own settings, assumptions, historical cost entries and
    /// snapshots. Refusals (RAISE EXCEPTION) come back as
    /// <see cref="EggCostRuleException"/>.
    /// </summary>
    public interface IPoultryEggCostService
    {
        Task<string> GetFactsAsync(string farmId, DateTime start, DateTime end);
        Task<string> SaveSettingsAsync(string farmId, string settingsJson, string? by);
        Task SaveAssumptionAsync(string farmId, int flockId, string assumptionJson, string? by);
        Task<int> AddHistoricalCostAsync(string farmId, PoultryEggCostHistoricalInput input, string? by);
        Task ReverseHistoricalCostAsync(string farmId, int id, string reason, string? by);
        Task<string> ListSnapshotsAsync(string farmId);
        Task<string?> GetSnapshotAsync(string farmId, int id);
        Task<int> SaveSnapshotAsync(string farmId, PoultryEggCostSnapshotInput input, string? by);
        Task DeleteSnapshotAsync(string farmId, int id, string? by);
        Task<string> ListAuditAsync(string farmId);
    }

    public class EggCostRuleException : Exception
    {
        public EggCostRuleException(string message, Exception inner) : base(message, inner) { }
    }

    public class PoultryEggCostHistoricalInput
    {
        public int? FlockId { get; set; }
        public int? BatchId { get; set; }
        public string Category { get; set; } = "Other";
        public decimal Amount { get; set; }
        public DateTime? PeriodFrom { get; set; }
        public DateTime? PeriodTo { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? Reference { get; set; }
        public bool IsEstimate { get; set; } = true;
    }

    public class PoultryEggCostSnapshotInput
    {
        public string Name { get; set; } = string.Empty;
        public string Mode { get; set; } = "Recorded";
        public System.Text.Json.JsonElement Params { get; set; }
        public System.Text.Json.JsonElement Result { get; set; }
        public string CalcVersion { get; set; } = string.Empty;
        public int? SettingsVersion { get; set; }
        public string? SourceFingerprint { get; set; }
    }

    public class PoultryEggCostService : IPoultryEggCostService
    {
        private readonly string _cs;
        public PoultryEggCostService(string cs) => _cs = cs;

        private async Task<T> RunAsync<T>(string sql, Action<NpgsqlParameterCollection> bind, Func<object?, T> read)
        {
            try
            {
                await using var conn = new NpgsqlConnection(_cs);
                await conn.OpenAsync();
                await using var cmd = new NpgsqlCommand(sql, conn);
                bind(cmd.Parameters);
                return read(await cmd.ExecuteScalarAsync());
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                throw new EggCostRuleException(ex.MessageText, ex);
            }
        }

        private static string Json(object? o) => o is null || o is DBNull ? "null" : (string)o;

        public Task<string> GetFactsAsync(string farmId, DateTime start, DateTime end) =>
            RunAsync("SELECT sppoultryeggcost_facts(p_farmid => @FarmId::text, p_startdate => @Start::date, p_enddate => @End::date)::text",
                p => { p.AddWithValue("@FarmId", farmId); p.AddWithValue("@Start", start.Date); p.AddWithValue("@End", end.Date); }, Json);

        public Task<string> SaveSettingsAsync(string farmId, string settingsJson, string? by) =>
            RunAsync("SELECT sppoultryeggcost_settingssave(p_farmid => @FarmId::text, p_settings => @S::jsonb, p_by => @By::text)::text",
                p => { p.AddWithValue("@FarmId", farmId); p.AddWithValue("@S", settingsJson); p.AddWithValue("@By", (object?)by ?? DBNull.Value); }, Json);

        public Task SaveAssumptionAsync(string farmId, int flockId, string assumptionJson, string? by) =>
            RunAsync("SELECT sppoultryeggcost_assumptionsave(p_farmid => @FarmId::text, p_flockid => @Flock::int, p_assumption => @A::jsonb, p_by => @By::text)",
                p => { p.AddWithValue("@FarmId", farmId); p.AddWithValue("@Flock", flockId); p.AddWithValue("@A", assumptionJson); p.AddWithValue("@By", (object?)by ?? DBNull.Value); },
                _ => 0);

        public Task<int> AddHistoricalCostAsync(string farmId, PoultryEggCostHistoricalInput i, string? by) =>
            RunAsync("SELECT sppoultryeggcost_historicaladd(p_farmid => @FarmId::text, p_flockid => @Flock::int, p_batchid => @Batch::int, " +
                     "p_category => @Cat::text, p_amount => @Amt::numeric, p_periodfrom => @From::date, p_periodto => @To::date, " +
                     "p_reason => @Reason::text, p_reference => @Ref::text, p_isestimate => @Est::boolean, p_by => @By::text)",
                p =>
                {
                    p.AddWithValue("@FarmId", farmId);
                    p.AddWithValue("@Flock", (object?)i.FlockId ?? DBNull.Value);
                    p.AddWithValue("@Batch", (object?)i.BatchId ?? DBNull.Value);
                    p.AddWithValue("@Cat", i.Category ?? "Other");
                    p.AddWithValue("@Amt", i.Amount);
                    p.AddWithValue("@From", (object?)i.PeriodFrom?.Date ?? DBNull.Value);
                    p.AddWithValue("@To", (object?)i.PeriodTo?.Date ?? DBNull.Value);
                    p.AddWithValue("@Reason", i.Reason ?? string.Empty);
                    p.AddWithValue("@Ref", (object?)i.Reference ?? DBNull.Value);
                    p.AddWithValue("@Est", i.IsEstimate);
                    p.AddWithValue("@By", (object?)by ?? DBNull.Value);
                }, o => Convert.ToInt32(o));

        public Task ReverseHistoricalCostAsync(string farmId, int id, string reason, string? by) =>
            RunAsync("SELECT sppoultryeggcost_historicalreverse(p_farmid => @FarmId::text, p_id => @Id::int, p_reason => @Reason::text, p_by => @By::text)",
                p => { p.AddWithValue("@FarmId", farmId); p.AddWithValue("@Id", id); p.AddWithValue("@Reason", reason ?? string.Empty); p.AddWithValue("@By", (object?)by ?? DBNull.Value); },
                _ => 0);

        public Task<string> ListSnapshotsAsync(string farmId) =>
            RunAsync("SELECT sppoultryeggcost_snapshotlist(p_farmid => @FarmId::text)::text", p => p.AddWithValue("@FarmId", farmId), Json);

        public async Task<string?> GetSnapshotAsync(string farmId, int id)
        {
            var json = await RunAsync("SELECT sppoultryeggcost_snapshotget(p_farmid => @FarmId::text, p_id => @Id::int)::text",
                p => { p.AddWithValue("@FarmId", farmId); p.AddWithValue("@Id", id); }, Json);
            return json == "null" ? null : json;
        }

        public Task<int> SaveSnapshotAsync(string farmId, PoultryEggCostSnapshotInput i, string? by) =>
            RunAsync("SELECT sppoultryeggcost_snapshotsave(p_farmid => @FarmId::text, p_name => @Name::text, p_mode => @Mode::text, " +
                     "p_params => @Params::jsonb, p_result => @Result::jsonb, p_calcversion => @Ver::text, " +
                     "p_settingsversion => @SVer::int, p_fingerprint => @Fp::text, p_by => @By::text)",
                p =>
                {
                    p.AddWithValue("@FarmId", farmId);
                    p.AddWithValue("@Name", i.Name ?? string.Empty);
                    p.AddWithValue("@Mode", i.Mode ?? "Recorded");
                    p.AddWithValue("@Params", i.Params.ValueKind == System.Text.Json.JsonValueKind.Undefined ? "{}" : i.Params.GetRawText());
                    p.AddWithValue("@Result", i.Result.ValueKind == System.Text.Json.JsonValueKind.Undefined ? "{}" : i.Result.GetRawText());
                    p.AddWithValue("@Ver", i.CalcVersion ?? string.Empty);
                    p.AddWithValue("@SVer", (object?)i.SettingsVersion ?? DBNull.Value);
                    p.AddWithValue("@Fp", (object?)i.SourceFingerprint ?? DBNull.Value);
                    p.AddWithValue("@By", (object?)by ?? DBNull.Value);
                }, o => Convert.ToInt32(o));

        public Task DeleteSnapshotAsync(string farmId, int id, string? by) =>
            RunAsync("SELECT sppoultryeggcost_snapshotdelete(p_farmid => @FarmId::text, p_id => @Id::int, p_by => @By::text)",
                p => { p.AddWithValue("@FarmId", farmId); p.AddWithValue("@Id", id); p.AddWithValue("@By", (object?)by ?? DBNull.Value); },
                _ => 0);

        public Task<string> ListAuditAsync(string farmId) =>
            RunAsync("SELECT sppoultryeggcost_auditlist(p_farmid => @FarmId::text)::text", p => p.AddWithValue("@FarmId", farmId), Json);
    }
}
