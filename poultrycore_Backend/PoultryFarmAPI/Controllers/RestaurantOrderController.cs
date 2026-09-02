using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [Route("api/Restaurant/orders")]
    public class RestaurantOrderController : ControllerBase
    {
        private readonly IRestaurantOrderService _svc;
        public RestaurantOrderController(IRestaurantOrderService svc) => _svc = svc;

        // ===== ORDERS =====

        [HttpGet]
        public async Task<IActionResult> ListOrders([FromQuery] string farmId, [FromQuery] string? status = null,
            [FromQuery] string? orderType = null, [FromQuery] DateTime? fromDate = null, [FromQuery] DateTime? toDate = null)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListOrdersAsync(farmId, status, orderType, fromDate, toDate));
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> GetOrder(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var o = await _svc.GetOrderAsync(id, farmId);
            if (o == null) return NotFound();
            return Ok(o);
        }

        [HttpPost]
        public async Task<IActionResult> CreateOrder([FromBody] RestaurantOrderCreateRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            req.CreatedBy ??= HotelAuthHelper.GetUserName(User);
            var (orderId, orderNumber) = await _svc.CreateOrderAsync(req);
            return Ok(new { orderId, orderNumber });
        }

        [HttpPatch("{id}/status")]
        public async Task<IActionResult> UpdateStatus(int id, [FromQuery] string farmId, [FromBody] OrderStatusUpdateRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.UpdateOrderStatusAsync(id, farmId, req.Status, req.Reason);
            return NoContent();
        }

        [HttpPost("{id}/recalc")]
        public async Task<IActionResult> Recalc(int id, [FromQuery] string farmId, [FromBody] OrderRecalcRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.RecalcOrderAsync(id, farmId, req.TaxRate, req.ServiceChargeRate);
            return NoContent();
        }

        // ===== ORDER ITEMS =====

        [HttpGet("{orderId}/items")]
        public async Task<IActionResult> ListItems(int orderId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListOrderItemsAsync(orderId, farmId));
        }

        [HttpPost("{orderId}/items")]
        public async Task<IActionResult> AddItem(int orderId, [FromBody] RestaurantOrderItemCreateRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            req.OrderId = orderId;
            var id = await _svc.AddOrderItemAsync(req);
            return Ok(new { orderItemId = id });
        }

        [HttpPatch("items/{id}/status")]
        public async Task<IActionResult> UpdateItemStatus(int id, [FromQuery] string farmId, [FromBody] OrderItemStatusRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.UpdateOrderItemStatusAsync(id, farmId, req.Status);
            return NoContent();
        }

        [HttpPost("items/{id}/cancel")]
        public async Task<IActionResult> CancelItem(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.CancelOrderItemAsync(id, farmId);
            return NoContent();
        }

        // ===== ORDER ITEM MODIFIERS =====

        [HttpGet("items/{orderItemId}/modifiers")]
        public async Task<IActionResult> ListItemModifiers(int orderItemId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListOrderItemModifiersAsync(orderItemId, farmId));
        }

        // ===== PAYMENTS =====

        [HttpGet("{orderId}/payments")]
        public async Task<IActionResult> ListPayments(int orderId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListPaymentsAsync(orderId, farmId));
        }

        [HttpPost("{orderId}/payments")]
        public async Task<IActionResult> AddPayment(int orderId, [FromQuery] string farmId, [FromBody] OrderPaymentRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var processedBy = HotelAuthHelper.GetUserName(User);
            var id = await _svc.AddPaymentAsync(farmId, orderId, req.PaymentMethod, req.Amount, req.TipAmount, req.Reference, processedBy);
            return Ok(new { orderPaymentId = id });
        }

        // ===== DISCOUNTS =====

        [HttpGet("discounts")]
        public async Task<IActionResult> ListDiscounts([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListDiscountsAsync(farmId));
        }

        [HttpPost("discounts")]
        public async Task<IActionResult> CreateDiscount([FromBody] RestaurantDiscountModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertDiscountAsync(m);
            return Ok(new { discountId = id });
        }

        [HttpPut("discounts/{id}")]
        public async Task<IActionResult> UpdateDiscount(int id, [FromBody] RestaurantDiscountModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.DiscountId = id;
            await _svc.UpdateDiscountAsync(m);
            return NoContent();
        }

        [HttpDelete("discounts/{id}")]
        public async Task<IActionResult> DeleteDiscount(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteDiscountAsync(id, farmId);
            return NoContent();
        }

        // ===== ORDER DISCOUNTS =====

        [HttpGet("{orderId}/discounts")]
        public async Task<IActionResult> ListOrderDiscounts(int orderId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListOrderDiscountsAsync(orderId, farmId));
        }

        [HttpPost("{orderId}/discounts")]
        public async Task<IActionResult> ApplyDiscount(int orderId, [FromQuery] string farmId, [FromBody] ApplyDiscountRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var id = await _svc.ApplyDiscountToOrderAsync(farmId, orderId, req.DiscountId, req.DiscountName, req.DiscountType, req.Value, req.AppliedAmount);
            return Ok(new { orderDiscountId = id });
        }

        [HttpDelete("discounts/applied/{id}")]
        public async Task<IActionResult> RemoveOrderDiscount(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.RemoveDiscountFromOrderAsync(id, farmId);
            return NoContent();
        }
    }

    // ---- Request DTOs ----

    public class OrderStatusUpdateRequest
    {
        public string Status { get; set; } = string.Empty;
        public string? Reason { get; set; }
    }

    public class OrderRecalcRequest
    {
        public decimal TaxRate { get; set; }
        public decimal ServiceChargeRate { get; set; }
    }

    public class OrderItemStatusRequest
    {
        public string Status { get; set; } = string.Empty;
    }

    public class OrderPaymentRequest
    {
        public string PaymentMethod { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public decimal TipAmount { get; set; }
        public string? Reference { get; set; }
    }

    public class ApplyDiscountRequest
    {
        public int? DiscountId { get; set; }
        public string DiscountName { get; set; } = string.Empty;
        public string DiscountType { get; set; } = "Percentage";
        public decimal Value { get; set; }
        public decimal AppliedAmount { get; set; }
    }
}
