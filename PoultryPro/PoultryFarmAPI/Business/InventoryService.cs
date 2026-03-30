using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Business
{
    public class InventoryService : IInventoryService
    {
        private readonly string _connectionString;

        public InventoryService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<List<InventoryItemModel>> GetAllItemsAsync(string userId, string farmId)
        {
            try
            {
                var list = new List<InventoryItemModel>();
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spInventoryItem_GetAll", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };
                cmd.Parameters.AddWithValue("@UserId", (object?)userId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(new InventoryItemModel
                    {
                        ItemId = reader.GetInt32(0),
                        UserId = reader.GetString(1),
                        FarmId = reader.GetString(2),
                        ItemName = reader.GetString(3),
                        Category = reader.GetString(4),
                        QuantityInStock = reader.GetDecimal(5),
                        UnitOfMeasure = reader.IsDBNull(6) ? "" : reader.GetString(6),
                        ReorderLevel = reader.IsDBNull(7) ? null : reader.GetDecimal(7),
                        IsActive = reader.GetBoolean(8)
                    });
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
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spInventoryItem_GetById", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };
                cmd.Parameters.AddWithValue("@ItemId", itemId);
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return new InventoryItemModel
                    {
                        FarmId = reader.GetString(0),
                        ItemId = reader.GetInt32(1),
                        UserId = reader.GetString(2),
                        ItemName = reader.GetString(3),
                        Category = reader.GetString(4),
                        QuantityInStock = reader.GetDecimal(5),
                        UnitOfMeasure = reader.IsDBNull(6) ? "" : reader.GetString(6),
                        ReorderLevel = reader.IsDBNull(7) ? null : reader.GetDecimal(7),
                        IsActive = reader.GetBoolean(8)
                    };
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
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spInventoryItem_Insert", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@ItemName", model.ItemName);
                cmd.Parameters.AddWithValue("@Category", model.Category);
                cmd.Parameters.AddWithValue("@QuantityInStock", model.QuantityInStock);
                cmd.Parameters.AddWithValue("@UnitOfMeasure", (object?)model.UnitOfMeasure ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ReorderLevel", (object?)model.ReorderLevel ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@IsActive", model.IsActive);

                await conn.OpenAsync();
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
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spInventoryItem_Update", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@ItemId", model.ItemId);
                cmd.Parameters.AddWithValue("@ItemName", model.ItemName);
                cmd.Parameters.AddWithValue("@Category", model.Category);
                cmd.Parameters.AddWithValue("@QuantityInStock", model.QuantityInStock);
                cmd.Parameters.AddWithValue("@UnitOfMeasure", (object?)model.UnitOfMeasure ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ReorderLevel", (object?)model.ReorderLevel ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@IsActive", model.IsActive);

                await conn.OpenAsync();
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
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spInventoryItem_Delete", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };
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
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spInventoryTransaction_GetByItem", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };
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
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spInventoryTransaction_Insert", conn)
                {
                    CommandType = CommandType.StoredProcedure
                };
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
