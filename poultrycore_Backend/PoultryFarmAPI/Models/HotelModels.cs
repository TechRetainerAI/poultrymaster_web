using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Hotel Foundation Models (Phase 1)
    // =========================================================================

    public class HotelProfileModel
    {
        [Key]
        public int HotelProfileId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(200)]
        public string HotelName { get; set; } = string.Empty;

        [StringLength(500)]
        public string? Address { get; set; }

        [StringLength(100)]
        public string? City { get; set; }

        [StringLength(100)]
        public string? Country { get; set; }

        [StringLength(50)]
        public string? Phone { get; set; }

        [StringLength(200)]
        public string? Email { get; set; }

        [Range(1, 5)]
        public int? StarRating { get; set; }

        [StringLength(10)]
        public string CheckInTime { get; set; } = "14:00";

        [StringLength(10)]
        public string CheckOutTime { get; set; } = "12:00";

        [StringLength(10)]
        public string DefaultCurrency { get; set; } = "GHS";

        public decimal TaxRate { get; set; }

        public decimal ServiceChargeRate { get; set; }

        [StringLength(50)]
        public string? TimeZone { get; set; }

        [StringLength(500)]
        public string? LogoUrl { get; set; }

        public string? Description { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class HotelRoomCategoryModel
    {
        [Key]
        public int HotelRoomCategoryId { get; set; }

        [Required]
        [StringLength(10)]
        public string Code { get; set; } = string.Empty;

        [Required]
        [StringLength(100)]
        public string Description { get; set; } = string.Empty;

        public int SortOrder { get; set; }

        public bool IsActive { get; set; } = true;
    }

    public class HotelBedTypeModel
    {
        [Key]
        public int HotelBedTypeId { get; set; }

        [Required]
        [StringLength(10)]
        public string Code { get; set; } = string.Empty;

        [Required]
        [StringLength(100)]
        public string Description { get; set; } = string.Empty;

        public int SortOrder { get; set; }

        public bool IsActive { get; set; } = true;
    }

    public class HotelRoomTypeModel
    {
        [Key]
        public int HotelRoomTypeId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(100)]
        public string Name { get; set; } = string.Empty;

        [StringLength(500)]
        public string? Description { get; set; }

        public decimal BaseRate { get; set; }

        [Range(1, 20)]
        public int MaxOccupancy { get; set; } = 2;

        [StringLength(50)]
        public string? BedType { get; set; }

        [StringLength(500)]
        public string? ImageUrl { get; set; }

        public bool IsActive { get; set; } = true;

        public int SortOrder { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        // Room category (lookup)
        public int? HotelRoomCategoryId { get; set; }
        public string? CategoryCode { get; set; }
        public string? CategoryName { get; set; }

        // Bed type (lookup)
        public int? HotelBedTypeId { get; set; }
        public string? BedTypeCode { get; set; }
        public string? BedTypeName { get; set; }
    }

    public class RestaurantMenuCategoryTypeModel
    {
        [Key]
        public int RestaurantMenuCategoryTypeId { get; set; }
        [Required][StringLength(10)]
        public string Code { get; set; } = string.Empty;
        [Required][StringLength(100)]
        public string Description { get; set; } = string.Empty;
        public int SortOrder { get; set; }
        public bool IsActive { get; set; } = true;
    }

    public class HotelSupplyCategoryModel
    {
        [Key]
        public int HotelSupplyCategoryId { get; set; }
        [Required][StringLength(10)]
        public string Code { get; set; } = string.Empty;
        [Required][StringLength(100)]
        public string Description { get; set; } = string.Empty;
        public int SortOrder { get; set; }
        public bool IsActive { get; set; } = true;
    }

    public class HotelSupplyItemModel
    {
        [Key]
        public int HotelSupplyItemId { get; set; }
        [Required][StringLength(10)]
        public string Code { get; set; } = string.Empty;
        [Required][StringLength(100)]
        public string Description { get; set; } = string.Empty;
        [StringLength(50)]
        public string? Category { get; set; }
        public int SortOrder { get; set; }
        public bool IsActive { get; set; } = true;
    }

    public class HotelMaintenanceAssetModel
    {
        [Key]
        public int HotelMaintenanceAssetId { get; set; }
        [Required][StringLength(10)]
        public string Code { get; set; } = string.Empty;
        [Required][StringLength(100)]
        public string Description { get; set; } = string.Empty;
        public int SortOrder { get; set; }
        public bool IsActive { get; set; } = true;
    }

    public class HotelTableLocationModel
    {
        [Key]
        public int HotelTableLocationId { get; set; }
        [Required][StringLength(10)]
        public string Code { get; set; } = string.Empty;
        [Required][StringLength(100)]
        public string Description { get; set; } = string.Empty;
        public int SortOrder { get; set; }
        public bool IsActive { get; set; } = true;
    }

    public class HotelHKTaskTypeModel
    {
        [Key]
        public int HotelHKTaskTypeId { get; set; }

        [Required]
        [StringLength(10)]
        public string Code { get; set; } = string.Empty;

        [Required]
        [StringLength(100)]
        public string Description { get; set; } = string.Empty;

        public int SortOrder { get; set; }

        public bool IsActive { get; set; } = true;
    }

    public class HotelRequestTypeModel
    {
        [Key]
        public int HotelRequestTypeId { get; set; }

        [Required]
        [StringLength(10)]
        public string Code { get; set; } = string.Empty;

        [Required]
        [StringLength(100)]
        public string Description { get; set; } = string.Empty;

        public int SortOrder { get; set; }

        public bool IsActive { get; set; } = true;
    }

    public class HotelCommSubjectModel
    {
        [Key]
        public int HotelCommSubjectId { get; set; }

        [Required]
        [StringLength(10)]
        public string Code { get; set; } = string.Empty;

        [Required]
        [StringLength(100)]
        public string Description { get; set; } = string.Empty;

        public int SortOrder { get; set; }

        public bool IsActive { get; set; } = true;
    }

    public class HotelIdTypeModel
    {
        [Key]
        public int HotelIdTypeId { get; set; }

        [Required]
        [StringLength(10)]
        public string Code { get; set; } = string.Empty;

        [Required]
        [StringLength(100)]
        public string Description { get; set; } = string.Empty;

        public int SortOrder { get; set; }

        public bool IsActive { get; set; } = true;
    }

    public class HotelFloorModel
    {
        [Key]
        public int HotelFloorId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int FloorNumber { get; set; }

        [Required]
        [StringLength(100)]
        public string Name { get; set; } = string.Empty;

        public bool IsActive { get; set; } = true;

        public int SortOrder { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public static class HotelRoomStatus
    {
        public const string Available = "Available";
        public const string Occupied = "Occupied";
        public const string Maintenance = "Maintenance";
        public const string Reserved = "Reserved";
        public const string Cleaning = "Cleaning";
    }

    public class HotelRoomModel
    {
        [Key]
        public int HotelRoomId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(20)]
        public string RoomNumber { get; set; } = string.Empty;

        public int HotelRoomTypeId { get; set; }

        public int? HotelFloorId { get; set; }

        [StringLength(30)]
        public string Status { get; set; } = HotelRoomStatus.Available;

        [StringLength(500)]
        public string? Description { get; set; }

        public bool IsActive { get; set; } = true;

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        // Joined fields from RoomType
        public string? RoomTypeName { get; set; }
        public decimal? BaseRate { get; set; }
        public int? MaxOccupancy { get; set; }
        public string? BedType { get; set; }

        // Joined fields from Floor
        public int? FloorNumber { get; set; }
        public string? FloorName { get; set; }
    }

    public class HotelAmenityModel
    {
        [Key]
        public int HotelAmenityId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(100)]
        public string Name { get; set; } = string.Empty;

        [StringLength(50)]
        public string? Category { get; set; }

        [StringLength(50)]
        public string? Icon { get; set; }

        public bool IsActive { get; set; } = true;

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class HotelRoomAmenityModel
    {
        public int HotelRoomId { get; set; }
        public int HotelAmenityId { get; set; }
        public string FarmId { get; set; } = string.Empty;

        // Joined fields
        public string? Name { get; set; }
        public string? Category { get; set; }
        public string? Icon { get; set; }
    }

    public class HotelRoomStatusSummary
    {
        public string Status { get; set; } = string.Empty;
        public int RoomCount { get; set; }
    }
}
