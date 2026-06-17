
using System;
using System.Collections.Generic;
using System.Data;
using Microsoft.Data.SqlClient;
using System.Linq;
using CsvHelper;
using CsvHelper.Configuration;
using System.Globalization;
using System.Xml.Linq;
using User.Management.Data.Models;

namespace User.Management.Data
{
    public class SubscriptionDAL : ISubscriptionDAL
    {
        private readonly string _connectionString;

        public SubscriptionDAL(string connectionString)
        {
            _connectionString = connectionString;
        }



        public List<Plan> GetPlans()
        {
            var result = new List<Plan>();

            using (SqlConnection connection = new SqlConnection(_connectionString))
            {
                connection.Open();
                using (SqlCommand cmd = connection.CreateCommand())
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandText = "GetPlans";                           // Replace with the actual procedure name

                    using (SqlDataReader reader = cmd.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            Plan plan = new Plan
                            {
                                PlanId = Convert.ToInt32(reader["PlanId"]),
                                ProductId = Convert.ToInt32(reader["ProductId"]),
                                PriceId = reader["PriceId"].ToString() ?? string.Empty,
                                Name = reader["Name"].ToString() ?? string.Empty,
                                Price = reader["Price"].ToString() ?? string.Empty,
                                Features = reader["Features"].ToString() ?? string.Empty,
                                TransactionLimit = Convert.ToInt32(reader["TransactionLimit"])
                            };

                            result.Add(plan);
                        }
                    }
                }
            }

            return result;
        }

        

        public Subscriber? GetSubscriberByCustomerId(string customerId)
        {
            Subscriber? subscriber = null;
            try
            {
                using (SqlConnection connection = new SqlConnection(_connectionString))
                {
                    connection.Open();
                    using (SqlCommand cmd = connection.CreateCommand())
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.CommandText = "GetSubscriberByCustomerId"; // Name of the stored procedure

                        // Add parameter for CustomerId
                        cmd.Parameters.AddWithValue("@CustomerId", customerId);

                        using (SqlDataReader reader = cmd.ExecuteReader())
                        {
                            if (reader.Read())
                            {
                                subscriber = new Subscriber
                                {
                                    Id = Convert.ToInt32(reader["Id"]),
                                    SubscriberId = reader["SubscriberId"].ToString() ?? string.Empty,
                                    CustomerId = reader["CustomerId"].ToString() ?? string.Empty,
                                    Email = reader["Email"] == DBNull.Value ? string.Empty : reader["Email"].ToString() ?? string.Empty,
                                    CurrentPeriodStart = Convert.ToDateTime(reader["CurrentPeriodStart"]),
                                    CurrentPeriodEnd = Convert.ToDateTime(reader["CurrentPeriodEnd"]),
                                    Status = reader["Status"].ToString() ?? string.Empty,
                                    CanceledAt = reader["CanceledAt"] == DBNull.Value ? null : (DateTime?)reader["CanceledAt"],
                                    Created = Convert.ToDateTime(reader["Created"]),
                                    EndedAt = reader["EndedAt"] == DBNull.Value ? null : (DateTime?)reader["EndedAt"],
                                    LatestInvoiceId = reader["LatestInvoiceId"].ToString() ?? string.Empty,
                                    StartDate = Convert.ToDateTime(reader["StartDate"]),
                                    TrialEnd = reader["TrialEnd"] == DBNull.Value ? null : (DateTime?)reader["TrialEnd"],
                                    TrialStart = reader["TrialStart"] == DBNull.Value ? null : (DateTime?)reader["TrialStart"],
                                    PlanId = reader["PlanId"] == DBNull.Value ? string.Empty : reader["PlanId"].ToString() ?? string.Empty,
                                    PlanName = reader["PlanName"] == DBNull.Value ? string.Empty : reader["PlanName"].ToString() ?? string.Empty,
                                    PlanAmount = reader["PlanAmount"] == DBNull.Value ? 0 :  Convert.ToDecimal(reader["PlanAmount"]),
                                    // Add other properties as needed
                                };
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                // Handle the exception as needed
                Console.WriteLine($"An error occurred while fetching subscriber: {ex.Message}");
            }

            return subscriber;
        }

        public async Task<bool> CreateFarmAsync(Farm farm)
        {
            // sp_CreateFarm (migration 053) returns the inserted row; treat
            // "no row returned" as failure so the caller's compensating
            // DeleteAsync runs and we never leak an AspNetUsers row whose
            // FarmId points at a Farms row that doesn't actually exist.
            // The original "return true if no exception" silently produced
            // 29 orphan users between this SP being deployed and 053.
            try
            {
                using (SqlConnection connection = new SqlConnection(_connectionString))
                using (SqlCommand cmd = connection.CreateCommand())
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandText = "sp_CreateFarm";

                    cmd.Parameters.AddWithValue("@FarmId", farm.FarmId);
                    cmd.Parameters.AddWithValue("@Name", farm.Name);
                    cmd.Parameters.AddWithValue("@Type", farm.Type);
                    cmd.Parameters.AddWithValue("@Email", farm.Email);
                    cmd.Parameters.AddWithValue("@PhoneNumber", (object)farm.PhoneNumber ?? DBNull.Value);

                    await connection.OpenAsync();
                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        var inserted = await reader.ReadAsync();
                        if (!inserted)
                        {
                            Console.WriteLine($"[CreateFarmAsync] sp_CreateFarm returned no row for FarmId={farm.FarmId}, Name={farm.Name}");
                            return false;
                        }
                    }
                    return true;
                }
            }
            catch (SqlException sqlEx)
            {
                // Surface the SQL error number + message so Cloud Run logs
                // show "Cannot insert NULL into column 'Email'" instead of a
                // generic 500.
                Console.WriteLine($"[CreateFarmAsync] SqlException {sqlEx.Number}/{sqlEx.State}: {sqlEx.Message}");
                return false;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[CreateFarmAsync] {ex.GetType().Name}: {ex.Message}");
                return false;
            }
        }

        public async Task<List<Farm>> GetFarmsAsync()
        {
            var farms = new List<Farm>();
            try
            {
                using (SqlConnection connection = new SqlConnection(_connectionString))
                using (SqlCommand cmd = connection.CreateCommand())
                {
                    cmd.CommandType = CommandType.Text;
                    cmd.CommandText = @"SELECT FarmId, Name, Email, Type, PhoneNumber, CreatedAt FROM [dbo].[Farms]";

                    await connection.OpenAsync();
                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        while (await reader.ReadAsync())
                        {
                            farms.Add(new Farm
                            {
                                FarmId = reader["FarmId"].ToString() ?? string.Empty,
                                Name = reader["Name"].ToString() ?? string.Empty,
                                Email = reader["Email"] == DBNull.Value ? string.Empty : reader["Email"].ToString() ?? string.Empty,
                                Type = reader["Type"] == DBNull.Value ? string.Empty : reader["Type"].ToString() ?? string.Empty,
                                PhoneNumber = reader["PhoneNumber"] == DBNull.Value ? string.Empty : reader["PhoneNumber"].ToString() ?? string.Empty,
                                CreatedAt = reader["CreatedAt"] == DBNull.Value ? DateTime.UtcNow : Convert.ToDateTime(reader["CreatedAt"]) 
                            });
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error in GetFarmsAsync: {ex.Message}");
            }

            return farms;
        }

        public async Task<int> GetFarmCountAsync()
        {
            try
            {
                using (SqlConnection connection = new SqlConnection(_connectionString))
                using (SqlCommand cmd = connection.CreateCommand())
                {
                    cmd.CommandType = CommandType.Text;
                    cmd.CommandText = @"SELECT COUNT(*) FROM [dbo].[Farms]";

                    await connection.OpenAsync();
                    var scalar = await cmd.ExecuteScalarAsync();
                    return Convert.ToInt32(scalar);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error in GetFarmCountAsync: {ex.Message}");
                return 0;
            }
        }
    }
}
