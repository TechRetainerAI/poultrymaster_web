namespace PoultryFarmAPIWeb.Models
{
    public class AuditLogModel
    {
        public string Id { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string UserName { get; set; } = string.Empty;
        public string Action { get; set; } = string.Empty;
        public string Resource { get; set; } = string.Empty;
        public string? ResourceId { get; set; }
        public string? Details { get; set; }
        /// <summary>JSON snapshot of request body / action arguments (and response when available).</summary>
        public string? Data { get; set; }
        public string? IpAddress { get; set; }
        public string? UserAgent { get; set; }
        public DateTime Timestamp { get; set; }
        public string Status { get; set; } = "Success"; // Success | Failed
        public string FarmId { get; set; } = string.Empty;
    }
}


