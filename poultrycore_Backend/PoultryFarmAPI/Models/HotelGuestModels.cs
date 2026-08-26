using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public class HotelGuestModel
    {
        [Key] public int HotelGuestId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required][StringLength(100)] public string FirstName { get; set; } = string.Empty;
        [Required][StringLength(100)] public string LastName { get; set; } = string.Empty;
        [StringLength(200)] public string? Email { get; set; }
        [StringLength(50)] public string? Phone { get; set; }
        [StringLength(50)] public string? IdType { get; set; }
        [StringLength(100)] public string? IdNumber { get; set; }
        [StringLength(100)] public string? Nationality { get; set; }
        [StringLength(500)] public string? Address { get; set; }
        public DateTime? DateOfBirth { get; set; }
        public string? Notes { get; set; }
        public bool IsVIP { get; set; }
        public int TotalStays { get; set; }
        public DateTime? LastStayDate { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public static class HotelBookingStatus
    {
        public const string Confirmed = "Confirmed";
        public const string CheckedIn = "CheckedIn";
        public const string CheckedOut = "CheckedOut";
        public const string Cancelled = "Cancelled";
        public const string NoShow = "NoShow";
    }

    public static class HotelBookingSource
    {
        public const string WalkIn = "WalkIn";
        public const string Phone = "Phone";
        public const string Online = "Online";
        public const string Agent = "Agent";
    }

    public class HotelBookingUpdateModel
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public int? HotelRoomId { get; set; }
        public int HotelRoomTypeId { get; set; }
        public DateTime CheckInDate { get; set; }
        public DateTime CheckOutDate { get; set; }
        public int NumberOfGuests { get; set; } = 1;
        public int Adults { get; set; } = 1;
        public int Children { get; set; }
        public decimal NightlyRate { get; set; }
        public decimal TotalAmount { get; set; }
        [StringLength(30)] public string Source { get; set; } = HotelBookingSource.WalkIn;
        public string? SpecialRequests { get; set; }
    }

    public class HotelBookingModel
    {
        [Key] public int HotelBookingId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required][StringLength(30)] public string BookingRef { get; set; } = string.Empty;
        public int HotelGuestId { get; set; }
        public int? HotelRoomId { get; set; }
        public int HotelRoomTypeId { get; set; }
        public DateTime CheckInDate { get; set; }
        public DateTime CheckOutDate { get; set; }
        public int NumberOfGuests { get; set; } = 1;
        public int Adults { get; set; } = 1;
        public int Children { get; set; }
        public decimal NightlyRate { get; set; }
        public decimal TotalAmount { get; set; }
        [StringLength(30)] public string Status { get; set; } = HotelBookingStatus.Confirmed;
        [StringLength(30)] public string Source { get; set; } = HotelBookingSource.WalkIn;
        public string? SpecialRequests { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        // Joined
        public string? GuestFirstName { get; set; }
        public string? GuestLastName { get; set; }
        public string? GuestPhone { get; set; }
        public string? GuestEmail { get; set; }
        public string? RoomNumber { get; set; }
        public string? RoomTypeName { get; set; }
    }
}
