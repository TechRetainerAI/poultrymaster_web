using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IHotelRoomService
    {
        Task<List<HotelRoomModel>> ListAsync(string farmId);
        Task<HotelRoomModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(HotelRoomModel m);
        Task UpdateAsync(HotelRoomModel m);
        Task UpdateStatusAsync(int id, string farmId, string status);
        Task DeleteAsync(int id, string farmId);
        Task<List<HotelRoomStatusSummary>> GetStatusSummaryAsync(string farmId);

        // Room Amenities
        Task<List<HotelRoomAmenityModel>> ListRoomAmenitiesAsync(int roomId, string farmId);
        Task SetRoomAmenityAsync(int roomId, int amenityId, string farmId);
        Task RemoveRoomAmenityAsync(int roomId, int amenityId, string farmId);
    }
}
