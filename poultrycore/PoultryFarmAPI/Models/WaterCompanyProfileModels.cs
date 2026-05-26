using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public static class WaterBusinessTypes
    {
        public const string Sachet  = "Sachet";
        public const string Bottled = "Bottled";
        public const string Both    = "Both";
    }

    public static class WaterSourceTypes
    {
        public const string Borehole   = "Borehole";
        public const string GhanaWater = "GhanaWater";
        public const string Tanker     = "Tanker";
        public const string Mixed      = "Mixed";
    }

    public class WaterCompanyProfileModel
    {
        [Key] public int WaterCompanyProfileId { get; set; }

        [Required] public string FarmId { get; set; } = string.Empty;

        [StringLength(150)] public string? BrandName { get; set; }

        [Required, StringLength(30)] public string BusinessType { get; set; } = WaterBusinessTypes.Sachet;

        [StringLength(500)] public string? ProductionSiteAddress { get; set; }
        [StringLength(255)] public string? MainLocation { get; set; }

        [Required, StringLength(30)] public string WaterSourceType { get; set; } = WaterSourceTypes.Borehole;

        [Required, StringLength(10)] public string DefaultCurrency { get; set; } = "GHC";

        [Range(1, int.MaxValue)] public int DefaultBagSachetCount { get; set; } = 30;

        [StringLength(150)] public string? OwnerName { get; set; }
        [StringLength(50)]  public string? PhoneNumber { get; set; }

        [StringLength(1000)] public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    /// <summary>POST /api/Water/company/setup body.</summary>
    public class WaterCompanySetupRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [StringLength(150)] public string? BrandName { get; set; }
        [StringLength(30)]  public string? BusinessType { get; set; }
        [StringLength(500)] public string? ProductionSiteAddress { get; set; }
        [StringLength(255)] public string? MainLocation { get; set; }
        [StringLength(30)]  public string? WaterSourceType { get; set; }
        [StringLength(10)]  public string? DefaultCurrency { get; set; }
        public int? DefaultBagSachetCount { get; set; }
        [StringLength(150)] public string? OwnerName { get; set; }
        [StringLength(50)]  public string? PhoneNumber { get; set; }
        [StringLength(1000)] public string? Notes { get; set; }
    }

    /// <summary>PUT /api/Water/company body — same shape minus FarmId (taken from query).</summary>
    public class WaterCompanyUpdateRequest
    {
        [StringLength(150)] public string? BrandName { get; set; }
        [StringLength(30)]  public string? BusinessType { get; set; }
        [StringLength(500)] public string? ProductionSiteAddress { get; set; }
        [StringLength(255)] public string? MainLocation { get; set; }
        [StringLength(30)]  public string? WaterSourceType { get; set; }
        [StringLength(10)]  public string? DefaultCurrency { get; set; }
        public int? DefaultBagSachetCount { get; set; }
        [StringLength(150)] public string? OwnerName { get; set; }
        [StringLength(50)]  public string? PhoneNumber { get; set; }
        [StringLength(1000)] public string? Notes { get; set; }
    }
}
