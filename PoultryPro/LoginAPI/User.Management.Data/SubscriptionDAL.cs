
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
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
                                PriceId = reader["PriceId"].ToString(),
                                Name = reader["Name"].ToString(),
                                Price = reader["Price"].ToString(),
                                Features = reader["Features"].ToString(),
                                TransactionLimit = Convert.ToInt32(reader["TransactionLimit"])
                            };

                            result.Add(plan);
                        }
                    }
                }
            }

            return result;
        }

        

        public Subscriber GetSubscriberByCustomerId(string customerId)
        {
            Subscriber subscriber = null;
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
                                    SubscriberId = reader["SubscriberId"].ToString(),
                                    CustomerId = reader["CustomerId"].ToString(),
                                    Email = reader["Email"] == DBNull.Value ? null : reader["Email"].ToString(),
                                    CurrentPeriodStart = Convert.ToDateTime(reader["CurrentPeriodStart"]),
                                    CurrentPeriodEnd = Convert.ToDateTime(reader["CurrentPeriodEnd"]),
                                    Status = reader["Status"].ToString(),
                                    CanceledAt = reader["CanceledAt"] == DBNull.Value ? null : (DateTime?)reader["CanceledAt"],
                                    Created = Convert.ToDateTime(reader["Created"]),
                                    EndedAt = reader["EndedAt"] == DBNull.Value ? null : (DateTime?)reader["EndedAt"],
                                    LatestInvoiceId = reader["LatestInvoiceId"].ToString(),
                                    StartDate = Convert.ToDateTime(reader["StartDate"]),
                                    TrialEnd = reader["TrialEnd"] == DBNull.Value ? null : (DateTime?)reader["TrialEnd"],
                                    TrialStart = reader["TrialStart"] == DBNull.Value ? null : (DateTime?)reader["TrialStart"],
                                    PlanId = reader["PlanId"] == DBNull.Value ? null :  reader["PlanId"].ToString(),
                                    PlanName = reader["PlanName"] == DBNull.Value ? null :  reader["PlanName"].ToString(),
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
                    await cmd.ExecuteNonQueryAsync();
                    return true; // 👍 Assume success if no exception thrown
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error in CreateFarmAsync: {ex.Message}");
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
                                FarmId = reader["FarmId"].ToString(),
                                Name = reader["Name"].ToString(),
                                Email = reader["Email"] == DBNull.Value ? null : reader["Email"].ToString(),
                                Type = reader["Type"] == DBNull.Value ? null : reader["Type"].ToString(),
                                PhoneNumber = reader["PhoneNumber"] == DBNull.Value ? null : reader["PhoneNumber"].ToString(),
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
