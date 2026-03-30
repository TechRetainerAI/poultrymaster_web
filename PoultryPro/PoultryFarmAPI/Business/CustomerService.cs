using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Business
{
    public class CustomerService : ICustomerService
    {
        private readonly string _connectionString;

        public CustomerService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<int> Insert(CustomerModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spCustomer_Insert", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@Name", model.Name);
                cmd.Parameters.AddWithValue("@ContactEmail", (object?)model.ContactEmail ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ContactPhone", (object?)model.ContactPhone ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Address", (object?)model.Address ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@City", (object?)model.City ?? DBNull.Value);

                await conn.OpenAsync();
                var result = await cmd.ExecuteScalarAsync();
                return Convert.ToInt32(result);
            }
            catch (Exception ex)
            {
                throw new Exception("Error inserting customer record.", ex);
            }
        }

        public async Task Update(CustomerModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spCustomer_Update", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@CustomerId", model.CustomerId);
                cmd.Parameters.AddWithValue("@Name", model.Name);
                cmd.Parameters.AddWithValue("@ContactEmail", (object?)model.ContactEmail ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ContactPhone", (object?)model.ContactPhone ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Address", (object?)model.Address ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@City", (object?)model.City ?? DBNull.Value);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error updating customer ID={model.CustomerId}.", ex);
            }
        }

        public async Task<CustomerModel?> GetById(int customerId, string userId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spCustomer_GetById", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@CustomerId", customerId);
                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return new CustomerModel
                    {
                        CustomerId = reader.GetInt32(reader.GetOrdinal("CustomerId")),
                        Name = reader.GetString(reader.GetOrdinal("Name")),
                        ContactEmail = reader.IsDBNull(reader.GetOrdinal("ContactEmail"))
                                         ? null
                                         : reader.GetString(reader.GetOrdinal("ContactEmail")),
                        ContactPhone = reader.IsDBNull(reader.GetOrdinal("ContactPhone"))
                                         ? null
                                         : reader.GetString(reader.GetOrdinal("ContactPhone")),
                        Address = reader.IsDBNull(reader.GetOrdinal("Address"))
                                         ? null
                                         : reader.GetString(reader.GetOrdinal("Address")),
                        City = reader.IsDBNull(reader.GetOrdinal("City"))
                                         ? null
                                         : reader.GetString(reader.GetOrdinal("City")),
                        CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                        FarmId = reader.IsDBNull(reader.GetOrdinal("FarmId"))
                                         ? null
                                         : reader.GetString(reader.GetOrdinal("FarmId"))
                    };
                }
                return null;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error retrieving customer ID={customerId}.", ex);
            }
        }

        public async Task<List<CustomerModel>> GetAll(string userId, string farmId)
        {
            try
            {
                var list = new List<CustomerModel>();
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spCustomer_GetAll", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var c = new CustomerModel
                    {
                        CustomerId = reader.GetInt32(reader.GetOrdinal("CustomerId")),
                        Name = reader.GetString(reader.GetOrdinal("Name")),
                        ContactEmail = reader.IsDBNull(reader.GetOrdinal("ContactEmail"))
                                         ? null
                                         : reader.GetString(reader.GetOrdinal("ContactEmail")),
                        ContactPhone = reader.IsDBNull(reader.GetOrdinal("ContactPhone"))
                                         ? null
                                         : reader.GetString(reader.GetOrdinal("ContactPhone")),
                        Address = reader.IsDBNull(reader.GetOrdinal("Address"))
                                         ? null
                                         : reader.GetString(reader.GetOrdinal("Address")),
                        City = reader.IsDBNull(reader.GetOrdinal("City"))
                                         ? null
                                         : reader.GetString(reader.GetOrdinal("City")),
                        CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                        FarmId = reader.IsDBNull(reader.GetOrdinal("FarmId"))
                                         ? null
                                         : reader.GetString(reader.GetOrdinal("FarmId"))
                    };
                    list.Add(c);
                }
                return list;
            }
            catch (Exception ex)
            {
                throw new Exception("Error retrieving all customers.", ex);
            }
        }

        public async Task Delete(int customerId, string userId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spCustomer_Delete", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@CustomerId", customerId);
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error deleting customer ID={customerId}.", ex);
            }
        }
    }
}