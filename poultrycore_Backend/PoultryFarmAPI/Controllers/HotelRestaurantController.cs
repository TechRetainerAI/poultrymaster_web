using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Helpers;

namespace PoultryFarmAPIWeb.Controllers
{
    public class CreateMenuItemRequest { public string FarmId { get; set; } = ""; public string Name { get; set; } = ""; public string Category { get; set; } = ""; public string? Description { get; set; } public decimal Price { get; set; } }
    public class UpdateMenuItemRequest { public string FarmId { get; set; } = ""; public string Name { get; set; } = ""; public string Category { get; set; } = ""; public string? Description { get; set; } public decimal Price { get; set; } public bool IsAvailable { get; set; } = true; }
    public class CreateTableRequest { public string FarmId { get; set; } = ""; public string TableNumber { get; set; } = ""; public int Capacity { get; set; } = 4; public string? Location { get; set; } }
    public class OrderItemInput { public int MenuItemId { get; set; } public int Quantity { get; set; } = 1; public decimal UnitPrice { get; set; } public string? Notes { get; set; } }
    public class CreateOrderRequest { public string FarmId { get; set; } = ""; public string? TableNumber { get; set; } public string? ServerName { get; set; } public int? HotelBookingId { get; set; } public int? HotelRoomId { get; set; } public List<OrderItemInput>? Items { get; set; } }

    [ApiController][Authorize][Route("api/Hotel/restaurant")]
    public class HotelRestaurantController : ControllerBase
    {
        private readonly string _cs;
        public HotelRestaurantController(IConfiguration config) => _cs = config.GetConnectionString("PoultryConn") ?? "";

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

            // Calculate totals from items
            decimal subtotal = 0;
            if (req.Items != null) subtotal = req.Items.Sum(i => i.UnitPrice * i.Quantity);

            // Insert order header
            int orderId;
            using (var cmd = new NpgsqlCommand("INSERT INTO hotelrestaurantorders(farmid,tablenumber,servername,hotelbookingid,hotelroomid,status,subtotal,totalamount) VALUES(@f,@t,@s,@b,@r,'Placed',@sub,@sub) RETURNING hotelrestaurantorderid", conn))
            {
                cmd.Parameters.AddWithValue("@f", req.FarmId);
                cmd.Parameters.AddWithValue("@t", (object?)req.TableNumber ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@s", (object?)req.ServerName ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@b", (object?)req.HotelBookingId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@r", (object?)req.HotelRoomId ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@sub", subtotal);
                orderId = Convert.ToInt32(await cmd.ExecuteScalarAsync());
            }

            // Insert line items
            if (req.Items != null)
            {
                foreach (var item in req.Items)
                {
                    // Get item name
                    string itemName = "";
                    using (var nc = new NpgsqlCommand("SELECT name FROM hotelmenuitems WHERE hotelmenuitemid=@id", conn))
                    { nc.Parameters.AddWithValue("@id", item.MenuItemId); itemName = (await nc.ExecuteScalarAsync())?.ToString() ?? "Unknown"; }

                    using var ic = new NpgsqlCommand("INSERT INTO hotelrestaurantorderitems(farmid,hotelrestaurantorderid,hotelmenuitemid,itemname,quantity,unitprice,linetotal,notes) VALUES(@f,@o,@m,@n,@q,@u,@lt,@nt)", conn);
                    ic.Parameters.AddWithValue("@f", req.FarmId); ic.Parameters.AddWithValue("@o", orderId);
                    ic.Parameters.AddWithValue("@m", item.MenuItemId); ic.Parameters.AddWithValue("@n", itemName);
                    ic.Parameters.AddWithValue("@q", item.Quantity); ic.Parameters.AddWithValue("@u", item.UnitPrice);
                    ic.Parameters.AddWithValue("@lt", item.UnitPrice * item.Quantity);
                    ic.Parameters.AddWithValue("@nt", (object?)item.Notes ?? DBNull.Value);
                    await ic.ExecuteNonQueryAsync();
                }
            }

            // Return the created order
            using var getCmd = new NpgsqlCommand("SELECT * FROM hotelrestaurantorders WHERE hotelrestaurantorderid=@id", conn);
            getCmd.Parameters.AddWithValue("@id", orderId);
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
            using var cmd = new NpgsqlCommand("UPDATE hotelrestaurantorders SET status=@s,updatedat=NOW(),deliveredtime=CASE WHEN @s='Served' THEN NOW() ELSE deliveredtime END WHERE hotelrestaurantorderid=@id AND farmid=@f", conn);
            cmd.Parameters.AddWithValue("@s", req.Status); cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            await cmd.ExecuteNonQueryAsync();
            return NoContent();
        }

        private static async Task<List<Dictionary<string, object?>>> ReadAll(NpgsqlCommand cmd) { using var r = await cmd.ExecuteReaderAsync(); var list = new List<Dictionary<string, object?>>(); while (await r.ReadAsync()) list.Add(ReadRow(r)); return list; }
        private static Dictionary<string, object?> ReadRow(NpgsqlDataReader r) { var d = new Dictionary<string, object?>(); for (int i = 0; i < r.FieldCount; i++) { var n = r.GetName(i); d[char.ToLower(n[0]) + n[1..]] = r.IsDBNull(i) ? null : r.GetValue(i); } return d; }
    }
}
