using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class HealthController : ControllerBase
    {
        private const int MaxAttachmentBytes = 4 * 1024 * 1024;

        private static readonly HashSet<string> AllowedAttachmentContentTypes = new(StringComparer.OrdinalIgnoreCase)
        {
            "image/jpeg", "image/png", "image/webp"
        };

        private readonly IHealthRecordService _healthService;

        public HealthController(IHealthRecordService healthService)
        {
            _healthService = healthService;
        }

        // GET: api/Health?userId=xxx&farmId=yyy&flockId=1&houseId=2&itemId=3
        [HttpGet]
        public async Task<ActionResult<IEnumerable<HealthRecordModel>>> GetAll(
            [FromQuery] string userId,
            [FromQuery] string farmId,
            [FromQuery] int? flockId = null,
            [FromQuery] int? houseId = null,
            [FromQuery] int? itemId = null)
        {
            if (string.IsNullOrWhiteSpace(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrWhiteSpace(farmId))
                return BadRequest("FarmId is required.");

            var records = await _healthService.GetAll(userId, farmId, flockId, houseId, itemId);
            return Ok(records);
        }

        /// <summary>Binary image for a health row (Bearer auth). List endpoints omit bytes; use this URL for &lt;img&gt; after same-origin proxy.</summary>
        [HttpGet("{id:int}/attachment")]
        public async Task<IActionResult> GetAttachment(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrWhiteSpace(farmId))
                return BadRequest("FarmId is required.");

            var blob = await _healthService.GetAttachment(id, userId, farmId);
            if (blob == null)
                return NotFound();

            return File(blob.Value.Body, blob.Value.ContentType);
        }

        // GET: api/Health/5?userId=xxx&farmId=yyy
        [HttpGet("{id:int}")]
        public async Task<ActionResult<HealthRecordModel>> GetById(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrWhiteSpace(farmId))
                return BadRequest("FarmId is required.");

            var record = await _healthService.GetById(id, userId, farmId);
            if (record == null)
                return NotFound();

            return Ok(record);
        }

        // POST: api/Health
        [HttpPost]
        public async Task<ActionResult<HealthRecordModel>> Create([FromBody] HealthRecordModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrWhiteSpace(model.UserId))
                return BadRequest("UserId is required in the model.");
            if (string.IsNullOrWhiteSpace(model.FarmId))
                return BadRequest("FarmId is required in the model.");

            var attErr = ValidateOptionalAttachment(model.AttachmentImage, model.AttachmentContentType);
            if (attErr != null)
                return BadRequest(attErr);

            var newId = await _healthService.Insert(model);
            var created = await _healthService.GetById(newId, model.UserId, model.FarmId!);
            return CreatedAtAction(nameof(GetById), new { id = newId, userId = model.UserId, farmId = model.FarmId }, created);
        }

        // PUT: api/Health/5
        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] HealthRecordModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrWhiteSpace(model.UserId))
                return BadRequest("UserId is required in the model.");
            if (string.IsNullOrWhiteSpace(model.FarmId))
                return BadRequest("FarmId is required in the model.");

            if (model.SetAttachmentImage)
            {
                var attErr = ValidateAttachmentForUpdate(model);
                if (attErr != null)
                    return BadRequest(attErr);
            }

            var existing = await _healthService.GetById(id, model.UserId, model.FarmId!);
            if (existing == null)
                return NotFound();

            model.Id = id;
            await _healthService.Update(model);
            return NoContent();
        }

        // DELETE: api/Health/5?userId=xxx&farmId=yyy
        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrWhiteSpace(farmId))
                return BadRequest("FarmId is required.");

            var existing = await _healthService.GetById(id, userId, farmId);
            if (existing == null)
                return NotFound();

            await _healthService.Delete(id, userId, farmId);
            return NoContent();
        }

        private static string? ValidateOptionalAttachment(byte[]? image, string? contentType)
        {
            if (image == null || image.Length == 0)
                return null;
            if (image.Length > MaxAttachmentBytes)
                return "Attachment too large (max 4 MB).";
            if (string.IsNullOrWhiteSpace(contentType) || !AllowedAttachmentContentTypes.Contains(contentType.Trim()))
                return "Attachment content type must be image/jpeg, image/png, or image/webp.";
            return null;
        }

        /// <summary>When <see cref="HealthRecordModel.SetAttachmentImage"/> is true and bytes are present, validate; clearing (null bytes) is allowed.</summary>
        private static string? ValidateAttachmentForUpdate(HealthRecordModel model)
        {
            if (model.AttachmentImage == null || model.AttachmentImage.Length == 0)
                return null;
            return ValidateOptionalAttachment(model.AttachmentImage, model.AttachmentContentType);
        }
    }
}
