using System.Data;
using System.Data.SqlClient;
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
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCompany_GetProfile", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<WaterCompanyProfileModel?> SetupAsync(WaterCompanySetupRequest req)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCompany_Setup", c) { CommandType = CommandType.StoredProcedure };
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
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<WaterCompanyProfileModel?> UpdateProfileAsync(string farmId, WaterCompanyUpdateRequest req)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCompany_UpdateProfile", c) { CommandType = CommandType.StoredProcedure };
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

        private static WaterCompanyProfileModel Read(SqlDataReader r) => new()
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
