using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using PoultryWeb.Business;
using PoultryWeb.Models;

namespace PoultryFarmApp.Business
{
    public class FlockWebApiService : BaseApiService, IFlockWebApiService
    {
        public FlockWebApiService(HttpClient httpClient, IConfiguration configuration, IHttpContextAccessor httpContextAccessor)
            : base(httpClient, configuration, httpContextAccessor)
        {
        }

        public async Task<List<FlockModel>> GetAllFlocksAsync()
        {
            var result = await _httpClient.GetFromJsonAsync<List<FlockModel>>(
                $"api/Flock?userId={_userId}&farmId={_farmId}"
            );
            return result ?? new List<FlockModel>();
        }

        public async Task<FlockModel> GetFlockByIdAsync(int id)
        {
            return await _httpClient.GetFromJsonAsync<FlockModel>(
                $"api/Flock/{id}?userId={_userId}&farmId={_farmId}"
            );
        }

        public async Task<FlockModel> CreateFlockAsync(FlockModel flock)
        {
            flock.UserId = _userId;
            flock.FarmId = _farmId;

            var response = await _httpClient.PostAsJsonAsync(
                "api/Flock",
                flock
            );
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadFromJsonAsync<FlockModel>();
        }

        public async Task UpdateFlockAsync(int id, FlockModel flock)
        {
            flock.UserId = _userId;
            flock.FarmId = _farmId;

            var response = await _httpClient.PutAsJsonAsync(
                $"api/Flock/{id}",
                flock
            );
            response.EnsureSuccessStatusCode();
        }

        public async Task DeleteFlockAsync(int id)
        {
            var response = await _httpClient.DeleteAsync(
                $"api/Flock/{id}?userId={_userId}&farmId={_farmId}"
            );
            response.EnsureSuccessStatusCode();
        }
    }
}
