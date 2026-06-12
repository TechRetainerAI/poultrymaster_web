using System.Collections.Generic;
using System.Threading.Tasks;
using PoultryWeb.Models; // Same models used in your Web API

namespace PoultryWeb.Business
{
    public interface IFlockWebApiService
    {
        Task<List<FlockModel>> GetAllFlocksAsync();
        Task<FlockModel> GetFlockByIdAsync(int id);
        Task<FlockModel> CreateFlockAsync(FlockModel flock);
        Task UpdateFlockAsync(int id, FlockModel flock);
        Task DeleteFlockAsync(int id);
    }
}
