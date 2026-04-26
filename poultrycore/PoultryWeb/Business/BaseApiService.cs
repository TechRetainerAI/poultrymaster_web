using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using System.Security.Claims;

namespace PoultryWeb.Business
{
    public abstract class BaseApiService
    {
        protected readonly HttpClient _httpClient;
        protected readonly string _baseApiUrl;
        protected readonly string _userId;
        protected readonly string _farmId;
        protected readonly IHttpContextAccessor _httpContextAccessor;

        protected BaseApiService(HttpClient httpClient, IConfiguration configuration, IHttpContextAccessor httpContextAccessor)
        {
            _httpClient = httpClient;
            _httpContextAccessor = httpContextAccessor;
            _baseApiUrl = configuration["PoultryFarmApiUrl"] ?? "https://localhost:7190/";

            // Set the base address for HttpClient
            _httpClient.BaseAddress = new Uri(_baseApiUrl);

            var user = httpContextAccessor.HttpContext?.User;
            _userId = user?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            _farmId = user?.FindFirst("FarmId")?.Value;

            if (string.IsNullOrEmpty(_userId))
                throw new Exception("UserId is missing from the current user's claims.");

            if (string.IsNullOrEmpty(_farmId))
                throw new Exception("FarmId is missing from the current user's claims.");

            // Add JWT token to all requests if available
            AddAuthenticationHeader();
        }

        protected void AddAuthenticationHeader()
        {
            var httpContext = _httpContextAccessor.HttpContext;
            if (httpContext != null)
            {
                // Try to get token from Authorization header first
                var authHeader = httpContext.Request.Headers["Authorization"].FirstOrDefault();
                if (!string.IsNullOrEmpty(authHeader) && authHeader.StartsWith("Bearer "))
                {
                    var token = authHeader.Substring("Bearer ".Length);
                    _httpClient.DefaultRequestHeaders.Authorization = 
                        new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
                    return;
                }

                // Try to get token from cookies (if using cookie-based auth)
                var tokenCookie = httpContext.Request.Cookies["auth_token"];
                if (!string.IsNullOrEmpty(tokenCookie))
                {
                    _httpClient.DefaultRequestHeaders.Authorization = 
                        new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", tokenCookie);
                }
            }
        }
    }
}
