using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface ISupplierService
    {
        Task<int> Insert(SupplierModel model);
        Task Update(SupplierModel model);
        Task<SupplierModel?> GetById(int supplierId, string userId, string farmId);
        Task<List<SupplierModel>> GetAll(string userId, string farmId);
        Task Delete(int supplierId, string userId, string farmId);
    }
}
