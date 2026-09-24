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

        public async Task<int> CreateFlock(FlockModel model)
        {
            if (model == null) throw new ArgumentNullException(nameof(model));
            if (string.IsNullOrWhiteSpace(model.Name)) throw new ArgumentException("Name is required", nameof(model.Name));
            if (string.IsNullOrWhiteSpace(model.UserId)) throw new ArgumentException("UserId is required", nameof(model.UserId));
            if (string.IsNullOrWhiteSpace(model.FarmId)) throw new ArgumentException("FarmId is required", nameof(model.FarmId));
            if (model.BatchId <= 0) throw new ArgumentException("BatchId is required and must be greater than 0", nameof(model.BatchId));

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

                        return Convert.ToInt32(result);
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
        /// The batch total, written once so the public reader and the
        /// in-transaction re-check cannot drift apart. Same stored function either
        /// way.
        /// </summary>
        private static NpgsqlCommand BuildBatchTotalCommand(
            NpgsqlConnection conn, NpgsqlTransaction? transaction, int batchId, string userId, string farmId, int? flockIdToExclude)
        {
            var cmd = new NpgsqlCommand("SELECT * FROM spflock_gettotalquantityforbatch(p_batchid => @BatchId::int, p_userid => @UserId::text, p_farmid => @FarmId::text, p_flockidtoexclude => @FlockIdToExclude::int)", conn, transaction);
            cmd.Parameters.AddWithValue("@BatchId", batchId);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FlockIdToExclude", (object?)flockIdToExclude ?? DBNull.Value);
            return cmd;
        }

        public async Task<List<FlockModel>> AllocateBatchToFlocks(
            string userId, string farmId, int batchId, int batchBirds, IReadOnlyList<FlockModel> flocks)
        {
            if (flocks == null || flocks.Count == 0) return new List<FlockModel>();

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
                        createdIds.Add(Convert.ToInt32(result));
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

        public async Task UpdateFlock(FlockModel model)
        {
            if (model == null) throw new ArgumentNullException(nameof(model));
            if (string.IsNullOrWhiteSpace(model.Name)) throw new ArgumentException("Name is required", nameof(model.Name));
            if (string.IsNullOrWhiteSpace(model.UserId)) throw new ArgumentException("UserId is required", nameof(model.UserId));
            if (string.IsNullOrWhiteSpace(model.FarmId)) throw new ArgumentException("FarmId is required", nameof(model.FarmId));

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
                await cmd.ExecuteNonQueryAsync();
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
                            HasArrived = ReadHasArrived(reader)
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
                            HasArrived = ReadHasArrived(reader)
                        };
                        flocks.Add(flock);
                    }
                }
            }
            return flocks;
        }

        public async Task<int> GetTotalFlockQuantityForBatch(int batchId, string userId, string farmId, int? flockIdToExclude = null)
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

        public async Task DeleteFlock(int flockId, string userId, string farmId)
        {
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
