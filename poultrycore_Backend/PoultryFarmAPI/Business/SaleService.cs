using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Business
{
    public class SaleService : ISaleService
    {
        private readonly string _connectionString;
        private static readonly ConcurrentDictionary<string, bool> SpHasPaidParamCache = new();
        private static readonly ConcurrentDictionary<string, bool> SpHasSizeParamCache = new();

        public SaleService(string connectionString)
        {
            _connectionString = connectionString;
        }

        private static async Task<bool> ProcedureHasPaidParameterAsync(SqlConnection conn, string procedureName)
        {
            if (SpHasPaidParamCache.TryGetValue(procedureName, out var cached))
                return cached;

            await using var probe = new SqlCommand(
                @"SELECT 1
                  FROM sys.parameters p
                  INNER JOIN sys.procedures pr ON p.object_id = pr.object_id
                  WHERE SCHEMA_NAME(pr.schema_id) = N'dbo'
                    AND pr.name = @procName
                    AND (p.name = N'Paid' OR p.name = N'@Paid')",
                conn);
            probe.Parameters.AddWithValue("@procName", procedureName);
            var scalar = await probe.ExecuteScalarAsync();
            var has = scalar != null && scalar != DBNull.Value;
            SpHasPaidParamCache[procedureName] = has;
            return has;
        }

        /// <summary>Probes whether the stored procedure has @Size (added by migration 018).</summary>
        private static async Task<bool> ProcedureHasSizeParameterAsync(SqlConnection conn, string procedureName)
        {
            if (SpHasSizeParamCache.TryGetValue(procedureName, out var cached))
                return cached;

            await using var probe = new SqlCommand(
                @"SELECT 1
                  FROM sys.parameters p
                  INNER JOIN sys.procedures pr ON p.object_id = pr.object_id
                  WHERE SCHEMA_NAME(pr.schema_id) = N'dbo'
                    AND pr.name = @procName
                    AND (p.name = N'Size' OR p.name = N'@Size')",
                conn);
            probe.Parameters.AddWithValue("@procName", procedureName);
            var scalar = await probe.ExecuteScalarAsync();
            var has = scalar != null && scalar != DBNull.Value;
            SpHasSizeParamCache[procedureName] = has;
            return has;
        }

        private static string? GetNullableStringIfPresent(SqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? null : reader.GetString(i);
            }
            return null;
        }

        private static bool GetBooleanIfPresent(SqlDataReader reader, string columnName, bool defaultValue = true)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return !reader.IsDBNull(i) && reader.GetBoolean(i);
            }
            return defaultValue;
        }

        private static int? GetNullableInt32IfPresent(SqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? (int?)null : Convert.ToInt32(reader.GetValue(i));
            }
            return null;
        }

        private static decimal GetDecimalIfPresent(SqlDataReader reader, string columnName, decimal defaultValue = 0m)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? defaultValue : Convert.ToDecimal(reader.GetValue(i));
            }
            return defaultValue;
        }

        // Posts / reverses the sale's cash-in on the chosen PoultryCashAccount.
        // Safe to call with a null account (reverse only). Only posts when the
        // sale is paid — an unpaid sale records the account but moves no money.
        private async Task SyncSaleCashAsync(string farmId, int saleId, int? cashAccountId, decimal amount, bool paid, string? description, string? createdBy)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spPoultrySaleCash_Sync", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@SaleId", saleId);
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", (object?)cashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Amount", amount);
            cmd.Parameters.AddWithValue("@Paid", paid);
            cmd.Parameters.AddWithValue("@Description", (object?)description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<int> Insert(SaleModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spSale_Insert", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@SaleDate", model.SaleDate);
                cmd.Parameters.AddWithValue("@Product", model.Product);
                cmd.Parameters.AddWithValue("@Quantity", model.Quantity);
                cmd.Parameters.AddWithValue("@UnitPrice", model.UnitPrice);
                cmd.Parameters.AddWithValue("@TotalAmount", model.TotalAmount);
                cmd.Parameters.AddWithValue("@PaymentMethod", (object?)model.PaymentMethod ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@CustomerName", (object?)model.CustomerName ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@FlockId", (object?)model.FlockId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@SaleDescription", (object?)model.SaleDescription ?? DBNull.Value);

                await conn.OpenAsync();
                if (await ProcedureHasPaidParameterAsync(conn, "spSale_Insert"))
                    cmd.Parameters.AddWithValue("@Paid", model.Paid);
                if (await ProcedureHasSizeParameterAsync(conn, "spSale_Insert"))
                    cmd.Parameters.AddWithValue("@Size", (object?)model.Size ?? DBNull.Value);
                var result = await cmd.ExecuteScalarAsync();
                var newId = Convert.ToInt32(result);
                await SyncSaleCashAsync(model.FarmId, newId, model.PoultryCashAccountId, model.TotalAmount, model.Paid, model.SaleDescription, model.UserId);
                return newId;
            }
            catch (Exception ex)
            {
                throw new Exception("Error inserting Sale record.", ex);
            }
        }

        public async Task Update(SaleModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spSale_Update", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@SaleId", model.SaleId);
                cmd.Parameters.AddWithValue("@SaleDate", model.SaleDate);
                cmd.Parameters.AddWithValue("@Product", model.Product);
                cmd.Parameters.AddWithValue("@Quantity", model.Quantity);
                cmd.Parameters.AddWithValue("@UnitPrice", model.UnitPrice);
                cmd.Parameters.AddWithValue("@TotalAmount", model.TotalAmount);
                cmd.Parameters.AddWithValue("@PaymentMethod", (object?)model.PaymentMethod ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@CustomerName", (object?)model.CustomerName ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@FlockId", (object?)model.FlockId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@SaleDescription", (object?)model.SaleDescription ?? DBNull.Value);

                await conn.OpenAsync();
                if (await ProcedureHasPaidParameterAsync(conn, "spSale_Update"))
                    cmd.Parameters.AddWithValue("@Paid", model.Paid);
                if (await ProcedureHasSizeParameterAsync(conn, "spSale_Update"))
                    cmd.Parameters.AddWithValue("@Size", (object?)model.Size ?? DBNull.Value);
                await cmd.ExecuteNonQueryAsync();
                conn.Close();
                await SyncSaleCashAsync(model.FarmId, model.SaleId, model.PoultryCashAccountId, model.TotalAmount, model.Paid, model.SaleDescription, model.UserId);
            }
            catch (Exception ex)
            {
                throw new Exception($"Error updating Sale record ID={model.SaleId}.", ex);
            }
        }

        public async Task<SaleModel?> GetById(int saleId, string userId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spSale_GetById", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@SaleId", saleId);
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return new SaleModel
                    {
                        SaleId = reader.GetInt32(reader.GetOrdinal("SaleId")),
                        SaleDate = reader.GetDateTime(reader.GetOrdinal("SaleDate")),
                        Product = reader.GetString(reader.GetOrdinal("Product")),
                        Quantity = reader.GetDecimal(reader.GetOrdinal("Quantity")),
                        UnitPrice = reader.GetDecimal(reader.GetOrdinal("UnitPrice")),
                        TotalAmount = reader.GetDecimal(reader.GetOrdinal("TotalAmount")),
                        PaymentMethod = reader.IsDBNull(reader.GetOrdinal("PaymentMethod")) ? null : reader.GetString(reader.GetOrdinal("PaymentMethod")),
                        CustomerName = reader.IsDBNull(reader.GetOrdinal("CustomerName")) ? null : reader.GetString(reader.GetOrdinal("CustomerName")),
                        FlockId = reader.IsDBNull(reader.GetOrdinal("FlockId")) ? null : reader.GetInt32(reader.GetOrdinal("FlockId")),
                        SaleDescription = reader.IsDBNull(reader.GetOrdinal("SaleDescription")) ? null : reader.GetString(reader.GetOrdinal("SaleDescription")),
                        Paid = GetBooleanIfPresent(reader, "Paid", true),
                        Size = GetNullableStringIfPresent(reader, "Size"),
                        PoultryCashAccountId = GetNullableInt32IfPresent(reader, "PoultryCashAccountId"),
                        AmountPaid = GetDecimalIfPresent(reader, "AmountPaid", 0m),
                        CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                        FarmId = reader.GetString(reader.GetOrdinal("FarmId"))
                    };
                }
                return null;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error retrieving Sale record ID={saleId}.", ex);
            }
        }

        public async Task<List<SaleModel>> GetAll(string userId, string farmId)
        {
            try
            {
                var list = new List<SaleModel>();
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spSale_GetAll", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var s = new SaleModel
                    {
                        SaleId = reader.GetInt32(reader.GetOrdinal("SaleId")),
                        SaleDate = reader.GetDateTime(reader.GetOrdinal("SaleDate")),
                        Product = reader.GetString(reader.GetOrdinal("Product")),
                        Quantity = reader.GetDecimal(reader.GetOrdinal("Quantity")),
                        UnitPrice = reader.GetDecimal(reader.GetOrdinal("UnitPrice")),
                        TotalAmount = reader.GetDecimal(reader.GetOrdinal("TotalAmount")),
                        PaymentMethod = reader.IsDBNull(reader.GetOrdinal("PaymentMethod")) ? null : reader.GetString(reader.GetOrdinal("PaymentMethod")),
                        CustomerName = reader.IsDBNull(reader.GetOrdinal("CustomerName")) ? null : reader.GetString(reader.GetOrdinal("CustomerName")),
                        FlockId = reader.IsDBNull(reader.GetOrdinal("FlockId")) ? null : reader.GetInt32(reader.GetOrdinal("FlockId")),
                        SaleDescription = reader.IsDBNull(reader.GetOrdinal("SaleDescription")) ? null : reader.GetString(reader.GetOrdinal("SaleDescription")),
                        Paid = GetBooleanIfPresent(reader, "Paid", true),
                        Size = GetNullableStringIfPresent(reader, "Size"),
                        PoultryCashAccountId = GetNullableInt32IfPresent(reader, "PoultryCashAccountId"),
                        AmountPaid = GetDecimalIfPresent(reader, "AmountPaid", 0m),
                        CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                        FarmId = reader.GetString(reader.GetOrdinal("FarmId"))
                    };
                    list.Add(s);
                }
                return list;
            }
            catch (Exception ex)
            {
                throw new Exception("Error retrieving all Sale records.", ex);
            }
        }

        public async Task Delete(int saleId, string userId, string farmId)
        {
            try
            {
                // Reverse any cash-in this sale posted before removing it.
                await SyncSaleCashAsync(farmId, saleId, null, 0m, false, null, userId);

                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spSale_Delete", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@SaleId", saleId);
                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error deleting Sale record ID={saleId}.", ex);
            }
        }

        public async Task<List<SaleModel>> GetByFlock(int flockId, string userId, string farmId)
        {
            try
            {
                var list = new List<SaleModel>();
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spSale_GetByFlock", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@FlockId", flockId);
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var s = new SaleModel
                    {
                        SaleId = reader.GetInt32(reader.GetOrdinal("SaleId")),
                        SaleDate = reader.GetDateTime(reader.GetOrdinal("SaleDate")),
                        Product = reader.GetString(reader.GetOrdinal("Product")),
                        Quantity = reader.GetDecimal(reader.GetOrdinal("Quantity")),
                        UnitPrice = reader.GetDecimal(reader.GetOrdinal("UnitPrice")),
                        TotalAmount = reader.GetDecimal(reader.GetOrdinal("TotalAmount")),
                        PaymentMethod = reader.IsDBNull(reader.GetOrdinal("PaymentMethod")) ? null : reader.GetString(reader.GetOrdinal("PaymentMethod")),
                        CustomerName = reader.IsDBNull(reader.GetOrdinal("CustomerName")) ? null : reader.GetString(reader.GetOrdinal("CustomerName")),
                        FlockId = reader.IsDBNull(reader.GetOrdinal("FlockId")) ? null : reader.GetInt32(reader.GetOrdinal("FlockId")),
                        SaleDescription = reader.IsDBNull(reader.GetOrdinal("SaleDescription")) ? null : reader.GetString(reader.GetOrdinal("SaleDescription")),
                        Paid = GetBooleanIfPresent(reader, "Paid", true),
                        Size = GetNullableStringIfPresent(reader, "Size"),
                        PoultryCashAccountId = GetNullableInt32IfPresent(reader, "PoultryCashAccountId"),
                        AmountPaid = GetDecimalIfPresent(reader, "AmountPaid", 0m),
                        CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                        FarmId = reader.GetString(reader.GetOrdinal("FarmId"))
                    };
                    list.Add(s);
                }
                return list;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error retrieving Sale records for Flock ID={flockId}.", ex);
            }
        }
    }
}
