using System.Data;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // Thin ADO.NET service for the Poultry Driver Distribution module. Every
    // method is a single spPoultry* call. Nested arrays are serialized to
    // camelCase JSON so the SP OPENJSON paths line up. Uses the PoultryRdr
    // reader extensions defined in PoultryProductionServices.cs.
    public class PoultryDriverDistributionService : IPoultryDriverDistributionService
    {
        private readonly string _cs;
        public PoultryDriverDistributionService(string cs) => _cs = cs;

        private static readonly JsonSerializerOptions JsonOpts =
            new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

        private static object Json<T>(List<T>? list) =>
            (list is { Count: > 0 }) ? JsonSerializer.Serialize(list, JsonOpts) : (object)DBNull.Value;

        // ====================================================================
        // Drivers
        // ====================================================================
        public async Task<List<PoultryDriverModel>> GetDriversAsync(string farmId)
        {
            var list = new List<PoultryDriverModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriver_getall(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadDriver(r));
            return list;
        }

        public async Task<PoultryDriverModel?> GetDriverAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriver_getbyid(p_poultrydriverid => @PoultryDriverId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDriverId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadDriver(r) : null;
        }

        public async Task<int> InsertDriverAsync(PoultryDriverModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriver_insert(p_farmid => @FarmId::text, p_drivername => @DriverName::text, p_phonenumber => @PhoneNumber::text, p_licensenumber => @LicenseNumber::text, p_defaultvehicleid => @DefaultVehicleId::int, p_defaultrouteid => @DefaultRouteId::int, p_basepay => @BasePay::numeric, p_commissionpercrate => @CommissionPerCrate::numeric, p_isactive => @IsActive::boolean, p_employeeuserid => @EmployeeUserId::text, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@DriverName", m.DriverName);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)m.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LicenseNumber", (object?)m.LicenseNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultVehicleId", (object?)m.DefaultVehicleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultRouteId", (object?)m.DefaultRouteId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BasePay", (object?)m.BasePay ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CommissionPerCrate", (object?)m.CommissionPerCrate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@EmployeeUserId", (object?)m.EmployeeUserId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateDriverAsync(PoultryDriverModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriver_update(p_poultrydriverid => @PoultryDriverId::int, p_farmid => @FarmId::text, p_drivername => @DriverName::text, p_phonenumber => @PhoneNumber::text, p_licensenumber => @LicenseNumber::text, p_defaultvehicleid => @DefaultVehicleId::int, p_defaultrouteid => @DefaultRouteId::int, p_basepay => @BasePay::numeric, p_commissionpercrate => @CommissionPerCrate::numeric, p_isactive => @IsActive::boolean, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDriverId", m.PoultryDriverId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@DriverName", m.DriverName);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)m.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LicenseNumber", (object?)m.LicenseNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultVehicleId", (object?)m.DefaultVehicleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultRouteId", (object?)m.DefaultRouteId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BasePay", (object?)m.BasePay ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CommissionPerCrate", (object?)m.CommissionPerCrate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteDriverAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriver_delete(p_poultrydriverid => @PoultryDriverId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDriverId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<PoultryDriverModel>> ListDriversForFarmAsync(string farmId)
        {
            var list = new List<PoultryDriverModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriver_listforfarm(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadDriver(r));
            return list;
        }

        public async Task<PoultryDriverModel?> UpsertDriverForEmployeeAsync(PoultryDriverFromEmployeeRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriver_upsertforemployee(p_farmid => @FarmId::text, p_employeeuserid => @EmployeeUserId::text, p_drivername => @DriverName::text, p_phonenumber => @PhoneNumber::text, p_licensenumber => @LicenseNumber::text, p_basepay => @BasePay::numeric, p_commissionpercrate => @CommissionPerCrate::numeric)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@EmployeeUserId", req.EmployeeUserId);
            cmd.Parameters.AddWithValue("@DriverName", (object?)req.DriverName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PhoneNumber", (object?)req.PhoneNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LicenseNumber", (object?)req.LicenseNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BasePay", (object?)req.BasePay ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CommissionPerCrate", (object?)req.CommissionPerCrate ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadDriver(r) : null;
        }

        private static PoultryDriverModel ReadDriver(NpgsqlDataReader r) => new()
        {
            PoultryDriverId = r.Int("PoultryDriverId"),
            FarmId = r.Str("FarmId"),
            DriverName = r.Str("DriverName"),
            PhoneNumber = r.StrN("PhoneNumber"),
            LicenseNumber = r.StrN("LicenseNumber"),
            DefaultVehicleId = r.IntN("DefaultVehicleId"),
            DefaultRouteId = r.IntN("DefaultRouteId"),
            BasePay = r.DecN("BasePay"),
            CommissionPerCrate = r.DecN("CommissionPerCrate"),
            IsActive = r.Bool("IsActive"),
            EmployeeUserId = r.StrN("EmployeeUserId"),
            Notes = r.StrN("Notes"),
            CreatedAt = r.Date("CreatedAt"),
            UpdatedAt = r.DateN("UpdatedAt"),
            EmployeeEmail = r.Has("EmployeeEmail") ? r.StrN("EmployeeEmail") : null,
            EmployeeUserName = r.Has("EmployeeUserName") ? r.StrN("EmployeeUserName") : null,
        };

        // ====================================================================
        // Vehicles
        // ====================================================================
        public async Task<List<PoultryVehicleModel>> GetVehiclesAsync(string farmId)
        {
            var list = new List<PoultryVehicleModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryvehicle_getall(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadVehicle(r));
            return list;
        }

        public async Task<PoultryVehicleModel?> GetVehicleAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryvehicle_getbyid(p_poultryvehicleid => @PoultryVehicleId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryVehicleId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadVehicle(r) : null;
        }

        public async Task<int> InsertVehicleAsync(PoultryVehicleModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryvehicle_insert(p_farmid => @FarmId::text, p_vehiclename => @VehicleName::text, p_vehicletype => @VehicleType::text, p_registrationnumber => @RegistrationNumber::text, p_defaultdriverid => @DefaultDriverId::int, p_capacitycrates => @CapacityCrates::int, p_fueltype => @FuelType::text, p_status => @Status::text, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@VehicleName", m.VehicleName);
            cmd.Parameters.AddWithValue("@VehicleType", (object?)m.VehicleType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RegistrationNumber", (object?)m.RegistrationNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultDriverId", (object?)m.DefaultDriverId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CapacityCrates", (object?)m.CapacityCrates ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FuelType", (object?)m.FuelType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", (object?)m.Status ?? "Active");
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateVehicleAsync(PoultryVehicleModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryvehicle_update(p_poultryvehicleid => @PoultryVehicleId::int, p_farmid => @FarmId::text, p_vehiclename => @VehicleName::text, p_vehicletype => @VehicleType::text, p_registrationnumber => @RegistrationNumber::text, p_defaultdriverid => @DefaultDriverId::int, p_capacitycrates => @CapacityCrates::int, p_fueltype => @FuelType::text, p_status => @Status::text, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@PoultryVehicleId", m.PoultryVehicleId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@VehicleName", m.VehicleName);
            cmd.Parameters.AddWithValue("@VehicleType", (object?)m.VehicleType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RegistrationNumber", (object?)m.RegistrationNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultDriverId", (object?)m.DefaultDriverId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CapacityCrates", (object?)m.CapacityCrates ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FuelType", (object?)m.FuelType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", (object?)m.Status ?? "Active");
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteVehicleAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryvehicle_delete(p_poultryvehicleid => @PoultryVehicleId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryVehicleId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        private static PoultryVehicleModel ReadVehicle(NpgsqlDataReader r) => new()
        {
            PoultryVehicleId = r.Int("PoultryVehicleId"),
            FarmId = r.Str("FarmId"),
            VehicleName = r.Str("VehicleName"),
            VehicleType = r.StrN("VehicleType"),
            RegistrationNumber = r.StrN("RegistrationNumber"),
            DefaultDriverId = r.IntN("DefaultDriverId"),
            CapacityCrates = r.IntN("CapacityCrates"),
            FuelType = r.StrN("FuelType"),
            Status = r.Str("Status"),
            Notes = r.StrN("Notes"),
            CreatedAt = r.Date("CreatedAt"),
            UpdatedAt = r.DateN("UpdatedAt"),
        };

        // ====================================================================
        // Routes
        // ====================================================================
        public async Task<List<PoultryRouteModel>> GetRoutesAsync(string farmId)
        {
            var list = new List<PoultryRouteModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryroute_getall(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadRoute(r));
            return list;
        }

        public async Task<PoultryRouteModel?> GetRouteAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryroute_getbyid(p_poultryrouteid => @PoultryRouteId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryRouteId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadRoute(r) : null;
        }

        public async Task<int> InsertRouteAsync(PoultryRouteModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryroute_insert(p_farmid => @FarmId::text, p_routename => @RouteName::text, p_areacovered => @AreaCovered::text, p_defaultdriverid => @DefaultDriverId::int, p_defaultvehicleid => @DefaultVehicleId::int, p_expectedcustomers => @ExpectedCustomers::int, p_expectedcratessold => @ExpectedCratesSold::int, p_isactive => @IsActive::boolean, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@RouteName", m.RouteName);
            cmd.Parameters.AddWithValue("@AreaCovered", (object?)m.AreaCovered ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultDriverId", (object?)m.DefaultDriverId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultVehicleId", (object?)m.DefaultVehicleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ExpectedCustomers", (object?)m.ExpectedCustomers ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ExpectedCratesSold", (object?)m.ExpectedCratesSold ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateRouteAsync(PoultryRouteModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryroute_update(p_poultryrouteid => @PoultryRouteId::int, p_farmid => @FarmId::text, p_routename => @RouteName::text, p_areacovered => @AreaCovered::text, p_defaultdriverid => @DefaultDriverId::int, p_defaultvehicleid => @DefaultVehicleId::int, p_expectedcustomers => @ExpectedCustomers::int, p_expectedcratessold => @ExpectedCratesSold::int, p_isactive => @IsActive::boolean, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@PoultryRouteId", m.PoultryRouteId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@RouteName", m.RouteName);
            cmd.Parameters.AddWithValue("@AreaCovered", (object?)m.AreaCovered ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultDriverId", (object?)m.DefaultDriverId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultVehicleId", (object?)m.DefaultVehicleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ExpectedCustomers", (object?)m.ExpectedCustomers ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ExpectedCratesSold", (object?)m.ExpectedCratesSold ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteRouteAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryroute_delete(p_poultryrouteid => @PoultryRouteId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryRouteId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        private static PoultryRouteModel ReadRoute(NpgsqlDataReader r) => new()
        {
            PoultryRouteId = r.Int("PoultryRouteId"),
            FarmId = r.Str("FarmId"),
            RouteName = r.Str("RouteName"),
            AreaCovered = r.StrN("AreaCovered"),
            DefaultDriverId = r.IntN("DefaultDriverId"),
            DefaultVehicleId = r.IntN("DefaultVehicleId"),
            ExpectedCustomers = r.IntN("ExpectedCustomers"),
            ExpectedCratesSold = r.IntN("ExpectedCratesSold"),
            Notes = r.StrN("Notes"),
            IsActive = r.Bool("IsActive"),
            CreatedAt = r.Date("CreatedAt"),
            UpdatedAt = r.DateN("UpdatedAt"),
        };

        // ====================================================================
        // Vehicle Loadings
        // ====================================================================
        public async Task<List<PoultryVehicleLoadingModel>> GetLoadingsAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryVehicleLoadingModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryvehicleloading_getall(p_farmid => @FarmId::text, p_status => @Status::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadLoading(r));
            return list;
        }

        public async Task<PoultryVehicleLoadingModel?> GetLoadingAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryvehicleloading_getbyid(p_poultryvehicleloadingid => @PoultryVehicleLoadingId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryVehicleLoadingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadLoading(r) : null;
        }

        public async Task<List<PoultryVehicleLoadingItemModel>> GetLoadingItemsAsync(int loadingId, string farmId)
        {
            var list = new List<PoultryVehicleLoadingItemModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryvehicleloading_getitems(p_poultryvehicleloadingid => @PoultryVehicleLoadingId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryVehicleLoadingId", loadingId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryVehicleLoadingItemModel
            {
                PoultryVehicleLoadingItemId = r.Int("PoultryVehicleLoadingItemId"),
                PoultryVehicleLoadingId = r.Int("PoultryVehicleLoadingId"),
                PoultryProductId = r.Int("PoultryProductId"),
                ProductName = r.StrN("ProductName"),
                ProductUnit = r.StrN("ProductUnit"),
                CratesLoaded = r.Int("CratesLoaded"),
                EggsPerCrate = r.Int("EggsPerCrate"),
                UnitPrice = r.Dec("UnitPrice"),
                ExpectedAmount = r.Dec("ExpectedAmount"),
                Notes = r.StrN("Notes"),
                CreatedAt = r.Date("CreatedAt"),
                UpdatedAt = r.DateN("UpdatedAt"),
            });
            return list;
        }

        public async Task<int> InsertLoadingAsync(PoultryVehicleLoadingCreateRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryvehicleloading_insert(p_farmid => @FarmId::text, p_loaddate => @LoadDate::timestamp, p_poultryvehicleid => @PoultryVehicleId::int, p_poultrydriverid => @PoultryDriverId::int, p_assistantstaffid => @AssistantStaffId::int, p_poultryrouteid => @PoultryRouteId::int, p_eggspercrate => @EggsPerCrate::int, p_openingcashwithdriver => @OpeningCashWithDriver::numeric, p_notes => @Notes::text, p_createdby => @CreatedBy::text, p_itemsjson => @ItemsJson::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@LoadDate", (object?)req.LoadDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PoultryVehicleId", req.PoultryVehicleId);
            cmd.Parameters.AddWithValue("@PoultryDriverId", (object?)req.PoultryDriverId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AssistantStaffId", (object?)req.AssistantStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PoultryRouteId", (object?)req.PoultryRouteId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EggsPerCrate", 30);
            cmd.Parameters.AddWithValue("@OpeningCashWithDriver", req.OpeningCashWithDriver);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)req.CreatedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ItemsJson", Json(req.Items));
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ApproveLoadingAsync(int id, string farmId, string? approvedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryvehicleloading_approve(p_poultryvehicleloadingid => @PoultryVehicleLoadingId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", c);
            cmd.Parameters.AddWithValue("@PoultryVehicleLoadingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelLoadingAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryvehicleloading_cancel(p_poultryvehicleloadingid => @PoultryVehicleLoadingId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryVehicleLoadingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task VoidLoadingAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryvehicleloading_void(p_poultryvehicleloadingid => @PoultryVehicleLoadingId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryVehicleLoadingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task<int> ReloadLoadingAsync(int id, string farmId, string? createdBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryvehicleloading_reload(p_poultryvehicleloadingid => @PoultryVehicleLoadingId::int, p_farmid => @FarmId::text, p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@PoultryVehicleLoadingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        private static PoultryVehicleLoadingModel ReadLoading(NpgsqlDataReader r) => new()
        {
            PoultryVehicleLoadingId = r.Int("PoultryVehicleLoadingId"),
            FarmId = r.Str("FarmId"),
            LoadDate = r.Date("LoadDate"),
            PoultryVehicleId = r.Int("PoultryVehicleId"),
            PoultryDriverId = r.IntN("PoultryDriverId"),
            AssistantStaffId = r.IntN("AssistantStaffId"),
            PoultryRouteId = r.IntN("PoultryRouteId"),
            PoultryProductId = r.Int("PoultryProductId"),
            CratesLoaded = r.Int("CratesLoaded"),
            EggsPerCrate = r.Int("EggsPerCrate"),
            ExpectedSellingPricePerCrate = r.Dec("ExpectedSellingPricePerCrate"),
            ExpectedCash = r.Dec("ExpectedCash"),
            OpeningCashWithDriver = r.Dec("OpeningCashWithDriver"),
            LoadedByStaffId = r.IntN("LoadedByStaffId"),
            Status = r.Str("Status"),
            Notes = r.StrN("Notes"),
            CreatedBy = r.StrN("CreatedBy"),
            ApprovedBy = r.StrN("ApprovedBy"),
            ApprovedAt = r.DateN("ApprovedAt"),
            CreatedAt = r.Date("CreatedAt"),
            UpdatedAt = r.DateN("UpdatedAt"),
            IsDeleted = r.Bool("IsDeleted"),
            VehicleName = r.Has("VehicleName") ? r.StrN("VehicleName") : null,
            RegistrationNumber = r.Has("RegistrationNumber") ? r.StrN("RegistrationNumber") : null,
            DriverName = r.Has("DriverName") ? r.StrN("DriverName") : null,
            RouteName = r.Has("RouteName") ? r.StrN("RouteName") : null,
            ProductName = r.Has("ProductName") ? r.StrN("ProductName") : null,
        };

        // ====================================================================
        // Driver Returns
        // ====================================================================
        public async Task<List<PoultryDriverReturnModel>> GetReturnsAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryDriverReturnModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriverreturn_getall(p_farmid => @FarmId::text, p_status => @Status::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadReturn(r));
            return list;
        }

        public async Task<PoultryDriverReturnModel?> GetReturnAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriverreturn_getbyid(p_poultrydriverreturnid => @PoultryDriverReturnId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDriverReturnId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadReturn(r) : null;
        }

        public async Task<List<PoultryDriverReturnItemModel>> GetReturnItemsAsync(int returnId, string farmId)
        {
            var list = new List<PoultryDriverReturnItemModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriverreturn_getitems(p_poultrydriverreturnid => @PoultryDriverReturnId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDriverReturnId", returnId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryDriverReturnItemModel
            {
                PoultryDriverReturnItemId = r.Int("PoultryDriverReturnItemId"),
                PoultryDriverReturnId = r.Int("PoultryDriverReturnId"),
                PoultryProductId = r.Int("PoultryProductId"),
                ProductName = r.StrN("ProductName"),
                CratesLoaded = r.Int("CratesLoaded"),
                CratesSold = r.Int("CratesSold"),
                CratesReturned = r.Int("CratesReturned"),
                CratesDamaged = r.Int("CratesDamaged"),
                UnitPrice = r.Dec("UnitPrice"),
                ExpectedSales = r.Dec("ExpectedSales"),
                Notes = r.StrN("Notes"),
                CreatedAt = r.Date("CreatedAt"),
                UpdatedAt = r.DateN("UpdatedAt"),
            });
            return list;
        }

        public async Task<List<PoultryDriverReturnCustomerSaleRow>> GetReturnCustomerSalesAsync(int returnId, string farmId)
        {
            var sales = new List<PoultryDriverReturnCustomerSaleRow>();
            var byId = new Dictionary<int, PoultryDriverReturnCustomerSaleRow>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriverreturn_getcustomersales_rs1(p_poultrydriverreturnid => @PoultryDriverReturnId::int, p_farmid => @FarmId::text); SELECT * FROM sppoultrydriverreturn_getcustomersales_rs2(p_poultrydriverreturnid => @PoultryDriverReturnId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDriverReturnId", returnId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var row = new PoultryDriverReturnCustomerSaleRow
                {
                    PoultryDriverReturnCustomerSaleId = r.Int("PoultryDriverReturnCustomerSaleId"),
                    PoultryDriverReturnId = r.Int("PoultryDriverReturnId"),
                    CustomerId = r.IntN("CustomerId"),
                    CustomerLabel = r.StrN("CustomerLabel"),
                    TotalAmount = r.Dec("TotalAmount"),
                    CashPaid = r.Dec("CashPaid"),
                    MoMoPaid = r.Dec("MoMoPaid"),
                    BankPaid = r.Dec("BankPaid"),
                    CreditAmount = r.Dec("CreditAmount"),
                    GeneratedSaleId = r.IntN("GeneratedSaleId"),
                    Notes = r.StrN("Notes"),
                    CreatedAt = r.Date("CreatedAt"),
                    UpdatedAt = r.DateN("UpdatedAt"),
                };
                sales.Add(row);
                byId[row.PoultryDriverReturnCustomerSaleId] = row;
            }
            if (await r.NextResultAsync())
            {
                while (await r.ReadAsync())
                {
                    var saleId = r.Int("PoultryDriverReturnCustomerSaleId");
                    if (!byId.TryGetValue(saleId, out var sale)) continue;
                    sale.Items.Add(new PoultryDriverReturnCustomerSaleItemRow
                    {
                        PoultryDriverReturnCustomerSaleItemId = r.Int("PoultryDriverReturnCustomerSaleItemId"),
                        PoultryDriverReturnCustomerSaleId = saleId,
                        PoultryProductId = r.Int("PoultryProductId"),
                        ProductName = r.StrN("ProductName"),
                        Quantity = r.Int("Quantity"),
                        UnitPrice = r.Dec("UnitPrice"),
                        LineTotal = r.Dec("LineTotal"),
                    });
                }
            }
            return sales;
        }

        public async Task<List<PoultryDriverDeliveryExpenseModel>> GetReturnExpensesAsync(int returnId, string farmId)
        {
            var list = new List<PoultryDriverDeliveryExpenseModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriverdeliveryexpense_getbyreturn(p_poultrydriverreturnid => @PoultryDriverReturnId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDriverReturnId", returnId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadExpense(r));
            return list;
        }

        public async Task<int> InsertReturnAsync(PoultryDriverReturnCreateRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriverreturn_insert(p_farmid => @FarmId::text, p_poultryvehicleloadingid => @PoultryVehicleLoadingId::int, p_returndate => @ReturnDate::timestamp, p_cratessold => @CratesSold::int, p_cratesreturned => @CratesReturned::int, p_cratesdamaged => @CratesDamaged::int, p_missingcrates => @MissingCrates::int, p_cashcollected => @CashCollected::numeric, p_momocollected => @MoMoCollected::numeric, p_bankcollected => @BankCollected::numeric, p_creditsalesamount => @CreditSalesAmount::numeric, p_cashreturnedbydriver => @CashReturnedByDriver::numeric, p_approveddeliveryexpenses => @ApprovedDeliveryExpenses::numeric, p_salespostingmode => @SalesPostingMode::text, p_primarycustomerid => @PrimaryCustomerId::int, p_reconciledbystaffid => @ReconciledByStaffId::int, p_notes => @Notes::text, p_createdby => @CreatedBy::text, p_itemsjson => @ItemsJson::text, p_customersalesjson => @CustomerSalesJson::text, p_expensesjson => @ExpensesJson::text)", c);
            AddReturnParams(cmd, req);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ApproveReturnAsync(int id, string farmId, string? approvedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriverreturn_approve(p_poultrydriverreturnid => @PoultryDriverReturnId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDriverReturnId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task ApproveReconcileReturnAsync(PoultryDriverReturnCreateRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriverreturn_approvereconcile(p_farmid => @FarmId::text, p_poultryvehicleloadingid => @PoultryVehicleLoadingId::int, p_returndate => @ReturnDate::timestamp, p_cratessold => @CratesSold::int, p_cratesreturned => @CratesReturned::int, p_cratesdamaged => @CratesDamaged::int, p_missingcrates => @MissingCrates::int, p_cashcollected => @CashCollected::numeric, p_momocollected => @MoMoCollected::numeric, p_bankcollected => @BankCollected::numeric, p_creditsalesamount => @CreditSalesAmount::numeric, p_cashreturnedbydriver => @CashReturnedByDriver::numeric, p_approveddeliveryexpenses => @ApprovedDeliveryExpenses::numeric, p_salespostingmode => @SalesPostingMode::text, p_primarycustomerid => @PrimaryCustomerId::int, p_reconciledbystaffid => @ReconciledByStaffId::int, p_notes => @Notes::text, p_createdby => @CreatedBy::text, p_itemsjson => @ItemsJson::text, p_customersalesjson => @CustomerSalesJson::text, p_expensesjson => @ExpensesJson::text)", c);
            AddReturnParams(cmd, req, includeOutput: false);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelReturnAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriverreturn_cancel(p_poultrydriverreturnid => @PoultryDriverReturnId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDriverReturnId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task UncancelReturnAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriverreturn_uncancel(p_poultrydriverreturnid => @PoultryDriverReturnId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDriverReturnId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReverseReturnAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriverreturn_reverse(p_poultrydriverreturnid => @PoultryDriverReturnId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDriverReturnId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteReturnAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriverreturn_delete(p_poultrydriverreturnid => @PoultryDriverReturnId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDriverReturnId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task UpdateReturnPostingModeAsync(int id, string farmId, string salesPostingMode)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sppoultrydriverreturn_updatepostingmode(p_poultrydriverreturnid => @PoultryDriverReturnId::int, p_farmid => @FarmId::text, p_salespostingmode => @SalesPostingMode::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDriverReturnId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@SalesPostingMode", salesPostingMode);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        // Shared parameter binding for Insert + ApproveReconcile (same signature,
        // except Insert carries the @NewReturnId OUTPUT — harmless to omit since
        // both SPs also SELECT the id).
        private static void AddReturnParams(NpgsqlCommand cmd, PoultryDriverReturnCreateRequest req, bool includeOutput = false)
        {
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@PoultryVehicleLoadingId", req.PoultryVehicleLoadingId);
            cmd.Parameters.AddWithValue("@ReturnDate", (object?)req.ReturnDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CratesSold", req.CratesSold);
            cmd.Parameters.AddWithValue("@CratesReturned", req.CratesReturned);
            cmd.Parameters.AddWithValue("@CratesDamaged", req.CratesDamaged);
            cmd.Parameters.AddWithValue("@MissingCrates", req.MissingCrates);
            cmd.Parameters.AddWithValue("@CashCollected", req.CashCollected);
            cmd.Parameters.AddWithValue("@MoMoCollected", req.MoMoCollected);
            cmd.Parameters.AddWithValue("@BankCollected", req.BankCollected);
            cmd.Parameters.AddWithValue("@CreditSalesAmount", req.CreditSalesAmount);
            cmd.Parameters.AddWithValue("@CashReturnedByDriver", req.CashReturnedByDriver);
            cmd.Parameters.AddWithValue("@ApprovedDeliveryExpenses", req.ApprovedDeliveryExpenses);
            cmd.Parameters.AddWithValue("@SalesPostingMode", (object?)req.SalesPostingMode ?? "Detailed");
            cmd.Parameters.AddWithValue("@PrimaryCustomerId", (object?)req.PrimaryCustomerId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ReconciledByStaffId", (object?)req.ReconciledByStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)req.CreatedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ItemsJson", Json(req.Items));
            cmd.Parameters.AddWithValue("@CustomerSalesJson", Json(req.CustomerSales));
            cmd.Parameters.AddWithValue("@ExpensesJson", Json(req.Expenses));
            if (includeOutput)
                cmd.Parameters.Add(new NpgsqlParameter("@NewReturnId", NpgsqlDbType.Integer) { Direction = ParameterDirection.Output });
        }

        private static PoultryDriverReturnModel ReadReturn(NpgsqlDataReader r) => new()
        {
            PoultryDriverReturnId = r.Int("PoultryDriverReturnId"),
            FarmId = r.Str("FarmId"),
            PoultryVehicleLoadingId = r.Int("PoultryVehicleLoadingId"),
            ReturnDate = r.Date("ReturnDate"),
            CratesSold = r.Int("CratesSold"),
            CratesReturned = r.Int("CratesReturned"),
            CratesDamaged = r.Int("CratesDamaged"),
            MissingCrates = r.Int("MissingCrates"),
            CashCollected = r.Dec("CashCollected"),
            MoMoCollected = r.Dec("MoMoCollected"),
            BankCollected = r.Dec("BankCollected"),
            CreditSalesAmount = r.Dec("CreditSalesAmount"),
            TotalAccountedFor = r.Dec("TotalAccountedFor"),
            CashReturnedByDriver = r.Dec("CashReturnedByDriver"),
            ApprovedDeliveryExpenses = r.Dec("ApprovedDeliveryExpenses"),
            ShortageAmount = r.Dec("ShortageAmount"),
            OverageAmount = r.Dec("OverageAmount"),
            SalesPostingMode = r.Str("SalesPostingMode"),
            PrimaryCustomerId = r.IntN("PrimaryCustomerId"),
            LinkedCashAdjId = r.IntN("LinkedCashAdjId"),
            ReconciledByStaffId = r.IntN("ReconciledByStaffId"),
            Status = r.Str("Status"),
            Notes = r.StrN("Notes"),
            CreatedBy = r.StrN("CreatedBy"),
            ApprovedBy = r.StrN("ApprovedBy"),
            ApprovedAt = r.DateN("ApprovedAt"),
            CreatedAt = r.Date("CreatedAt"),
            UpdatedAt = r.DateN("UpdatedAt"),
            PoultryVehicleId = r.Has("PoultryVehicleId") ? r.IntN("PoultryVehicleId") : null,
            PoultryDriverId = r.Has("PoultryDriverId") ? r.IntN("PoultryDriverId") : null,
            PoultryRouteId = r.Has("PoultryRouteId") ? r.IntN("PoultryRouteId") : null,
            LoadingCratesLoaded = r.Has("LoadingCratesLoaded") ? r.IntN("LoadingCratesLoaded") : null,
            LoadingExpectedCash = r.Has("LoadingExpectedCash") ? r.DecN("LoadingExpectedCash") : null,
            VehicleName = r.Has("VehicleName") ? r.StrN("VehicleName") : null,
            DriverName = r.Has("DriverName") ? r.StrN("DriverName") : null,
            RouteName = r.Has("RouteName") ? r.StrN("RouteName") : null,
        };

        // ====================================================================
        // Delivery Expenses
        // ====================================================================
        public async Task<List<PoultryDriverDeliveryExpenseModel>> ListDeliveryExpensesAsync(string farmId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryDriverDeliveryExpenseModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydriverdeliveryexpense_listall(p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadExpense(r));
            return list;
        }

        private static PoultryDriverDeliveryExpenseModel ReadExpense(NpgsqlDataReader r) => new()
        {
            PoultryDriverDeliveryExpenseId = r.Int("PoultryDriverDeliveryExpenseId"),
            FarmId = r.Str("FarmId"),
            PoultryDriverReturnId = r.IntN("PoultryDriverReturnId"),
            PoultryVehicleLoadingId = r.IntN("PoultryVehicleLoadingId"),
            ExpenseCategory = r.Str("ExpenseCategory"),
            Amount = r.Dec("Amount"),
            Description = r.StrN("Description"),
            IsApproved = r.Bool("IsApproved"),
            LinkedExpenseId = r.IntN("LinkedExpenseId"),
            Notes = r.StrN("Notes"),
            CreatedBy = r.StrN("CreatedBy"),
            CreatedAt = r.Date("CreatedAt"),
            UpdatedAt = r.DateN("UpdatedAt"),
            ReturnDate = r.Has("ReturnDate") ? r.DateN("ReturnDate") : null,
            PoultryDriverId = r.Has("PoultryDriverId") ? r.IntN("PoultryDriverId") : null,
            DriverName = r.Has("DriverName") ? r.StrN("DriverName") : null,
        };

        // ====================================================================
        // Shortages
        // ====================================================================
        public async Task<List<PoultryDriverShortageModel>> GetShortagesAsync(string farmId, string? status)
        {
            var list = new List<PoultryDriverShortageModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydrivershortage_getall(p_farmid => @FarmId::text, p_status => @Status::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryDriverShortageModel
            {
                PoultryDriverShortageId = r.Int("PoultryDriverShortageId"),
                FarmId = r.Str("FarmId"),
                PoultryDriverId = r.IntN("PoultryDriverId"),
                PoultryVehicleLoadingId = r.IntN("PoultryVehicleLoadingId"),
                PoultryDriverReturnId = r.Int("PoultryDriverReturnId"),
                ShortageDate = r.Date("ShortageDate"),
                ExpectedAmount = r.Dec("ExpectedAmount"),
                ActualAmount = r.Dec("ActualAmount"),
                ShortageAmount = r.Dec("ShortageAmount"),
                Reason = r.StrN("Reason"),
                Status = r.Str("Status"),
                ApprovedBy = r.StrN("ApprovedBy"),
                Notes = r.StrN("Notes"),
                CreatedAt = r.Date("CreatedAt"),
                UpdatedAt = r.DateN("UpdatedAt"),
                DriverName = r.Has("DriverName") ? r.StrN("DriverName") : null,
            });
            return list;
        }

        public async Task ResolveShortageAsync(int id, PoultryDriverShortageResolveRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydrivershortage_resolve(p_poultrydrivershortageid => @PoultryDriverShortageId::int, p_farmid => @FarmId::text, p_status => @Status::text, p_approvedby => @ApprovedBy::text, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDriverShortageId", id);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Status", req.Status);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)req.ApprovedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        // ====================================================================
        // Reports
        // ====================================================================
        public async Task<List<PoultryDriverReconciliationRow>> GetDriverReconciliationAsync(string farmId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryDriverReconciliationRow>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryreport_driverreconciliation(p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryDriverReconciliationRow
            {
                PoultryDriverId = r.IntN("PoultryDriverId"),
                DriverName = r.StrN("DriverName"),
                DeliveryRuns = r.Int("DeliveryRuns"),
                TotalCratesLoaded = r.Int("TotalCratesLoaded"),
                TotalCratesSold = r.Int("TotalCratesSold"),
                TotalCratesReturned = r.Int("TotalCratesReturned"),
                TotalCratesLost = r.Int("TotalCratesLost"),
                ExpectedRevenue = r.Dec("ExpectedRevenue"),
                AccountedRevenue = r.Dec("AccountedRevenue"),
                TotalShortage = r.Dec("TotalShortage"),
                TotalOverage = r.Dec("TotalOverage"),
            });
            return list;
        }

        public async Task<PoultryDriverCollectionReport> GetDriverCollectionAsync(string farmId, DateTime? fromDate, DateTime? toDate, int? poultryDriverId)
        {
            var report = new PoultryDriverCollectionReport();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydrivercollection_rs1(p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date, p_poultrydriverid => @PoultryDriverId::int); SELECT * FROM sppoultrydrivercollection_rs2(p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date, p_poultrydriverid => @PoultryDriverId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PoultryDriverId", (object?)poultryDriverId ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) report.Detail.Add(new PoultryDriverCollectionDetailRow
            {
                PoultryDriverId = r.IntN("PoultryDriverId"),
                DriverName = r.StrN("DriverName"),
                PoultryDriverReturnId = r.Int("PoultryDriverReturnId"),
                ReturnDate = r.Date("ReturnDate"),
                ProductName = r.StrN("ProductName"),
                CratesLoaded = r.Int("CratesLoaded"),
                CratesSold = r.Int("CratesSold"),
                CratesReturned = r.Int("CratesReturned"),
                CratesDamaged = r.Int("CratesDamaged"),
                ExpectedAmount = r.Dec("ExpectedAmount"),
            });
            if (await r.NextResultAsync())
                while (await r.ReadAsync()) report.Totals.Add(new PoultryDriverCollectionTotalsRow
                {
                    PoultryDriverId = r.IntN("PoultryDriverId"),
                    DriverName = r.StrN("DriverName"),
                    DeliveryRuns = r.Int("DeliveryRuns"),
                    TotalCratesLoaded = r.Int("TotalCratesLoaded"),
                    TotalCratesSold = r.Int("TotalCratesSold"),
                    TotalCratesReturned = r.Int("TotalCratesReturned"),
                    TotalCratesLost = r.Int("TotalCratesLost"),
                    TotalExpected = r.Dec("TotalExpected"),
                    TotalCollected = r.Dec("TotalCollected"),
                    TotalShortage = r.Dec("TotalShortage"),
                });
            return report;
        }
    }
}
