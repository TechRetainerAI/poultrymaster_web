using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Initial Farm Setup: turn "here is what my farm looks like today" into
    /// batches, houses, flocks and opening positions, in one transaction.
    ///
    /// <para><b>What makes this correct.</b> A flock is created with its
    /// <i>opening live birds</i> as its quantity — 960, not the 1,050 originally
    /// placed. Current-bird maths in this application reads the latest production
    /// record and falls back to the flock's quantity, so with no production records
    /// the farm reads 960 immediately and the first real record starts from 960.
    /// Nothing here writes a production record, so the months of mortality behind
    /// that 90-bird gap can never surface as "Deaths Today".</para>
    ///
    /// <para><b>What is reused, not rebuilt.</b> Batches go through
    /// <see cref="MainFlockBatchService.BuildInsertCommand"/>, houses through
    /// <see cref="HouseService.BuildInsertCommand"/> and flocks through
    /// <see cref="BirdFlockService.BuildFlockInsertCommand"/> — the very command
    /// builders the ordinary pages, the bulk house tool and the batch allocation
    /// tool use. They are <c>internal static</c> for exactly this reason: the
    /// wizard needs them inside ITS transaction, and a second copy of any of those
    /// inserts is how the three paths would drift apart.</para>
    /// </summary>
    public class FarmSetupService : IFarmSetupService
    {
        private readonly string _connectionString;
        private readonly IMainFlockBatchService _batchService;
        private readonly IHouseService _houseService;
        private readonly IBirdFlockService _flockService;

        public FarmSetupService(
            string connectionString,
            IMainFlockBatchService batchService,
            IHouseService houseService,
            IBirdFlockService flockService)
        {
            _connectionString = connectionString;
            _batchService = batchService;
            _houseService = houseService;
            _flockService = flockService;
        }

        // ------------------------------------------------------------------
        // Status
        // ------------------------------------------------------------------

        public async Task<FarmSetupStatusModel> GetStatusAsync(string userId, string farmId)
        {
            var status = await ReadSetupRowAsync(farmId, null, null) ?? new FarmSetupStatusModel { FarmId = farmId };

            // What the company already has decides whether the wizard is OFFERED.
            // It never decides whether it may run — that is the setup row above.
            var batches = await _batchService.GetAll(userId, farmId);
            var houses = _houseService.GetAll(userId, farmId);
            var flocks = _flockService.GetAllFlocks(userId, farmId);

            status.FarmId = farmId;
            status.ExistingBatches = batches.Count;
            status.ExistingHouses = houses.Count;
            status.ExistingFlocks = flocks.Count;
            status.LooksEmpty = batches.Count == 0 && houses.Count == 0 && flocks.Count == 0;

            return status;
        }

        private async Task<FarmSetupStatusModel?> ReadSetupRowAsync(
            string farmId, NpgsqlConnection? conn, NpgsqlTransaction? tx)
        {
            var owned = conn is null;
            conn ??= new NpgsqlConnection(_connectionString);
            try
            {
                if (owned) await conn.OpenAsync();

                using var cmd = new NpgsqlCommand(
                    "SELECT * FROM sppoultryfarmsetup_get(p_farmid => @FarmId::text)", conn, tx);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                using var reader = await cmd.ExecuteReaderAsync();
                if (!await reader.ReadAsync()) return null;

                return new FarmSetupStatusModel
                {
                    IsComplete = true,
                    FarmSetupId = reader.GetInt32(reader.GetOrdinal("farmsetupid")),
                    FarmId = reader.GetString(reader.GetOrdinal("farmid")),
                    SetupMode = reader.GetString(reader.GetOrdinal("setupmode")),
                    CompletedBusinessDate = reader.GetDateTime(reader.GetOrdinal("completedbusinessdate")),
                    CompletedAt = reader.GetDateTime(reader.GetOrdinal("completedat")),
                    CompletedBy = reader.IsDBNull(reader.GetOrdinal("completedby")) ? null : reader.GetString(reader.GetOrdinal("completedby")),
                    BatchCount = reader.GetInt32(reader.GetOrdinal("batchcount")),
                    HouseCount = reader.GetInt32(reader.GetOrdinal("housecount")),
                    FlockCount = reader.GetInt32(reader.GetOrdinal("flockcount")),
                    OriginallyPlaced = reader.GetInt32(reader.GetOrdinal("originallyplaced")),
                    OpeningLiveBirds = reader.GetInt32(reader.GetOrdinal("openinglivebirds")),
                    HistoricalReduction = reader.GetInt32(reader.GetOrdinal("historicalreduction")),
                    Notes = reader.IsDBNull(reader.GetOrdinal("notes")) ? null : reader.GetString(reader.GetOrdinal("notes")),
                };
            }
            finally
            {
                if (owned) await conn.DisposeAsync();
            }
        }

        // ------------------------------------------------------------------
        // The unfinished setup
        // ------------------------------------------------------------------

        public async Task<FarmSetupDraftModel?> GetDraftAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryfarmsetupdraft_get(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync()) return null;

            return new FarmSetupDraftModel
            {
                FarmId = reader.GetString(reader.GetOrdinal("farmid")),
                // Handed back as the text the wizard sent. The server never reads
                // into it -- see the note in migration 328 on why it is jsonb.
                Draft = reader.GetString(reader.GetOrdinal("draft")),
                Step = reader.GetInt32(reader.GetOrdinal("step")),
                Phase = reader.IsDBNull(reader.GetOrdinal("phase")) ? null : reader.GetString(reader.GetOrdinal("phase")),
                UpdatedBy = reader.IsDBNull(reader.GetOrdinal("updatedby")) ? null : reader.GetString(reader.GetOrdinal("updatedby")),
                UpdatedAt = reader.GetDateTime(reader.GetOrdinal("updatedat")),
            };
        }

        public async Task<DateTime> SaveDraftAsync(FarmSetupDraftModel draft)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryfarmsetupdraft_save(" +
                "p_farmid => @FarmId::text, p_draft => @Draft::jsonb, p_step => @Step::int, " +
                "p_phase => @Phase::text, p_updatedby => @UpdatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", draft.FarmId);
            cmd.Parameters.AddWithValue("@Draft", string.IsNullOrWhiteSpace(draft.Draft) ? "{}" : draft.Draft);
            cmd.Parameters.AddWithValue("@Step", draft.Step);
            cmd.Parameters.AddWithValue("@Phase", (object?)draft.Phase ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)draft.UpdatedBy ?? DBNull.Value);

            var at = await cmd.ExecuteScalarAsync();
            return at is DateTime stamp ? stamp : DateTime.UtcNow;
        }

        public async Task<bool> DeleteDraftAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            return await DeleteDraftAsync(farmId, conn, null);
        }

        /// <summary>
        /// The in-transaction form, so completing a setup discards its draft as
        /// part of the same commit. A draft that outlived the farm it created
        /// would offer to resume work that has already been done.
        /// </summary>
        private static async Task<bool> DeleteDraftAsync(
            string farmId, NpgsqlConnection conn, NpgsqlTransaction? tx)
        {
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryfarmsetupdraft_delete(p_farmid => @FarmId::text)", conn, tx);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            var rows = await cmd.ExecuteScalarAsync();
            return Convert.ToInt32(rows ?? 0) > 0;
        }

        // ------------------------------------------------------------------
        // Opening positions
        // ------------------------------------------------------------------

        public async Task<OpeningPositionSummaryModel> GetOpeningPositionsAsync(string farmId)
        {
            var summary = new OpeningPositionSummaryModel();

            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryopeningposition_getall(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                summary.Positions.Add(new OpeningFlockPositionModel
                {
                    OpeningPositionId = reader.GetInt32(reader.GetOrdinal("openingpositionid")),
                    FarmId = reader.GetString(reader.GetOrdinal("farmid")),
                    FlockId = reader.GetInt32(reader.GetOrdinal("flockid")),
                    FlockName = reader.IsDBNull(reader.GetOrdinal("flockname")) ? null : reader.GetString(reader.GetOrdinal("flockname")),
                    BatchId = reader.IsDBNull(reader.GetOrdinal("batchid")) ? null : reader.GetInt32(reader.GetOrdinal("batchid")),
                    HouseId = reader.IsDBNull(reader.GetOrdinal("houseid")) ? null : reader.GetInt32(reader.GetOrdinal("houseid")),
                    EffectiveBusinessDate = reader.GetDateTime(reader.GetOrdinal("effectivebusinessdate")),
                    OriginallyPlaced = reader.GetInt32(reader.GetOrdinal("originallyplaced")),
                    OpeningLiveBirds = reader.GetInt32(reader.GetOrdinal("openinglivebirds")),
                    HistoricalMortality = reader.GetInt32(reader.GetOrdinal("historicalmortality")),
                    HistoricalSold = reader.GetInt32(reader.GetOrdinal("historicalsold")),
                    HistoricalCulled = reader.GetInt32(reader.GetOrdinal("historicalculled")),
                    HistoricalTransferred = reader.GetInt32(reader.GetOrdinal("historicaltransferred")),
                    OtherAdjustment = reader.GetInt32(reader.GetOrdinal("otheradjustment")),
                    HistoryKnown = reader.GetBoolean(reader.GetOrdinal("historyknown")),
                    StartDateEstimated = reader.GetBoolean(reader.GetOrdinal("startdateestimated")),
                    Source = reader.GetString(reader.GetOrdinal("source")),
                    Notes = reader.IsDBNull(reader.GetOrdinal("notes")) ? null : reader.GetString(reader.GetOrdinal("notes")),
                    CreatedBy = reader.IsDBNull(reader.GetOrdinal("createdby")) ? null : reader.GetString(reader.GetOrdinal("createdby")),
                    CreatedAt = reader.IsDBNull(reader.GetOrdinal("createdat")) ? null : reader.GetDateTime(reader.GetOrdinal("createdat")),
                });
            }

            summary.FlockCount = summary.Positions.Count;
            summary.OriginallyPlaced = summary.Positions.Sum(p => p.OriginallyPlaced);
            summary.OpeningLiveBirds = summary.Positions.Sum(p => p.OpeningLiveBirds);
            summary.HistoricalReduction = summary.Positions.Sum(p => p.HistoricalReduction);
            summary.HistoricalMortality = summary.Positions.Sum(p => p.HistoricalMortality);
            summary.HistoricalSold = summary.Positions.Sum(p => p.HistoricalSold);
            summary.HistoricalCulled = summary.Positions.Sum(p => p.HistoricalCulled);
            summary.HistoricalTransferred = summary.Positions.Sum(p => p.HistoricalTransferred);
            summary.OtherAdjustment = summary.Positions.Sum(p => p.OtherAdjustment);
            summary.FlocksWithUnknownHistory = summary.Positions.Count(p => !p.HistoryKnown && p.HistoricalReduction > 0);

            return summary;
        }

        // ------------------------------------------------------------------
        // The setup itself
        // ------------------------------------------------------------------

        // ------------------------------------------------------------------
        // 416: setup runs -- list and undo
        // ------------------------------------------------------------------

        public async Task<string> ListRunsAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            using (var has = new NpgsqlCommand("SELECT to_regprocedure('sppoultryfarmsetuprun_list(text)') IS NOT NULL", conn))
            {
                if (await has.ExecuteScalarAsync() is not true) return "[]";
            }
            using var cmd = new NpgsqlCommand(
                "SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.setuprunid DESC), '[]'::jsonb)::text " +
                "FROM sppoultryfarmsetuprun_list(p_farmid => @FarmId::text) r", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            return (string?)await cmd.ExecuteScalarAsync() ?? "[]";
        }

        public async Task<string> ReverseRunAsync(string farmId, int setupRunId, string reason, string? by)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            using var tx = await conn.BeginTransactionAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryfarmsetuprun_reverse(p_farmid => @FarmId::text, p_setuprunid => @Run::int, " +
                "p_reason => @Reason::text, p_by => @By::text)::text", conn, tx);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Run", setupRunId);
            cmd.Parameters.AddWithValue("@Reason", reason ?? string.Empty);
            cmd.Parameters.AddWithValue("@By", (object?)by ?? DBNull.Value);
            var json = (string?)await cmd.ExecuteScalarAsync() ?? "{}";
            await tx.CommitAsync();
            return json;
        }

        public async Task<string> ListLegacyCandidatesAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            using (var has = new NpgsqlCommand("SELECT to_regprocedure('fnpoultryfarmsetuplegacy_candidates(text)') IS NOT NULL", conn))
            {
                if (await has.ExecuteScalarAsync() is not true) return "[]";
            }
            using var cmd = new NpgsqlCommand(
                "SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]'::jsonb)::text " +
                "FROM fnpoultryfarmsetuplegacy_candidates(p_farmid => @FarmId::text) c", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            return (string?)await cmd.ExecuteScalarAsync() ?? "[]";
        }

        public async Task<string> ReverseLegacyAsync(string farmId, string itemsJson, string reason, string? by)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            using var tx = await conn.BeginTransactionAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryfarmsetuplegacy_reverse(p_farmid => @FarmId::text, p_items => @Items::jsonb, " +
                "p_reason => @Reason::text, p_by => @By::text)::text", conn, tx);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Items", itemsJson);
            cmd.Parameters.AddWithValue("@Reason", reason ?? string.Empty);
            cmd.Parameters.AddWithValue("@By", (object?)by ?? DBNull.Value);
            var json = (string?)await cmd.ExecuteScalarAsync() ?? "{}";
            await tx.CommitAsync();
            return json;
        }

        public async Task<FarmSetupResult> CompleteAsync(
            FarmSetupRequest request,
            DateTime effectiveBusinessDate,
            Func<Task<IReadOnlyList<FarmSetupRowError>>> revalidate)
        {
            var source = string.IsNullOrWhiteSpace(request.Source) ? "Initial Farm Setup" : request.Source!.Trim();
            var result = new FarmSetupResult { EffectiveBusinessDate = effectiveBusinessDate.Date };

            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            using var tx = await conn.BeginTransactionAsync();

            // Which call we are on, so a database error names the step that raised
            // it. Without this a failure anywhere in a twenty-statement sequence
            // arrives as a bare SQLSTATE with nothing to chase.
            var stage = "opening the transaction";
            try
            {
                // One setup session per company at a time.
                stage = "taking the company setup lock";
                using (var lockCmd = new NpgsqlCommand("SELECT pg_advisory_xact_lock(hashtext(@Key))", conn, tx))
                {
                    lockCmd.Parameters.AddWithValue("@Key", $"farm-setup:{request.FarmId}");
                    await lockCmd.ExecuteNonQueryAsync();
                }

                // Re-validate under the lock, against what is committed RIGHT NOW.
                //
                // This used to be "has this company been set up before?", which made
                // the tool usable exactly once. It is meant to be reopened -- a farm
                // that builds new pens or buys another batch comes back -- so the
                // question is no longer "has setup run?" but "would this submission
                // create something that already exists?". Duplicate batch codes,
                // house names and flock names are all ordinary validation errors,
                // and running that validation again here is what stops two tabs
                // that both passed it a moment ago from doubling the farm.
                stage = "re-checking for clashes";
                var conflicts = await revalidate();
                if (conflicts.Count > 0)
                {
                    throw new FarmSetupConflictException(conflicts);
                }

                // 416: this setup is a run that remembers what it creates, so it
                // can be undone later. Skipped (not failed) until 416 is applied.
                stage = "recording the setup run";
                int? runId = null;
                using (var has = new NpgsqlCommand(
                    "SELECT to_regprocedure('sppoultryfarmsetuprun_start(text,date,text,text)') IS NOT NULL", conn, tx))
                {
                    if (await has.ExecuteScalarAsync() is true)
                    {
                        using var start = new NpgsqlCommand(
                            "SELECT sppoultryfarmsetuprun_start(p_farmid => @FarmId::text, p_businessdate => @Date::date, " +
                            "p_by => @By::text, p_source => @Source::text)", conn, tx);
                        start.Parameters.AddWithValue("@FarmId", request.FarmId);
                        start.Parameters.AddWithValue("@Date", effectiveBusinessDate.Date);
                        start.Parameters.AddWithValue("@By", request.UserId);
                        start.Parameters.AddWithValue("@Source", source);
                        runId = Convert.ToInt32(await start.ExecuteScalarAsync());
                        result.SetupRunId = runId;
                    }
                }
                async Task TrackAsync(string type, int id)
                {
                    if (runId is null) return;
                    using var add = new NpgsqlCommand(
                        "SELECT sppoultryfarmsetuprun_additem(p_setuprunid => @Run::int, p_entitytype => @Type::text, p_entityid => @Id::int)",
                        conn, tx);
                    add.Parameters.AddWithValue("@Run", runId.Value);
                    add.Parameters.AddWithValue("@Type", type);
                    add.Parameters.AddWithValue("@Id", id);
                    await add.ExecuteNonQueryAsync();
                }

                // ---- 1. Batches -------------------------------------------
                var batchIdByKey = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                foreach (var b in request.Batches ?? new List<FarmSetupBatchInput>())
                {
                    var key = FarmSetupValidator.Normalize(b.Key);
                    if (b.ExistingBatchId.HasValue)
                    {
                        batchIdByKey[key] = b.ExistingBatchId.Value;
                        result.BatchesReused++;
                        continue;
                    }

                    var model = new MainFlockBatchModel
                    {
                        UserId = request.UserId,
                        FarmId = request.FarmId,
                        BatchCode = FarmSetupValidator.Normalize(b.BatchCode),
                        BatchName = FarmSetupValidator.Normalize(b.BatchName),
                        Breed = FarmSetupValidator.Normalize(b.Breed),
                        NumberOfBirds = b.NumberOfBirds,
                        StartDate = b.StartDate,
                        Status = string.IsNullOrWhiteSpace(b.Status) ? "active" : b.Status!.Trim(),
                        // Financials are optional for an established farm; an unknown
                        // purchase price stays zero rather than being invented.
                        CostPerChick = b.CostPerChick ?? 0m,
                        TotalCost = b.TotalCost ?? (b.CostPerChick ?? 0m) * b.NumberOfBirds,
                        // AmountPaid is no longer forced to zero (migration 326).
                        // Zeroing it was how this used to avoid inventing an expense
                        // for a purchase that happened months ago — at the cost of
                        // making every historical batch look wholly unpaid, and of
                        // being undone the first time anyone edited it through the
                        // ordinary page. IsHistorical now carries that decision, and
                        // carries it in the database, so what the farm really paid
                        // can be recorded and what it still owes comes out right.
                        AmountPaid = b.AmountPaid ?? 0m,
                        IsHistorical = b.IsHistorical,
                        SupplierType = b.SupplierType ?? string.Empty,
                        SupplierId = b.SupplierId,
                        PoultryCashAccountId = b.PoultryCashAccountId,
                        DollarConversionRate = b.DollarConversionRate,
                        OrderPlacementDate = b.OrderPlacementDate,
                        EstimatedArrivalDate = b.EstimatedArrivalDate,
                        Notes = b.Notes,
                    };

                    stage = $"creating batch \"{model.BatchCode}\"";
                    using var cmd = MainFlockBatchService.BuildInsertCommand(conn, tx, model);
                    batchIdByKey[key] = Convert.ToInt32(await cmd.ExecuteScalarAsync());
                    result.BatchesCreated++;
                    await TrackAsync("Batch", batchIdByKey[key]);
                }

                // ---- 2. Houses --------------------------------------------
                var houseIdByKey = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                foreach (var h in request.Houses ?? new List<FarmSetupHouseInput>())
                {
                    var key = FarmSetupValidator.Normalize(h.Key);
                    if (h.ExistingHouseId.HasValue)
                    {
                        houseIdByKey[key] = h.ExistingHouseId.Value;
                        result.HousesReused++;
                        continue;
                    }

                    stage = $"creating pen \"{FarmSetupValidator.Normalize(h.HouseName)}\"";
                    using var cmd = HouseService.BuildInsertCommand(
                        conn, tx, request.UserId, request.FarmId,
                        FarmSetupValidator.Normalize(h.HouseName), h.Capacity,
                        string.IsNullOrWhiteSpace(h.Location) ? null : h.Location!.Trim());
                    houseIdByKey[key] = Convert.ToInt32(await cmd.ExecuteScalarAsync());
                    result.HousesCreated++;
                    await TrackAsync("House", houseIdByKey[key]);
                }

                // ---- 3. Flocks, then 4. their opening positions ------------
                foreach (var f in request.Flocks)
                {
                    var batchId = batchIdByKey[FarmSetupValidator.Normalize(f.BatchKey)];
                    var houseId = houseIdByKey[FarmSetupValidator.Normalize(f.HouseKey)];

                    var estimated = f.StartDate is null;
                    var startDate = f.StartDate
                        ?? FarmSetupValidator.DeriveStartDate(effectiveBusinessDate, f.CurrentAgeInWeeks ?? 0);

                    var flock = new FlockModel
                    {
                        UserId = request.UserId,
                        FarmId = request.FarmId,
                        BatchId = batchId,
                        HouseId = houseId,
                        Name = FarmSetupValidator.Normalize(f.Name),
                        // The flock's own breed when it gave one, otherwise its
                        // batch's — the same prefill the single Add Flock form does.
                        Breed = string.IsNullOrWhiteSpace(f.Breed)
                            ? ResolveBreed(request, f)
                            : FarmSetupValidator.Normalize(f.Breed),
                        StartDate = startDate,
                        // THE line that fixes the bug: the flock starts with what is
                        // standing in the pen today, not with what was placed months
                        // ago. No production record is needed to get here.
                        Quantity = f.CurrentLiveBirds,
                        Active = true,
                        // Onboarded birds are standing in the pen, so arrived is the
                        // default. A NEW purchase can be allocated before it lands,
                        // which is what the ordinary Add Flock switch is for.
                        HasArrived = f.HasArrived ?? true,
                        Notes = f.Notes,
                    };

                    // 413: the same poster the Flocks page uses for an existing
                    // flock -- flock at its live birds, opening position, and one
                    // opening ledger movement that names this batch and flock.
                    stage = $"creating flock \"{flock.Name}\" and its opening position";
                    var (mortality, sold, culled, transferred, _) = FarmSetupValidator.Breakdown(f);
                    var posted = await OpeningFlockPoster.PostAsync(conn, tx, flock,
                        new ExistingFlockHistory
                        {
                            OriginallyPlaced = f.OriginallyPlaced,
                            CurrentLiveBirds = f.CurrentLiveBirds,
                            HistoryKnown = f.HistoryKnown,
                            HistoricalMortality = mortality,
                            HistoricalSold = sold,
                            HistoricalCulled = culled,
                            HistoricalTransferred = transferred,
                            Notes = f.Notes,
                        },
                        effectiveBusinessDate, estimated, source, request.UserId);
                    result.FlocksCreated++;
                    result.OpeningPositionsCreated++;
                    await TrackAsync("Flock", posted.FlockId);
                    result.OpeningLedgerMovements += posted.LedgerRows;

                    result.OriginallyPlaced += f.OriginallyPlaced;
                    result.OpeningLiveBirds += f.CurrentLiveBirds;
                    result.HistoricalReduction += FarmSetupValidator.HistoricalReduction(f);
                }

                // ---- 4b. Batch reconciliation (413) -------------------------
                // Birds a batch bought that never went into a pen. AFTER the flocks,
                // because the batch's unplaced pool is what is left once they are
                // placed. Same function as the Batch page; inside this commit, so a
                // farm can never be created with half its batch explained.
                foreach (var r in request.BatchReconciliations ?? new List<FarmSetupBatchReconciliationInput>())
                {
                    var key = FarmSetupValidator.Normalize(r.BatchKey);
                    if (!batchIdByKey.TryGetValue(key, out var reconBatchId)) continue;
                    var removed = r.Removed();
                    if (removed == 0 && r.StillUnallocatedLive == 0 && (r.Lines ?? new()).All(l => l.Quantity == 0)) continue;

                    stage = $"reconciling the birds of batch {key} that never went into a pen";
                    using var reconCmd = BirdReconciliationService.BuildPostCommand(conn, tx, new BatchReconciliationRequest
                    {
                        FarmId = request.FarmId,
                        BatchId = reconBatchId,
                        AsOfDate = effectiveBusinessDate.Date,
                        Lines = r.Lines ?? new List<BatchReconciliationLine>(),
                        StillUnallocatedLive = r.StillUnallocatedLive,
                        Notes = r.Notes,
                        Source = source,
                        CreatedBy = request.UserId,
                    });
                    var reconJson = await reconCmd.ExecuteScalarAsync() as string;
                    result.BatchReconciliationsPosted++;
                    if (!string.IsNullOrEmpty(reconJson))
                    {
                        using var doc = System.Text.Json.JsonDocument.Parse(reconJson);
                        if (doc.RootElement.TryGetProperty("reconciliationId", out var rid) && rid.TryGetInt32(out var reconId))
                            await TrackAsync("Reconciliation", reconId);
                    }
                    result.BatchBirdsReconciled += removed;
                }

                // ---- 5. Mark it done --------------------------------------
                stage = "marking the setup complete";
                using (var completeCmd = new NpgsqlCommand(
                    "SELECT * FROM sppoultryfarmsetup_complete(" +
                    "p_farmid => @FarmId::text, p_setupmode => @SetupMode::text, " +
                    "p_completedbusinessdate => @BusinessDate::date, p_completedby => @CompletedBy::text, " +
                    "p_batchcount => @BatchCount::int, p_housecount => @HouseCount::int, " +
                    "p_flockcount => @FlockCount::int, p_originallyplaced => @OriginallyPlaced::int, " +
                    "p_openinglivebirds => @OpeningLive::int, p_historicalreduction => @Reduction::int, " +
                    "p_notes => @Notes::text)", conn, tx))
                {
                    completeCmd.Parameters.AddWithValue("@FarmId", request.FarmId);
                    completeCmd.Parameters.AddWithValue("@SetupMode", string.IsNullOrWhiteSpace(request.SetupMode) ? "ExistingFarm" : request.SetupMode);
                    completeCmd.Parameters.AddWithValue("@BusinessDate", effectiveBusinessDate.Date);
                    completeCmd.Parameters.AddWithValue("@CompletedBy", request.UserId);
                    completeCmd.Parameters.AddWithValue("@BatchCount", result.BatchesCreated);
                    completeCmd.Parameters.AddWithValue("@HouseCount", result.HousesCreated);
                    completeCmd.Parameters.AddWithValue("@FlockCount", result.FlocksCreated);
                    completeCmd.Parameters.AddWithValue("@OriginallyPlaced", result.OriginallyPlaced);
                    completeCmd.Parameters.AddWithValue("@OpeningLive", result.OpeningLiveBirds);
                    completeCmd.Parameters.AddWithValue("@Reduction", result.HistoricalReduction);
                    completeCmd.Parameters.AddWithValue("@Notes", (object?)request.Notes ?? DBNull.Value);
                    await completeCmd.ExecuteNonQueryAsync();
                }

                // The draft has become the farm. Dropped inside the SAME commit, so
                // there is never a moment where the setup exists and something still
                // offers to resume it.
                stage = "discarding the saved draft";
                await DeleteDraftAsync(request.FarmId, conn, tx);

                await tx.CommitAsync();
            }
            catch (PostgresException pg)
            {
                try { await tx.RollbackAsync(); } catch { /* connection already gone */ }
                // Re-thrown with the step attached. The database says WHAT went
                // wrong; only we know WHICH of twenty statements asked.
                throw new FarmSetupStageException(stage, pg);
            }
            catch
            {
                // Disposing an uncommitted transaction rolls it back anyway; doing it
                // explicitly releases the company's setup lock before the exception
                // unwinds. Either the whole farm exists or none of it does — a half
                // onboarded farm is worse than none, because nothing tells you which
                // half.
                try { await tx.RollbackAsync(); } catch { /* connection already gone */ }
                throw;
            }

            result.Success = true;
            result.Message =
                $"{result.FlocksCreated} flock{(result.FlocksCreated == 1 ? "" : "s")} created with " +
                $"{result.OpeningLiveBirds:N0} live birds. " +
                (result.HistoricalReduction > 0
                    ? $"{result.HistoricalReduction:N0} birds were recorded as an opening historical reduction, not as today's mortality."
                    : "No historical reduction to record.");

            return result;
        }

        /// <summary>
        /// A flock's breed comes from its batch, the same prefill the single Add
        /// Flock form does. Falls back to empty rather than guessing.
        /// </summary>
        private static string ResolveBreed(FarmSetupRequest request, FarmSetupFlockInput flock)
        {
            var batch = (request.Batches ?? new List<FarmSetupBatchInput>())
                .FirstOrDefault(b => string.Equals(
                    FarmSetupValidator.Normalize(b.Key),
                    FarmSetupValidator.Normalize(flock.BatchKey),
                    StringComparison.OrdinalIgnoreCase));
            return FarmSetupValidator.Normalize(batch?.Breed);
        }

        // ------------------------------------------------------------------
        // Corrections
        // ------------------------------------------------------------------

        public async Task<bool> CorrectOpeningPositionAsync(OpeningFlockPositionCorrection correction)
        {
            var difference = Math.Max(0, correction.OriginallyPlaced - correction.OpeningLiveBirds);
            var mortality = correction.HistoryKnown ? correction.HistoricalMortality : 0;
            var sold = correction.HistoryKnown ? correction.HistoricalSold : 0;
            var culled = correction.HistoryKnown ? correction.HistoricalCulled : 0;
            var transferred = correction.HistoryKnown ? correction.HistoricalTransferred : 0;
            var other = Math.Max(0, difference - (mortality + sold + culled + transferred));

            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            using var tx = await conn.BeginTransactionAsync();
            try
            {
                using (var cmd = new NpgsqlCommand(
                    "SELECT * FROM sppoultryopeningposition_correct(" +
                    "p_farmid => @FarmId::text, p_flockid => @FlockId::int, " +
                    "p_originallyplaced => @OriginallyPlaced::int, p_openinglivebirds => @OpeningLive::int, " +
                    "p_historicalmortality => @Mortality::int, p_historicalsold => @Sold::int, " +
                    "p_historicalculled => @Culled::int, p_historicaltransferred => @Transferred::int, " +
                    "p_otheradjustment => @Other::int, p_historyknown => @HistoryKnown::boolean, " +
                    "p_notes => @Notes::text, p_correctedby => @CorrectedBy::text)", conn, tx))
                {
                    cmd.Parameters.AddWithValue("@FarmId", correction.FarmId);
                    cmd.Parameters.AddWithValue("@FlockId", correction.FlockId);
                    cmd.Parameters.AddWithValue("@OriginallyPlaced", correction.OriginallyPlaced);
                    cmd.Parameters.AddWithValue("@OpeningLive", correction.OpeningLiveBirds);
                    cmd.Parameters.AddWithValue("@Mortality", mortality);
                    cmd.Parameters.AddWithValue("@Sold", sold);
                    cmd.Parameters.AddWithValue("@Culled", culled);
                    cmd.Parameters.AddWithValue("@Transferred", transferred);
                    cmd.Parameters.AddWithValue("@Other", other);
                    cmd.Parameters.AddWithValue("@HistoryKnown", correction.HistoryKnown);
                    cmd.Parameters.AddWithValue("@Notes", (object?)correction.Notes ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@CorrectedBy", correction.UserId);

                    var id = await cmd.ExecuteScalarAsync();
                    if (id is null || id == DBNull.Value)
                    {
                        await tx.RollbackAsync();
                        return false;
                    }

                    // Restating day one restates what the ledger was told about it.
                    // A pure RECLASSIFICATION (the same reduction, now broken down)
                    // leaves the size unchanged, so the append-only post computes a
                    // delta of zero and writes nothing — which is exactly right: the
                    // birds did not move, only their explanation did.
                    //
                    // The movement keeps the opening position's ORIGINAL effective
                    // date. A correction is a restatement of that day, not a new event
                    // on the day someone noticed, and re-dating it would shift the
                    // opening position into a period it was never part of.
                    using var ledgerCmd = new NpgsqlCommand(
                        "SELECT * FROM sppoultryopeningbirdstock_post(" +
                        "p_farmid => @FarmId::text, p_openingpositionid => @OpeningId::int, " +
                        "p_reduction => @Reduction::int, " +
                        "p_effectivedate => (SELECT o.effectivebusinessdate FROM poultryopeningflockposition o " +
                        "WHERE o.openingpositionid = @OpeningId::int AND o.farmid = @FarmId::text), " +
                        "p_note => @Note::text, p_createdby => @CreatedBy::text)", conn, tx);
                    ledgerCmd.Parameters.AddWithValue("@FarmId", correction.FarmId);
                    ledgerCmd.Parameters.AddWithValue("@OpeningId", Convert.ToInt32(id));
                    ledgerCmd.Parameters.AddWithValue("@Reduction", difference);
                    ledgerCmd.Parameters.AddWithValue("@Note",
                        $"Opening historical reduction restated (flock {correction.FlockId})");
                    ledgerCmd.Parameters.AddWithValue("@CreatedBy", correction.UserId);
                    await ledgerCmd.ExecuteNonQueryAsync();
                }

                // The flock's own quantity is the opening live birds, so restating
                // one has to restate the other or the two disagree about day one.
                // Safe only because the caller has already established that this
                // flock has no production records — with any, the quantity is no
                // longer the current count and moving it would rewrite history.
                var flock = _flockService.GetFlockById(correction.FlockId, correction.UserId, correction.FarmId);
                // 413: a flock adjusted before its first record carries those
                // adjustments in its quantity too; restating day one keeps them.
                int laterAdjustments;
                using (var adjCmd = new NpgsqlCommand(
                    "SELECT fnflock_quantityadjustments(p_farmid => @FarmId::text, p_flockid => @FlockId::int)", conn, tx))
                {
                    adjCmd.Parameters.AddWithValue("@FarmId", correction.FarmId);
                    adjCmd.Parameters.AddWithValue("@FlockId", correction.FlockId);
                    laterAdjustments = Convert.ToInt32(await adjCmd.ExecuteScalarAsync());
                }
                var targetQuantity = correction.OpeningLiveBirds + laterAdjustments;
                if (flock is not null && flock.Quantity != targetQuantity)
                {
                    flock.Quantity = targetQuantity;
                    flock.UserId = correction.UserId;
                    flock.FarmId = correction.FarmId;
                    using var updateCmd = new NpgsqlCommand(
                        "SELECT * FROM spflock_update(p_flockid => @FlockId::int, p_name => @Name::text, p_breed => @Breed::text, p_startdate => @StartDate::timestamp, p_quantity => @Quantity::int, p_active => @Active::boolean, p_houseid => @HouseId::int, p_inactivationreason => @InactivationReason::text, p_otherreason => @OtherReason::text, p_userid => @UserId::text, p_farmid => @FarmId::text, p_batchid => @BatchId::int, p_notes => @Notes::text, p_hasarrived => @HasArrived::boolean)",
                        conn, tx);
                    updateCmd.Parameters.AddWithValue("@FlockId", flock.FlockId);
                    updateCmd.Parameters.AddWithValue("@Name", flock.Name);
                    updateCmd.Parameters.AddWithValue("@Breed", flock.Breed);
                    updateCmd.Parameters.AddWithValue("@StartDate", flock.StartDate);
                    updateCmd.Parameters.AddWithValue("@Quantity", flock.Quantity);
                    updateCmd.Parameters.AddWithValue("@Active", flock.Active);
                    updateCmd.Parameters.AddWithValue("@HouseId", (object?)flock.HouseId ?? DBNull.Value);
                    updateCmd.Parameters.AddWithValue("@InactivationReason", (object?)flock.InactivationReason ?? DBNull.Value);
                    updateCmd.Parameters.AddWithValue("@OtherReason", (object?)flock.OtherReason ?? DBNull.Value);
                    updateCmd.Parameters.AddWithValue("@UserId", flock.UserId);
                    updateCmd.Parameters.AddWithValue("@FarmId", flock.FarmId);
                    updateCmd.Parameters.AddWithValue("@BatchId", flock.BatchId);
                    updateCmd.Parameters.AddWithValue("@Notes", (object?)flock.Notes ?? DBNull.Value);
                    updateCmd.Parameters.AddWithValue("@HasArrived", flock.HasArrived);
                    await updateCmd.ExecuteNonQueryAsync();
                }

                await tx.CommitAsync();
                return true;
            }
            catch
            {
                try { await tx.RollbackAsync(); } catch { /* connection already gone */ }
                throw;
            }
        }
    }
}
