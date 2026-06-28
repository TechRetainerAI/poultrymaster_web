using System;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Advanced Poultry Reports — 20 brand-new poultry-only reports.
    //
    // Route is deliberately poultry-specific: every endpoint lives under
    // /api/poultry/reports/* and is gated to Poultry farms only (Water and
    // Generic companies get a 409). This controller is additive — it does not
    // touch GenericReportsController, the water report endpoints, or any
    // existing poultry endpoints.
    //
    // FarmId is supplied as a query parameter (consistent with the other
    // poultry controllers such as Flock / EggProduction).
    // =========================================================================
    [ApiController]
    [Route("api/poultry/reports")]
    public class PoultryAdvancedReportsController : ControllerBase
    {
        private readonly IPoultryAdvancedReportService _reports;
        private readonly IGenericCompanyService _companies;

        public PoultryAdvancedReportsController(
            IPoultryAdvancedReportService reports,
            IGenericCompanyService companies)
        {
            _reports = reports;
            _companies = companies;
        }

        /// <summary>
        /// Ensures a farmId was supplied and the farm is a Poultry farm. Legacy
        /// poultry farms may have a NULL/blank Type, so we allow NULL/blank or
        /// "Poultry"; Water and Generic companies are rejected so these reports
        /// only ever appear in a poultry context.
        /// </summary>
        private async Task<ActionResult?> EnsurePoultryAsync(string? farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId))
                return BadRequest("farmId is required.");

            var farmType = await _companies.GetFarmTypeAsync(farmId);
            if (farmType is not null
                && !string.Equals(farmType, "Poultry", StringComparison.OrdinalIgnoreCase))
            {
                return Conflict($"Advanced poultry reports are only available for Poultry farms (current type: {farmType}).");
            }
            return null;
        }

        // 1
        [HttpGet("farm-summary")]
        public async Task<IActionResult> FarmSummary([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetFarmSummaryAsync(filter));
        }

        // 2
        [HttpGet("daily-egg-production")]
        public async Task<IActionResult> DailyEggProduction([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetDailyEggProductionAsync(filter));
        }

        // 3
        [HttpGet("flock-production-summary")]
        public async Task<IActionResult> FlockProductionSummary([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetFlockProductionSummaryAsync(filter));
        }

        // 4
        [HttpGet("hen-day-production")]
        public async Task<IActionResult> HenDayProduction([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetHenDayProductionAsync(filter));
        }

        // 5
        [HttpGet("mortality")]
        public async Task<IActionResult> Mortality([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetMortalityAsync(filter));
        }

        // 6
        [HttpGet("birds-on-hand")]
        public async Task<IActionResult> BirdsOnHand([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetBirdsOnHandAsync(filter));
        }

        // 7
        [HttpGet("feed-usage")]
        public async Task<IActionResult> FeedUsage([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetFeedUsageAsync(filter));
        }

        // 8
        [HttpGet("feed-inventory-balance")]
        public async Task<IActionResult> FeedInventoryBalance([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetFeedInventoryBalanceAsync(filter));
        }

        // 9
        [HttpGet("feed-cost-per-egg")]
        public async Task<IActionResult> FeedCostPerEgg([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetFeedCostPerEggAsync(filter));
        }

        // 10
        [HttpGet("egg-stock-balance")]
        public async Task<IActionResult> EggStockBalance([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetEggStockBalanceAsync(filter));
        }

        // 11
        [HttpGet("egg-sales")]
        public async Task<IActionResult> EggSales([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetEggSalesAsync(filter));
        }

        // 12
        [HttpGet("customer-balance")]
        public async Task<IActionResult> CustomerBalance([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetCustomerBalanceAsync(filter));
        }

        // 13
        [HttpGet("expense-summary")]
        public async Task<IActionResult> ExpenseSummary([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetExpenseSummaryAsync(filter));
        }

        // 14
        [HttpGet("cash-movement")]
        public async Task<IActionResult> CashMovement([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetCashMovementAsync(filter));
        }

        // 15
        [HttpGet("profit-loss-by-flock")]
        public async Task<IActionResult> ProfitLossByFlock([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetProfitLossByFlockAsync(filter));
        }

        // 16
        [HttpGet("cost-per-egg")]
        public async Task<IActionResult> CostPerEgg([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetCostPerEggAsync(filter));
        }

        // 17
        [HttpGet("vaccination-schedule")]
        public async Task<IActionResult> VaccinationSchedule([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetVaccinationScheduleAsync(filter));
        }

        // 18
        [HttpGet("medicine-usage")]
        public async Task<IActionResult> MedicineUsage([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetMedicineUsageAsync(filter));
        }

        // 19
        [HttpGet("missing-daily-records")]
        public async Task<IActionResult> MissingDailyRecords([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetMissingDailyRecordsAsync(filter));
        }

        // 20
        [HttpGet("end-of-flock")]
        public async Task<IActionResult> EndOfFlock([FromQuery] PoultryReportFilterDto filter)
        {
            var guard = await EnsurePoultryAsync(filter.FarmId);
            if (guard is not null) return guard;
            return Ok(await _reports.GetEndOfFlockAsync(filter));
        }
    }
}
