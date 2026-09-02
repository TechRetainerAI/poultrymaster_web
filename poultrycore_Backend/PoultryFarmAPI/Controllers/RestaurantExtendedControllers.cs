using Microsoft.AspNetCore.Authorization; using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business; using PoultryFarmAPIWeb.Helpers; using PoultryFarmAPIWeb.Models;
using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Loyalty Controller
    // =========================================================================
    [ApiController][Authorize][Route("api/Restaurant/loyalty")]
    public class RestaurantLoyaltyController : ControllerBase
    {
        private readonly IRestaurantLoyaltyService _svc;
        public RestaurantLoyaltyController(IRestaurantLoyaltyService svc) => _svc = svc;

        [HttpGet("settings")]
        public async Task<IActionResult> GetSettings([FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; var s=await _svc.GetSettingsAsync(farmId); return Ok(s ?? new LoyaltySettingsModel{FarmId=farmId}); }

        [HttpPost("settings")]
        public async Task<IActionResult> UpsertSettings([FromBody] LoyaltySettingsModel m)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,m.FarmId); if(a!=null) return a; await _svc.UpsertSettingsAsync(m); return NoContent(); }

        [HttpGet("accounts")]
        public async Task<IActionResult> ListAccounts([FromQuery] string farmId, [FromQuery] string? tier=null)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.ListAccountsAsync(farmId,tier)); }

        [HttpPost("accounts")]
        public async Task<IActionResult> CreateAccount([FromQuery] string farmId, [FromBody] LoyaltyAccountCreateReq req)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(new{loyaltyAccountId=await _svc.CreateAccountAsync(farmId,req.CustomerId,req.CustomerName,req.CustomerPhone)}); }

        [HttpPost("accounts/{id}/earn")]
        public async Task<IActionResult> Earn(int id, [FromQuery] string farmId, [FromBody] PointsReq req)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; await _svc.EarnPointsAsync(id,farmId,req.Points,req.Description,req.OrderId); return NoContent(); }

        [HttpPost("accounts/{id}/redeem")]
        public async Task<IActionResult> Redeem(int id, [FromQuery] string farmId, [FromBody] PointsReq req)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; var ok=await _svc.RedeemPointsAsync(id,farmId,req.Points,req.Description); return ok ? NoContent() : BadRequest(new{message="Insufficient points"}); }

        [HttpGet("accounts/{id}/transactions")]
        public async Task<IActionResult> Transactions(int id, [FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.GetTransactionsAsync(id,farmId)); }

        [HttpGet("stats")]
        public async Task<IActionResult> Stats([FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.GetStatsAsync(farmId)); }
    }
    public class LoyaltyAccountCreateReq { public int? CustomerId { get; set; } public string CustomerName { get; set; }=""; public string? CustomerPhone { get; set; } }
    public class PointsReq { public int Points { get; set; } public string Description { get; set; }=""; public int? OrderId { get; set; } }

    // =========================================================================
    // Notification Controller
    // =========================================================================
    [ApiController][Authorize][Route("api/Restaurant/notifications")]
    public class RestaurantNotificationController : ControllerBase
    {
        private readonly IRestaurantNotificationService _svc;
        public RestaurantNotificationController(IRestaurantNotificationService svc) => _svc = svc;

        [HttpGet]
        public async Task<IActionResult> List([FromQuery] string farmId, [FromQuery] bool unreadOnly=false)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.ListAsync(farmId,unreadOnly)); }

        [HttpPost("{id}/read")]
        public async Task<IActionResult> MarkRead(int id, [FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; await _svc.MarkReadAsync(id,farmId); return NoContent(); }

        [HttpPost("read-all")]
        public async Task<IActionResult> MarkAllRead([FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; await _svc.MarkAllReadAsync(farmId); return NoContent(); }

        [HttpGet("settings")]
        public async Task<IActionResult> GetSettings([FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; var s=await _svc.GetSettingsAsync(farmId); return Ok(s ?? new NotificationSettingsModel{FarmId=farmId}); }

        [HttpPost("settings")]
        public async Task<IActionResult> UpsertSettings([FromBody] NotificationSettingsModel m)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,m.FarmId); if(a!=null) return a; await _svc.UpsertSettingsAsync(m); return NoContent(); }
    }

    // =========================================================================
    // Event Controller
    // =========================================================================
    [ApiController][Authorize][Route("api/Restaurant/events")]
    public class RestaurantEventController : ControllerBase
    {
        private readonly IRestaurantEventService _svc;
        public RestaurantEventController(IRestaurantEventService svc) => _svc = svc;

        [HttpGet]
        public async Task<IActionResult> List([FromQuery] string farmId, [FromQuery] string? status=null)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.ListAsync(farmId,status)); }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] EventModel m)
        { if(!ModelState.IsValid) return BadRequest(ModelState); var a=HotelAuthHelper.VerifyFarmOwnership(User,m.FarmId); if(a!=null) return a; m.CreatedBy??=HotelAuthHelper.GetUserName(User); return Ok(new{eventId=await _svc.InsertAsync(m)}); }

        [HttpPatch("{id}/status")]
        public async Task<IActionResult> UpdateStatus(int id, [FromQuery] string farmId, [FromBody] EventStatusReq req)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; await _svc.UpdateStatusAsync(id,farmId,req.Status); return NoContent(); }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; await _svc.DeleteAsync(id,farmId); return NoContent(); }
    }
    public class EventStatusReq { public string Status { get; set; }=""; }

    // =========================================================================
    // Gift Card Controller
    // =========================================================================
    [ApiController][Authorize][Route("api/Restaurant/gift-cards")]
    public class RestaurantGiftCardController : ControllerBase
    {
        private readonly IRestaurantGiftCardService _svc;
        public RestaurantGiftCardController(IRestaurantGiftCardService svc) => _svc = svc;

        [HttpGet]
        public async Task<IActionResult> List([FromQuery] string farmId, [FromQuery] string? status=null)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.ListAsync(farmId,status)); }

        [HttpPost]
        public async Task<IActionResult> Create([FromQuery] string farmId, [FromBody] GiftCardCreateReq req)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; var(id,num)=await _svc.CreateAsync(farmId,req.CardType,req.Amount,req.PurchaserName,req.PurchaserPhone,req.RecipientName,req.RecipientEmail,req.Message,req.ExpiryDate); return Ok(new{giftCardId=id,cardNumber=num}); }

        [HttpPost("redeem")]
        public async Task<IActionResult> Redeem([FromQuery] string farmId, [FromBody] GiftCardRedeemReq req)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.RedeemAsync(req.CardNumber,farmId,req.Amount,req.OrderId,HotelAuthHelper.GetUserName(User))); }

        [HttpPost("reload")]
        public async Task<IActionResult> Reload([FromQuery] string farmId, [FromBody] GiftCardReloadReq req)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; await _svc.ReloadAsync(req.CardNumber,farmId,req.Amount,HotelAuthHelper.GetUserName(User)); return NoContent(); }

        [HttpGet("balance/{cardNumber}")]
        public async Task<IActionResult> Balance(string cardNumber)
        { var r=await _svc.CheckBalanceAsync(cardNumber); if(r==null) return NotFound(new{message="Card not found"}); return Ok(r); }

        [HttpGet("{id}/transactions")]
        public async Task<IActionResult> Transactions(int id, [FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.GetTransactionsAsync(id,farmId)); }

        [HttpGet("stats")]
        public async Task<IActionResult> Stats([FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.GetStatsAsync(farmId)); }
    }
    public class GiftCardCreateReq { public string CardType { get; set; }="Digital"; public decimal Amount { get; set; } public string? PurchaserName { get; set; } public string? PurchaserPhone { get; set; } public string? RecipientName { get; set; } public string? RecipientEmail { get; set; } public string? Message { get; set; } public DateTime? ExpiryDate { get; set; } }
    public class GiftCardRedeemReq { public string CardNumber { get; set; }=""; public decimal Amount { get; set; } public int? OrderId { get; set; } }
    public class GiftCardReloadReq { public string CardNumber { get; set; }=""; public decimal Amount { get; set; } }

    // =========================================================================
    // Expense Controller
    // =========================================================================
    [ApiController][Authorize][Route("api/Restaurant/expenses")]
    public class RestaurantExpenseController : ControllerBase
    {
        private readonly IRestaurantExpenseService _svc;
        public RestaurantExpenseController(IRestaurantExpenseService svc) => _svc = svc;

        [HttpGet("categories")]
        public async Task<IActionResult> ListCategories([FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.ListCategoriesAsync(farmId)); }

        [HttpPost("categories")]
        public async Task<IActionResult> CreateCategory([FromQuery] string farmId, [FromBody] ExpCatReq req)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(new{expenseCategoryId=await _svc.InsertCategoryAsync(farmId,req.Name)}); }

        [HttpDelete("categories/{id}")]
        public async Task<IActionResult> DeleteCategory(int id, [FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; await _svc.DeleteCategoryAsync(id,farmId); return NoContent(); }

        [HttpGet]
        public async Task<IActionResult> List([FromQuery] string farmId, [FromQuery] DateTime? from=null, [FromQuery] DateTime? to=null)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.ListExpensesAsync(farmId,from,to)); }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] RestaurantExpenseModel m)
        { if(!ModelState.IsValid) return BadRequest(ModelState); var a=HotelAuthHelper.VerifyFarmOwnership(User,m.FarmId); if(a!=null) return a; m.CreatedBy??=HotelAuthHelper.GetUserName(User); return Ok(new{expenseId=await _svc.InsertExpenseAsync(m)}); }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; await _svc.DeleteExpenseAsync(id,farmId); return NoContent(); }

        [HttpGet("receipt-template")]
        public async Task<IActionResult> GetReceipt([FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; var r=await _svc.GetReceiptTemplateAsync(farmId); return Ok(r ?? new ReceiptTemplateModel{FarmId=farmId}); }

        [HttpPost("receipt-template")]
        public async Task<IActionResult> UpsertReceipt([FromBody] ReceiptTemplateModel m)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,m.FarmId); if(a!=null) return a; await _svc.UpsertReceiptTemplateAsync(m); return NoContent(); }
    }
    public class ExpCatReq { [Required] public string Name { get; set; }=""; }

    // =========================================================================
    // Restaurant Staff Controller
    // =========================================================================
    [ApiController][Authorize][Route("api/Restaurant/staff")]
    public class RestaurantStaffController : ControllerBase
    {
        private readonly IRestaurantStaffService _svc;
        public RestaurantStaffController(IRestaurantStaffService svc) => _svc = svc;

        [HttpGet]
        public async Task<IActionResult> List([FromQuery] string farmId, [FromQuery] string? role = null)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; return Ok(await _svc.ListAsync(farmId,role)); }

        [HttpGet("{id:int}")]
        public async Task<IActionResult> GetById(int id, [FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; var m=await _svc.GetByIdAsync(id,farmId); return m is null ? NotFound() : Ok(m); }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] RestaurantStaffModel m)
        { if(!ModelState.IsValid) return BadRequest(ModelState); var a=HotelAuthHelper.VerifyFarmOwnership(User,m.FarmId); if(a!=null) return a; return Ok(new{staffId=await _svc.InsertAsync(m)}); }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromQuery] string farmId, [FromBody] RestaurantStaffModel m)
        { if(!ModelState.IsValid) return BadRequest(ModelState); var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; m.RestaurantStaffId=id; m.FarmId=farmId; await _svc.UpdateAsync(m); return NoContent(); }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        { var a=HotelAuthHelper.VerifyFarmOwnership(User,farmId); if(a!=null) return a; await _svc.DeleteAsync(id,farmId); return NoContent(); }
    }
}
