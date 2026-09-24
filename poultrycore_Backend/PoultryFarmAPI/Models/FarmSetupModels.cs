using System;
using System.Collections.Generic;

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// A batch the wizard should create, or an existing one it should reuse.
    ///
    /// <para>
    /// <see cref="Key"/> is a client-side label ("b1"), not an id: flocks refer to
    /// their batch by key so a batch that does not exist yet can still be pointed
    /// at. The server resolves keys to real ids inside the setup transaction.
    /// </para>
    /// </summary>
    public class FarmSetupBatchInput
    {
        public string Key { get; set; } = string.Empty;
        /// <summary>Set to reuse a batch the farm already has. Everything else is then ignored.</summary>
        public int? ExistingBatchId { get; set; }

        public string BatchName { get; set; } = string.Empty;
        public string BatchCode { get; set; } = string.Empty;
        public string Breed { get; set; } = string.Empty;
        public int NumberOfBirds { get; set; }
        public DateTime StartDate { get; set; }

        // Optional. An established farm often does not know what it paid, and the
        // point of onboarding is the bird position, not the ledger.
        public decimal? CostPerChick { get; set; }
        public decimal? TotalCost { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierType { get; set; }
        public string? Notes { get; set; }
    }

    /// <summary>A house the wizard should create, or an existing one it should reuse.</summary>
    public class FarmSetupHouseInput
    {
        public string Key { get; set; } = string.Empty;
        /// <summary>Set to reuse a house the farm already has.</summary>
        public int? ExistingHouseId { get; set; }

        public string HouseName { get; set; } = string.Empty;
        public int? Capacity { get; set; }
        public string? Location { get; set; }
    }

    /// <summary>
    /// One flock as it stands TODAY, plus what is known about how it got there.
    ///
    /// <para>
    /// The two numbers that matter: <see cref="OriginallyPlaced"/> is what went in
    /// and is what batch totals are checked against; <see cref="CurrentLiveBirds"/>
    /// is what is standing in the pen and becomes the flock's quantity — which is
    /// what makes the first real production record start from the right figure
    /// without a fabricated one before it.
    /// </para>
    /// </summary>
    public class FarmSetupFlockInput
    {
        public string BatchKey { get; set; } = string.Empty;
        public string HouseKey { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;

        public int OriginallyPlaced { get; set; }
        public int CurrentLiveBirds { get; set; }

        /// <summary>Supplied when the farm knows it. Otherwise derived from <see cref="CurrentAgeInWeeks"/>.</summary>
        public DateTime? StartDate { get; set; }
        /// <summary>Used only when <see cref="StartDate"/> is null; the date is then derived and flagged as estimated.</summary>
        public int? CurrentAgeInWeeks { get; set; }

        /// <summary>
        /// False means the farm cannot break the difference down. The whole of it
        /// is then recorded as an unknown opening adjustment — never as mortality.
        /// </summary>
        public bool HistoryKnown { get; set; }
        public int HistoricalMortality { get; set; }
        public int HistoricalSold { get; set; }
        public int HistoricalCulled { get; set; }
        public int HistoricalTransferred { get; set; }
        public int OtherAdjustment { get; set; }

        public string? Notes { get; set; }
    }

    /// <summary>POST api/PoultryFarmSetup/complete body.</summary>
    public class FarmSetupRequest
    {
        public string UserId { get; set; } = string.Empty;
        public string FarmId { get; set; } = string.Empty;

        /// <summary>"ExistingFarm" — the only mode that reaches this endpoint. A farm
        /// starting with new chicks uses the ordinary batch + allocation flow instead.</summary>
        public string SetupMode { get; set; } = "ExistingFarm";

        public List<FarmSetupBatchInput> Batches { get; set; } = new();
        public List<FarmSetupHouseInput> Houses { get; set; } = new();
        public List<FarmSetupFlockInput> Flocks { get; set; } = new();

        /// <summary>Recorded on every audit row. Defaults to "Initial Farm Setup".</summary>
        public string? Source { get; set; }
        public string? Notes { get; set; }
    }

    /// <summary>A problem pinned to the row that caused it.</summary>
    public class FarmSetupRowError
    {
        /// <summary>"batches" | "houses" | "flocks" | "setup".</summary>
        public string Section { get; set; } = string.Empty;
        /// <summary>Zero-based index into that section, or -1 for the setup as a whole.</summary>
        public int Index { get; set; }
        public string Field { get; set; } = string.Empty;
        public string Message { get; set; } = string.Empty;
    }

    /// <summary>
    /// The opening position of one flock: what was true when tracking began.
    /// Never an operational event, and never dated into a reporting period.
    /// </summary>
    public class OpeningFlockPositionModel
    {
        public int OpeningPositionId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int FlockId { get; set; }
        public string? FlockName { get; set; }
        public int? BatchId { get; set; }
        public int? HouseId { get; set; }
        public DateTime EffectiveBusinessDate { get; set; }

        public int OriginallyPlaced { get; set; }
        public int OpeningLiveBirds { get; set; }

        public int HistoricalMortality { get; set; }
        public int HistoricalSold { get; set; }
        public int HistoricalCulled { get; set; }
        public int HistoricalTransferred { get; set; }
        public int OtherAdjustment { get; set; }

        public bool HistoryKnown { get; set; }
        public bool StartDateEstimated { get; set; }
        public string Source { get; set; } = string.Empty;
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }

        /// <summary>Birds that went missing before tracking began. Not mortality unless said so.</summary>
        public int HistoricalReduction => Math.Max(0, OriginallyPlaced - OpeningLiveBirds);
    }

    /// <summary>The one-per-company record that says onboarding is done.</summary>
    public class FarmSetupStatusModel
    {
        public bool IsComplete { get; set; }
        public int FarmSetupId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string SetupMode { get; set; } = string.Empty;
        public DateTime? CompletedBusinessDate { get; set; }
        public DateTime? CompletedAt { get; set; }
        public string? CompletedBy { get; set; }
        public int BatchCount { get; set; }
        public int HouseCount { get; set; }
        public int FlockCount { get; set; }
        public int OriginallyPlaced { get; set; }
        public int OpeningLiveBirds { get; set; }
        public int HistoricalReduction { get; set; }
        public string? Notes { get; set; }

        /// <summary>
        /// True when the company has nothing worth calling a farm yet — no batches,
        /// no houses, no flocks. What decides whether to OFFER the wizard; it never
        /// decides whether the wizard may run.
        /// </summary>
        public bool LooksEmpty { get; set; }
        public int ExistingBatches { get; set; }
        public int ExistingHouses { get; set; }
        public int ExistingFlocks { get; set; }
    }

    /// <summary>
    /// Opening historical mortality beside mortality recorded since — the two kept
    /// apart on purpose. Known lifetime mortality is their sum and NEVER includes
    /// the unknown opening adjustment.
    /// </summary>
    public class OpeningPositionSummaryModel
    {
        public int FlockCount { get; set; }
        public int OriginallyPlaced { get; set; }
        public int OpeningLiveBirds { get; set; }
        public int HistoricalReduction { get; set; }

        public int HistoricalMortality { get; set; }
        public int HistoricalSold { get; set; }
        public int HistoricalCulled { get; set; }
        public int HistoricalTransferred { get; set; }
        public int OtherAdjustment { get; set; }

        /// <summary>How many flocks' opening reduction has no breakdown at all.</summary>
        public int FlocksWithUnknownHistory { get; set; }

        public List<OpeningFlockPositionModel> Positions { get; set; } = new();
    }

    /// <summary>Result of completing the wizard.</summary>
    public class FarmSetupResult
    {
        public bool Success { get; set; }
        public int BatchesCreated { get; set; }
        public int BatchesReused { get; set; }
        public int HousesCreated { get; set; }
        public int HousesReused { get; set; }
        public int FlocksCreated { get; set; }
        public int OpeningPositionsCreated { get; set; }

        public int OriginallyPlaced { get; set; }
        public int OpeningLiveBirds { get; set; }
        public int HistoricalReduction { get; set; }

        public DateTime? EffectiveBusinessDate { get; set; }

        public List<FarmSetupRowError> Errors { get; set; } = new();
        /// <summary>Things worth saying but not worth refusing over — see the capacity note in FarmSetupValidator.</summary>
        public List<FarmSetupRowError> Warnings { get; set; } = new();
        public string? Message { get; set; }
    }
}
