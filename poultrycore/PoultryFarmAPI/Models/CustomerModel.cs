using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public class CustomerModel
    {
        [Key]
        public int CustomerId { get; set; }

        [Required]
        public string FarmId { get; set; }

        [Required]
        public string UserId { get; set; }

        [Required]
        [StringLength(100)]
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