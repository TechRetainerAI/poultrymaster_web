using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterCompanyService
    {
        Task<WaterCompanyProfileModel?> GetProfileAsync(string farmId);
        Task<WaterCompanyProfileModel?> SetupAsync(WaterCompanySetupRequest req);
        Task<WaterCompanyProfileModel?> UpdateProfileAsync(string farmId, WaterCompanyUpdateRequest req);
    }

    public class WaterCompanyService : IWaterCompanyService
    {
        private readonly string _cs;
        public WaterCompanyService(string cs) => _cs = cs;

        public async Task<WaterCompanyProfileModel?> GetProfileAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercompany_getprofile(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<WaterCompanyProfileModel?> SetupAsync(WaterCompanySetupRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercompany_setup_rs1(p_farmid => @FarmId::text, p_brandname => @BrandName::text, p_businesstype => @BusinessType::text, p_productionsiteaddress => @ProductionSiteAddress::text, p_mainlocation => @MainLocation::text, p_watersourcetype => @WaterSourceType::text, p_defaultcurrency => @DefaultCurrency::text, p_defaultbagsachetcount => @DefaultBagSachetCount::int, p_ownername => @OwnerName::text, p_phonenumber => @PhoneNumber::text, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@BrandName",             (object?)req.BrandName             ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BusinessType",          (object?)req.BusinessType          ?? (object)"Sachet");
            cmd.Parameters.AddWithValue("@ProductionSiteAddress", (object?)req.ProductionSiteAddress ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MainLocation",          (object?)req.MainLocation          ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterSourceType",       (object?)req.WaterSourceType       ?? (object)"Borehole");
            cmd.Parameters.AddWithValue("@DefaultCurrency",       (object?)req.DefaultCurrency       ?? (object)"GHC");
            cmd.Parameters.AddWithValue("@DefaultBagSachetCount", (object?)req.DefaultBagSachetCount ?? (object)30);
            cmd.Parameters.AddWithValue("@OwnerName",             (object?)req.OwnerName             ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PhoneNumber",           (object?)req.PhoneNumber           ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",                 (object?)req.Notes                 ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            // spWaterCompany_Setup emits TWO result sets:
            //   1) the verification readout from EXEC spWaterFinance_SeedDefaults
            //      (ExpenseCategoryCount, CashAccountCount)
            //   2) the profile row (WaterCompanyProfileId, FarmId, BrandName, ...)
            // Reading the first one and calling Read() raises
            // IndexOutOfRangeException("WaterCompanyProfileId") because that
            // column isn't on the verification row. Skip past it explicitly.
            // James (2026-05-30): "save failed: Error: WaterCompanyProfileId".
            await SkipToProfileResultSetAsync(r);
            return await r.ReadAsync() ? Read(r) : null;
        }

        // Advances the reader past intermediate result sets (verification
        // counts) until it finds one with a WaterCompanyProfileId column, or
        // exhausts. Safe no-op when the SP only returns one result set.
        private static async Task SkipToProfileResultSetAsync(NpgsqlDataReader r)
        {
            while (true)
            {
                var hasProfileColumn = false;
                for (int i = 0; i < r.FieldCount; i++)
                {
                    if (string.Equals(r.GetName(i), "WaterCompanyProfileId", StringComparison.OrdinalIgnoreCase))
                    {
                        hasProfileColumn = true;
                        break;
                    }
                }
                if (hasProfileColumn) return;
                if (!await r.NextResultAsync()) return;
            }
        }

        public async Task<WaterCompanyProfileModel?> UpdateProfileAsync(string farmId, WaterCompanyUpdateRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercompany_updateprofile(p_farmid => @FarmId::text, p_brandname => @BrandName::text, p_businesstype => @BusinessType::text, p_productionsiteaddress => @ProductionSiteAddress::text, p_mainlocation => @MainLocation::text, p_watersourcetype => @WaterSourceType::text, p_defaultcurrency => @DefaultCurrency::text, p_defaultbagsachetcount => @DefaultBagSachetCount::int, p_ownername => @OwnerName::text, p_phonenumber => @PhoneNumber::text, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@BrandName",             (object?)req.BrandName             ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BusinessType",          (object?)req.BusinessType          ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ProductionSiteAddress", (object?)req.ProductionSiteAddress ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MainLocation",          (object?)req.MainLocation          ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterSourceType",       (object?)req.WaterSourceType       ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultCurrency",       (object?)req.DefaultCurrency       ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultBagSachetCount", (object?)req.DefaultBagSachetCount ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OwnerName",             (object?)req.OwnerName             ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PhoneNumber",           (object?)req.PhoneNumber           ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",                 (object?)req.Notes                 ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        private static WaterCompanyProfileModel Read(NpgsqlDataReader r) => new()
        {
            WaterCompanyProfileId = r.GetInt32(r.GetOrdinal("WaterCompanyProfileId")),
            FarmId                = r.GetString(r.GetOrdinal("FarmId")),
            BrandName             = r.IsDBNull(r.GetOrdinal("BrandName")) ? null : r.GetString(r.GetOrdinal("BrandName")),
            BusinessType          = r.GetString(r.GetOrdinal("BusinessType")),
            ProductionSiteAddress = r.IsDBNull(r.GetOrdinal("ProductionSiteAddress")) ? null : r.GetString(r.GetOrdinal("ProductionSiteAddress")),
            MainLocation          = r.IsDBNull(r.GetOrdinal("MainLocation")) ? null : r.GetString(r.GetOrdinal("MainLocation")),
            WaterSourceType       = r.GetString(r.GetOrdinal("WaterSourceType")),
            DefaultCurrency       = r.GetString(r.GetOrdinal("DefaultCurrency")),
            DefaultBagSachetCount = r.GetInt32(r.GetOrdinal("DefaultBagSachetCount")),
            OwnerName             = r.IsDBNull(r.GetOrdinal("OwnerName")) ? null : r.GetString(r.GetOrdinal("OwnerName")),
            PhoneNumber           = r.IsDBNull(r.GetOrdinal("PhoneNumber")) ? null : r.GetString(r.GetOrdinal("PhoneNumber")),
            Notes                 = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt             = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt             = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }
}
