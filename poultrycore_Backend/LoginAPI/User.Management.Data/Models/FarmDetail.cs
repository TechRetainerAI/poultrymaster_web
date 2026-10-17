using System.Collections.Generic;

namespace User.Management.Data.Models
{
    /// <summary>
    /// Platform-admin "Audit" view of one farm: the farm's own details, its owner
    /// account and the staff/employees under it. Returned by
    /// GET /api/System/farms/{farmId}/detail (SystemAdmin / PlatformOwner only).
    /// </summary>
    public class FarmDetail
    {
        public string FarmId { get; set; } = string.Empty;
        public string? FarmName { get; set; }
        public string? Type { get; set; }
        public string? Email { get; set; }          // farm contact email (dbo.Farms)
        public string? PhoneNumber { get; set; }

        /// <summary>The account that registered/owns the farm (IsStaff = false). May be null for legacy data.</summary>
        public FarmPerson? Owner { get; set; }

        /// <summary>Staff accounts belonging to the farm.</summary>
        public List<FarmPerson> Employees { get; set; } = new();
    }

    /// <summary>One person (owner or employee) attached to a farm, with the fields the admin audit panel shows.</summary>
    public class FarmPerson
    {
        public string UserId { get; set; } = string.Empty;
        public string? UserName { get; set; }
        public string? Email { get; set; }
        public string? FirstName { get; set; }
        public string? LastName { get; set; }
        public string Role { get; set; } = "Staff";   // "Owner" | "Staff"
        public bool TwoFactorEnabled { get; set; }
        public bool EmailConfirmed { get; set; }
    }
}
