using PoultryFarmAPIWeb.Models;
using System.Data;
using System.Data.SqlClient;
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
                using (SqlConnection conn = new SqlConnection(_connectionString))
                using (SqlCommand cmd = new SqlCommand("spFlock_Insert", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@UserId", model.UserId);
                    cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                    cmd.Parameters.AddWithValue("@Name", model.Name);
                    cmd.Parameters.AddWithValue("@Breed", model.Breed);
                    cmd.Parameters.AddWithValue("@StartDate", model.StartDate);
                    cmd.Parameters.AddWithValue("@Quantity", model.Quantity);
                    cmd.Parameters.AddWithValue("@BatchId", model.BatchId);
                    cmd.Parameters.AddWithValue("@HouseId", (object)model.HouseId ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@InactivationReason", (object)model.InactivationReason ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@OtherReason", (object)model.OtherReason ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@Notes", (object)model.Notes ?? DBNull.Value);

                    await conn.OpenAsync();
                    object result = await cmd.ExecuteScalarAsync();
                    
                    if (result == null || result == DBNull.Value)
                    {
                        throw new Exception("Stored procedure did not return a FlockId");
                    }
                    
                    return Convert.ToInt32(result);
                }
            }
            catch (SqlException sqlEx)
            {
                Console.WriteLine($"SQL Error in CreateFlock: {sqlEx.Message}");
                Console.WriteLine($"SQL Error Number: {sqlEx.Number}");
                throw new Exception($"Database error while creating flock: {sqlEx.Message}", sqlEx);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error in CreateFlock: {ex.Message}");
                throw;
            }
        }

        public async Task UpdateFlock(FlockModel model)
        {
            if (model == null) throw new ArgumentNullException(nameof(model));
            if (string.IsNullOrWhiteSpace(model.Name)) throw new ArgumentException("Name is required", nameof(model.Name));
            if (string.IsNullOrWhiteSpace(model.UserId)) throw new ArgumentException("UserId is required", nameof(model.UserId));
            if (string.IsNullOrWhiteSpace(model.FarmId)) throw new ArgumentException("FarmId is required", nameof(model.FarmId));

            using (SqlConnection conn = new SqlConnection(_connectionString))
            using (SqlCommand cmd = new SqlCommand("spFlock_Update", conn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@FlockId", model.FlockId);
                cmd.Parameters.AddWithValue("@Name", model.Name);
                cmd.Parameters.AddWithValue("@Breed", model.Breed);
                cmd.Parameters.AddWithValue("@StartDate", model.StartDate);
                cmd.Parameters.AddWithValue("@Quantity", model.Quantity);
                cmd.Parameters.AddWithValue("@Active", model.Active);
                cmd.Parameters.AddWithValue("@HouseId", (object)model.HouseId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@InactivationReason", (object)model.InactivationReason ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@OtherReason", (object)model.OtherReason ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@BatchId", (object)model.BatchId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Notes", (object)model.Notes ?? DBNull.Value);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
        }

        public FlockModel GetFlockById(int flockId, string userId, string farmId)
        {
            FlockModel flock = null;
            using (SqlConnection conn = new SqlConnection(_connectionString))
            using (SqlCommand cmd = new SqlCommand("spFlock_GetById", conn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@FlockId", flockId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                conn.Open();
                using (SqlDataReader reader = cmd.ExecuteReader())
                {
                    if (reader.Read())
                    {
                        flock = new FlockModel
                        {
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
                            BatchName = reader.IsDBNull(reader.GetOrdinal("BatchName")) ? null : reader.GetString(reader.GetOrdinal("BatchName"))
                        };
                    }
                }
            }
            return flock;
        }

        public List<FlockModel> GetAllFlocks(string userId, string farmId)
        {
            List<FlockModel> flocks = new List<FlockModel>();
            using (SqlConnection conn = new SqlConnection(_connectionString))
            using (SqlCommand cmd = new SqlCommand("spFlock_GetAll", conn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                conn.Open();
                using (SqlDataReader reader = cmd.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        var flock = new FlockModel
                        {
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
                            BatchName = reader.IsDBNull(reader.GetOrdinal("BatchName")) ? null : reader.GetString(reader.GetOrdinal("BatchName"))
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
            using (SqlConnection conn = new SqlConnection(_connectionString))
            using (SqlCommand cmd = new SqlCommand("spFlock_GetTotalQuantityForBatch", conn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@BatchId", batchId);
                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@FlockIdToExclude", (object)flockIdToExclude ?? DBNull.Value);

                await conn.OpenAsync();
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
                using (SqlConnection conn = new SqlConnection(_connectionString))
                {
                    using (SqlCommand cmd = new SqlCommand("spFlock_Delete", conn))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
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
