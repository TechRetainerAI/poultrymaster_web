using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class WaterStockService : IWaterStockService
    {
        private readonly string _connectionString;

        public WaterStockService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<int> AddTransaction(WaterStockTransactionModel m)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterstock_addtransaction(p_farmid => @FarmId::text, p_waterproductid => @WaterProductId::int, p_txntype => @TxnType::text, p_quantity => @Quantity::int, p_unitcost => @UnitCost::numeric, p_relatedsaleid => @RelatedSaleId::int, p_note => @Note::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@WaterProductId", m.WaterProductId);
            cmd.Parameters.AddWithValue("@TxnType", m.TxnType);
            cmd.Parameters.AddWithValue("@Quantity", m.Quantity);
            cmd.Parameters.AddWithValue("@UnitCost", (object?)m.UnitCost ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RelatedSaleId", (object?)m.RelatedSaleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Note", (object?)m.Note ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<List<WaterStockTransactionModel>> GetTransactions(string farmId, int? productId)
        {
            var list = new List<WaterStockTransactionModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterstock_gettransactions(p_farmid => @FarmId::text, p_waterproductid => @WaterProductId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterProductId", (object?)productId ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new WaterStockTransactionModel
                {
                    StockTxnId     = reader.GetInt32(reader.GetOrdinal("StockTxnId")),
                    FarmId         = reader.GetString(reader.GetOrdinal("FarmId")),
                    WaterProductId = reader.GetInt32(reader.GetOrdinal("WaterProductId")),
                    ProductName    = reader.IsDBNull(reader.GetOrdinal("ProductName")) ? null : reader.GetString(reader.GetOrdinal("ProductName")),
                    TxnType        = reader.GetString(reader.GetOrdinal("TxnType")),
                    Quantity       = reader.GetInt32(reader.GetOrdinal("Quantity")),
                    UnitCost       = reader.IsDBNull(reader.GetOrdinal("UnitCost")) ? null : reader.GetDecimal(reader.GetOrdinal("UnitCost")),
                    RelatedSaleId  = reader.IsDBNull(reader.GetOrdinal("RelatedSaleId")) ? null : reader.GetInt32(reader.GetOrdinal("RelatedSaleId")),
                    Note           = reader.IsDBNull(reader.GetOrdinal("Note")) ? null : reader.GetString(reader.GetOrdinal("Note")),
                    CreatedDate    = reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
                    CreatedBy      = reader.IsDBNull(reader.GetOrdinal("CreatedBy")) ? null : reader.GetString(reader.GetOrdinal("CreatedBy")),
                });
            }
            return list;
        }
    }
}
