using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // This model holds the data structure for a single Main Flock Batch.
    public class MainFlockBatchModel
    {
        [Key]
        // Primary Key, auto-incremented in the database.
        public int BatchId { get; set; }

        [Required]
        // Used for filtering data for a specific Farm/Tenant.
        public string FarmId { get; set; }

        [Required]
        // Used for filtering data for a specific User.
        public string UserId { get; set; }

        [Required]
        [StringLength(25, ErrorMessage = "BatchCode cannot exceed 25 characters.")]
        // Unique identifier for the batch, manually provided or generated.
        public string BatchCode { get; set; } = string.Empty;

        [Required]
        [StringLength(100)]
        public string BatchName { get; set; } = string.Empty;

        [Required]
        [StringLength(50)]
        public string Breed { get; set; } = string.Empty;

        [Required]
        [Range(1, int.MaxValue, ErrorMessage = "The number of birds must be greater than zero.")]
        public int NumberOfBirds { get; set; }

        [Required]
        // The date the batch was started or acquired.
        public DateTime StartDate { get; set; }

        [StringLength(20)]
        public string Status { get; set; } = "active"; // e.g., "active", "inactive", "sold"

        // Per-chick acquisition cost.
        public decimal CostPerChick { get; set; }

        // Full purchase price for the batch. Stored explicitly so the user can override the auto-computed value.
        public decimal TotalCost { get; set; }

        // Amount actually paid to the supplier (USD). May differ from TotalCost during partial payments.
        public decimal AmountPaid { get; set; }

        [StringLength(20)]
        public string SupplierType { get; set; } = string.Empty; // "local" | "foreign"

        // Optional FK to dbo.Supplier.
        public int? SupplierId { get; set; }

        // Denormalized supplier name for display (filled from JOIN on GET).
        public string SupplierName { get; set; } = string.Empty;

        public string? Notes { get; set; }

        // Optional USD→local rate for foreign-supplier batch purchases.
        public decimal? DollarConversionRate { get; set; }

        // Date the record was created (managed by the database or service).
        public DateTime CreatedDate { get; set; }
    }
}
