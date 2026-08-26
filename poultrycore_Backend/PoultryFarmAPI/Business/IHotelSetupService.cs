using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IHotelSetupService
    {
        // Profile
        Task<HotelProfileModel?> GetProfileAsync(string farmId);
        Task<HotelProfileModel> UpsertProfileAsync(HotelProfileModel m);

        // Room Types
        Task<List<HotelRoomTypeModel>> ListRoomTypesAsync(string farmId);
        Task<HotelRoomTypeModel?> GetRoomTypeAsync(int id, string farmId);
        Task<int> InsertRoomTypeAsync(HotelRoomTypeModel m);
        Task UpdateRoomTypeAsync(HotelRoomTypeModel m);
        Task DeleteRoomTypeAsync(int id, string farmId);

        // Floors
        Task<List<HotelFloorModel>> ListFloorsAsync(string farmId);
        Task<int> InsertFloorAsync(HotelFloorModel m);
        Task UpdateFloorAsync(HotelFloorModel m);
        Task DeleteFloorAsync(int id, string farmId);

        // Amenities
        Task<List<HotelAmenityModel>> ListAmenitiesAsync(string farmId);
        Task<int> InsertAmenityAsync(HotelAmenityModel m);
        Task UpdateAmenityAsync(HotelAmenityModel m);
        Task DeleteAmenityAsync(int id, string farmId);
    }
}
