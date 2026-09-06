using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [Route("api/Restaurant/setup")]
    public class RestaurantSetupController : ControllerBase
    {
        private readonly IRestaurantSetupService _svc;
        public RestaurantSetupController(IRestaurantSetupService svc) => _svc = svc;

        [HttpGet("profile")]
        public async Task<IActionResult> GetProfile([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var p = await _svc.GetProfileAsync(farmId);
            if (p == null) return NotFound();
            return Ok(p);
        }

        [HttpPost("profile")]
        public async Task<IActionResult> UpsertProfile([FromBody] RestaurantProfileModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var result = await _svc.UpsertProfileAsync(m);
            return Ok(result);
        }
        // =====================================================================
        // SUPPLIERS
        // =====================================================================

        [HttpGet("suppliers")]
        public async Task<IActionResult> ListSuppliers([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new Npgsql.NpgsqlConnection(_svc.GetConnectionString());
            await conn.OpenAsync();
            using var cmd = new Npgsql.NpgsqlCommand("SELECT * FROM sprestaurant_supplier_list(p_farmid => @F::text)", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<Dictionary<string, object?>>();
            while (await r.ReadAsync())
            {
                var d = new Dictionary<string, object?>();
                for (int i = 0; i < r.FieldCount; i++) d[r.GetName(i)] = r.IsDBNull(i) ? null : r.GetValue(i);
                list.Add(d);
            }
            return Ok(list);
        }

        [HttpPost("suppliers")]
        public async Task<IActionResult> CreateSupplier([FromBody] CreateSupplierRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new Npgsql.NpgsqlConnection(_svc.GetConnectionString());
            await conn.OpenAsync();
            using var cmd = new Npgsql.NpgsqlCommand(
                "SELECT sprestaurant_supplier_insert(p_farmid=>@F::text, p_name=>@N::text, p_contactname=>@C::text, p_phone=>@P::text, p_email=>@E::text, p_address=>@A::text, p_category=>@Cat::text, p_notes=>@Nt::text)", conn);
            cmd.Parameters.AddWithValue("@F", req.FarmId); cmd.Parameters.AddWithValue("@N", req.Name);
            cmd.Parameters.AddWithValue("@C", (object?)req.ContactName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@P", (object?)req.Phone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@E", (object?)req.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@A", (object?)req.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Cat", (object?)req.Category ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Nt", (object?)req.Notes ?? DBNull.Value);
            var id = Convert.ToInt32(await cmd.ExecuteScalarAsync());
            return Ok(new { restaurantSupplierId = id });
        }

        [HttpDelete("suppliers/{id}")]
        public async Task<IActionResult> DeleteSupplier(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new Npgsql.NpgsqlConnection(_svc.GetConnectionString());
            await conn.OpenAsync();
            using var cmd = new Npgsql.NpgsqlCommand("SELECT sprestaurant_supplier_delete(p_id=>@I::int, p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@I", id); cmd.Parameters.AddWithValue("@F", farmId);
            await cmd.ExecuteNonQueryAsync();
            return NoContent();
        }
    }

    public class CreateSupplierRequest
    {
        public string FarmId { get; set; } = "";
        public string Name { get; set; } = "";
        public string? ContactName { get; set; }
        public string? Phone { get; set; }
        public string? Email { get; set; }
        public string? Address { get; set; }
        public string? Category { get; set; }
        public string? Notes { get; set; }
    }
}
