using System.Data;
using Microsoft.Data.SqlClient;
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

            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterSale_CreateV2", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@WaterCustomerId", (object?)req.WaterCustomerId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SaleDate", (object?)req.SaleDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)req.CreatedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ItemsJson", itemsJson);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<WaterSaleModel?> GetById(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterSale_GetById", conn) { CommandType = CommandType.StoredProcedure };
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterSale_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadHeader(reader));
            return list;
        }

        public async Task Cancel(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterSale_Cancel", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterSaleId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // Hard-delete a direct sale (restores stock, removes payments + items).
        // The SP rejects delivery-sourced sales.
        public async Task Delete(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterSale_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterSaleId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterSaleModel ReadHeader(SqlDataReader r) => new()
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
        };

        private static WaterSaleItemModel ReadItem(SqlDataReader r) => new()
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

        private static bool HasCol(SqlDataReader r, string name)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (r.GetName(i).Equals(name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }
}
