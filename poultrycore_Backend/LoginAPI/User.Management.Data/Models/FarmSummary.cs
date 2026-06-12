using System;

namespace User.Management.Data.Models
{
    public class FarmSummary
    {
        public string FarmId { get; set; } = string.Empty;
        public string? FarmName { get; set; }
        public int TotalUsers { get; set; }
        public int StaffCount { get; set; }

        /// <summary>True when at least one user on the farm has IsSubscriber (paid / active subscription flag on account).</summary>
        public bool HasPaidSubscription { get; set; }
    }
}


