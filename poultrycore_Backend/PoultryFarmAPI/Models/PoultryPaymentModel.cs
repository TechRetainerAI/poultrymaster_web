using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // A payment received against a poultry Sale (partial payments on credit
    // sales). Mirrors WaterPaymentModel.
    public class PoultryPaymentModel
    {
        [Key]
        public int PoultryPaymentId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        public int SaleId { get; set; }

        [Range(0.01, double.MaxValue)]
        public decimal Amount { get; set; }

        [StringLength(40)]
        public string? PaymentMethod { get; set; }

        public DateTime PaymentDate { get; set; }

        [StringLength(120)]
        public string? Reference { get; set; }

        [StringLength(300)]
        public string? Note { get; set; }

        public DateTime CreatedDate { get; set; }

        public string? CreatedBy { get; set; }

        /// <summary>Customer on the linked sale (populated by the list query).</summary>
        public string? CustomerName { get; set; }
    }
}
