using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spCompany_Create", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Name", req.Name);
            cmd.Parameters.AddWithValue("@Type", string.IsNullOrWhiteSpace(req.Type) ? "Poultry" : req.Type);
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spCompany_GetByUserId", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@UserId", userId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(Map(reader));
            return list;
        }

        public async Task<CompanyResponse?> GetByIdAsync(string farmId, string userId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spCompany_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@UserId", userId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync()) return Map(reader);
            return null;
        }

        public async Task<bool> IsMemberAsync(string userId, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spUserFarm_IsMember", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return result is bool b && b;
        }

        public async Task UpdateAsync(string farmId, CreateCompanyRequest req)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spCompany_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Name", req.Name);
            cmd.Parameters.AddWithValue("@Email", (object?)req.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)req.PhoneNumber ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static CompanyResponse Map(SqlDataReader r) => new()
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
