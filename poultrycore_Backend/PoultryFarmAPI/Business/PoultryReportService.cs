using System.Data;
using Npgsql;

namespace PoultryFarmAPIWeb.Business
{
    // Doc 6: poultry closing report. Returns the single aggregated row as a
    // dictionary (column -> value) so the frontend gets all fields without a
    // 35-property DTO. Additive.
    public interface IPoultryReportService
    {
        Task<Dictionary<string, object?>> GetClosingReportAsync(string farmId, DateTime fromDate, DateTime toDate);
    }

    public class PoultryReportService : IPoultryReportService
    {
        private readonly string _cs;
        public PoultryReportService(string cs) => _cs = cs;

        public async Task<Dictionary<string, object?>> GetClosingReportAsync(string farmId, DateTime fromDate, DateTime toDate)
        {
            var result = new Dictionary<string, object?>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryclosingreport_get(p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", fromDate.Date);
            cmd.Parameters.AddWithValue("@ToDate", toDate.Date);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync())
                for (int i = 0; i < r.FieldCount; i++)
                    result[r.GetName(i)] = r.IsDBNull(i) ? null : r.GetValue(i);
            return result;
        }
    }
}
