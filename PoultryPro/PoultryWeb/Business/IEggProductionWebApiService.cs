using PoultryWeb.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace PoultryWeb.Business
{
    public interface IEggProductionWebApiService
    {
        Task<List<EggProductionModel>> GetAllAsync();
        Task<EggProductionModel?> GetByIdAsync(int productionId);
        Task<EggProductionModel?> CreateAsync(EggProductionModel model);
        Task UpdateAsync(int productionId, EggProductionModel model);
        Task DeleteAsync(int productionId);
    }
}
