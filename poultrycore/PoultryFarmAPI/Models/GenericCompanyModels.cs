using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Platform-wide lookup. NOT FarmId-scoped.
    // =========================================================================
    public class BusinessCategoryModel
    {
        [Key]
        public int BusinessCategoryId { get; set; }

        [Required]
        [StringLength(100)]
        public string Name { get; set; } = string.Empty;

        [StringLength(500)]
        public string? Description { get; set; }

        public int SortOrder { get; set; }
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // =========================================================================
    // One row per Farms where Farms.Type = 'Generic'
    // =========================================================================
    public class GenericCompanyProfileModel
    {
        [Key]
        public int GenericCompanyProfileId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int? BusinessCategoryId { get; set; }

        // Snapshot captured at create-time so renames of the lookup don't
        // rewrite history.
        [StringLength(100)]
        public string? BusinessCategoryNameSnapshot { get; set; }

        // Live name from the BusinessCategories lookup (populated by the SP).
        [StringLength(100)]
        public string? BusinessCategoryName { get; set; }

        [StringLength(500)]
        public string? BusinessDescription { get; set; }

        [Required]
        [StringLength(10)]
        public string DefaultCurrency { get; set; } = "GHC";

        [Range(0, double.MaxValue)]
        public decimal OpeningCashBalance { get; set; }

        public DateTime? BusinessStartDate { get; set; }

        [StringLength(255)]
        public string? MainLocation { get; set; }

        [StringLength(150)]
        public string? OwnerName { get; set; }

        [StringLength(50)]
        public string? PhoneNumber { get; set; }

        [StringLength(1000)]
        public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // =========================================================================
    // Setup request: called once after the Farm row is created (Type='Generic').
    // Idempotent on the server side.
    // =========================================================================
    public class GenericCompanySetupRequest
    {
        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int? BusinessCategoryId { get; set; }

        [StringLength(500)]
        public string? BusinessDescription { get; set; }

        [StringLength(10)]
        public string? DefaultCurrency { get; set; }

        [Range(0, double.MaxValue)]
        public decimal? OpeningCashBalance { get; set; }

        public DateTime? BusinessStartDate { get; set; }

        [StringLength(255)]
        public string? MainLocation { get; set; }

        [StringLength(150)]
        public string? OwnerName { get; set; }

        [StringLength(50)]
        public string? PhoneNumber { get; set; }

        [StringLength(1000)]
        public string? Notes { get; set; }
    }

    public class GenericCompanyUpdateRequest
    {
        public int? BusinessCategoryId { get; set; }

        [StringLength(500)]
        public string? BusinessDescription { get; set; }

        [StringLength(10)]
        public string? DefaultCurrency { get; set; }

        [Range(0, double.MaxValue)]
        public decimal? OpeningCashBalance { get; set; }

        public DateTime? BusinessStartDate { get; set; }

        [StringLength(255)]
        public string? MainLocation { get; set; }

        [StringLength(150)]
        public string? OwnerName { get; set; }

        [StringLength(50)]
        public string? PhoneNumber { get; set; }

        [StringLength(1000)]
        public string? Notes { get; set; }
    }

    // =========================================================================
    // Per-FarmId seed/CRUD tables
    // =========================================================================
    public class GenericExpenseCategoryModel
    {
        [Key]
        public int GenericExpenseCategoryId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(100)]
        public string Name { get; set; } = string.Empty;

        [StringLength(500)]
        public string? Description { get; set; }

        public bool IsActive { get; set; } = true;
        public bool IsDeleted { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class GenericCashAccountModel
    {
        [Key]
        public int GenericCashAccountId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(150)]
        public string AccountName { get; set; } = string.Empty;

        // 'MainCashBox' | 'PettyCash' | 'OwnerCash' | 'MoMoWallet' |
        // 'BankAccount' | 'StaffCash' | 'BranchCash' | 'Other'
        [Required]
        [StringLength(40)]
        public string AccountType { get; set; } = "MainCashBox";

        [Range(0, double.MaxValue)]
        public decimal OpeningBalance { get; set; }

        public decimal CurrentBalance { get; set; }

        public bool AllowNegativeBalance { get; set; }

        public bool IsActive { get; set; } = true;

        [StringLength(500)]
        public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class GenericCustomerTypeModel
    {
        [Key]
        public int GenericCustomerTypeId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class GenericSupplierTypeModel
    {
        [Key]
        public int GenericSupplierTypeId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class GenericPaymentMethodModel
    {
        [Key]
        public int GenericPaymentMethodId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }
}
