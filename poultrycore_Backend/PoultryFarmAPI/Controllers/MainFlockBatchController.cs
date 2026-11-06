using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    // Handles all API requests for the MainFlockBatch entity.
    [RequireCompanyType("Poultry")]
    public class MainFlockBatchController : ControllerBase
    {
        private readonly IMainFlockBatchService _batchService;
        private readonly IAuditLogService _auditLog;
        private readonly ILogger<MainFlockBatchController> _logger;

        public MainFlockBatchController(IMainFlockBatchService batchService, IAuditLogService auditLog, ILogger<MainFlockBatchController> logger)
        {
            _batchService = batchService;
            _auditLog = auditLog;
            _logger = logger;
        }

        // POST: api/MainFlockBatch/bulk
        // "Add Multiple Batches": the bulk counterpart of Create, like House/bulk.
        // Every row is validated first (FlockBatchBulkValidator); then all are
        // inserted in one transaction through the same spmainflockbatch_insert,
        // so either every batch exists afterwards or none does. Permission is the
        // same as Create: IamPermissionMap resolves mainflockbatch + POST.
        [HttpPost("bulk")]
        public async Task<ActionResult<BulkFlockBatchCreateResult>> CreateBulk([FromBody] BulkFlockBatchCreateRequest request)
        {
            if (request == null) return BadRequest("A request body is required.");
            if (string.IsNullOrEmpty(request.UserId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(request.FarmId)) return BadRequest("FarmId is required.");

            var existing = await _batchService.GetAll(request.UserId, request.FarmId);
            var errors = FlockBatchBulkValidator.Validate(request.Batches, existing.Select(b => b.BatchCode));
            if (errors.Count > 0)
            {
                return BadRequest(new BulkFlockBatchCreateResult
                {
                    Success = false,
                    Errors = errors,
                    Message = errors.Count == 1
                        ? errors[0].Message
                        : $"{errors.Count} rows need attention before these batches can be created.",
                });
            }

            var models = FlockBatchBulkValidator.ToModels(request.UserId, request.FarmId, request.Batches);
            List<int> ids;
            try
            {
                ids = await _batchService.InsertBulk(models);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Bulk batch creation failed for farm {FarmId}; {Count} batches rolled back.", request.FarmId, models.Count);
                var detail = ex is Npgsql.PostgresException pg ? pg.MessageText : ex.Message;
                return StatusCode(500, new BulkFlockBatchCreateResult
                {
                    Success = false,
                    Message = "None of the batches were created. " + detail,
                });
            }

            var idSet = new HashSet<int>(ids);
            var created = (await _batchService.GetAll(request.UserId, request.FarmId))
                .Where(b => idSet.Contains(b.BatchId)).ToList();
            await WriteBulkAuditAsync(request, created);

            return Ok(new BulkFlockBatchCreateResult
            {
                Success = true,
                CreatedCount = ids.Count,
                Batches = created,
                Message = ids.Count == 1 ? "1 batch created successfully." : $"{ids.Count} batches created successfully.",
            });
        }

        // One audit row per batch on top of the request-level row the global
        // AuditLogActionFilter writes, so each batch is traceable on its own.
        private async Task WriteBulkAuditAsync(BulkFlockBatchCreateRequest request, List<MainFlockBatchModel> created)
        {
            var source = string.IsNullOrWhiteSpace(request.Source) ? "Bulk Batch Creation" : request.Source!.Trim();
            var userName = User?.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value
                           ?? User?.Identity?.Name
                           ?? Request.Headers["X-Username"].FirstOrDefault()
                           ?? request.UserId;
            foreach (var b in created)
            {
                try
                {
                    await _auditLog.InsertAsync(new AuditLogModel
                    {
                        UserId = request.UserId,
                        UserName = userName,
                        FarmId = request.FarmId,
                        Action = "POST",
                        Resource = "MainFlockBatch",
                        ResourceId = b.BatchId.ToString(),
                        Details = $"POST MainFlockBatch (ID: {b.BatchId}) - Created via {source}",
                        Data = System.Text.Json.JsonSerializer.Serialize(new
                        {
                            source, batchSize = created.Count, b.BatchId, b.BatchName, b.BatchCode,
                            b.NumberOfBirds, b.TotalCost, b.AmountPaid,
                        }),
                        IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString(),
                        UserAgent = Request.Headers["User-Agent"].FirstOrDefault(),
                        Timestamp = DateTime.UtcNow,
                        Status = "Success",
                    });
                }
                catch (Exception ex)
                {
                    // The batches are committed; a lost audit row must not turn success into an error.
                    _logger.LogError(ex, "Could not write bulk audit row for batch {BatchId}.", b.BatchId);
                }
            }
        }

        // GET: api/MainFlockBatch?userId=xxx&farmId=xxx
        // Retrieves all batches for a specific farm/user.
        [HttpGet]
        public async Task<ActionResult<IEnumerable<MainFlockBatchModel>>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");

            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var allBatches = await _batchService.GetAll(userId, farmId);
            return Ok(allBatches);
        }

        // GET: api/MainFlockBatch/5?userId=xxx&farmId=xxx
        // Retrieves a single batch by ID.
        [HttpGet("{id}")]
        public async Task<ActionResult<MainFlockBatchModel>> GetById(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");

            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var batch = await _batchService.GetById(id, userId, farmId);
            if (batch == null) return NotFound();
            return Ok(batch);
        }

        // POST: api/MainFlockBatch
        // Creates a new batch record.
        [HttpPost]
        public async Task<ActionResult<MainFlockBatchModel>> Create([FromBody] MainFlockBatchModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required in the model.");

            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required in the model.");

            var newId = await _batchService.Insert(model);
            // Retrieve the full created record to return in the 201 Created response.
            var createdRecord = await _batchService.GetById(newId, model.UserId, model.FarmId);
            return CreatedAtAction(nameof(GetById), new { id = newId, userId = model.UserId, farmId = model.FarmId }, createdRecord);
        }

        // PUT: api/MainFlockBatch/5
        // Updates an existing batch record.
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] MainFlockBatchModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required in the model.");

            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required in the model.");

            var existing = await _batchService.GetById(id, model.UserId, model.FarmId);
            if (existing == null) return NotFound();

            model.BatchId = id;
            await _batchService.Update(model);
            return NoContent(); // 204 No Content success response.
        }

        // DELETE: api/MainFlockBatch/5?userId=xxx&farmId=xxx
        // Deletes a batch record.
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");

            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var existing = await _batchService.GetById(id, userId, farmId);
            if (existing == null) return NotFound();

            await _batchService.Delete(id, userId, farmId);
            return NoContent(); // 204 No Content success response.
        }

        // POST: api/MainFlockBatch/5/pay-balance
        // Records a follow-up payment toward the batch's outstanding balance.
        [HttpPost("{id:int}/pay-balance")]
        public async Task<IActionResult> PayBalance(int id, [FromBody] FlockBatchPayBalanceRequest body)
        {
            if (body is null || string.IsNullOrWhiteSpace(body.FarmId))
                return BadRequest("FarmId is required.");
            if (body.Amount <= 0)
                return BadRequest("Payment amount must be greater than 0.");

            var balance = await _batchService.PayBalance(id, body.FarmId, body.Amount, body.PaymentMethod, body.PaymentDate, body.CreatedBy);
            return Ok(new { Balance = balance });
        }
    }

    // Body for POST api/MainFlockBatch/{id}/pay-balance.
    public class FlockBatchPayBalanceRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public string? PaymentMethod { get; set; }
        public DateTime? PaymentDate { get; set; }
        public string? CreatedBy { get; set; }
    }
}
