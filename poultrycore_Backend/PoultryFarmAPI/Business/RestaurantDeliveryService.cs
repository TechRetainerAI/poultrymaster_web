using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class RestaurantDeliveryService : IRestaurantDeliveryService
    {
        private readonly string _cs;
        public RestaurantDeliveryService(string cs) => _cs = cs;

        // =====================================================================
        // DRIVERS
        // =====================================================================

        public async Task<List<RestaurantDriverModel>> ListDriversAsync(string farmId, string? status = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_driver_list(p_farmid=>@F::text,p_status=>@S::text)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@S", (object?)status ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantDriverModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                DriverId = r.GetInt32(r.GetOrdinal("driverid")), FarmId = r.GetString(r.GetOrdinal("farmid")),
                FirstName = r.GetString(r.GetOrdinal("firstname")), LastName = r.GetString(r.GetOrdinal("lastname")),
                Phone = r.GetString(r.GetOrdinal("phone")),
                Email = r.IsDBNull(r.GetOrdinal("email")) ? null : r.GetString(r.GetOrdinal("email")),
                VehicleType = r.GetString(r.GetOrdinal("vehicletype")),
                VehiclePlate = r.IsDBNull(r.GetOrdinal("vehicleplate")) ? null : r.GetString(r.GetOrdinal("vehicleplate")),
                LicenseNumber = r.IsDBNull(r.GetOrdinal("licensenumber")) ? null : r.GetString(r.GetOrdinal("licensenumber")),
                Status = r.GetString(r.GetOrdinal("status")),
                CurrentLatitude = r.IsDBNull(r.GetOrdinal("currentlatitude")) ? null : r.GetDecimal(r.GetOrdinal("currentlatitude")),
                CurrentLongitude = r.IsDBNull(r.GetOrdinal("currentlongitude")) ? null : r.GetDecimal(r.GetOrdinal("currentlongitude")),
                LastLocationUpdate = r.IsDBNull(r.GetOrdinal("lastlocationupdate")) ? null : r.GetDateTime(r.GetOrdinal("lastlocationupdate")),
                IsActive = r.GetBoolean(r.GetOrdinal("isactive")),
                Notes = r.IsDBNull(r.GetOrdinal("notes")) ? null : r.GetString(r.GetOrdinal("notes")),
                CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
                ActiveDeliveries = r.GetInt64(r.GetOrdinal("activedeliveries")),
                TotalDeliveries = r.GetInt64(r.GetOrdinal("totaldeliveries")),
                AvgRating = r.IsDBNull(r.GetOrdinal("avgrating")) ? null : r.GetDouble(r.GetOrdinal("avgrating")),
            });
            return list;
        }

        public async Task<int> InsertDriverAsync(RestaurantDriverModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "INSERT INTO restaurantdrivers (farmid, firstname, lastname, phone, email, vehicletype, vehicleplate, licensenumber, notes) " +
                "VALUES (@FarmId, @FirstName, @LastName, @Phone, @Email, @Vehicle, @Plate, @License, @Notes) RETURNING driverid", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId); cmd.Parameters.AddWithValue("@FirstName", m.FirstName);
            cmd.Parameters.AddWithValue("@LastName", m.LastName); cmd.Parameters.AddWithValue("@Phone", m.Phone);
            cmd.Parameters.AddWithValue("@Email", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Vehicle", m.VehicleType);
            cmd.Parameters.AddWithValue("@Plate", (object?)m.VehiclePlate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@License", (object?)m.LicenseNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateDriverAsync(RestaurantDriverModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "UPDATE restaurantdrivers SET firstname=@FirstName, lastname=@LastName, phone=@Phone, email=@Email, " +
                "vehicletype=@Vehicle, vehicleplate=@Plate, licensenumber=@License, isactive=@Active, notes=@Notes, updatedat=NOW() " +
                "WHERE driverid=@DriverId AND farmid=@FarmId", conn);
            cmd.Parameters.AddWithValue("@DriverId", m.DriverId); cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FirstName", m.FirstName); cmd.Parameters.AddWithValue("@LastName", m.LastName);
            cmd.Parameters.AddWithValue("@Phone", m.Phone); cmd.Parameters.AddWithValue("@Email", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Vehicle", m.VehicleType); cmd.Parameters.AddWithValue("@Plate", (object?)m.VehiclePlate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@License", (object?)m.LicenseNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Active", m.IsActive); cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteDriverAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_driver_delete(p_id=>@I::int,p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@I", id); cmd.Parameters.AddWithValue("@F", farmId);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task UpdateDriverStatusAsync(int id, string farmId, string status)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_driver_update_status(p_id=>@I::int,p_farmid=>@F::text,p_status=>@S::text)", conn);
            cmd.Parameters.AddWithValue("@I", id); cmd.Parameters.AddWithValue("@F", farmId); cmd.Parameters.AddWithValue("@S", status);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task UpdateDriverLocationAsync(int id, string farmId, decimal lat, decimal lng)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_driver_update_location(p_id=>@I::int,p_farmid=>@F::text,p_lat=>@La::numeric,p_lng=>@Lo::numeric)", conn);
            cmd.Parameters.AddWithValue("@I", id); cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@La", lat); cmd.Parameters.AddWithValue("@Lo", lng);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task<DriverStatsModel> GetDriverStatsAsync(int driverId, string farmId, DateTime? fromDate = null, DateTime? toDate = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_driver_stats(p_driverid=>@I::int,p_farmid=>@F::text,p_fromdate=>@A::date,p_todate=>@B::date)", conn);
            cmd.Parameters.AddWithValue("@I", driverId); cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@A", (object?)fromDate ?? DBNull.Value); cmd.Parameters.AddWithValue("@B", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync()) return new()
            {
                TotalDeliveries = r.GetInt64(0), CompletedDeliveries = r.GetInt64(1), FailedDeliveries = r.GetInt64(2),
                AvgDeliveryMins = r.IsDBNull(3) ? null : r.GetDouble(3), AvgRating = r.IsDBNull(4) ? null : r.GetDouble(4),
                TotalDeliveryFees = r.GetDecimal(5),
            };
            return new();
        }

        // =====================================================================
        // DELIVERY ZONES
        // =====================================================================

        public async Task<List<RestaurantDeliveryZoneModel>> ListZonesAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_deliveryzone_list(p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantDeliveryZoneModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                DeliveryZoneId = r.GetInt32(r.GetOrdinal("deliveryzoneid")), FarmId = r.GetString(r.GetOrdinal("farmid")),
                Name = r.GetString(r.GetOrdinal("name")), MinDistanceKm = r.GetDecimal(r.GetOrdinal("mindistancekm")),
                MaxDistanceKm = r.GetDecimal(r.GetOrdinal("maxdistancekm")), DeliveryFee = r.GetDecimal(r.GetOrdinal("deliveryfee")),
                EstimatedMins = r.GetInt32(r.GetOrdinal("estimatedmins")), IsActive = r.GetBoolean(r.GetOrdinal("isactive")),
                SortOrder = r.GetInt32(r.GetOrdinal("sortorder")), CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
            });
            return list;
        }

        public async Task<int> InsertZoneAsync(RestaurantDeliveryZoneModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "INSERT INTO restaurantdeliveryzones (farmid, name, mindistancekm, maxdistancekm, deliveryfee, estimatedmins, isactive, sortorder) " +
                "VALUES (@FarmId, @ZoneName, @MinDist, @MaxDist, @Fee, @EstMins, @Active, @Sort) RETURNING deliveryzoneid", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId); cmd.Parameters.AddWithValue("@ZoneName", m.Name);
            cmd.Parameters.AddWithValue("@MinDist", m.MinDistanceKm); cmd.Parameters.AddWithValue("@MaxDist", m.MaxDistanceKm);
            cmd.Parameters.AddWithValue("@Fee", m.DeliveryFee); cmd.Parameters.AddWithValue("@EstMins", m.EstimatedMins);
            cmd.Parameters.AddWithValue("@Active", m.IsActive); cmd.Parameters.AddWithValue("@Sort", m.SortOrder);
            await conn.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateZoneAsync(RestaurantDeliveryZoneModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "UPDATE restaurantdeliveryzones SET name=@ZoneName, mindistancekm=@MinDist, maxdistancekm=@MaxDist, " +
                "deliveryfee=@Fee, estimatedmins=@EstMins, isactive=@Active, sortorder=@Sort, updatedat=NOW() " +
                "WHERE deliveryzoneid=@ZoneId AND farmid=@FarmId", conn);
            cmd.Parameters.AddWithValue("@ZoneId", m.DeliveryZoneId); cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@ZoneName", m.Name); cmd.Parameters.AddWithValue("@MinDist", m.MinDistanceKm);
            cmd.Parameters.AddWithValue("@MaxDist", m.MaxDistanceKm); cmd.Parameters.AddWithValue("@Fee", m.DeliveryFee);
            cmd.Parameters.AddWithValue("@EstMins", m.EstimatedMins); cmd.Parameters.AddWithValue("@Active", m.IsActive);
            cmd.Parameters.AddWithValue("@Sort", m.SortOrder);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteZoneAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_deliveryzone_delete(p_id=>@I::int,p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@I", id); cmd.Parameters.AddWithValue("@F", farmId);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // ASSIGNMENTS
        // =====================================================================

        public async Task<List<RestaurantDeliveryAssignmentModel>> ListAssignmentsAsync(string farmId, string? status = null, int? driverId = null, DateTime? fromDate = null, DateTime? toDate = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_deliveryassignment_list(p_farmid=>@F::text,p_status=>@S::text," +
                "p_driverid=>@D::int,p_fromdate=>@A::timestamp,p_todate=>@B::timestamp)", conn);
            cmd.Parameters.AddWithValue("@F", farmId); cmd.Parameters.AddWithValue("@S", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@D", (object?)driverId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@A", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@B", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantDeliveryAssignmentModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                DeliveryAssignmentId = r.GetInt32(r.GetOrdinal("deliveryassignmentid")),
                FarmId = r.GetString(r.GetOrdinal("farmid")), OrderId = r.GetInt32(r.GetOrdinal("orderid")),
                OrderNumber = r.IsDBNull(r.GetOrdinal("ordernumber")) ? null : r.GetString(r.GetOrdinal("ordernumber")),
                DriverId = r.IsDBNull(r.GetOrdinal("driverid")) ? null : r.GetInt32(r.GetOrdinal("driverid")),
                DriverName = r.IsDBNull(r.GetOrdinal("drivername")) ? null : r.GetString(r.GetOrdinal("drivername")),
                DriverPhone = r.IsDBNull(r.GetOrdinal("driverphone")) ? null : r.GetString(r.GetOrdinal("driverphone")),
                Status = r.GetString(r.GetOrdinal("status")),
                AssignedAt = r.IsDBNull(r.GetOrdinal("assignedat")) ? null : r.GetDateTime(r.GetOrdinal("assignedat")),
                PickedUpAt = r.IsDBNull(r.GetOrdinal("pickedupat")) ? null : r.GetDateTime(r.GetOrdinal("pickedupat")),
                DeliveredAt = r.IsDBNull(r.GetOrdinal("deliveredat")) ? null : r.GetDateTime(r.GetOrdinal("deliveredat")),
                DeliveryAddress = r.IsDBNull(r.GetOrdinal("deliveryaddress")) ? null : r.GetString(r.GetOrdinal("deliveryaddress")),
                DeliveryNotes = r.IsDBNull(r.GetOrdinal("deliverynotes")) ? null : r.GetString(r.GetOrdinal("deliverynotes")),
                DeliveryZoneId = r.IsDBNull(r.GetOrdinal("deliveryzoneid")) ? null : r.GetInt32(r.GetOrdinal("deliveryzoneid")),
                DeliveryFee = r.GetDecimal(r.GetOrdinal("deliveryfee")),
                EstimatedMins = r.IsDBNull(r.GetOrdinal("estimatedmins")) ? null : r.GetInt32(r.GetOrdinal("estimatedmins")),
                ActualMins = r.IsDBNull(r.GetOrdinal("actualmins")) ? null : r.GetInt32(r.GetOrdinal("actualmins")),
                DistanceKm = r.IsDBNull(r.GetOrdinal("distancekm")) ? null : r.GetDecimal(r.GetOrdinal("distancekm")),
                ProofType = r.IsDBNull(r.GetOrdinal("prooftype")) ? null : r.GetString(r.GetOrdinal("prooftype")),
                ProofData = r.IsDBNull(r.GetOrdinal("proofdata")) ? null : r.GetString(r.GetOrdinal("proofdata")),
                Rating = r.IsDBNull(r.GetOrdinal("rating")) ? null : r.GetInt32(r.GetOrdinal("rating")),
                FailReason = r.IsDBNull(r.GetOrdinal("failreason")) ? null : r.GetString(r.GetOrdinal("failreason")),
                CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
            });
            return list;
        }

        public async Task<int> CreateAssignmentAsync(string farmId, int orderId, string orderNumber, int driverId,
            string? deliveryAddress, string? deliveryNotes, int? zoneId, decimal deliveryFee, int? estimatedMins)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_deliveryassignment_create(p_farmid=>@F::text,p_orderid=>@O::int," +
                "p_ordernumber=>@ON::text,p_driverid=>@D::int,p_deliveryaddress=>@A::text," +
                "p_deliverynotes=>@N::text,p_deliveryzoneid=>@Z::int,p_deliveryfee=>@Fe::numeric," +
                "p_estimatedmins=>@E::int)", conn);
            cmd.Parameters.AddWithValue("@F", farmId); cmd.Parameters.AddWithValue("@O", orderId);
            cmd.Parameters.AddWithValue("@ON", orderNumber); cmd.Parameters.AddWithValue("@D", driverId);
            cmd.Parameters.AddWithValue("@A", (object?)deliveryAddress ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@N", (object?)deliveryNotes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Z", (object?)zoneId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Fe", deliveryFee);
            cmd.Parameters.AddWithValue("@E", (object?)estimatedMins ?? DBNull.Value);
            await conn.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAssignmentStatusAsync(int id, string farmId, string status, string? failReason = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_deliveryassignment_update_status(p_id=>@I::int,p_farmid=>@F::text," +
                "p_status=>@S::text,p_failreason=>@R::text)", conn);
            cmd.Parameters.AddWithValue("@I", id); cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@S", status); cmd.Parameters.AddWithValue("@R", (object?)failReason ?? DBNull.Value);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task RateAssignmentAsync(int id, string farmId, int rating)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_deliveryassignment_rate(p_id=>@I::int,p_farmid=>@F::text,p_rating=>@R::int)", conn);
            cmd.Parameters.AddWithValue("@I", id); cmd.Parameters.AddWithValue("@F", farmId); cmd.Parameters.AddWithValue("@R", rating);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task AddProofAsync(int id, string farmId, string proofType, string proofData)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_deliveryassignment_proof(p_id=>@I::int,p_farmid=>@F::text,p_prooftype=>@T::text,p_proofdata=>@D::text)", conn);
            cmd.Parameters.AddWithValue("@I", id); cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@T", proofType); cmd.Parameters.AddWithValue("@D", proofData);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // THIRD-PARTY PLATFORMS
        // =====================================================================

        public async Task<List<RestaurantThirdPartyPlatformModel>> ListPlatformsAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_thirdpartyplatform_list(p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantThirdPartyPlatformModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                PlatformId = r.GetInt32(r.GetOrdinal("platformid")), FarmId = r.GetString(r.GetOrdinal("farmid")),
                Name = r.GetString(r.GetOrdinal("name")),
                ApiKey = r.IsDBNull(r.GetOrdinal("apikey")) ? null : r.GetString(r.GetOrdinal("apikey")),
                ApiSecret = r.IsDBNull(r.GetOrdinal("apisecret")) ? null : r.GetString(r.GetOrdinal("apisecret")),
                StoreId = r.IsDBNull(r.GetOrdinal("storeid")) ? null : r.GetString(r.GetOrdinal("storeid")),
                CommissionRate = r.GetDecimal(r.GetOrdinal("commissionrate")),
                AutoAccept = r.GetBoolean(r.GetOrdinal("autoaccept")),
                IsEnabled = r.GetBoolean(r.GetOrdinal("isenabled")),
                IsActive = r.GetBoolean(r.GetOrdinal("isactive")),
                CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
                OrderCount = r.GetInt64(r.GetOrdinal("ordercount")),
                TotalRevenue = r.GetDecimal(r.GetOrdinal("totalrevenue")),
            });
            return list;
        }

        public async Task<int> InsertPlatformAsync(RestaurantThirdPartyPlatformModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "INSERT INTO restaurantthirdpartyplatforms (farmid,name,apikey,apisecret,storeid,commissionrate,autoaccept,isenabled) " +
                "VALUES (@FarmId,@PlatName,@ApiKey,@ApiSecret,@StoreId,@Commission,@AutoAccept,@IsEnabled) RETURNING platformid", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId); cmd.Parameters.AddWithValue("@PlatName", m.Name);
            cmd.Parameters.AddWithValue("@ApiKey", (object?)m.ApiKey ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ApiSecret", (object?)m.ApiSecret ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StoreId", (object?)m.StoreId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Commission", m.CommissionRate); cmd.Parameters.AddWithValue("@AutoAccept", m.AutoAccept);
            cmd.Parameters.AddWithValue("@IsEnabled", m.IsEnabled);
            await conn.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdatePlatformAsync(RestaurantThirdPartyPlatformModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "UPDATE restaurantthirdpartyplatforms SET name=@PlatName,apikey=@ApiKey,apisecret=@ApiSecret," +
                "storeid=@StoreId,commissionrate=@Commission,autoaccept=@AutoAccept,isenabled=@IsEnabled,updatedat=NOW() " +
                "WHERE platformid=@PlatId AND farmid=@FarmId", conn);
            cmd.Parameters.AddWithValue("@PlatId", m.PlatformId); cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@PlatName", m.Name); cmd.Parameters.AddWithValue("@ApiKey", (object?)m.ApiKey ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ApiSecret", (object?)m.ApiSecret ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StoreId", (object?)m.StoreId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Commission", m.CommissionRate); cmd.Parameters.AddWithValue("@AutoAccept", m.AutoAccept);
            cmd.Parameters.AddWithValue("@IsEnabled", m.IsEnabled);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeletePlatformAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_thirdpartyplatform_delete(p_id=>@I::int,p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@I", id); cmd.Parameters.AddWithValue("@F", farmId);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // THIRD-PARTY ORDERS
        // =====================================================================

        public async Task<List<RestaurantThirdPartyOrderModel>> ListThirdPartyOrdersAsync(string farmId, string? status = null, int? platformId = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_thirdpartyorder_list(p_farmid=>@F::text,p_status=>@S::text,p_platformid=>@P::int)", conn);
            cmd.Parameters.AddWithValue("@F", farmId); cmd.Parameters.AddWithValue("@S", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@P", (object?)platformId ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantThirdPartyOrderModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                ThirdPartyOrderId = r.GetInt32(r.GetOrdinal("thirdpartyorderid")),
                FarmId = r.GetString(r.GetOrdinal("farmid")),
                PlatformId = r.IsDBNull(r.GetOrdinal("platformid")) ? null : r.GetInt32(r.GetOrdinal("platformid")),
                PlatformName = r.GetString(r.GetOrdinal("platformname")),
                ExternalOrderId = r.GetString(r.GetOrdinal("externalorderid")),
                OrderId = r.IsDBNull(r.GetOrdinal("orderid")) ? null : r.GetInt32(r.GetOrdinal("orderid")),
                Status = r.GetString(r.GetOrdinal("status")),
                CustomerName = r.IsDBNull(r.GetOrdinal("customername")) ? null : r.GetString(r.GetOrdinal("customername")),
                CustomerPhone = r.IsDBNull(r.GetOrdinal("customerphone")) ? null : r.GetString(r.GetOrdinal("customerphone")),
                DeliveryAddress = r.IsDBNull(r.GetOrdinal("deliveryaddress")) ? null : r.GetString(r.GetOrdinal("deliveryaddress")),
                ItemsJson = r.IsDBNull(r.GetOrdinal("itemsjson")) ? null : r.GetString(r.GetOrdinal("itemsjson")),
                Subtotal = r.GetDecimal(r.GetOrdinal("subtotal")), DeliveryFee = r.GetDecimal(r.GetOrdinal("deliveryfee")),
                PlatformFee = r.GetDecimal(r.GetOrdinal("platformfee")), TotalAmount = r.GetDecimal(r.GetOrdinal("totalamount")),
                CommissionAmount = r.GetDecimal(r.GetOrdinal("commissionamount")), NetAmount = r.GetDecimal(r.GetOrdinal("netamount")),
                Notes = r.IsDBNull(r.GetOrdinal("notes")) ? null : r.GetString(r.GetOrdinal("notes")),
                ReceivedAt = r.IsDBNull(r.GetOrdinal("receivedat")) ? null : r.GetDateTime(r.GetOrdinal("receivedat")),
                AcceptedAt = r.IsDBNull(r.GetOrdinal("acceptedat")) ? null : r.GetDateTime(r.GetOrdinal("acceptedat")),
                RejectedAt = r.IsDBNull(r.GetOrdinal("rejectedat")) ? null : r.GetDateTime(r.GetOrdinal("rejectedat")),
                RejectReason = r.IsDBNull(r.GetOrdinal("rejectreason")) ? null : r.GetString(r.GetOrdinal("rejectreason")),
                CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
            });
            return list;
        }

        public async Task<int> InsertThirdPartyOrderAsync(RestaurantThirdPartyOrderModel m, decimal commissionRate)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_thirdpartyorder_insert(p_farmid=>@F::text,p_platformid=>@a::int," +
                "p_platformname=>@b::text,p_externalorderid=>@c::text,p_customername=>@d::text," +
                "p_customerphone=>@e::text,p_deliveryaddress=>@f::text,p_itemsjson=>@g::text," +
                "p_subtotal=>@h::numeric,p_deliveryfee=>@i::numeric,p_platformfee=>@j::numeric," +
                "p_totalamount=>@k::numeric,p_commissionrate=>@l::numeric,p_notes=>@m::text)", conn);
            cmd.Parameters.AddWithValue("@F", m.FarmId); cmd.Parameters.AddWithValue("@a", (object?)m.PlatformId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@b", m.PlatformName); cmd.Parameters.AddWithValue("@c", m.ExternalOrderId);
            cmd.Parameters.AddWithValue("@d", (object?)m.CustomerName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@e", (object?)m.CustomerPhone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@f", (object?)m.DeliveryAddress ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@g", (object?)m.ItemsJson ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@h", m.Subtotal); cmd.Parameters.AddWithValue("@i", m.DeliveryFee);
            cmd.Parameters.AddWithValue("@j", m.PlatformFee); cmd.Parameters.AddWithValue("@k", m.TotalAmount);
            cmd.Parameters.AddWithValue("@l", commissionRate); cmd.Parameters.AddWithValue("@m", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateThirdPartyOrderStatusAsync(int id, string farmId, string status, string? rejectReason = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_thirdpartyorder_update_status(p_id=>@I::int,p_farmid=>@F::text,p_status=>@S::text,p_rejectreason=>@R::text)", conn);
            cmd.Parameters.AddWithValue("@I", id); cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@S", status); cmd.Parameters.AddWithValue("@R", (object?)rejectReason ?? DBNull.Value);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // STATS
        // =====================================================================

        public async Task<DeliveryStatsModel> GetDeliveryStatsAsync(string farmId, DateTime? date = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_delivery_stats(p_farmid=>@F::text,p_date=>@D::date)", conn);
            cmd.Parameters.AddWithValue("@F", farmId); cmd.Parameters.AddWithValue("@D", (object?)date ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync()) return new()
            {
                TotalAssignments = r.GetInt64(0), PendingCount = r.GetInt64(1), ActiveCount = r.GetInt64(2),
                DeliveredCount = r.GetInt64(3), FailedCount = r.GetInt64(4),
                AvgDeliveryMins = r.IsDBNull(5) ? null : r.GetDouble(5),
                TotalFees = r.GetDecimal(6), AvailableDrivers = r.GetInt64(7), OnDeliveryDrivers = r.GetInt64(8),
            };
            return new();
        }
    }
}
