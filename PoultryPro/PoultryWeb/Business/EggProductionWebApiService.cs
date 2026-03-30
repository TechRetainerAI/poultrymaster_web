using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using PoultryWeb.Models;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;

namespace PoultryWeb.Business
{
    public class EggProductionWebApiService : IEggProductionWebApiService
    {
        private readonly HttpClient _httpClient;
        private readonly string _baseApiUrl;
        private readonly string _userId;
        private readonly string _farmId;

        public EggProductionWebApiService(
            HttpClient httpClient,
            IConfiguration configuration,
            IHttpContextAccessor httpContextAccessor)
        {
            _httpClient = httpClient;
            _baseApiUrl = configuration["PoultryFarmApiUrl"];

            var user = httpContextAccessor.HttpContext?.User;
            _userId = user?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            _farmId = user?.FindFirst("FarmId")?.Value;

            if (string.IsNullOrEmpty(_userId))
                throw new Exception("UserId is missing from the current user's claims.");
            if (string.IsNullOrEmpty(_farmId))
                throw new Exception("FarmId is missing from the current user's claims.");
        }

        public async Task<List<EggProductionModel>> GetAllAsync()
        {
            try
            {
                var result = await _httpClient.GetFromJsonAsync<List<EggProductionModel>>(
                    $"{_baseApiUrl}api/EggProduction?userId={_userId}&farmId={_farmId}"
                );
                return result ?? new List<EggProductionModel>();
            }
            catch (Exception ex)
            {
                throw new Exception("Error while fetching all egg production records from the API.", ex);
            }
        }

        public async Task<EggProductionModel?> GetByIdAsync(int productionId)
        {
            try
            {
                return await _httpClient.GetFromJsonAsync<EggProductionModel>(
                    $"{_baseApiUrl}api/EggProduction/{productionId}?userId={_userId}&farmId={_farmId}"
                );
            }
            catch (Exception ex)
            {
                throw new Exception($"Error while fetching egg production record ID={productionId} from the API.", ex);
            }
        }

        public async Task<EggProductionModel?> CreateAsync(EggProductionModel model)
        {
            try
            {
                model.UserId = _userId;
                model.FarmId = _farmId;

                var response = await _httpClient.PostAsJsonAsync(
                    $"{_baseApiUrl}api/EggProduction",
                    model
                );
                response.EnsureSuccessStatusCode();
                return await response.Content.ReadFromJsonAsync<EggProductionModel>();
            }
            catch (Exception ex)
            {
                throw new Exception("Error while creating a new egg production record via the API.", ex);
            }
        }

        public async Task UpdateAsync(int productionId, EggProductionModel model)
        {
            try
            {
                model.UserId = _userId;
                model.FarmId = _farmId;

                var response = await _httpClient.PutAsJsonAsync(
                    $"{_baseApiUrl}api/EggProduction/{productionId}",
                    model
                );
                response.EnsureSuccessStatusCode();
            }
            catch (Exception ex)
            {
                throw new Exception(
                    $"Error while updating egg production record ID={productionId} via the API.",
                    ex
                );
            }
        }

        public async Task DeleteAsync(int productionId)
        {
            try
            {
                var response = await _httpClient.DeleteAsync(
                    $"{_baseApiUrl}api/EggProduction/{productionId}?userId={_userId}&farmId={_farmId}"
                );
                response.EnsureSuccessStatusCode();
            }
            catch (Exception ex)
            {
                throw new Exception(
                    $"Error while deleting egg production record ID={productionId} via the API.",
                    ex
                );
            }
        }
    }
}
