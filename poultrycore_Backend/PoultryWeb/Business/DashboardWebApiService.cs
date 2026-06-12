using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using PoultryWeb.Models;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Threading.Tasks;
using System;

namespace PoultryWeb.Business
{
    public class DashboardWebApiService : IDashboardWebApiService
    {
        private readonly HttpClient _httpClient;
        private readonly string _baseApiUrl;
        private readonly string _userId;
        private readonly string _farmId;

        public DashboardWebApiService(HttpClient httpClient, IConfiguration config, IHttpContextAccessor httpContextAccessor)
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

        public async Task<DashboardViewModel> GetDashboardSummaryAsync()
        {
            var result = await _httpClient.GetFromJsonAsync<DashboardViewModel>(
                $"{_baseApiUrl}api/Dashboard/Summary?farmId={_farmId}"
            );
            return result ?? new DashboardViewModel();
        }
    }
}
