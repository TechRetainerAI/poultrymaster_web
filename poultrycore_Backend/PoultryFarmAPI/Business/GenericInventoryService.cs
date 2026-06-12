using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericInventoryService : IGenericInventoryService
    {
        private readonly string _connectionString;
        public GenericInventoryService(string connectionString) => _connectionString = connectionString;

        // ====================================================================
        // Stock movements
        // ====================================================================
        public async Task<List<GenericStockMovementModel>> GetMovementsForProductAsync(int productId, string farmId)
        {
            var list = new List<GenericStockMovementModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericStockMovement_GetAllForProduct", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericProductId", productId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadMovement(reader));
            return list;
        }

        public async Task<List<GenericStockMovementModel>> GetMovementsForFarmAsync(string farmId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<GenericStockMovementModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericStockMovement_GetByFarm", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",   (object?)toDate   ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadMovement(reader));
            return list;
        }

        // ====================================================================
        // Stock adjustments
        // ====================================================================
        public async Task<List<GenericStockAdjustmentModel>> GetAdjustmentsAsync(string farmId, string? status)
        {
            var list = new List<GenericStockAdjustmentModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericStockAdjustment_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadAdjustment(reader));
            return list;
        }

        public async Task<GenericStockAdjustmentModel?> GetAdjustmentByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericStockAdjustment_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericStockAdjustmentId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? ReadAdjustment(reader) : null;
        }

        public async Task<int> InsertAdjustmentAsync(GenericStockAdjustmentModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericStockAdjustment_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@GenericProductId", m.GenericProductId);
            cmd.Parameters.AddWithValue("@AdjustmentType", m.AdjustmentType);
            cmd.Parameters.AddWithValue("@Quantity", m.Quantity);
            cmd.Parameters.AddWithValue("@Reason", m.Reason);
            cmd.Parameters.AddWithValue("@AdjustmentDate",
                m.AdjustmentDate == default ? (object)DBNull.Value : m.AdjustmentDate);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RequestedBy", (object?)m.RequestedBy ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task SubmitAdjustmentAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericStockAdjustment_Submit", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericStockAdjustmentId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ApproveAdjustmentAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericStockAdjustment_Approve", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericStockAdjustmentId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task RejectAdjustmentAsync(int id, string farmId, string rejectionReason, string? approvedBy)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericStockAdjustment_Reject", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericStockAdjustmentId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@RejectionReason", rejectionReason);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ====================================================================
        // Helpers
        // ====================================================================
        private static GenericStockMovementModel ReadMovement(SqlDataReader r) => new()
        {
            GenericStockMovementId = r.GetInt32(r.GetOrdinal("GenericStockMovementId")),
            FarmId                 = r.GetString(r.GetOrdinal("FarmId")),
            GenericProductId       = r.GetInt32(r.GetOrdinal("GenericProductId")),
            ProductName            = HasColumn(r, "ProductName") && !r.IsDBNull(r.GetOrdinal("ProductName")) ? r.GetString(r.GetOrdinal("ProductName")) : null,
            InventoryLocationId    = r.IsDBNull(r.GetOrdinal("InventoryLocationId")) ? null : r.GetInt32(r.GetOrdinal("InventoryLocationId")),
            MovementDate           = r.GetDateTime(r.GetOrdinal("MovementDate")),
            MovementType           = r.GetString(r.GetOrdinal("MovementType")),
            Quantity               = r.GetDecimal(r.GetOrdinal("Quantity")),
            UnitCost               = r.IsDBNull(r.GetOrdinal("UnitCost")) ? null : r.GetDecimal(r.GetOrdinal("UnitCost")),
            UnitSellingPrice       = r.IsDBNull(r.GetOrdinal("UnitSellingPrice")) ? null : r.GetDecimal(r.GetOrdinal("UnitSellingPrice")),
            TotalCostValue         = r.IsDBNull(r.GetOrdinal("TotalCostValue")) ? null : r.GetDecimal(r.GetOrdinal("TotalCostValue")),
            ReferenceType          = r.IsDBNull(r.GetOrdinal("ReferenceType")) ? null : r.GetString(r.GetOrdinal("ReferenceType")),
            ReferenceId            = r.IsDBNull(r.GetOrdinal("ReferenceId")) ? null : r.GetInt32(r.GetOrdinal("ReferenceId")),
            Reason                 = r.IsDBNull(r.GetOrdinal("Reason")) ? null : r.GetString(r.GetOrdinal("Reason")),
            CreatedBy              = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy             = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt             = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            Notes                  = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt              = r.GetDateTime(r.GetOrdinal("CreatedAt")),
        };

        private static GenericStockAdjustmentModel ReadAdjustment(SqlDataReader r) => new()
        {
            GenericStockAdjustmentId = r.GetInt32(r.GetOrdinal("GenericStockAdjustmentId")),
            FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
            GenericProductId         = r.GetInt32(r.GetOrdinal("GenericProductId")),
            ProductName              = HasColumn(r, "ProductName") && !r.IsDBNull(r.GetOrdinal("ProductName")) ? r.GetString(r.GetOrdinal("ProductName")) : null,
            InventoryLocationId      = r.IsDBNull(r.GetOrdinal("InventoryLocationId")) ? null : r.GetInt32(r.GetOrdinal("InventoryLocationId")),
            AdjustmentDate           = r.GetDateTime(r.GetOrdinal("AdjustmentDate")),
            AdjustmentType           = r.GetString(r.GetOrdinal("AdjustmentType")),
            Quantity                 = r.GetDecimal(r.GetOrdinal("Quantity")),
            Reason                   = r.GetString(r.GetOrdinal("Reason")),
            Status                   = r.GetString(r.GetOrdinal("Status")),
            RequestedBy              = r.IsDBNull(r.GetOrdinal("RequestedBy")) ? null : r.GetString(r.GetOrdinal("RequestedBy")),
            ApprovedBy               = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt               = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            RejectionReason          = r.IsDBNull(r.GetOrdinal("RejectionReason")) ? null : r.GetString(r.GetOrdinal("RejectionReason")),
            Notes                    = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        private static bool HasColumn(SqlDataReader r, string name)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (r.GetName(i).Equals(name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }
}
