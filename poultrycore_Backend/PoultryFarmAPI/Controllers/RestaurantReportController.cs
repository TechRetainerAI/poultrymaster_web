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

        // =====================================================================
        // Migration 298 reports.
        //
        // Every endpoint keeps the ownership check the originals use: the farmId
        // arrives as a query parameter, so without VerifyFarmOwnership any
        // authenticated user could read any restaurant's takings simply by
        // editing the URL. There is no shortcut here and no unguarded endpoint.
        //
        // All of them are (farmId, from, to) except stock-on-hand, which is a
        // position rather than a period.
        // =====================================================================

        [HttpGet("sales-summary")]
        public async Task<IActionResult> SalesSummary([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetSalesSummaryAsync(farmId, from, to)); }

        [HttpGet("payment-methods")]
        public async Task<IActionResult> PaymentMethods([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetPaymentMethodsAsync(farmId, from, to)); }

        [HttpGet("pnl")]
        public async Task<IActionResult> Pnl([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetPnlSummaryAsync(farmId, from, to)); }

        [HttpGet("pnl-expenses")]
        public async Task<IActionResult> PnlExpenses([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetPnlExpensesAsync(farmId, from, to)); }

        [HttpGet("kitchen-performance")]
        public async Task<IActionResult> KitchenPerformance([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetKitchenPerformanceAsync(farmId, from, to)); }

        [HttpGet("table-turnover")]
        public async Task<IActionResult> TableTurnover([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetTableTurnoverAsync(farmId, from, to)); }

        [HttpGet("tips")]
        public async Task<IActionResult> Tips([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetTipsAsync(farmId, from, to)); }

        [HttpGet("delivery-performance")]
        public async Task<IActionResult> DeliveryPerformance([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetDeliveryPerformanceAsync(farmId, from, to)); }

        [HttpGet("discounts")]
        public async Task<IActionResult> Discounts([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetDiscountsAsync(farmId, from, to)); }

        [HttpGet("voids")]
        public async Task<IActionResult> Voids([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetVoidsAsync(farmId, from, to)); }

        [HttpGet("stock-on-hand")]
        public async Task<IActionResult> StockOnHand([FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetStockOnHandAsync(farmId)); }

        [HttpGet("waste-detail")]
        public async Task<IActionResult> WasteDetail([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetWasteDetailAsync(farmId, from, to)); }

        [HttpGet("expenses")]
        public async Task<IActionResult> Expenses([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetExpenseReportAsync(farmId, from, to)); }

        [HttpGet("menu-engineering")]
        public async Task<IActionResult> MenuEngineering([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetMenuEngineeringAsync(farmId, from, to)); }

        [HttpGet("customer-retention")]
        public async Task<IActionResult> CustomerRetention([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetCustomerRetentionAsync(farmId, from, to)); }

        [HttpGet("channel")]
        public async Task<IActionResult> Channel([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetChannelAsync(farmId, from, to)); }

        [HttpGet("events")]
        public async Task<IActionResult> EventsReport([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetEventsReportAsync(farmId, from, to)); }

        [HttpGet("feedback")]
        public async Task<IActionResult> FeedbackReport([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetFeedbackReportAsync(farmId, from, to)); }
    }
    public class KpiAlertReq { public string Name { get; set; } = ""; public string Metric { get; set; } = ""; public string Operator { get; set; } = ">"; public decimal Threshold { get; set; } public bool IsEnabled { get; set; } = true; }
}
