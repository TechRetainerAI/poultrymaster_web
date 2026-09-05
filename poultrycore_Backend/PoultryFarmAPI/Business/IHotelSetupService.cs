using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IHotelSetupService
    {
        // Profile
        Task<HotelProfileModel?> GetProfileAsync(string farmId);
        Task<HotelProfileModel> UpsertProfileAsync(HotelProfileModel m);

        // Room Categories (system-wide lookup)
        Task<List<HotelRoomCategoryModel>> ListRoomCategoriesAsync();

        // Bed Types (system-wide lookup)
        Task<List<HotelBedTypeModel>> ListBedTypesAsync();

        // ID Types (system-wide lookup)
        Task<List<HotelIdTypeModel>> ListIdTypesAsync();

        // Restaurant Menu Category Types (system-wide lookup)
        Task<List<RestaurantMenuCategoryTypeModel>> ListMenuCategoryTypesAsync();

        // Supply Categories & Items (system-wide lookup)
        Task<List<HotelSupplyCategoryModel>> ListSupplyCategoriesAsync();
        Task<List<HotelSupplyItemModel>> ListSupplyItemsAsync();

        // Maintenance Assets (system-wide lookup)
        Task<List<HotelMaintenanceAssetModel>> ListMaintenanceAssetsAsync();

        // Table Locations (system-wide lookup)
        Task<List<HotelTableLocationModel>> ListTableLocationsAsync();

        // HK Task Types (system-wide lookup)
        Task<List<HotelHKTaskTypeModel>> ListHKTaskTypesAsync();

        // Guest Request Types (system-wide lookup)
        Task<List<HotelRequestTypeModel>> ListRequestTypesAsync();

        // Communication Subjects (system-wide lookup)
        Task<List<HotelCommSubjectModel>> ListCommSubjectsAsync();

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
