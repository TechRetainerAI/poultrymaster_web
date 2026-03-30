using System;

namespace User.Management.Data.Models
{
    public class FarmSummary
    {
        public string FarmId { get; set; } = string.Empty;
        public string? FarmName { get; set; }
        public int TotalUsers { get; set; }
        public int StaffCount { get; set; }
    }
}


