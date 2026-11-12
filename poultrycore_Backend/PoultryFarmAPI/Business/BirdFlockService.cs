using PoultryFarmAPIWeb.Models;
using System.Data;
using Npgsql;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Business
{
    public class BirdFlockService : IBirdFlockService
    {
        private readonly string _connectionString;
        private readonly IMainFlockBatchService _mainFlockBatchService;

        public BirdFlockService(string connectionString, IMainFlockBatchService mainFlockBatchService)
        {
            if (string.IsNullOrWhiteSpace(connectionString))
            {
                throw new ArgumentException(
                    "Database connection string is missing. On Google Cloud Run set the environment variable ConnectionStrings__PoultryConn (two underscores) to your SQL Server connection string for the Farm database.",
                    nameof(connectionString));
            }

            _connectionString = connectionString;
            _mainFlockBatchService = mainFlockBatchService;
        }

        public async Task<int> CreateExistingFlock(FlockModel flock, ExistingFlockHistory history, DateTime asOfDate,
                                                   int batchBirds, string source)
        {
            flock.FlockType = NormalizeFlockType(flock.FlockType);
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            using var tx = await conn.BeginTransactionAsync();
            try
            {
                // Same key as AllocateBatchToFlocks and every bird adjustment.
                using (var lockCmd = new NpgsqlCommand("SELECT pg_advisory_xact_lock(hashtext(@Key))", conn, tx))
                {
                    lockCmd.Parameters.AddWithValue("@Key", $"flock-alloc:{flock.FarmId}:{flock.BatchId}");
                    await lockCmd.ExecuteNonQueryAsync();
                }
                int consumed;
                using (var cmd = new NpgsqlCommand(
                    "SELECT spflock_getconsumedforbatch(p_batchid => @BatchId::int, p_farmid => @FarmId::text, p_flockidtoexclude => NULL)", conn, tx))
                {
                    cmd.Parameters.AddWithValue("@BatchId", flock.BatchId);
                    cmd.Parameters.AddWithValue("@FarmId", flock.FarmId);
                    consumed = Convert.ToInt32(await cmd.ExecuteScalarAsync());
                }
                var available = Math.Max(0, batchBirds - consumed);
                if (history.OriginallyPlaced > available)
                    throw new FlockAllocationConflictException(batchBirds, consumed, history.OriginallyPlaced);

                var posted = await OpeningFlockPoster.PostAsync(conn, tx, flock, history, asOfDate,
                    startDateEstimated: false, source: source, userId: flock.UserId);
                await tx.CommitAsync();
                return posted.FlockId;
            }
            catch
            {
                try { await tx.RollbackAsync(); } catch { /* connection already gone */ }
                throw;
            }
        }

        public async Task<int> CreateFlock(FlockModel model)
        {
            if (model == null) throw new ArgumentNullException(nameof(model));
            if (string.IsNullOrWhiteSpace(model.Name)) throw new ArgumentException("Name is required", nameof(model.Name));
            if (string.IsNullOrWhiteSpace(model.UserId)) throw new ArgumentException("UserId is required", nameof(model.UserId));
            if (string.IsNullOrWhiteSpace(model.FarmId)) throw new ArgumentException("FarmId is required", nameof(model.FarmId));
            if (model.BatchId <= 0) throw new ArgumentException("BatchId is required and must be greater than 0", nameof(model.BatchId));
            model.FlockType = NormalizeFlockType(model.FlockType);

            try
            {
                using (NpgsqlConnection conn = new NpgsqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (NpgsqlCommand cmd = BuildFlockInsertCommand(conn, null, model))
                    {
                        object result = await cmd.ExecuteScalarAsync();

                        if (result == null || result == DBNull.Value)
                        {
                            throw new Exception("Stored procedure did not return a FlockId");
                        }

                        var flockId = Convert.ToInt32(result);
                        await ApplyFlockTypeAsync(conn, null, flockId, model);
                        return flockId;
                    }
                }
            }
            catch (PostgresException sqlEx)
            {
                Console.WriteLine($"SQL Error in CreateFlock: {sqlEx.Message}");
                Console.WriteLine($"SQL Error SqlState: {sqlEx.SqlState}");
                throw new Exception($"Database error while creating flock: {sqlEx.Message}", sqlEx);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error in CreateFlock: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// The one place the flock insert is written. The single Add Flock form,
        /// the batch allocation tool and the Farm Setup wizard all go through here,
        /// so there is exactly one definition of what creating a flock means -- the
        /// only difference between them is whether a transaction is passed in.
        /// </summary>
        internal static NpgsqlCommand BuildFlockInsertCommand(NpgsqlConnection conn, NpgsqlTransaction? transaction, FlockModel model)
        {
            var cmd = new NpgsqlCommand("SELECT * FROM spflock_insert(p_userid => @UserId::text, p_farmid => @FarmId::text, p_name => @Name::text, p_breed => @Breed::text, p_startdate => @StartDate::timestamp, p_quantity => @Quantity::int, p_batchid => @BatchId::int, p_houseid => @HouseId::int, p_inactivationreason => @InactivationReason::text, p_otherreason => @OtherReason::text, p_notes => @Notes::text, p_hasarrived => @HasArrived::boolean)", conn, transaction);
            cmd.Parameters.AddWithValue("@UserId", model.UserId);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@Name", model.Name);
            cmd.Parameters.AddWithValue("@Breed", model.Breed);
            cmd.Parameters.AddWithValue("@StartDate", model.StartDate);
            cmd.Parameters.AddWithValue("@Quantity", model.Quantity);
            cmd.Parameters.AddWithValue("@BatchId", model.BatchId);
            cmd.Parameters.AddWithValue("@HouseId", (object?)model.HouseId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@InactivationReason", (object?)model.InactivationReason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OtherReason", (object?)model.OtherReason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)model.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@HasArrived", model.HasArrived);
            return cmd;
        }

        /// <summary>
        /// "Layer" / "Broiler" (migration 399), or null for "not sent". Anything
        /// else is refused here, before a row is written, so the type step after
        /// an insert cannot fail on its value and leave a half-made flock.
        /// </summary>
        internal static string? NormalizeFlockType(string? raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return null;
            var t = raw.Trim();
            if (string.Equals(t, "Layer", StringComparison.OrdinalIgnoreCase)) return "Layer";
            if (string.Equals(t, "Broiler", StringComparison.OrdinalIgnoreCase)) return "Broiler";
            throw new ArgumentException("Flock type must be Layer or Broiler.", nameof(FlockModel.FlockType));
        }

        /// <summary>
        /// Runs after every flock insert, on the same connection and transaction.
        /// spflock_insert knows nothing of the type: when the caller sends none,
        /// the insert trigger has already given the flock its default (broiler
        /// breed, else the company's business type), so there is nothing to do.
        /// </summary>
        internal static async Task ApplyFlockTypeAsync(NpgsqlConnection conn, NpgsqlTransaction? transaction, int flockId, FlockModel model)
        {
            var type = NormalizeFlockType(model.FlockType);
            if (type == null) return;
            using var cmd = new NpgsqlCommand("SELECT spflock_settype(p_flockid => @FlockId::int, p_farmid => @FarmId::text, p_flocktype => @FlockType::text, p_userid => @UserId::text)", conn, transaction);
            cmd.Parameters.AddWithValue("@FlockId", flockId);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@FlockType", type);
            cmd.Parameters.AddWithValue("@UserId", (object?)model.UserId ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        /// <summary>
        /// Birds a batch has given out, written once so the public reader and the
        /// in-transaction re-check cannot drift apart. Same stored function either
        /// way.
        ///
        /// <para><b>Measured on the PLACED basis</b> (migration 325). Summing flock
        /// quantities alone undercounts a batch onboarded through Initial Farm
        /// Setup, because since 319 such a flock carries its opening LIVE birds —
        /// 919 of the 1,000 placed. The batch would then look like it had 81 spare,
        /// and this is the guard that decides whether someone may allocate them.
        /// spflock_getconsumedforbatch adds the opening historical reduction back,
        /// so the batch is measured the way its NumberOfBirds means it.</para>
        ///
        /// <para>userId is carried for call-site symmetry only; the stored function
        /// scopes by farm, exactly as its predecessor did — the userid filter there
        /// has been commented out since it was written.</para>
        /// </summary>
        private static NpgsqlCommand BuildBatchTotalCommand(
            NpgsqlConnection conn, NpgsqlTransaction? transaction, int batchId, string userId, string farmId, int? flockIdToExclude)
        {
            var cmd = new NpgsqlCommand("SELECT * FROM spflock_getconsumedforbatch(p_batchid => @BatchId::int, p_farmid => @FarmId::text, p_flockidtoexclude => @FlockIdToExclude::int)", conn, transaction);
            cmd.Parameters.AddWithValue("@BatchId", batchId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FlockIdToExclude", (object?)flockIdToExclude ?? DBNull.Value);
            return cmd;
        }

        public async Task<List<FlockModel>> AllocateBatchToFlocks(
            string userId, string farmId, int batchId, int batchBirds, IReadOnlyList<FlockModel> flocks)
        {
            if (flocks == null || flocks.Count == 0) return new List<FlockModel>();

            foreach (var f in flocks) f.FlockType = NormalizeFlockType(f.FlockType);
            var requested = flocks.Sum(f => f.Quantity);
            var createdIds = new List<int>();

            using (var conn = new NpgsqlConnection(_connectionString))
            {
                await conn.OpenAsync();
                using var tx = await conn.BeginTransactionAsync();
                try
                {
                    // Serialise allocators of THIS batch. Two people dividing the
                    // same 4,000 birds at the same moment would otherwise both read
                    // "4,000 free" and both succeed, leaving 5,000 allocated out of
                    // 4,000. An advisory lock keyed on the batch is the cheapest
                    // correct answer here: it needs no schema knowledge, touches no
                    // rows, blocks nobody working on a different batch, and Postgres
                    // releases it at commit or rollback whatever happens.
                    using (var lockCmd = new NpgsqlCommand("SELECT pg_advisory_xact_lock(hashtext(@Key))", conn, tx))
                    {
                        lockCmd.Parameters.AddWithValue("@Key", $"flock-alloc:{farmId}:{batchId}");
                        await lockCmd.ExecuteNonQueryAsync();
                    }

                    // Now -- and only now -- is the allocated total trustworthy.
                    int alreadyAllocated;
                    using (var totalCmd = BuildBatchTotalCommand(conn, tx, batchId, userId, farmId, null))
                    {
                        var result = await totalCmd.ExecuteScalarAsync();
                        alreadyAllocated = result == null || result == DBNull.Value ? 0 : Convert.ToInt32(result);
                    }

                    if (alreadyAllocated + requested > batchBirds)
                    {
                        throw new FlockAllocationConflictException(batchBirds, alreadyAllocated, requested);
                    }

                    foreach (var flock in flocks)
                    {
                        using var cmd = BuildFlockInsertCommand(conn, tx, flock);
                        var result = await cmd.ExecuteScalarAsync();
                        if (result == null || result == DBNull.Value)
                        {
                            throw new Exception("Stored procedure did not return a FlockId");
                        }
                        var newId = Convert.ToInt32(result);
                        await ApplyFlockTypeAsync(conn, tx, newId, flock);
                        createdIds.Add(newId);
                    }

                    await tx.CommitAsync();
                }
                catch
                {
                    // Disposing an uncommitted transaction rolls it back anyway;
                    // doing it explicitly releases the batch lock before the
                    // exception unwinds, so the next allocator is not left waiting.
                    try { await tx.RollbackAsync(); } catch { /* connection already gone */ }
                    throw;
                }
            }

            // Re-read through the normal farm-scoped reader rather than echoing the
            // input back, so the caller gets the rows as the database stored them.
            var ids = new HashSet<int>(createdIds);
            return GetAllFlocks(userId, farmId).Where(f => ids.Contains(f.FlockId)).ToList();
        }

        public async Task<string?> GetFlockEditContext(int flockId, string farmId)
        {
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                await conn.OpenAsync();
                using var cmd = new NpgsqlCommand(
                    "SELECT sppoultryflock_editcontext(p_farmid => @FarmId::text, p_flockid => @FlockId::int)::text", conn);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@FlockId", flockId);
                var v = await cmd.ExecuteScalarAsync();
                return v is string s ? s : null;
            }
            catch (PostgresException pg) when (pg.SqlState == "42883")
            {
                return null;   // 414 not applied
            }
        }

        public async Task UpdateFlock(FlockModel model)
        {
            if (model == null) throw new ArgumentNullException(nameof(model));
            if (string.IsNullOrWhiteSpace(model.Name)) throw new ArgumentException("Name is required", nameof(model.Name));
            if (string.IsNullOrWhiteSpace(model.UserId)) throw new ArgumentException("UserId is required", nameof(model.UserId));
            if (string.IsNullOrWhiteSpace(model.FarmId)) throw new ArgumentException("FarmId is required", nameof(model.FarmId));
            model.FlockType = NormalizeFlockType(model.FlockType);

            using (NpgsqlConnection conn = new NpgsqlConnection(_connectionString))
            using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM spflock_update(p_flockid => @FlockId::int, p_name => @Name::text, p_breed => @Breed::text, p_startdate => @StartDate::timestamp, p_quantity => @Quantity::int, p_active => @Active::boolean, p_houseid => @HouseId::int, p_inactivationreason => @InactivationReason::text, p_otherreason => @OtherReason::text, p_userid => @UserId::text, p_farmid => @FarmId::text, p_batchid => @BatchId::int, p_notes => @Notes::text, p_hasarrived => @HasArrived::boolean)", conn))
            {
                cmd.Parameters.AddWithValue("@FlockId", model.FlockId);
                cmd.Parameters.AddWithValue("@Name", model.Name);
                cmd.Parameters.AddWithValue("@Breed", model.Breed);
                cmd.Parameters.AddWithValue("@StartDate", model.StartDate);
                cmd.Parameters.AddWithValue("@Quantity", model.Quantity);
                cmd.Parameters.AddWithValue("@Active", model.Active);
                cmd.Parameters.AddWithValue("@HouseId", (object?)model.HouseId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@InactivationReason", (object?)model.InactivationReason ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@OtherReason", (object?)model.OtherReason ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@BatchId", (object)model.BatchId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Notes", (object?)model.Notes ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@HasArrived", model.HasArrived);

                await conn.OpenAsync();
                using var tx = await conn.BeginTransactionAsync();
                cmd.Transaction = tx;
                await cmd.ExecuteNonQueryAsync();
                // A flock moved to another batch takes its own bird movements with
                // it (metadata only -- no quantity changes), so the ledger never
                // names the old batch for birds that now belong to the new one.
                using (var retag = new NpgsqlCommand(
                    "UPDATE poultrystocktransactions SET batchid = @BatchId " +
                    "WHERE farmid = @FarmId AND flockid = @FlockId AND COALESCE(birdscope, 'Flock') = 'Flock' AND batchid IS DISTINCT FROM @BatchId; " +
                    "UPDATE poultrybirdadjustments SET batchid = @BatchId " +
                    "WHERE farmid = @FarmId AND flockid = @FlockId AND scope = 'Flock' AND batchid IS DISTINCT FROM @BatchId;", conn, tx))
                {
                    retag.Parameters.AddWithValue("@BatchId", model.BatchId);
                    retag.Parameters.AddWithValue("@FarmId", model.FarmId);
                    retag.Parameters.AddWithValue("@FlockId", model.FlockId);
                    try { await retag.ExecuteNonQueryAsync(); }
                    catch (PostgresException pg) when (pg.SqlState == "42703") { /* pre-413 schema: no scope columns */ }
                }
                // 399: null = the form did not send a type -- leave it alone, so
                // the auto-activate and other partial updates never retype a flock.
                await ApplyFlockTypeAsync(conn, tx, model.FlockId, model);
                await tx.CommitAsync();
            }
        }

        public FlockModel GetFlockById(int flockId, string userId, string farmId)
        {
            FlockModel flock = null;
            using (NpgsqlConnection conn = new NpgsqlConnection(_connectionString))
            using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM spflock_getbyid(p_flockid => @FlockId::int, p_farmid => @FarmId::text)", conn))
            {
                cmd.Parameters.AddWithValue("@FlockId", flockId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                conn.Open();
                using (NpgsqlDataReader reader = cmd.ExecuteReader())
                {
                    if (reader.Read())
                    {
                        flock = new FlockModel
                        {
                            // 301: the time tables show beside the business date.
                            CreatedAt = reader.OptionalDateTime("CreatedAt"),
                            FlockId = Convert.ToInt32(reader["FlockId"]),
                            Name = reader.IsDBNull(reader.GetOrdinal("Name")) ? string.Empty : reader.GetString(reader.GetOrdinal("Name")),
                            Breed = reader.IsDBNull(reader.GetOrdinal("Breed")) ? string.Empty : reader.GetString(reader.GetOrdinal("Breed")),
                            StartDate = reader.GetDateTime(reader.GetOrdinal("StartDate")),
                            Quantity = reader.GetInt32(reader.GetOrdinal("Quantity")),
                            Active = reader.GetBoolean(reader.GetOrdinal("Active")),
                            HouseId = reader.IsDBNull(reader.GetOrdinal("HouseId")) ? (int?)null : reader.GetInt32(reader.GetOrdinal("HouseId")),
                            UserId = reader.IsDBNull(reader.GetOrdinal("UserId")) ? string.Empty : reader.GetString(reader.GetOrdinal("UserId")),
                            FarmId = reader.IsDBNull(reader.GetOrdinal("FarmId")) ? string.Empty : reader.GetString(reader.GetOrdinal("FarmId")),
                            InactivationReason = reader.IsDBNull(reader.GetOrdinal("InactivationReason")) ? null : reader.GetString(reader.GetOrdinal("InactivationReason")),
                            OtherReason = reader.IsDBNull(reader.GetOrdinal("OtherReason")) ? null : reader.GetString(reader.GetOrdinal("OtherReason")),
                            BatchId = (int)(reader.IsDBNull(reader.GetOrdinal("BatchId")) ? (int?)null : reader.GetInt32(reader.GetOrdinal("BatchId"))),
                            Notes = reader.IsDBNull(reader.GetOrdinal("Notes")) ? null : reader.GetString(reader.GetOrdinal("Notes")),
                            BatchName = reader.IsDBNull(reader.GetOrdinal("BatchName")) ? null : reader.GetString(reader.GetOrdinal("BatchName")),
                            HasArrived = ReadHasArrived(reader),
                            // 338: tolerant reads -- absent until the migration runs.
                            ClosedDate = reader.OptionalDateTime("ClosedDate"),
                            ClosedAt = reader.OptionalDateTime("ClosedAt"),
                            ClosedBy = reader.OptionalString("ClosedBy"),
                            CloseReason = reader.OptionalString("CloseReason"),
                            CloseoutId = reader.OptionalInt32("CloseoutId"),
                            // 399: absent until the migration runs -> Layer.
                            FlockType = reader.OptionalString("FlockType") ?? "Layer",
                        };
                    }
                }
            }
            return flock;
        }

        private static bool ReadHasArrived(NpgsqlDataReader reader)
        {
            for (int i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), "HasArrived", StringComparison.OrdinalIgnoreCase))
                {
                    return !reader.IsDBNull(i) && reader.GetBoolean(i);
                }
            }
            return false;
        }

        public List<FlockModel> GetAllFlocks(string userId, string farmId)
        {
            List<FlockModel> flocks = new List<FlockModel>();
            using (NpgsqlConnection conn = new NpgsqlConnection(_connectionString))
            using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM spflock_getall(p_farmid => @FarmId::text)", conn))
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                conn.Open();
                using (NpgsqlDataReader reader = cmd.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        var flock = new FlockModel
                        {
                            // 301: the time tables show beside the business date.
                            CreatedAt = reader.OptionalDateTime("CreatedAt"),
                            FlockId = Convert.ToInt32(reader["FlockId"]),
                            Name = reader.IsDBNull(reader.GetOrdinal("Name")) ? string.Empty : reader.GetString(reader.GetOrdinal("Name")),
                            Breed = reader.IsDBNull(reader.GetOrdinal("Breed")) ? string.Empty : reader.GetString(reader.GetOrdinal("Breed")),
                            StartDate = reader.GetDateTime(reader.GetOrdinal("StartDate")),
                            Quantity = reader.GetInt32(reader.GetOrdinal("Quantity")),
                            Active = reader.IsDBNull(reader.GetOrdinal("Active")) ? true : reader.GetBoolean(reader.GetOrdinal("Active")),
                            HouseId = reader.IsDBNull(reader.GetOrdinal("HouseId")) ? (int?)null : reader.GetInt32(reader.GetOrdinal("HouseId")),
                            UserId = reader.IsDBNull(reader.GetOrdinal("UserId")) ? string.Empty : reader.GetString(reader.GetOrdinal("UserId")),
                            FarmId = reader.IsDBNull(reader.GetOrdinal("FarmId")) ? string.Empty : reader.GetString(reader.GetOrdinal("FarmId")),
                            InactivationReason = reader.IsDBNull(reader.GetOrdinal("InactivationReason")) ? null : reader.GetString(reader.GetOrdinal("InactivationReason")),
                            OtherReason = reader.IsDBNull(reader.GetOrdinal("OtherReason")) ? null : reader.GetString(reader.GetOrdinal("OtherReason")),
                            BatchId = (int)(reader.IsDBNull(reader.GetOrdinal("BatchId")) ? (int?)null : reader.GetInt32(reader.GetOrdinal("BatchId"))),
                            Notes = reader.IsDBNull(reader.GetOrdinal("Notes")) ? null : reader.GetString(reader.GetOrdinal("Notes")),
                            BatchName = reader.IsDBNull(reader.GetOrdinal("BatchName")) ? null : reader.GetString(reader.GetOrdinal("BatchName")),
                            HasArrived = ReadHasArrived(reader),
                            // 338: tolerant reads -- absent until the migration runs.
                            ClosedDate = reader.OptionalDateTime("ClosedDate"),
                            ClosedAt = reader.OptionalDateTime("ClosedAt"),
                            ClosedBy = reader.OptionalString("ClosedBy"),
                            CloseReason = reader.OptionalString("CloseReason"),
                            CloseoutId = reader.OptionalInt32("CloseoutId"),
                            // 399: absent until the migration runs -> Layer.
                            FlockType = reader.OptionalString("FlockType") ?? "Layer",
                        };
                        flocks.Add(flock);
                    }
                }
            }
            return flocks;
        }

        public async Task<int> GetBirdsConsumedFromBatch(int batchId, string userId, string farmId, int? flockIdToExclude = null)
        {
            int totalQuantity = 0;
            using (NpgsqlConnection conn = new NpgsqlConnection(_connectionString))
            {
                await conn.OpenAsync();
                using var cmd = BuildBatchTotalCommand(conn, null, batchId, userId, farmId, flockIdToExclude);
                object result = await cmd.ExecuteScalarAsync();
                if (result != null && result != DBNull.Value)
                {
                    totalQuantity = Convert.ToInt32(result);
                }
            }
            return totalQuantity;
        }

        public async Task<List<FlockPositionRow>> GetFlockPositions(string farmId)
        {
            var list = new List<FlockPositionRow>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryflock_positions(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            int I(string c) => r.IsDBNull(r.GetOrdinal(c)) ? 0 : r.GetInt32(r.GetOrdinal(c));
            while (await r.ReadAsync())
            {
                list.Add(new FlockPositionRow
                {
                    FlockId = I("flockid"),
                    BatchId = r.IsDBNull(r.GetOrdinal("batchid")) ? null : r.GetInt32(r.GetOrdinal("batchid")),
                    IsClosed = r.GetBoolean(r.GetOrdinal("isclosed")),
                    IsDeleted = r.GetBoolean(r.GetOrdinal("isdeleted")),
                    HasOpeningPosition = r.GetBoolean(r.GetOrdinal("hasopeningposition")),
                    HistoryKnown = r.GetBoolean(r.GetOrdinal("historyknown")),
                    OriginallyPlaced = I("originallyplaced"),
                    OpeningMortality = I("openingmortality"),
                    OpeningSold = I("openingsold"),
                    OpeningCulled = I("openingculled"),
                    OpeningTransferred = I("openingtransferred"),
                    OpeningOther = I("openingother"),
                    OpeningLiveBirds = I("openinglivebirds"),
                    RecordedMortality = I("recordedmortality"),
                    ProductionRecordCount = I("productionrecordcount"),
                    LastCountedBirds = I("lastcountedbirds"),
                    LastCountDate = r.IsDBNull(r.GetOrdinal("lastcountdate")) ? null : r.GetDateTime(r.GetOrdinal("lastcountdate")),
                    Correction = I("correction"),
                    BirdsSold = I("birdssold"),
                    BirdsCulled = I("birdsculled"),
                    BirdsTransferred = I("birdstransferred"),
                    CurrentLiveBirds = I("currentlivebirds"),
                    StartedBirds = I("startedbirds"),
                });
            }
            return list;
        }

        public async Task<string?> DeleteFlock(int flockId, string userId, string farmId)
        {
            // 414: the safe delete. spflock_delete only ever soft-deleted (the
            // tr_flock_softdelete trigger) while the lists kept showing the flock,
            // and it never gave the flock's birds back to its batch.
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                await conn.OpenAsync();
                using var tx = await conn.BeginTransactionAsync();
                using var cmd = new NpgsqlCommand(
                    "SELECT sppoultryflock_delete(p_farmid => @FarmId::text, p_flockid => @FlockId::int, p_by => @UserId::text)::text",
                    conn, tx);
                cmd.Parameters.AddWithValue("@FlockId", flockId);
                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                var json = (string?)await cmd.ExecuteScalarAsync();
                await tx.CommitAsync();
                return json;
            }
            catch (PostgresException pg) when (pg.SqlState == "P0001")
            {
                throw new FlockDeleteBlockedException(pg.MessageText);
            }
            catch (PostgresException pg) when (pg.SqlState == "42883")
            {
                // 414 not applied yet: the old path, unchanged.
                Console.WriteLine("sppoultryflock_delete is missing (migration 414); using spflock_delete.");
            }

            try
            {
                using (NpgsqlConnection conn = new NpgsqlConnection(_connectionString))
                {
                    using (NpgsqlCommand cmd = new NpgsqlCommand("SELECT * FROM spflock_delete(p_flockid => @FlockId::int, p_userid => @UserId::text, p_farmid => @FarmId::text)", conn))
                    {
                        cmd.Parameters.AddWithValue("@FlockId", flockId);
                        cmd.Parameters.AddWithValue("@UserId", userId);
                        cmd.Parameters.AddWithValue("@FarmId", farmId);

                        // Log parameters before execution
                        Console.WriteLine($"Executing spFlock_Delete with FlockId={flockId}, UserId={userId}, FarmId={farmId}");

                        await conn.OpenAsync();
                        int rowsAffected = await cmd.ExecuteNonQueryAsync();
                        Console.WriteLine($"spFlock_Delete executed. Rows affected: {rowsAffected}");
                    }
                }
                return null;
            }
            catch (Exception ex)
            {
                // Log the full exception details
                Console.WriteLine($"Error in DeleteFlock: {ex.ToString()}");
                throw new Exception($"Error deleting flock ID={flockId}. See inner exception for details.", ex);
            }
        }
    }
}
