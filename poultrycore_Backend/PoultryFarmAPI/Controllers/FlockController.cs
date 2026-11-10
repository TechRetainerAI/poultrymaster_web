using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
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
    [RequireCompanyType("Poultry")]
    public class FlockController : ControllerBase
    {
        private readonly IBirdFlockService _flockService;
        private readonly IMainFlockBatchService _batchService;
        private readonly IHouseService _houseService;
        private readonly IAuditLogService _auditLog;
        private readonly ILogger<FlockController> _logger;

        // IFarmSetupService is deliberately NOT a dependency any more. It was here
        // only to read opening positions so the batch total could be corrected in
        // C#; migration 325 moved that into the stored function every caller
        // already reads, which removed both the dependency and the chance of two
        // answers.
        private readonly IFarmSetupService _setupService;

        public FlockController(
            IBirdFlockService flockService,
            IMainFlockBatchService batchService,
            IHouseService houseService,
            IAuditLogService auditLog,
            ILogger<FlockController> logger,
            IFarmSetupService setupService)
        {
            _setupService = setupService;
            _flockService = flockService;
            _batchService = batchService;
            _houseService = houseService;
            _auditLog = auditLog;
            _logger = logger;
        }

        /// <summary>
        /// Birds a batch has actually given out.
        ///
        /// <para>
        /// A flock created by Initial Farm Setup carries its opening LIVE birds --
        /// 919 of the 1,000 that were placed (migration 319). Measured by quantity
        /// alone the batch looks like it still has 81 spare, which invites someone
        /// to allocate birds that died months ago. The opening historical reduction
        /// has to be added back so the batch is measured by what was PLACED, which
        /// is what its NumberOfBirds means.
        /// </para>
        ///
        /// <para>
        /// That addition used to happen here, in C#, and only here -- so this
        /// controller and the allocation guard inside
        /// <see cref="IBirdFlockService.AllocateBatchToFlocks"/> gave two different
        /// answers, and the one that decided whether the birds could be created was
        /// the wrong one. It now lives in spflock_getconsumedforbatch (migration
        /// 325), which every caller reads, so there is one answer. This wrapper is
        /// kept only because the name says what the number means.
        /// </para>
        /// </summary>
        private Task<int> ConsumedFromBatchAsync(int batchId, string userId, string farmId) =>
            _flockService.GetBirdsConsumedFromBatch(batchId, userId, farmId);

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

                var existingFlockQuantityInBatch = await _flockService.GetBirdsConsumedFromBatch(model.BatchId, model.UserId, model.FarmId);
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

        // POST: api/Flock/existing
        //
        // 413 / Issue 5: a flock that is ALREADY OPERATING. The farm says how many
        // birds were originally placed and how many are standing now; the
        // difference is explained (mortality / sold / culled / transferred, the
        // rest "other", never mortality). The batch is charged the placed birds
        // exactly once; the flock reads the current birds; one opening movement
        // names the batch and flock. Same OpeningFlockPoster as Initial Farm Setup.
        [HttpPost("existing")]
        public async Task<ActionResult> CreateExisting([FromBody] ExistingFlockRequest request)
        {
            if (request?.Flock is null || request.History is null)
                return BadRequest(new { message = "Flock and history are required." });
            var model = request.Flock;
            if (string.IsNullOrEmpty(model.UserId) || string.IsNullOrEmpty(model.FarmId))
                return BadRequest(new { message = "UserId and FarmId are required." });
            if (model.BatchId <= 0) return BadRequest(new { message = "Choose the batch." });
            if (string.IsNullOrWhiteSpace(model.Name)) return BadRequest(new { message = "Give the flock a name." });
            var problem = request.History.Validate();
            if (problem is not null) return BadRequest(new { message = problem });

            var batch = await _batchService.GetById(model.BatchId, model.UserId, model.FarmId);
            if (batch == null) return BadRequest(new { message = $"Flock Batch with ID {model.BatchId} not found." });

            var asOf = (request.AsOfDate ?? DateTime.UtcNow).Date;
            if (asOf > DateTime.UtcNow.Date.AddDays(1)) return BadRequest(new { message = "The as-of date is in the future." });
            if (model.StartDate.Date > asOf) return BadRequest(new { message = "The flock cannot start after the date its birds were counted." });

            try
            {
                model.Active = true;
                var id = await _flockService.CreateExistingFlock(model, request.History, asOf, batch.NumberOfBirds,
                    string.IsNullOrWhiteSpace(request.Source) ? "Flocks page" : request.Source!.Trim());
                var created = _flockService.GetFlockById(id, model.UserId, model.FarmId);
                return CreatedAtAction(nameof(Get), new { id, userId = model.UserId, farmId = model.FarmId }, created);
            }
            catch (FlockAllocationConflictException ex) { return Conflict(new { message = ex.Message }); }
            catch (ArgumentException ex) { return BadRequest(new { message = ex.Message }); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001" || ex.SqlState == "23514")
            {
                return BadRequest(new { message = ex.MessageText });
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
                FlockType = request.FlockType,   // 399: null -> database default
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

            // EVERY flock is editable, however it was created (Initial Farm Setup,
            // the Flocks page, an allocation). Numbers that look out of proportion
            // come back as WARNINGS; the save goes through.
            var warnings = new List<string>();

            // How the flock was registered, from posted records (414).
            System.Text.Json.JsonElement? opening = null;
            int productionRecords = 0;
            int quantityAdjustments = 0;
            var contextJson = await _flockService.GetFlockEditContext(id, model.FarmId);
            if (contextJson is not null && contextJson != "null")
            {
                using var ctxDoc = System.Text.Json.JsonDocument.Parse(contextJson);
                var root = ctxDoc.RootElement;
                if (root.TryGetProperty("opening", out var o) && o.ValueKind == System.Text.Json.JsonValueKind.Object)
                    opening = o.Clone();
                if (root.TryGetProperty("position", out var p) && p.ValueKind == System.Text.Json.JsonValueKind.Object
                    && p.TryGetProperty("productionrecordcount", out var prc) && prc.ValueKind == System.Text.Json.JsonValueKind.Number)
                    productionRecords = prc.GetInt32();
                if (root.TryGetProperty("quantityAdjustments", out var qa) && qa.ValueKind == System.Text.Json.JsonValueKind.Number)
                    quantityAdjustments = qa.GetInt32();
            }

            // A flock registered as already operating: its Number of Birds is the
            // count when it was registered, and its history (originally placed +
            // what happened to the difference) is restated together with it.
            OpeningFlockPositionCorrection? correction = null;
            if (opening is not null)
            {
                var o = opening.Value;
                int I(string n) => o.TryGetProperty(n, out var v) && v.ValueKind == System.Text.Json.JsonValueKind.Number ? v.GetInt32() : 0;
                bool B(string n) => o.TryGetProperty(n, out var v) && v.ValueKind == System.Text.Json.JsonValueKind.True;

                var h = model.OpeningHistory;
                // Number of Birds on the form = alive when registered + any later
                // adjustments that moved flock.quantity directly (413).
                var live = h?.OpeningLiveBirds ?? (model.Quantity - quantityAdjustments);
                var placed = h?.OriginallyPlaced ?? I("originallyPlaced");
                var known = h?.HistoryKnown ?? B("historyKnown");
                var mort = h?.HistoricalMortality ?? I("historicalMortality");
                var sold = h?.HistoricalSold ?? I("historicalSold");
                var cull = h?.HistoricalCulled ?? I("historicalCulled");
                var moved = h?.HistoricalTransferred ?? I("historicalTransferred");

                if (live < 0) live = 0;
                if (placed < live)
                {
                    warnings.Add($"{live:N0} birds alive is more than the {placed:N0} originally placed, so originally placed was raised to {live:N0}.");
                    placed = live;
                }
                var difference = placed - live;
                if (known && mort + sold + cull + moved > difference)
                {
                    warnings.Add($"What happened to the missing birds adds up to {mort + sold + cull + moved:N0}, but only {difference:N0} are missing " +
                                 $"({placed:N0} placed − {live:N0} alive). The breakdown was not saved — the {difference:N0} are recorded as not yet explained. " +
                                 "Open the flock again to split them.");
                    known = false;
                }

                var changed = placed != I("originallyPlaced") || live != I("openingLiveBirds") || known != B("historyKnown")
                              || mort != I("historicalMortality") || sold != I("historicalSold")
                              || cull != I("historicalCulled") || moved != I("historicalTransferred");
                if (changed)
                {
                    if (productionRecords > 0 && (placed != I("originallyPlaced") || live != I("openingLiveBirds")))
                        warnings.Add($"This flock already has {productionRecords:N0} production record(s). Its birds-left figures come from those records, " +
                                     "so check the latest record still matches.");
                    correction = new OpeningFlockPositionCorrection
                    {
                        UserId = model.UserId,
                        FarmId = model.FarmId,
                        FlockId = id,
                        OriginallyPlaced = placed,
                        OpeningLiveBirds = live,
                        HistoryKnown = known,
                        HistoricalMortality = known ? mort : 0,
                        HistoricalSold = known ? sold : 0,
                        HistoricalCulled = known ? cull : 0,
                        HistoricalTransferred = known ? moved : 0,
                        Notes = model.OpeningHistory?.Notes,
                    };
                }
                // flock.quantity is restated by the correction itself.
                model.Quantity = live + quantityAdjustments;
            }

            var batch = await _batchService.GetById(model.BatchId, model.UserId, model.FarmId);
            if (batch == null)
            {
                return BadRequest($"Flock Batch with ID {model.BatchId} not found.");
            }

            // Batch capacity is measured on what was PLACED. Over it is a warning:
            // the batch's own number may be the one that is out of date.
            var placedNow = correction?.OriginallyPlaced
                            ?? (opening is not null && opening.Value.TryGetProperty("originallyPlaced", out var op) && op.ValueKind == System.Text.Json.JsonValueKind.Number
                                ? op.GetInt32() : model.Quantity);
            var totalQuantityExcludingCurrent = await _flockService.GetBirdsConsumedFromBatch(model.BatchId, model.UserId, model.FarmId, id);
            if (totalQuantityExcludingCurrent + placedNow > batch.NumberOfBirds)
            {
                warnings.Add($"Batch '{batch.BatchName}' had {batch.NumberOfBirds:N0} birds, but its flocks (and anything already recorded against it) now account for " +
                             $"{totalQuantityExcludingCurrent + placedNow:N0}. Check the flock numbers or update the batch.");
            }
            if (model.BatchId != existingFlock.BatchId)
                warnings.Add($"The flock now belongs to batch '{batch.BatchName}' and its birds now count against that batch. Movements already posted keep the batch they were posted under.");

            try { model.FlockType = BirdFlockService.NormalizeFlockType(model.FlockType); }
            catch (ArgumentException ex) { return BadRequest(ex.Message); }

            model.FlockId = id;
            await _flockService.UpdateFlock(model);

            // After the plain update, so the correction's own flock rewrite keeps
            // the new name / house / batch. Posts only the ledger difference.
            if (correction is not null)
            {
                var ok = await _setupService.CorrectOpeningPositionAsync(correction);
                if (!ok) warnings.Add("The flock's history could not be found to update; the other changes were saved.");
            }

            return Ok(new { message = "Flock updated.", warnings });
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

            try
            {
                var result = await _flockService.DeleteFlock(id, userId, farmId);
                // Never "deleted" unless the database says it was.
                return result is null ? NoContent() : Content(result, "application/json");
            }
            catch (FlockDeleteBlockedException ex)
            {
                return Conflict(new { message = ex.Message });
            }
        }

        // GET: api/Flock/{id}/edit-context?farmId=...
        // 414: Edit Flock restores the flock from posted records -- mode, opening
        // position, bird position, movement history and what may still change.
        [HttpGet("{id:int}/edit-context")]
        public async Task<IActionResult> GetEditContext(int id, [FromQuery] string? userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");
            var json = await _flockService.GetFlockEditContext(id, farmId);
            if (json is null || json == "null") return NotFound(new { message = "That flock is not available on this farm." });
            return Content(json, "application/json");
        }
    }
}
