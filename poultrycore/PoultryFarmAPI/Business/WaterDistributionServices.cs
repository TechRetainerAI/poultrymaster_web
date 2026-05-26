using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // WaterDriverService
    // =========================================================================
    public class WaterDriverService : IWaterDriverService
    {
        private readonly string _cs;
        public WaterDriverService(string cs) => _cs = cs;

        public async Task<List<WaterDriverModel>> GetAllAsync(string farmId)
        {
            var list = new List<WaterDriverModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDriver_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterDriverModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDriver_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDriverId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterDriverModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDriver_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@DriverName", m.DriverName);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)m.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LicenseNumber", (object?)m.LicenseNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultVehicleId", (object?)m.DefaultVehicleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultRouteId", (object?)m.DefaultRouteId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BasePay", (object?)m.BasePay ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CommissionPerBag", (object?)m.CommissionPerBag ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(WaterDriverModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDriver_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDriverId", m.WaterDriverId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@DriverName", m.DriverName);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)m.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LicenseNumber", (object?)m.LicenseNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultVehicleId", (object?)m.DefaultVehicleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultRouteId", (object?)m.DefaultRouteId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BasePay", (object?)m.BasePay ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CommissionPerBag", (object?)m.CommissionPerBag ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDriver_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDriverId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterDriverModel Read(SqlDataReader r) => new()
        {
            WaterDriverId    = r.GetInt32(r.GetOrdinal("WaterDriverId")),
            FarmId           = r.GetString(r.GetOrdinal("FarmId")),
            DriverName       = r.GetString(r.GetOrdinal("DriverName")),
            PhoneNumber      = r.IsDBNull(r.GetOrdinal("PhoneNumber"))    ? null : r.GetString(r.GetOrdinal("PhoneNumber")),
            LicenseNumber    = r.IsDBNull(r.GetOrdinal("LicenseNumber"))  ? null : r.GetString(r.GetOrdinal("LicenseNumber")),
            DefaultVehicleId = r.IsDBNull(r.GetOrdinal("DefaultVehicleId")) ? null : r.GetInt32(r.GetOrdinal("DefaultVehicleId")),
            DefaultRouteId   = r.IsDBNull(r.GetOrdinal("DefaultRouteId"))   ? null : r.GetInt32(r.GetOrdinal("DefaultRouteId")),
            BasePay          = r.IsDBNull(r.GetOrdinal("BasePay"))          ? null : r.GetDecimal(r.GetOrdinal("BasePay")),
            CommissionPerBag = r.IsDBNull(r.GetOrdinal("CommissionPerBag")) ? null : r.GetDecimal(r.GetOrdinal("CommissionPerBag")),
            IsActive         = r.GetBoolean(r.GetOrdinal("IsActive")),
            Notes            = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt        = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt        = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // =========================================================================
    // WaterVehicleService
    // =========================================================================
    public class WaterVehicleService : IWaterVehicleService
    {
        private readonly string _cs;
        public WaterVehicleService(string cs) => _cs = cs;

        public async Task<List<WaterVehicleModel>> GetAllAsync(string farmId)
        {
            var list = new List<WaterVehicleModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterVehicle_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterVehicleModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterVehicle_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterVehicleId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterVehicleModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterVehicle_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@VehicleName", m.VehicleName);
            cmd.Parameters.AddWithValue("@VehicleType", (object?)m.VehicleType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RegistrationNumber", (object?)m.RegistrationNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultDriverId", (object?)m.DefaultDriverId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CapacityBags", (object?)m.CapacityBags ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FuelType", (object?)m.FuelType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", m.Status);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(WaterVehicleModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterVehicle_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterVehicleId", m.WaterVehicleId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@VehicleName", m.VehicleName);
            cmd.Parameters.AddWithValue("@VehicleType", (object?)m.VehicleType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RegistrationNumber", (object?)m.RegistrationNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultDriverId", (object?)m.DefaultDriverId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CapacityBags", (object?)m.CapacityBags ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FuelType", (object?)m.FuelType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", m.Status);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterVehicle_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterVehicleId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterVehicleModel Read(SqlDataReader r) => new()
        {
            WaterVehicleId      = r.GetInt32(r.GetOrdinal("WaterVehicleId")),
            FarmId              = r.GetString(r.GetOrdinal("FarmId")),
            VehicleName         = r.GetString(r.GetOrdinal("VehicleName")),
            VehicleType         = r.IsDBNull(r.GetOrdinal("VehicleType")) ? null : r.GetString(r.GetOrdinal("VehicleType")),
            RegistrationNumber  = r.IsDBNull(r.GetOrdinal("RegistrationNumber")) ? null : r.GetString(r.GetOrdinal("RegistrationNumber")),
            DefaultDriverId     = r.IsDBNull(r.GetOrdinal("DefaultDriverId")) ? null : r.GetInt32(r.GetOrdinal("DefaultDriverId")),
            DefaultDriverName   = HasCol(r, "DefaultDriverName") && !r.IsDBNull(r.GetOrdinal("DefaultDriverName")) ? r.GetString(r.GetOrdinal("DefaultDriverName")) : null,
            CapacityBags        = r.IsDBNull(r.GetOrdinal("CapacityBags")) ? null : r.GetInt32(r.GetOrdinal("CapacityBags")),
            FuelType            = r.IsDBNull(r.GetOrdinal("FuelType")) ? null : r.GetString(r.GetOrdinal("FuelType")),
            Status              = r.GetString(r.GetOrdinal("Status")),
            Notes               = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt           = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt           = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        internal static bool HasCol(SqlDataReader r, string n)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (r.GetName(i).Equals(n, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }

    // =========================================================================
    // WaterRouteService
    // =========================================================================
    public class WaterRouteService : IWaterRouteService
    {
        private readonly string _cs;
        public WaterRouteService(string cs) => _cs = cs;

        public async Task<List<WaterRouteModel>> GetAllAsync(string farmId)
        {
            var list = new List<WaterRouteModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRoute_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterRouteModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRoute_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterRouteId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterRouteModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRoute_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@RouteName", m.RouteName);
            cmd.Parameters.AddWithValue("@AreaCovered", (object?)m.AreaCovered ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultDriverId", (object?)m.DefaultDriverId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultVehicleId", (object?)m.DefaultVehicleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ExpectedCustomers", (object?)m.ExpectedCustomers ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ExpectedBagsSold", (object?)m.ExpectedBagsSold ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(WaterRouteModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRoute_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterRouteId", m.WaterRouteId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@RouteName", m.RouteName);
            cmd.Parameters.AddWithValue("@AreaCovered", (object?)m.AreaCovered ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultDriverId", (object?)m.DefaultDriverId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultVehicleId", (object?)m.DefaultVehicleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ExpectedCustomers", (object?)m.ExpectedCustomers ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ExpectedBagsSold", (object?)m.ExpectedBagsSold ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRoute_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterRouteId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterRouteModel Read(SqlDataReader r) => new()
        {
            WaterRouteId       = r.GetInt32(r.GetOrdinal("WaterRouteId")),
            FarmId             = r.GetString(r.GetOrdinal("FarmId")),
            RouteName          = r.GetString(r.GetOrdinal("RouteName")),
            AreaCovered        = r.IsDBNull(r.GetOrdinal("AreaCovered")) ? null : r.GetString(r.GetOrdinal("AreaCovered")),
            DefaultDriverId    = r.IsDBNull(r.GetOrdinal("DefaultDriverId")) ? null : r.GetInt32(r.GetOrdinal("DefaultDriverId")),
            DefaultDriverName  = WaterVehicleService.HasCol(r, "DefaultDriverName") && !r.IsDBNull(r.GetOrdinal("DefaultDriverName")) ? r.GetString(r.GetOrdinal("DefaultDriverName")) : null,
            DefaultVehicleId   = r.IsDBNull(r.GetOrdinal("DefaultVehicleId")) ? null : r.GetInt32(r.GetOrdinal("DefaultVehicleId")),
            DefaultVehicleName = WaterVehicleService.HasCol(r, "DefaultVehicleName") && !r.IsDBNull(r.GetOrdinal("DefaultVehicleName")) ? r.GetString(r.GetOrdinal("DefaultVehicleName")) : null,
            ExpectedCustomers  = r.IsDBNull(r.GetOrdinal("ExpectedCustomers")) ? null : r.GetInt32(r.GetOrdinal("ExpectedCustomers")),
            ExpectedBagsSold   = r.IsDBNull(r.GetOrdinal("ExpectedBagsSold")) ? null : r.GetInt32(r.GetOrdinal("ExpectedBagsSold")),
            Notes              = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            IsActive           = r.GetBoolean(r.GetOrdinal("IsActive")),
            CreatedAt          = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt          = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // =========================================================================
    // WaterVehicleLoadingService
    // =========================================================================
    public class WaterVehicleLoadingService : IWaterVehicleLoadingService
    {
        private readonly string _cs;
        public WaterVehicleLoadingService(string cs) => _cs = cs;

        public async Task<List<WaterVehicleLoadingModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<WaterVehicleLoadingModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterVehicleLoading_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterVehicleLoadingModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterVehicleLoading_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterVehicleLoadingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterVehicleLoadingModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterVehicleLoading_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@LoadDate", m.LoadDate == default ? (object)DBNull.Value : m.LoadDate);
            cmd.Parameters.AddWithValue("@WaterVehicleId", m.WaterVehicleId);
            cmd.Parameters.AddWithValue("@WaterDriverId", (object?)m.WaterDriverId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AssistantStaffId", (object?)m.AssistantStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterRouteId", (object?)m.WaterRouteId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterProductId", m.WaterProductId);
            cmd.Parameters.AddWithValue("@BagsLoaded", m.BagsLoaded);
            cmd.Parameters.AddWithValue("@SachetsPerBag", m.SachetsPerBag);
            cmd.Parameters.AddWithValue("@ExpectedSellingPricePerBag", m.ExpectedSellingPricePerBag);
            cmd.Parameters.AddWithValue("@OpeningCashWithDriver", m.OpeningCashWithDriver);
            cmd.Parameters.AddWithValue("@LoadedByStaffId", (object?)m.LoadedByStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterVehicleLoading_Approve", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterVehicleLoadingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterVehicleLoading_Cancel", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterVehicleLoadingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterVehicleLoadingModel Read(SqlDataReader r) => new()
        {
            WaterVehicleLoadingId      = r.GetInt32(r.GetOrdinal("WaterVehicleLoadingId")),
            FarmId                     = r.GetString(r.GetOrdinal("FarmId")),
            LoadDate                   = r.GetDateTime(r.GetOrdinal("LoadDate")),
            WaterVehicleId             = r.GetInt32(r.GetOrdinal("WaterVehicleId")),
            VehicleName                = WaterVehicleService.HasCol(r, "VehicleName") && !r.IsDBNull(r.GetOrdinal("VehicleName")) ? r.GetString(r.GetOrdinal("VehicleName")) : null,
            WaterDriverId              = r.IsDBNull(r.GetOrdinal("WaterDriverId")) ? null : r.GetInt32(r.GetOrdinal("WaterDriverId")),
            DriverName                 = WaterVehicleService.HasCol(r, "DriverName") && !r.IsDBNull(r.GetOrdinal("DriverName")) ? r.GetString(r.GetOrdinal("DriverName")) : null,
            AssistantStaffId           = r.IsDBNull(r.GetOrdinal("AssistantStaffId")) ? null : r.GetInt32(r.GetOrdinal("AssistantStaffId")),
            WaterRouteId               = r.IsDBNull(r.GetOrdinal("WaterRouteId")) ? null : r.GetInt32(r.GetOrdinal("WaterRouteId")),
            RouteName                  = WaterVehicleService.HasCol(r, "RouteName") && !r.IsDBNull(r.GetOrdinal("RouteName")) ? r.GetString(r.GetOrdinal("RouteName")) : null,
            WaterProductId             = r.GetInt32(r.GetOrdinal("WaterProductId")),
            ProductName                = WaterVehicleService.HasCol(r, "ProductName") && !r.IsDBNull(r.GetOrdinal("ProductName")) ? r.GetString(r.GetOrdinal("ProductName")) : null,
            BagsLoaded                 = r.GetInt32(r.GetOrdinal("BagsLoaded")),
            SachetsPerBag              = r.GetInt32(r.GetOrdinal("SachetsPerBag")),
            ExpectedSellingPricePerBag = r.GetDecimal(r.GetOrdinal("ExpectedSellingPricePerBag")),
            ExpectedCash               = r.GetDecimal(r.GetOrdinal("ExpectedCash")),
            OpeningCashWithDriver      = r.GetDecimal(r.GetOrdinal("OpeningCashWithDriver")),
            LoadedByStaffId            = r.IsDBNull(r.GetOrdinal("LoadedByStaffId")) ? null : r.GetInt32(r.GetOrdinal("LoadedByStaffId")),
            Status                     = r.GetString(r.GetOrdinal("Status")),
            Notes                      = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy                  = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy                 = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt                 = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            CreatedAt                  = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                  = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
            IsDeleted                  = r.GetBoolean(r.GetOrdinal("IsDeleted")),
        };
    }

    // =========================================================================
    // WaterDriverReturnService
    // =========================================================================
    public class WaterDriverReturnService : IWaterDriverReturnService
    {
        private readonly string _cs;
        public WaterDriverReturnService(string cs) => _cs = cs;

        public async Task<List<WaterDriverReturnModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<WaterDriverReturnModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDriverReturn_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterDriverReturnModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDriverReturn_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDriverReturnId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterDriverReturnModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDriverReturn_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@WaterVehicleLoadingId", m.WaterVehicleLoadingId);
            cmd.Parameters.AddWithValue("@ReturnDate", m.ReturnDate == default ? (object)DBNull.Value : m.ReturnDate);
            cmd.Parameters.AddWithValue("@BagsSold", m.BagsSold);
            cmd.Parameters.AddWithValue("@BagsReturned", m.BagsReturned);
            cmd.Parameters.AddWithValue("@BagsDamaged", m.BagsDamaged);
            cmd.Parameters.AddWithValue("@MissingBags", m.MissingBags);
            cmd.Parameters.AddWithValue("@CashCollected", m.CashCollected);
            cmd.Parameters.AddWithValue("@MoMoCollected", m.MoMoCollected);
            cmd.Parameters.AddWithValue("@BankCollected", m.BankCollected);
            cmd.Parameters.AddWithValue("@CreditSalesAmount", m.CreditSalesAmount);
            cmd.Parameters.AddWithValue("@ReconciledByStaffId", (object?)m.ReconciledByStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDriverReturn_Approve", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDriverReturnId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDriverReturn_Cancel", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDriverReturnId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterDriverReturnModel Read(SqlDataReader r) => new()
        {
            WaterDriverReturnId         = r.GetInt32(r.GetOrdinal("WaterDriverReturnId")),
            FarmId                      = r.GetString(r.GetOrdinal("FarmId")),
            WaterVehicleLoadingId       = r.GetInt32(r.GetOrdinal("WaterVehicleLoadingId")),
            ReturnDate                  = r.GetDateTime(r.GetOrdinal("ReturnDate")),
            BagsSold                    = r.GetInt32(r.GetOrdinal("BagsSold")),
            BagsReturned                = r.GetInt32(r.GetOrdinal("BagsReturned")),
            BagsDamaged                 = r.GetInt32(r.GetOrdinal("BagsDamaged")),
            MissingBags                 = r.GetInt32(r.GetOrdinal("MissingBags")),
            CashCollected               = r.GetDecimal(r.GetOrdinal("CashCollected")),
            MoMoCollected               = r.GetDecimal(r.GetOrdinal("MoMoCollected")),
            BankCollected               = r.GetDecimal(r.GetOrdinal("BankCollected")),
            CreditSalesAmount           = r.GetDecimal(r.GetOrdinal("CreditSalesAmount")),
            TotalAccountedFor           = r.GetDecimal(r.GetOrdinal("TotalAccountedFor")),
            ShortageAmount              = r.GetDecimal(r.GetOrdinal("ShortageAmount")),
            OverageAmount               = r.GetDecimal(r.GetOrdinal("OverageAmount")),
            ReconciledByStaffId         = r.IsDBNull(r.GetOrdinal("ReconciledByStaffId")) ? null : r.GetInt32(r.GetOrdinal("ReconciledByStaffId")),
            Status                      = r.GetString(r.GetOrdinal("Status")),
            Notes                       = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy                   = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy                  = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt                  = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            CreatedAt                   = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                   = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),

            WaterVehicleId              = WaterVehicleService.HasCol(r, "WaterVehicleId") && !r.IsDBNull(r.GetOrdinal("WaterVehicleId")) ? r.GetInt32(r.GetOrdinal("WaterVehicleId")) : null,
            WaterDriverId               = WaterVehicleService.HasCol(r, "WaterDriverId") && !r.IsDBNull(r.GetOrdinal("WaterDriverId")) ? r.GetInt32(r.GetOrdinal("WaterDriverId")) : null,
            WaterRouteId                = WaterVehicleService.HasCol(r, "WaterRouteId") && !r.IsDBNull(r.GetOrdinal("WaterRouteId")) ? r.GetInt32(r.GetOrdinal("WaterRouteId")) : null,
            LoadingBagsLoaded           = WaterVehicleService.HasCol(r, "LoadingBagsLoaded") && !r.IsDBNull(r.GetOrdinal("LoadingBagsLoaded")) ? r.GetInt32(r.GetOrdinal("LoadingBagsLoaded")) : null,
            LoadingExpectedCash         = WaterVehicleService.HasCol(r, "LoadingExpectedCash") && !r.IsDBNull(r.GetOrdinal("LoadingExpectedCash")) ? r.GetDecimal(r.GetOrdinal("LoadingExpectedCash")) : null,
            ExpectedSellingPricePerBag  = WaterVehicleService.HasCol(r, "ExpectedSellingPricePerBag") && !r.IsDBNull(r.GetOrdinal("ExpectedSellingPricePerBag")) ? r.GetDecimal(r.GetOrdinal("ExpectedSellingPricePerBag")) : null,
            VehicleName                 = WaterVehicleService.HasCol(r, "VehicleName") && !r.IsDBNull(r.GetOrdinal("VehicleName")) ? r.GetString(r.GetOrdinal("VehicleName")) : null,
            DriverName                  = WaterVehicleService.HasCol(r, "DriverName") && !r.IsDBNull(r.GetOrdinal("DriverName")) ? r.GetString(r.GetOrdinal("DriverName")) : null,
            RouteName                   = WaterVehicleService.HasCol(r, "RouteName") && !r.IsDBNull(r.GetOrdinal("RouteName")) ? r.GetString(r.GetOrdinal("RouteName")) : null,
        };
    }

    // =========================================================================
    // WaterDriverShortageService
    // =========================================================================
    public class WaterDriverShortageService : IWaterDriverShortageService
    {
        private readonly string _cs;
        public WaterDriverShortageService(string cs) => _cs = cs;

        public async Task<List<WaterDriverShortageModel>> GetAllAsync(string farmId, string? status)
        {
            var list = new List<WaterDriverShortageModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDriverShortage_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterDriverShortageModel
                {
                    WaterDriverShortageId  = r.GetInt32(r.GetOrdinal("WaterDriverShortageId")),
                    FarmId                 = r.GetString(r.GetOrdinal("FarmId")),
                    WaterDriverId          = r.IsDBNull(r.GetOrdinal("WaterDriverId")) ? null : r.GetInt32(r.GetOrdinal("WaterDriverId")),
                    DriverName             = WaterVehicleService.HasCol(r, "DriverName") && !r.IsDBNull(r.GetOrdinal("DriverName")) ? r.GetString(r.GetOrdinal("DriverName")) : null,
                    WaterVehicleLoadingId  = r.IsDBNull(r.GetOrdinal("WaterVehicleLoadingId")) ? null : r.GetInt32(r.GetOrdinal("WaterVehicleLoadingId")),
                    WaterDriverReturnId    = r.GetInt32(r.GetOrdinal("WaterDriverReturnId")),
                    ShortageDate           = r.GetDateTime(r.GetOrdinal("ShortageDate")),
                    ExpectedAmount         = r.GetDecimal(r.GetOrdinal("ExpectedAmount")),
                    ActualAmount           = r.GetDecimal(r.GetOrdinal("ActualAmount")),
                    ShortageAmount         = r.GetDecimal(r.GetOrdinal("ShortageAmount")),
                    Reason                 = r.IsDBNull(r.GetOrdinal("Reason")) ? null : r.GetString(r.GetOrdinal("Reason")),
                    Status                 = r.GetString(r.GetOrdinal("Status")),
                    ApprovedBy             = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
                    Notes                  = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                    CreatedAt              = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                    UpdatedAt              = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
                });
            }
            return list;
        }

        public async Task ResolveAsync(int id, string farmId, string newStatus, string? reason, string? approvedBy)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDriverShortage_Resolve", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDriverShortageId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@NewStatus", newStatus);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
