using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using PoultryFarmAPIWeb.Hubs;
using System.Security.Claims;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ChatController : ControllerBase
    {
        private readonly IChatService _service;
        private readonly IHubContext<ChatHub> _hubContext;
        public ChatController(IChatService service, IHubContext<ChatHub> hubContext)
        {
            _service = service;
            _hubContext = hubContext;
        }

        [HttpPost("threads")]
        [Authorize]
        public async Task<ActionResult<ChatThreadModel>> CreateOrGetThread([FromBody] CreateThreadRequest req)
        {
            if (req == null || string.IsNullOrEmpty(req.FarmId) || string.IsNullOrEmpty(req.UserId) || string.IsNullOrEmpty(req.OtherUserId))
                return BadRequest("FarmId, UserId and OtherUserId are required.");

            // Enforce FarmId based on caller claims
            var claimFarmId = User.FindFirst("FarmId")?.Value;
            if (string.IsNullOrEmpty(claimFarmId) || !string.Equals(claimFarmId, req.FarmId, StringComparison.OrdinalIgnoreCase))
            {
                return Forbid();
            }

            // Enforce that caller is creating a thread for self
            var callerUserId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (!string.IsNullOrEmpty(callerUserId) && !string.Equals(callerUserId, req.UserId, StringComparison.OrdinalIgnoreCase))
            {
                return Forbid();
            }

            var thread = await _service.CreateOrGetThreadAsync(req.FarmId, req.UserId, req.OtherUserId);
            return Ok(thread);
        }

        [HttpGet("threads")]
        [Authorize]
        public async Task<ActionResult<List<ChatThreadModel>>> GetThreads([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId)) return BadRequest("userId and farmId required");

            var claimFarmId = User.FindFirst("FarmId")?.Value;
            var callerUserId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(claimFarmId) || !string.Equals(claimFarmId, farmId, StringComparison.OrdinalIgnoreCase))
            {
                return Forbid();
            }
            if (!string.IsNullOrEmpty(callerUserId) && !string.Equals(callerUserId, userId, StringComparison.OrdinalIgnoreCase))
            {
                return Forbid();
            }
            var list = await _service.GetThreadsAsync(userId, farmId);
            return Ok(list);
        }

        [HttpGet("threads/{threadId}/messages")]
        [Authorize]
        public async Task<ActionResult<List<ChatMessageModel>>> GetMessages(Guid threadId, [FromQuery] int take = 50, [FromQuery] DateTime? before = null)
        {
            // Enforce participant access
            var callerUserId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(callerUserId) || !await _service.IsParticipantAsync(threadId, callerUserId))
            {
                return Forbid();
            }
            var list = await _service.GetMessagesAsync(threadId, take, before);
            return Ok(list);
        }

        [HttpPost("threads/{threadId}/messages")]
        [Authorize]
        public async Task<ActionResult<ChatMessageModel>> SendMessage(Guid threadId, [FromBody] SendMessageRequest req)
        {
            if (req == null || string.IsNullOrEmpty(req.UserId) || string.IsNullOrWhiteSpace(req.Content)) 
                return BadRequest("userId and content required");
            
            // Get the caller's userId from claims as a fallback
            var callerUserId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            
            // Determine which userId to use - prefer the one from request, but verify caller has access
            var userIdToUse = req.UserId;
            
            // If caller's userId is available and doesn't match request, use caller's userId
            // This handles cases where the frontend sends a different userId format
            if (!string.IsNullOrEmpty(callerUserId))
            {
                // Check if caller is a participant (using caller's userId from claims)
                var isCallerParticipant = await _service.IsParticipantAsync(threadId, callerUserId);
                
                // Also check if the requested userId is a participant
                var isRequestedUserParticipant = await _service.IsParticipantAsync(threadId, req.UserId);
                
                // If caller is a participant but requested user is not, use caller's userId
                if (isCallerParticipant && !isRequestedUserParticipant)
                {
                    userIdToUse = callerUserId;
                }
                // If neither is a participant, deny access
                else if (!isCallerParticipant && !isRequestedUserParticipant)
                {
                    return Forbid("You are not a participant in this thread.");
                }
                // If both are participants, prefer the requested userId (but verify caller matches)
                else if (isRequestedUserParticipant)
                {
                    // Allow if caller matches requested user (case-insensitive) or if caller is also a participant
                    if (!string.Equals(callerUserId, req.UserId, StringComparison.OrdinalIgnoreCase) && !isCallerParticipant)
                    {
                        return Forbid("You can only send messages as yourself.");
                    }
                    userIdToUse = req.UserId;
                }
            }
            else
            {
                // No caller userId in claims - just check if requested userId is a participant
                if (!await _service.IsParticipantAsync(threadId, req.UserId))
                {
                    return Forbid("You are not a participant in this thread.");
                }
            }
            
            var msg = await _service.SendMessageAsync(threadId, userIdToUse, req.Content);
            
            // Broadcast message via SignalR after saving
            await _hubContext.Clients.Group($"thread:{threadId}").SendAsync("message", new
            {
                messageId = msg.MessageId,
                threadId = msg.ThreadId,
                userId = msg.UserId,
                content = msg.Content,
                createdAt = msg.CreatedAt,
                isRead = msg.IsRead
            });
            
            return Ok(msg);
        }

        [HttpPost("threads/{threadId}/read")]
        [Authorize]
        public async Task<IActionResult> MarkRead(Guid threadId, [FromBody] MarkReadRequest req)
        {
            if (req == null || string.IsNullOrEmpty(req.UserId)) return BadRequest("userId required");
            if (!await _service.IsParticipantAsync(threadId, req.UserId)) return Forbid();
            await _service.MarkReadAsync(threadId, req.UserId);
            return NoContent();
        }

        public class CreateThreadRequest { public string FarmId { get; set; } = string.Empty; public string UserId { get; set; } = string.Empty; public string OtherUserId { get; set; } = string.Empty; }
        public class SendMessageRequest { public string UserId { get; set; } = string.Empty; public string Content { get; set; } = string.Empty; }
        public class MarkReadRequest { public string UserId { get; set; } = string.Empty; }
    }
}


