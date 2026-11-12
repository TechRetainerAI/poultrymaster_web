using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// What happened to the birds between placing a flock and today — the same
    /// shape the Initial Farm Setup wizard sends per flock (migration 319).
    /// </summary>
    public class ExistingFlockHistory
    {
        public int OriginallyPlaced { get; set; }
        public int CurrentLiveBirds { get; set; }
        /// <summary>False = the farm cannot break the difference down; all of it is "other", never mortality.</summary>
        public bool HistoryKnown { get; set; } = true;
        public int HistoricalMortality { get; set; }
        public int HistoricalSold { get; set; }
        public int HistoricalCulled { get; set; }
        public int HistoricalTransferred { get; set; }
        public string? Notes { get; set; }

        public int Difference => Math.Max(0, OriginallyPlaced - CurrentLiveBirds);

        /// <summary>Same rule as FarmSetupValidator.Breakdown: what the buckets do not cover is unknown.</summary>
        public (int Mortality, int Sold, int Culled, int Transferred, int Other) Breakdown()
        {
            if (!HistoryKnown) return (0, 0, 0, 0, Difference);
            var known = HistoricalMortality + HistoricalSold + HistoricalCulled + HistoricalTransferred;
            return (HistoricalMortality, HistoricalSold, HistoricalCulled, HistoricalTransferred, Math.Max(0, Difference - known));
        }

        /// <summary>Null when valid.</summary>
        public string? Validate()
        {
            if (OriginallyPlaced <= 0) return "Enter how many birds were originally placed.";
            if (CurrentLiveBirds < 0) return "Birds remaining cannot be negative.";
            if (CurrentLiveBirds > OriginallyPlaced)
                return "Birds remaining are more than were placed. Record the extra birds as a transfer in or a correction instead.";
            if (HistoricalMortality < 0 || HistoricalSold < 0 || HistoricalCulled < 0 || HistoricalTransferred < 0)
                return "Historical figures cannot be negative.";
            if (HistoryKnown && HistoricalMortality + HistoricalSold + HistoricalCulled + HistoricalTransferred > Difference)
                return $"The reasons add up to more than the {Difference:N0} birds that are gone.";
            return null;
        }
    }

    /// <summary>POST api/Flock/existing — an already-operating flock (Issue 5).</summary>
    public class ExistingFlockRequest
    {
        [Required] public FlockModel Flock { get; set; } = new();
        [Required] public ExistingFlockHistory History { get; set; } = new();
        /// <summary>The date the remaining count is true on. Defaults to the company business date.</summary>
        public DateTime? AsOfDate { get; set; }
        /// <summary>"Flocks page" / "Farm Setup" — recorded on the opening position.</summary>
        public string? Source { get; set; }
    }

    /// <summary>One line of a batch reconciliation (birds that never went into a flock).</summary>
    public class BatchReconciliationLine
    {
        /// <summary>Sale | Mortality | Cull | TransferOut | StockCorrection | Other</summary>
        public string Kind { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public DateTime? Date { get; set; }
        public string? Note { get; set; }
        /// <summary>StockCorrection only: Decrease (default) or Increase.</summary>
        public string? Direction { get; set; }
        // ---- Sale only
        /// <summary>Set = these birds were sold FROM this flock (already in its opening position); the line only values them.</summary>
        public int? FlockId { get; set; }
        public decimal? PricePerBird { get; set; }
        public bool ValueUnknown { get; set; }
        public int? CustomerId { get; set; }
        public decimal? AmountReceived { get; set; }
        public bool CreateReceivable { get; set; }
        public int? LinkDebtId { get; set; }
        public string? Reference { get; set; }
        public string Classification { get; set; } = "PreCutover";
    }

    public class BatchReconciliationRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public int BatchId { get; set; }
        public DateTime? AsOfDate { get; set; }
        public List<BatchReconciliationLine> Lines { get; set; } = new();
        /// <summary>Birds still alive and not in any flock after these lines.</summary>
        public int StillUnallocatedLive { get; set; }
        public string? Notes { get; set; }
        public string? Source { get; set; }
        [StringLength(100)] public string? RequestKey { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class BatchReconciliationReverseRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public string Reason { get; set; } = string.Empty;
        public string? ReversedBy { get; set; }
    }

    public class BirdTransferRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public int FromFlockId { get; set; }
        public int ToFlockId { get; set; }
        public int Quantity { get; set; }
        public DateTime? EffectiveDate { get; set; }
        [StringLength(500)] public string? Note { get; set; }
        [StringLength(100)] public string? RequestKey { get; set; }
        public string? CreatedBy { get; set; }
    }

    /// <summary>sppoultrybatchreconcile_summary row.</summary>
    public class BatchBirdReconciliationRow
    {
        public int BatchId { get; set; }
        public string BatchCode { get; set; } = string.Empty;
        public string BatchName { get; set; } = string.Empty;
        public DateTime StartDate { get; set; }
        public bool IsHistorical { get; set; }
        public int OriginalBirds { get; set; }
        public int OriginallyAllocated { get; set; }
        public int FlockCount { get; set; }
        public int BatchSold { get; set; }
        /// <summary>Birds sold out of the batch's (non-deleted) flocks: opening history + posted sales.</summary>
        public int FlockSold { get; set; }
        public int BatchMortality { get; set; }
        public int BatchCulled { get; set; }
        public int BatchTransferred { get; set; }
        public int BatchOtherRemovals { get; set; }
        public int BatchAdditions { get; set; }
        /// <summary>Birds of the batch in no flock (derived).</summary>
        public int UnallocatedPool { get; set; }
        /// <summary>Of those, confirmed alive.</summary>
        public int UnallocatedLive { get; set; }
        /// <summary>Positive = not explained yet; negative = more placed than bought.</summary>
        public int Unexplained { get; set; }
        public int FlockLiveBirds { get; set; }
        public int TotalLiveBirds { get; set; }
        public int FlockHistoricalReductions { get; set; }
        public int HistoricalSaleBirds { get; set; }
        public decimal HistoricalSaleValue { get; set; }
        public decimal HistoricalReceived { get; set; }
        public decimal HistoricalOwed { get; set; }
        /// <summary>FullyAccountedFor | NeedsReconciliation | OverAllocated</summary>
        public string Status { get; set; } = string.Empty;
        public DateTime? LastReconciledAt { get; set; }
        public string? LastReconciliationNo { get; set; }

        // 418: where the birds PLACED IN FLOCKS went. Together with FlockLiveBirds
        // these add up to OriginallyAllocated exactly.
        /// <summary>Opening position (Initial Farm Setup): lost before tracking began.</summary>
        public int FlockHistMortality { get; set; }
        public int FlockHistSold { get; set; }
        public int FlockHistCulled { get; set; }
        public int FlockHistTransferred { get; set; }
        public int FlockHistOther { get; set; }
        /// <summary>Since tracking began: production-record deaths, posted bird sales, closeout culls / transfers.</summary>
        public int FlockRecordedMortality { get; set; }
        public int FlockPostedSold { get; set; }
        public int FlockCulled { get; set; }
        public int FlockTransferred { get; set; }
        /// <summary>Signed remainder: count corrections, quantity adjustments, birds left in closed or deleted flocks.</summary>
        public int FlockOtherChanges { get; set; }
    }

    public class BirdRepairDiagnosticRow
    {
        public string FarmId { get; set; } = string.Empty;
        public string CheckCode { get; set; } = string.Empty;
        public string Severity { get; set; } = string.Empty;
        public int? LedgerRowId { get; set; }
        public int? OpeningPositionId { get; set; }
        public int? BatchId { get; set; }
        public int? FlockId { get; set; }
        public string? FlockName { get; set; }
        public string? CurrentValue { get; set; }
        public string? ExpectedValue { get; set; }
        public string? MissingRelationship { get; set; }
        public string? ProposedCorrection { get; set; }
        public string? DoubleApplicationRisk { get; set; }
        public string Confidence { get; set; } = string.Empty;
        public string? Evidence { get; set; }
        public bool AutoRepairable { get; set; }
    }

    public class BirdRepairAppliedRow
    {
        public string CheckCode { get; set; } = string.Empty;
        public int LedgerRowId { get; set; }
        public int? BatchId { get; set; }
        public int? FlockId { get; set; }
        public bool Applied { get; set; }
        public string? Evidence { get; set; }
    }

    public class BirdRepairApplyRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public bool DryRun { get; set; } = true;
        public string? RepairedBy { get; set; }
    }
}
