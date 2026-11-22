// Water Closing by Category (migration 463): one period totalled into financial,
// production, inventory, losses, cash & delivery and staff. Read-only; every
// figure comes from the function that owns it (P&L, Cash Flow, payables ...).
//
// GET api/Water/closing-report?farmId=&fromDate=&toDate=   -> water.reports

using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Filters;

namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterClosingReportService
    {
        Task<string> GetAsync(string farmId, DateTime from, DateTime to);
    }

    /// <summary>Thin wrapper over spwaterclosingreport_get (jsonb).</summary>
    public class WaterClosingReportService : IWaterClosingReportService
    {
        private readonly string _cs;
        public WaterClosingReportService(string connectionString) => _cs = connectionString;

        public async Task<string> GetAsync(string farmId, DateTime from, DateTime to)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(
                "SELECT spwaterclosingreport_get(p_farmid => @FarmId::text, p_fromdate => @From::date, p_todate => @To::date)::text", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@From", NpgsqlTypes.NpgsqlDbType.Date, from);
            cmd.Parameters.AddWithValue("@To", NpgsqlTypes.NpgsqlDbType.Date, to);
            return (string?)await cmd.ExecuteScalarAsync() ?? "{}";
        }
    }
}

namespace PoultryFarmAPIWeb.Controllers
{
    using PoultryFarmAPIWeb.Business;

    [ApiController]
    [Route("api/Water/closing-report")]
    [RequireCompanyType("Water")]
    public class WaterClosingByCategoryController : ControllerBase
    {
        private readonly IWaterClosingReportService _svc;
        public WaterClosingByCategoryController(IWaterClosingReportService svc) => _svc = svc;

        [HttpGet]
        public async Task<IActionResult> Get([FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            var today = DateTime.Today;
            var from = (fromDate ?? new DateTime(today.Year, today.Month, 1)).Date;
            var to = (toDate ?? today).Date;
            return Content(await _svc.GetAsync(farmId, from, to), "application/json");
        }
    }
}
