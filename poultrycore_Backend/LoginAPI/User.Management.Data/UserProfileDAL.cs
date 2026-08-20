using System;
using System.Collections.Generic;
using System.Data;
using Npgsql;
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
                using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
                using (NpgsqlCommand cmd = connection.CreateCommand())
                {
                    cmd.CommandText = @"SELECT * FROM sp_createuser(
                        p_id => @Id::text, p_username => @UserName::text, p_normalizedusername => @NormalizedUserName::text,
                        p_email => @Email::text, p_normalizedemail => @NormalizedEmail::text, p_passwordhash => @PasswordHash::text,
                        p_firstname => @FirstName::text, p_lastname => @LastName::text, p_phonenumber => @PhoneNumber::text,
                        p_farmid => @FarmId::text, p_farmname => @FarmName::text, p_isstaff => @IsStaff::boolean,
                        p_issubscriber => @IsSubscriber::boolean, p_emailconfirmed => @EmailConfirmed::boolean,
                        p_phonenumberconfirmed => @PhoneNumberConfirmed::boolean, p_twofactorenabled => @TwoFactorEnabled::boolean,
                        p_securitystamp => @SecurityStamp::text, p_concurrencystamp => @ConcurrencyStamp::text,
                        p_lockoutenabled => @LockoutEnabled::boolean, p_accessfailedcount => @AccessFailedCount::int)";

                    cmd.Parameters.AddWithValue("@Id", user.Id);
                    cmd.Parameters.AddWithValue("@UserName", user.UserName);
                    cmd.Parameters.AddWithValue("@NormalizedUserName", user.NormalizedUserName);
                    cmd.Parameters.AddWithValue("@Email", (object?)user.Email ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@NormalizedEmail", (object?)user.NormalizedEmail ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@PasswordHash", (object?)user.PasswordHash ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@FirstName", (object?)user.FirstName ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@LastName", (object?)user.LastName ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@PhoneNumber", (object?)user.PhoneNumber ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@FarmId", (object?)user.FarmId ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@FarmName", (object?)user.FarmName ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@IsStaff", user.IsStaff);
                    cmd.Parameters.AddWithValue("@IsSubscriber", user.IsSubscriber);
                    cmd.Parameters.AddWithValue("@EmailConfirmed", user.EmailConfirmed);
                    cmd.Parameters.AddWithValue("@PhoneNumberConfirmed", user.PhoneNumberConfirmed);
                    cmd.Parameters.AddWithValue("@TwoFactorEnabled", user.TwoFactorEnabled);
                    cmd.Parameters.AddWithValue("@SecurityStamp", (object?)user.SecurityStamp ?? Guid.NewGuid().ToString());
                    cmd.Parameters.AddWithValue("@ConcurrencyStamp", (object?)user.ConcurrencyStamp ?? Guid.NewGuid().ToString());
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
                using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
                using (NpgsqlCommand cmd = connection.CreateCommand())
                {
                    cmd.CommandText = "SELECT * FROM sp_deleteuserbyid(p_userid => @UserId::text)";
                    cmd.Parameters.AddWithValue("@UserId", userId);

                    await connection.OpenAsync();
                    // The call is a SELECT, so Npgsql reports -1 rows affected;
                    // the function returns the real count instead.
                    return Convert.ToInt32(await cmd.ExecuteScalarAsync()) > 0;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error in DeleteUserByIdAsync: {ex.Message}");
                return false;
            }
        }

        public async Task<ApplicationUser?> FindByIdAsync(string userId)
        {
            try
            {
                using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
                using (NpgsqlCommand cmd = connection.CreateCommand())
                {
                    cmd.CommandText = "SELECT * FROM sp_getuserbyid(p_userid => @UserId::text)";
                    cmd.Parameters.AddWithValue("@UserId", userId);

                    await connection.OpenAsync();
                    using (NpgsqlDataReader reader = await cmd.ExecuteReaderAsync())
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

        public async Task<ApplicationUser?> FindByNameAsync(string normalizedUserName)
        {
            try
            {
                using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
                using (NpgsqlCommand cmd = connection.CreateCommand())
                {
                    cmd.CommandText = "SELECT * FROM sp_getuserbyname(p_normalizedusername => @NormalizedUserName::text)";
                    cmd.Parameters.AddWithValue("@NormalizedUserName", normalizedUserName);

                    await connection.OpenAsync();
                    using (NpgsqlDataReader reader = await cmd.ExecuteReaderAsync())
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

        public async Task<ApplicationUser?> UpdateUserAsync(ApplicationUser user)
        {
            try
            {
                using (NpgsqlConnection connection = new NpgsqlConnection(_connectionString))
                using (NpgsqlCommand cmd = connection.CreateCommand())
                {
                    cmd.CommandText = @"SELECT * FROM sp_updateuser(
                        p_id => @Id::text, p_username => @UserName::text, p_normalizedusername => @NormalizedUserName::text,
                        p_email => @Email::text, p_passwordhash => @PasswordHash::text, p_firstname => @FirstName::text,
                        p_lastname => @LastName::text, p_phonenumber => @PhoneNumber::text, p_issubscriber => @IsSubscriber::boolean)";

                    cmd.Parameters.AddWithValue("@Id", user.Id);
                    cmd.Parameters.AddWithValue("@UserName", user.UserName);
                    cmd.Parameters.AddWithValue("@NormalizedUserName", user.NormalizedUserName);
                    cmd.Parameters.AddWithValue("@Email", (object?)user.Email ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@PasswordHash", (object?)user.PasswordHash ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@FirstName", (object?)user.FirstName ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@LastName", (object?)user.LastName ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@PhoneNumber", (object?)user.PhoneNumber ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@IsSubscriber", user.IsSubscriber);

                    await connection.OpenAsync();
                    // The call is a SELECT, so Npgsql reports -1 rows affected;
                    // the function returns the real count instead.
                    var result = Convert.ToInt32(await cmd.ExecuteScalarAsync());
                    return result > 0 ? user : null;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error in UpdateUserAsync: {ex.Message}");
                return null;
            }
        }


        private static bool ReaderHasColumn(NpgsqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }

        private static string? ReadOptionalString(NpgsqlDataReader reader, string columnName)
        {
            try
            {
                if (!ReaderHasColumn(reader, columnName)) return null;
                var i = reader.GetOrdinal(columnName);
                return reader.IsDBNull(i) ? null : reader.GetValue(i)?.ToString();
            }
            catch
            {
                return null;
            }
        }

        private static bool ReadOptionalBool(NpgsqlDataReader reader, string columnName, bool defaultValue = false)
        {
            try
            {
                if (!ReaderHasColumn(reader, columnName)) return defaultValue;
                var i = reader.GetOrdinal(columnName);
                if (reader.IsDBNull(i)) return defaultValue;
                return Convert.ToBoolean(reader.GetValue(i));
            }
            catch
            {
                return defaultValue;
            }
        }

        private ApplicationUser MapReaderToUser(NpgsqlDataReader reader)
        {
            return new ApplicationUser
            {
                Id = reader["Id"].ToString() ?? string.Empty,
                UserName = reader["UserName"].ToString(),
                NormalizedUserName = reader["NormalizedUserName"].ToString(),
                Email = reader["Email"] == DBNull.Value ? null : reader["Email"].ToString(),
                PasswordHash = reader["PasswordHash"] == DBNull.Value ? null : reader["PasswordHash"].ToString(),
                FirstName = reader["FirstName"] == DBNull.Value ? string.Empty : reader["FirstName"].ToString() ?? string.Empty,
                LastName = reader["LastName"] == DBNull.Value ? string.Empty : reader["LastName"].ToString() ?? string.Empty,
                PhoneNumber = reader["PhoneNumber"] == DBNull.Value ? null : reader["PhoneNumber"].ToString(),
                IsSubscriber = reader["IsSubscriber"] == DBNull.Value ? false : Convert.ToBoolean(reader["IsSubscriber"]),
                IsStaff = ReadOptionalBool(reader, "IsStaff", false),
                IsAdmin = ReadOptionalBool(reader, "IsAdmin", false),
                FarmId = ReadOptionalString(reader, "FarmId") ?? string.Empty,
                FarmName = ReadOptionalString(reader, "FarmName"),
                AdminTitle = ReadOptionalString(reader, "AdminTitle"),
                FeaturePermissions = ReadOptionalString(reader, "FeaturePermissions"),
                Permissions = ReadOptionalString(reader, "Permissions"),
                CustomerId = ReadOptionalString(reader, "CustomerId"),
            };
        }

    }
}
