// Livestock Company settings (migration 467): the business profile.
// Currency and time zone are saved through the shared farm-settings and
// CompanyTime endpoints, as for every company type.
//
// PERMISSIONS (IamPermissionMap): livestock/company -> office.settings (as
// water/company). Writes are owner/admin only (SetupAdminOnly).

using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using static PoultryFarmAPIWeb.Business.LivestockDb;

namespace PoultryFarmAPIWeb.Controllers
{
    [Authorize]
    [ApiController]
    [SetupAdminOnly]
    [Route("api/Livestock/company")]
    [RequireCompanyType("Livestock")]
    public class LivestockCompanyController : LivestockControllerBase
    {
        public LivestockCompanyController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> Get([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockprofile_get", Text("p_farmid", farmId))));

        /// <summary>Body: { farmId, brandName, ownerName, phoneNumber, email, mainLocation, siteAddress, totalCapacity, operatingHours, notes }.</summary>
        [HttpPut]
        public Task<IActionResult> Save([FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestockprofile_save", Text("p_farmid", FarmOf(body)), Jsonb("p_x", body.GetRawText()), Text("p_by", by));
                return NoContent();
            });
    }
}
