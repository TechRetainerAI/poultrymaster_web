using System.Text.Json;

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>Migration 527: what the Sales page needs to know about approval for the caller.</summary>
    public class PoultrySaleApprovalInfo
    {
        /// <summary>The company's switch ("Sales by staff need approval").</summary>
        public bool NeedApproval { get; set; }
        /// <summary>The switch is on AND per-company page access is live, so it actually applies.</summary>
        public bool Active { get; set; }
        /// <summary>Owner, or holds poultry.sales.approve.</summary>
        public bool IsApprover { get; set; }
        public bool IsOwner { get; set; }
        /// <summary>A sale this person records will wait for approval.</summary>
        public bool MySalesWait { get; set; }
        public int WaitingCount { get; set; }
    }

    public class PoultryPendingSaleRow
    {
        public int PendingSaleId { get; set; }
        /// <summary>"single" (POST api/Sale body) or "group" (POST api/Sale/group body).</summary>
        public string Kind { get; set; } = "single";
        /// <summary>The request exactly as it will be posted.</summary>
        public JsonElement Payload { get; set; }
        public DateTime? SaleDate { get; set; }
        public string? CustomerName { get; set; }
        public string? Summary { get; set; }
        public decimal TotalAmount { get; set; }
        public int LineCount { get; set; }
        /// <summary>Waiting, Approving, Approved, Rejected, Withdrawn.</summary>
        public string Status { get; set; } = "Waiting";
        public string SubmittedBy { get; set; } = string.Empty;
        public string? SubmittedByName { get; set; }
        public DateTime SubmittedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? DecidedBy { get; set; }
        public string? DecidedByName { get; set; }
        public DateTime? DecidedAt { get; set; }
        public string? RejectionReason { get; set; }
        /// <summary>Why the last approval attempt did not post (e.g. not enough eggs).</summary>
        public string? LastError { get; set; }
        public int? PostedSaleId { get; set; }
        public string? PostedSaleLabel { get; set; }
    }

    public class PoultryPendingSaleApproved
    {
        public int PendingSaleId { get; set; }
        public int SaleId { get; set; }
        public string SaleLabel { get; set; } = string.Empty;
    }

    public class PoultryPendingSaleDecision
    {
        public string FarmId { get; set; } = string.Empty;
        public string? Reason { get; set; }
    }

    public class PoultrySaleApprovalSetting
    {
        public string FarmId { get; set; } = string.Empty;
        public bool NeedApproval { get; set; }
    }

    /// <summary>Returned (202) instead of a sale when the sale waits for approval.</summary>
    public class PoultrySaleSubmitted
    {
        public bool Pending { get; set; } = true;
        public int PendingSaleId { get; set; }
        public string Message { get; set; } = "Sent for approval. It will be posted once a manager approves it.";
    }
}
