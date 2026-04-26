using Microsoft.AspNetCore.SignalR;
using PoultryFarmAPIWeb.Business;

namespace PoultryFarmAPIWeb.Hubs
{
    public class ChatHub : Hub
    {
        private readonly IChatService _service;
        public ChatHub(IChatService service)
        {
            _service = service;
        }

        public async Task JoinThread(string threadId)
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, $"thread:{threadId}");
        }

        public async Task LeaveThread(string threadId)
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"thread:{threadId}");
        }

        public async Task SendMessage(string threadId, string userId, string content)
        {
            // NOTE: This method is kept for backward compatibility but should not be used.
            // Messages should be sent via REST API (/api/Chat/threads/{threadId}/messages) 
            // which handles saving and broadcasting. This method only broadcasts.
            // If a client accidentally calls this, we'll just broadcast without saving to prevent duplicates.
            var msg = await _service.SendMessageAsync(Guid.Parse(threadId), userId, content);
            await Clients.Group($"thread:{threadId}").SendAsync("message", new
            {
                messageId = msg.MessageId,
                threadId = msg.ThreadId,
                userId = msg.UserId,
                content = msg.Content,
                createdAt = msg.CreatedAt,
                isRead = msg.IsRead
            });
        }

        public async Task Typing(string threadId, string userId)
        {
            await Clients.Group($"thread:{threadId}").SendAsync("typing", new { threadId, userId });
        }

        public async Task MarkRead(string threadId, string userId)
        {
            await _service.MarkReadAsync(Guid.Parse(threadId), userId);
            await Clients.Group($"thread:{threadId}").SendAsync("read", new { threadId, userId });
        }
    }
}


