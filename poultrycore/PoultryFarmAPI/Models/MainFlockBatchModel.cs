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

        // Date the record was created (managed by the database or service).
        public DateTime CreatedDate { get; set; }
    }
}
