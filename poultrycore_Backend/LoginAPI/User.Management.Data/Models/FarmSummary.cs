using System;

namespace User.Management.Data.Models
{
    public class FarmSummary
    {
        public string FarmId { get; set; } = string.Empty;
        public string? FarmName { get; set; }

        /// <summary>Owner / company contact email (from the farms row).</summary>
        public string? Email { get; set; }

        /// <summary>Owner / company contact phone (from the farms row).</summary>
        public string? PhoneNumber { get; set; }

        /// <summary>When the company/farm was created (signup date), from the farms row. Null if unknown.</summary>
        public DateTime? CreatedAt { get; set; }

        public int TotalUsers { get; set; }
        public int StaffCount { get; set; }

        /// <summary>True when at least one user on the farm has IsSubscriber (paid / active subscription flag on account).</summary>
        public bool HasPaidSubscription { get; set; }
    }
}


