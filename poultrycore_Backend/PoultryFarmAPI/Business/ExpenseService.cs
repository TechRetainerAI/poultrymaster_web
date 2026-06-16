using System.Data;
using Microsoft.Data.SqlClient;
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

        private static Guid FarmIdToGuid(string farmId)
        {
            if (Guid.TryParse(farmId?.Trim(), out var g)) return g;
            return Guid.Empty;
        }

        private static string ReadFarmIdString(SqlDataReader reader)
        {
            if (!TryGetOrdinal(reader, "FarmId", out var ord)) return string.Empty;
            if (reader.IsDBNull(ord)) return string.Empty;
            var v = reader.GetValue(ord);
            return v is Guid g ? g.ToString("D") : v.ToString() ?? string.Empty;
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
                cmd.Parameters.AddWithValue("@Supplier", (object?)model.Supplier ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@FlockId", (object?)model.FlockId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", FarmIdToGuid(model.FarmId ?? string.Empty));
                cmd.Parameters.Add(new SqlParameter("@AttachmentImage", SqlDbType.VarBinary, -1)
                {
                    Value = (object?)model.AttachmentImage ?? DBNull.Value
                });
                cmd.Parameters.Add(new SqlParameter("@AttachmentContentType", SqlDbType.NVarChar, 64)
                {
                    Value = (object?)model.AttachmentContentType ?? DBNull.Value
                });

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
                cmd.Parameters.AddWithValue("@Supplier", (object?)model.Supplier ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@FlockId", (object?)model.FlockId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", FarmIdToGuid(model.FarmId ?? string.Empty));
                cmd.Parameters.Add(new SqlParameter("@AttachmentImage", SqlDbType.VarBinary, -1)
                {
                    Value = (object?)model.AttachmentImage ?? DBNull.Value
                });
                cmd.Parameters.Add(new SqlParameter("@AttachmentContentType", SqlDbType.NVarChar, 64)
                {
                    Value = (object?)model.AttachmentContentType ?? DBNull.Value
                });
                cmd.Parameters.AddWithValue("@AttachmentImageSet", model.SetAttachmentImage);

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
                cmd.Parameters.AddWithValue("@FarmId", FarmIdToGuid(farmId));

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return MapExpense(reader, userId);
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
                cmd.Parameters.AddWithValue("@FarmId", FarmIdToGuid(farmId));

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(MapExpense(reader, userId));
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
                cmd.Parameters.AddWithValue("@FarmId", FarmIdToGuid(farmId));

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
                cmd.Parameters.AddWithValue("@FarmId", FarmIdToGuid(farmId));

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(MapExpense(reader, userId));
                }
                return list;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error retrieving expense records for Flock ID={flockId}.", ex);
            }
        }

        public async Task<(byte[] Body, string ContentType)?> GetAttachment(int expenseId, string userId, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spExpense_GetAttachment", conn)
            {
                CommandType = CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("@ExpenseId", expenseId);
            cmd.Parameters.AddWithValue("@FarmId", FarmIdToGuid(farmId));

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync(CommandBehavior.SequentialAccess);
            if (!await reader.ReadAsync()) return null;

            var ordImg = reader.GetOrdinal("AttachmentImage");
            var ordCt = reader.GetOrdinal("AttachmentContentType");
            if (reader.IsDBNull(ordImg)) return null;

            var len = reader.GetBytes(ordImg, 0, null, 0, 0);
            if (len <= 0) return null;

            var buf = new byte[len];
            reader.GetBytes(ordImg, 0, buf, 0, (int)len);
            var ct = reader.IsDBNull(ordCt) ? "application/octet-stream" : reader.GetString(ordCt);
            return (buf, ct);
        }

        private static ExpenseModel MapExpense(SqlDataReader reader, string userId)
        {
            var hasAtt = TryGetOrdinal(reader, "HasAttachmentImage", out var ordHas)
                && !reader.IsDBNull(ordHas)
                && reader.GetBoolean(ordHas);

            var expenseDate = TryGetOrdinal(reader, "ExpenseDate", out var ordEd) && !reader.IsDBNull(ordEd)
                ? reader.GetDateTime(ordEd)
                : default;
            var category = TryGetOrdinal(reader, "Category", out var ordCat) && !reader.IsDBNull(ordCat)
                ? reader.GetString(ordCat)
                : string.Empty;
            var descOrd = TryGetOrdinal(reader, "Description", out var ordDesc) && !reader.IsDBNull(ordDesc)
                ? reader.GetString(ordDesc)
                : null;
            var amount = TryGetOrdinal(reader, "Amount", out var ordAmt) && !reader.IsDBNull(ordAmt)
                ? reader.GetDecimal(ordAmt)
                : 0m;
            string? paymentMethod = null;
            if (TryGetOrdinal(reader, "PaymentMethod", out var ordPm) && !reader.IsDBNull(ordPm))
                paymentMethod = reader.GetString(ordPm);
            string? supplier = null;
            if (TryGetOrdinal(reader, "Supplier", out var ordSup) && !reader.IsDBNull(ordSup))
                supplier = reader.GetString(ordSup);
            int? flockId = null;
            if (TryGetOrdinal(reader, "FlockId", out var ordFlock) && !reader.IsDBNull(ordFlock))
                flockId = ReadIntFlexible(reader, "FlockId");
            var createdDate = TryGetOrdinal(reader, "CreatedDate", out var ordCd) && !reader.IsDBNull(ordCd)
                ? reader.GetDateTime(ordCd)
                : default;
            var resolvedUserId = userId;
            if (TryGetOrdinal(reader, "UserId", out var ordUid) && !reader.IsDBNull(ordUid))
                resolvedUserId = reader.GetString(ordUid);

            return new ExpenseModel
            {
                ExpenseId = ReadIntFlexible(reader, "ExpenseId", "ExpenseID", "Id", "EXPENSEID"),
                ExpenseDate = expenseDate,
                Category = category,
                Description = descOrd,
                Amount = amount,
                PaymentMethod = paymentMethod,
                Supplier = supplier,
                FlockId = flockId,
                CreatedDate = createdDate,
                UserId = resolvedUserId,
                FarmId = ReadFarmIdString(reader),
                HasAttachmentImage = hasAtt
            };
        }

        private static bool TryGetOrdinal(SqlDataReader reader, string name, out int ordinal)
        {
            try
            {
                ordinal = reader.GetOrdinal(name);
                return true;
            }
            catch (IndexOutOfRangeException)
            {
                ordinal = -1;
                return false;
            }
        }

        private static bool HasColumn(IDataRecord record, string columnName)
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

        private static int ReadIntFlexible(SqlDataReader reader, params string[] columns)
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
                if (obj is Guid) continue;
                if (obj is string s)
                {
                    if (int.TryParse(s, out var v)) return v;
                    continue;
                }
                try
                {
                    return Convert.ToInt32(obj);
                }
                catch
                {
                    continue;
                }
            }
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
    }
}
