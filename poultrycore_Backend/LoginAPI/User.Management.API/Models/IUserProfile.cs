using Microsoft.AspNetCore.Identity;
using User.Management.Data.Models;

public interface IUserProfile
{
    Task<IdentityResult> CreateUserAsync(ApplicationUser user);
    Task<IdentityResult> UpdateUserAsync(ApplicationUser user);
    Task<IdentityResult> DeleteUserAsync(string userId);
    Task<ApplicationUser> FindByIdAsync(string userId);
    Task<ApplicationUser> FindByNameAsync(string normalizedUserName);
    Task<string> GetPasswordHashAsync(string userId);
    Task<bool> HasPasswordAsync(string userId);
    Task<bool> SetPasswordHashAsync(string userId, string hash);
}
