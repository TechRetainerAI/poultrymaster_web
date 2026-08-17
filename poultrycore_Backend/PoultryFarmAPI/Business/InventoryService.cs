using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Business
{
    public class InventoryService : IInventoryService
    {
        private readonly string _connectionString;
        /// <summary>Cache: does dbo.spInventoryItem_* include @Cost (migration 019)? Probing one param is enough — all 6 were added together.</summary>
        private static readonly ConcurrentDictionary<string, bool> SpHasInventoryFieldsCache = new();

        public InventoryService(string connectionString)
        {
            _connectionString = connectionString;
        }

        private static async Task<bool> ProcedureHasInventoryFieldsAsync(NpgsqlConnection conn, string procedureName)
        {
            if (SpHasInventoryFieldsCache.TryGetValue(procedureName, out var cached)) return cached;
            await using var probe = new NpgsqlCommand(
                @"SELECT 1 FROM sys.parameters p
                  INNER JOIN sys.procedures pr ON p.object_id = pr.object_id
                  WHERE SCHEMA_NAME(pr.schema_id) = N'dbo'
                    AND pr.name = @procName
                    AND (p.name = N'Cost' OR p.name = N'@Cost')",
                conn);
            probe.Parameters.AddWithValue("@procName", procedureName);
            var scalar = await probe.ExecuteScalarAsync();
            var has = scalar != null && scalar != DBNull.Value;
            SpHasInventoryFieldsCache[procedureName] = has;
            return has;
        }

        /// <summary>Read column by name if present in result set; otherwise return default.</summary>
        private static int? IndexOfColumn(NpgsqlDataReader reader, string name)
        {
            for (var i = 0; i < reader.FieldCount; i++)
                if (string.Equals(reader.GetName(i), name, StringComparison.OrdinalIgnoreCase)) return i;
            return null;
        }
        private static decimal? GetNullableDecimalIfPresent(NpgsqlDataReader r, string col)
        {
            var idx = IndexOfColumn(r, col); return idx.HasValue && !r.IsDBNull(idx.Value) ? r.GetDecimal(idx.Value) : (decimal?)null;
        }
        private static string? GetNullableStringIfPresent(NpgsqlDataReader r, string col)
        {
            var idx = IndexOfColumn(r, col); return idx.HasValue && !r.IsDBNull(idx.Value) ? r.GetString(idx.Value) : null;
        }
        private static DateTime? GetNullableDateTimeIfPresent(NpgsqlDataReader r, string col)
        {
            var idx = IndexOfColumn(r, col); return idx.HasValue && !r.IsDBNull(idx.Value) ? r.GetDateTime(idx.Value) : (DateTime?)null;
        }
        private static void HydrateInventoryExtras(NpgsqlDataReader r, InventoryItemModel m)
        {
            m.Cost = GetNullableDecimalIfPresent(r, "Cost");
            m.SupplierName = GetNullableStringIfPresent(r, "SupplierName");
            m.PurchaseDate = GetNullableDateTimeIfPresent(r, "PurchaseDate");
            m.Notes = GetNullableStringIfPresent(r, "Notes");
            m.Location = GetNullableStringIfPresent(r, "Location");
            m.ExpiryDate = GetNullableDateTimeIfPresent(r, "ExpiryDate");
        }

        public async Task<List<InventoryItemModel>> GetAllItemsAsync(string userId, string farmId)
        {
            try
            {
                var list = new List<InventoryItemModel>();
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spinventoryitem_getall(p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);
                cmd.Parameters.AddWithValue("@UserId", (object?)userId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var item = new InventoryItemModel
                    {
                        ItemId = reader.GetInt32(0),
                        UserId = reader.GetString(1),
                        FarmId = reader.GetString(2),
                        ItemName = reader.GetString(3),
                        Category = reader.GetString(4),
                        QuantityInStock = reader.GetDecimal(5),
                        UnitOfMeasure = reader.IsDBNull(6) ? "" : reader.GetString(6),
                        ReorderLevel = reader.IsDBNull(7) ? null : reader.GetDecimal(7),
                        SupplierId = reader.IsDBNull(8) ? null : reader.GetInt32(8),
                        IsActive = reader.GetBoolean(9)
                    };
                    HydrateInventoryExtras(reader, item);
                    list.Add(item);
                }
                return list;
            }
            catch (Exception ex)
            {
                throw new Exception("Error retrieving inventory items.", ex);
            }
        }

        public async Task<InventoryItemModel?> GetItemByIdAsync(int itemId, string userId, string farmId)
        {
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spinventoryitem_getbyid(p_itemid => @ItemId::int, p_farmid => @FarmId::text)", conn);
                cmd.Parameters.AddWithValue("@ItemId", itemId);
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    var item = new InventoryItemModel
                    {
                        FarmId = reader.GetString(0),
                        ItemId = reader.GetInt32(1),
                        UserId = reader.GetString(2),
                        ItemName = reader.GetString(3),
                        Category = reader.GetString(4),
                        QuantityInStock = reader.GetDecimal(5),
                        UnitOfMeasure = reader.IsDBNull(6) ? "" : reader.GetString(6),
                        ReorderLevel = reader.IsDBNull(7) ? null : reader.GetDecimal(7),
                        SupplierId = reader.IsDBNull(8) ? null : reader.GetInt32(8),
                        IsActive = reader.GetBoolean(9)
                    };
                    HydrateInventoryExtras(reader, item);
                    return item;
                }
                return null;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error retrieving item ID={itemId}.", ex);
            }
        }

        public async Task<int> CreateItemAsync(InventoryItemModel model)
        {
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spinventoryitem_insert(p_userid => @UserId::text, p_farmid => @FarmId::text, p_itemname => @ItemName::text, p_category => @Category::text, p_quantityinstock => @QuantityInStock::numeric, p_unitofmeasure => @UnitOfMeasure::text, p_reorderlevel => @ReorderLevel::numeric, p_supplierid => @SupplierId::int, p_isactive => @IsActive::boolean, p_cost => @Cost::numeric, p_suppliername => @SupplierName::text, p_purchasedate => @PurchaseDate::timestamp, p_notes => @Notes::text, p_location => @Location::text, p_expirydate => @ExpiryDate::timestamp)", conn);
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@ItemName", model.ItemName);
                cmd.Parameters.AddWithValue("@Category", model.Category);
                cmd.Parameters.AddWithValue("@QuantityInStock", model.QuantityInStock);
                cmd.Parameters.AddWithValue("@UnitOfMeasure", (object?)model.UnitOfMeasure ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ReorderLevel", (object?)model.ReorderLevel ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@SupplierId", (object?)model.SupplierId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@IsActive", model.IsActive);

                await conn.OpenAsync();
                if (await ProcedureHasInventoryFieldsAsync(conn, "spInventoryItem_Insert"))
                {
                    cmd.Parameters.AddWithValue("@Cost", (object?)model.Cost ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@SupplierName", (object?)model.SupplierName ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@PurchaseDate", (object?)model.PurchaseDate ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@Notes", (object?)model.Notes ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@Location", (object?)model.Location ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@ExpiryDate", (object?)model.ExpiryDate ?? DBNull.Value);
                }
                var result = await cmd.ExecuteScalarAsync();
                return Convert.ToInt32(result);
            }
            catch (Exception ex)
            {
                throw new Exception("Error creating inventory item.", ex);
            }
        }

        public async Task UpdateItemAsync(InventoryItemModel model)
        {
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spinventoryitem_update(p_userid => @UserId::text, p_farmid => @FarmId::text, p_itemid => @ItemId::int, p_itemname => @ItemName::text, p_category => @Category::text, p_quantityinstock => @QuantityInStock::numeric, p_unitofmeasure => @UnitOfMeasure::text, p_reorderlevel => @ReorderLevel::numeric, p_supplierid => @SupplierId::int, p_isactive => @IsActive::boolean, p_cost => @Cost::numeric, p_suppliername => @SupplierName::text, p_purchasedate => @PurchaseDate::timestamp, p_notes => @Notes::text, p_location => @Location::text, p_expirydate => @ExpiryDate::timestamp)", conn);
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@ItemId", model.ItemId);
                cmd.Parameters.AddWithValue("@ItemName", model.ItemName);
                cmd.Parameters.AddWithValue("@Category", model.Category);
                cmd.Parameters.AddWithValue("@QuantityInStock", model.QuantityInStock);
                cmd.Parameters.AddWithValue("@UnitOfMeasure", (object?)model.UnitOfMeasure ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ReorderLevel", (object?)model.ReorderLevel ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@SupplierId", (object?)model.SupplierId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@IsActive", model.IsActive);

                await conn.OpenAsync();
                if (await ProcedureHasInventoryFieldsAsync(conn, "spInventoryItem_Update"))
                {
                    cmd.Parameters.AddWithValue("@Cost", (object?)model.Cost ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@SupplierName", (object?)model.SupplierName ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@PurchaseDate", (object?)model.PurchaseDate ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@Notes", (object?)model.Notes ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@Location", (object?)model.Location ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@ExpiryDate", (object?)model.ExpiryDate ?? DBNull.Value);
                }
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error updating inventory item ID={model.ItemId}.", ex);
            }
        }

        public async Task DeleteItemAsync(int itemId, string userId, string farmId)
        {
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spinventoryitem_delete(p_itemid => @ItemId::int, p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);
                cmd.Parameters.AddWithValue("@ItemId", itemId);
                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error deleting item ID={itemId}.", ex);
            }
        }

        public async Task<List<InventoryTransactionModel>> GetTransactionsByItemAsync(int itemId, string userId, string farmId)
        {
            try
            {
                var list = new List<InventoryTransactionModel>();
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spinventorytransaction_getbyitem(p_itemid => @ItemId::int, p_farmid => @FarmId::text)", conn);
                cmd.Parameters.AddWithValue("@ItemId", itemId);
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(new InventoryTransactionModel
                    {
                        FarmId = reader.GetString(0),
                        UserId = reader.GetString(1),
                        TransactionId = reader.GetInt32(2),   //CHECK CAREFULLY
                        ItemId = reader.GetInt32(2),
                        TransactionDate = reader.GetDateTime(3),
                        QuantityChange = reader.GetDecimal(4),
                        TransactionType = reader.IsDBNull(5) ? null : reader.GetString(5),
                        Remarks = reader.IsDBNull(6) ? null : reader.GetString(6)
                    });
                }
                return list;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error retrieving transactions for item ID={itemId}.", ex);
            }
        }

        public async Task<int> CreateTransactionAsync(InventoryTransactionModel model)
        {
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spinventorytransaction_insert(p_itemid => @ItemId::int, p_farmid => @FarmId::text, p_transactiondate => @TransactionDate::timestamp, p_quantitychange => @QuantityChange::numeric, p_transactiontype => @TransactionType::text, p_remarks => @Remarks::text)", conn);
                cmd.Parameters.AddWithValue("@ItemId", model.ItemId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@TransactionDate", model.TransactionDate);
                cmd.Parameters.AddWithValue("@QuantityChange", model.QuantityChange);
                cmd.Parameters.AddWithValue("@TransactionType", (object?)model.TransactionType ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Remarks", (object?)model.Remarks ?? DBNull.Value);

                await conn.OpenAsync();
                var result = await cmd.ExecuteScalarAsync();
                return Convert.ToInt32(result);
            }
            catch (Exception ex)
            {
                throw new Exception("Error creating inventory transaction.", ex);
            }
        }
    }
}
