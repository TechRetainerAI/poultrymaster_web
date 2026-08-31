using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryCompanyService
    {
        Task<PoultryCompanyProfileModel?> GetProfileAsync(string farmId);
        Task<PoultryCompanyProfileModel?> SetupAsync(PoultryCompanySetupRequest req);
        Task<PoultryCompanyProfileModel?> UpdateProfileAsync(string farmId, PoultryCompanyUpdateRequest req);
    }

    /// <summary>
    /// Poultry company profile, mirroring WaterCompanyService (migration 049).
    /// Backed by sppoultrycompany_* from migration 212.
    /// </summary>
    public class PoultryCompanyService : IPoultryCompanyService
    {
        private readonly string _cs;
        public PoultryCompanyService(string cs) => _cs = cs;

        public async Task<PoultryCompanyProfileModel?> GetProfileAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrycompany_getprofile(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<PoultryCompanyProfileModel?> SetupAsync(PoultryCompanySetupRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrycompany_setup(" +
                "p_farmid => @FarmId::text, " +
                "p_brandname => @BrandName::text, " +
                "p_businesstype => @BusinessType::text, " +
                "p_farmsiteaddress => @FarmSiteAddress::text, " +
                "p_mainlocation => @MainLocation::text, " +
                "p_housingsystem => @HousingSystem::text, " +
                "p_defaultcurrency => @DefaultCurrency::text, " +
                "p_defaultcrateeggcount => @DefaultCrateEggCount::int, " +
                "p_totalcapacity => @TotalCapacity::int, " +
                "p_operatinghours => @OperatingHours::text, " +
                "p_ownername => @OwnerName::text, " +
                "p_phonenumber => @PhoneNumber::text, " +
                "p_email => @Email::text, " +
                "p_notes => @Notes::text)", c);

            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@BrandName",            (object?)req.BrandName            ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BusinessType",         (object?)req.BusinessType         ?? (object)PoultryBusinessTypes.Layers);
            cmd.Parameters.AddWithValue("@FarmSiteAddress",      (object?)req.FarmSiteAddress      ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MainLocation",         (object?)req.MainLocation         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@HousingSystem",        (object?)req.HousingSystem        ?? (object)PoultryHousingSystems.DeepLitter);
            cmd.Parameters.AddWithValue("@DefaultCurrency",      (object?)req.DefaultCurrency      ?? (object)"GHC");
            cmd.Parameters.AddWithValue("@DefaultCrateEggCount", (object?)req.DefaultCrateEggCount ?? (object)30);
            cmd.Parameters.AddWithValue("@TotalCapacity",        (object?)req.TotalCapacity        ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OperatingHours",       (object?)req.OperatingHours       ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OwnerName",            (object?)req.OwnerName            ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PhoneNumber",          (object?)req.PhoneNumber          ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email",                (object?)req.Email                ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",                (object?)req.Notes                ?? DBNull.Value);

            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            // Unlike spwatercompany_setup_rs1, this returns a single result set
            // (the profile), so there is no verification row to skip past.
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<PoultryCompanyProfileModel?> UpdateProfileAsync(string farmId, PoultryCompanyUpdateRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrycompany_updateprofile(" +
                "p_farmid => @FarmId::text, " +
                "p_brandname => @BrandName::text, " +
                "p_businesstype => @BusinessType::text, " +
                "p_farmsiteaddress => @FarmSiteAddress::text, " +
                "p_mainlocation => @MainLocation::text, " +
                "p_housingsystem => @HousingSystem::text, " +
                "p_defaultcurrency => @DefaultCurrency::text, " +
                "p_defaultcrateeggcount => @DefaultCrateEggCount::int, " +
                "p_totalcapacity => @TotalCapacity::int, " +
                "p_operatinghours => @OperatingHours::text, " +
                "p_ownername => @OwnerName::text, " +
                "p_phonenumber => @PhoneNumber::text, " +
                "p_email => @Email::text, " +
                "p_notes => @Notes::text)", c);

            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@BrandName",            (object?)req.BrandName            ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BusinessType",         (object?)req.BusinessType         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FarmSiteAddress",      (object?)req.FarmSiteAddress      ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MainLocation",         (object?)req.MainLocation         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@HousingSystem",        (object?)req.HousingSystem        ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultCurrency",      (object?)req.DefaultCurrency      ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultCrateEggCount", (object?)req.DefaultCrateEggCount ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TotalCapacity",        (object?)req.TotalCapacity        ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OperatingHours",       (object?)req.OperatingHours       ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OwnerName",            (object?)req.OwnerName            ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PhoneNumber",          (object?)req.PhoneNumber          ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email",                (object?)req.Email                ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",                (object?)req.Notes                ?? DBNull.Value);

            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        private static string? Str(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetString(i);
        }

        private static int? Int(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetInt32(i);
        }

        private static PoultryCompanyProfileModel Read(NpgsqlDataReader r) => new()
        {
            PoultryCompanyProfileId = r.GetInt32(r.GetOrdinal("PoultryCompanyProfileId")),
            FarmId                  = r.GetString(r.GetOrdinal("FarmId")),
            BrandName               = Str(r, "BrandName"),
            BusinessType            = r.GetString(r.GetOrdinal("BusinessType")),
            FarmSiteAddress         = Str(r, "FarmSiteAddress"),
            MainLocation            = Str(r, "MainLocation"),
            HousingSystem           = r.GetString(r.GetOrdinal("HousingSystem")),
            DefaultCurrency         = r.GetString(r.GetOrdinal("DefaultCurrency")),
            DefaultCrateEggCount    = r.GetInt32(r.GetOrdinal("DefaultCrateEggCount")),
            TotalCapacity           = Int(r, "TotalCapacity"),
            OperatingHours          = Str(r, "OperatingHours"),
            OwnerName               = Str(r, "OwnerName"),
            PhoneNumber             = Str(r, "PhoneNumber"),
            Email                   = Str(r, "Email"),
            Notes                   = Str(r, "Notes"),
            CreatedAt               = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt               = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }
}
