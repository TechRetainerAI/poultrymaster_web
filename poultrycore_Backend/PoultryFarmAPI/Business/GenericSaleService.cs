using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericSaleService : IGenericSaleService
    {
        private readonly string _connectionString;
        public GenericSaleService(string connectionString) => _connectionString = connectionString;

        // ====================================================================
        // Reads
        // ====================================================================
        public async Task<List<GenericSaleModel>> GetAllAsync(string farmId, string? status)
        {
            var list = new List<GenericSaleModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSale_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadSaleHeader(reader));
            return list;
        }

        public async Task<GenericSaleModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSale_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericSaleId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();

            GenericSaleModel? sale = null;
            if (await reader.ReadAsync()) sale = ReadSaleHeader(reader);
            if (sale is null) return null;

            // Result set 2: items
            if (await reader.NextResultAsync())
            {
                while (await reader.ReadAsync()) sale.Items.Add(ReadSaleItem(reader));
            }
            return sale;
        }

        // ====================================================================
        // Insert (Draft) with items via TVP
        // ====================================================================
        public async Task<int> InsertAsync(string farmId, GenericSaleCreateRequest req, string? createdBy)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSale_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@SaleDate", (object?)req.SaleDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@GenericCustomerId", (object?)req.GenericCustomerId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BranchId", (object?)req.BranchId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SalesType", req.SalesType);
            cmd.Parameters.AddWithValue("@SalesChannel", (object?)req.SalesChannel ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SalespersonStaffId", (object?)req.SalespersonStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@HeaderDiscountAmount", req.HeaderDiscountAmount);
            cmd.Parameters.AddWithValue("@TaxAmount", req.TaxAmount);
            cmd.Parameters.AddWithValue("@AmountPaid", req.AmountPaid);
            cmd.Parameters.AddWithValue("@PaymentMethod", (object?)req.PaymentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", (object?)req.GenericCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ReceiptNumber", (object?)req.ReceiptNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);

            // Items as a TVP
            var tvp = new SqlParameter("@Items", SqlDbType.Structured)
            {
                TypeName = "dbo.GenericSaleItemTvp",
                Value = BuildItemsTable(req.Items),
            };
            cmd.Parameters.Add(tvp);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        private static DataTable BuildItemsTable(IEnumerable<GenericSaleItemModel> items)
        {
            var table = new DataTable();
            table.Columns.Add("ItemType",         typeof(string));
            table.Columns.Add("GenericProductId", typeof(int));
            table.Columns.Add("GenericServiceId", typeof(int));
            table.Columns.Add("Description",      typeof(string));
            table.Columns.Add("Quantity",         typeof(decimal));
            table.Columns.Add("UnitPrice",        typeof(decimal));
            table.Columns.Add("DiscountAmount",   typeof(decimal));
            table.Columns.Add("CostAmount",       typeof(decimal));
            table.Columns.Add("Notes",            typeof(string));

            foreach (var i in items)
            {
                table.Rows.Add(
                    i.ItemType,
                    (object?)i.GenericProductId ?? DBNull.Value,
                    (object?)i.GenericServiceId ?? DBNull.Value,
                    (object?)i.Description ?? DBNull.Value,
                    i.Quantity,
                    i.UnitPrice,
                    i.DiscountAmount,
                    (object?)i.CostAmount ?? DBNull.Value,
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
            using var cmd = new SqlCommand("spGenericSale_Approve", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericSaleId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId, string? cancelledBy, string? reason)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSale_Cancel", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericSaleId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@CancelledBy", (object?)cancelledBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task RefundAsync(int id, string farmId, string? refundedBy, string? reason)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericSale_Refund", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericSaleId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@RefundedBy", (object?)refundedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ====================================================================
        // Helpers
        // ====================================================================
        private static GenericSaleModel ReadSaleHeader(SqlDataReader r) => new()
        {
            GenericSaleId         = r.GetInt32(r.GetOrdinal("GenericSaleId")),
            FarmId                = r.GetString(r.GetOrdinal("FarmId")),
            SaleDate              = r.GetDateTime(r.GetOrdinal("SaleDate")),
            GenericCustomerId     = r.IsDBNull(r.GetOrdinal("GenericCustomerId")) ? null : r.GetInt32(r.GetOrdinal("GenericCustomerId")),
            CustomerName          = r.IsDBNull(r.GetOrdinal("CustomerName")) ? null : r.GetString(r.GetOrdinal("CustomerName")),
            BranchId              = r.IsDBNull(r.GetOrdinal("BranchId")) ? null : r.GetInt32(r.GetOrdinal("BranchId")),
            SalesType             = r.GetString(r.GetOrdinal("SalesType")),
            SalesChannel          = r.IsDBNull(r.GetOrdinal("SalesChannel")) ? null : r.GetString(r.GetOrdinal("SalesChannel")),
            SalespersonStaffId    = r.IsDBNull(r.GetOrdinal("SalespersonStaffId")) ? null : r.GetInt32(r.GetOrdinal("SalespersonStaffId")),
            SubtotalAmount        = r.GetDecimal(r.GetOrdinal("SubtotalAmount")),
            DiscountAmount        = r.GetDecimal(r.GetOrdinal("DiscountAmount")),
            TaxAmount             = r.GetDecimal(r.GetOrdinal("TaxAmount")),
            TotalAmount           = r.GetDecimal(r.GetOrdinal("TotalAmount")),
            AmountPaid            = r.GetDecimal(r.GetOrdinal("AmountPaid")),
            Balance               = r.GetDecimal(r.GetOrdinal("Balance")),
            PaymentStatus         = r.GetString(r.GetOrdinal("PaymentStatus")),
            PaymentMethod         = r.IsDBNull(r.GetOrdinal("PaymentMethod")) ? null : r.GetString(r.GetOrdinal("PaymentMethod")),
            GenericCashAccountId  = r.IsDBNull(r.GetOrdinal("GenericCashAccountId")) ? null : r.GetInt32(r.GetOrdinal("GenericCashAccountId")),
            ReceiptNumber         = r.IsDBNull(r.GetOrdinal("ReceiptNumber")) ? null : r.GetString(r.GetOrdinal("ReceiptNumber")),
            Status                = r.GetString(r.GetOrdinal("Status")),
            Notes                 = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy             = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy            = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt            = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            CancelledBy           = r.IsDBNull(r.GetOrdinal("CancelledBy")) ? null : r.GetString(r.GetOrdinal("CancelledBy")),
            CancelledAt           = r.IsDBNull(r.GetOrdinal("CancelledAt")) ? null : r.GetDateTime(r.GetOrdinal("CancelledAt")),
            CancellationReason    = r.IsDBNull(r.GetOrdinal("CancellationReason")) ? null : r.GetString(r.GetOrdinal("CancellationReason")),
            CreatedAt             = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt             = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        private static GenericSaleItemModel ReadSaleItem(SqlDataReader r) => new()
        {
            GenericSaleItemId = r.GetInt32(r.GetOrdinal("GenericSaleItemId")),
            GenericSaleId     = r.GetInt32(r.GetOrdinal("GenericSaleId")),
            FarmId            = r.GetString(r.GetOrdinal("FarmId")),
            ItemType          = r.GetString(r.GetOrdinal("ItemType")),
            GenericProductId  = r.IsDBNull(r.GetOrdinal("GenericProductId")) ? null : r.GetInt32(r.GetOrdinal("GenericProductId")),
            GenericServiceId  = r.IsDBNull(r.GetOrdinal("GenericServiceId")) ? null : r.GetInt32(r.GetOrdinal("GenericServiceId")),
            Description       = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
            Quantity          = r.GetDecimal(r.GetOrdinal("Quantity")),
            UnitPrice         = r.GetDecimal(r.GetOrdinal("UnitPrice")),
            DiscountAmount    = r.GetDecimal(r.GetOrdinal("DiscountAmount")),
            LineTotal         = r.GetDecimal(r.GetOrdinal("LineTotal")),
            CostAmount        = r.IsDBNull(r.GetOrdinal("CostAmount")) ? null : r.GetDecimal(r.GetOrdinal("CostAmount")),
            Notes             = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
        };
    }
}
