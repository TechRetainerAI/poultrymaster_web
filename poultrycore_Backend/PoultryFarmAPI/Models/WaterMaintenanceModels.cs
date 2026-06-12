using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public static class WaterMaintenanceAssetTypes
    {
        public const string Machine   = "Machine";
        public const string Vehicle   = "Vehicle";
        public const string Borehole  = "Borehole";
        public const string Generator = "Generator";
        public const string Other     = "Other";
    }

    public static class WaterMaintenanceStatus
    {
        public const string Open       = "Open";
        public const string InProgress = "InProgress";
        public const string Completed  = "Completed";
        public const string Cancelled  = "Cancelled";
    }

    public class WaterMaintenanceLogModel
    {
        [Key] public int WaterMaintenanceLogId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;

        [Required, StringLength(20)] public string AssetType { get; set; } = WaterMaintenanceAssetTypes.Machine;
        public int? AssetId { get; set; }
        [StringLength(200)] public string? AssetLabel { get; set; }

        public DateTime IssueDate { get; set; }

        [Required, StringLength(1000)] public string IssueDescription { get; set; } = string.Empty;

        public int? ReportedByWaterStaffId { get; set; }
        [StringLength(150)] public string? TechnicianName { get; set; }

        [Range(0, double.MaxValue)] public decimal RepairCost { get; set; }
        [StringLength(1000)] public string? PartsReplaced { get; set; }
        public decimal? DowntimeHours { get; set; }

        [StringLength(20)] public string Status { get; set; } = WaterMaintenanceStatus.Open;
        public DateTime? CompletedDate { get; set; }

        public int? WaterCashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public bool CashTransactionWritten { get; set; }

        [StringLength(1000)] public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class WaterMaintenanceLogCompleteRequest
    {
        public DateTime? CompletedDate { get; set; }
        public int? WaterCashAccountId { get; set; }
    }

    public class WaterMaintenanceLogAlertModel
    {
        public string AssetType { get; set; } = string.Empty;
        public int AssetId { get; set; }
        public string AssetLabel { get; set; } = string.Empty;
        public DateTime NextDueDate { get; set; }
        public int DaysUntilDue { get; set; }
        public string Severity { get; set; } = string.Empty; // Overdue | DueSoon | Upcoming
    }
}
