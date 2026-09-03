using System.ComponentModel.DataAnnotations;
namespace PoultryFarmAPIWeb.Models
{
    public class RestaurantCustomerModel
    {
        [Key] public int CustomerId { get; set; }
        [Required] public string FarmId { get; set; } = "";
        [Required] public string Name { get; set; } = "";
        public string? Phone { get; set; } public string? Email { get; set; }
        public DateTime? DateOfBirth { get; set; } public DateTime? Anniversary { get; set; }
        public string? DietaryPreferences { get; set; } public string? Allergies { get; set; }
        public string? FavouriteItems { get; set; } public string Segment { get; set; } = "New";
        public int TotalVisits { get; set; } public decimal TotalSpent { get; set; }
        public decimal AvgTicket { get; set; } public DateTime? LastVisit { get; set; }
        public string? Notes { get; set; } public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; } public DateTime? UpdatedAt { get; set; }
    }
    public class RestaurantFeedbackModel
    {
        [Key] public int FeedbackId { get; set; }
        [Required] public string FarmId { get; set; } = "";
        public int? CustomerId { get; set; } public string? CustomerName { get; set; }
        public int? OrderId { get; set; } public int Rating { get; set; }
        public int? FoodRating { get; set; } public int? ServiceRating { get; set; }
        public int? AmbienceRating { get; set; } public string? Comment { get; set; }
        public string Source { get; set; } = "InStore"; public string Status { get; set; } = "New";
        public string? Response { get; set; } public string? RespondedBy { get; set; }
        public DateTime CreatedAt { get; set; } public DateTime? UpdatedAt { get; set; }
    }
    public class RestaurantCampaignModel
    {
        [Key] public int CampaignId { get; set; }
        [Required] public string FarmId { get; set; } = "";
        [Required] public string Name { get; set; } = "";
        public string CampaignType { get; set; } = ""; public string? TargetSegment { get; set; }
        public string? Subject { get; set; } public string? Message { get; set; }
        public string Channel { get; set; } = "SMS"; public string Status { get; set; } = "Draft";
        public DateTime? ScheduledAt { get; set; } public DateTime? SentAt { get; set; }
        public int RecipientCount { get; set; } public int OpenCount { get; set; }
        public DateTime CreatedAt { get; set; }
    }
    public class CustomerStatsModel { public long TotalCustomers { get; set; } public long NewCount { get; set; } public long RegularCount { get; set; } public long VipCount { get; set; } public long LapsedCount { get; set; } public decimal TotalLifetimeValue { get; set; } }
    public class FeedbackStatsModel { public long TotalFeedback { get; set; } public double? AvgRating { get; set; } public double? AvgFood { get; set; } public double? AvgService { get; set; } public double? AvgAmbience { get; set; } public long NewCount { get; set; } }
}
