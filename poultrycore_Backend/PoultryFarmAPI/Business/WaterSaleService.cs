using System.Data;
using Npgsql;
using System.Text.Json;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class WaterSaleService : IWaterSaleService
    {
        private readonly string _connectionString;

        public WaterSaleService(string connectionString)
        {
            _connectionString = connectionString;
        }

        // Migration 084: routes to spWaterSale_CreateV2 so per-line SellingUnit
        // is honored and stock is deducted in BaseQuantity (sachets) when the
        // product is flagged IsSachetProduct=1. Legacy callers that don't send
        // SellingUnit get the product's default Unit, preserving prior behavior.
        public async Task<int> Create(CreateWaterSaleRequest req)
        {
            var itemsJson = JsonSerializer.Serialize(req.Items.Select(i => new
            {
                i.WaterProductId,
                i.Quantity,
                i.UnitPrice,
                SellingUnit = i.SellingUnit,
            }));

            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            // 458: one transaction -- the sale, and (Edit & repost) its link to the
            // reversed sale it replaces. A refused link leaves no new sale behind.
            await using var tx = await conn.BeginTransactionAsync();
            try
            {
                int newId;
                await using (var cmd = new NpgsqlCommand("SELECT * FROM spwatersale_createv2(p_farmid => @FarmId::text, p_watercustomerid => @WaterCustomerId::int, p_saledate => @SaleDate::timestamp, p_notes => @Notes::text, p_createdby => @CreatedBy::text, p_itemsjson => @ItemsJson::text)", conn, tx))
                {
                    cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
                    cmd.Parameters.AddWithValue("@WaterCustomerId", (object?)req.WaterCustomerId ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@SaleDate", (object?)req.SaleDate ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@CreatedBy", (object?)req.CreatedBy ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@ItemsJson", itemsJson);
                    newId = Convert.ToInt32(await cmd.ExecuteScalarAsync());
                }

                if (req.CorrectsSaleId is int corrects && corrects > 0)
                {
                    await using var link = new NpgsqlCommand(
                        "SELECT spwatersale_linkcorrection(p_farmid => @FarmId::text, p_newsaleid => @New::int, p_correctssaleid => @Old::int, p_by => @By::text)", conn, tx);
                    link.Parameters.AddWithValue("@FarmId", req.FarmId);
                    link.Parameters.AddWithValue("@New", newId);
                    link.Parameters.AddWithValue("@Old", corrects);
                    link.Parameters.AddWithValue("@By", (object?)req.CreatedBy ?? DBNull.Value);
                    await link.ExecuteNonQueryAsync();
                }

                await tx.CommitAsync();
                return newId;
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                throw new SaleRuleException(ex.MessageText, ex);
            }
        }

        // ------------------------------------------------------- 458: reversal

        /// <summary>What reversing the sale would do (jsonb, same shape as poultry's).</summary>
        public Task<string> GetReversalPreview(int saleId, string farmId)
            => ScalarJsonAsync("SELECT spwatersale_reversalpreview(p_farmid => @FarmId::text, p_saleid => @SaleId::int)::text", farmId, saleId);

        /// <summary>The reversal of a reversed sale, or null.</summary>
        public async Task<string?> GetReversal(int saleId, string farmId)
        {
            var json = await ScalarJsonAsync("SELECT spwatersale_reversalget(p_farmid => @FarmId::text, p_saleid => @SaleId::int)::text", farmId, saleId);
            return string.IsNullOrEmpty(json) || json == "null" ? null : json;
        }

        /// <summary>
        /// Reverses a saved sale in one transaction (spwatersale_reverse). A refusal
        /// comes back as <see cref="SaleRuleException"/> (Stale = preview out of date).
        /// </summary>
        public async Task<int> Reverse(int saleId, SaleReverseRequest req)
        {
            try
            {
                await using var conn = new NpgsqlConnection(_connectionString);
                await conn.OpenAsync();
                await using var cmd = new NpgsqlCommand(
                    "SELECT spwatersale_reverse(p_farmid => @FarmId::text, p_saleid => @SaleId::int, " +
                    "p_reasoncode => @Code::text, p_reason => @Reason::text, p_handling => @Handling::jsonb, " +
                    "p_expectedfingerprint => @Fp::text, p_idempotencykey => @Key::text, p_reversedby => @By::text)", conn);
                cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
                cmd.Parameters.AddWithValue("@SaleId", saleId);
                cmd.Parameters.AddWithValue("@Code", (object?)req.ReasonCode ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Reason", req.Reason ?? string.Empty);
                cmd.Parameters.AddWithValue("@Handling",
                    JsonSerializer.Serialize(req.PaymentHandling ?? new Dictionary<string, string>()));
                cmd.Parameters.AddWithValue("@Fp", (object?)req.ExpectedFingerprint ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Key", (object?)req.IdempotencyKey ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@By", (object?)req.UserId ?? DBNull.Value);
                return Convert.ToInt32(await cmd.ExecuteScalarAsync());
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                throw new SaleRuleException(ex.MessageText, ex) { Stale = ex.Hint == "stale-preview" };
            }
        }

        private async Task<string> ScalarJsonAsync(string sql, string farmId, int saleId)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@SaleId", saleId);
            var o = await cmd.ExecuteScalarAsync();
            return o is null || o is DBNull ? "null" : (string)o;
        }

        public async Task<WaterSaleModel?> GetById(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatersale_getbyid_rs1(p_watersaleid => @WaterSaleId::int, p_farmid => @FarmId::text); SELECT * FROM spwatersale_getbyid_rs2(p_watersaleid => @WaterSaleId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@WaterSaleId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();

            if (!await reader.ReadAsync()) return null;
            var sale = ReadHeader(reader);

            if (await reader.NextResultAsync())
            {
                while (await reader.ReadAsync()) sale.Items.Add(ReadItem(reader));
            }

            return sale;
        }

        public async Task<List<WaterSaleModel>> GetAll(string farmId)
        {
            var list = new List<WaterSaleModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatersale_getall(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadHeader(reader));
            return list;
        }

        public async Task Cancel(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatersale_cancel(p_watersaleid => @WaterSaleId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@WaterSaleId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // Hard-delete a direct sale (restores stock, removes payments + items).
        // The SP rejects delivery-sourced sales.
        public async Task Delete(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatersale_delete(p_watersaleid => @WaterSaleId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@WaterSaleId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterSaleModel ReadHeader(NpgsqlDataReader r) => new()
        {
            WaterSaleId     = r.GetInt32(r.GetOrdinal("WaterSaleId")),
            FarmId          = r.GetString(r.GetOrdinal("FarmId")),
            WaterCustomerId = r.IsDBNull(r.GetOrdinal("WaterCustomerId")) ? null : r.GetInt32(r.GetOrdinal("WaterCustomerId")),
            CustomerName    = r.IsDBNull(r.GetOrdinal("CustomerName")) ? null : r.GetString(r.GetOrdinal("CustomerName")),
            SaleDate        = r.GetDateTime(r.GetOrdinal("SaleDate")),
            TotalAmount     = r.GetDecimal(r.GetOrdinal("TotalAmount")),
            AmountPaid      = r.GetDecimal(r.GetOrdinal("AmountPaid")),
            Balance         = r.GetDecimal(r.GetOrdinal("Balance")),
            Status          = r.GetString(r.GetOrdinal("Status")),
            Notes           = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedDate     = r.GetDateTime(r.GetOrdinal("CreatedDate")),
            CreatedBy       = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            UpdatedDate     = r.IsDBNull(r.GetOrdinal("UpdatedDate")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedDate")),
            // Migration 111 — where the sale came from (NULL/Direct vs DeliveryRun).
            SourceType      = HasCol(r, "SourceType") && !r.IsDBNull(r.GetOrdinal("SourceType")) ? r.GetString(r.GetOrdinal("SourceType")) : null,
            SourceId        = HasCol(r, "SourceId")   && !r.IsDBNull(r.GetOrdinal("SourceId"))   ? r.GetInt32(r.GetOrdinal("SourceId"))   : (int?)null,
            // Migration 225 — derived from the sale's payments ("Mixed" when
            // several methods were used). Absent on a pre-225 database.
            PaymentMethod   = HasCol(r, "PaymentMethod") && !r.IsDBNull(r.GetOrdinal("PaymentMethod")) ? r.GetString(r.GetOrdinal("PaymentMethod")) : null,
            // Migration 458 -- the reversal, when there is one. Absent before 458.
            SaleReversalId    = HasCol(r, "SaleReversalId")    && !r.IsDBNull(r.GetOrdinal("SaleReversalId"))    ? r.GetInt32(r.GetOrdinal("SaleReversalId"))     : null,
            ReversalNumber    = HasCol(r, "ReversalNumber")    && !r.IsDBNull(r.GetOrdinal("ReversalNumber"))    ? r.GetString(r.GetOrdinal("ReversalNumber"))    : null,
            ReversedAt        = HasCol(r, "ReversedAt")        && !r.IsDBNull(r.GetOrdinal("ReversedAt"))        ? r.GetDateTime(r.GetOrdinal("ReversedAt"))      : null,
            ReversedBy        = HasCol(r, "ReversedBy")        && !r.IsDBNull(r.GetOrdinal("ReversedBy"))        ? r.GetString(r.GetOrdinal("ReversedBy"))        : null,
            ReversalReason    = HasCol(r, "ReversalReason")    && !r.IsDBNull(r.GetOrdinal("ReversalReason"))    ? r.GetString(r.GetOrdinal("ReversalReason"))    : null,
            CorrectsSaleId    = HasCol(r, "CorrectsSaleId")    && !r.IsDBNull(r.GetOrdinal("CorrectsSaleId"))    ? r.GetInt32(r.GetOrdinal("CorrectsSaleId"))     : null,
            CorrectedBySaleId = HasCol(r, "CorrectedBySaleId") && !r.IsDBNull(r.GetOrdinal("CorrectedBySaleId")) ? r.GetInt32(r.GetOrdinal("CorrectedBySaleId"))  : null,
        };

        private static WaterSaleItemModel ReadItem(NpgsqlDataReader r) => new()
        {
            WaterSaleItemId = r.GetInt32(r.GetOrdinal("WaterSaleItemId")),
            WaterSaleId     = r.GetInt32(r.GetOrdinal("WaterSaleId")),
            WaterProductId  = r.GetInt32(r.GetOrdinal("WaterProductId")),
            ProductName     = r.IsDBNull(r.GetOrdinal("ProductName")) ? null : r.GetString(r.GetOrdinal("ProductName")),
            Quantity        = r.GetInt32(r.GetOrdinal("Quantity")),
            UnitPrice       = r.GetDecimal(r.GetOrdinal("UnitPrice")),
            LineTotal       = r.GetDecimal(r.GetOrdinal("LineTotal")),
            // Migration 084 — new selling-unit columns; absent on older sales.
            SellingUnit     = HasCol(r, "SellingUnit")  && !r.IsDBNull(r.GetOrdinal("SellingUnit"))  ? r.GetString(r.GetOrdinal("SellingUnit"))  : null,
            BaseUnit        = HasCol(r, "BaseUnit")     && !r.IsDBNull(r.GetOrdinal("BaseUnit"))     ? r.GetString(r.GetOrdinal("BaseUnit"))     : null,
            BaseQuantity    = HasCol(r, "BaseQuantity") && !r.IsDBNull(r.GetOrdinal("BaseQuantity")) ? r.GetDecimal(r.GetOrdinal("BaseQuantity")) : null,
        };

        private static bool HasCol(NpgsqlDataReader r, string name)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (r.GetName(i).Equals(name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }
}
