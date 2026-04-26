namespace PoultryFarmAPIWeb.Models
{
    public class ChatThreadModel
    {
        public Guid ThreadId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string CreatedBy { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        public string OtherUserId { get; set; } = string.Empty; // convenience
        public string? OtherUserName { get; set; } // UserName from AspNetUsers
        public string? OtherUserFirstName { get; set; } // FirstName from AspNetUsers
        public string? OtherUserLastName { get; set; } // LastName from AspNetUsers
        public string? LastMessagePreview { get; set; }
        public DateTime? LastMessageAt { get; set; }
        public int UnreadCount { get; set; }
    }

    public class ChatMessageModel
    {
        public Guid MessageId { get; set; }
        public Guid ThreadId { get; set; }
        public string UserId { get; set; } = string.Empty;
        public string Content { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        public bool IsRead { get; set; }
    }
}


