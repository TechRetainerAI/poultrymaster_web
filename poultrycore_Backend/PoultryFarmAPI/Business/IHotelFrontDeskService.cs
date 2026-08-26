using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IHotelFrontDeskService
    {
        Task<object> CheckInAsync(string farmId, int bookingId, int roomId, string? keyCardNumber, decimal depositAmount, string? depositMethod, string? notes);
        Task<object> CheckOutAsync(string farmId, int bookingId, int roomId, decimal lateFee, decimal damageCharges, bool keyReturned, string? notes);
    }

    public interface IHotelHousekeepingService
    {
        Task<List<HotelHousekeepingTaskModel>> ListAsync(string farmId);
        Task<int> InsertAsync(string farmId, int roomId, string taskType, string priority, string? assignedTo, string? scheduledDate, string? notes);
        Task UpdateStatusAsync(int id, string farmId, string status);
    }

    public class HotelHousekeepingTaskModel
    {
        public int HotelHousekeepingTaskId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int HotelRoomId { get; set; }
        public string TaskType { get; set; } = "Cleaning";
        public string Priority { get; set; } = "Normal";
        public string Status { get; set; } = "Pending";
        public string? AssignedTo { get; set; }
        public DateTime ScheduledDate { get; set; }
        public DateTime? StartedAt { get; set; }
        public DateTime? CompletedAt { get; set; }
        public string? InspectedBy { get; set; }
        public string? InspectionNotes { get; set; }
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? RoomNumber { get; set; }
    }
}
