using System;

namespace User.Management.Data.Models
{
    public class Subscriber
    {
        public int Id { get; set; }
        public string SubscriberId { get; set; }
        public string CustomerId { get; set; }
        public string Email { get; set; }
        public DateTime CurrentPeriodStart { get; set; }
        public DateTime CurrentPeriodEnd { get; set; }
        public string Status { get; set; }
        public DateTime? CanceledAt { get; set; }
        public DateTime Created { get; set; }
        public DateTime? EndedAt { get; set; }
        public string LatestInvoiceId { get; set; }
        public DateTime StartDate { get; set; }
        public DateTime? TrialEnd { get; set; }
        public DateTime? TrialStart { get; set; }
        public string PlanId { get; set; }
        public string PlanName { get; set; }
        public decimal PlanAmount { get; set; }
    }
}