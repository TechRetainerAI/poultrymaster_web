using System;
using System.Collections.Generic;

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// One row of "Add Multiple Batches". Each row carries every field it needs --
    /// the dialog copies its shared settings (supplier, cash account, status) onto
    /// every row before posting -- so the server never has to merge defaults.
    /// </summary>
    public class BulkFlockBatchItem
    {
        public string BatchName { get; set; } = string.Empty;
        public string BatchCode { get; set; } = string.Empty;
        public string? Breed { get; set; }
        public DateTime StartDate { get; set; }
        public int NumberOfBirds { get; set; }
        public decimal CostPerChick { get; set; }
        /// <summary>0 = cost per chick x birds, as the single form does.</summary>
        public decimal TotalCost { get; set; }
        public decimal AmountPaid { get; set; }
        public string? SupplierType { get; set; }
        public int? SupplierId { get; set; }
        public int? PoultryCashAccountId { get; set; }
        public string? Status { get; set; }
        public string? Notes { get; set; }
    }

    public class BulkFlockBatchCreateRequest
    {
        public string UserId { get; set; } = string.Empty;
        public string FarmId { get; set; } = string.Empty;
        public List<BulkFlockBatchItem> Batches { get; set; } = new();
        /// <summary>Which screen sent it; recorded on each batch's audit row.</summary>
        public string? Source { get; set; }
    }

    public class BulkFlockBatchRowError
    {
        /// <summary>Zero-based index into Batches, or -1 for the request as a whole.</summary>
        public int Index { get; set; }
        /// <summary>Matches the grid column: batchName | batchCode | numberOfBirds | startDate | costPerChick | amountPaid | batches.</summary>
        public string Field { get; set; } = string.Empty;
        public string Message { get; set; } = string.Empty;
    }

    /// <summary>Either every batch was created or none was.</summary>
    public class BulkFlockBatchCreateResult
    {
        public bool Success { get; set; }
        public int CreatedCount { get; set; }
        public List<MainFlockBatchModel> Batches { get; set; } = new();
        public List<BulkFlockBatchRowError> Errors { get; set; } = new();
        public string? Message { get; set; }
    }
}
