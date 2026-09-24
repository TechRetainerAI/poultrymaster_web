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
    public class FlockController : ControllerBase
    {
        private readonly IBirdFlockService _flockService;
        private readonly IMainFlockBatchService _batchService;
        private readonly IHouseService _houseService;
        private readonly IFarmSetupService _setupService;
        private readonly IAuditLogService _auditLog;
        private readonly ILogger<FlockController> _logger;

        public FlockController(
            IBirdFlockService flockService,
            IMainFlockBatchService batchService,
            IHouseService houseService,
            IFarmSetupService setupService,
            IAuditLogService auditLog,
            ILogger<FlockController> logger)
        {
            _flockService = flockService;
            _batchService = batchService;
            _houseService = houseService;
            _setupService = setupService;
            _auditLog = auditLog;
            _logger = logger;
        }

        /// <summary>
        /// Birds a batch has actually given out.
        ///
        /// <para>
        /// spflock_gettotalquantityforbatch sums flock QUANTITIES, which for a flock
        /// created by Initial Farm Setup is its opening LIVE birds -- 960 of the
        /// 1,050 that were placed. Reading that alone would leave the batch looking
        /// like it still has 90 birds spare and invite someone to allocate birds
        /// that died months ago. The opening historical reduction is added back so
        /// the batch is measured by what was placed, which is what its
        /// NumberOfBirds means (migration 319).
        /// </para>
        /// </summary>
        private async Task<int> ConsumedFromBatchAsync(int batchId, string userId, string farmId)
        {
            var allocated = await _flockService.GetTotalFlockQuantityForBatch(batchId, userId, farmId);

            var opening = await _setupService.GetOpeningPositionsAsync(farmId);
            var openingReduction = opening.Positions
                .Where(p => p.BatchId == batchId)
                .Sum(p => p.HistoricalReduction);

            return allocated + openingReduction;
        }

        // GET: api/Flock/{id}?userId=xxx&farmId=yyy
        [HttpGet("{id:int}")]
        public ActionResult<FlockModel> Get(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var flock = _flockService.GetFlockById(id, userId, farmId);
            if (flock == null)
                return NotFound();

            return Ok(flock);
        }

        // GET: api/Flock?userId=xxx&farmId=yyy
        [HttpGet]
        public ActionResult<List<FlockModel>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var flocks = _flockService.GetAllFlocks(userId, farmId);
            return Ok(flocks);
        }

        // POST: api/Flock
        [HttpPost]
        public async Task<ActionResult> Create([FromBody] FlockModel model)
        {
            try
            {
                if (!ModelState.IsValid)
                {
                    var errors = ModelState.Values.SelectMany(v => v.Errors).Select(e => e.ErrorMessage);
                    return BadRequest(new { message = "Validation failed", errors = errors });
                }

                if (string.IsNullOrEmpty(model.UserId))
                    return BadRequest(new { message = "UserId is required in the flock model." });
                if (string.IsNullOrEmpty(model.FarmId))
                    return BadRequest(new { message = "FarmId is required in the flock model." });

                if (model.BatchId <= 0)
                    return BadRequest(new { message = "BatchId is required and must be greater than 0." });

                var batch = await _batchService.GetById(model.BatchId, model.UserId, model.FarmId);
                if (batch == null)
                {
                    return BadRequest(new { message = $"Flock Batch with ID {model.BatchId} not found." });
                }

                var existingFlockQuantityInBatch = await _flockService.GetTotalFlockQuantityForBatch(model.BatchId, model.UserId, model.FarmId);
                if (existingFlockQuantityInBatch + model.Quantity > batch.NumberOfBirds)
                {
                    return BadRequest(new { message = $"The total quantity of birds ({existingFlockQuantityInBatch + model.Quantity}) exceeds the available birds in batch '{batch.BatchName}' ({batch.NumberOfBirds})." });
                }

                int newFlockId = await _flockService.CreateFlock(model);
                var createdFlock = _flockService.GetFlockById(newFlockId, model.UserId, model.FarmId);
                return CreatedAtAction(nameof(Get), new { id = newFlockId, userId = model.UserId, farmId = model.FarmId }, createdFlock);
            }
            catch (Exception ex)
            {
                // Log the exception for debugging
                Console.WriteLine($"Error in FlockController.Create: {ex.Message}");
                Console.WriteLine($"Stack trace: {ex.StackTrace}");
                if (ex.InnerException != null)
                {
                    Console.WriteLine($"Inner exception: {ex.InnerException.Message}");
                }
                
                return StatusCode(500, new { 
                    message = "An error occurred while creating the flock.", 
                    error = ex.Message,
                    details = ex.InnerException?.Message 
                });
            }
        }

        // GET: api/Flock/allocation-context/{batchId}?userId=...&farmId=...
        //
        // Everything the batch allocation tool needs to open: what the batch has
        // left to give, and this company's houses with their current occupancy.
        //
        // Every number is derived, never stored: allocated birds come from
        // spflock_gettotalquantityforbatch and occupancy from the active flocks
        // placed in each house. There is no "allocated" counter to drift.
        [HttpGet("allocation-context/{batchId:int}")]
        public async Task<ActionResult<BatchAllocationContext>> GetAllocationContext(
            int batchId, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");

            // Farm-scoped read: another company's batch simply is not found.
            var batch = await _batchService.GetById(batchId, userId, farmId);
            if (batch == null) return NotFound(new { message = "That batch is not available on this farm." });

            var allocated = await ConsumedFromBatchAsync(batchId, userId, farmId);
            var flocks = _flockService.GetAllFlocks(userId, farmId);
            var houses = _houseService.GetAll(userId, farmId);

            return Ok(new BatchAllocationContext
            {
                Batch = BuildSummary(batch, allocated),
                Houses = BuildOccupancy(houses, flocks),
                ExistingFlockNames = flocks.Select(f => f.Name).Where(n => !string.IsNullOrWhiteSpace(n)).ToList(),
            });
        }

        // POST: api/Flock/bulk-allocate
        //
        // Divide one batch across many houses in a single operation. Same
        // permission as the single create (IamPermissionMap resolves
        // "flock/bulk-allocate" + POST to poultry.flocks.create), same stored
        // function, same audit resource -- the difference is that it happens N
        // times inside one transaction, under a lock on the batch.
        //
        // Creating a flock is NOT a production event: nothing here writes a
        // production record. The flock starts life with the allocated quantity,
        // which is exactly how the single Add Flock form works.
        [HttpPost("bulk-allocate")]
        public async Task<ActionResult<FlockAllocationResult>> BulkAllocate([FromBody] FlockAllocationRequest request)
        {
            if (request == null) return BadRequest("A request body is required.");
            if (string.IsNullOrEmpty(request.UserId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(request.FarmId)) return BadRequest("FarmId is required.");
            if (request.BatchId <= 0) return BadRequest("BatchId is required and must be greater than 0.");

            // Company scoping, all three ways at once:
            //  - the batch is read farm-scoped, so another company's batch is not found;
            //  - houses are read farm-scoped, and a row naming anything outside that
            //    list is rejected by the validator;
            //  - flocks are written with the envelope's FarmId, which no row can override.
            var batch = await _batchService.GetById(request.BatchId, request.UserId, request.FarmId);
            if (batch == null)
            {
                return BadRequest(new FlockAllocationResult
                {
                    Success = false,
                    Message = "That batch is not available on this farm.",
                });
            }

            var flocks = _flockService.GetAllFlocks(request.UserId, request.FarmId);
            var houses = BuildOccupancy(_houseService.GetAll(request.UserId, request.FarmId), flocks);
            var allocated = await ConsumedFromBatchAsync(request.BatchId, request.UserId, request.FarmId);
            var available = Math.Max(0, batch.NumberOfBirds - allocated);

            var errors = FlockAllocationValidator.Validate(
                request.Allocations, available, houses, flocks.Select(f => f.Name));

            if (errors.Count > 0)
            {
                return BadRequest(new FlockAllocationResult
                {
                    Success = false,
                    Errors = errors,
                    Batch = BuildSummary(batch, allocated),
                    Message = errors.Count == 1
                        ? errors[0].Message
                        : $"{errors.Count} rows need attention before these flocks can be created.",
                });
            }

            // Breed and start date come from the batch unless the caller overrode
            // them -- the same prefill the single Add Flock form does.
            var breed = string.IsNullOrWhiteSpace(request.Breed) ? batch.Breed : request.Breed!.Trim();
            var startDate = request.StartDate ?? batch.StartDate;
            var hasArrived = request.HasArrived ?? true;

            var models = request.Allocations.Select(a => new FlockModel
            {
                UserId = request.UserId,
                FarmId = request.FarmId,
                BatchId = request.BatchId,
                Name = FlockAllocationValidator.NormalizeName(a.Name),
                Breed = breed,
                StartDate = startDate,
                Quantity = a.Quantity,
                Active = true,
                HasArrived = hasArrived,
                HouseId = a.HouseId,
                Notes = string.IsNullOrWhiteSpace(a.Notes) ? null : a.Notes!.Trim(),
            }).ToList();

            List<FlockModel> created;
            try
            {
                created = await _flockService.AllocateBatchToFlocks(
                    request.UserId, request.FarmId, request.BatchId, batch.NumberOfBirds, models);
            }
            catch (FlockAllocationConflictException conflict)
            {
                // Someone else allocated from this batch while the tool was open.
                // Nothing was created; 409 so the client can reload and retry.
                _logger.LogInformation(
                    "Batch {BatchId} allocation rejected at posting time: {Requested} requested, {Available} available.",
                    request.BatchId, conflict.Requested, conflict.Available);
                return Conflict(new FlockAllocationResult
                {
                    Success = false,
                    Batch = BuildSummary(batch, conflict.AlreadyAllocated),
                    Errors = new List<FlockAllocationRowError>
                    {
                        new() { Index = -1, Field = "allocations", Message = conflict.Message },
                    },
                    Message = conflict.Message,
                });
            }
            catch (Exception ex)
            {
                // Nothing was created -- AllocateBatchToFlocks rolled the batch back.
                _logger.LogError(ex, "Batch {BatchId} allocation failed; {Count} flocks rolled back.",
                    request.BatchId, models.Count);
                return StatusCode(500, new FlockAllocationResult
                {
                    Success = false,
                    Message = "None of the flocks were created. " + ex.Message,
                });
            }

            await WriteAllocationAuditAsync(request, created);

            var birdsAllocated = created.Sum(f => f.Quantity);
            var newTotal = allocated + birdsAllocated;

            return Ok(new FlockAllocationResult
            {
                Success = true,
                CreatedCount = created.Count,
                BirdsAllocated = birdsAllocated,
                Flocks = created,
                Batch = BuildSummary(batch, newTotal),
                Message = created.Count == 1
                    ? $"1 flock created successfully. {birdsAllocated:N0} birds allocated from {batch.BatchCode}."
                    : $"{created.Count} flocks created successfully. {birdsAllocated:N0} birds allocated from {batch.BatchCode}.",
            });
        }

        private static BatchAllocationSummary BuildSummary(MainFlockBatchModel batch, int allocated) => new()
        {
            BatchId = batch.BatchId,
            BatchCode = batch.BatchCode,
            BatchName = batch.BatchName,
            Breed = batch.Breed,
            StartDate = batch.StartDate,
            OriginalBirds = batch.NumberOfBirds,
            AllocatedBirds = allocated,
            UnallocatedBirds = Math.Max(0, batch.NumberOfBirds - allocated),
        };

        /// <summary>
        /// Houses with what is already in them.
        ///
        /// Occupancy counts ACTIVE flocks only, and a house may hold several --
        /// both are the existing rules, taken from the capacity check the Flock
        /// Groups page already applies. A house with no capacity recorded is left
        /// unconstrained rather than treated as holding zero birds.
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
        /// One audit row per flock, on top of the single request-level row the
        /// global AuditLogActionFilter writes. Without this an allocation of fifty
        /// would be one audit entry, and an individual flock would not be traceable
        /// the way one added through the single form is.
        /// </summary>
        private async Task WriteAllocationAuditAsync(FlockAllocationRequest request, List<FlockModel> created)
        {
            var source = string.IsNullOrWhiteSpace(request.Source) ? "Batch Allocation Tool" : request.Source!.Trim();
            var userName = User?.FindFirst(ClaimTypes.Name)?.Value
                           ?? User?.Identity?.Name
                           ?? Request.Headers["X-Username"].FirstOrDefault()
                           ?? request.UserId;

            foreach (var flock in created)
            {
                try
                {
                    await _auditLog.InsertAsync(new AuditLogModel
                    {
                        UserId = request.UserId,
                        UserName = userName,
                        FarmId = request.FarmId,
                        Action = "POST",
                        Resource = "Flock",
                        ResourceId = flock.FlockId.ToString(),
                        Details = $"POST Flock (ID: {flock.FlockId}) - Created via {source}",
                        Data = System.Text.Json.JsonSerializer.Serialize(new
                        {
                            source,
                            batchId = request.BatchId,
                            allocationSize = created.Count,
                            flock.FlockId,
                            flock.Name,
                            flock.Quantity,
                            flock.HouseId,
                        }),
                        IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString(),
                        UserAgent = Request.Headers["User-Agent"].FirstOrDefault(),
                        Timestamp = DateTime.UtcNow,
                        Status = "Success",
                    });
                }
                catch (Exception ex)
                {
                    // The flocks exist and are committed; losing an audit row must
                    // not turn a successful allocation into an error for the user.
                    _logger.LogError(ex, "Could not write allocation audit row for flock {FlockId}.", flock.FlockId);
                }
            }
        }

        // PUT: api/Flock/{id}
        [HttpPut("{id:int}")]
        public async Task<ActionResult> Update(int id, [FromBody] FlockModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required in the flock model.");
            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required in the flock model.");

            var existingFlock = _flockService.GetFlockById(id, model.UserId, model.FarmId);
            if (existingFlock == null)
                return NotFound();

            var batch = await _batchService.GetById(model.BatchId, model.UserId, model.FarmId);
            if (batch == null)
            {
                return BadRequest($"Flock Batch with ID {model.BatchId} not found.");
            }

            // Calculate total quantity excluding the current flock's original quantity
            var totalQuantityExcludingCurrent = await _flockService.GetTotalFlockQuantityForBatch(model.BatchId, model.UserId, model.FarmId, id);
            
            if (totalQuantityExcludingCurrent + model.Quantity > batch.NumberOfBirds)
            {
                return BadRequest($"The total quantity of birds ({totalQuantityExcludingCurrent + model.Quantity}) exceeds the available birds in batch '{batch.BatchName}' ({batch.NumberOfBirds}).");
            }


            model.FlockId = id;
            await _flockService.UpdateFlock(model);
            return NoContent();
        }

        // DELETE: api/Flock/{id}?userId=xxx&farmId=yyy
        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            Console.WriteLine($"FlockController.Delete called for FlockId={id}, UserId={userId}, FarmId={farmId}");
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var existingFlock = _flockService.GetFlockById(id, userId, farmId);
            if (existingFlock == null)
                return NotFound();

            await _flockService.DeleteFlock(id, userId, farmId);
            return NoContent();
        }
    }
}
