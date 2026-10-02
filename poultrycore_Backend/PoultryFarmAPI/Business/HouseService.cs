using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class HouseService : IHouseService
    {
        private readonly string _connectionString;
        public HouseService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public List<HouseModel> GetAll(string userId, string farmId)
        {
            var list = new List<HouseModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphouse_getall(p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            conn.Open();
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                list.Add(new HouseModel
                {
                    // 301: the time tables show beside the business date.
                    CreatedAt = reader.OptionalDateTime("CreatedAt"),
                    UserId = reader.GetString(0),
                    FarmId = reader.GetString(1),
                    HouseId = reader.GetInt32(2),
                    HouseName = reader.GetString(3),
                    Capacity = reader.IsDBNull(4) ? null : reader.GetInt32(4),
                    Location = reader.IsDBNull(5) ? null : reader.GetString(5)
                });
            }
            return list;
        }

        public HouseModel? GetById(int id, string userId, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphouse_getbyid(p_houseid => @HouseId::int, p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@HouseId", id);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            conn.Open();
            using var reader = cmd.ExecuteReader();
            if (reader.Read())
            {
                return new HouseModel
                {
                    // 301: the time tables show beside the business date.
                    CreatedAt = reader.OptionalDateTime("CreatedAt"),
                    UserId = reader.GetString(0),
                    FarmId = reader.GetString(1),
                    HouseId = reader.GetInt32(2),
                    HouseName = reader.GetString(3),
                    Capacity = reader.IsDBNull(4) ? null : reader.GetInt32(4),
                    Location = reader.IsDBNull(5) ? null : reader.GetString(5)
                };
            }
            return null;
        }

        /// <summary>
        /// The one place the insert is written. The single "Add House" form, the
        /// bulk house tool and the Farm Setup wizard all go through here, so there
        /// is exactly one definition of what creating a house means -- the only
        /// difference between them is whether a transaction is passed in.
        /// </summary>
        internal static NpgsqlCommand BuildInsertCommand(
            NpgsqlConnection conn,
            NpgsqlTransaction? transaction,
            string userId,
            string farmId,
            string houseName,
            int? capacity,
            string? location)
        {
            var cmd = new NpgsqlCommand("SELECT * FROM sphouse_insert(p_userid => @UserId::text, p_farmid => @FarmId::text, p_housename => @HouseName::text, p_capacity => @Capacity::int, p_location => @Location::text)", conn, transaction);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@HouseName", houseName);
            cmd.Parameters.AddWithValue("@Capacity", (object?)capacity ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Location", (object?)location ?? DBNull.Value);
            return cmd;
        }

        public int Create(HouseModel model)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = BuildInsertCommand(conn, null, model.UserId, model.FarmId, model.HouseName, model.Capacity, model.Location);
            conn.Open();
            var result = cmd.ExecuteScalar();
            return Convert.ToInt32(result);
        }

        /// <summary>
        /// Bulk creation: one connection, one transaction, N calls to the same
        /// stored function <see cref="Create"/> uses. If any row fails -- a
        /// constraint, a bad value, a dropped connection -- the whole batch rolls
        /// back, so a farmer never lands on a half-created set of pens they then
        /// have to reconcile by hand.
        ///
        /// <para>
        /// The company is a parameter, not per row: every house in the batch is
        /// written against the same farmId, which is what makes a cross-company
        /// batch impossible to express rather than merely forbidden.
        /// </para>
        /// </summary>
        public List<HouseModel> CreateBulk(string userId, string farmId, IReadOnlyList<BulkHouseItem> items)
        {
            if (items == null || items.Count == 0) return new List<HouseModel>();

            var createdIds = new List<int>();

            using (var conn = new NpgsqlConnection(_connectionString))
            {
                conn.Open();
                using var tx = conn.BeginTransaction();
                try
                {
                    foreach (var item in items)
                    {
                        using var cmd = BuildInsertCommand(conn, tx, userId, farmId, item.HouseName, item.Capacity, item.Location);
                        createdIds.Add(Convert.ToInt32(cmd.ExecuteScalar()));
                    }
                    tx.Commit();
                }
                catch
                {
                    // Best-effort: the using block disposes (and so rolls back) an
                    // uncommitted transaction anyway, but rolling back explicitly
                    // releases the row locks before the exception unwinds.
                    try { tx.Rollback(); } catch { /* connection already gone */ }
                    throw;
                }
            }

            // Re-read through the normal farm-scoped reader rather than echoing the
            // input back: the caller gets the rows as the database actually stored
            // them, including createddate, exactly like the single-create path does
            // with its GetById.
            var ids = new HashSet<int>(createdIds);
            return GetAll(userId, farmId).Where(h => ids.Contains(h.HouseId)).ToList();
        }

        public void Update(HouseModel model)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphouse_update(p_userid => @UserId::text, p_farmid => @FarmId::text, p_houseid => @HouseId::int, p_housename => @HouseName::text, p_capacity => @Capacity::int, p_location => @Location::text)", conn);
            cmd.Parameters.AddWithValue("@UserId", model.UserId);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@HouseId", model.HouseId);
            cmd.Parameters.AddWithValue("@HouseName", model.HouseName);
            cmd.Parameters.AddWithValue("@Capacity", (object?)model.Capacity ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Location", (object?)model.Location ?? DBNull.Value);
            conn.Open();
            cmd.ExecuteNonQuery();
        }

        public void Delete(int id, string userId, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphouse_delete(p_houseid => @HouseId::int, p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@HouseId", id);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            conn.Open();
            cmd.ExecuteNonQuery();
        }
    }
}
