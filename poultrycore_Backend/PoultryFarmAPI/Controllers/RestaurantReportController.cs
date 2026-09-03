using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController][Authorize][Route("api/Restaurant/reports")]
    public class RestaurantReportController : ControllerBase
    {
        private readonly IRestaurantReportService _svc;
        public RestaurantReportController(IRestaurantReportService svc) => _svc = svc;

        [HttpGet("daily-sales")]
        public async Task<IActionResult> DailySales([FromQuery] string farmId, [FromQuery] DateTime date)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetDailySalesAsync(farmId, date)); }

        [HttpGet("sales-by-item")]
        public async Task<IActionResult> SalesByItem([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetSalesByItemAsync(farmId, from, to)); }

        [HttpGet("sales-by-category")]
        public async Task<IActionResult> SalesByCategory([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetSalesByCategoryAsync(farmId, from, to)); }

        [HttpGet("sales-by-hour")]
        public async Task<IActionResult> SalesByHour([FromQuery] string farmId, [FromQuery] DateTime date)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetSalesByHourAsync(farmId, date)); }

        [HttpGet("revenue-trend")]
        public async Task<IActionResult> RevenueTrend([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetRevenueTrendAsync(farmId, from, to)); }

        [HttpGet("food-cost")]
        public async Task<IActionResult> FoodCost([FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetFoodCostReportAsync(farmId)); }

        [HttpGet("server-performance")]
        public async Task<IActionResult> ServerPerformance([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetServerPerformanceAsync(farmId, from, to)); }

        [HttpGet("kpi-alerts")]
        public async Task<IActionResult> ListAlerts([FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.ListKpiAlertsAsync(farmId)); }

        [HttpPost("kpi-alerts")]
        public async Task<IActionResult> CreateAlert([FromQuery] string farmId, [FromBody] KpiAlertReq req)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(new { kpiAlertId = await _svc.InsertKpiAlertAsync(farmId, req.Name, req.Metric, req.Operator, req.Threshold, req.IsEnabled) }); }

        [HttpDelete("kpi-alerts/{id}")]
        public async Task<IActionResult> DeleteAlert(int id, [FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; await _svc.DeleteKpiAlertAsync(id, farmId); return NoContent(); }
    }
    public class KpiAlertReq { public string Name { get; set; } = ""; public string Metric { get; set; } = ""; public string Operator { get; set; } = ">"; public decimal Threshold { get; set; } public bool IsEnabled { get; set; } = true; }
}
