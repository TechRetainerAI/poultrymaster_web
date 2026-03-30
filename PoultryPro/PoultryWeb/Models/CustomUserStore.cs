using Microsoft.AspNetCore.Identity;
using Newtonsoft.Json;
using PoultryWeb.Models;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text;

public class CustomUserStore : IUserStore<AppUser>, IUserPasswordStore<AppUser>
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<CustomUserStore> _logger;
    private readonly string _userProfileUrl;
    private readonly IConfiguration _configuration;

    public CustomUserStore(IHttpClientFactory httpClientFactory, IConfiguration configuration, ILogger<CustomUserStore> logger)
    {
        _httpClient = httpClientFactory.CreateClient();
        _configuration = configuration;
        _logger = logger;
        _userProfileUrl = configuration["LoginUrl"];
    }

    public async Task<IdentityResult> CreateAsync(AppUser user, CancellationToken cancellationToken)
    {
        var url = $"{_userProfileUrl}/api/UserProfile/create";
        try
        {
            var jsonContent = new StringContent(JsonConvert.SerializeObject(user), Encoding.UTF8, "application/json");
            var response = await _httpClient.PostAsync(url, jsonContent);

            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                var result = JsonConvert.DeserializeObject<IdentityResult>(content);
                return result ?? IdentityResult.Failed(new IdentityError { Description = "Failed to deserialize IdentityResult." });
            }
            else
            {
                var content = await response.Content.ReadAsStringAsync(); // 🔍  read the response body
                _logger.LogWarning("User creation failed: {StatusCode}, Response: {Content}", response.StatusCode, content);
                return IdentityResult.Failed(new IdentityError
                {
                    Description = $"API call failed. Status: {response.StatusCode}, Response: {content}"
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error occurred during user creation for {UserId}", user.Id);
            return IdentityResult.Failed(new IdentityError { Description = $"Exception during user creation: {ex.Message}" });
        }
    }

    public async Task<IdentityResult> DeleteAsync(AppUser user, CancellationToken cancellationToken)
    {
        var url = $"{_userProfileUrl}/api/UserProfile/{user.Id}";
        try
        {
            var response = await _httpClient.DeleteAsync(url);
            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                return JsonConvert.DeserializeObject<IdentityResult>(content);
            }
            else
            {
                return IdentityResult.Failed(new IdentityError { Description = $"API call failed with status code {response.StatusCode}" });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error occurred during user deletion for {UserId}", user.Id);
            return IdentityResult.Failed(new IdentityError { Description = $"Exception during user deletion: {ex.Message}" });
        }
    }

    public async Task<AppUser> FindByIdAsync(string userId, CancellationToken cancellationToken)
    {
        var url = $"{_userProfileUrl}/api/UserProfile/find?id={userId}";
        try
        {
            var response = await _httpClient.GetAsync(url);
            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                return JsonConvert.DeserializeObject<AppUser>(content);
            }
            return null;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error finding user by ID {UserId}", userId);
            return null;
        }
    }

    public async Task<AppUser> FindByNameAsync(string normalizedUserName, CancellationToken cancellationToken)
    {
        var url = $"{_userProfileUrl}/api/UserProfile/find/username/{normalizedUserName}";
        try
        {
            var response = await _httpClient.GetAsync(url);
            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                return JsonConvert.DeserializeObject<AppUser>(content);
            }
            return null;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error finding user by username {NormalizedUserName}", normalizedUserName);
            return null;
        }
    }

    public Task<string> GetNormalizedUserNameAsync(AppUser user, CancellationToken cancellationToken)
    {
        return Task.FromResult(user.NormalizedUserName);
    }

    public Task<string> GetUserIdAsync(AppUser user, CancellationToken cancellationToken)
    {
        return Task.FromResult(user.Id);
    }

    public Task<string> GetUserNameAsync(AppUser user, CancellationToken cancellationToken)
    {
        return Task.FromResult(user.UserName);
    }

    public Task SetNormalizedUserNameAsync(AppUser user, string normalizedName, CancellationToken cancellationToken)
    {
        user.NormalizedUserName = normalizedName;
        return Task.CompletedTask;
    }

    public Task SetUserNameAsync(AppUser user, string userName, CancellationToken cancellationToken)
    {
        user.UserName = userName;
        return Task.CompletedTask;
    }


    public async Task<IdentityResult> UpdateAsync(AppUser user, CancellationToken cancellationToken)
    {
        var url = $"{_userProfileUrl}/api/UserProfile/update";
        try
        {
            _logger.LogInformation("Sending update request to: {Url}", url);

            var jsonContent = new StringContent(JsonConvert.SerializeObject(user), Encoding.UTF8, "application/json");
            var response = await _httpClient.PutAsync(url, jsonContent);

            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                return JsonConvert.DeserializeObject<IdentityResult>(content);
            }
            else
            {
                var errorBody = await response.Content.ReadAsStringAsync();
                _logger.LogError("Update failed. Status: {Status}, Body: {Body}", response.StatusCode, errorBody);

                return IdentityResult.Failed(new IdentityError
                {
                    Description = $"API failed with status {response.StatusCode}. Details: {errorBody}"
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Exception while updating user {UserId}", user.Id);
            return IdentityResult.Failed(new IdentityError { Description = $"Exception: {ex.Message}" });
        }
    }


    public Task SetPasswordHashAsync(AppUser user, string passwordHash, CancellationToken cancellationToken)
    {
        user.PasswordHash = passwordHash;
        return Task.CompletedTask;
    }

    public Task<string> GetPasswordHashAsync(AppUser user, CancellationToken cancellationToken)
    {
        return Task.FromResult(user.PasswordHash);
    }

    public Task<bool> HasPasswordAsync(AppUser user, CancellationToken cancellationToken)
    {
        return Task.FromResult(!string.IsNullOrEmpty(user.PasswordHash));
    }

    //public async Task SetPasswordHashAsync(AppUser user, string passwordHash, CancellationToken cancellationToken)
    //{
    //    user.PasswordHash = passwordHash;   //No neeed to call the API
    //    //var url = $"{_userProfileUrl}/api/UserProfile/set-password-hash/{user.Id}";
    //    //try
    //    //{
    //    //    var jsonContent = new StringContent(JsonConvert.SerializeObject(passwordHash), Encoding.UTF8, "application/json");
    //    //    var response = await _httpClient.PostAsync(url, jsonContent);
    //    //    if (response.IsSuccessStatusCode)
    //    //    {
    //    //        user.PasswordHash = passwordHash;
    //    //    }
    //    //}
    //    //catch (Exception ex)
    //    //{
    //    //    _logger.LogError(ex, "Error setting password hash for {UserId}", user.Id);
    //    //}
    //}

    //public async Task<string> GetPasswordHashAsync(AppUser user, CancellationToken cancellationToken)
    //{
    //    return user.PasswordHash;
    //    //var url = $"{_userProfileUrl}/api/UserProfile/password-hash/{user.Id}";
    //    //try
    //    //{
    //    //    var response = await _httpClient.GetAsync(url);
    //    //    return response.IsSuccessStatusCode ? await response.Content.ReadAsStringAsync() : null;
    //    //}
    //    //catch (Exception ex)
    //    //{
    //    //    _logger.LogError(ex, "Error getting password hash for {UserId}", user.Id);
    //    //    return null;
    //    //}
    //}

    //public async Task<bool> HasPasswordAsync(AppUser user, CancellationToken cancellationToken)
    //{
    //    var url = $"{_userProfileUrl}/api/UserProfile/has-password/{user.Id}";
    //    try
    //    {
    //        var response = await _httpClient.GetAsync(url);
    //        if (response.IsSuccessStatusCode)
    //        {
    //            var content = await response.Content.ReadAsStringAsync();
    //            return JsonConvert.DeserializeObject<bool>(content);
    //        }
    //        return false;
    //    }
    //    catch (Exception ex)
    //    {
    //        _logger.LogError(ex, "Error checking if user {UserId} has password", user.Id);
    //        return false;
    //    }
    //}

    public void Dispose()
    {
        // clean up if needed
    }
}



//using Microsoft.AspNetCore.Identity;
//using PoultryWeb.Models;

//public class CustomUserStore : IUserStore<AppUser>, IUserPasswordStore<AppUser>
//{
//    // TODO: Replace with your own storage logic (e.g., DB, file, API call)

//    public Task<IdentityResult> CreateAsync(AppUser user)
//    {
//        // Your logic to create the user
//        return Task.FromResult(IdentityResult.Success);
//    }

//    public Task<IdentityResult> DeleteAsync(AppUser user)
//    {
//        // Your logic to delete the user
//        return Task.FromResult(IdentityResult.Success);
//    }

//    public Task<AppUser> FindByIdAsync(string userId)
//    {
//        // Your logic to find a user by ID
//        return Task.FromResult<AppUser>(null);
//    }

//    public Task<AppUser> FindByNameAsync(string normalizedUserName)
//    {
//        // Your logic to find a user by username
//        return Task.FromResult<AppUser>(null);
//    }

//    public Task<string> GetNormalizedUserNameAsync(AppUser user)
//    {
//        return Task.FromResult(user.UserName.ToUpperInvariant());
//    }

//    public Task<string> GetUserIdAsync(AppUser user)
//    {
//        return Task.FromResult(user.Id);
//    }

//    public Task<string> GetUserNameAsync(AppUser user)
//    {
//        return Task.FromResult(user.UserName);
//    }

//    public Task SetNormalizedUserNameAsync(AppUser user, string normalizedName)
//    {
//        user.UserName = normalizedName;
//        return Task.CompletedTask;
//    }

//    public Task SetUserNameAsync(AppUser user, string userName)
//    {
//        user.UserName = userName;
//        return Task.CompletedTask;
//    }

//    public Task<IdentityResult> UpdateAsync(AppUser user)
//    {
//        return Task.FromResult(IdentityResult.Success);
//    }

//    public Task SetPasswordHashAsync(AppUser user, string passwordHash)
//    {
//        user.PasswordHash = passwordHash;
//        return Task.CompletedTask;
//    }

//    public Task<string> GetPasswordHashAsync(AppUser user)
//    {
//        return Task.FromResult(user.PasswordHash);
//    }

//    public Task<bool> HasPasswordAsync(AppUser user)
//    {
//        return Task.FromResult(!string.IsNullOrEmpty(user.PasswordHash));
//    }

//    public void Dispose()
//    {
//        // clean up if needed
//    }
//}
