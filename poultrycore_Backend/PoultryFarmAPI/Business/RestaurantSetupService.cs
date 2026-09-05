using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class RestaurantSetupService : IRestaurantSetupService
    {
        private readonly string _cs;
        public RestaurantSetupService(string cs) => _cs = cs;
        public string GetConnectionString() => _cs;

        // =====================================================================
        // PROFILE
        // =====================================================================

        public async Task<RestaurantProfileModel?> GetProfileAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_profile_get(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadProfile(r) : null;
        }

        public async Task<RestaurantProfileModel> UpsertProfileAsync(RestaurantProfileModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_profile_upsert(" +
                "p_farmid => @FarmId::text, p_restaurantname => @RestaurantName::text, " +
                "p_address => @Address::text, p_city => @City::text, p_country => @Country::text, " +
                "p_phone => @Phone::text, p_email => @Email::text, p_cuisinetype => @CuisineType::text, " +
                "p_servicetypes => @ServiceTypes::text, p_openingtime => @OpeningTime::text, " +
                "p_closingtime => @ClosingTime::text, p_defaultcurrency => @DefaultCurrency::text, " +
                "p_taxrate => @TaxRate::numeric, p_servicechargerate => @ServiceChargeRate::numeric, " +
                "p_timezone => @TimeZone::text, p_logourl => @LogoUrl::text, " +
                "p_description => @Description::text, p_seatingcapacity => @SeatingCapacity::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@RestaurantName", m.RestaurantName);
            cmd.Parameters.AddWithValue("@Address", (object?)m.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@City", (object?)m.City ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Country", (object?)m.Country ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Phone", (object?)m.Phone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CuisineType", (object?)m.CuisineType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ServiceTypes", (object?)m.ServiceTypes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OpeningTime", m.OpeningTime);
            cmd.Parameters.AddWithValue("@ClosingTime", m.ClosingTime);
            cmd.Parameters.AddWithValue("@DefaultCurrency", m.DefaultCurrency);
            cmd.Parameters.AddWithValue("@TaxRate", m.TaxRate);
            cmd.Parameters.AddWithValue("@ServiceChargeRate", m.ServiceChargeRate);
            cmd.Parameters.AddWithValue("@TimeZone", (object?)m.TimeZone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LogoUrl", (object?)m.LogoUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SeatingCapacity", m.SeatingCapacity);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            return ReadProfile(r);
        }

        private static RestaurantProfileModel ReadProfile(NpgsqlDataReader r) => new()
        {
            RestaurantProfileId = r.GetInt32(r.GetOrdinal("restaurantprofileid")),
            FarmId              = r.GetString(r.GetOrdinal("farmid")),
            RestaurantName      = r.GetString(r.GetOrdinal("restaurantname")),
            Address             = r.IsDBNull(r.GetOrdinal("address")) ? null : r.GetString(r.GetOrdinal("address")),
            City                = r.IsDBNull(r.GetOrdinal("city")) ? null : r.GetString(r.GetOrdinal("city")),
            Country             = r.IsDBNull(r.GetOrdinal("country")) ? null : r.GetString(r.GetOrdinal("country")),
            Phone               = r.IsDBNull(r.GetOrdinal("phone")) ? null : r.GetString(r.GetOrdinal("phone")),
            Email               = r.IsDBNull(r.GetOrdinal("email")) ? null : r.GetString(r.GetOrdinal("email")),
            CuisineType         = r.IsDBNull(r.GetOrdinal("cuisinetype")) ? null : r.GetString(r.GetOrdinal("cuisinetype")),
            ServiceTypes        = r.IsDBNull(r.GetOrdinal("servicetypes")) ? null : r.GetString(r.GetOrdinal("servicetypes")),
            OpeningTime         = r.GetString(r.GetOrdinal("openingtime")),
            ClosingTime         = r.GetString(r.GetOrdinal("closingtime")),
            DefaultCurrency     = r.GetString(r.GetOrdinal("defaultcurrency")),
            TaxRate             = r.GetDecimal(r.GetOrdinal("taxrate")),
            ServiceChargeRate   = r.GetDecimal(r.GetOrdinal("servicechargerate")),
            TimeZone            = r.IsDBNull(r.GetOrdinal("timezone")) ? null : r.GetString(r.GetOrdinal("timezone")),
            LogoUrl             = r.IsDBNull(r.GetOrdinal("logourl")) ? null : r.GetString(r.GetOrdinal("logourl")),
            Description         = r.IsDBNull(r.GetOrdinal("description")) ? null : r.GetString(r.GetOrdinal("description")),
            SeatingCapacity     = r.GetInt32(r.GetOrdinal("seatingcapacity")),
            CreatedAt           = r.GetDateTime(r.GetOrdinal("createdat")),
            UpdatedAt           = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
        };
    }
}
