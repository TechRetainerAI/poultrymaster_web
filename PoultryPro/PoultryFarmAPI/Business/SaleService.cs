using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Business
{
    public class SaleService : ISaleService
    {
        private readonly string _connectionString;

        public SaleService(string connectionString)
        {
            _connectionString = connectionString;
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
                var result = await cmd.ExecuteScalarAsync();
                return Convert.ToInt32(result);
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
                await cmd.ExecuteNonQueryAsync();
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
