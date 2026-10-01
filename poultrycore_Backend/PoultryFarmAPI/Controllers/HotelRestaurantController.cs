using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Helpers;

namespace PoultryFarmAPIWeb.Controllers
{
    public class CreateMenuItemRequest { public string FarmId { get; set; } = ""; public string Name { get; set; } = ""; public string Category { get; set; } = ""; public string? Description { get; set; } public decimal Price { get; set; } }
    public class UpdateMenuItemRequest { public string FarmId { get; set; } = ""; public string Name { get; set; } = ""; public string Category { get; set; } = ""; public string? Description { get; set; } public decimal Price { get; set; } public bool IsAvailable { get; set; } = true; }
    public class CreateTableRequest { public string FarmId { get; set; } = ""; public string TableNumber { get; set; } = ""; public int Capacity { get; set; } = 4; public string? Location { get; set; } }
    public class OrderItemInput { public int MenuItemId { get; set; } public int Quantity { get; set; } = 1; public decimal UnitPrice { get; set; } public string? Notes { get; set; } }
    public class CreateOrderRequest { public string FarmId { get; set; } = ""; public string? TableNumber { get; set; } public string? ServerName { get; set; } public int? HotelBookingId { get; set; } public int? HotelRoomId { get; set; } public List<OrderItemInput>? Items { get; set; }
        /// <summary>327: true = the lines go on the booking's folio and no cash moves; false = paid at the till.</summary>
        public bool ChargeToRoom { get; set; } public string? PaymentMethod { get; set; } public int? HotelCashAccountId { get; set; } }

    // Orders and their money are written by sphotelrestaurantorder_create / _setstatus
    // (migration 327) in one transaction: a paid order posts POS cash, a room-charged
    // order becomes folio charges, a cancellation reverses either. Refusals are 400s.
    [ApiController][Authorize][Route("api/Hotel/restaurant")][HotelBusinessRuleFilter]
    public class HotelRestaurantController : ControllerBase
    {
        private readonly string _cs;
        public HotelRestaurantController(IConfiguration config) { _cs = config.GetConnectionString("PoultryConn") ?? ""; }

        [HttpGet("menu")]
        public async Task<IActionResult> ListMenu([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelmenuitems WHERE farmid=@f ORDER BY category, name", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("menu")]
        public async Task<IActionResult> CreateMenuItem([FromBody] CreateMenuItemRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("INSERT INTO hotelmenuitems(farmid,name,category,description,price) VALUES(@f,@n,@c,@d,@p) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@n", req.Name);
            cmd.Parameters.AddWithValue("@c", req.Category); cmd.Parameters.AddWithValue("@d", (object?)req.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@p", req.Price);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        [HttpPut("menu/{id}")]
        public async Task<IActionResult> UpdateMenuItem(int id, [FromBody] UpdateMenuItemRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("UPDATE hotelmenuitems SET name=@n,category=@c,description=@d,price=@p,isavailable=@a,updatedat=NOW() WHERE hotelmenuitemid=@id AND farmid=@f", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@n", req.Name); cmd.Parameters.AddWithValue("@c", req.Category);
            cmd.Parameters.AddWithValue("@d", (object?)req.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@p", req.Price); cmd.Parameters.AddWithValue("@a", req.IsAvailable);
            await cmd.ExecuteNonQueryAsync();
            return NoContent();
        }

        [HttpDelete("menu/{id}")]
        public async Task<IActionResult> DeleteMenuItem(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("DELETE FROM hotelmenuitems WHERE hotelmenuitemid=@id AND farmid=@f", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            await cmd.ExecuteNonQueryAsync();
            return NoContent();
        }

        [HttpGet("tables")]
        public async Task<IActionResult> ListTables([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelrestauranttables WHERE farmid=@f ORDER BY tablenumber", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("tables")]
        public async Task<IActionResult> CreateTable([FromBody] CreateTableRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("INSERT INTO hotelrestauranttables(farmid,tablenumber,capacity,location) VALUES(@f,@n,@c,@l) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@n", req.TableNumber);
            cmd.Parameters.AddWithValue("@c", req.Capacity); cmd.Parameters.AddWithValue("@l", (object?)req.Location ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        [HttpGet("orders")]
        public async Task<IActionResult> ListOrders([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelrestaurantorders WHERE farmid=@f ORDER BY ordertime DESC", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("orders")]
        public async Task<IActionResult> CreateOrder([FromBody] CreateOrderRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();

            var items = (req.Items ?? new List<OrderItemInput>())
                .Select(i => new { menuItemId = i.MenuItemId, quantity = i.Quantity, unitPrice = i.UnitPrice, notes = i.Notes });
            int orderId;
            using (var cmd = new NpgsqlCommand(
                "SELECT sphotelrestaurantorder_create(p_farmid => @f::text, p_tablenumber => @t::text, p_servername => @s::text, " +
                "p_bookingid => @b::int, p_roomid => @r::int, p_items => @items, p_chargetoroom => @room::boolean, " +
                "p_paymentmethod => @pm::text, p_cashaccountid => @ca::int, p_by => @by::text)", conn))
            {
                cmd.Parameters.AddWithValue("@f", req.FarmId);
                cmd.Parameters.AddWithValue("@t", (object?)req.TableNumber ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@s", (object?)req.ServerName ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@b", (object?)req.HotelBookingId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@r", (object?)req.HotelRoomId ?? DBNull.Value);
                cmd.Parameters.Add(new NpgsqlParameter("@items", NpgsqlDbType.Jsonb) { Value = JsonSerializer.Serialize(items) });
                cmd.Parameters.AddWithValue("@room", req.ChargeToRoom);
                cmd.Parameters.AddWithValue("@pm", (object?)req.PaymentMethod ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ca", (object?)req.HotelCashAccountId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@by", (object?)HotelAuthHelper.GetUserName(User) ?? DBNull.Value);
                orderId = Convert.ToInt32(await cmd.ExecuteScalarAsync());
            }

            using var getCmd = new NpgsqlCommand("SELECT * FROM hotelrestaurantorders WHERE hotelrestaurantorderid=@id AND farmid=@f", conn);
            getCmd.Parameters.AddWithValue("@id", orderId); getCmd.Parameters.AddWithValue("@f", req.FarmId);
            using var rd = await getCmd.ExecuteReaderAsync();
            return await rd.ReadAsync() ? Ok(ReadRow(rd)) : Ok(new { hotelRestaurantOrderId = orderId });
        }

        [HttpGet("orders/{id}/items")]
        public async Task<IActionResult> GetOrderItems(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelrestaurantorderitems WHERE hotelrestaurantorderid=@id AND farmid=@f ORDER BY hotelrestaurantorderitemid", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPatch("orders/{id}/status")]
        public async Task<IActionResult> UpdateOrderStatus(int id, [FromQuery] string farmId, [FromBody] UpdateStatusRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelrestaurantorder_setstatus(p_farmid => @f::text, p_orderid => @id::int, p_status => @s::text, p_by => @by::text)", conn);
            cmd.Parameters.AddWithValue("@s", req.Status ?? ""); cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@by", (object?)HotelAuthHelper.GetUserName(User) ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
            return NoContent();
        }

        private static async Task<List<Dictionary<string, object?>>> ReadAll(NpgsqlCommand cmd) { using var r = await cmd.ExecuteReaderAsync(); var list = new List<Dictionary<string, object?>>(); while (await r.ReadAsync()) list.Add(ReadRow(r)); return list; }
        private static Dictionary<string, object?> ReadRow(NpgsqlDataReader r) { var d = new Dictionary<string, object?>(); for (int i = 0; i < r.FieldCount; i++) { var n = r.GetName(i); d[char.ToLower(n[0]) + n[1..]] = r.IsDBNull(i) ? null : r.GetValue(i); } return d; }
    }
}
