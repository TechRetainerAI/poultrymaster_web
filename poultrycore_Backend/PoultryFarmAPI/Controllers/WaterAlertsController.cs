// Water Alerts (migration 465): what needs attention, derived on every read and
// never stored. GET api/Water/alerts?farmId=   -> water.reports

using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Filters;

namespace PoultryFarmAPIWeb.Business
{
    public class WaterAlertModel
    {
        public string Section { get; set; } = string.Empty;
        public string Code { get; set; } = string.Empty;
        public string Severity { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public string? Detail { get; set; }
        public int ItemCount { get; set; }
        public decimal? Amount { get; set; }
        public string Href { get; set; } = string.Empty;
        public int SortOrder { get; set; }
    }

    public interface IWaterAlertsService
    {
        Task<List<WaterAlertModel>> GetAsync(string farmId);
    }

    public class WaterAlertsService : IWaterAlertsService
    {
        private readonly string _cs;
        public WaterAlertsService(string connectionString) => _cs = connectionString;

        public async Task<List<WaterAlertModel>> GetAsync(string farmId)
        {
            var list = new List<WaterAlertModel>();
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand("SELECT * FROM spwateralerts_get(p_farmid => @FarmId::text) ORDER BY sortorder", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterAlertModel
                {
                    Section   = r.GetString(r.GetOrdinal("section")),
                    Code      = r.GetString(r.GetOrdinal("code")),
                    Severity  = r.GetString(r.GetOrdinal("severity")),
                    Title     = r.GetString(r.GetOrdinal("title")),
                    Detail    = r.IsDBNull(r.GetOrdinal("detail")) ? null : r.GetString(r.GetOrdinal("detail")),
                    ItemCount = r.GetInt32(r.GetOrdinal("itemcount")),
                    Amount    = r.IsDBNull(r.GetOrdinal("amount")) ? null : r.GetDecimal(r.GetOrdinal("amount")),
                    Href      = r.GetString(r.GetOrdinal("href")),
                    SortOrder = r.GetInt32(r.GetOrdinal("sortorder")),
                });
            }
            return list;
        }
    }
}

namespace PoultryFarmAPIWeb.Controllers
{
    using PoultryFarmAPIWeb.Business;

    [ApiController]
    [Route("api/Water/alerts")]
    [RequireCompanyType("Water")]
    public class WaterAlertsController : ControllerBase
    {
        private readonly IWaterAlertsService _svc;
        public WaterAlertsController(IWaterAlertsService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterAlertModel>>> Get([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest(new { message = "Company ID is required." })
                : Ok(await _svc.GetAsync(farmId));
    }
}
