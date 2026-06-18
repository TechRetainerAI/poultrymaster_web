using System;

namespace User.Management.Data.Models
{
    public class Subscriber
    {
        public int Id { get; set; }
        public string SubscriberId { get; set; } = string.Empty;
        public string CustomerId { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public DateTime CurrentPeriodStart { get; set; }
        public DateTime CurrentPeriodEnd { get; set; }
        public string Status { get; set; } = string.Empty;
        public DateTime? CanceledAt { get; set; }
        public DateTime Created { get; set; }
        public DateTime? EndedAt { get; set; }
        public string LatestInvoiceId { get; set; } = string.Empty;
        public DateTime StartDate { get; set; }
        public DateTime? TrialEnd { get; set; }
        public DateTime? TrialStart { get; set; }
        public string PlanId { get; set; } = string.Empty;
        public string PlanName { get; set; } = string.Empty;
        public decimal PlanAmount { get; set; }
    }
}