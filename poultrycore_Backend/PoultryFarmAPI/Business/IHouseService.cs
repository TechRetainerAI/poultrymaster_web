using System.Collections.Generic;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IHouseService
    {
        List<HouseModel> GetAll(string userId, string farmId);
        HouseModel? GetById(int id, string userId, string farmId);
        int Create(HouseModel model);
        void Update(HouseModel model);
        void Delete(int id, string userId, string farmId);
    }
}
