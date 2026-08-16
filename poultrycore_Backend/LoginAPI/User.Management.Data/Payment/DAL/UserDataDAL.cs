
using System;
using System.Collections.Generic;
using System.Data;
using Npgsql;
using System.Linq;
using System.Threading.Tasks;
//using User.Management.Data.Entities;
using User.Management.Data.Models;

namespace User.Management.Data
{
    public class UserDataDAL : IUserDataDAL
    {
        private readonly string _connectionString;

        public UserDataDAL(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task SaveSubscriberAsync(Subscriber subscriber)
        {
            using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
            {
                await connection.OpenAsync();
                using (NpgsqlCommand cmd = connection.CreateCommand())
                {
                    // TODO(pg): function savesubscriber does not exist in the PostgreSQL
                    // database and has no T-SQL source in the migration dump (legacy
                    // Stripe-era procedure). This call will fail at runtime.
                    cmd.CommandText = @"SELECT * FROM savesubscriber(
                        p_subscriberid => @SubscriberId, p_customerid => @CustomerId, p_status => @Status,
                        p_currentperiodend => @CurrentPeriodEnd, p_currentperiodstart => @CurrentPeriodStart,
                        p_canceledat => @CanceledAt, p_created => @Created, p_endedat => @EndedAt,
                        p_latestinvoiceid => @LatestInvoiceId, p_startdate => @StartDate,
                        p_trialend => @TrialEnd, p_trialstart => @TrialStart)";

                    // Add parameters for each property in your Subscriber class
                    cmd.Parameters.AddWithValue("@SubscriberId", subscriber.SubscriberId);
                    cmd.Parameters.AddWithValue("@CustomerId", subscriber.CustomerId);
                    cmd.Parameters.AddWithValue("@Status", subscriber.Status);
                    cmd.Parameters.AddWithValue("@CurrentPeriodEnd", subscriber.CurrentPeriodEnd);
                    cmd.Parameters.AddWithValue("@CurrentPeriodStart", subscriber.CurrentPeriodStart);
                    cmd.Parameters.AddWithValue("@CanceledAt", subscriber.CanceledAt);
                    cmd.Parameters.AddWithValue("@Created", subscriber.Created);
                    cmd.Parameters.AddWithValue("@EndedAt", subscriber.EndedAt);
                    cmd.Parameters.AddWithValue("@LatestInvoiceId", subscriber.LatestInvoiceId);
                    cmd.Parameters.AddWithValue("@StartDate", subscriber.StartDate);
                    cmd.Parameters.AddWithValue("@TrialEnd", subscriber.TrialEnd);
                    cmd.Parameters.AddWithValue("@TrialStart", subscriber.TrialStart);

                    // Execute the stored procedure asynchronously
                    await cmd.ExecuteNonQueryAsync();
                }
            }
        }




        public async Task DeleteAsync(Subscriber subscription)
        {
            using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
            {
                await connection.OpenAsync();
                using (NpgsqlCommand cmd = connection.CreateCommand())
                {
                    // TODO(pg): function deletesubscriber does not exist in the PostgreSQL
                    // database and has no T-SQL source in the migration dump (legacy
                    // Stripe-era procedure). This call will fail at runtime.
                    cmd.CommandText = "SELECT * FROM deletesubscriber(p_subscriberid => @SubscriberId)";

                    // Add parameters
                    cmd.Parameters.AddWithValue("@SubscriberId", subscription.SubscriberId);

                    // Execute the stored procedure asynchronously
                    await cmd.ExecuteNonQueryAsync();
                }
            }
        }

        public async Task<IEnumerable<Subscriber>> GetAsync()
        {
            List<Subscriber> subscribers = new List<Subscriber>();
            try
            {
                using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
                {
                    await connection.OpenAsync();
                    using (NpgsqlCommand cmd = connection.CreateCommand())
                    {
                        // TODO(pg): function getsubscribers does not exist in the PostgreSQL
                        // database and has no T-SQL source in the migration dump (legacy
                        // Stripe-era procedure). This call will fail at runtime.
                        cmd.CommandText = "SELECT * FROM getsubscribers()";

                        // Execute the stored procedure asynchronously
                        using (NpgsqlDataReader reader = await cmd.ExecuteReaderAsync())
                        {
                            while (await reader.ReadAsync())
                            {
                                Subscriber subscriber = new Subscriber
                                {
                                    Id = reader.GetInt32(reader.GetOrdinal("Id")),
                                    SubscriberId = reader.GetString(reader.GetOrdinal("SubscriberId")),
                                    CustomerId = reader.GetString(reader.GetOrdinal("CustomerId")),
                                    Email = reader.GetString(reader.GetOrdinal("Email")),
                                    CurrentPeriodStart = reader.GetDateTime(reader.GetOrdinal("CurrentPeriodStart")),
                                    CurrentPeriodEnd = reader.GetDateTime(reader.GetOrdinal("CurrentPeriodEnd")),
                                    Status = reader.GetString(reader.GetOrdinal("Status")),
                                    CanceledAt = reader.IsDBNull(reader.GetOrdinal("CanceledAt")) ? null : reader.GetDateTime(reader.GetOrdinal("CanceledAt")),
                                    Created = reader.GetDateTime(reader.GetOrdinal("Created")),
                                    EndedAt = reader.IsDBNull(reader.GetOrdinal("EndedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("EndedAt")),
                                    LatestInvoiceId = reader.GetString(reader.GetOrdinal("LatestInvoiceId")),
                                    StartDate = reader.GetDateTime(reader.GetOrdinal("StartDate")),
                                    TrialEnd = reader.IsDBNull(reader.GetOrdinal("TrialEnd")) ? null : reader.GetDateTime(reader.GetOrdinal("TrialEnd")),
                                    TrialStart = reader.IsDBNull(reader.GetOrdinal("TrialStart")) ? null : reader.GetDateTime(reader.GetOrdinal("TrialStart")),
                                    PlanId = reader.GetString(reader.GetOrdinal("PlanId")),
                                    PlanName = reader.GetString(reader.GetOrdinal("PlanName")),
                                    PlanAmount = reader.GetDecimal(reader.GetOrdinal("PlanAmount")),
                                    // Add other properties as needed
                                };
                                subscribers.Add(subscriber);
                            }
                            return subscribers;
                        }
                    }
                }

            }
            catch (Exception ex)
            {
                // Handle the exception as needed
                Console.WriteLine($"An error occurred while fetching transactions: {ex.Message}");
                return subscribers; // User not found
            }
        }


        public async Task<Subscriber?> GetSubscriberByCustomerId(string customerId)
        {
            Subscriber? subscriber = null;
            try
            {
                using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
                {

                    await connection.OpenAsync();
                    using (NpgsqlCommand cmd = connection.CreateCommand())
                    {
                        // TODO(pg): function getsubscriberbycustomerid does not exist in the
                        // PostgreSQL database and has no T-SQL source in the migration dump
                        // (legacy Stripe-era procedure). This call will fail at runtime.
                        cmd.CommandText = "SELECT * FROM getsubscriberbycustomerid(p_customerid => @CustomerId)";

                        // Add parameter for SubscriberId
                        cmd.Parameters.AddWithValue("@CustomerId", customerId);

                        // Execute the stored procedure asynchronously
                        using (NpgsqlDataReader reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                subscriber = new Subscriber
                                {
                                    Id = reader.GetInt32(reader.GetOrdinal("Id")),
                                    SubscriberId = reader.GetString(reader.GetOrdinal("SubscriberId")),
                                    CustomerId = reader.GetString(reader.GetOrdinal("CustomerId")),
                                    Email = reader.GetString(reader.GetOrdinal("Email")),
                                    CurrentPeriodStart = reader.GetDateTime(reader.GetOrdinal("CurrentPeriodStart")),
                                    CurrentPeriodEnd = reader.GetDateTime(reader.GetOrdinal("CurrentPeriodEnd")),
                                    Status = reader.GetString(reader.GetOrdinal("Status")),
                                    CanceledAt = reader.IsDBNull(reader.GetOrdinal("CanceledAt")) ? null : reader.GetDateTime(reader.GetOrdinal("CanceledAt")),
                                    Created = reader.GetDateTime(reader.GetOrdinal("Created")),
                                    EndedAt = reader.IsDBNull(reader.GetOrdinal("EndedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("EndedAt")),
                                    LatestInvoiceId = reader.GetString(reader.GetOrdinal("LatestInvoiceId")),
                                    StartDate = reader.GetDateTime(reader.GetOrdinal("StartDate")),
                                    TrialEnd = reader.IsDBNull(reader.GetOrdinal("TrialEnd")) ? null : reader.GetDateTime(reader.GetOrdinal("TrialEnd")),
                                    TrialStart = reader.IsDBNull(reader.GetOrdinal("TrialStart")) ? null : reader.GetDateTime(reader.GetOrdinal("TrialStart")),
                                    PlanId = reader.GetString(reader.GetOrdinal("PlanId")),
                                    PlanName = reader.GetString(reader.GetOrdinal("PlanName")),
                                    PlanAmount = reader.GetDecimal(reader.GetOrdinal("PlanAmount")),
                                    // Add other properties as needed
                                };
                            }

                            return subscriber;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                // Handle the exception as needed
                Console.WriteLine($"An error occurred while fetching transactions: {ex.Message}");
                return subscriber; // User not found
            }
        }


        public async Task<Subscriber?> GetSubscriberByIdAsync(string subscriberId)
        {
            Subscriber? subscriber = null;
            try
            {
                using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
                {
                    await connection.OpenAsync();
                    using (NpgsqlCommand cmd = connection.CreateCommand())
                    {
                        // TODO(pg): function getsubscriberbyid does not exist in the PostgreSQL
                        // database and has no T-SQL source in the migration dump (legacy
                        // Stripe-era procedure). This call will fail at runtime.
                        cmd.CommandText = "SELECT * FROM getsubscriberbyid(p_subscriberid => @SubscriberId)";

                        // Add parameter for SubscriberId
                        cmd.Parameters.AddWithValue("@SubscriberId", subscriberId);

                        // Execute the stored procedure asynchronously
                        using (NpgsqlDataReader reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                subscriber = new Subscriber
                                {
                                    Id = reader.GetInt32(reader.GetOrdinal("Id")),
                                    SubscriberId = reader.GetString(reader.GetOrdinal("SubscriberId")),
                                    CustomerId = reader.GetString(reader.GetOrdinal("CustomerId")),
                                    Email = reader.GetString(reader.GetOrdinal("Email")),
                                    CurrentPeriodStart = reader.GetDateTime(reader.GetOrdinal("CurrentPeriodStart")),
                                    CurrentPeriodEnd = reader.GetDateTime(reader.GetOrdinal("CurrentPeriodEnd")),
                                    Status = reader.GetString(reader.GetOrdinal("Status")),
                                    CanceledAt = reader.IsDBNull(reader.GetOrdinal("CanceledAt")) ? null : reader.GetDateTime(reader.GetOrdinal("CanceledAt")),
                                    Created = reader.GetDateTime(reader.GetOrdinal("Created")),
                                    EndedAt = reader.IsDBNull(reader.GetOrdinal("EndedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("EndedAt")),
                                    LatestInvoiceId = reader.GetString(reader.GetOrdinal("LatestInvoiceId")),
                                    StartDate = reader.GetDateTime(reader.GetOrdinal("StartDate")),
                                    TrialEnd = reader.IsDBNull(reader.GetOrdinal("TrialEnd")) ? null : reader.GetDateTime(reader.GetOrdinal("TrialEnd")),
                                    TrialStart = reader.IsDBNull(reader.GetOrdinal("TrialStart")) ? null : reader.GetDateTime(reader.GetOrdinal("TrialStart")),
                                    PlanId = reader.GetString(reader.GetOrdinal("PlanId")),
                                    PlanName = reader.GetString(reader.GetOrdinal("PlanName")),
                                    PlanAmount = reader.GetDecimal(reader.GetOrdinal("PlanAmount")),
                                    // Add other properties as needed
                                };
                            }

                            return subscriber;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                // Handle the exception as needed
                Console.WriteLine($"An error occurred while fetching transactions: {ex.Message}");
                return subscriber; // User not found
            }
        }

        public async Task<Subscriber?> GetSubscriberByCustomerIdAsync(string customerId)
        {
            Subscriber? subscriber = null;
            try
            {
                using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
                {
                    await connection.OpenAsync();
                    using (NpgsqlCommand cmd = connection.CreateCommand())
                    {
                        // TODO(pg): function getsubscriberbycustomerid does not exist in the
                        // PostgreSQL database and has no T-SQL source in the migration dump
                        // (legacy Stripe-era procedure). This call will fail at runtime.
                        cmd.CommandText = "SELECT * FROM getsubscriberbycustomerid(p_customerid => @CustomerId)";

                        // Add parameter for CustomerId
                        cmd.Parameters.AddWithValue("@CustomerId", customerId);

                        using (NpgsqlDataReader reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
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
                                    PlanAmount = reader["PlanAmount"] == DBNull.Value ? 0 : Convert.ToDecimal(reader["PlanAmount"]),
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


        public async Task<Subscriber> UpdateSubscriberAsync(Subscriber subscription)
        {

            using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
            {
                await connection.OpenAsync();
                using (NpgsqlCommand cmd = connection.CreateCommand())
                {
                    // TODO(pg): function updatesubscriber does not exist in the PostgreSQL
                    // database and has no T-SQL source in the migration dump (legacy
                    // Stripe-era procedure). This call will fail at runtime.
                    cmd.CommandText = @"SELECT * FROM updatesubscriber(
                        p_id => @Id, p_subscriberid => @SubscriberId, p_customerid => @CustomerId,
                        p_email => @Email, p_currentperiodstart => @CurrentPeriodStart,
                        p_currentperiodend => @CurrentPeriodEnd, p_status => @Status,
                        p_canceledat => @CanceledAt, p_created => @Created, p_endedat => @EndedAt,
                        p_latestinvoiceid => @LatestInvoiceId, p_startdate => @StartDate,
                        p_trialend => @TrialEnd, p_trialstart => @TrialStart,
                        p_planid => @PlanId, p_planname => @PlanName, p_planamount => @PlanAmount)";

                    // Add parameters for each property in the Subscriber class
                    cmd.Parameters.AddWithValue("@Id", subscription.Id);
                    cmd.Parameters.AddWithValue("@SubscriberId", subscription.SubscriberId);
                    cmd.Parameters.AddWithValue("@CustomerId", subscription.CustomerId);
                    cmd.Parameters.AddWithValue("@Email", subscription.Email);
                    cmd.Parameters.AddWithValue("@CurrentPeriodStart", subscription.CurrentPeriodStart);
                    cmd.Parameters.AddWithValue("@CurrentPeriodEnd", subscription.CurrentPeriodEnd);
                    cmd.Parameters.AddWithValue("@Status", subscription.Status);
                    cmd.Parameters.AddWithValue("@CanceledAt", subscription.CanceledAt);
                    cmd.Parameters.AddWithValue("@Created", subscription.Created);
                    cmd.Parameters.AddWithValue("@EndedAt", subscription.EndedAt);
                    cmd.Parameters.AddWithValue("@LatestInvoiceId", subscription.LatestInvoiceId);
                    cmd.Parameters.AddWithValue("@StartDate", subscription.StartDate);
                    cmd.Parameters.AddWithValue("@TrialEnd", subscription.TrialEnd);
                    cmd.Parameters.AddWithValue("@TrialStart", subscription.TrialStart);
                    cmd.Parameters.AddWithValue("@PlanId", subscription.PlanId);
                    cmd.Parameters.AddWithValue("@PlanName", subscription.PlanName);
                    cmd.Parameters.AddWithValue("@PlanAmount", subscription.PlanAmount);

                    // Execute the stored procedure
                    await cmd.ExecuteNonQueryAsync();
                }
            }

            return subscription;
        }


        public async Task<ApplicationUser?> FindByEmailAsync(string email)
        {
            try
            {
                using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
                {
                    await connection.OpenAsync();
                    using (NpgsqlCommand cmd = connection.CreateCommand())
                    {
                        // TODO(pg): function finduserbyemail does not exist in the PostgreSQL
                        // database and has no T-SQL source in the migration dump (legacy
                        // Stripe-era procedure). This call will fail at runtime.
                        cmd.CommandText = "SELECT * FROM finduserbyemail(p_email => @Email)";

                        // Add parameter for email
                        cmd.Parameters.AddWithValue("@Email", email);

                        // Execute the stored procedure and read the result
                        using (NpgsqlDataReader reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                ApplicationUser user = new ApplicationUser
                                {
                                    Id = reader.GetString(reader.GetOrdinal("Id")),
                                    CustomerId = reader.IsDBNull(reader.GetOrdinal("CustomerId")) ? null : reader.GetString(reader.GetOrdinal("CustomerId")),
                                    FirstName = reader.IsDBNull(reader.GetOrdinal("FirstName")) ? string.Empty : reader.GetString(reader.GetOrdinal("FirstName")),
                                    LastName = reader.IsDBNull(reader.GetOrdinal("LastName")) ? string.Empty : reader.GetString(reader.GetOrdinal("LastName")),
                                    UserName = reader.IsDBNull(reader.GetOrdinal("UserName")) ? null : reader.GetString(reader.GetOrdinal("UserName")),
                                    NormalizedUserName = reader.IsDBNull(reader.GetOrdinal("NormalizedUserName")) ? null : reader.GetString(reader.GetOrdinal("NormalizedUserName")),
                                    Email = reader.IsDBNull(reader.GetOrdinal("Email")) ? null : reader.GetString(reader.GetOrdinal("Email")),
                                    NormalizedEmail = reader.IsDBNull(reader.GetOrdinal("NormalizedEmail")) ? null : reader.GetString(reader.GetOrdinal("NormalizedEmail")),
                                    EmailConfirmed = reader.IsDBNull(reader.GetOrdinal("EmailConfirmed")) ? false : reader.GetBoolean(reader.GetOrdinal("EmailConfirmed")),
                                    PasswordHash = reader.IsDBNull(reader.GetOrdinal("PasswordHash")) ? null : reader.GetString(reader.GetOrdinal("PasswordHash")),
                                    SecurityStamp = reader.IsDBNull(reader.GetOrdinal("SecurityStamp")) ? null : reader.GetString(reader.GetOrdinal("SecurityStamp")),
                                    ConcurrencyStamp = reader.IsDBNull(reader.GetOrdinal("ConcurrencyStamp")) ? null : reader.GetString(reader.GetOrdinal("ConcurrencyStamp")),
                                    PhoneNumber = reader.IsDBNull(reader.GetOrdinal("PhoneNumber")) ? null : reader.GetString(reader.GetOrdinal("PhoneNumber")),
                                    PhoneNumberConfirmed = reader.IsDBNull(reader.GetOrdinal("PhoneNumberConfirmed")) ? false : reader.GetBoolean(reader.GetOrdinal("PhoneNumberConfirmed")),
                                    TwoFactorEnabled = reader.IsDBNull(reader.GetOrdinal("TwoFactorEnabled")) ? false : reader.GetBoolean(reader.GetOrdinal("TwoFactorEnabled")),
                                    LockoutEnd = reader.IsDBNull(reader.GetOrdinal("LockoutEnd")) ? null : (DateTime?)reader.GetDateTime(reader.GetOrdinal("LockoutEnd")),
                                    LockoutEnabled = reader.IsDBNull(reader.GetOrdinal("LockoutEnabled")) ? false : reader.GetBoolean(reader.GetOrdinal("LockoutEnabled")),
                                    AccessFailedCount = reader.IsDBNull(reader.GetOrdinal("AccessFailedCount")) ? 0 : reader.GetInt32(reader.GetOrdinal("AccessFailedCount"))
                                };
                                return user;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                // Handle the exception as needed
                Console.WriteLine($"An error occurred while fetching the user: {ex.Message}");
                return null; // User not found
            }
            return null;
        }


        //06062024
        //public async Task<ApplicationUser> FindByEmailAsync(string email)
        //{
        //    try
        //    {
        //        using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
        //        {
        //            await connection.OpenAsync();
        //            using (NpgsqlCommand cmd = connection.CreateCommand())
        //            {
        //        //                cmd.CommandText = "FindUserByEmail"; // Name of the stored procedure

        //                // Add parameter for email
        //                cmd.Parameters.AddWithValue("@Email", email);

        //                // Execute the stored procedure and read the result
        //                using (NpgsqlDataReader reader = await cmd.ExecuteReaderAsync())
        //                {
        //                    if (await reader.ReadAsync())
        //                    {
        //                        ApplicationUser user = new ApplicationUser
        //                        {
        //                            Id = reader.GetString(reader.GetOrdinal("Id")),
        //                            CustomerId = reader.IsDBNull(reader.GetOrdinal("CustomerId")) ? null : reader.GetString(reader.GetOrdinal("CustomerId")),
        //                            //CustomerId = reader.GetString(reader.GetOrdinal("CustomerId")),
        //                            FirstName = reader.GetString(reader.GetOrdinal("FirstName")),
        //                            LastName = reader.GetString(reader.GetOrdinal("LastName")),
        //                            UserName = reader.GetString(reader.GetOrdinal("UserName")),
        //                            NormalizedUserName = reader.GetString(reader.GetOrdinal("NormalizedUserName")),
        //                            Email = reader.GetString(reader.GetOrdinal("Email")),
        //                            NormalizedEmail = reader.GetString(reader.GetOrdinal("NormalizedEmail")),
        //                            EmailConfirmed = reader.GetBoolean(reader.GetOrdinal("EmailConfirmed")),
        //                            PasswordHash = reader.GetString(reader.GetOrdinal("PasswordHash")),
        //                            SecurityStamp = reader.GetString(reader.GetOrdinal("SecurityStamp")),
        //                            ConcurrencyStamp = reader.GetString(reader.GetOrdinal("ConcurrencyStamp")),
        //                            PhoneNumber = reader.GetString(reader.GetOrdinal("PhoneNumber")),
        //                            PhoneNumberConfirmed = reader.GetBoolean(reader.GetOrdinal("PhoneNumberConfirmed")),
        //                            TwoFactorEnabled = reader.GetBoolean(reader.GetOrdinal("TwoFactorEnabled")),
        //                            LockoutEnd = reader.IsDBNull(reader.GetOrdinal("LockoutEnd")) ? null : (DateTime?)reader.GetDateTime(reader.GetOrdinal("LockoutEnd")),
        //                            LockoutEnabled = reader.GetBoolean(reader.GetOrdinal("LockoutEnabled")),
        //                            AccessFailedCount = reader.GetInt32(reader.GetOrdinal("AccessFailedCount"))
        //                            // Add other properties as needed
        //                        };
        //                        return user;
        //                    }
        //                }
        //            }
        //        }
        //    }
        //    catch (Exception ex)
        //    {
        //        // Handle the exception as needed
        //        Console.WriteLine($"An error occurred while fetching transactions: {ex.Message}");
        //        return null; // User not found
        //    }
        //    return null;
        //}



        public async Task<ApplicationUser> UpdateUserAsync(ApplicationUser user)
        {
            using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
            {
                await connection.OpenAsync();
                using (NpgsqlCommand cmd = connection.CreateCommand())
                {
                    // TODO(pg): function updateuser does not exist in the PostgreSQL database
                    // and has no T-SQL source in the migration dump (legacy Stripe-era
                    // procedure; distinct from sp_updateuser). This call will fail at runtime.
                    cmd.CommandText = @"SELECT * FROM updateuser(
                        p_id => @Id, p_customerid => @CustomerId, p_firstname => @FirstName,
                        p_lastname => @LastName, p_username => @UserName,
                        p_normalizedusername => @NormalizedUserName, p_email => @Email,
                        p_normalizedemail => @NormalizedEmail, p_emailconfirmed => @EmailConfirmed,
                        p_passwordhash => @PasswordHash, p_securitystamp => @SecurityStamp,
                        p_concurrencystamp => @ConcurrencyStamp, p_phonenumber => @PhoneNumber,
                        p_phonenumberconfirmed => @PhoneNumberConfirmed,
                        p_twofactorenabled => @TwoFactorEnabled, p_lockoutenabled => @LockoutEnabled,
                        p_accessfailedcount => @AccessFailedCount)";

                    // Add parameters for user properties
                    cmd.Parameters.AddWithValue("@Id", user.Id);
                    cmd.Parameters.AddWithValue("@CustomerId", user.CustomerId);
                    cmd.Parameters.AddWithValue("@FirstName", user.FirstName);
                    cmd.Parameters.AddWithValue("@LastName", user.LastName);
                    cmd.Parameters.AddWithValue("@UserName", user.UserName);
                    cmd.Parameters.AddWithValue("@NormalizedUserName", user.NormalizedUserName);
                    cmd.Parameters.AddWithValue("@Email", user.Email);
                    cmd.Parameters.AddWithValue("@NormalizedEmail", user.NormalizedEmail);
                    cmd.Parameters.AddWithValue("@EmailConfirmed", user.EmailConfirmed);
                    cmd.Parameters.AddWithValue("@PasswordHash", user.PasswordHash);
                    cmd.Parameters.AddWithValue("@SecurityStamp", user.SecurityStamp);
                    cmd.Parameters.AddWithValue("@ConcurrencyStamp", user.ConcurrencyStamp);
                    cmd.Parameters.AddWithValue("@PhoneNumber", user.PhoneNumber);
                    cmd.Parameters.AddWithValue("@PhoneNumberConfirmed", user.PhoneNumberConfirmed);
                    cmd.Parameters.AddWithValue("@TwoFactorEnabled", user.TwoFactorEnabled);
                    //cmd.Parameters.AddWithValue("@LockoutEnd", user.LockoutEnd);
                    cmd.Parameters.AddWithValue("@LockoutEnabled", user.LockoutEnabled);
                    cmd.Parameters.AddWithValue("@AccessFailedCount", user.AccessFailedCount);

                    // Execute the stored procedure
                    await cmd.ExecuteNonQueryAsync();
                }
            }

            return user;
        }


        public async Task<ApplicationUser> UpdateUserCustomerIdAsync(ApplicationUser user)
        {
            using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
            {
                await connection.OpenAsync();
                using (NpgsqlCommand cmd = connection.CreateCommand())
                {
                    // TODO(pg): function updateusercustomerid does not exist in the PostgreSQL
                    // database and has no T-SQL source in the migration dump (legacy
                    // Stripe-era procedure). This call will fail at runtime.
                    cmd.CommandText = @"SELECT * FROM updateusercustomerid(
                        p_id => @Id, p_customerid => @CustomerId,
                        p_issubscriber => @IsSubscriber, p_email => @Email)";

                    // Add parameters for user properties
                    cmd.Parameters.AddWithValue("@Id", user.Id);
                    cmd.Parameters.AddWithValue("@CustomerId", user.CustomerId);
                    cmd.Parameters.AddWithValue("@IsSubscriber", user.IsSubscriber);
                    cmd.Parameters.AddWithValue("@Email", user.Email);
                   
                    await cmd.ExecuteNonQueryAsync();
                }
            }

            return user;
        }
    }
}
