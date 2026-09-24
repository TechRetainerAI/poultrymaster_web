using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class HouseController : ControllerBase
    {
        private readonly IHouseService _service;
        private readonly IIamService _iam;
        private readonly IAuditLogService _auditLog;
        private readonly ILogger<HouseController> _logger;

        public HouseController(
            IHouseService service,
            IIamService iam,
            IAuditLogService auditLog,
            ILogger<HouseController> logger)
        {
            _service = service;
            _iam = iam;
            _auditLog = auditLog;
            _logger = logger;
        }

        // GET: api/House?userId=...&farmId=...
        [HttpGet]
        public ActionResult<List<HouseModel>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");
            var list = _service.GetAll(userId, farmId);
            return Ok(list);
        }

        // GET: api/House/{id}?userId=...&farmId=...
        [HttpGet("{id:int}")]
        public ActionResult<HouseModel> Get(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");
            var item = _service.GetById(id, userId, farmId);
            if (item == null) return NotFound();
            return Ok(item);
        }

        // POST: api/House
        [HttpPost]
        public ActionResult Create([FromBody] HouseModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrEmpty(model.UserId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(model.FarmId)) return BadRequest("FarmId is required.");
            var id = _service.Create(model);
            var created = _service.GetById(id, model.UserId, model.FarmId);
            return CreatedAtAction(nameof(Get), new { id, userId = model.UserId, farmId = model.FarmId }, created);
        }

        // POST: api/House/bulk
        //
        // Create many houses/pens for one company at once. Same permission as the
        // single create (IamPermissionMap resolves "house/bulk" + POST to
        // poultry.houses.create), same stored function, same audit resource -- the
        // only thing this adds is doing it N times inside one transaction.
        //
        // Reusable on purpose: the Farm Setup Wizard and the Batch-to-Flock
        // allocation screen can post the same body. Only `source` differs, and it
        // exists so the audit trail says which screen a batch came from.
        [HttpPost("bulk")]
        public async Task<ActionResult<BulkHouseCreateResult>> CreateBulk([FromBody] BulkHouseCreateRequest request)
        {
            if (request == null) return BadRequest("A request body is required.");
            if (string.IsNullOrEmpty(request.UserId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(request.FarmId)) return BadRequest("FarmId is required.");

            // Company isolation. The browser states the company once, here, and
            // every row is written against it -- a row cannot carry its own farm.
            // What is still worth checking is that the company it named is a
            // POULTRY company: this tool creates poultry houses and nothing else.
            //
            // Fails OPEN when the type cannot be resolved (unknown farm, missing
            // IAM migration): the same posture as IamEnforcementFilter, where a
            // lookup that cannot answer must not take a working feature down.
            // Who may write to this company at all is IAM's job, via the map above.
            var module = await _iam.GetModuleForFarmAsync(request.FarmId);
            if (module is not null && !string.Equals(module, "poultry", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(new BulkHouseCreateResult
                {
                    Success = false,
                    Message = "Houses can only be created for a poultry company.",
                });
            }

            // Existing names for the duplicate check, read through the ordinary
            // farm-scoped reader so this sees exactly the houses the user sees.
            var existing = _service.GetAll(request.UserId, request.FarmId);

            var errors = HouseBulkValidator.Validate(request.Houses, existing.Select(h => h.HouseName));
            if (errors.Count > 0)
            {
                return BadRequest(new BulkHouseCreateResult
                {
                    Success = false,
                    Errors = errors,
                    Message = errors.Count == 1
                        ? errors[0].Message
                        : $"{errors.Count} rows need attention before these houses can be created.",
                });
            }

            var rows = HouseBulkValidator.Normalize(request.Houses);

            List<HouseModel> created;
            try
            {
                created = _service.CreateBulk(request.UserId, request.FarmId, rows);
            }
            catch (Exception ex)
            {
                // Nothing was created -- CreateBulk rolled the batch back.
                _logger.LogError(ex, "Bulk house creation failed for farm {FarmId}; {Count} houses rolled back.",
                    request.FarmId, rows.Count);
                return StatusCode(500, new BulkHouseCreateResult
                {
                    Success = false,
                    Message = "None of the houses were created. " + ex.Message,
                });
            }

            await WriteBulkAuditAsync(request, created);

            return Ok(new BulkHouseCreateResult
            {
                Success = true,
                CreatedCount = created.Count,
                Houses = created,
                Message = created.Count == 1
                    ? "1 house/pen created successfully."
                    : $"{created.Count} houses/pens created successfully.",
            });
        }

        /// <summary>
        /// One audit row per house, on top of the single request-level row the
        /// global AuditLogActionFilter writes. Without this a batch of 50 would be
        /// one audit entry, and an individual house would not be traceable the way
        /// one added through the single form is.
        /// </summary>
        private async Task WriteBulkAuditAsync(BulkHouseCreateRequest request, List<HouseModel> created)
        {
            var source = string.IsNullOrWhiteSpace(request.Source) ? "Bulk House Creation" : request.Source!.Trim();
            var userName = User?.FindFirst(ClaimTypes.Name)?.Value
                           ?? User?.Identity?.Name
                           ?? Request.Headers["X-Username"].FirstOrDefault()
                           ?? request.UserId;

            foreach (var house in created)
            {
                try
                {
                    await _auditLog.InsertAsync(new AuditLogModel
                    {
                        UserId = request.UserId,
                        UserName = userName,
                        FarmId = request.FarmId,
                        Action = "POST",
                        Resource = "House",
                        ResourceId = house.HouseId.ToString(),
                        Details = $"POST House (ID: {house.HouseId}) - Created via {source}",
                        Data = System.Text.Json.JsonSerializer.Serialize(new
                        {
                            source,
                            batchSize = created.Count,
                            house.HouseId,
                            house.HouseName,
                            house.Capacity,
                            house.Location,
                        }),
                        IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString(),
                        UserAgent = Request.Headers["User-Agent"].FirstOrDefault(),
                        Timestamp = DateTime.UtcNow,
                        Status = "Success",
                    });
                }
                catch (Exception ex)
                {
                    // The houses exist and are committed; losing an audit row must
                    // not turn a successful creation into an error for the user.
                    _logger.LogError(ex, "Could not write bulk audit row for house {HouseId}.", house.HouseId);
                }
            }
        }

        // PUT: api/House/{id}
        [HttpPut("{id:int}")]
        public ActionResult Update(int id, [FromBody] HouseModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrEmpty(model.UserId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(model.FarmId)) return BadRequest("FarmId is required.");
            var existing = _service.GetById(id, model.UserId, model.FarmId);
            if (existing == null) return NotFound();
            model.HouseId = id;
            _service.Update(model);
            return NoContent();
        }

        // DELETE: api/House/{id}?userId=...&farmId=...
        [HttpDelete("{id:int}")]
        public ActionResult Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");
            var existing = _service.GetById(id, userId, farmId);
            if (existing == null) return NotFound();
            _service.Delete(id, userId, farmId);
            return NoContent();
        }
    }
}
