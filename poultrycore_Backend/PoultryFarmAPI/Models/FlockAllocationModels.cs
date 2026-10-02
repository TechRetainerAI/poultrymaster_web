using System;
using System.Collections.Generic;

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// One row of a batch-to-flocks allocation: this many birds from the batch,
    /// into this house, as a flock with this name.
    ///
    /// <para>
    /// Carries no UserId/FarmId/BatchId — those are stated once on the envelope,
    /// so a browser cannot slip a second company or a second batch into row 3.
    /// </para>
    /// </summary>
    public class FlockAllocationItem
    {
        public int HouseId { get; set; }
        public string Name { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public string? Notes { get; set; }
    }

    /// <summary>POST api/Flock/bulk-allocate body. One batch, one company, many flocks.</summary>
    public class FlockAllocationRequest
    {
        public string UserId { get; set; } = string.Empty;
        public string FarmId { get; set; } = string.Empty;
        public int BatchId { get; set; }
        public List<FlockAllocationItem> Allocations { get; set; } = new();

        /// <summary>
        /// Breed and start date for every flock created. Both default to the
        /// batch's own values when the caller says nothing — the same prefill the
        /// single Add Flock form does, just applied once instead of per row.
        /// </summary>
        public string? Breed { get; set; }
        public DateTime? StartDate { get; set; }

        /// <summary>
        /// Whether the birds have physically arrived. Mirrors the single form's
        /// toggle; defaults to true, since allocating birds into pens is something
        /// you do once they are there.
        /// </summary>
        public bool? HasArrived { get; set; }

        /// <summary>
        /// Where the allocation came from — "Batch Allocation Tool", "Farm Setup
        /// Wizard". Recorded on each created flock's audit row.
        /// </summary>
        public string? Source { get; set; }
    }

    /// <summary>A validation failure pinned to the row that caused it.</summary>
    public class FlockAllocationRowError
    {
        /// <summary>Zero-based index into Allocations, or -1 for the batch as a whole.</summary>
        public int Index { get; set; }
        /// <summary>"name" | "quantity" | "houseId" | "allocations" — matches the grid column.</summary>
        public string Field { get; set; } = string.Empty;
        public string Message { get; set; } = string.Empty;
    }

    /// <summary>
    /// What a batch has left to give. Every number here is DERIVED from flock
    /// records through spflock_gettotalquantityforbatch — there is no stored
    /// "allocated" counter to drift out of step.
    /// </summary>
    public class BatchAllocationSummary
    {
        public int BatchId { get; set; }
        public string BatchCode { get; set; } = string.Empty;
        public string BatchName { get; set; } = string.Empty;
        public string Breed { get; set; } = string.Empty;
        public DateTime StartDate { get; set; }
        public int OriginalBirds { get; set; }
        public int AllocatedBirds { get; set; }
        public int UnallocatedBirds { get; set; }
    }

    /// <summary>
    /// Result of an allocation. Either every flock was created or none was — see
    /// BirdFlockService.AllocateBatchToFlocks for the transaction and the lock.
    /// </summary>
    public class FlockAllocationResult
    {
        public bool Success { get; set; }
        public int CreatedCount { get; set; }
        public int BirdsAllocated { get; set; }
        public List<FlockModel> Flocks { get; set; } = new();
        /// <summary>The batch as it stands after the allocation, for the success screen.</summary>
        public BatchAllocationSummary? Batch { get; set; }
        public List<FlockAllocationRowError> Errors { get; set; } = new();
        public string? Message { get; set; }
    }

    /// <summary>
    /// Everything the allocation tool needs to open: what the batch has left, and
    /// the company's houses with their current occupancy. One call rather than
    /// three, and the occupancy is computed from flock records server-side rather
    /// than by the browser summing every flock on the farm.
    /// </summary>
    public class BatchAllocationContext
    {
        public BatchAllocationSummary Batch { get; set; } = new();
        public List<HouseOccupancyModel> Houses { get; set; } = new();
        /// <summary>Flock names already on this farm, for the duplicate check in the grid.</summary>
        public List<string> ExistingFlockNames { get; set; } = new();
    }

    /// <summary>
    /// A house as the allocation tool needs to see it: how much it holds and how
    /// much of that is already taken by active flocks.
    /// </summary>
    public class HouseOccupancyModel
    {
        public int HouseId { get; set; }
        public string HouseName { get; set; } = string.Empty;
        public int? Capacity { get; set; }
        public string? Location { get; set; }
        /// <summary>Birds in active flocks currently placed in this house.</summary>
        public int Occupied { get; set; }
        /// <summary>Capacity − Occupied, or null when the house has no capacity recorded.</summary>
        public int? AvailableCapacity { get; set; }
        /// <summary>Active flocks currently in this house. A house may hold more than one.</summary>
        public int ActiveFlocks { get; set; }
    }
}
