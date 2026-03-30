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
    public class ExpenseWebApiService : IExpenseWebApiService
    {
        private readonly HttpClient _httpClient;
        private readonly string _baseApiUrl;
        private readonly string _userId;
        private readonly string _farmId;

        public ExpenseWebApiService(HttpClient httpClient, IConfiguration config, IHttpContextAccessor httpContextAccessor)
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

        public async Task<List<ExpenseModel>> GetAllAsync()
        {
            var expenses = await _httpClient.GetFromJsonAsync<List<ExpenseModel>>(
                $"{_baseApiUrl}api/Expense?userId={_userId}&farmId={_farmId}"
            );
            return expenses ?? new List<ExpenseModel>();
        }

        public async Task<ExpenseModel?> GetByIdAsync(int expenseId)
        {
            return await _httpClient.GetFromJsonAsync<ExpenseModel>(
                $"{_baseApiUrl}api/Expense/{expenseId}?userId={_userId}&farmId={_farmId}"
            );
        }

        public async Task<ExpenseModel?> CreateAsync(ExpenseModel model)
        {
            model.UserId = _userId;
            model.FarmId = _farmId;
            var response = await _httpClient.PostAsJsonAsync(
                $"{_baseApiUrl}api/Expense", model
            );
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadFromJsonAsync<ExpenseModel>();
        }

        public async Task UpdateAsync(int expenseId, ExpenseModel model)
        {
            model.UserId = _userId;
            model.FarmId = _farmId;
            var response = await _httpClient.PutAsJsonAsync(
                $"{_baseApiUrl}api/Expense/{expenseId}", model
            );
            response.EnsureSuccessStatusCode();
        }

        public async Task DeleteAsync(int expenseId)
        {
            var response = await _httpClient.DeleteAsync(
                $"{_baseApiUrl}api/Expense/{expenseId}?userId={_userId}&farmId={_farmId}"
            );
            response.EnsureSuccessStatusCode();
        }

        public async Task<List<ExpenseModel>> GetByFlockAsync(int flockId)
        {
            var expenses = await _httpClient.GetFromJsonAsync<List<ExpenseModel>>(
                $"{_baseApiUrl}api/Expense/ByFlock/{flockId}?userId={_userId}&farmId={_farmId}"
            );
            return expenses ?? new List<ExpenseModel>();
        }
    }
}
