using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // Poultry Purchase Receipts (migration 345). Thin, like every service here:
    // the whole workflow -- lots, payment, cash, expense, reversal -- happens in
    // ONE database call, so it commits or fails as one. Nothing is posted from
    // C#; doing so would open a window where the goods are in stock and the
    // payment is not.
    // =========================================================================

    public interface IPoultryPurchaseReceiptService
    {
        Task<List<PoultryPurchaseReceiptModel>> GetAllAsync(string farmId, DateTime? fromDate, DateTime? toDate, string? status);
        Task<PoultryPurchaseReceiptModel?> GetByIdAsync(int id, string farmId);
        Task<int> ReceiveAsync(PoultryPurchaseReceiptRequest req);
        Task<int> ReverseAsync(int id, PoultryPurchaseReceiptReverseRequest req);
    }

    public class PoultryPurchaseReceiptService : IPoultryPurchaseReceiptService
    {
        private readonly string _cs;
        public PoultryPurchaseReceiptService(string cs) => _cs = cs;

        private static string? Str(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetString(i);
        }

        private static int? NInt(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetInt32(i);
        }

        private static decimal? NDec(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetDecimal(i);
        }

        private static DateTime? NDate(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetDateTime(i);
        }

        private static PoultryPurchaseReceiptModel MapHeader(NpgsqlDataReader r) => new()
        {
            PoultryPurchaseReceiptId = r.GetInt32(r.GetOrdinal("poultrypurchasereceiptid")),
            ReceiptNumber            = r.GetString(r.GetOrdinal("receiptnumber")),
            SupplierId               = r.GetInt32(r.GetOrdinal("supplierid")),
            SupplierName             = Str(r, "suppliername"),
            PurchaseDate             = r.GetDateTime(r.GetOrdinal("purchasedate")),
            ReferenceNo              = Str(r, "referenceno"),
            DueDate                  = NDate(r, "duedate"),
            Notes                    = Str(r, "notes"),
            Subtotal                 = r.GetDecimal(r.GetOrdinal("subtotal")),
            AdditionalCosts          = r.GetDecimal(r.GetOrdinal("additionalcosts")),
            AdditionalCostsNote      = Str(r, "additionalcostsnote"),
            TotalCost                = r.GetDecimal(r.GetOrdinal("totalcost")),
            AmountPaidAtReceipt      = r.GetDecimal(r.GetOrdinal("amountpaidatreceipt")),
            AmountPaid               = r.GetDecimal(r.GetOrdinal("amountpaid")),
            Balance                  = r.GetDecimal(r.GetOrdinal("balance")),
            PaymentStatus            = r.GetString(r.GetOrdinal("paymentstatus")),
            IsOverdue                = !r.IsDBNull(r.GetOrdinal("isoverdue")) && r.GetBoolean(r.GetOrdinal("isoverdue")),
            PaymentMethod            = Str(r, "paymentmethod"),
            PoultryCashAccountId     = NInt(r, "poultrycashaccountid"),
            CashAccountName          = Str(r, "cashaccountname"),
            PoultrySupplierPaymentId = NInt(r, "poultrysupplierpaymentid"),
            Status                   = r.GetString(r.GetOrdinal("status")),
            LineCount                = r.GetInt32(r.GetOrdinal("linecount")),
            ItemSummary              = Str(r, "itemsummary"),
            ExpensedAtPurchaseCost   = r.GetDecimal(r.GetOrdinal("expensedatpurchasecost")),
            DeferredCost             = r.GetDecimal(r.GetOrdinal("deferredcost")),
            CreatedBy                = Str(r, "createdby"),
            CreatedAt                = r.GetDateTime(r.GetOrdinal("createdat")),
            ReversedBy               = Str(r, "reversedby"),
            ReversedAt               = NDate(r, "reversedat"),
            ReversalReason           = Str(r, "reversalreason"),
            ReversalBlocker          = Str(r, "reversalblocker"),
        };

        private static PoultryPurchaseReceiptLineModel MapLine(NpgsqlDataReader r) => new()
        {
            PoultryPurchaseReceiptLineId   = r.GetInt32(r.GetOrdinal("poultrypurchasereceiptlineid")),
            LineNo                         = r.GetInt32(r.GetOrdinal("lineno")),
            PoultryRawMaterialItemId       = r.GetInt32(r.GetOrdinal("poultryrawmaterialitemid")),
            ItemName                       = Str(r, "itemname"),
            Category                       = Str(r, "category"),
            UnitOfMeasure                  = Str(r, "unitofmeasure"),
            Quantity                       = r.GetDecimal(r.GetOrdinal("quantity")),
            UnitCost                       = r.GetDecimal(r.GetOrdinal("unitcost")),
            LineSubtotal                   = r.GetDecimal(r.GetOrdinal("linesubtotal")),
            AllocatedAdditionalCost        = r.GetDecimal(r.GetOrdinal("allocatedadditionalcost")),
            LineTotal                      = r.GetDecimal(r.GetOrdinal("linetotal")),
            LandedUnitCost                 = r.GetDecimal(r.GetOrdinal("landedunitcost")),
            ProductionUnit                 = Str(r, "productionunit"),
            ProductionUnitsPerPurchaseUnit = NDec(r, "productionunitsperpurchaseunit"),
            ProductionQuantity             = r.GetDecimal(r.GetOrdinal("productionquantity")),
            Notes                          = Str(r, "notes"),
            PoultryRawMaterialPurchaseId   = r.GetInt32(r.GetOrdinal("poultryrawmaterialpurchaseid")),
            CostRecognitionMethod          = Str(r, "costrecognitionmethod"),
            RecognitionLabel               = Str(r, "recognitionlabel"),
            RemainingQuantity              = r.GetDecimal(r.GetOrdinal("remainingquantity")),
            ConsumedQuantity               = r.GetDecimal(r.GetOrdinal("consumedquantity")),
            AmountPaid                     = r.GetDecimal(r.GetOrdinal("amountpaid")),
            Balance                        = r.GetDecimal(r.GetOrdinal("balance")),
            DeferredRemainingCost          = r.GetDecimal(r.GetOrdinal("deferredremainingcost")),
            ReversalAdjustmentId           = NInt(r, "reversaladjustmentid"),
        };

        public async Task<List<PoultryPurchaseReceiptModel>> GetAllAsync(string farmId, DateTime? fromDate, DateTime? toDate, string? status)
        {
            var list = new List<PoultryPurchaseReceiptModel>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrypurchasereceipt_getall(p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date, p_status => @Status::text, p_receiptid => NULL::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate?.Date ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate?.Date ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapHeader(r));
            return list;
        }

        public async Task<PoultryPurchaseReceiptModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();

            PoultryPurchaseReceiptModel? receipt = null;
            using (var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrypurchasereceipt_getall(p_farmid => @FarmId::text, p_receiptid => @Id::int)", conn))
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@Id", id);
                using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync()) receipt = MapHeader(r);
            }
            if (receipt is null) return null;

            receipt.Lines = new List<PoultryPurchaseReceiptLineModel>();
            using (var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrypurchasereceipt_getlines(p_farmid => @FarmId::text, p_receiptid => @Id::int)", conn))
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@Id", id);
                using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync()) receipt.Lines.Add(MapLine(r));
            }
            return receipt;
        }

        public async Task<int> ReceiveAsync(PoultryPurchaseReceiptRequest req)
        {
            // Lowercase keys on purpose: the function reads them with ->>, which
            // is case-sensitive (postgres-sp-gotchas #1). A camelCase key would
            // arrive as NULL and the line would be refused as "choose an item".
            var lines = JsonSerializer.Serialize(req.Lines.Select(l => new Dictionary<string, object?>
            {
                ["itemid"] = l.PoultryRawMaterialItemId,
                ["quantity"] = l.Quantity,
                ["unitcost"] = l.UnitCost,
                ["productionunit"] = string.IsNullOrWhiteSpace(l.ProductionUnit) ? null : l.ProductionUnit.Trim(),
                ["productionunitsperpurchaseunit"] = l.ProductionUnitsPerPurchaseUnit,
                ["notes"] = string.IsNullOrWhiteSpace(l.Notes) ? null : l.Notes.Trim(),
            }));

            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(@"
                SELECT sppoultrypurchasereceipt_post(
                    p_farmid              => @FarmId::text,
                    p_supplierid          => @SupplierId::int,
                    p_suppliername        => @SupplierName::text,
                    p_purchasedate        => @PurchaseDate::timestamp,
                    p_referenceno         => @ReferenceNo::text,
                    p_duedate             => @DueDate::date,
                    p_notes               => @Notes::text,
                    p_lines               => @Lines::jsonb,
                    p_additionalcosts     => @AdditionalCosts::numeric,
                    p_additionalcostsnote => @AdditionalCostsNote::text,
                    p_amountpaid          => @AmountPaid::numeric,
                    p_paymentmethod       => @PaymentMethod::text,
                    p_cashaccountid       => @CashAccountId::int,
                    p_clientrequestid     => @ClientRequestId::uuid,
                    p_createdby           => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@SupplierId", (object?)req.SupplierId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SupplierName", (object?)req.SupplierName ?? DBNull.Value);
            // The business DATE: a back-dated receipt stores midnight, like every
            // other dated poultry document (datetime-display note).
            cmd.Parameters.AddWithValue("@PurchaseDate", (object?)req.PurchaseDate?.Date ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ReferenceNo", (object?)req.ReferenceNo ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DueDate", (object?)req.DueDate?.Date ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Lines", lines);
            cmd.Parameters.AddWithValue("@AdditionalCosts", req.AdditionalCosts);
            cmd.Parameters.AddWithValue("@AdditionalCostsNote", (object?)req.AdditionalCostsNote ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AmountPaid", req.AmountPaid);
            cmd.Parameters.AddWithValue("@PaymentMethod", (object?)req.PaymentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CashAccountId", (object?)req.CashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ClientRequestId", (object?)req.ClientRequestId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)req.CreatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<int> ReverseAsync(int id, PoultryPurchaseReceiptReverseRequest req)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrypurchasereceipt_reverse(p_farmid => @FarmId::text, p_receiptid => @Id::int, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@Reason", req.Reason);
            cmd.Parameters.AddWithValue("@ReversedBy", (object?)req.ReversedBy ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
    }
}
