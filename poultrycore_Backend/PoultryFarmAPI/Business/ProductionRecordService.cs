using PoultryFarmAPIWeb.Models;
using System.Collections.Concurrent;
using System.Data;
using Microsoft.Data.SqlClient;

namespace PoultryFarmAPIWeb.Business
{
    public class ProductionRecordService : IProductionRecordService
    {
        private readonly string _connectionString;

        /// <summary>Caches whether dbo stored procedures include @EggGrade (migration 003).</summary>
        private static readonly ConcurrentDictionary<string, bool> SpHasEggGradeParamCache = new();
        /// <summary>Caches whether dbo stored procedures include the egg-loss params @MeatyEggs/@SoftEggs/@LostEggs (migration 018). Probing @MeatyEggs is sufficient — they were added together.</summary>
        private static readonly ConcurrentDictionary<string, bool> SpHasEggLossParamsCache = new();
        /// <summary>Caches whether dbo stored procedures include the feed/medication costing params (migration 137). Probing @SpecificFeedUsedId is sufficient — they were added together.</summary>
        private static readonly ConcurrentDictionary<string, bool> SpHasCostingParamsCache = new();

        public ProductionRecordService(string connectionString)
        {
            _connectionString = connectionString;
        }

        private static async Task<bool> ProcedureHasEggGradeParameterAsync(SqlConnection conn, string procedureName)
        {
            if (SpHasEggGradeParamCache.TryGetValue(procedureName, out var cached))
                return cached;

            await using var probe = new SqlCommand(
                @"SELECT 1
                  FROM sys.parameters p
                  INNER JOIN sys.procedures pr ON p.object_id = pr.object_id
                  WHERE SCHEMA_NAME(pr.schema_id) = N'dbo'
                    AND pr.name = @procName
                    AND (p.name = N'EggGrade' OR p.name = N'@EggGrade')",
                conn);
            probe.Parameters.AddWithValue("@procName", procedureName);
            var scalar = await probe.ExecuteScalarAsync();
            var has = scalar != null && scalar != DBNull.Value;
            SpHasEggGradeParamCache[procedureName] = has;
            return has;
        }

        private static async Task<bool> ProcedureHasEggLossParamsAsync(SqlConnection conn, string procedureName)
        {
            if (SpHasEggLossParamsCache.TryGetValue(procedureName, out var cached))
                return cached;

            await using var probe = new SqlCommand(
                @"SELECT 1
                  FROM sys.parameters p
                  INNER JOIN sys.procedures pr ON p.object_id = pr.object_id
                  WHERE SCHEMA_NAME(pr.schema_id) = N'dbo'
                    AND pr.name = @procName
                    AND (p.name = N'MeatyEggs' OR p.name = N'@MeatyEggs')",
                conn);
            probe.Parameters.AddWithValue("@procName", procedureName);
            var scalar = await probe.ExecuteScalarAsync();
            var has = scalar != null && scalar != DBNull.Value;
            SpHasEggLossParamsCache[procedureName] = has;
            return has;
        }

        private static int? GetNullableIntIfPresent(SqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? (int?)null : reader.GetInt32(i);
            }
            return null;
        }

        private static decimal? GetNullableDecimalIfPresent(SqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? (decimal?)null : reader.GetDecimal(i);
            }
            return null;
        }

        /// <summary>Doc §4a-4c feed/medication costing params (migration 137). Probing @SpecificFeedUsedId suffices.</summary>
        private static async Task<bool> ProcedureHasCostingParamsAsync(SqlConnection conn, string procedureName)
        {
            if (SpHasCostingParamsCache.TryGetValue(procedureName, out var cached))
                return cached;

            await using var probe = new SqlCommand(
                @"SELECT 1
                  FROM sys.parameters p
                  INNER JOIN sys.procedures pr ON p.object_id = pr.object_id
                  WHERE SCHEMA_NAME(pr.schema_id) = N'dbo'
                    AND pr.name = @procName
                    AND (p.name = N'SpecificFeedUsedId' OR p.name = N'@SpecificFeedUsedId')",
                conn);
            probe.Parameters.AddWithValue("@procName", procedureName);
            var scalar = await probe.ExecuteScalarAsync();
            var has = scalar != null && scalar != DBNull.Value;
            SpHasCostingParamsCache[procedureName] = has;
            return has;
        }

        /// <summary>Adds the feed/medication costing SP params from the model (used by Insert + Update).</summary>
        private static void AddCostingParameters(SqlCommand cmd, ProductionRecordModel model)
        {
            cmd.Parameters.AddWithValue("@SpecificFeedUsedId", (object?)model.SpecificFeedUsedId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SpecificFeedUsedName", (object?)model.SpecificFeedUsedName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FeedUnitCost", (object?)model.FeedUnitCost ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TotalFeedConsumed", (object?)model.TotalFeedConsumed ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TotalFeedCost", (object?)model.TotalFeedCost ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SpecificMedicationUsedId", (object?)model.SpecificMedicationUsedId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SpecificMedicationUsedName", (object?)model.SpecificMedicationUsedName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MedicationUnitCost", (object?)model.MedicationUnitCost ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TotalMedicationConsumed", (object?)model.TotalMedicationConsumed ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TotalMedicationCost", (object?)model.TotalMedicationCost ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TotalCostOfProduction", (object?)model.TotalCostOfProduction ?? DBNull.Value);
        }

        private static void MapCostingFields(SqlDataReader reader, ProductionRecordModel m)
        {
            m.SpecificFeedUsedId = GetNullableIntIfPresent(reader, "SpecificFeedUsedId");
            m.SpecificFeedUsedName = reader.GetNullableStringIfPresent("SpecificFeedUsedName");
            m.FeedUnitCost = GetNullableDecimalIfPresent(reader, "FeedUnitCost");
            m.TotalFeedConsumed = GetNullableDecimalIfPresent(reader, "TotalFeedConsumed");
            m.TotalFeedCost = GetNullableDecimalIfPresent(reader, "TotalFeedCost");
            m.SpecificMedicationUsedId = GetNullableIntIfPresent(reader, "SpecificMedicationUsedId");
            m.SpecificMedicationUsedName = reader.GetNullableStringIfPresent("SpecificMedicationUsedName");
            m.MedicationUnitCost = GetNullableDecimalIfPresent(reader, "MedicationUnitCost");
            m.TotalMedicationConsumed = GetNullableDecimalIfPresent(reader, "TotalMedicationConsumed");
            m.TotalMedicationCost = GetNullableDecimalIfPresent(reader, "TotalMedicationCost");
            m.TotalCostOfProduction = GetNullableDecimalIfPresent(reader, "TotalCostOfProduction");
        }

        public async Task<int> Insert(ProductionRecordModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spProductionRecord_Insert", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };

                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@CreatedBy", model.CreatedBy);
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@AgeInWeeks", model.AgeInWeeks);
                cmd.Parameters.AddWithValue("@AgeInDays", model.AgeInDays);
                cmd.Parameters.AddWithValue("@Date", model.Date);
                cmd.Parameters.AddWithValue("@NoOfBirds", model.NoOfBirds);
                cmd.Parameters.AddWithValue("@Mortality", model.Mortality);
                cmd.Parameters.AddWithValue("@NoOfBirdsLeft", model.NoOfBirdsLeft);
                cmd.Parameters.AddWithValue("@FeedKg", model.FeedKg);
                cmd.Parameters.AddWithValue("@Medication", (object?)model.Medication ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Production9AM", model.Production9AM);
                cmd.Parameters.AddWithValue("@Production12PM", model.Production12PM);
                cmd.Parameters.AddWithValue("@Production4PM", model.Production4PM);
                cmd.Parameters.AddWithValue("@TotalProduction", model.TotalProduction);
                cmd.Parameters.AddWithValue("@FlockId", (object?)model.FlockId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@BrokenEggs", (object?)model.BrokenEggs ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Notes", (object?)model.Notes ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@EggCount", model.EggCount > 0 ? model.EggCount : model.TotalProduction);

                // Output parameter to get the newly inserted Id
                var newIdParam = new SqlParameter("@NewId", SqlDbType.Int)
                {
                    Direction = ParameterDirection.Output
                };
                cmd.Parameters.Add(newIdParam);

                await conn.OpenAsync();
                if (await ProcedureHasEggGradeParameterAsync(conn, "spProductionRecord_Insert"))
                    cmd.Parameters.AddWithValue("@EggGrade", (object?)model.EggGrade ?? DBNull.Value);
                if (await ProcedureHasEggLossParamsAsync(conn, "spProductionRecord_Insert"))
                {
                    cmd.Parameters.AddWithValue("@MeatyEggs", (object?)model.MeatyEggs ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@SoftEggs", (object?)model.SoftEggs ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@LostEggs", (object?)model.LostEggs ?? DBNull.Value);
                }
                if (await ProcedureHasCostingParamsAsync(conn, "spProductionRecord_Insert"))
                    AddCostingParameters(cmd, model);

                await cmd.ExecuteNonQueryAsync();

                // Get the new Id
                int newId = (int)newIdParam.Value;
                return newId;
            }
            catch (Exception ex)
            {
                // Log the exception as needed
                throw new ApplicationException("An error occurred while inserting the production record.", ex);
            }
        }

        public async Task Update(ProductionRecordModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spProductionRecord_Update", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };

                cmd.Parameters.AddWithValue("@RecordId", model.Id);
                cmd.Parameters.AddWithValue("@UpdatedBy", model.UpdatedBy);
                cmd.Parameters.AddWithValue("@AgeInWeeks", model.AgeInWeeks);
                cmd.Parameters.AddWithValue("@AgeInDays", model.AgeInDays);
                cmd.Parameters.AddWithValue("@Date", model.Date);
                cmd.Parameters.AddWithValue("@NoOfBirds", model.NoOfBirds);
                cmd.Parameters.AddWithValue("@Mortality", model.Mortality);
                cmd.Parameters.AddWithValue("@NoOfBirdsLeft", model.NoOfBirdsLeft);
                cmd.Parameters.AddWithValue("@FeedKg", model.FeedKg);
                cmd.Parameters.AddWithValue("@Medication", model.Medication);
                cmd.Parameters.AddWithValue("@Production9AM", model.Production9AM);
                cmd.Parameters.AddWithValue("@Production12PM", model.Production12PM);
                cmd.Parameters.AddWithValue("@Production4PM", model.Production4PM);
                cmd.Parameters.AddWithValue("@TotalProduction", model.TotalProduction);
                cmd.Parameters.AddWithValue("@FlockId", (object?)model.FlockId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@BrokenEggs", (object?)model.BrokenEggs ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Notes", (object?)model.Notes ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@EggCount", model.EggCount > 0 ? model.EggCount : model.TotalProduction);

                await conn.OpenAsync();
                if (await ProcedureHasEggGradeParameterAsync(conn, "spProductionRecord_Update"))
                    cmd.Parameters.AddWithValue("@EggGrade", (object?)model.EggGrade ?? DBNull.Value);
                if (await ProcedureHasEggLossParamsAsync(conn, "spProductionRecord_Update"))
                {
                    cmd.Parameters.AddWithValue("@MeatyEggs", (object?)model.MeatyEggs ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@SoftEggs", (object?)model.SoftEggs ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@LostEggs", (object?)model.LostEggs ?? DBNull.Value);
                }
                if (await ProcedureHasCostingParamsAsync(conn, "spProductionRecord_Update"))
                    AddCostingParameters(cmd, model);

                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                // Log the exception as needed
                throw new ApplicationException("An error occurred while updating the production record.", ex);
            }
        }

        public async Task<ProductionRecordModel?> GetById(int recordId, string userId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spProductionRecord_GetById", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };

                cmd.Parameters.AddWithValue("@RecordId", recordId);
                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    var totalProd = reader.GetInt32(reader.GetOrdinal("TotalProduction"));
                    var record = new ProductionRecordModel
                    {
                        Id = reader.GetInt32(reader.GetOrdinal("Id")),
                        FarmId = reader.GetString(reader.GetOrdinal("FarmId")),
                        UserId = reader.GetNullableStringIfPresent("UserId") ?? reader.GetString(reader.GetOrdinal("CreatedBy")),
                        CreatedBy = reader.GetString(reader.GetOrdinal("CreatedBy")),
                        UpdatedBy = reader.GetNullableStringIfPresent("UpdatedBy") ?? string.Empty,
                        Medication = reader.GetNullableStringIfPresent("Medication") ?? string.Empty,
                        UpdatedAt = reader.GetNullableDateTimeIfPresent("UpdatedAt"),
                        AgeInWeeks = reader.GetInt32(reader.GetOrdinal("AgeInWeeks")),
                        AgeInDays = reader.GetInt32(reader.GetOrdinal("AgeInDays")),
                        Date = reader.GetDateTime(reader.GetOrdinal("Date")),
                        NoOfBirds = reader.GetInt32(reader.GetOrdinal("NoOfBirds")),
                        Mortality = reader.GetInt32(reader.GetOrdinal("Mortality")),
                        NoOfBirdsLeft = reader.GetInt32(reader.GetOrdinal("NoOfBirdsLeft")),
                        FeedKg = reader.GetDecimal(reader.GetOrdinal("FeedKg")),
                        Production9AM = reader.GetInt32(reader.GetOrdinal("Production9AM")),
                        Production12PM = reader.GetInt32(reader.GetOrdinal("Production12PM")),
                        Production4PM = reader.GetInt32(reader.GetOrdinal("Production4PM")),
                        TotalProduction = totalProd,
                        CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                        FlockId = reader.IsDBNull(reader.GetOrdinal("FlockId")) ? (int?)null : reader.GetInt32(reader.GetOrdinal("FlockId")),
                        BrokenEggs = reader.IsDBNull(reader.GetOrdinal("BrokenEggs")) ? (int?)null : reader.GetInt32(reader.GetOrdinal("BrokenEggs")),
                        Notes = reader.GetNullableStringIfPresent("Notes"),
                        EggCount = reader.IsDBNull(reader.GetOrdinal("EggCount")) ? totalProd : reader.GetInt32(reader.GetOrdinal("EggCount")),
                        EggGrade = reader.GetNullableStringIfPresent("EggGrade"),
                        MeatyEggs = GetNullableIntIfPresent(reader, "MeatyEggs"),
                        SoftEggs = GetNullableIntIfPresent(reader, "SoftEggs"),
                        LostEggs = GetNullableIntIfPresent(reader, "LostEggs")
                    };
                    MapCostingFields(reader, record);
                    return record;
                }

                return null;
            }
            catch (Exception ex)
            {
                // Log the exception as needed
                throw new ApplicationException("An error occurred while retrieving the production record.", ex);
            }
        }

        public async Task<List<ProductionRecordModel>> GetAll(string userId, string farmId)
        {
            var records = new List<ProductionRecordModel>();
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spProductionRecord_GetAll", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };

                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var totalProd = reader.GetInt32(reader.GetOrdinal("TotalProduction"));
                    var rec = new ProductionRecordModel
                    {
                        Id = reader.GetInt32(reader.GetOrdinal("Id")),
                        FarmId = reader.GetString(reader.GetOrdinal("FarmId")),
                        UserId = reader.GetNullableStringIfPresent("UserId") ?? reader.GetString(reader.GetOrdinal("CreatedBy")),
                        CreatedBy = reader.GetString(reader.GetOrdinal("CreatedBy")),
                        UpdatedBy = reader.GetNullableStringIfPresent("UpdatedBy") ?? string.Empty,
                        Medication = reader.GetNullableStringIfPresent("Medication") ?? string.Empty,
                        UpdatedAt = reader.GetNullableDateTimeIfPresent("UpdatedAt"),
                        AgeInWeeks = reader.GetInt32(reader.GetOrdinal("AgeInWeeks")),
                        AgeInDays = reader.GetInt32(reader.GetOrdinal("AgeInDays")),
                        Date = reader.GetDateTime(reader.GetOrdinal("Date")),
                        NoOfBirds = reader.GetInt32(reader.GetOrdinal("NoOfBirds")),
                        Mortality = reader.GetInt32(reader.GetOrdinal("Mortality")),
                        NoOfBirdsLeft = reader.GetInt32(reader.GetOrdinal("NoOfBirdsLeft")),
                        FeedKg = reader.GetDecimal(reader.GetOrdinal("FeedKg")),
                        Production9AM = reader.GetInt32(reader.GetOrdinal("Production9AM")),
                        Production12PM = reader.GetInt32(reader.GetOrdinal("Production12PM")),
                        Production4PM = reader.GetInt32(reader.GetOrdinal("Production4PM")),
                        TotalProduction = totalProd,
                        CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                        FlockId = reader.IsDBNull(reader.GetOrdinal("FlockId")) ? (int?)null : reader.GetInt32(reader.GetOrdinal("FlockId")),
                        BrokenEggs = reader.IsDBNull(reader.GetOrdinal("BrokenEggs")) ? (int?)null : reader.GetInt32(reader.GetOrdinal("BrokenEggs")),
                        Notes = reader.GetNullableStringIfPresent("Notes"),
                        EggCount = reader.IsDBNull(reader.GetOrdinal("EggCount")) ? totalProd : reader.GetInt32(reader.GetOrdinal("EggCount")),
                        EggGrade = reader.GetNullableStringIfPresent("EggGrade"),
                        MeatyEggs = GetNullableIntIfPresent(reader, "MeatyEggs"),
                        SoftEggs = GetNullableIntIfPresent(reader, "SoftEggs"),
                        LostEggs = GetNullableIntIfPresent(reader, "LostEggs")
                    };
                    MapCostingFields(reader, rec);
                    records.Add(rec);
                }
            }
            catch (Exception ex)
            {
                // Log the exception as needed
                throw new ApplicationException("An error occurred while retrieving production records.", ex);
            }

            return records;
        }

        public async Task Delete(int recordId, string userId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spProductionRecord_Delete", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };

                cmd.Parameters.AddWithValue("@RecordId", recordId);
                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                // Log the exception as needed
                throw new ApplicationException("An error occurred while deleting the production record.", ex);
            }
        }
    }

    public static class SqlDataReaderExtensions
    {
        public static string? GetNullableString(this SqlDataReader reader, string columnName)
        {
            int ordinal = reader.GetOrdinal(columnName);
            return reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
        }

        /// <summary>Returns null if the column is not in the result set (older stored procedures before EggGrade).</summary>
        public static string? GetNullableStringIfPresent(this SqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? null : reader.GetString(i);
            }
            return null;
        }

        public static DateTime? GetNullableDateTime(this SqlDataReader reader, string columnName)
        {
            int ordinal = reader.GetOrdinal(columnName);
            return reader.IsDBNull(ordinal) ? (DateTime?)null : reader.GetDateTime(ordinal);
        }

        public static DateTime? GetNullableDateTimeIfPresent(this SqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? (DateTime?)null : reader.GetDateTime(i);
            }
            return null;
        }
    }
}
