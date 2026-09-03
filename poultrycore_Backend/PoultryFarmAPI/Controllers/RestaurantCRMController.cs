using Microsoft.AspNetCore.Authorization; using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business; using PoultryFarmAPIWeb.Helpers; using PoultryFarmAPIWeb.Models;
namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController][Authorize][Route("api/Restaurant/crm")]
    public class RestaurantCRMController : ControllerBase
    {
        private readonly IRestaurantCRMService _svc;
        public RestaurantCRMController(IRestaurantCRMService svc) => _svc = svc;

        [HttpGet("customers")]
        public async Task<IActionResult> ListCustomers([FromQuery] string farmId, [FromQuery] string? segment=null, [FromQuery] string? search=null)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.ListCustomersAsync(farmId,segment,search)); }

        [HttpPost("customers")]
        public async Task<IActionResult> CreateCustomer([FromBody] RestaurantCustomerModel m)
        { if(!ModelState.IsValid) return BadRequest(ModelState); var a=HotelAuthHelper.VerifyFarmOwnership(User,m.FarmId); if(a!=null) return a; return Ok(new{customerId=await _svc.InsertCustomerAsync(m)}); }

        [HttpPut("customers/{id}")]
        public async Task<IActionResult> UpdateCustomer(int id,[FromBody] RestaurantCustomerModel m)
        { if(!ModelState.IsValid) return BadRequest(ModelState); var a=HotelAuthHelper.VerifyFarmOwnership(User,m.FarmId); if(a!=null) return a; m.CustomerId=id; await _svc.UpdateCustomerAsync(m); return NoContent(); }

        [HttpDelete("customers/{id}")]
        public async Task<IActionResult> DeleteCustomer(int id,[FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; await _svc.DeleteCustomerAsync(id,farmId); return NoContent(); }

        [HttpPost("customers/{id}/visit")]
        public async Task<IActionResult> RecordVisit(int id,[FromQuery] string farmId,[FromBody] VisitReq req)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; await _svc.RecordVisitAsync(id,farmId,req.OrderAmount); return NoContent(); }

        [HttpGet("customers/stats")]
        public async Task<IActionResult> CustomerStats([FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.GetCustomerStatsAsync(farmId)); }

        [HttpGet("feedback")]
        public async Task<IActionResult> ListFeedback([FromQuery] string farmId,[FromQuery] string? status=null)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.ListFeedbackAsync(farmId,status)); }

        [HttpPost("feedback")]
        public async Task<IActionResult> CreateFeedback([FromBody] RestaurantFeedbackModel m)
        { if(!ModelState.IsValid) return BadRequest(ModelState); var a=HotelAuthHelper.VerifyFarmOwnership(User,m.FarmId); if(a!=null) return a; return Ok(new{feedbackId=await _svc.InsertFeedbackAsync(m)}); }

        [HttpPost("feedback/{id}/respond")]
        public async Task<IActionResult> Respond(int id,[FromQuery] string farmId,[FromBody] FeedbackRespondReq req)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; await _svc.RespondToFeedbackAsync(id,farmId,req.Response,HotelAuthHelper.GetUserName(User)); return NoContent(); }

        [HttpGet("feedback/stats")]
        public async Task<IActionResult> FeedbackStats([FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.GetFeedbackStatsAsync(farmId)); }

        [HttpGet("campaigns")]
        public async Task<IActionResult> ListCampaigns([FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.ListCampaignsAsync(farmId)); }

        [HttpPost("campaigns")]
        public async Task<IActionResult> CreateCampaign([FromBody] RestaurantCampaignModel m)
        { if(!ModelState.IsValid) return BadRequest(ModelState); var a=HotelAuthHelper.VerifyFarmOwnership(User,m.FarmId); if(a!=null) return a; return Ok(new{campaignId=await _svc.InsertCampaignAsync(m)}); }

        [HttpDelete("campaigns/{id}")]
        public async Task<IActionResult> DeleteCampaign(int id,[FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; await _svc.DeleteCampaignAsync(id,farmId); return NoContent(); }
    }
    public class VisitReq { public decimal OrderAmount { get; set; } }
    public class FeedbackRespondReq { public string Response { get; set; } = ""; }
}
