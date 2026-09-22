// Cash Flow — one controller per rail. The route segment picks the rail; the
// service validates it against a fixed list before it reaches any SQL.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Poultry/cash-flow")]
    public class PoultryCashFlowController : ControllerBase
    {
        private readonly ICashFlowService _svc;
        public PoultryCashFlowController(ICashFlowService svc) => _svc = svc;

        [HttpGet]
        public Task<ActionResult<CashFlowResponse>> Get(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => CashFlowEndpoint.Handle(this, _svc, "poultry", farmId, fromDate, toDate);
    }

    [ApiController]
    [Route("api/Water/cash-flow")]
    public class WaterCashFlowController : ControllerBase
    {
        private readonly ICashFlowService _svc;
        public WaterCashFlowController(ICashFlowService svc) => _svc = svc;

        [HttpGet]
        public Task<ActionResult<CashFlowResponse>> Get(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => CashFlowEndpoint.Handle(this, _svc, "water", farmId, fromDate, toDate);
    }

    [ApiController]
    [Route("api/Hotel/cash-flow")]
    public class HotelCashFlowController : ControllerBase
    {
        private readonly ICashFlowService _svc;
        public HotelCashFlowController(ICashFlowService svc) => _svc = svc;

        [HttpGet]
        public Task<ActionResult<CashFlowResponse>> Get(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => CashFlowEndpoint.Handle(this, _svc, "hotel", farmId, fromDate, toDate);
    }

    [ApiController]
    [Route("api/Restaurant/cash-flow")]
    public class RestaurantCashFlowController : ControllerBase
    {
        private readonly ICashFlowService _svc;
        public RestaurantCashFlowController(ICashFlowService svc) => _svc = svc;

        [HttpGet]
        public Task<ActionResult<CashFlowResponse>> Get(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => CashFlowEndpoint.Handle(this, _svc, "restaurant", farmId, fromDate, toDate);
    }

    internal static class CashFlowEndpoint
    {
        public static async Task<ActionResult<CashFlowResponse>> Handle(
            ControllerBase c, ICashFlowService svc, string rail,
            string farmId, DateTime? fromDate, DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return c.BadRequest("Company ID is required.");

            // The end date is inclusive of the whole day. A bare date binds to
            // midnight, which silently drops everything recorded on the last day
            // of the range -- the bug migration 232's header calls out.
            var to = toDate?.TimeOfDay == TimeSpan.Zero
                ? toDate.Value.Date.AddDays(1).AddTicks(-1)
                : toDate;

            return c.Ok(await svc.GetAsync(rail, farmId, fromDate?.Date, to));
        }
    }
}
