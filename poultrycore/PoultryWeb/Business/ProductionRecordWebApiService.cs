using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using PoultryWeb.Models;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Collections.Generic;
using System.Threading.Tasks;
using System;

namespace PoultryWeb.Business
{
    public class ProductionRecordWebApiService : IProductionRecordWebApiService
    {
        private readonly HttpClient _httpClient;
        private readonly string _baseApiUrl;
        private readonly string _userId;
        private readonly string _farmId;

        public ProductionRecordWebApiService(HttpClient httpClient, IConfiguration config, IHttpContextAccessor httpContextAccessor)
        {
            _httpClient = httpClient;
            _baseApiUrl = config["PoultryFarmApiUrl"] ?? "https://localhost:7190/";

            var user = httpContextAccessor.HttpContext?.User;
            _userId = user?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            _farmId = user?.FindFirst("FarmId")?.Value;

            if (string.IsNullOrEmpty(_userId))
                throw new Exception("UserId is missing from the current user's claims.");

            if (string.IsNullOrEmpty(_farmId))
                throw new Exception("FarmId is missing from the current user's claims.");
        }

        public async Task<List<ProductionRecordViewModel>> GetAllAsync()
        {
            var records = await _httpClient.GetFromJsonAsync<List<ProductionRecordViewModel>>(
                $"{_baseApiUrl}api/ProductionRecord?userId={_userId}&farmId={_farmId}"
            );
            return records ?? new List<ProductionRecordViewModel>();
        }

        public async Task<ProductionRecordViewModel?> GetByIdAsync(int id)
        {
            return await _httpClient.GetFromJsonAsync<ProductionRecordViewModel>(
                $"{_baseApiUrl}api/ProductionRecord/{id}?userId={_userId}&farmId={_farmId}"
            );
        }

        public async Task<ProductionRecordViewModel?> CreateAsync(ProductionRecordViewModel model)
        {
            model.FarmId = _farmId;
            model.UserId = _userId;
            model.UpdatedBy = _userId;
            model.CreatedBy = _userId;

            var response = await _httpClient.PostAsJsonAsync(
                $"{_baseApiUrl}api/ProductionRecord", model
            );
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadFromJsonAsync<ProductionRecordViewModel>();
        }

        public async Task UpdateAsync(int id, ProductionRecordViewModel model)
        {
            model.UserId = _userId;
            model.FarmId = _farmId;
            model.UpdatedBy = _userId;
            model.CreatedBy = _userId;

            var response = await _httpClient.PutAsJsonAsync(
                $"{_baseApiUrl}api/ProductionRecord/{id}", model
            );
            response.EnsureSuccessStatusCode();
        }

        public async Task DeleteAsync(int id)
        {
            var response = await _httpClient.DeleteAsync(
                $"{_baseApiUrl}api/ProductionRecord/{id}?userId={_userId}&farmId={_farmId}"
            );
            response.EnsureSuccessStatusCode();
        }
    }
}
