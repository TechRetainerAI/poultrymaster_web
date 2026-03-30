using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using PoultryWeb.Models;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Collections.Generic;
using System.Threading.Tasks;
using PoultryWeb.Business;
using System;

namespace PoultryWeb.Business
{
    public class ReportWebApiService : IReportWebApiService
    {
        private readonly HttpClient _httpClient;
        private readonly string _apiBaseUrl;
        private readonly string _userId;
        private readonly string _farmId;

        public ReportWebApiService(HttpClient httpClient, IConfiguration config, IHttpContextAccessor httpContextAccessor)
        {
            _httpClient = httpClient;
            _apiBaseUrl = config["PoultryFarmApiUrl"] ?? "https://localhost:7190/";

            var httpContext = httpContextAccessor.HttpContext;

            // Retrieve the current user's ID and FarmId from the claims.
            _userId = httpContext?.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            _farmId = httpContext?.User.FindFirst("FarmId")?.Value;

            if (string.IsNullOrEmpty(_userId))
                throw new Exception("UserId is missing from the current user's claims.");
            if (string.IsNullOrEmpty(_farmId))
                throw new Exception("FarmId is missing from the current user's claims.");
        }

        public async Task<byte[]> ExportCsvAsync(ReportRequestModel request)
        {
            request.UserId = _userId;
            request.FarmId = _farmId;

            var response = await _httpClient.PostAsJsonAsync($"{_apiBaseUrl}api/report/export/csv", request);
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadAsByteArrayAsync();
        }

        public async Task<byte[]> ExportPdfAsync(ReportRequestModel request)
        {
            request.UserId = _userId;
            request.FarmId = _farmId;

            var response = await _httpClient.PostAsJsonAsync($"{_apiBaseUrl}api/report/export/pdf", request);
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadAsByteArrayAsync();
        }

        public async Task<byte[]> ExportExcelAsync(ReportRequestModel request)
        {
            request.UserId = _userId;
            request.FarmId = _farmId;

            var response = await _httpClient.PostAsJsonAsync($"{_apiBaseUrl}api/report/export/excel", request);
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadAsByteArrayAsync();
        }
    }
}
