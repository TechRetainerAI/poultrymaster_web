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

        /// <summary>Owner (registrant) first name — the non-staff account on the farm. Null if no owner row.</summary>
        public string? OwnerFirstName { get; set; }

        /// <summary>Owner (registrant) last name. Null if no owner row.</summary>
        public string? OwnerLastName { get; set; }

        /// <summary>Company / farm type (Poultry, Water, Generic, Hotel, …) from the farms row.</summary>
        public string? CompanyType { get; set; }

        /// <summary>Country the company operates in — the owner account's BusinessOfficeCountry.</summary>
        public string? Country { get; set; }

        public int TotalUsers { get; set; }
        public int StaffCount { get; set; }

        /// <summary>True when at least one user on the farm has IsSubscriber (paid / active subscription flag on account).</summary>
        public bool HasPaidSubscription { get; set; }
    }
}


