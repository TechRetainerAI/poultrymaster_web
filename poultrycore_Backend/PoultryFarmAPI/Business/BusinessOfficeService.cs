using System.Data;
using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IBusinessOfficeService
    {
        Task<CompanySnapshotModel> GetCompanySnapshotAsync(string farmId, string companyType, DateTime? today);
    }

    /// <summary>
    /// Today's numbers for the Business Office company cards. One company per
    /// call — the page fans out across its cards, so this stays a single cheap
    /// round trip rather than a batch endpoint that would couple the cards'
    /// loading states together.
    /// </summary>
    public class BusinessOfficeService : IBusinessOfficeService
    {
        private readonly string _connectionString;

        public BusinessOfficeService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<CompanySnapshotModel> GetCompanySnapshotAsync(string farmId, string companyType, DateTime? today)
        {
            var model = new CompanySnapshotModel { FarmId = farmId, CompanyType = companyType };

            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spbusinessoffice_companysnapshot(p_farmid => @FarmId::text, p_companytype => @CompanyType::text, p_today => @Today::date)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@CompanyType", companyType);
            // Null hands the SP the server's UTC date; the client normally sends
            // its own local one so "today" matches the person reading the card.
            cmd.Parameters.Add("@Today", NpgsqlDbType.Date).Value = today.HasValue ? today.Value.Date : DBNull.Value;

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync()) return model;

            model.Metric1 = Read(reader, "Metric1");
            model.Metric2 = Read(reader, "Metric2");
            model.Metric3 = Read(reader, "Metric3");
            model.Metric4 = Read(reader, "Metric4");
            return model;
        }

        // NULL survives as null all the way to the card, where it renders as a
        // dash. Collapsing it to 0 here would claim a measurement we never took.
        private static decimal? Read(NpgsqlDataReader reader, string column)
        {
            var ordinal = reader.GetOrdinal(column);
            return reader.IsDBNull(ordinal) ? null : reader.GetDecimal(ordinal);
        }
    }
}
