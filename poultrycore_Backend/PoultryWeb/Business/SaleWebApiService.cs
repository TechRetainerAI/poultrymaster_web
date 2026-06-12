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
    public class SaleWebApiService : ISaleWebApiService
    {
        private readonly HttpClient _httpClient;
        private readonly string _baseApiUrl;
        private readonly string _userId;
        private readonly string _farmId;

        public SaleWebApiService(HttpClient httpClient, IConfiguration config, IHttpContextAccessor httpContextAccessor)
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

        public async Task<List<SaleModel>> GetAllAsync()
        {
            var sales = await _httpClient.GetFromJsonAsync<List<SaleModel>>(
                $"{_baseApiUrl}api/Sale?userId={_userId}&farmId={_farmId}"
            );
            return sales ?? new List<SaleModel>();
        }

        public async Task<SaleModel?> GetByIdAsync(int saleId)
        {
            return await _httpClient.GetFromJsonAsync<SaleModel>(
                $"{_baseApiUrl}api/Sale/{saleId}?userId={_userId}&farmId={_farmId}"
            );
        }

        public async Task<SaleModel?> CreateAsync(SaleModel model)
        {
            model.UserId = _userId;
            model.FarmId = _farmId;

            var response = await _httpClient.PostAsJsonAsync(
                $"{_baseApiUrl}api/Sale", model
            );
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadFromJsonAsync<SaleModel>();
        }

        public async Task UpdateAsync(int saleId, SaleModel model)
        {
            model.UserId = _userId;
            model.FarmId = _farmId;

            var response = await _httpClient.PutAsJsonAsync(
                $"{_baseApiUrl}api/Sale/{saleId}", model
            );
            response.EnsureSuccessStatusCode();
        }

        public async Task DeleteAsync(int saleId)
        {
            var response = await _httpClient.DeleteAsync(
                $"{_baseApiUrl}api/Sale/{saleId}?userId={_userId}&farmId={_farmId}"
            );
            response.EnsureSuccessStatusCode();
        }

        public async Task<List<SaleModel>> GetByFlockAsync(int flockId)
        {
            var sales = await _httpClient.GetFromJsonAsync<List<SaleModel>>(
                $"{_baseApiUrl}api/Sale/ByFlock/{flockId}?userId={_userId}&farmId={_farmId}"
            );
            return sales ?? new List<SaleModel>();
        }
    }
}
