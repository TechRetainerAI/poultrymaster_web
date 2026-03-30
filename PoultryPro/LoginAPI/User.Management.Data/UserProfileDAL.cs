using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Threading.Tasks;
using User.Management.Data.Models;

namespace User.Management.Data
{
    public class UserProfileDAL : IUserProfileDAL
    {
        private readonly string _connectionString;

        public UserProfileDAL(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<bool> CreateUserAsync(ApplicationUser user)
        {
            try
            {
                using (SqlConnection connection = new SqlConnection(_connectionString))
                using (SqlCommand cmd = connection.CreateCommand())
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandText = "sp_CreateUser";

                    cmd.Parameters.AddWithValue("@Id", user.Id);
                    cmd.Parameters.AddWithValue("@UserName", user.UserName);
                    cmd.Parameters.AddWithValue("@NormalizedUserName", user.NormalizedUserName);
                    cmd.Parameters.AddWithValue("@Email", (object)user.Email ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@NormalizedEmail", (object)user.NormalizedEmail ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@PasswordHash", (object)user.PasswordHash ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@FirstName", (object)user.FirstName ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@LastName", (object)user.LastName ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@PhoneNumber", (object)user.PhoneNumber ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@FarmId", (object)user.FarmId ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@FarmName", (object)user.FarmName ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@IsStaff", user.IsStaff);
                    cmd.Parameters.AddWithValue("@IsSubscriber", user.IsSubscriber);
                    cmd.Parameters.AddWithValue("@EmailConfirmed", user.EmailConfirmed);
                    cmd.Parameters.AddWithValue("@PhoneNumberConfirmed", user.PhoneNumberConfirmed);
                    cmd.Parameters.AddWithValue("@TwoFactorEnabled", user.TwoFactorEnabled);
                    cmd.Parameters.AddWithValue("@SecurityStamp", (object)user.SecurityStamp ?? Guid.NewGuid().ToString());
                    cmd.Parameters.AddWithValue("@ConcurrencyStamp", (object)user.ConcurrencyStamp ?? Guid.NewGuid().ToString());
                    cmd.Parameters.AddWithValue("@LockoutEnabled", user.LockoutEnabled);
                    cmd.Parameters.AddWithValue("@AccessFailedCount", user.AccessFailedCount);

                    await connection.OpenAsync();
                    await cmd.ExecuteNonQueryAsync();
                    return true;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error in CreateUserAsync: {ex.Message}");
                return false;
            }
        }



        public async Task<bool> DeleteUserByIdAsync(string userId)
        {
            try
            {
                using (SqlConnection connection = new SqlConnection(_connectionString))
                using (SqlCommand cmd = connection.CreateCommand())
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandText = "sp_DeleteUserById";
                    cmd.Parameters.AddWithValue("@UserId", userId);

                    await connection.OpenAsync();
                    return await cmd.ExecuteNonQueryAsync() > 0;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error in DeleteUserByIdAsync: {ex.Message}");
                return false;
            }
        }

        public async Task<ApplicationUser> FindByIdAsync(string userId)
        {
            try
            {
                using (SqlConnection connection = new SqlConnection(_connectionString))
                using (SqlCommand cmd = connection.CreateCommand())
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandText = "sp_GetUserById";
                    cmd.Parameters.AddWithValue("@UserId", userId);

                    await connection.OpenAsync();
                    using (SqlDataReader reader = await cmd.ExecuteReaderAsync())
                    {
                        if (await reader.ReadAsync())
                        {
                            return MapReaderToUser(reader);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error in FindByIdAsync: {ex.Message}");
            }
            return null;
        }

        public async Task<ApplicationUser> FindByNameAsync(string normalizedUserName)
        {
            try
            {
                using (SqlConnection connection = new SqlConnection(_connectionString))
                using (SqlCommand cmd = connection.CreateCommand())
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandText = "sp_GetUserByName";
                    cmd.Parameters.AddWithValue("@NormalizedUserName", normalizedUserName);

                    await connection.OpenAsync();
                    using (SqlDataReader reader = await cmd.ExecuteReaderAsync())
                    {
                        if (await reader.ReadAsync())
                        {
                            return MapReaderToUser(reader);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error in FindByNameAsync: {ex.Message}");
            }
            return null;
        }

        public async Task<ApplicationUser> UpdateUserAsync(ApplicationUser user)
        {
            try
            {
                using (SqlConnection connection = new SqlConnection(_connectionString))
                using (SqlCommand cmd = connection.CreateCommand())
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.CommandText = "sp_UpdateUser";

                    cmd.Parameters.AddWithValue("@Id", user.Id);
                    cmd.Parameters.AddWithValue("@UserName", user.UserName);
                    cmd.Parameters.AddWithValue("@NormalizedUserName", user.NormalizedUserName);
                    cmd.Parameters.AddWithValue("@Email", (object)user.Email ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@PasswordHash", (object)user.PasswordHash ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@FirstName", (object)user.FirstName ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@LastName", (object)user.LastName ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@PhoneNumber", (object)user.PhoneNumber ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@IsSubscriber", user.IsSubscriber);

                    await connection.OpenAsync();
                    var result = await cmd.ExecuteNonQueryAsync();
                    return result > 0 ? user : null;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error in UpdateUserAsync: {ex.Message}");
                return null;
            }
        }


        private ApplicationUser MapReaderToUser(SqlDataReader reader)
        {
            return new ApplicationUser
            {
                Id = reader["Id"].ToString(),
                UserName = reader["UserName"].ToString(),
                NormalizedUserName = reader["NormalizedUserName"].ToString(),
                Email = reader["Email"] == DBNull.Value ? null : reader["Email"].ToString(),
                PasswordHash = reader["PasswordHash"] == DBNull.Value ? null : reader["PasswordHash"].ToString(),
                FirstName = reader["FirstName"] == DBNull.Value ? null : reader["FirstName"].ToString(),
                LastName = reader["LastName"] == DBNull.Value ? null : reader["LastName"].ToString(),
                PhoneNumber = reader["PhoneNumber"] == DBNull.Value ? null : reader["PhoneNumber"].ToString(),
                IsSubscriber = reader["IsSubscriber"] == DBNull.Value ? false : Convert.ToBoolean(reader["IsSubscriber"])
            };
        }

    }
}
