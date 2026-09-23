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
    /// <summary>
    /// Initial Farm Setup — the onboarding page for a poultry farm that already
    /// has birds when it arrives.
    ///
    /// <para>
    /// This is an orchestration endpoint, not a fourth way to manage batches,
    /// houses or flocks. Those pages stay exactly as they are; this one runs once
    /// and establishes the opening position that makes them honest from day one.
    /// </para>
    /// </summary>
    [ApiController]
    [Route("api/[controller]")]
    public class PoultryFarmSetupController : ControllerBase
    {
        private readonly IFarmSetupService _setupService;
        private readonly IMainFlockBatchService _batchService;
        private readonly IHouseService _houseService;
        private readonly IBirdFlockService _flockService;
        private readonly IProductionRecordService _productionService;
        private readonly ICompanyTimeService _companyTime;
        private readonly IIamService _iam;
        private readonly IAuditLogService _auditLog;
        private readonly IConfiguration _config;
        private readonly ILogger<PoultryFarmSetupController> _logger;

        public PoultryFarmSetupController(
            IFarmSetupService setupService,
            IMainFlockBatchService batchService,
            IHouseService houseService,
            IBirdFlockService flockService,
            IProductionRecordService productionService,
            ICompanyTimeService companyTime,
            IIamService iam,
            IAuditLogService auditLog,
            IConfiguration config,
            ILogger<PoultryFarmSetupController> logger)
        {
            _setupService = setupService;
            _batchService = batchService;
            _houseService = houseService;
            _flockService = flockService;
            _productionService = productionService;
            _companyTime = companyTime;
            _iam = iam;
            _auditLog = auditLog;
            _config = config;
            _logger = logger;
        }

        // GET: api/PoultryFarmSetup/status?userId=...&farmId=...
        [HttpGet("status")]
        public async Task<ActionResult<FarmSetupStatusModel>> GetStatus([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");

            return Ok(await _setupService.GetStatusAsync(userId, farmId));
        }

        // GET: api/PoultryFarmSetup/opening-positions?userId=...&farmId=...
        //
        // Opening historical mortality and what has been recorded since, kept
        // apart. Known lifetime mortality is their sum and never includes the
        // unknown adjustment -- "we don't know what happened to 30 birds" is not
        // 30 deaths, and reporting it as such is the bug this feature exists for.
        [HttpGet("opening-positions")]
        public async Task<ActionResult<OpeningPositionSummaryModel>> GetOpeningPositions(
            [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");

            return Ok(await _setupService.GetOpeningPositionsAsync(farmId));
        }

        // GET: api/PoultryFarmSetup/context?userId=...&farmId=...
        //
        // What the wizard needs to open: the batches, houses (with occupancy) and
        // flock names the company already has, so existing records can be reused
        // rather than duplicated.
        [HttpGet("context")]
        public async Task<ActionResult<object>> GetContext([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");

            var batches = await _batchService.GetAll(userId, farmId);
            var flocks = _flockService.GetAllFlocks(userId, farmId);
            var houses = BuildOccupancy(_houseService.GetAll(userId, farmId), flocks);

            // Birds already allocated per batch, so reusing a batch cannot overspend it.
            var allocated = flocks
                .Where(f => f.BatchId > 0)
                .GroupBy(f => f.BatchId)
                .ToDictionary(g => g.Key, g => g.Sum(f => f.Quantity));

            return Ok(new
            {
                Status = await _setupService.GetStatusAsync(userId, farmId),
                BusinessDate = await _companyTime.GetBusinessDateAsync(farmId),
                Batches = batches,
                Houses = houses,
                ExistingFlockNames = flocks.Select(f => f.Name).Where(n => !string.IsNullOrWhiteSpace(n)).ToList(),
                AllocatedByBatchId = allocated,
            });
        }

        // POST: api/PoultryFarmSetup/complete
        [HttpPost("complete")]
        public async Task<ActionResult<FarmSetupResult>> Complete([FromBody] FarmSetupRequest request)
        {
            if (request == null) return BadRequest("A request body is required.");
            if (string.IsNullOrEmpty(request.UserId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(request.FarmId)) return BadRequest("FarmId is required.");

            // Company type. Fails OPEN when it cannot be resolved, the same posture
            // as IamEnforcementFilter -- a lookup that cannot answer must not take a
            // working feature down.
            var module = await _iam.GetModuleForFarmAsync(request.FarmId);
            if (module is not null && !string.Equals(module, "poultry", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(new FarmSetupResult { Success = false, Message = "Farm setup is only available for a poultry company." });
            }

            // The wizard creates batches and houses as well as flocks, and the route
            // map can only express one key. Rather than invent a farm-setup
            // permission that no role holds yet -- which would lock everyone out the
            // day enforcement is switched on -- the extra rights are checked here,
            // and only once IAM is actually enforcing. In shadow mode this is a
            // no-op and the map's poultry.flocks.create still applies.
            if (_config.GetValue("Iam:Enforced", false))
            {
                var callerId = User?.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? request.UserId;
                foreach (var key in new[] { "poultry.flock-batches.create", "poultry.houses.create" })
                {
                    if (!await _iam.HasPermissionAsync(callerId, request.FarmId, key))
                    {
                        return StatusCode(403, new FarmSetupResult
                        {
                            Success = false,
                            Message = $"Farm setup also creates {(key.Contains("batches") ? "batches" : "houses")}, which you do not have permission to do.",
                        });
                    }
                }
            }

            var status = await _setupService.GetStatusAsync(request.UserId, request.FarmId);
            if (status.IsComplete)
            {
                return Conflict(new FarmSetupResult
                {
                    Success = false,
                    Message = "Initial farm setup has already been completed for this company. Use Flock Purchases, Houses and Flock Groups to add more.",
                });
            }

            // Everything the validator compares against, read through the ordinary
            // farm-scoped readers -- which is also what keeps company scoping in one
            // place. A batch or house from another company is simply not in these
            // lists, so a row naming one is rejected as unavailable.
            var existingBatches = await _batchService.GetAll(request.UserId, request.FarmId);
            var existingFlocks = _flockService.GetAllFlocks(request.UserId, request.FarmId);
            var existingHouses = BuildOccupancy(_houseService.GetAll(request.UserId, request.FarmId), existingFlocks);
            var allocatedByBatch = existingFlocks
                .Where(f => f.BatchId > 0)
                .GroupBy(f => f.BatchId)
                .ToDictionary(g => g.Key, g => g.Sum(f => f.Quantity));

            var (errors, warnings) = FarmSetupValidator.Validate(
                request, existingBatches, existingHouses,
                existingFlocks.Select(f => f.Name), allocatedByBatch);

            if (errors.Count > 0)
            {
                return BadRequest(new FarmSetupResult
                {
                    Success = false,
                    Errors = errors,
                    Warnings = warnings,
                    Message = errors.Count == 1
                        ? errors[0].Message
                        : $"{errors.Count} rows need attention before your farm can be set up.",
                });
            }

            // The opening date is the COMPANY's business date, read server-side.
            // Never the browser's: a farmer in Accra onboarding at 23:40 while the
            // server is on UTC must not have day one recorded as tomorrow.
            var businessDate = await _companyTime.GetBusinessDateAsync(request.FarmId);

            FarmSetupResult result;
            try
            {
                result = await _setupService.CompleteAsync(request, businessDate);
            }
            catch (FarmSetupAlreadyCompleteException ex)
            {
                return Conflict(new FarmSetupResult { Success = false, Message = ex.Message });
            }
            catch (Exception ex)
            {
                // Nothing was created -- CompleteAsync rolled the whole setup back.
                _logger.LogError(ex, "Farm setup failed for farm {FarmId}; nothing was created.", request.FarmId);
                return StatusCode(500, new FarmSetupResult
                {
                    Success = false,
                    Message = "Nothing was created. " + ex.Message,
                });
            }

            result.Warnings = warnings;
            await WriteSetupAuditAsync(request, result);

            return Ok(result);
        }

        // POST: api/PoultryFarmSetup/opening-positions/correct
        //
        // Restating day one, not rewriting what has happened since. Refused the
        // moment the flock has production records: at that point its quantity is no
        // longer the opening figure, and moving it would silently change every
        // birds-left figure that has been reported since.
        [HttpPost("opening-positions/correct")]
        public async Task<ActionResult<object>> CorrectOpeningPosition([FromBody] OpeningFlockPositionCorrection correction)
        {
            if (correction == null) return BadRequest("A request body is required.");
            if (string.IsNullOrEmpty(correction.UserId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(correction.FarmId)) return BadRequest("FarmId is required.");
            if (correction.FlockId <= 0) return BadRequest("FlockId is required.");

            // Farm-scoped: another company's flock is simply not found.
            var flock = _flockService.GetFlockById(correction.FlockId, correction.UserId, correction.FarmId);
            if (flock is null) return NotFound(new { message = "That flock is not available on this farm." });

            var summary = await _setupService.GetOpeningPositionsAsync(correction.FarmId);
            var existing = summary.Positions.FirstOrDefault(p => p.FlockId == correction.FlockId);
            if (existing is null)
                return NotFound(new { message = "That flock has no opening position to correct." });

            // Does this flock have operational history? Read through the ordinary
            // farm-scoped reader and filter -- there is no per-flock count in the
            // API, and adding a stored function for an existence check that runs
            // only during onboarding fix-ups is not worth another migration.
            var hasProduction = (await _productionService.GetAll(correction.UserId, correction.FarmId))
                .Any(r => r.FlockId == correction.FlockId);

            // With production on the books the counts are frozen; only the
            // reclassification of the historical reduction is still allowed.
            var blocked = FarmSetupValidator.ValidateCorrection(
                existing, correction.OriginallyPlaced, correction.OpeningLiveBirds, hasProduction);
            if (blocked is not null)
            {
                _logger.LogInformation(
                    "Opening-position correction refused for flock {FlockId}: {Reason}",
                    correction.FlockId, blocked.Message);
                return blocked.Field == "openingLiveBirds" && hasProduction
                    ? Conflict(new { message = blocked.Message, field = blocked.Field })
                    : BadRequest(new { message = blocked.Message, field = blocked.Field });
            }

            if (correction.HistoryKnown)
            {
                var difference = Math.Max(0, correction.OriginallyPlaced - correction.OpeningLiveBirds);
                var known = correction.HistoricalMortality + correction.HistoricalSold
                            + correction.HistoricalCulled + correction.HistoricalTransferred;
                if (known > difference)
                    return BadRequest(new { message = $"The breakdown adds up to {known:N0} but only {difference:N0} birds are unaccounted for." });
            }

            var ok = await _setupService.CorrectOpeningPositionAsync(correction);
            if (!ok) return NotFound(new { message = "That flock has no opening position to correct." });

            try
            {
                await _auditLog.InsertAsync(BuildAuditRow(correction.UserId, correction.FarmId,
                    "Flock", correction.FlockId.ToString(),
                    $"Opening position corrected for flock {correction.FlockId}"
                    + (hasProduction ? " (reclassified; counts unchanged)" : " (restated)"),
                    new
                    {
                        source = "Opening Position Correction",
                        correction.FlockId,
                        correction.OriginallyPlaced,
                        correction.OpeningLiveBirds,
                        correction.HistoryKnown,
                        hadProductionRecords = hasProduction,
                    }));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Could not write audit row for opening-position correction on flock {FlockId}.", correction.FlockId);
            }

            return Ok(new { success = true, message = "Opening position updated." });
        }

        /// <summary>
        /// Houses with what is already in them. Occupancy counts ACTIVE flocks only
        /// and a house may hold several — the existing rules, shared with the batch
        /// allocation tool.
        /// </summary>
        private static List<HouseOccupancyModel> BuildOccupancy(List<HouseModel> houses, List<FlockModel> flocks)
        {
            var active = flocks.Where(f => f.Active && f.HouseId.HasValue).ToList();

            return houses.Select(h =>
            {
                var inHouse = active.Where(f => f.HouseId == h.HouseId).ToList();
                var occupied = inHouse.Sum(f => f.Quantity);
                return new HouseOccupancyModel
                {
                    HouseId = h.HouseId,
                    HouseName = h.HouseName,
                    Capacity = h.Capacity,
                    Location = h.Location,
                    Occupied = occupied,
                    AvailableCapacity = FlockAllocationValidator.AvailableCapacity(h.Capacity, occupied),
                    ActiveFlocks = inHouse.Count,
                };
            }).ToList();
        }

        /// <summary>
        /// One audit row for the setup as a whole, on top of the request-level row
        /// the global filter writes. The individual batches, houses and flocks are
        /// each audited by that same filter's per-request row plus this summary,
        /// which is what lets someone answer "where did this flock come from"
        /// months later.
        /// </summary>
        private async Task WriteSetupAuditAsync(FarmSetupRequest request, FarmSetupResult result)
        {
            try
            {
                await _auditLog.InsertAsync(BuildAuditRow(request.UserId, request.FarmId,
                    "FarmSetup", null,
                    $"Initial Farm Setup completed: {result.BatchesCreated} batches, {result.HousesCreated} houses, " +
                    $"{result.FlocksCreated} flocks, {result.OpeningLiveBirds:N0} opening live birds, " +
                    $"{result.HistoricalReduction:N0} opening historical reduction",
                    new
                    {
                        source = string.IsNullOrWhiteSpace(request.Source) ? "Initial Farm Setup" : request.Source,
                        result.BatchesCreated,
                        result.BatchesReused,
                        result.HousesCreated,
                        result.HousesReused,
                        result.FlocksCreated,
                        result.OpeningPositionsCreated,
                        result.OriginallyPlaced,
                        result.OpeningLiveBirds,
                        result.HistoricalReduction,
                        effectiveBusinessDate = result.EffectiveBusinessDate,
                    }));
            }
            catch (Exception ex)
            {
                // The farm exists and is committed; losing an audit row must not turn
                // a successful setup into an error for the user.
                _logger.LogError(ex, "Could not write farm-setup audit row for farm {FarmId}.", request.FarmId);
            }
        }

        private AuditLogModel BuildAuditRow(string userId, string farmId, string resource, string? resourceId, string details, object data) => new()
        {
            UserId = userId,
            UserName = User?.FindFirst(ClaimTypes.Name)?.Value
                       ?? User?.Identity?.Name
                       ?? Request.Headers["X-Username"].FirstOrDefault()
                       ?? userId,
            FarmId = farmId,
            Action = "POST",
            Resource = resource,
            ResourceId = resourceId,
            Details = details,
            Data = System.Text.Json.JsonSerializer.Serialize(data),
            IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString(),
            UserAgent = Request.Headers["User-Agent"].FirstOrDefault(),
            Timestamp = DateTime.UtcNow,
            Status = "Success",
        };
    }
}
