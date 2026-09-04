using System.Data;
using Npgsql;
using NpgsqlTypes;
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

        private static string ReadFarmIdString(NpgsqlDataReader reader)
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
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spexpense_insert(p_expensedate => @ExpenseDate::timestamp, p_category => @Category::text, p_description => @Description::text, p_amount => @Amount::numeric, p_paymentmethod => @PaymentMethod::text, p_supplier => @Supplier::text, p_flockid => @FlockId::int, p_userid => @UserId::text, p_farmid => @FarmId::uuid, p_attachmentimage => @AttachmentImage::bytea, p_attachmentcontenttype => @AttachmentContentType::text, p_supplierid => @SupplierId::int, p_amountpaid => @AmountPaid::numeric, p_duedate => @DueDate::date)", conn);
                cmd.Parameters.AddWithValue("@SupplierId", (object?)model.SupplierId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@AmountPaid", (object?)model.AmountPaid ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@DueDate", (object?)model.DueDate?.Date ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ExpenseDate", model.ExpenseDate);
                cmd.Parameters.AddWithValue("@Category", model.Category);
                cmd.Parameters.AddWithValue("@Description", (object?)model.Description ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Amount", model.Amount);
                cmd.Parameters.AddWithValue("@PaymentMethod", (object?)model.PaymentMethod ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Supplier", (object?)model.Supplier ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@FlockId", (object?)model.FlockId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", FarmIdToGuid(model.FarmId ?? string.Empty));
                cmd.Parameters.Add(new NpgsqlParameter("@AttachmentImage", NpgsqlDbType.Bytea, -1)
                {
                    Value = (object?)model.AttachmentImage ?? DBNull.Value
                });
                cmd.Parameters.Add(new NpgsqlParameter("@AttachmentContentType", NpgsqlDbType.Text, 64)
                {
                    Value = (object?)model.AttachmentContentType ?? DBNull.Value
                });

                await conn.OpenAsync();
                var result = await cmd.ExecuteScalarAsync();
                var newId = Convert.ToInt32(result);
                await SyncExpenseCashAsync(model.FarmId ?? string.Empty, newId, model.PoultryCashAccountId, model.Amount, model.Description, model.UserId, model.ExpenseDate);
                return newId;
            }
            catch (Exception ex)
            {
                throw new Exception("Error inserting expense record.", ex);
            }
        }

        // Posts / reverses the expense's cash-out on the chosen PoultryCashAccount.
        // Safe to call with a null account (reverse only). Uses the NVARCHAR farmId
        // so the cash rows scope correctly (dbo.Expense.FarmId is a GUID).
        //
        // Since migration 238 the AMOUNT argument is advisory: the function posts
        // the expense's own resolved amountpaid, minus whatever supplier payments
        // have already covered, so a part-paid bill moves only the cash that
        // actually moved and the payment's own CashOut is not double counted.
        // Call it AFTER the insert/update, never before -- it reads the row.
        //
        // businessDate re-stamps the ledger row after the sync. The sync itself
        // writes now(), and it is reverse-then-repost, so without this a January
        // expense edited in August lands its cash-out in August and every
        // date-ranged cash-flow total shifts under the reader. See migration 229 --
        // it explains why this is a separate call rather than a parameter on the
        // sync (that function's live Postgres body is not in this repo).
        private async Task SyncExpenseCashAsync(string farmId, int expenseId, int? cashAccountId, decimal amount, string? description, string? createdBy, DateTime? businessDate = null)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryexpensecash_sync(p_farmid => @FarmId::text, p_expenseid => @ExpenseId::int, p_poultrycashaccountid => @PoultryCashAccountId::int, p_amount => @Amount::numeric, p_description => @Description::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ExpenseId", expenseId);
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", (object?)cashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Amount", amount);
            cmd.Parameters.AddWithValue("@Description", (object?)description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();

            if (businessDate.HasValue)
            {
                using var stamp = new NpgsqlCommand("SELECT public.sppoultrycashtransaction_setbusinessdate(p_farmid => @FarmId::text, p_sourcetype => 'Expense', p_sourceid => @ExpenseId::int, p_businessdate => @BusinessDate::timestamp)", conn);
                stamp.Parameters.AddWithValue("@FarmId", farmId);
                stamp.Parameters.AddWithValue("@ExpenseId", expenseId);
                stamp.Parameters.AddWithValue("@BusinessDate", businessDate.Value);
                await stamp.ExecuteNonQueryAsync();
            }
        }

        public async Task Update(ExpenseModel model)
        {
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spexpense_update(p_expenseid => @ExpenseId::int, p_expensedate => @ExpenseDate::timestamp, p_category => @Category::text, p_description => @Description::text, p_amount => @Amount::numeric, p_paymentmethod => @PaymentMethod::text, p_supplier => @Supplier::text, p_flockid => @FlockId::int, p_userid => @UserId::text, p_farmid => @FarmId::uuid, p_attachmentimageset => @AttachmentImageSet::boolean, p_attachmentimage => @AttachmentImage::bytea, p_attachmentcontenttype => @AttachmentContentType::text, p_supplierid => @SupplierId::int, p_amountpaid => @AmountPaid::numeric, p_duedate => @DueDate::date)", conn);
                cmd.Parameters.AddWithValue("@SupplierId", (object?)model.SupplierId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@AmountPaid", (object?)model.AmountPaid ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@DueDate", (object?)model.DueDate?.Date ?? DBNull.Value);
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
                cmd.Parameters.Add(new NpgsqlParameter("@AttachmentImage", NpgsqlDbType.Bytea, -1)
                {
                    Value = (object?)model.AttachmentImage ?? DBNull.Value
                });
                cmd.Parameters.Add(new NpgsqlParameter("@AttachmentContentType", NpgsqlDbType.Text, 64)
                {
                    Value = (object?)model.AttachmentContentType ?? DBNull.Value
                });
                cmd.Parameters.AddWithValue("@AttachmentImageSet", model.SetAttachmentImage);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
                conn.Close();
                await SyncExpenseCashAsync(model.FarmId ?? string.Empty, model.ExpenseId, model.PoultryCashAccountId, model.Amount, model.Description, model.UserId, model.ExpenseDate);
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
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spexpense_getbyid(p_expenseid => @ExpenseId::int, p_farmid => @FarmId::uuid)", conn);
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
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spexpense_getall(p_farmid => @FarmId::uuid)", conn);
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
                // Reverse any cash-out this expense posted before removing it.
                await SyncExpenseCashAsync(farmId, expenseId, null, 0m, null, userId);

                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spexpense_delete(p_expenseid => @ExpenseId::int, p_farmid => @FarmId::uuid)", conn);
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
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spexpense_getbyflock(p_flockid => @FlockId::int, p_farmid => @FarmId::uuid)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spexpense_getattachment(p_expenseid => @ExpenseId::int, p_farmid => @FarmId::uuid)", conn);
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

        private static ExpenseModel MapExpense(NpgsqlDataReader reader, string userId)
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
            int? cashAccountId = null;
            if (TryGetOrdinal(reader, "PoultryCashAccountId", out var ordCash) && !reader.IsDBNull(ordCash))
                cashAccountId = ReadIntFlexible(reader, "PoultryCashAccountId");
            var createdDate = TryGetOrdinal(reader, "CreatedDate", out var ordCd) && !reader.IsDBNull(ordCd)
                ? reader.GetDateTime(ordCd)
                : default;
            var resolvedUserId = userId;
            if (TryGetOrdinal(reader, "UserId", out var ordUid) && !reader.IsDBNull(ordUid))
                resolvedUserId = reader.GetString(ordUid);

            // Payment state (migration 238). Read defensively -- a farm whose DB
            // has not had 238 applied yet returns none of these columns, and the
            // page must still render rather than 500.
            int? supplierId = null;
            if (TryGetOrdinal(reader, "SupplierId", out var ordSupId) && !reader.IsDBNull(ordSupId))
                supplierId = ReadIntFlexible(reader, "SupplierId");
            string? supplierName = null;
            if (TryGetOrdinal(reader, "SupplierName", out var ordSupName) && !reader.IsDBNull(ordSupName))
                supplierName = reader.GetString(ordSupName);
            // The SP resolves amountpaid for us, so an absent column -- not a NULL
            // -- is the only "unknown", and unknown means the legacy fully-paid.
            var amountPaid = TryGetOrdinal(reader, "AmountPaid", out var ordPaid) && !reader.IsDBNull(ordPaid)
                ? reader.GetDecimal(ordPaid)
                : amount;
            var balance = TryGetOrdinal(reader, "Balance", out var ordBal) && !reader.IsDBNull(ordBal)
                ? reader.GetDecimal(ordBal)
                : 0m;
            string? paymentStatus = null;
            if (TryGetOrdinal(reader, "PaymentStatus", out var ordStatus) && !reader.IsDBNull(ordStatus))
                paymentStatus = reader.GetString(ordStatus);
            DateTime? dueDate = null;
            if (TryGetOrdinal(reader, "DueDate", out var ordDue) && !reader.IsDBNull(ordDue))
                dueDate = reader.GetDateTime(ordDue);
            string? sourceType = null;
            if (TryGetOrdinal(reader, "SourceType", out var ordSrcT) && !reader.IsDBNull(ordSrcT))
                sourceType = reader.GetString(ordSrcT);
            int? sourceId = null;
            if (TryGetOrdinal(reader, "SourceId", out var ordSrcId) && !reader.IsDBNull(ordSrcId))
                sourceId = ReadIntFlexible(reader, "SourceId");

            return new ExpenseModel
            {
                ExpenseId = ReadIntFlexible(reader, "ExpenseId", "ExpenseID", "Id", "EXPENSEID"),
                ExpenseDate = expenseDate,
                Category = category,
                Description = descOrd,
                Amount = amount,
                PaymentMethod = paymentMethod,
                Supplier = supplier,
                SupplierId = supplierId,
                SupplierName = supplierName,
                AmountPaid = amountPaid,
                Balance = balance,
                PaymentStatus = paymentStatus ?? (balance > 0m ? "PartiallyPaid" : "Paid"),
                DueDate = dueDate,
                SourceType = sourceType,
                SourceId = sourceId,
                FlockId = flockId,
                PoultryCashAccountId = cashAccountId,
                CreatedDate = createdDate,
                UserId = resolvedUserId,
                FarmId = ReadFarmIdString(reader),
                HasAttachmentImage = hasAtt
            };
        }

        private static bool TryGetOrdinal(NpgsqlDataReader reader, string name, out int ordinal)
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

        private static int ReadIntFlexible(NpgsqlDataReader reader, params string[] columns)
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
