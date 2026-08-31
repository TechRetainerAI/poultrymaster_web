using System.Data;
using Npgsql;
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
        private static readonly ConcurrentDictionary<string, bool> SpHasCustomerIdParamCache = new();

        public SaleService(string connectionString)
        {
            _connectionString = connectionString;
        }

        private static async Task<bool> ProcedureHasPaidParameterAsync(NpgsqlConnection conn, string procedureName)
        {
            if (SpHasPaidParamCache.TryGetValue(procedureName, out var cached))
                return cached;

            await using var probe = new NpgsqlCommand(
                @"SELECT 1
                  FROM pg_proc p
                  INNER JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public'
                    AND p.proname = lower(@procName)
                    AND 'p_paid' = ANY(p.proargnames)",
                conn);
            probe.Parameters.AddWithValue("@procName", procedureName);
            var scalar = await probe.ExecuteScalarAsync();
            var has = scalar != null && scalar != DBNull.Value;
            SpHasPaidParamCache[procedureName] = has;
            return has;
        }

        /// <summary>Probes whether the stored procedure has @Size (added by migration 018).</summary>
        private static async Task<bool> ProcedureHasSizeParameterAsync(NpgsqlConnection conn, string procedureName)
        {
            if (SpHasSizeParamCache.TryGetValue(procedureName, out var cached))
                return cached;

            await using var probe = new NpgsqlCommand(
                @"SELECT 1
                  FROM pg_proc p
                  INNER JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public'
                    AND p.proname = lower(@procName)
                    AND 'p_size' = ANY(p.proargnames)",
                conn);
            probe.Parameters.AddWithValue("@procName", procedureName);
            var scalar = await probe.ExecuteScalarAsync();
            var has = scalar != null && scalar != DBNull.Value;
            SpHasSizeParamCache[procedureName] = has;
            return has;
        }

        /// <summary>
        /// Probes whether the stored procedure has @CustomerId (migration 223).
        /// Same guard the @Paid and @Size probes use, for the same reason: an API
        /// deployed ahead of its migration must still be able to save a sale.
        /// </summary>
        private static async Task<bool> ProcedureHasCustomerIdParameterAsync(NpgsqlConnection conn, string procedureName)
        {
            if (SpHasCustomerIdParamCache.TryGetValue(procedureName, out var cached))
                return cached;

            await using var probe = new NpgsqlCommand(
                @"SELECT 1
                  FROM pg_proc p
                  INNER JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public'
                    AND p.proname = lower(@procName)
                    AND 'p_customerid' = ANY(p.proargnames)",
                conn);
            probe.Parameters.AddWithValue("@procName", procedureName);
            var scalar = await probe.ExecuteScalarAsync();
            var has = scalar != null && scalar != DBNull.Value;
            SpHasCustomerIdParamCache[procedureName] = has;
            return has;
        }

        private static string? GetNullableStringIfPresent(NpgsqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? null : reader.GetString(i);
            }
            return null;
        }

        private static bool GetBooleanIfPresent(NpgsqlDataReader reader, string columnName, bool defaultValue = true)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return !reader.IsDBNull(i) && reader.GetBoolean(i);
            }
            return defaultValue;
        }

        private static int? GetNullableInt32IfPresent(NpgsqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? (int?)null : Convert.ToInt32(reader.GetValue(i));
            }
            return null;
        }

        private static decimal GetDecimalIfPresent(NpgsqlDataReader reader, string columnName, decimal defaultValue = 0m)
        {
            for (var i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? defaultValue : Convert.ToDecimal(reader.GetValue(i));
            }
            return defaultValue;
        }

        // Posts / reverses the sale's cash-in on the chosen PoultryCashAccount.
        // Safe to call with a null account (reverse only).
        //
        // Since migration 223 a PART-paid sale posts what has actually been
        // received (sale.AmountPaid) rather than nothing. A paid sale still posts
        // its full total, and an unpaid sale with no payments still moves no
        // money — AmountPaid is 0 at that point.
        // businessDate re-stamps the ledger row after the sync. The sync writes
        // now() and is reverse-then-repost, so a January sale that takes a second
        // payment in August would otherwise have its whole cash-in re-dated to
        // August. See migration 229 for why this is a separate call rather than a
        // parameter on the sync.
        private async Task SyncSaleCashAsync(string farmId, int saleId, int? cashAccountId, decimal amount, bool paid, string? description, string? createdBy, DateTime? businessDate = null)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrysalecash_sync(p_farmid => @FarmId::text, p_saleid => @SaleId::int, p_poultrycashaccountid => @PoultryCashAccountId::int, p_amount => @Amount::numeric, p_paid => @Paid::boolean, p_description => @Description::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@SaleId", saleId);
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", (object?)cashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Amount", amount);
            cmd.Parameters.AddWithValue("@Paid", paid);
            cmd.Parameters.AddWithValue("@Description", (object?)description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();

            if (businessDate.HasValue)
            {
                using var stamp = new NpgsqlCommand("SELECT public.sppoultrycashtransaction_setbusinessdate(p_farmid => @FarmId::text, p_sourcetype => 'Sale', p_sourceid => @SaleId::int, p_businessdate => @BusinessDate::timestamp)", conn);
                stamp.Parameters.AddWithValue("@FarmId", farmId);
                stamp.Parameters.AddWithValue("@SaleId", saleId);
                stamp.Parameters.AddWithValue("@BusinessDate", businessDate.Value);
                await stamp.ExecuteNonQueryAsync();
            }
        }

        public async Task<int> Insert(SaleModel model)
        {
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("spSale_Insert", conn);
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
                if (await ProcedureHasCustomerIdParameterAsync(conn, "spSale_Insert"))
                    cmd.Parameters.AddWithValue("@CustomerId", (object?)model.CustomerId ?? DBNull.Value);
                // Built after the conditional adds so the call text matches the
                // parameters actually present.
                cmd.CommandText = await PgCallText.ForAsync("spSale_Insert", cmd);
                var result = await cmd.ExecuteScalarAsync();
                var newId = Convert.ToInt32(result);
                await SyncSaleCashAsync(model.FarmId, newId, model.PoultryCashAccountId, model.TotalAmount, model.Paid, model.SaleDescription, model.UserId, model.SaleDate);
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
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("spSale_Update", conn);
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
                if (await ProcedureHasCustomerIdParameterAsync(conn, "spSale_Update"))
                    cmd.Parameters.AddWithValue("@CustomerId", (object?)model.CustomerId ?? DBNull.Value);
                cmd.CommandText = await PgCallText.ForAsync("spSale_Update", cmd);
                await cmd.ExecuteNonQueryAsync();
                conn.Close();
                await SyncSaleCashAsync(model.FarmId, model.SaleId, model.PoultryCashAccountId, model.TotalAmount, model.Paid, model.SaleDescription, model.UserId, model.SaleDate);
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
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spsale_getbyid(p_saleid => @SaleId::int, p_farmid => @FarmId::text)", conn);
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
                        CustomerId = GetNullableInt32IfPresent(reader, "CustomerId"),
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
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spsale_getall(p_farmid => @FarmId::text)", conn);
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
                        CustomerId = GetNullableInt32IfPresent(reader, "CustomerId"),
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

                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spsale_delete(p_saleid => @SaleId::int, p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);
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
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spsale_getbyflock(p_flockid => @FlockId::int, p_farmid => @FarmId::text)", conn);
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
                        CustomerId = GetNullableInt32IfPresent(reader, "CustomerId"),
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
