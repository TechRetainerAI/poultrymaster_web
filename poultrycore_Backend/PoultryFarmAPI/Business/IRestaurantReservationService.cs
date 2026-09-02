using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantReservationService
    {
        // Settings
        Task<RestaurantReservationSettingsModel?> GetSettingsAsync(string farmId);
        Task UpsertSettingsAsync(RestaurantReservationSettingsModel m);

        // Reservations
        Task<(int id, string number)> CreateReservationAsync(RestaurantReservationModel m, bool autoConfirm);
        Task<List<RestaurantReservationModel>> ListReservationsAsync(string farmId, DateTime? date = null, string? status = null, DateTime? fromDate = null, DateTime? toDate = null);
        Task<RestaurantReservationModel?> GetReservationAsync(int id, string farmId);
        Task UpdateReservationAsync(RestaurantReservationModel m);
        Task UpdateReservationStatusAsync(int id, string farmId, string status, string? reason = null);
        Task DeleteReservationAsync(int id, string farmId);
        Task<List<AutoAssignTableResult>> AutoAssignTableAsync(string farmId, int partySize, DateTime date, string time);
        Task<ReservationStatsModel> GetReservationStatsAsync(string farmId, DateTime date);

        // Waitlist
        Task<List<RestaurantWaitlistModel>> ListWaitlistAsync(string farmId, string? status = null);
        Task<int> AddToWaitlistAsync(RestaurantWaitlistModel m);
        Task UpdateWaitlistStatusAsync(int id, string farmId, string status, int? tableId = null, string? tableNumber = null);
        Task DeleteFromWaitlistAsync(int id, string farmId);
        Task<WaitlistStatsModel> GetWaitlistStatsAsync(string farmId);
    }
}
