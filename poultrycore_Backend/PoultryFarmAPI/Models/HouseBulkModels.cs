using System.Collections.Generic;

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// One row of a bulk house creation request.
    ///
    /// <para>
    /// Deliberately carries NO UserId/FarmId: the company is stated once, on the
    /// envelope, so a browser cannot slip a second company into row 3 of a batch.
    /// Everything else mirrors <see cref="HouseModel"/> exactly, because these
    /// rows end up in the very same <c>sphouse_insert</c> the single "Add House"
    /// form calls.
    /// </para>
    /// </summary>
    public class BulkHouseItem
    {
        public string HouseName { get; set; } = string.Empty;
        public int? Capacity { get; set; }
        public string? Location { get; set; }
    }

    /// <summary>
    /// POST api/House/bulk body. One company, one user, many houses.
    /// </summary>
    public class BulkHouseCreateRequest
    {
        public string UserId { get; set; } = string.Empty;
        public string FarmId { get; set; } = string.Empty;
        public List<BulkHouseItem> Houses { get; set; } = new();

        /// <summary>
        /// Where the batch came from — "Houses page", "Farm Setup Wizard",
        /// "Batch Allocation". Recorded on the per-house audit rows so the same
        /// service can be called from several screens and still be traceable.
        /// Free text; defaults when the caller says nothing.
        /// </summary>
        public string? Source { get; set; }
    }

    /// <summary>A validation failure pinned to the row that caused it.</summary>
    public class BulkHouseRowError
    {
        /// <summary>Zero-based index into the submitted Houses list.</summary>
        public int Index { get; set; }
        /// <summary>"houseName" | "capacity" | "location" — matches the grid column.</summary>
        public string Field { get; set; } = string.Empty;
        public string Message { get; set; } = string.Empty;
    }

    /// <summary>
    /// Result of a bulk create. Either everything was created or nothing was —
    /// see HouseService.CreateBulk for the transaction.
    /// </summary>
    public class BulkHouseCreateResult
    {
        public bool Success { get; set; }
        public int CreatedCount { get; set; }
        public List<HouseModel> Houses { get; set; } = new();
        public List<BulkHouseRowError> Errors { get; set; } = new();
        public string? Message { get; set; }
    }
}
