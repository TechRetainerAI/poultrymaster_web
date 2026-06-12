using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using PoultryWeb.Models;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Collections.Generic;
using System.Threading.Tasks;
using System;
using System.Net;
using Microsoft.Extensions.Logging;

namespace PoultryWeb.Business
{
    public class CustomerWebApiService : BaseApiService, ICustomerWebApiService
    {
        private readonly ILogger<CustomerWebApiService> _logger;

        public CustomerWebApiService(HttpClient httpClient, IConfiguration config,
                                   IHttpContextAccessor httpContextAccessor,
                                   ILogger<CustomerWebApiService> logger)
            : base(httpClient, config, httpContextAccessor)
        {
            _logger = logger;
            _logger.LogInformation("API Base: {BaseUrl}, UserId: {UserId}, FarmId: {FarmId}",
                _baseApiUrl, _userId, _farmId);
        }

       
        public async Task<List<CustomerModel>> GetAllAsync()
        {
            try
            {
                _logger.LogInformation("Fetching all customers for User: {UserId}, Firm: {FarmId}", _userId, _farmId);

                // Use the correct parameter names that the API expects
                var response = await _httpClient.GetAsync($"api/Customer?userId={Uri.EscapeDataString(_userId)}&farmId={Uri.EscapeDataString(_farmId)}");

                if (response.IsSuccessStatusCode)
                {
                    var customers = await response.Content.ReadFromJsonAsync<List<CustomerModel>>();
                    _logger.LogInformation("Retrieved {Count} customers", customers?.Count ?? 0);
                    return customers ?? new List<CustomerModel>();
                }
                else
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for GET All Customers. Error: {ErrorContent}",
                        response.StatusCode, errorContent);

                    throw new HttpRequestException($"API returned {response.StatusCode}: {errorContent}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching customers");
                throw;
            }
        }

        public async Task<CustomerModel?> GetByIdAsync(int customerId)
        {
            try
            {
                var response = await _httpClient.GetAsync($"api/Customer/{customerId}?userId={Uri.EscapeDataString(_userId)}&farmId={Uri.EscapeDataString(_farmId)}");

                if (response.IsSuccessStatusCode)
                {
                    return await response.Content.ReadFromJsonAsync<CustomerModel>();
                }
                else
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for GET Customer {CustomerId}. Error: {ErrorContent}",
                        response.StatusCode, customerId, errorContent);
                    return null;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching customer {CustomerId}", customerId);
                throw;
            }
        }

        public async Task<CustomerModel?> CreateAsync(CustomerModel model)
        {
            try
            {
                model.UserId = _userId;
                model.FarmId = _farmId;

                var response = await _httpClient.PostAsJsonAsync("api/Customer", model);

                if (response.IsSuccessStatusCode)
                {
                    return await response.Content.ReadFromJsonAsync<CustomerModel>();
                }
                else
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for CREATE Customer. Error: {ErrorContent}",
                        response.StatusCode, errorContent);
                    throw new HttpRequestException($"API returned {response.StatusCode}: {errorContent}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating customer");
                throw;
            }
        }

        public async Task UpdateAsync(int customerId, CustomerModel model)
        {
            try
            {
                model.UserId = _userId;
                model.FarmId = _farmId;

                var response = await _httpClient.PutAsJsonAsync($"api/Customer/{customerId}", model);

                if (!response.IsSuccessStatusCode)
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for UPDATE Customer {CustomerId}. Error: {ErrorContent}",
                        response.StatusCode, customerId, errorContent);
                    throw new HttpRequestException($"API returned {response.StatusCode}: {errorContent}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating customer {CustomerId}", customerId);
                throw;
            }
        }

        public async Task DeleteAsync(int customerId)
        {
            try
            {
                var response = await _httpClient.DeleteAsync($"api/Customer/{customerId}?userId={Uri.EscapeDataString(_userId)}&farmId={Uri.EscapeDataString(_farmId)}");

                if (!response.IsSuccessStatusCode)
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for DELETE Customer {CustomerId}. Error: {ErrorContent}",
                        response.StatusCode, customerId, errorContent);
                    throw new HttpRequestException($"API returned {response.StatusCode}: {errorContent}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting customer {CustomerId}", customerId);
                throw;
            }
        }
    }
}