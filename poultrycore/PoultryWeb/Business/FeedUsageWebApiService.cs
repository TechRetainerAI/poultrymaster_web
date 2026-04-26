using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using PoultryWeb.Models;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Collections.Generic;
using System.Threading.Tasks;
using System;
using Microsoft.Extensions.Logging;

namespace PoultryWeb.Business
{
    public class FeedUsageWebApiService : BaseApiService, IFeedUsageWebApiService
    {
        private readonly ILogger<FeedUsageWebApiService> _logger;

        public FeedUsageWebApiService(HttpClient httpClient, IConfiguration configuration, 
                                     IHttpContextAccessor httpContextAccessor,
                                     ILogger<FeedUsageWebApiService> logger)
            : base(httpClient, configuration, httpContextAccessor)
        {
            _logger = logger;
            _logger.LogInformation("FeedUsageWebApiService initialized - UserId: {UserId}, FarmId: {FarmId}", 
                _userId, _farmId);
        }

        public async Task<List<FeedUsageModel>> GetAllAsync()
        {
            try
            {
                _logger.LogInformation("Fetching all feed usage for User: {UserId}, Farm: {FarmId}", _userId, _farmId);

                var response = await _httpClient.GetAsync($"api/FeedUsage?userId={Uri.EscapeDataString(_userId)}&farmId={Uri.EscapeDataString(_farmId)}");

                if (response.IsSuccessStatusCode)
                {
                    var feedUsage = await response.Content.ReadFromJsonAsync<List<FeedUsageModel>>();
                    _logger.LogInformation("Retrieved {Count} feed usage records", feedUsage?.Count ?? 0);
                    return feedUsage ?? new List<FeedUsageModel>();
                }
                else
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for GET All FeedUsage. Error: {ErrorContent}",
                        response.StatusCode, errorContent);
                    throw new HttpRequestException($"API returned {response.StatusCode}: {errorContent}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching feed usage records");
                throw;
            }
        }

        public async Task<FeedUsageModel?> GetByIdAsync(int feedUsageId)
        {
            try
            {
                var response = await _httpClient.GetAsync($"api/FeedUsage/{feedUsageId}?userId={Uri.EscapeDataString(_userId)}&farmId={Uri.EscapeDataString(_farmId)}");

                if (response.IsSuccessStatusCode)
                {
                    return await response.Content.ReadFromJsonAsync<FeedUsageModel>();
                }
                else
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for GET FeedUsage {FeedUsageId}. Error: {ErrorContent}",
                        response.StatusCode, feedUsageId, errorContent);
                    return null;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching feed usage {FeedUsageId}", feedUsageId);
                throw;
            }
        }

        public async Task<FeedUsageModel?> CreateAsync(FeedUsageModel model)
        {
            try
            {
                // Log BEFORE setting values
                _logger.LogWarning("BEFORE setting - model.UserId: '{ModelUserId}', model.FarmId: '{ModelFarmId}'", 
                    model.UserId ?? "NULL", model.FarmId ?? "NULL");
                
                model.UserId = _userId;
                model.FarmId = _farmId;

                // Log AFTER setting values
                _logger.LogWarning("AFTER setting - model.UserId: '{ModelUserId}', model.FarmId: '{ModelFarmId}'", 
                    model.UserId ?? "NULL", model.FarmId ?? "NULL");
                _logger.LogWarning("Service fields - _userId: '{UserId}', _farmId: '{FarmId}'", 
                    _userId ?? "NULL", _farmId ?? "NULL");

                // Serialize to see what's being sent
                var json = System.Text.Json.JsonSerializer.Serialize(model);
                _logger.LogWarning("JSON being sent to API: {Json}", json);

                var response = await _httpClient.PostAsJsonAsync("api/FeedUsage", model);

                if (response.IsSuccessStatusCode)
                {
                    _logger.LogInformation("Feed usage created successfully");
                    return await response.Content.ReadFromJsonAsync<FeedUsageModel>();
                }
                else
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for CREATE FeedUsage. Error: {ErrorContent}",
                        response.StatusCode, errorContent);
                    throw new HttpRequestException($"API returned {response.StatusCode}: {errorContent}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating feed usage");
                throw;
            }
        }

        public async Task UpdateAsync(int feedUsageId, FeedUsageModel model)
        {
            try
            {
                model.UserId = _userId;
                model.FarmId = _farmId;

                var response = await _httpClient.PutAsJsonAsync($"api/FeedUsage/{feedUsageId}", model);

                if (!response.IsSuccessStatusCode)
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for UPDATE FeedUsage {FeedUsageId}. Error: {ErrorContent}",
                        response.StatusCode, feedUsageId, errorContent);
                    throw new HttpRequestException($"API returned {response.StatusCode}: {errorContent}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating feed usage {FeedUsageId}", feedUsageId);
                throw;
            }
        }

        public async Task DeleteAsync(int feedUsageId)
        {
            try
            {
                var response = await _httpClient.DeleteAsync($"api/FeedUsage/{feedUsageId}?userId={Uri.EscapeDataString(_userId)}&farmId={Uri.EscapeDataString(_farmId)}");

                if (!response.IsSuccessStatusCode)
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for DELETE FeedUsage {FeedUsageId}. Error: {ErrorContent}",
                        response.StatusCode, feedUsageId, errorContent);
                    throw new HttpRequestException($"API returned {response.StatusCode}: {errorContent}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting feed usage {FeedUsageId}", feedUsageId);
                throw;
            }
        }
    }
}
