using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Batch Bird Reconciliation (migration 413). Thin wrapper: every rule lives
    /// in the database functions, so the Batch page, the Farm Setup view and the
    /// Initial Farm Setup wizard cannot disagree about how a bird is counted.
    /// </summary>
    public interface IBirdReconciliationService
    {
        Task<List<BatchBirdReconciliationRow>> GetSummaryAsync(string farmId);
        Task<string> GetDetailAsync(string farmId, int batchId);
        Task<string> PostAsync(BatchReconciliationRequest request);
        Task<string> ReverseAsync(int reconciliationId, BatchReconciliationReverseRequest request);
        Task<string> TransferAsync(BirdTransferRequest request);
        Task<List<BirdRepairDiagnosticRow>> DiagnoseAsync(string farmId);
        Task<List<BirdRepairAppliedRow>> RepairAsync(BirdRepairApplyRequest request);
    }

    public class BirdReconciliationService : IBirdReconciliationService
    {
        private readonly string _cs;
        public BirdReconciliationService(string cs) => _cs = cs;

        private static readonly JsonSerializerOptions LineJson = new()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        };

        /// <summary>
        /// The reconciliation call, built for the caller's connection and
        /// transaction — Initial Farm Setup posts it inside its own commit.
        /// </summary>
        internal static NpgsqlCommand BuildPostCommand(NpgsqlConnection conn, NpgsqlTransaction? tx, BatchReconciliationRequest m)
        {
            var lines = new List<object>();
            foreach (var l in m.Lines ?? new List<BatchReconciliationLine>())
            {
                lines.Add(new
                {
                    kind = l.Kind,
                    quantity = l.Quantity,
                    date = l.Date?.ToString("yyyy-MM-dd"),
                    note = l.Note,
                    direction = l.Direction,
                    flockId = l.FlockId,
                    pricePerBird = l.PricePerBird,
                    valueUnknown = l.ValueUnknown,
                    customerId = l.CustomerId,
                    amountReceived = l.AmountReceived,
                    createReceivable = l.CreateReceivable,
                    linkDebtId = l.LinkDebtId,
                    reference = l.Reference,
                    classification = string.IsNullOrWhiteSpace(l.Classification) ? "PreCutover" : l.Classification,
                });
            }

            var cmd = new NpgsqlCommand(
                "SELECT sppoultrybatchreconcile_post(p_farmid => @FarmId::text, p_batchid => @BatchId::int, " +
                "p_asofdate => @AsOf::date, p_lines => @Lines::jsonb, p_stillalive => @StillAlive::int, " +
                "p_notes => @Notes::text, p_source => @Source::text, p_requestkey => @Key::text, p_by => @By::text)::text",
                conn, tx);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@BatchId", m.BatchId);
            cmd.Parameters.AddWithValue("@AsOf", m.AsOfDate.HasValue ? m.AsOfDate.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@Lines", JsonSerializer.Serialize(lines, LineJson));
            cmd.Parameters.AddWithValue("@StillAlive", m.StillUnallocatedLive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Source", string.IsNullOrWhiteSpace(m.Source) ? "Batch" : m.Source!);
            cmd.Parameters.AddWithValue("@Key", (object?)m.RequestKey ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", (object?)m.CreatedBy ?? DBNull.Value);
            return cmd;
        }

        public async Task<List<BatchBirdReconciliationRow>> GetSummaryAsync(string farmId)
        {
            var list = new List<BatchBirdReconciliationRow>();
            using var c = new NpgsqlConnection(_cs);
            // 418 adds the flock-side columns. Before 418 they are absent, so
            // fall back to the old inline flock-sold join (opening + posted sales).
            using var cmd = new NpgsqlCommand(@"
                SELECT s.*, COALESCE(fs.sold, 0)::int AS flocksold
                FROM   sppoultrybatchreconcile_summary(p_farmid => @FarmId::text) s
                LEFT   JOIN (SELECT f.batchid, SUM(bp.openingsold + bp.birdssold)::int AS sold
                             FROM   flock f
                             CROSS  JOIN LATERAL fnflock_birdposition(@FarmId::text, f.flockid) bp
                             WHERE  f.farmid = @FarmId::text AND NOT f.isdeleted
                             GROUP  BY f.batchid) fs ON fs.batchid = s.batchid
                ORDER  BY s.startdate DESC, s.batchid DESC", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new BatchBirdReconciliationRow
                {
                    BatchId = r.Int("batchid"), BatchCode = r.StrN("batchcode") ?? "", BatchName = r.StrN("batchname") ?? "",
                    StartDate = r.Date("startdate"), IsHistorical = r.Bool("ishistorical"),
                    OriginalBirds = r.Int("originalbirds"), OriginallyAllocated = r.Int("originallyallocated"),
                    FlockCount = r.Int("flockcount"),
                    BatchSold = r.Int("batchsold"), FlockSold = r.Int("flocksold"), BatchMortality = r.Int("batchmortality"), BatchCulled = r.Int("batchculled"),
                    BatchTransferred = r.Int("batchtransferred"), BatchOtherRemovals = r.Int("batchotherremovals"),
                    BatchAdditions = r.Int("batchadditions"),
                    UnallocatedPool = r.Int("unallocatedpool"), UnallocatedLive = r.Int("unallocatedlive"),
                    Unexplained = r.Int("unexplained"),
                    FlockLiveBirds = r.Int("flocklivebirds"), TotalLiveBirds = r.Int("totallivebirds"),
                    FlockHistoricalReductions = r.Int("flockhistoricalreductions"),
                    HistoricalSaleBirds = r.Int("historicalsalebirds"), HistoricalSaleValue = r.Dec("historicalsalevalue"),
                    HistoricalReceived = r.Dec("historicalreceived"), HistoricalOwed = r.Dec("historicalowed"),
                    Status = r.Str("status"), LastReconciledAt = r.DateN("lastreconciledat"),
                    LastReconciliationNo = r.StrN("lastreconciliationno"),
                    FlockHistMortality = IntOr0(r, "flockhistmortality"),
                    FlockHistSold = IntOr0(r, "flockhistsold"),
                    FlockHistCulled = IntOr0(r, "flockhistculled"),
                    FlockHistTransferred = IntOr0(r, "flockhisttransferred"),
                    FlockHistOther = IntOr0(r, "flockhistother"),
                    FlockRecordedMortality = IntOr0(r, "flockrecordedmortality"),
                    FlockPostedSold = IntOr0(r, "flockpostedsold"),
                    FlockCulled = IntOr0(r, "flockculled"),
                    FlockTransferred = IntOr0(r, "flocktransferred"),
                    FlockOtherChanges = IntOr0(r, "flockotherchanges"),
                });
            }
            return list;
        }

        // A column 418 added; 0 when the database predates it.
        private static int IntOr0(NpgsqlDataReader r, string name)
        {
            for (var i = 0; i < r.FieldCount; i++)
                if (r.GetName(i) == name) return r.IsDBNull(i) ? 0 : r.GetInt32(i);
            return 0;
        }

        public async Task<string> GetDetailAsync(string farmId, int batchId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sppoultrybatchreconcile_detail(p_farmid => @FarmId::text, p_batchid => @BatchId::int)::text", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@BatchId", batchId);
            await c.OpenAsync();
            return (string?)await cmd.ExecuteScalarAsync() ?? "{}";
        }

        public async Task<string> PostAsync(BatchReconciliationRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            using var cmd = BuildPostCommand(c, null, m);
            return (string?)await cmd.ExecuteScalarAsync() ?? "{}";
        }

        public async Task<string> ReverseAsync(int reconciliationId, BatchReconciliationReverseRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrybatchreconcile_reverse(p_farmid => @FarmId::text, p_reconciliationid => @Id::int, " +
                "p_reason => @Reason::text, p_by => @By::text)::text", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Id", reconciliationId);
            cmd.Parameters.AddWithValue("@Reason", m.Reason ?? string.Empty);
            cmd.Parameters.AddWithValue("@By", (object?)m.ReversedBy ?? DBNull.Value);
            await c.OpenAsync();
            return (string?)await cmd.ExecuteScalarAsync() ?? "{}";
        }

        public async Task<string> TransferAsync(BirdTransferRequest m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrybirdtransfer_post(p_farmid => @FarmId::text, p_fromflockid => @From::int, p_toflockid => @To::int, " +
                "p_quantity => @Qty::int, p_effectivedate => @Date::date, p_note => @Note::text, p_requestkey => @Key::text, p_by => @By::text)::text", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@From", m.FromFlockId);
            cmd.Parameters.AddWithValue("@To", m.ToFlockId);
            cmd.Parameters.AddWithValue("@Qty", m.Quantity);
            cmd.Parameters.AddWithValue("@Date", m.EffectiveDate.HasValue ? m.EffectiveDate.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@Note", (object?)m.Note ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Key", (object?)m.RequestKey ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync();
            return (string?)await cmd.ExecuteScalarAsync() ?? "{}";
        }

        public async Task<List<BirdRepairDiagnosticRow>> DiagnoseAsync(string farmId)
        {
            var list = new List<BirdRepairDiagnosticRow>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM fnpoultrybirdrepair_diagnose(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new BirdRepairDiagnosticRow
                {
                    FarmId = r.Str("farmid"), CheckCode = r.Str("checkcode"), Severity = r.Str("severity"),
                    LedgerRowId = r.IntN("ledgerrowid"), OpeningPositionId = r.IntN("openingpositionid"),
                    BatchId = r.IntN("batchid"), FlockId = r.IntN("flockid"), FlockName = r.StrN("flockname"),
                    CurrentValue = r.StrN("currentvalue"), ExpectedValue = r.StrN("expectedvalue"),
                    MissingRelationship = r.StrN("missingrelationship"), ProposedCorrection = r.StrN("proposedcorrection"),
                    DoubleApplicationRisk = r.StrN("doubleapplicationrisk"), Confidence = r.Str("confidence"),
                    Evidence = r.StrN("evidence"), AutoRepairable = r.Bool("autorepairable"),
                });
            }
            return list;
        }

        public async Task<List<BirdRepairAppliedRow>> RepairAsync(BirdRepairApplyRequest m)
        {
            var list = new List<BirdRepairAppliedRow>();
            using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            using var tx = await c.BeginTransactionAsync();
            using (var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrybirdrepair_apply(p_farmid => @FarmId::text, p_by => @By::text, p_dryrun => @DryRun::boolean)", c, tx))
            {
                cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
                cmd.Parameters.AddWithValue("@By", (object?)m.RepairedBy ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@DryRun", m.DryRun);
                using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    list.Add(new BirdRepairAppliedRow
                    {
                        CheckCode = r.Str("checkcode"), LedgerRowId = r.Int("ledgerrowid"),
                        BatchId = r.IntN("batchid"), FlockId = r.IntN("flockid"),
                        Applied = r.Bool("applied"), Evidence = r.StrN("evidence"),
                    });
                }
            }
            // A dry run is rolled back as well, so it can never write by mistake.
            if (m.DryRun) await tx.RollbackAsync(); else await tx.CommitAsync();
            return list;
        }
    }
}
