using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // Poultry equivalent of WaterBusinessTypes / WaterSourceTypes (migration 049).
    // The database validates these too; these constants keep the API and the SP
    // speaking the same vocabulary.
    public static class PoultryBusinessTypes
    {
        public const string Layers   = "Layers";
        public const string Broilers = "Broilers";
        public const string Both     = "Both";
    }

    public static class PoultryHousingSystems
    {
        public const string DeepLitter  = "DeepLitter";
        public const string BatteryCage = "BatteryCage";
        public const string FreeRange   = "FreeRange";
        public const string Mixed       = "Mixed";
    }

    public class PoultryCompanyProfileModel
    {
        [Key] public int PoultryCompanyProfileId { get; set; }

        [Required] public string FarmId { get; set; } = string.Empty;

        [StringLength(150)] public string? BrandName { get; set; }

        [Required, StringLength(30)] public string BusinessType { get; set; } = PoultryBusinessTypes.Layers;

        [StringLength(500)] public string? FarmSiteAddress { get; set; }
        [StringLength(255)] public string? MainLocation { get; set; }

        [Required, StringLength(30)] public string HousingSystem { get; set; } = PoultryHousingSystems.DeepLitter;

        [Required, StringLength(10)] public string DefaultCurrency { get; set; } = "GHC";

        /// <summary>
        /// Eggs per crate. Migration 211 made this load-bearing: the driver
        /// distribution flow converts crates to eggs with it, and it was
        /// previously hardcoded to 30 in the vehicle-loading form.
        /// </summary>
        [Range(1, int.MaxValue)] public int DefaultCrateEggCount { get; set; } = 30;

        /// <summary>Birds the farm can house. Null when not stated.</summary>
        [Range(0, int.MaxValue)] public int? TotalCapacity { get; set; }

        [StringLength(100)] public string? OperatingHours { get; set; }
        [StringLength(150)] public string? OwnerName { get; set; }
        [StringLength(50)]  public string? PhoneNumber { get; set; }
        [StringLength(150), EmailAddress] public string? Email { get; set; }

        [StringLength(1000)] public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    /// <summary>POST /api/Poultry/company/setup body.</summary>
    public class PoultryCompanySetupRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [StringLength(150)] public string? BrandName { get; set; }
        [StringLength(30)]  public string? BusinessType { get; set; }
        [StringLength(500)] public string? FarmSiteAddress { get; set; }
        [StringLength(255)] public string? MainLocation { get; set; }
        [StringLength(30)]  public string? HousingSystem { get; set; }
        [StringLength(10)]  public string? DefaultCurrency { get; set; }
        public int? DefaultCrateEggCount { get; set; }
        public int? TotalCapacity { get; set; }
        [StringLength(100)] public string? OperatingHours { get; set; }
        [StringLength(150)] public string? OwnerName { get; set; }
        [StringLength(50)]  public string? PhoneNumber { get; set; }
        [StringLength(150)] public string? Email { get; set; }
        [StringLength(1000)] public string? Notes { get; set; }
    }

    /// <summary>PUT /api/Poultry/company body — same shape minus FarmId (taken from query).</summary>
    public class PoultryCompanyUpdateRequest
    {
        [StringLength(150)] public string? BrandName { get; set; }
        [StringLength(30)]  public string? BusinessType { get; set; }
        [StringLength(500)] public string? FarmSiteAddress { get; set; }
        [StringLength(255)] public string? MainLocation { get; set; }
        [StringLength(30)]  public string? HousingSystem { get; set; }
        [StringLength(10)]  public string? DefaultCurrency { get; set; }
        public int? DefaultCrateEggCount { get; set; }
        public int? TotalCapacity { get; set; }
        [StringLength(100)] public string? OperatingHours { get; set; }
        [StringLength(150)] public string? OwnerName { get; set; }
        [StringLength(50)]  public string? PhoneNumber { get; set; }
        [StringLength(150)] public string? Email { get; set; }
        [StringLength(1000)] public string? Notes { get; set; }
    }
}
