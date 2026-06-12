using PoultryWeb.Business;
using PoultryWeb.Models;
using System.Security.Claims;

public class InventoryWebApiService : IInventoryWebApiService
{
    private readonly HttpClient _httpClient;
    private readonly string _baseApiUrl;
    private readonly string _userId;
    private readonly string _farmId;

    public InventoryWebApiService(HttpClient httpClient, IConfiguration config, IHttpContextAccessor httpContextAccessor)
    {
        _httpClient = httpClient;
        _baseApiUrl = config["PoultryFarmApiUrl"] ?? "https://localhost:7190/";

        var user = httpContextAccessor.HttpContext?.User;

        _userId = user?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        _farmId = user?.FindFirst("FarmId")?.Value; // Ensure "FarmId" claim is present

        if (string.IsNullOrEmpty(_userId))
            throw new Exception("UserId is missing from the current user's claims.");
        if (string.IsNullOrEmpty(_farmId))
            throw new Exception("FarmId is missing from the current user's claims.");
    }

    //public async Task<List<InventoryItemModel>> GetAllItemsAsync()
    //{
    //    return await _httpClient.GetFromJsonAsync<List<InventoryItemModel>>(
    //        $"{_baseApiUrl}api/InventoryItem?userId={_userId}&farmId={_farmId}"
    //    ) ?? new();
    //}

    public async Task<List<InventoryItemModel>> GetAllItemsAsync()
    {
        var url = $"{_baseApiUrl}api/InventoryItem?userId={_userId}&farmId={_farmId}";
        return await _httpClient.GetFromJsonAsync<List<InventoryItemModel>>(url) ?? new();
    }


    public async Task<InventoryItemModel?> GetItemByIdAsync(int id)
    {
        return await _httpClient.GetFromJsonAsync<InventoryItemModel>(
            $"{_baseApiUrl}api/InventoryItem/{id}?userId={_userId}&farmId={_farmId}"
        );
    }

    public async Task CreateItemAsync(InventoryItemModel model)
    {
        model.UserId = _userId;
        model.FarmId = _farmId;
        var response = await _httpClient.PostAsJsonAsync(
            $"{_baseApiUrl}api/InventoryItem", model
        );
        response.EnsureSuccessStatusCode();
    }

    public async Task UpdateItemAsync(int id, InventoryItemModel model)
    {
        model.UserId = _userId;
        model.FarmId = _farmId;
        var response = await _httpClient.PutAsJsonAsync(
            $"{_baseApiUrl}api/InventoryItem/{id}", model
        );
        response.EnsureSuccessStatusCode();
    }

    public async Task DeleteItemAsync(int id)
    {
        var response = await _httpClient.DeleteAsync(
            $"{_baseApiUrl}api/InventoryItem/{id}?userId={_userId}&farmId={_farmId}"
        );
        response.EnsureSuccessStatusCode();
    }

    public async Task<List<InventoryTransactionModel>> GetTransactionsByItemAsync(int itemId)
    {
        return await _httpClient.GetFromJsonAsync<List<InventoryTransactionModel>>(
            $"{_baseApiUrl}api/InventoryTransaction/ByItem/{itemId}?userId={_userId}&farmId={_farmId}"
        ) ?? new();
    }

    public async Task CreateTransactionAsync(InventoryTransactionModel model)
    {
        model.UserId = _userId;
        model.FarmId = _farmId;
        var response = await _httpClient.PostAsJsonAsync(
            $"{_baseApiUrl}api/InventoryTransaction", model
        );
        response.EnsureSuccessStatusCode();
    }
}
