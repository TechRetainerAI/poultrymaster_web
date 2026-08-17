using System;
using System.Collections.Generic;
using System.Data;
using Npgsql;
using System.Threading.Tasks;
using User.Management.Data.Models;

namespace User.Management.Data
{
    public class CompanyDAL : ICompanyDAL
    {
        private readonly string _connectionString;

        public CompanyDAL(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<CompanyResponse> CreateAsync(string farmId, CreateCompanyRequest req, string ownerUserId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                @"SELECT * FROM spcompany_create(p_farmid => @FarmId::text, p_name => @Name::text, p_type => @Type::text,
                                                 p_owneruserid => @OwnerUserId::text, p_email => @Email::text,
                                                 p_phonenumber => @PhoneNumber::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Name", req.Name);
            cmd.Parameters.AddWithValue("@Type", req.Type);
            cmd.Parameters.AddWithValue("@OwnerUserId", ownerUserId);
            cmd.Parameters.AddWithValue("@Email", (object?)req.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)req.PhoneNumber ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync())
                throw new InvalidOperationException("Company create returned no row.");

            return new CompanyResponse
            {
                FarmId      = reader["FarmId"].ToString() ?? string.Empty,
                Name        = reader["Name"].ToString() ?? string.Empty,
                Type        = reader["Type"]?.ToString() ?? "Poultry",
                OwnerUserId = reader["OwnerUserId"] == DBNull.Value ? null : reader["OwnerUserId"].ToString(),
                Email       = reader["Email"]       == DBNull.Value ? null : reader["Email"].ToString(),
                PhoneNumber = reader["PhoneNumber"] == DBNull.Value ? null : reader["PhoneNumber"].ToString(),
                CreatedAt   = reader["CreatedAt"]   == DBNull.Value ? DateTime.UtcNow : Convert.ToDateTime(reader["CreatedAt"]),
                UpdatedAt   = reader["UpdatedAt"]   == DBNull.Value ? null : Convert.ToDateTime(reader["UpdatedAt"]),
                Role        = "Admin",
            };
        }

        public async Task<List<CompanyResponse>> GetByUserIdAsync(string userId)
        {
            var list = new List<CompanyResponse>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spcompany_getbyuserid(p_userid => @UserId::text)", conn);
            cmd.Parameters.AddWithValue("@UserId", userId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(Map(reader));
            return list;
        }

        public async Task<CompanyResponse?> GetByIdAsync(string farmId, string userId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spcompany_getbyid(p_farmid => @FarmId::text, p_userid => @UserId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@UserId", userId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync()) return Map(reader);
            return null;
        }

        public async Task<bool> IsMemberAsync(string userId, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spuserfarm_ismember(p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return result is bool b && b;
        }

        public async Task AddMemberAsync(string userId, string farmId, string role)
        {
            // Idempotent link into UserFarms — the table spCompany_GetByUserId
            // (/Companies/mine) joins on. Without this row a freshly-created staff
            // member resolves to no company at login and lands on the Poultry
            // default dashboard instead of their company's (Water/Generic). No SP
            // exists for a plain membership insert, so this is inline + guarded.
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                @"INSERT INTO userfarms (userid, farmid, role)
                  SELECT @UserId, @FarmId, @Role
                  WHERE NOT EXISTS (SELECT 1 FROM userfarms WHERE userid = @UserId AND farmid = @FarmId);",
                conn);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Role", string.IsNullOrWhiteSpace(role) ? "Staff" : role);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task RemoveMemberAsync(string userId, string farmId)
        {
            // Revoke a user's access to a company (Doc 3 §6-7). Inline + guarded —
            // there is no dedicated SP for a plain membership delete, matching the
            // inline INSERT in AddMemberAsync.
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                @"DELETE FROM userfarms WHERE userid = @UserId AND farmid = @FarmId;",
                conn);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<string>> GetMemberUserIdsAsync(string farmId)
        {
            // User ids granted access to a company via UserFarms — powers the
            // access-based company employee list (Doc 3 §7).
            var ids = new List<string>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                @"SELECT userid FROM userfarms WHERE farmid = @FarmId;",
                conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                var id = reader["UserId"]?.ToString();
                if (!string.IsNullOrWhiteSpace(id)) ids.Add(id);
            }
            return ids;
        }

        public async Task UpdateAsync(string farmId, CreateCompanyRequest req)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                @"SELECT * FROM spcompany_update(p_farmid => @FarmId::text, p_name => @Name::text,
                                                 p_email => @Email::text, p_phonenumber => @PhoneNumber::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Name", req.Name);
            cmd.Parameters.AddWithValue("@Email", (object?)req.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)req.PhoneNumber ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // Soft-delete (owner-only). Returns true if the company was deleted.
        public async Task<bool> DeleteAsync(string farmId, string userId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spcompany_delete(p_farmid => @FarmId::text, p_userid => @UserId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@UserId", userId);

            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return result != null && result != DBNull.Value && Convert.ToInt32(result) == 1;
        }

        private static CompanyResponse Map(NpgsqlDataReader r) => new()
        {
            FarmId      = r["FarmId"].ToString() ?? string.Empty,
            Name        = r["Name"].ToString() ?? string.Empty,
            Type        = r["Type"]?.ToString() ?? "Poultry",
            OwnerUserId = r["OwnerUserId"] == DBNull.Value ? null : r["OwnerUserId"].ToString(),
            Email       = r["Email"]       == DBNull.Value ? null : r["Email"].ToString(),
            PhoneNumber = r["PhoneNumber"] == DBNull.Value ? null : r["PhoneNumber"].ToString(),
            CreatedAt   = r["CreatedAt"]   == DBNull.Value ? DateTime.UtcNow : Convert.ToDateTime(r["CreatedAt"]),
            UpdatedAt   = r["UpdatedAt"]   == DBNull.Value ? null : Convert.ToDateTime(r["UpdatedAt"]),
            Role        = r["Role"]?.ToString() ?? "Admin",
        };
    }
}
