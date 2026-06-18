using System.Data;
using Microsoft.Data.SqlClient;
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericPurchase_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadHeader(reader));
            return list;
        }

        public async Task<GenericPurchaseModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericPurchase_GetById", conn) { CommandType = CommandType.StoredProcedure };
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericPurchase_Insert", conn) { CommandType = CommandType.StoredProcedure };
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

            var tvp = new SqlParameter("@Items", SqlDbType.Structured)
            {
                TypeName = "dbo.GenericPurchaseItemTvp",
                Value = BuildItemsTable(req.Items),
            };
            cmd.Parameters.Add(tvp);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        private static DataTable BuildItemsTable(IEnumerable<GenericPurchaseItemModel> items)
        {
            var table = new DataTable();
            table.Columns.Add("GenericProductId", typeof(int));
            table.Columns.Add("Description",      typeof(string));
            table.Columns.Add("Quantity",         typeof(decimal));
            table.Columns.Add("UnitCost",         typeof(decimal));
            table.Columns.Add("DiscountAmount",   typeof(decimal));
            table.Columns.Add("Notes",            typeof(string));

            foreach (var i in items)
            {
                table.Rows.Add(
                    i.GenericProductId,
                    (object?)i.Description ?? DBNull.Value,
                    i.Quantity,
                    i.UnitCost,
                    i.DiscountAmount,
                    (object?)i.Notes ?? DBNull.Value
                );
            }
            return table;
        }

        // ====================================================================
        // Workflow
        // ====================================================================
        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericPurchase_Approve", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericPurchaseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId, string? cancelledBy, string? reason)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericPurchase_Cancel", conn) { CommandType = CommandType.StoredProcedure };
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
        private static GenericPurchaseModel ReadHeader(SqlDataReader r) => new()
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
        };

        private static GenericPurchaseItemModel ReadItem(SqlDataReader r) => new()
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
        };
    }
}
