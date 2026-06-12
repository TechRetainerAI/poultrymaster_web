using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public class SupplierModel
    {
        [Key]
        public int SupplierId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        public string UserId { get; set; } = string.Empty;

        [Required]
        [StringLength(200)]
        public string Name { get; set; } = string.Empty;

        [EmailAddress]
        public string? ContactEmail { get; set; }

        [Phone]
        public string? ContactPhone { get; set; }

        public string? Address { get; set; }

        public string? City { get; set; }

        public DateTime CreatedDate { get; set; }
    }
}
