using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericProductionRecordService : IGenericProductionRecordService
    {
        private readonly string _connectionString;
        public GenericProductionRecordService(string connectionString) => _connectionString = connectionString;

        public async Task<List<GenericProductionRecordModel>> GetAllAsync(string farmId, string? status = null)
        {
            var list = new List<GenericProductionRecordModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericproductionrecord_getall(p_farmid => @FarmId::text, p_status => @Status::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericProductionRecordModel
                {
                    GenericProductionRecordId = reader.GetInt32(reader.GetOrdinal("GenericProductionRecordId")),
                    FarmId = reader.GetString(reader.GetOrdinal("FarmId")),
                    GenericProductId = reader.GetInt32(reader.GetOrdinal("GenericProductId")),
                    ProductName = reader.IsDBNull(reader.GetOrdinal("ProductName")) ? null : reader.GetString(reader.GetOrdinal("ProductName")),
                    QuantityProduced = reader.GetDecimal(reader.GetOrdinal("QuantityProduced")),
                    ProductionDate = reader.GetDateTime(reader.GetOrdinal("ProductionDate")),
                    UnitCost = reader.GetDecimal(reader.GetOrdinal("UnitCost")),
                    TotalCost = reader.GetDecimal(reader.GetOrdinal("TotalCost")),
                    BatchNumber = reader.IsDBNull(reader.GetOrdinal("BatchNumber")) ? null : reader.GetString(reader.GetOrdinal("BatchNumber")),
                    MaterialsUsed = reader.IsDBNull(reader.GetOrdinal("MaterialsUsed")) ? null : reader.GetString(reader.GetOrdinal("MaterialsUsed")),
                    Notes = reader.IsDBNull(reader.GetOrdinal("Notes")) ? null : reader.GetString(reader.GetOrdinal("Notes")),
                    Status = reader.GetString(reader.GetOrdinal("Status")),
                    ReversalReason = reader.IsDBNull(reader.GetOrdinal("ReversalReason")) ? null : reader.GetString(reader.GetOrdinal("ReversalReason")),
                    CreatedBy = reader.IsDBNull(reader.GetOrdinal("CreatedBy")) ? null : reader.GetString(reader.GetOrdinal("CreatedBy")),
                    ReversedBy = reader.IsDBNull(reader.GetOrdinal("ReversedBy")) ? null : reader.GetString(reader.GetOrdinal("ReversedBy")),
                    ReversedAt = reader.IsDBNull(reader.GetOrdinal("ReversedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("ReversedAt")),
                    CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                });
            }
            return list;
        }

        public async Task<int> InsertAsync(GenericProductionRecordModel m)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                @"SELECT * FROM spgenericproductionrecord_insert(
                    p_farmid => @FarmId::text,
                    p_genericproductid => @GenericProductId::int,
                    p_quantityproduced => @QuantityProduced::numeric,
                    p_productiondate => @ProductionDate::timestamp,
                    p_unitcost => @UnitCost::numeric,
                    p_batchnumber => @BatchNumber::text,
                    p_materialsused => @MaterialsUsed::text,
                    p_notes => @Notes::text,
                    p_createdby => @CreatedBy::text
                )", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@GenericProductId", m.GenericProductId);
            cmd.Parameters.AddWithValue("@QuantityProduced", m.QuantityProduced);
            cmd.Parameters.AddWithValue("@ProductionDate", m.ProductionDate);
            cmd.Parameters.AddWithValue("@UnitCost", m.UnitCost);
            cmd.Parameters.AddWithValue("@BatchNumber", (object?)m.BatchNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MaterialsUsed", (object?)m.MaterialsUsed ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);

            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return Convert.ToInt32(result);
        }

        public async Task ReverseAsync(int id, string farmId, string reason, string? reversedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                @"SELECT spgenericproductionrecord_reverse(
                    p_id => @Id::int,
                    p_farmid => @FarmId::text,
                    p_reason => @Reason::text,
                    p_reversedby => @ReversedBy::text
                )", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Reason", reason);
            cmd.Parameters.AddWithValue("@ReversedBy", (object?)reversedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
