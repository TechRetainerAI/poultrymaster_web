using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IChatService
    {
        Task<ChatThreadModel> CreateOrGetThreadAsync(string farmId, string userId, string otherUserId);
        Task<List<ChatThreadModel>> GetThreadsAsync(string userId, string farmId);
        Task<List<ChatMessageModel>> GetMessagesAsync(Guid threadId, int take = 50, DateTime? before = null);
        Task<ChatMessageModel> SendMessageAsync(Guid threadId, string userId, string content);
        Task MarkReadAsync(Guid threadId, string userId);
        Task<bool> IsParticipantAsync(Guid threadId, string userId);
    }
}


