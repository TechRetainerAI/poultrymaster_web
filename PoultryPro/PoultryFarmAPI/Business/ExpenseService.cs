using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Business
{
    public class ExpenseService : IExpenseService
    {
        private readonly string _connectionString;

        public ExpenseService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<int> Insert(ExpenseModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spExpense_Insert", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@ExpenseDate", model.ExpenseDate);
                cmd.Parameters.AddWithValue("@Category", model.Category);
                cmd.Parameters.AddWithValue("@Description", (object?)model.Description ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Amount", model.Amount);
                cmd.Parameters.AddWithValue("@PaymentMethod", (object?)model.PaymentMethod ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@FlockId", (object?)model.FlockId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);

                await conn.OpenAsync();
                var result = await cmd.ExecuteScalarAsync();
                return Convert.ToInt32(result);
            }
            catch (Exception ex)
            {
                throw new Exception("Error inserting expense record.", ex);
            }
        }

        public async Task Update(ExpenseModel model)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spExpense_Update", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                cmd.Parameters.AddWithValue("@ExpenseId", model.ExpenseId);
                cmd.Parameters.AddWithValue("@ExpenseDate", model.ExpenseDate);
                cmd.Parameters.AddWithValue("@Category", model.Category);
                cmd.Parameters.AddWithValue("@Description", (object?)model.Description ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Amount", model.Amount);
                cmd.Parameters.AddWithValue("@PaymentMethod", (object?)model.PaymentMethod ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@FlockId", (object?)model.FlockId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error updating expense record ID={model.ExpenseId}.", ex);
            }
        }

        public async Task<ExpenseModel?> GetById(int expenseId, string userId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spExpense_GetById", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@ExpenseId", expenseId);
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return new ExpenseModel
                    {
                        ExpenseId = ReadIntFlexible(reader, "ExpenseId", "ExpenseID", "Id", "EXPENSEID"),
                        ExpenseDate = reader.GetDateTime(reader.GetOrdinal("ExpenseDate")),
                        Category = reader.GetString(reader.GetOrdinal("Category")),
                        Description = reader.IsDBNull(reader.GetOrdinal("Description"))
                                      ? null
                                      : reader.GetString(reader.GetOrdinal("Description")),
                        Amount = reader.GetDecimal(reader.GetOrdinal("Amount")),
                        PaymentMethod = reader.IsDBNull(reader.GetOrdinal("PaymentMethod"))
                                      ? null
                                      : reader.GetString(reader.GetOrdinal("PaymentMethod")),
                        FlockId = reader.IsDBNull(reader.GetOrdinal("FlockId"))
                                      ? (int?)null
                                      : ReadIntFlexible(reader, "FlockId"),
                        CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                        UserId = userId,
                        FarmId = farmId
                    };
                }
                return null;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error retrieving expense record ID={expenseId}.", ex);
            }
        }

        public async Task<List<ExpenseModel>> GetAll(string userId, string farmId)
        {
            try
            {
                var list = new List<ExpenseModel>();
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spExpense_GetAll", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var e = new ExpenseModel
                    {
                        ExpenseId = ReadIntFlexible(reader, "ExpenseId", "ExpenseID", "Id", "EXPENSEID"),
                        ExpenseDate = reader.GetDateTime(reader.GetOrdinal("ExpenseDate")),
                        Category = reader.GetString(reader.GetOrdinal("Category")),
                        Description = reader.IsDBNull(reader.GetOrdinal("Description"))
                                      ? null
                                      : reader.GetString(reader.GetOrdinal("Description")),
                        Amount = reader.GetDecimal(reader.GetOrdinal("Amount")),
                        PaymentMethod = reader.IsDBNull(reader.GetOrdinal("PaymentMethod"))
                                      ? null
                                      : reader.GetString(reader.GetOrdinal("PaymentMethod")),
                        FlockId = reader.IsDBNull(reader.GetOrdinal("FlockId"))
                                      ? (int?)null
                                      : ReadIntFlexible(reader, "FlockId"),
                        CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                        UserId = userId, // Use parameter instead of reading from DB
                        FarmId = farmId // Use parameter instead of reading from DB
                    };
                    list.Add(e);
                }
                return list;
            }
            catch (Exception ex)
            {
                throw new Exception("Error retrieving all expense records.", ex);
            }
        }

        public async Task Delete(int expenseId, string userId, string farmId)
        {
            try
            {
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spExpense_Delete", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@ExpenseId", expenseId);
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                throw new Exception($"Error deleting expense record ID={expenseId}.", ex);
            }
        }

        public async Task<List<ExpenseModel>> GetByFlock(int flockId, string userId, string farmId)
        {
            try
            {
                var list = new List<ExpenseModel>();
                using var conn = new SqlConnection(_connectionString);
                using var cmd = new SqlCommand("spExpense_GetByFlock", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@FlockId", flockId);
                //cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var e = new ExpenseModel
                    {
                        ExpenseId = ReadIntFlexible(reader, "ExpenseId", "ExpenseID", "Id", "EXPENSEID"),
                        ExpenseDate = reader.GetDateTime(reader.GetOrdinal("ExpenseDate")),
                        Category = reader.GetString(reader.GetOrdinal("Category")),
                        Description = reader.IsDBNull(reader.GetOrdinal("Description"))
                                      ? null
                                      : reader.GetString(reader.GetOrdinal("Description")),
                        Amount = reader.GetDecimal(reader.GetOrdinal("Amount")),
                        PaymentMethod = reader.IsDBNull(reader.GetOrdinal("PaymentMethod"))
                                      ? null
                                      : reader.GetString(reader.GetOrdinal("PaymentMethod")),
                        FlockId = reader.IsDBNull(reader.GetOrdinal("FlockId"))
                                      ? (int?)null
                                      : ReadIntFlexible(reader, "FlockId"),
                        CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                        UserId = userId, // Use parameter instead of reading from DB
                        FarmId = farmId // Use parameter instead of reading from DB
                    };
                    list.Add(e);
                }
                return list;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error retrieving expense records for Flock ID={flockId}.", ex);
            }
        }

        private bool HasColumn(IDataRecord record, string columnName)
        {
            for (int i = 0; i < record.FieldCount; i++)
            {
                if (string.Equals(record.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
            return false;
        }

        private int ReadIntFlexible(SqlDataReader reader, params string[] columns)
        {
            foreach (var column in columns)
            {
                if (!HasColumn(reader, column)) continue;
                var ordinal = reader.GetOrdinal(column);
                var obj = reader.GetValue(ordinal);
                if (obj == null || obj == DBNull.Value) continue;
                if (obj is int i) return i;
                if (obj is decimal d) return (int)d;
                if (obj is long l) return (int)l;
                if (obj is Guid) continue; // not an int
                if (obj is string s)
                {
                    if (int.TryParse(s, out var v)) return v;
                    // String but not numeric (e.g., GUID FarmId) → try next column or default 0
                    continue;
                }
                // Fallback: try safe conversion, but guard against format issues
                try
                {
                    return Convert.ToInt32(obj);
                }
                catch
                {
                    // Not convertible, move on
                    continue;
                }
            }
            // Last resort: scan for first numeric-looking column > 0
            for (int idx = 0; idx < reader.FieldCount; idx++)
            {
                var val = reader.GetValue(idx);
                if (val == null || val == DBNull.Value) continue;
                if (val is int ii && ii > 0) return ii;
                if (val is long ll && ll > 0) return (int)ll;
                if (val is decimal dd && dd > 0) return (int)dd;
                if (val is string ss && int.TryParse(ss, out var vv) && vv > 0) return vv;
            }
            return 0;
        }
        private int TryReadInt(SqlDataReader reader, string column)
        {
            try
            {
                var ordinal = reader.GetOrdinal(column);
                var obj = reader.GetValue(ordinal);
                if (obj == null || obj == DBNull.Value) return 0;
                if (obj is int i) return i;
                if (obj is decimal d) return (int)d;
                if (obj is long l) return (int)l;
                if (obj is string s && int.TryParse(s, out var v)) return v;
                return Convert.ToInt32(obj);
            }
            catch
            {
                return 0;
            }
        }
    }
}
