// Flock anomaly detection (migration 338). Every rule -- the metrics, the
// baselines, the methods, the thresholds, the opening-history exclusions, the
// one-alert-per-flock-per-day grouping and the alert lifecycle -- lives in SQL
// and is covered by the migration's self-test. This file sends parameters and
// maps rows. Nothing here decides whether an anomaly occurred.

using System.Text.Json;
using Npgsql;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>One signal judged for one flock on one day, fired or not (sppoultryanomaly_evaluate).</summary>
    public class FlockSignalEvaluation
    {
        public int FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public string? HouseName { get; set; }
        public DateTime BusinessDate { get; set; }
        public string SignalKey { get; set; } = string.Empty;
        public string SignalLabel { get; set; } = string.Empty;
        public string MetricKey { get; set; } = string.Empty;
        public string MetricLabel { get; set; } = string.Empty;
        public string MetricUnit { get; set; } = string.Empty;
        public string Direction { get; set; } = "up";
        /// <summary>Fired | Normal | InsufficientBaseline | BelowMinimum | NoData | DuplicateRecords | OnboardingDay</summary>
        public string Status { get; set; } = "Normal";
        /// <summary>Information | Warning | Critical; null unless Fired.</summary>
        public string? Severity { get; set; }
        public int SeverityRank { get; set; }
        public decimal? CurrentValue { get; set; }
        public decimal? BaselineMean { get; set; }
        public decimal? BaselineStdDev { get; set; }
        public int BaselinePoints { get; set; }
        public DateTime BaselineFrom { get; set; }
        public DateTime BaselineTo { get; set; }
        public string Method { get; set; } = "ratio";
        public decimal? Observed { get; set; }
        public decimal? ChangePct { get; set; }
        public decimal? InformationThreshold { get; set; }
        public decimal WarningThreshold { get; set; }
        public decimal CriticalThreshold { get; set; }
        /// <summary>Structured evidence (schema poultry.flock-anomaly.v1) -- what an assistant may explain from.</summary>
        public JsonElement Evidence { get; set; }
        public string[] Explanation { get; set; } = Array.Empty<string>();
    }

    public class FlockAlert
    {
        public int AlertId { get; set; }
        public int FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public string? HouseName { get; set; }
        public DateTime BusinessDate { get; set; }
        /// <summary>Open | Acknowledged | Resolved | Cleared</summary>
        public string Status { get; set; } = "Open";
        public string Severity { get; set; } = "Information";
        public int SeverityRank { get; set; }
        public string PeakSeverity { get; set; } = "Information";
        public int ActiveSignalCount { get; set; }
        /// <summary>Days in a row (ending on this date) this flock has had an alert.</summary>
        public int ConsecutiveDays { get; set; }
        public DateTime FirstDetectedAtUtc { get; set; }
        public DateTime LastEvaluatedAtUtc { get; set; }
        public string? AcknowledgedBy { get; set; }
        public DateTime? AcknowledgedAtUtc { get; set; }
        public string? ResolvedBy { get; set; }
        public DateTime? ResolvedAtUtc { get; set; }
        public string? ResolutionNote { get; set; }
        public int NoteCount { get; set; }
        /// <summary>[{signalKey, label, isActive, severity, observed, explanation[], evidence, firstDetectedAtUtc, clearedAtUtc}]</summary>
        public JsonElement Signals { get; set; }
    }

    public class FlockAlertEvent
    {
        public long EventId { get; set; }
        public int AlertId { get; set; }
        public string EventType { get; set; } = string.Empty;
        public string? SignalKey { get; set; }
        public string? Note { get; set; }
        public string? Actor { get; set; }
        public JsonElement? Details { get; set; }
        public DateTime AtUtc { get; set; }
    }

    public class FlockAlertScanResult
    {
        public DateTime ScanDate { get; set; }
        public int FlocksEvaluated { get; set; }
        public int AlertsOpened { get; set; }
        public int AlertsUpdated { get; set; }
        public int AlertsCleared { get; set; }
        public int AlertsEscalated { get; set; }
    }

    public class FlockAnomalySignalSetting
    {
        public string FarmId { get; set; } = string.Empty;
        public string SignalKey { get; set; } = string.Empty;
        public string Label { get; set; } = string.Empty;
        public string MetricLabel { get; set; } = string.Empty;
        public string MetricUnit { get; set; } = string.Empty;
        public string Direction { get; set; } = "up";
        public string? GuardField { get; set; }
        public string? GuardLabel { get; set; }
        public bool Enabled { get; set; } = true;
        /// <summary>ratio | pctchange | zscore</summary>
        public string Method { get; set; } = "ratio";
        public int BaselineDays { get; set; }
        public int MinBaselineDays { get; set; }
        public decimal? InformationThreshold { get; set; }
        public decimal WarningThreshold { get; set; }
        public decimal CriticalThreshold { get; set; }
        public decimal? GuardMinimum { get; set; }
        public decimal BaselineFloor { get; set; }
        public bool IsCustomised { get; set; }
        public string? UpdatedBy { get; set; }
        public DateTime? UpdatedAtUtc { get; set; }
    }

    public interface IPoultryFlockAnomalyService
    {
        Task<IReadOnlyList<FlockSignalEvaluation>> EvaluateAsync(string farmId, DateTime? date);
        Task<IReadOnlyList<FlockAlertScanResult>> ScanAsync(string farmId, DateTime? from, DateTime? to, string? actor);
        Task<IReadOnlyList<FlockAlert>> ListAsync(string farmId, string? status, DateTime? from, DateTime? to, int? flockId, int? alertId);
        Task<IReadOnlyList<FlockAlertEvent>> GetEventsAsync(string farmId, int alertId);
        Task AcknowledgeAsync(string farmId, int alertId, string? note, string? actor);
        Task AddNoteAsync(string farmId, int alertId, string note, string? actor);
        Task ResolveAsync(string farmId, int alertId, string note, string? actor);
        Task<IReadOnlyList<FlockAnomalySignalSetting>> GetSettingsAsync(string farmId);
        Task SetSettingAsync(FlockAnomalySignalSetting s, string? updatedBy);
        Task ResetSettingAsync(string farmId, string signalKey);
    }

    public class PoultryFlockAnomalyService : IPoultryFlockAnomalyService
    {
        private readonly string _cs;
        public PoultryFlockAnomalyService(string cs) => _cs = cs;

        public async Task<IReadOnlyList<FlockSignalEvaluation>> EvaluateAsync(string farmId, DateTime? date)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryanomaly_evaluate(p_farmid => @FarmId::text, p_date => @Date::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Date", date.HasValue ? date.Value.Date : DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<FlockSignalEvaluation>();
            while (await r.ReadAsync())
            {
                list.Add(new FlockSignalEvaluation
                {
                    FlockId = Int(r, "flockid"),
                    FlockName = Str(r, "flockname") ?? string.Empty,
                    HouseName = Str(r, "housename"),
                    BusinessDate = r.GetDateTime(r.GetOrdinal("businessdate")),
                    SignalKey = Str(r, "signalkey") ?? string.Empty,
                    SignalLabel = Str(r, "signallabel") ?? string.Empty,
                    MetricKey = Str(r, "metrickey") ?? string.Empty,
                    MetricLabel = Str(r, "metriclabel") ?? string.Empty,
                    MetricUnit = Str(r, "metricunit") ?? string.Empty,
                    Direction = Str(r, "direction") ?? "up",
                    Status = Str(r, "status") ?? "Normal",
                    Severity = Str(r, "severity"),
                    SeverityRank = Int(r, "severityrank"),
                    CurrentValue = Dec(r, "currentvalue"),
                    BaselineMean = Dec(r, "baselinemean"),
                    BaselineStdDev = Dec(r, "baselinestddev"),
                    BaselinePoints = Int(r, "baselinepoints"),
                    BaselineFrom = r.GetDateTime(r.GetOrdinal("baselinefrom")),
                    BaselineTo = r.GetDateTime(r.GetOrdinal("baselineto")),
                    Method = Str(r, "method") ?? "ratio",
                    Observed = Dec(r, "observed"),
                    ChangePct = Dec(r, "changepct"),
                    InformationThreshold = Dec(r, "informationthreshold"),
                    WarningThreshold = Dec(r, "warningthreshold") ?? 0,
                    CriticalThreshold = Dec(r, "criticalthreshold") ?? 0,
                    Evidence = Json(r, "evidence") ?? default,
                    Explanation = r.IsDBNull(r.GetOrdinal("explanation")) ? Array.Empty<string>()
                        : r.GetFieldValue<string[]>(r.GetOrdinal("explanation")),
                });
            }
            return list;
        }

        public async Task<IReadOnlyList<FlockAlertScanResult>> ScanAsync(string farmId, DateTime? from, DateTime? to, string? actor)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryanomaly_scan(p_farmid => @FarmId::text, p_from => @From::date, "
                + "p_to => @To::date, p_actor => @Actor::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@From", from.HasValue ? from.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@To", to.HasValue ? to.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@Actor", (object?)actor ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<FlockAlertScanResult>();
            while (await r.ReadAsync())
            {
                list.Add(new FlockAlertScanResult
                {
                    ScanDate = r.GetDateTime(r.GetOrdinal("scandate")),
                    FlocksEvaluated = Int(r, "flocksevaluated"),
                    AlertsOpened = Int(r, "alertsopened"),
                    AlertsUpdated = Int(r, "alertsupdated"),
                    AlertsCleared = Int(r, "alertscleared"),
                    AlertsEscalated = Int(r, "alertsescalated"),
                });
            }
            return list;
        }

        public async Task<IReadOnlyList<FlockAlert>> ListAsync(string farmId, string? status, DateTime? from, DateTime? to, int? flockId, int? alertId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryflockalert_list(p_farmid => @FarmId::text, p_status => @Status::text, "
                + "p_from => @From::date, p_to => @To::date, p_flockid => @Flock::int, p_alertid => @Alert::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", string.IsNullOrWhiteSpace(status) ? "active" : status);
            cmd.Parameters.AddWithValue("@From", from.HasValue ? from.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@To", to.HasValue ? to.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@Flock", flockId.HasValue ? flockId.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@Alert", alertId.HasValue ? alertId.Value : DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<FlockAlert>();
            while (await r.ReadAsync())
            {
                list.Add(new FlockAlert
                {
                    AlertId = Int(r, "alertid"),
                    FlockId = Int(r, "flockid"),
                    FlockName = Str(r, "flockname") ?? string.Empty,
                    HouseName = Str(r, "housename"),
                    BusinessDate = r.GetDateTime(r.GetOrdinal("businessdate")),
                    Status = Str(r, "status") ?? "Open",
                    Severity = Str(r, "severity") ?? "Information",
                    SeverityRank = Int(r, "severityrank"),
                    PeakSeverity = Str(r, "peakseverity") ?? "Information",
                    ActiveSignalCount = Int(r, "activesignalcount"),
                    ConsecutiveDays = Int(r, "consecutivedays"),
                    FirstDetectedAtUtc = r.GetDateTime(r.GetOrdinal("firstdetectedatutc")),
                    LastEvaluatedAtUtc = r.GetDateTime(r.GetOrdinal("lastevaluatedatutc")),
                    AcknowledgedBy = Str(r, "acknowledgedby"),
                    AcknowledgedAtUtc = Date(r, "acknowledgedatutc"),
                    ResolvedBy = Str(r, "resolvedby"),
                    ResolvedAtUtc = Date(r, "resolvedatutc"),
                    ResolutionNote = Str(r, "resolutionnote"),
                    NoteCount = Int(r, "notecount"),
                    Signals = Json(r, "signals") ?? default,
                });
            }
            return list;
        }

        public async Task<IReadOnlyList<FlockAlertEvent>> GetEventsAsync(string farmId, int alertId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryflockalert_events(p_farmid => @FarmId::text, p_alertid => @Alert::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Alert", alertId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<FlockAlertEvent>();
            while (await r.ReadAsync())
            {
                list.Add(new FlockAlertEvent
                {
                    EventId = r.GetInt64(r.GetOrdinal("eventid")),
                    AlertId = Int(r, "alertid"),
                    EventType = Str(r, "eventtype") ?? string.Empty,
                    SignalKey = Str(r, "signalkey"),
                    Note = Str(r, "note"),
                    Actor = Str(r, "actor"),
                    Details = Json(r, "details"),
                    AtUtc = r.GetDateTime(r.GetOrdinal("atutc")),
                });
            }
            return list;
        }

        public Task AcknowledgeAsync(string farmId, int alertId, string? note, string? actor)
            => ActAsync("sppoultryflockalert_acknowledge", farmId, alertId, note, actor);

        public Task AddNoteAsync(string farmId, int alertId, string note, string? actor)
            => ActAsync("sppoultryflockalert_addnote", farmId, alertId, note, actor);

        public Task ResolveAsync(string farmId, int alertId, string note, string? actor)
            => ActAsync("sppoultryflockalert_resolve", farmId, alertId, note, actor);

        private async Task ActAsync(string fn, string farmId, int alertId, string? note, string? actor)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                $"SELECT {fn}(p_farmid => @FarmId::text, p_alertid => @Alert::int, p_note => @Note::text, p_actor => @Actor::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Alert", alertId);
            cmd.Parameters.AddWithValue("@Note", (object?)note ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Actor", (object?)actor ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<IReadOnlyList<FlockAnomalySignalSetting>> GetSettingsAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryanomalysettings_get(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<FlockAnomalySignalSetting>();
            while (await r.ReadAsync())
            {
                list.Add(new FlockAnomalySignalSetting
                {
                    FarmId = farmId,
                    SignalKey = Str(r, "signalkey") ?? string.Empty,
                    Label = Str(r, "label") ?? string.Empty,
                    MetricLabel = Str(r, "metriclabel") ?? string.Empty,
                    MetricUnit = Str(r, "metricunit") ?? string.Empty,
                    Direction = Str(r, "direction") ?? "up",
                    GuardField = Str(r, "guardfield"),
                    GuardLabel = Str(r, "guardlabel"),
                    Enabled = r.GetBoolean(r.GetOrdinal("enabled")),
                    Method = Str(r, "method") ?? "ratio",
                    BaselineDays = Int(r, "baselinedays"),
                    MinBaselineDays = Int(r, "minbaselinedays"),
                    InformationThreshold = Dec(r, "informationthreshold"),
                    WarningThreshold = Dec(r, "warningthreshold") ?? 0,
                    CriticalThreshold = Dec(r, "criticalthreshold") ?? 0,
                    GuardMinimum = Dec(r, "guardminimum"),
                    BaselineFloor = Dec(r, "baselinefloor") ?? 0,
                    IsCustomised = r.GetBoolean(r.GetOrdinal("iscustomised")),
                    UpdatedBy = Str(r, "updatedby"),
                    UpdatedAtUtc = Date(r, "updatedatutc"),
                });
            }
            return list;
        }

        public async Task SetSettingAsync(FlockAnomalySignalSetting s, string? updatedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryanomalysettings_set(p_farmid => @FarmId::text, p_signalkey => @Key::text, "
                + "p_enabled => @On::boolean, p_method => @Method::text, p_baselinedays => @Days::int, "
                + "p_minbaselinedays => @Min::int, p_informationthreshold => @Info::numeric, "
                + "p_warningthreshold => @Warn::numeric, p_criticalthreshold => @Crit::numeric, "
                + "p_guardminimum => @Guard::numeric, p_baselinefloor => @Floor::numeric, p_updatedby => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", s.FarmId);
            cmd.Parameters.AddWithValue("@Key", s.SignalKey);
            cmd.Parameters.AddWithValue("@On", s.Enabled);
            cmd.Parameters.AddWithValue("@Method", s.Method);
            cmd.Parameters.AddWithValue("@Days", s.BaselineDays);
            cmd.Parameters.AddWithValue("@Min", s.MinBaselineDays);
            cmd.Parameters.AddWithValue("@Info", s.InformationThreshold.HasValue ? s.InformationThreshold.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@Warn", s.WarningThreshold);
            cmd.Parameters.AddWithValue("@Crit", s.CriticalThreshold);
            cmd.Parameters.AddWithValue("@Guard", s.GuardMinimum.HasValue ? s.GuardMinimum.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@Floor", s.BaselineFloor);
            cmd.Parameters.AddWithValue("@By", (object?)updatedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ResetSettingAsync(string farmId, string signalKey)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryanomalysettings_reset(p_farmid => @FarmId::text, p_signalkey => @Key::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Key", signalKey);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static string? Str(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetValue(i).ToString();
        }

        private static int Int(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? 0 : Convert.ToInt32(r.GetValue(i));
        }

        private static decimal? Dec(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : Convert.ToDecimal(r.GetValue(i));
        }

        private static DateTime? Date(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetDateTime(i);
        }

        private static JsonElement? Json(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            if (r.IsDBNull(i)) return null;
            using var doc = JsonDocument.Parse(r.GetValue(i).ToString() ?? "null");
            return doc.RootElement.Clone();
        }
    }
}
