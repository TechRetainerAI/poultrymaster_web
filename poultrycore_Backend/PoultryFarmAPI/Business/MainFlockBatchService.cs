using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>506: the database refused a batch delete for a business reason.</summary>
    public class BatchDeleteBlockedException : Exception
    {
        public BatchDeleteBlockedException(string message, string? hint) : base(message) { Hint = hint; }
        /// <summary>BATCH_HAS_FLOCKS (confirm and retry) or BATCH_DELETE_BLOCKED.</summary>
        public string? Hint { get; }
    }

    // Concrete implementation using ADO.NET and Stored Procedures, mirroring CustomerService.
    public class MainFlockBatchService : IMainFlockBatchService
    {
        private readonly string _connectionString;

        public MainFlockBatchService(string connectionString)
        {
            _connectionString = connectionString;
        }

        private static bool HasColumn(NpgsqlDataReader reader, string name)
        {
            for (int i = 0; i < reader.FieldCount; i++)
            {
                if (string.Equals(reader.GetName(i), name, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }

        private MainFlockBatchModel MapFromReader(NpgsqlDataReader reader)
        {
            var model = new MainFlockBatchModel
            {
                BatchId = reader.GetInt32(reader.GetOrdinal("BatchId")),
                FarmId = reader.GetString(reader.GetOrdinal("FarmId")),
                UserId = reader.GetString(reader.GetOrdinal("UserId")),
                BatchCode = reader.GetString(reader.GetOrdinal("BatchCode")),
                BatchName = reader.GetString(reader.GetOrdinal("BatchName")),
                Breed = reader.GetString(reader.GetOrdinal("Breed")),
                NumberOfBirds = reader.GetInt32(reader.GetOrdinal("NumberOfBirds")),
                StartDate = reader.GetDateTime(reader.GetOrdinal("StartDate")),
                CreatedDate = reader.GetDateTime(reader.GetOrdinal("CreatedDate"))
            };

            // Optional columns added in migration 021 — tolerate older sp shapes during rollout.
            if (HasColumn(reader, "Status"))
            {
                int o = reader.GetOrdinal("Status");
                model.Status = reader.IsDBNull(o) ? "active" : reader.GetString(o);
            }
            if (HasColumn(reader, "CostPerChick"))
            {
                int o = reader.GetOrdinal("CostPerChick");
                model.CostPerChick = reader.IsDBNull(o) ? 0m : reader.GetDecimal(o);
            }
            if (HasColumn(reader, "DollarConversionRate"))
            {
                int o = reader.GetOrdinal("DollarConversionRate");
                model.DollarConversionRate = reader.IsDBNull(o) ? (decimal?)null : reader.GetDecimal(o);
            }
            if (HasColumn(reader, "TotalCost"))
            {
                int o = reader.GetOrdinal("TotalCost");
                model.TotalCost = reader.IsDBNull(o) ? 0m : reader.GetDecimal(o);
            }
            if (HasColumn(reader, "AmountPaid"))
            {
                int o = reader.GetOrdinal("AmountPaid");
                model.AmountPaid = reader.IsDBNull(o) ? 0m : reader.GetDecimal(o);
            }
            if (HasColumn(reader, "SupplierType"))
            {
                int o = reader.GetOrdinal("SupplierType");
                model.SupplierType = reader.IsDBNull(o) ? string.Empty : reader.GetString(o);
            }
            if (HasColumn(reader, "SupplierId"))
            {
                int o = reader.GetOrdinal("SupplierId");
                model.SupplierId = reader.IsDBNull(o) ? (int?)null : reader.GetInt32(o);
            }
            if (HasColumn(reader, "SupplierName"))
            {
                int o = reader.GetOrdinal("SupplierName");
                model.SupplierName = reader.IsDBNull(o) ? string.Empty : reader.GetString(o);
            }
            if (HasColumn(reader, "Notes"))
            {
                int o = reader.GetOrdinal("Notes");
                model.Notes = reader.IsDBNull(o) ? null : reader.GetString(o);
            }
            // Historical-purchase marker added in migration 326 — tolerate older sp shapes.
            if (HasColumn(reader, "IsHistorical"))
            {
                int o = reader.GetOrdinal("IsHistorical");
                model.IsHistorical = reader.IsDBNull(o) ? false : reader.GetBoolean(o);
            }
            // Cash account added in migrations 330/331 — tolerate older sp shapes.
            if (HasColumn(reader, "PoultryCashAccountId"))
            {
                int o = reader.GetOrdinal("PoultryCashAccountId");
                model.PoultryCashAccountId = reader.IsDBNull(o) ? (int?)null : reader.GetInt32(o);
            }
            if (HasColumn(reader, "PoultryCashAccountName"))
            {
                int o = reader.GetOrdinal("PoultryCashAccountName");
                model.PoultryCashAccountName = reader.IsDBNull(o) ? null : reader.GetString(o);
            }
            // Procurement dates added in migration 150 — tolerate older sp shapes.
            if (HasColumn(reader, "OrderPlacementDate"))
            {
                int o = reader.GetOrdinal("OrderPlacementDate");
                model.OrderPlacementDate = reader.IsDBNull(o) ? (DateTime?)null : reader.GetDateTime(o);
            }
            if (HasColumn(reader, "EstimatedArrivalDate"))
            {
                int o = reader.GetOrdinal("EstimatedArrivalDate");
                model.EstimatedArrivalDate = reader.IsDBNull(o) ? (DateTime?)null : reader.GetDateTime(o);
            }

            return model;
        }

        /// <summary>
        /// The one place the batch insert is written. Both the ordinary Flock
        /// Purchases form and the Farm Setup wizard go through here, so there is
        /// exactly one definition of what creating a batch means -- the only
        /// difference between them is whether a transaction is passed in.
        /// </summary>
        internal static NpgsqlCommand BuildInsertCommand(NpgsqlConnection conn, NpgsqlTransaction? transaction, MainFlockBatchModel model)
        {
            var cmd = new NpgsqlCommand("SELECT * FROM spmainflockbatch_insert(p_userid => @UserId::text, p_farmid => @FarmId::text, p_batchcode => @BatchCode::text, p_batchname => @BatchName::text, p_breed => @Breed::text, p_numberofbirds => @NumberOfBirds::int, p_startdate => @StartDate::timestamp, p_status => @Status::text, p_costperchick => @CostPerChick::numeric, p_totalcost => @TotalCost::numeric, p_amountpaid => @AmountPaid::numeric, p_suppliertype => @SupplierType::text, p_supplierid => @SupplierId::int, p_notes => @Notes::text, p_dollarconversionrate => @DollarConversionRate::numeric, p_orderplacementdate => @OrderPlacementDate::date, p_estimatedarrivaldate => @EstimatedArrivalDate::date, p_ishistorical => @IsHistorical::boolean, p_poultrycashaccountid => @PoultryCashAccountId::int)", conn, transaction);
            cmd.Parameters.AddWithValue("@UserId", model.UserId);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@BatchCode", model.BatchCode);
            cmd.Parameters.AddWithValue("@BatchName", model.BatchName);
            cmd.Parameters.AddWithValue("@Breed", model.Breed);
            cmd.Parameters.AddWithValue("@NumberOfBirds", model.NumberOfBirds);
            cmd.Parameters.AddWithValue("@StartDate", model.StartDate);
            cmd.Parameters.AddWithValue("@Status", (object?)model.Status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CostPerChick", model.CostPerChick);
            cmd.Parameters.AddWithValue("@TotalCost", model.TotalCost);
            cmd.Parameters.AddWithValue("@AmountPaid", model.AmountPaid);
            cmd.Parameters.AddWithValue("@SupplierType", (object?)model.SupplierType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SupplierId", (object?)model.SupplierId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)model.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DollarConversionRate", (object?)model.DollarConversionRate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OrderPlacementDate", (object?)model.OrderPlacementDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EstimatedArrivalDate", (object?)model.EstimatedArrivalDate ?? DBNull.Value);
            // NULL is meaningful, and differs between the two calls: the insert
            // coalesces it to false (an ordinary purchase is a new one), the
            // update coalesces it to the batch's current value so the everyday
            // edit form cannot silently un-flag a historical batch.
            cmd.Parameters.AddWithValue("@IsHistorical", (object?)model.IsHistorical ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", (object?)model.PoultryCashAccountId ?? DBNull.Value);
            return cmd;
        }

        public async Task<int> Insert(MainFlockBatchModel model)
        {
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                await conn.OpenAsync();
                using var cmd = BuildInsertCommand(conn, null, model);
                var result = await cmd.ExecuteScalarAsync();
                // ExecuteScalarAsync returns the identity value (BatchId) from the stored procedure.
                return Convert.ToInt32(result);
            }
            catch (PostgresException)
            {
                // Let PostgresException propagate so GlobalExceptionMiddleware surfaces the
                // real SQL number/message (e.g. "too many arguments", "Invalid column")
                // instead of collapsing it into an opaque wrapper.
                throw;
            }
            catch (Exception ex)
            {
                throw new Exception("Error inserting Main Flock Batch record.", ex);
            }
        }

        public async Task<List<int>> InsertBulk(IReadOnlyList<MainFlockBatchModel> models)
        {
            var ids = new List<int>();
            if (models == null || models.Count == 0) return ids;

            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            using var tx = await conn.BeginTransactionAsync();
            try
            {
                // Same command, same stored function as Insert: the payment,
                // cash-account and supplier-ledger side effects are identical to
                // creating each batch on its own.
                foreach (var model in models)
                {
                    using var cmd = BuildInsertCommand(conn, tx, model);
                    ids.Add(Convert.ToInt32(await cmd.ExecuteScalarAsync()));
                }
                await tx.CommitAsync();
            }
            catch
            {
                try { await tx.RollbackAsync(); } catch { /* connection already gone */ }
                throw;
            }
            return ids;
        }

        public async Task Update(MainFlockBatchModel model)
        {
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spmainflockbatch_update(p_batchid => @BatchId::int, p_userid => @UserId::text, p_farmid => @FarmId::text, p_batchcode => @BatchCode::text, p_batchname => @BatchName::text, p_breed => @Breed::text, p_numberofbirds => @NumberOfBirds::int, p_startdate => @StartDate::timestamp, p_status => @Status::text, p_costperchick => @CostPerChick::numeric, p_totalcost => @TotalCost::numeric, p_amountpaid => @AmountPaid::numeric, p_suppliertype => @SupplierType::text, p_supplierid => @SupplierId::int, p_notes => @Notes::text, p_dollarconversionrate => @DollarConversionRate::numeric, p_orderplacementdate => @OrderPlacementDate::date, p_estimatedarrivaldate => @EstimatedArrivalDate::date, p_ishistorical => @IsHistorical::boolean, p_poultrycashaccountid => @PoultryCashAccountId::int)", conn);
                cmd.Parameters.AddWithValue("@BatchId", model.BatchId);
                cmd.Parameters.AddWithValue("@UserId", model.UserId);
                cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
                cmd.Parameters.AddWithValue("@BatchCode", model.BatchCode);
                cmd.Parameters.AddWithValue("@BatchName", model.BatchName);
                cmd.Parameters.AddWithValue("@Breed", model.Breed);
                cmd.Parameters.AddWithValue("@NumberOfBirds", model.NumberOfBirds);
                cmd.Parameters.AddWithValue("@StartDate", model.StartDate);
                cmd.Parameters.AddWithValue("@Status", (object?)model.Status ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@CostPerChick", model.CostPerChick);
                cmd.Parameters.AddWithValue("@TotalCost", model.TotalCost);
                cmd.Parameters.AddWithValue("@AmountPaid", model.AmountPaid);
                cmd.Parameters.AddWithValue("@SupplierType", (object?)model.SupplierType ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@SupplierId", (object?)model.SupplierId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Notes", (object?)model.Notes ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@DollarConversionRate", (object?)model.DollarConversionRate ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@OrderPlacementDate", (object?)model.OrderPlacementDate ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@EstimatedArrivalDate", (object?)model.EstimatedArrivalDate ?? DBNull.Value);
                // NULL here means "leave the flag as it is" -- see the insert above.
                cmd.Parameters.AddWithValue("@IsHistorical", (object?)model.IsHistorical ?? DBNull.Value);
                // NULL leaves the stored account, 0 clears it, anything else sets it (331).
                cmd.Parameters.AddWithValue("@PoultryCashAccountId", (object?)model.PoultryCashAccountId ?? DBNull.Value);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (PostgresException)
            {
                throw;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error updating Main Flock Batch ID={model.BatchId}.", ex);
            }
        }

        public async Task<MainFlockBatchModel?> GetById(int batchId, string userId, string farmId)
        {
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spmainflockbatch_getbyid(p_batchid => @BatchId::int, p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);
                cmd.Parameters.AddWithValue("@BatchId", batchId);
                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return MapFromReader(reader);
                }
                return null;
            }
            catch (Exception ex)
            {
                throw new Exception($"Error retrieving Main Flock Batch ID={batchId}.", ex);
            }
        }

        public async Task<List<MainFlockBatchModel>> GetAll(string userId, string farmId)
        {
            try
            {
                var list = new List<MainFlockBatchModel>();
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spmainflockbatch_getall(p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);
                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);

                await conn.OpenAsync();
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(MapFromReader(reader));
                }
                return list;
            }
            catch (Exception ex)
            {
                throw new Exception("Error retrieving all Main Flock Batches.", ex);
            }
        }

        public async Task Delete(int batchId, string userId, string farmId, bool deleteFlocks = false)
        {
            try
            {
                using var conn = new NpgsqlConnection(_connectionString);
                using var cmd = new NpgsqlCommand("SELECT * FROM spmainflockbatch_delete(p_batchid => @BatchId::int, p_userid => @UserId::text, p_farmid => @FarmId::text, p_deleteflocks => @DeleteFlocks::boolean)", conn);
                cmd.Parameters.AddWithValue("@BatchId", batchId);
                cmd.Parameters.AddWithValue("@UserId", userId);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@DeleteFlocks", deleteFlocks);

                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                // 506: a rule refusal (flock with records, supplier payment, unconfirmed flocks) -- the caller shows it.
                throw new BatchDeleteBlockedException(ex.MessageText, ex.Hint);
            }
            catch (Exception ex)
            {
                throw new Exception($"Error deleting Main Flock Batch ID={batchId}.", ex);
            }
        }

        // 507: reversal (preview -> reverse -> record), shown in the batch page's Reversed list.
        public Task<string> GetReversalPreview(int batchId, string farmId)
            => ScalarJson("SELECT sppoultrybatch_reversalpreview(p_farmid => @FarmId::text, p_batchid => @Id::int)::text", farmId, batchId);

        public async Task<string?> GetReversal(int batchReversalId, string farmId)
        {
            var json = await ScalarJson("SELECT sppoultrybatch_reversalget(p_farmid => @FarmId::text, p_batchreversalid => @Id::int)::text", farmId, batchReversalId);
            return string.IsNullOrEmpty(json) || json == "null" ? null : json;
        }

        public Task<string> GetReversals(string farmId)
            => ScalarJson("SELECT sppoultrybatchreversal_list(p_farmid => @FarmId::text)::text", farmId, 0);

        public async Task<int> Reverse(int batchId, string farmId, FlockBatchReverseRequest req, string? reversedBy)
        {
            try
            {
                await using var conn = new NpgsqlConnection(_connectionString);
                await conn.OpenAsync();
                await using var cmd = new NpgsqlCommand(
                    "SELECT sppoultrybatch_reverse(p_farmid => @FarmId::text, p_batchid => @Id::int, p_reasoncode => @Code::text, " +
                    "p_reason => @Reason::text, p_handling => @Handling::jsonb, p_deleteflocks => @DeleteFlocks::boolean, " +
                    "p_expectedfingerprint => @Fp::text, p_idempotencykey => @Key::text, p_reversedby => @By::text)", conn);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@Id", batchId);
                cmd.Parameters.AddWithValue("@Code", (object?)req.ReasonCode ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Reason", req.Reason ?? string.Empty);
                cmd.Parameters.AddWithValue("@Handling",
                    System.Text.Json.JsonSerializer.Serialize(req.PaymentHandling ?? new Dictionary<string, string>()));
                cmd.Parameters.AddWithValue("@DeleteFlocks", req.DeleteFlocks);
                cmd.Parameters.AddWithValue("@Fp", (object?)req.ExpectedFingerprint ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Key", (object?)req.IdempotencyKey ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@By", (object?)reversedBy ?? DBNull.Value);
                return Convert.ToInt32(await cmd.ExecuteScalarAsync());
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                throw new SaleRuleException(ex.MessageText, ex) { Stale = ex.Hint == "stale-preview" };
            }
        }

        private async Task<string> ScalarJson(string sql, string farmId, int id)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            if (sql.Contains("@Id")) cmd.Parameters.AddWithValue("@Id", id);
            var o = await cmd.ExecuteScalarAsync();
            return o is null || o is DBNull ? "null" : (string)o;
        }

        // 506: what deleting the batch would do -- its flocks, what blocks it, the money removed.
        public async Task<string> GetDeletePreview(int batchId, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT fnpoultrybatch_deletepreview(p_farmid => @FarmId::text, p_batchid => @BatchId::int)::text", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@BatchId", batchId);
            await conn.OpenAsync();
            var o = await cmd.ExecuteScalarAsync();
            return o is null || o is DBNull ? "null" : (string)o;
        }

        public async Task<decimal> PayBalance(int batchId, string farmId, decimal amount, string? paymentMethod, DateTime? paymentDate, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spmainflockbatch_paybalance(p_batchid => @BatchId::int, p_farmid => @FarmId::text, p_amount => @Amount::numeric, p_paymentmethod => @PaymentMethod::text, p_paymentdate => @PaymentDate::timestamp, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@BatchId", batchId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Amount", amount);
            cmd.Parameters.AddWithValue("@PaymentMethod", (object?)paymentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaymentDate", (object?)paymentDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);

            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return result is null || result == DBNull.Value ? 0m : Convert.ToDecimal(result);
        }
    }
}
