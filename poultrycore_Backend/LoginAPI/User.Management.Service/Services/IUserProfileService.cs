using System;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity;
using User.Management.Data.Models;

public interface IUserProfileService : IDisposable
{
    Task<IdentityResult> CreateAsync(ApplicationUser user);
    Task<IdentityResult> UpdateAsync(ApplicationUser user);
    Task<IdentityResult> DeleteAsync(string userId);
    Task<ApplicationUser> FindByIdAsync(string userId);
    Task<ApplicationUser> FindByNameAsync(string normalizedUserName);
    Task<string> GetNormalizedUserNameAsync(ApplicationUser user);
    Task<string> GetUserIdAsync(ApplicationUser user);
    Task<string> GetUserNameAsync(ApplicationUser user);
    Task SetNormalizedUserNameAsync(ApplicationUser user, string normalizedName);
    Task SetUserNameAsync(ApplicationUser user, string userName);
    Task SetPasswordHashAsync(ApplicationUser user, string passwordHash);
    Task<string> GetPasswordHashAsync(ApplicationUser user);
    Task<bool> HasPasswordAsync(ApplicationUser user);
}
