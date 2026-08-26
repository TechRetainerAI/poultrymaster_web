using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IHotelGuestService
    {
        Task<List<HotelGuestModel>> ListAsync(string farmId);
        Task<HotelGuestModel?> GetByIdAsync(int id, string farmId);
        Task<List<HotelGuestModel>> SearchAsync(string farmId, string query);
        Task<int> InsertAsync(HotelGuestModel m);
        Task UpdateAsync(HotelGuestModel m);
        Task DeleteAsync(int id, string farmId);
    }

    public interface IHotelBookingService
    {
        Task<List<HotelBookingModel>> ListAsync(string farmId);
        Task<HotelBookingModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(HotelBookingModel m);
        Task UpdateAsync(HotelBookingModel m);
        Task UpdateStatusAsync(int id, string farmId, string status);
        Task CancelAsync(int id, string farmId);
        Task<List<HotelBookingModel>> TodayArrivalsAsync(string farmId);
        Task<List<HotelBookingModel>> TodayDeparturesAsync(string farmId);
    }
}
