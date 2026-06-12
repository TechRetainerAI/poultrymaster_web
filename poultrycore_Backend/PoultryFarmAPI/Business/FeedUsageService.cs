using PoultryFarmAPIWeb.Models;
using System.Data;
using System.Data.SqlClient;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Business
{
    public class FeedUsageService : IFeedUsageService
    {
        private readonly string _connectionString;

        public FeedUsageService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<int> Insert(FeedUsageModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spFeedUsage_Insert", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@FlockId", model.FlockId);
                cmd.Parameters.AddWithValue("@UsageDate", model.UsageDate);
                cmd.Parameters.AddWithValue("@FeedType", model.FeedType);
                cmd.Parameters.AddWithValue("@QuantityKg", model.QuantityKg);

                await conn.OpenAsync();
                var result = await cmd.ExecuteScalarAsync();
                return Convert.ToInt32(result);
            }
            catch (Exception ex)
            {
                throw new Exception("Error inserting FeedUsage record.", ex);
            }
        }

        public async Task Update(FeedUsageModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spFeedUsage_Update", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@FeedUsageId", model.FeedUsageId);
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@FlockId", model.FlockId);
                cmd.Parameters.AddWithValue("@UsageDate", model.UsageDate);
                cmd.Parameters.AddWithValue("@FeedType", model.FeedType);
                cmd.Parameters.AddWithValue("@QuantityKg", model.QuantityKg);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error updating FeedUsage record ID={model.FeedUsageId}.", ex);
            }
        }

        public async Task<FeedUsageModel?> GetById(int feedUsageId, string userId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spFeedUsage_GetById", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@FeedUsageId", feedUsageId);
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();

                if (await reader.ReadAsync())
                {
                    return new FeedUsageModel
                    {
                        FeedUsageId = reader.GetInt32(reader.GetOrdinal("FeedUsageId")),
                        FlockId = reader.GetInt32(reader.GetOrdinal("FlockId")),
                        UsageDate = reader.GetDateTime(reader.GetOrdinal("UsageDate")),
                        FeedType = reader.GetString(reader.GetOrdinal("FeedType")),
                        QuantityKg = reader.GetDecimal(reader.GetOrdinal("QuantityKg")),
                        UserId = reader["UserId"]?.ToString(),
                        FarmId = reader["FarmId"]?.ToString(),
                        Source = HasColumn(reader, "Source") ? reader["Source"]?.ToString() : null,
                        SourceProductionRecordId = HasColumn(reader, "SourceProductionRecordId") && !reader.IsDBNull(reader.GetOrdinal("SourceProductionRecordId")) 
                            ? reader.GetInt32(reader.GetOrdinal("SourceProductionRecordId")) 
                            : null
                    };
                }
                return null;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error retrieving FeedUsage record ID={feedUsageId}.", ex);
            }
        }

        public async Task<List<FeedUsageModel>> GetAll(string userId, string farmId)
        {
            try
            {
                var list = new List<FeedUsageModel>();
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spFeedUsage_GetAll", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var usage = new FeedUsageModel
                    {
                        FeedUsageId = reader.GetInt32(reader.GetOrdinal("FeedUsageId")),
                        FlockId = reader.GetInt32(reader.GetOrdinal("FlockId")),
                        UsageDate = reader.GetDateTime(reader.GetOrdinal("UsageDate")),
                        FeedType = reader.GetString(reader.GetOrdinal("FeedType")),
                        QuantityKg = reader.GetDecimal(reader.GetOrdinal("QuantityKg")),
                        UserId = reader["UserId"]?.ToString(),
                        FarmId = reader["FarmId"]?.ToString(),
                        Source = HasColumn(reader, "Source") ? reader["Source"]?.ToString() : null,
                        SourceProductionRecordId = HasColumn(reader, "SourceProductionRecordId") && !reader.IsDBNull(reader.GetOrdinal("SourceProductionRecordId")) 
                            ? reader.GetInt32(reader.GetOrdinal("SourceProductionRecordId")) 
                            : null
                    };
                    list.Add(usage);
                }
                return list;
            }
            catch (Exception ex)
            {
                throw new Exception("Error retrieving all FeedUsage records.", ex);
            }
        }

        public async Task Delete(int feedUsageId, string userId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spFeedUsage_Delete", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@FeedUsageId", feedUsageId);
                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error deleting FeedUsage record ID={feedUsageId}.", ex);
            }
        }

        /// <summary>
        /// Helper method to check if a column exists in the reader
        /// </summary>
        private static bool HasColumn(SqlDataReader reader, string columnName)
        {
            for (int i = 0; i < reader.FieldCount; i++)
            {
                if (reader.GetName(i).Equals(columnName, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }
    }
}
