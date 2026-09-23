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

        /// <summary>
        /// Create many houses for one company in a single transaction: all of them
        /// or none. Every row goes through the same <c>sphouse_insert</c> as
        /// <see cref="Create"/>, so a bulk-created house is indistinguishable from
        /// one added through the single "Add House" form.
        /// </summary>
        /// <returns>The created houses, re-read from the database after commit.</returns>
        List<HouseModel> CreateBulk(string userId, string farmId, IReadOnlyList<BulkHouseItem> items);
    }
}
