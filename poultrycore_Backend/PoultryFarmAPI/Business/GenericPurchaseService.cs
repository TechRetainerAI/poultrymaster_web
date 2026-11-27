using System.Data;
using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericPurchaseService : IGenericPurchaseService
    {
        private readonly string _connectionString;
        public GenericPurchaseService(string connectionString) => _connectionString = connectionString;

        // ====================================================================
        // Reads
        // ====================================================================
        public async Task<List<GenericPurchaseModel>> GetAllAsync(string farmId, string? status)
        {
            var list = new List<GenericPurchaseModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpurchase_getall(p_farmid => @FarmId::text, p_status => @Status::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadHeader(reader));
            return list;
        }

        public async Task<GenericPurchaseModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpurchase_getbyid_rs1(p_genericpurchaseid => @GenericPurchaseId::int, p_farmid => @FarmId::text); SELECT * FROM spgenericpurchase_getbyid_rs2(p_genericpurchaseid => @GenericPurchaseId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@GenericPurchaseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();

            GenericPurchaseModel? purchase = null;
            if (await reader.ReadAsync()) purchase = ReadHeader(reader);
            if (purchase is null) return null;

            if (await reader.NextResultAsync())
            {
                while (await reader.ReadAsync()) purchase.Items.Add(ReadItem(reader));
            }
            return purchase;
        }

        // ====================================================================
        // Insert with items via TVP
        // ====================================================================
        public async Task<int> InsertAsync(string farmId, GenericPurchaseCreateRequest req, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            var insertCall = "spgenericpurchase_insert(p_farmid => @FarmId::text, p_purchasedate => @PurchaseDate::timestamp, p_genericsupplierid => @GenericSupplierId::int, p_branchid => @BranchId::int, p_headerdiscountamount => @HeaderDiscountAmount::numeric, p_taxamount => @TaxAmount::numeric, p_amountpaid => @AmountPaid::numeric, p_paymentmethod => @PaymentMethod::text, p_genericcashaccountid => @GenericCashAccountId::int, p_invoicenumber => @InvoiceNumber::text, p_receipturl => @ReceiptUrl::text, p_receivedbystaffid => @ReceivedByStaffId::int, p_notes => @Notes::text, p_createdby => @CreatedBy::text, p_items => @Items::jsonb)";
            using var cmd = new NpgsqlCommand(GenericProjectAttach.Has(req.Projects)
                ? GenericProjectAttach.WrapInsert(insertCall, "Purchase")
                : "SELECT * FROM " + insertCall, conn);
            if (GenericProjectAttach.Has(req.Projects)) GenericProjectAttach.AddParams(cmd, farmId, req.Projects, createdBy);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PurchaseDate", (object?)req.PurchaseDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@GenericSupplierId", (object?)req.GenericSupplierId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BranchId", (object?)req.BranchId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@HeaderDiscountAmount", req.HeaderDiscountAmount);
            cmd.Parameters.AddWithValue("@TaxAmount", req.TaxAmount);
            cmd.Parameters.AddWithValue("@AmountPaid", req.AmountPaid);
            cmd.Parameters.AddWithValue("@PaymentMethod", (object?)req.PaymentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", (object?)req.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@InvoiceNumber", (object?)req.InvoiceNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ReceiptUrl", (object?)req.ReceiptUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ReceivedByStaffId", (object?)req.ReceivedByStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);

            // Items: the SQL Server TVP (dbo.GenericPurchaseItemTvp) became a jsonb
            // array read with jsonb_to_recordset, so keys must be lowercase.
            cmd.Parameters.Add(new NpgsqlParameter("@Items", NpgsqlTypes.NpgsqlDbType.Jsonb)
            {
                Value = BuildItemsJson(req.Items),
            });

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        // Keys must match the jsonb_to_recordset column list in spgenericpurchase_insert.
        private static string BuildItemsJson(IEnumerable<GenericPurchaseItemModel> items)
            => System.Text.Json.JsonSerializer.Serialize(items.Select(i => new
            {
                genericproductid = i.GenericProductId,
                description      = i.Description,
                quantity         = i.Quantity,
                unitcost         = i.UnitCost,
                discountamount   = i.DiscountAmount,
                notes            = i.Notes,
                purchaseunit     = i.PurchaseUnit,
                unitfactor       = i.UnitFactor > 0 ? i.UnitFactor : 1m,
            }));

        // Draft only (migration 472): rewrites the header and replaces every line.
        public async Task UpdateAsync(int id, string farmId, GenericPurchaseCreateRequest req)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            var updateCall = "spgenericpurchase_update(p_genericpurchaseid => @Id::int, p_farmid => @FarmId::text, p_purchasedate => @PurchaseDate::timestamp, p_genericsupplierid => @GenericSupplierId::int, p_headerdiscountamount => @HeaderDiscountAmount::numeric, p_taxamount => @TaxAmount::numeric, p_amountpaid => @AmountPaid::numeric, p_paymentmethod => @PaymentMethod::text, p_genericcashaccountid => @GenericCashAccountId::int, p_invoicenumber => @InvoiceNumber::text, p_notes => @Notes::text, p_items => @Items::jsonb)";
            // 483: the update re-creates every line; attach carries their projects over.
            using var cmd = new NpgsqlCommand(GenericProjectAttach.WrapUpdate(updateCall, "Purchase"), conn);
            GenericProjectAttach.AddParams(cmd, farmId, req.Projects, req.UpdatedByForProjects, id);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PurchaseDate", (object?)req.PurchaseDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@GenericSupplierId", (object?)req.GenericSupplierId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@HeaderDiscountAmount", req.HeaderDiscountAmount);
            cmd.Parameters.AddWithValue("@TaxAmount", req.TaxAmount);
            cmd.Parameters.AddWithValue("@AmountPaid", req.AmountPaid);
            cmd.Parameters.AddWithValue("@PaymentMethod", (object?)req.PaymentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", (object?)req.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@InvoiceNumber", (object?)req.InvoiceNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.Add(new NpgsqlParameter("@Items", NpgsqlTypes.NpgsqlDbType.Jsonb) { Value = BuildItemsJson(req.Items) });
            await conn.OpenAsync();
            await cmd.ExecuteScalarAsync();
        }

        // ====================================================================
        // Workflow
        // ====================================================================
        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpurchase_approve(p_genericpurchaseid => @GenericPurchaseId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", conn);
            cmd.Parameters.AddWithValue("@GenericPurchaseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId, string? cancelledBy, string? reason)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericpurchase_cancel(p_genericpurchaseid => @GenericPurchaseId::int, p_farmid => @FarmId::text, p_cancelledby => @CancelledBy::text, p_reason => @Reason::text)", conn);
            cmd.Parameters.AddWithValue("@GenericPurchaseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@CancelledBy", (object?)cancelledBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ====================================================================
        // Helpers
        // ====================================================================
        private static GenericPurchaseModel ReadHeader(NpgsqlDataReader r) => new()
        {
            GenericPurchaseId      = r.GetInt32(r.GetOrdinal("GenericPurchaseId")),
            FarmId                 = r.GetString(r.GetOrdinal("FarmId")),
            GenericSupplierId      = r.IsDBNull(r.GetOrdinal("GenericSupplierId")) ? null : r.GetInt32(r.GetOrdinal("GenericSupplierId")),
            SupplierName           = r.IsDBNull(r.GetOrdinal("SupplierName")) ? null : r.GetString(r.GetOrdinal("SupplierName")),
            PurchaseDate           = r.GetDateTime(r.GetOrdinal("PurchaseDate")),
            BranchId               = r.IsDBNull(r.GetOrdinal("BranchId")) ? null : r.GetInt32(r.GetOrdinal("BranchId")),
            SubtotalAmount         = r.GetDecimal(r.GetOrdinal("SubtotalAmount")),
            DiscountAmount         = r.GetDecimal(r.GetOrdinal("DiscountAmount")),
            TaxAmount              = r.GetDecimal(r.GetOrdinal("TaxAmount")),
            TotalAmount            = r.GetDecimal(r.GetOrdinal("TotalAmount")),
            AmountPaid             = r.GetDecimal(r.GetOrdinal("AmountPaid")),
            Balance                = r.GetDecimal(r.GetOrdinal("Balance")),
            PaymentStatus          = r.GetString(r.GetOrdinal("PaymentStatus")),
            PaymentMethod          = r.IsDBNull(r.GetOrdinal("PaymentMethod")) ? null : r.GetString(r.GetOrdinal("PaymentMethod")),
            GenericCashAccountId   = r.IsDBNull(r.GetOrdinal("GenericCashAccountId")) ? null : r.GetInt32(r.GetOrdinal("GenericCashAccountId")),
            InvoiceNumber          = r.IsDBNull(r.GetOrdinal("InvoiceNumber")) ? null : r.GetString(r.GetOrdinal("InvoiceNumber")),
            ReceiptUrl             = r.IsDBNull(r.GetOrdinal("ReceiptUrl")) ? null : r.GetString(r.GetOrdinal("ReceiptUrl")),
            ReceivedByStaffId      = r.IsDBNull(r.GetOrdinal("ReceivedByStaffId")) ? null : r.GetInt32(r.GetOrdinal("ReceivedByStaffId")),
            Status                 = r.GetString(r.GetOrdinal("Status")),
            Notes                  = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy              = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy             = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt             = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            CancelledBy            = r.IsDBNull(r.GetOrdinal("CancelledBy")) ? null : r.GetString(r.GetOrdinal("CancelledBy")),
            CancelledAt            = r.IsDBNull(r.GetOrdinal("CancelledAt")) ? null : r.GetDateTime(r.GetOrdinal("CancelledAt")),
            CancellationReason     = r.IsDBNull(r.GetOrdinal("CancellationReason")) ? null : r.GetString(r.GetOrdinal("CancellationReason")),
            CreatedAt              = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt              = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
            // 500: only the list returns these, so read them only when the column is there.
            PurchaseReversalId     = Optional(r, "PurchaseReversalId") is int rid ? rid : null,
            ReversalNumber         = Optional(r, "ReversalNumber") as string,
        };

        private static object? Optional(NpgsqlDataReader r, string name)
        {
            for (var i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), name, StringComparison.OrdinalIgnoreCase))
                    return r.IsDBNull(i) ? null : r.GetValue(i);
            return null;
        }

        // ====================================================================
        // 500: reversal, same JSON shape as Water / Poultry so the shared
        // Reverse Purchase dialog serves Generic too.
        // ====================================================================
        public Task<string> GetReversalPreviewAsync(int id, string farmId)
            => ScalarJsonAsync("SELECT spgenericpurchase_reversalpreview(p_farmid => @FarmId::text, p_purchaseid => @Id::int)::text", farmId, id);

        public async Task<string?> GetReversalAsync(int id, string farmId)
        {
            var json = await ScalarJsonAsync("SELECT spgenericpurchase_reversalget(p_farmid => @FarmId::text, p_purchaseid => @Id::int)::text", farmId, id);
            return string.IsNullOrEmpty(json) || json == "null" ? null : json;
        }

        public async Task<int> ReverseAsync(int id, string farmId, GenericPurchaseReverseRequest req, string? reversedBy)
        {
            try
            {
                await using var conn = new NpgsqlConnection(_connectionString);
                await conn.OpenAsync();
                await using var cmd = new NpgsqlCommand(
                    "SELECT spgenericpurchase_reverse(p_farmid => @FarmId::text, p_purchaseid => @Id::int, p_reasoncode => @Code::text, " +
                    "p_reason => @Reason::text, p_handling => @Handling::jsonb, p_expectedfingerprint => @Fp::text, " +
                    "p_idempotencykey => @Key::text, p_reversedby => @By::text)", conn);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@Id", id);
                cmd.Parameters.AddWithValue("@Code", (object?)req.ReasonCode ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Reason", req.Reason ?? string.Empty);
                cmd.Parameters.AddWithValue("@Handling",
                    System.Text.Json.JsonSerializer.Serialize(req.PaymentHandling ?? new Dictionary<string, string>()));
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

        private async Task<string> ScalarJsonAsync(string sql, string farmId, int id)
        {
            await using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", id);
            var o = await cmd.ExecuteScalarAsync();
            return o is null || o is DBNull ? "null" : (string)o;
        }

        private static GenericPurchaseItemModel ReadItem(NpgsqlDataReader r) => new()
        {
            GenericPurchaseItemId = r.GetInt32(r.GetOrdinal("GenericPurchaseItemId")),
            GenericPurchaseId     = r.GetInt32(r.GetOrdinal("GenericPurchaseId")),
            FarmId                = r.GetString(r.GetOrdinal("FarmId")),
            GenericProductId      = r.GetInt32(r.GetOrdinal("GenericProductId")),
            Description           = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
            Quantity              = r.GetDecimal(r.GetOrdinal("Quantity")),
            UnitCost              = r.GetDecimal(r.GetOrdinal("UnitCost")),
            DiscountAmount        = r.GetDecimal(r.GetOrdinal("DiscountAmount")),
            LineTotal             = r.GetDecimal(r.GetOrdinal("LineTotal")),
            Notes                 = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            PurchaseUnit          = r.IsDBNull(r.GetOrdinal("PurchaseUnit")) ? null : r.GetString(r.GetOrdinal("PurchaseUnit")),
            UnitFactor            = r.GetDecimal(r.GetOrdinal("UnitFactor")),
        };
    }
}
