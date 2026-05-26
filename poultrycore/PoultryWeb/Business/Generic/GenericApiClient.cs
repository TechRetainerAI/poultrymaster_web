using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using PoultryWeb.Models.Generic;
using System.Net.Http.Json;
using System.Text.Json;

namespace PoultryWeb.Business.Generic
{
    // Single typed HttpClient for the entire Generic Company API surface.
    // Inherits FarmId / JWT resolution from BaseApiService.
    public class GenericApiClient : BaseApiService, IGenericApiClient
    {
        private readonly ILogger<GenericApiClient> _logger;

        // API emits camelCase JSON; we deserialize into PascalCase POCOs.
        // System.Text.Json default options for ReadFromJsonAsync are
        // case-insensitive, so this Just Works for reads. For writes, we
        // pass POCOs and let the framework serialize.
        private static readonly JsonSerializerOptions _json = new(JsonSerializerDefaults.Web);

        public GenericApiClient(HttpClient httpClient, IConfiguration config,
                                IHttpContextAccessor httpContextAccessor,
                                ILogger<GenericApiClient> logger)
            : base(httpClient, config, httpContextAccessor)
        {
            _logger = logger;
        }

        private string Base(string suffix = "") => $"api/generic-company/{Uri.EscapeDataString(_farmId)}{suffix}";

        // =====================================================================
        // Foundation
        // =====================================================================
        public async Task<List<BusinessCategoryVm>> GetBusinessCategoriesAsync()
        {
            var resp = await _httpClient.GetAsync("api/business-categories");
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "GetBusinessCategories"); return new(); }
            return await resp.Content.ReadFromJsonAsync<List<BusinessCategoryVm>>(_json) ?? new();
        }

        public async Task<GenericCompanyProfileVm?> GetProfileAsync()
        {
            var resp = await _httpClient.GetAsync(Base());
            if (resp.StatusCode == System.Net.HttpStatusCode.NotFound) return null;
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "GetProfile"); return null; }
            return await resp.Content.ReadFromJsonAsync<GenericCompanyProfileVm>(_json);
        }

        public async Task<GenericCompanyProfileVm?> SetupAsync(GenericCompanySetupRequestVm req)
        {
            req.FarmId = _farmId;
            var resp = await _httpClient.PostAsJsonAsync("api/generic-company/setup", req, _json);
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "Setup"); return null; }
            return await resp.Content.ReadFromJsonAsync<GenericCompanyProfileVm>(_json);
        }

        public async Task<List<GenericProductVm>> GetProductsAsync()
        {
            var resp = await _httpClient.GetAsync(Base("/products"));
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "GetProducts"); return new(); }
            return await resp.Content.ReadFromJsonAsync<List<GenericProductVm>>(_json) ?? new();
        }

        public async Task<List<GenericCashAccountVm>> GetCashAccountsAsync()
        {
            var resp = await _httpClient.GetAsync(Base("/cash-accounts"));
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "GetCashAccounts"); return new(); }
            return await resp.Content.ReadFromJsonAsync<List<GenericCashAccountVm>>(_json) ?? new();
        }

        // =====================================================================
        // Customers + Suppliers
        // =====================================================================
        public async Task<List<GenericCustomerVm>> GetCustomersAsync()
        {
            var resp = await _httpClient.GetAsync(Base("/customers"));
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "GetCustomers"); return new(); }
            return await resp.Content.ReadFromJsonAsync<List<GenericCustomerVm>>(_json) ?? new();
        }

        public async Task<GenericCustomerVm?> CreateCustomerAsync(GenericCustomerVm m)
        {
            var resp = await _httpClient.PostAsJsonAsync(Base("/customers"), m, _json);
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "CreateCustomer"); return null; }
            return await resp.Content.ReadFromJsonAsync<GenericCustomerVm>(_json);
        }

        public async Task<List<GenericSupplierVm>> GetSuppliersAsync()
        {
            var resp = await _httpClient.GetAsync(Base("/suppliers"));
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "GetSuppliers"); return new(); }
            return await resp.Content.ReadFromJsonAsync<List<GenericSupplierVm>>(_json) ?? new();
        }

        public async Task<GenericSupplierVm?> CreateSupplierAsync(GenericSupplierVm m)
        {
            var resp = await _httpClient.PostAsJsonAsync(Base("/suppliers"), m, _json);
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "CreateSupplier"); return null; }
            return await resp.Content.ReadFromJsonAsync<GenericSupplierVm>(_json);
        }

        // =====================================================================
        // Sales
        // =====================================================================
        public async Task<List<GenericSaleVm>> GetSalesAsync(string? status)
        {
            var url = Base("/sales") + (status is null ? "" : $"?status={Uri.EscapeDataString(status)}");
            var resp = await _httpClient.GetAsync(url);
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "GetSales"); return new(); }
            return await resp.Content.ReadFromJsonAsync<List<GenericSaleVm>>(_json) ?? new();
        }

        public async Task<GenericSaleVm?> GetSaleAsync(int id)
        {
            var resp = await _httpClient.GetAsync(Base($"/sales/{id}"));
            if (resp.StatusCode == System.Net.HttpStatusCode.NotFound) return null;
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "GetSale"); return null; }
            return await resp.Content.ReadFromJsonAsync<GenericSaleVm>(_json);
        }

        public async Task<int> CreateSaleAsync(GenericSaleCreateVm req)
        {
            var resp = await _httpClient.PostAsJsonAsync(Base("/sales"), req, _json);
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "CreateSale"); return 0; }
            var created = await resp.Content.ReadFromJsonAsync<GenericSaleVm>(_json);
            return created?.GenericSaleId ?? 0;
        }

        public async Task ApproveSaleAsync(int id)
        {
            var resp = await _httpClient.PostAsync(Base($"/sales/{id}/approve"), content: null);
            if (!resp.IsSuccessStatusCode) LogFail(resp, "ApproveSale");
        }

        public async Task CancelSaleAsync(int id, string? reason)
        {
            var body = new { reason };
            var resp = await _httpClient.PostAsJsonAsync(Base($"/sales/{id}/cancel"), body, _json);
            if (!resp.IsSuccessStatusCode) LogFail(resp, "CancelSale");
        }

        // =====================================================================
        // Purchases + Expenses
        // =====================================================================
        public async Task<List<GenericPurchaseVm>> GetPurchasesAsync(string? status)
        {
            var url = Base("/purchases") + (status is null ? "" : $"?status={Uri.EscapeDataString(status)}");
            var resp = await _httpClient.GetAsync(url);
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "GetPurchases"); return new(); }
            return await resp.Content.ReadFromJsonAsync<List<GenericPurchaseVm>>(_json) ?? new();
        }

        public async Task ApprovePurchaseAsync(int id)
        {
            var resp = await _httpClient.PostAsync(Base($"/purchases/{id}/approve"), content: null);
            if (!resp.IsSuccessStatusCode) LogFail(resp, "ApprovePurchase");
        }

        public async Task<List<GenericExpenseVm>> GetExpensesAsync(string? status)
        {
            var url = Base("/expenses") + (status is null ? "" : $"?status={Uri.EscapeDataString(status)}");
            var resp = await _httpClient.GetAsync(url);
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "GetExpenses"); return new(); }
            return await resp.Content.ReadFromJsonAsync<List<GenericExpenseVm>>(_json) ?? new();
        }

        public async Task ApproveExpenseAsync(int id)
        {
            var resp = await _httpClient.PostAsync(Base($"/expenses/{id}/approve"), content: null);
            if (!resp.IsSuccessStatusCode) LogFail(resp, "ApproveExpense");
        }

        // =====================================================================
        // Daily Closings
        // =====================================================================
        public async Task<List<GenericDailyClosingVm>> GetDailyClosingsAsync()
        {
            var resp = await _httpClient.GetAsync(Base("/daily-closings"));
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "GetDailyClosings"); return new(); }
            return await resp.Content.ReadFromJsonAsync<List<GenericDailyClosingVm>>(_json) ?? new();
        }

        public async Task<int> CreateDailyClosingAsync(GenericDailyClosingCreateVm req)
        {
            var resp = await _httpClient.PostAsJsonAsync(Base("/daily-closings"), req, _json);
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "CreateDailyClosing"); return 0; }
            var created = await resp.Content.ReadFromJsonAsync<GenericDailyClosingVm>(_json);
            return created?.GenericDailyClosingId ?? 0;
        }

        public async Task SubmitDailyClosingAsync(int id)
        {
            var resp = await _httpClient.PostAsJsonAsync(
                Base($"/daily-closings/{id}/submit"), new { }, _json);
            if (!resp.IsSuccessStatusCode) LogFail(resp, "SubmitDailyClosing");
        }

        public async Task ApproveDailyClosingAsync(int id)
        {
            var resp = await _httpClient.PostAsync(Base($"/daily-closings/{id}/approve"), content: null);
            if (!resp.IsSuccessStatusCode) LogFail(resp, "ApproveDailyClosing");
        }

        // =====================================================================
        // Dashboard
        // =====================================================================
        public async Task<GenericDashboardVm> GetDashboardAsync()
        {
            var resp = await _httpClient.GetAsync(Base("/reports/dashboard"));
            if (!resp.IsSuccessStatusCode) { LogFail(resp, "GetDashboard"); return new(); }
            return await resp.Content.ReadFromJsonAsync<GenericDashboardVm>(_json) ?? new();
        }

        // =====================================================================
        private void LogFail(HttpResponseMessage resp, string op)
        {
            var body = resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            _logger.LogWarning("Generic API {Op} returned {Status}: {Body}", op, resp.StatusCode, body);
        }
    }
}
