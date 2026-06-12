using Microsoft.AspNetCore.Identity;
using User.Management.Data;
using User.Management.Data.Models;

namespace User.Management.Service.Services
{
    public class UserProfileService : IUserProfileService
    {
        private readonly IUserProfileDAL _userProfileDal; // Or your own DAL logic

        public UserProfileService(IUserProfileDAL UserProfileDal)
        {
            _userProfileDal = UserProfileDal;
        }

        public async Task<IdentityResult> CreateAsync(ApplicationUser user)
        {
            var success = await _userProfileDal.CreateUserAsync(user);
            return success ? IdentityResult.Success : IdentityResult.Failed(new IdentityError { Description = "Failed to create user" });
        }

        public async Task<IdentityResult> UpdateAsync(ApplicationUser user)
        {
            var updatedUser = await _userProfileDal.UpdateUserAsync(user);
            return updatedUser != null ? IdentityResult.Success : IdentityResult.Failed(new IdentityError { Description = "Failed to update user" });
        }

        public async Task<IdentityResult> DeleteAsync(string userId)
        {
            var success = await _userProfileDal.DeleteUserByIdAsync(userId);
            return success ? IdentityResult.Success : IdentityResult.Failed(new IdentityError { Description = "Failed to delete user" });
        }

        public Task<ApplicationUser> FindByIdAsync(string userId)
        {
            return _userProfileDal.FindByIdAsync(userId);
        }

        public Task<ApplicationUser> FindByNameAsync(string normalizedUserName)
        {
            return _userProfileDal.FindByNameAsync(normalizedUserName);
        }

        public Task<string> GetNormalizedUserNameAsync(ApplicationUser user)
        {
            return Task.FromResult(user.NormalizedUserName);
        }

        public Task<string> GetUserIdAsync(ApplicationUser user)
        {
            return Task.FromResult(user.Id);
        }

        public Task<string> GetUserNameAsync(ApplicationUser user)
        {
            return Task.FromResult(user.UserName);
        }

        public Task SetNormalizedUserNameAsync(ApplicationUser user, string normalizedName)
        {
            user.NormalizedUserName = normalizedName;
            return Task.CompletedTask;
        }

        public Task SetUserNameAsync(ApplicationUser user, string userName)
        {
            user.UserName = userName;
            return Task.CompletedTask;
        }

        public Task SetPasswordHashAsync(ApplicationUser user, string passwordHash)
        {
            user.PasswordHash = passwordHash;
            return Task.CompletedTask;
        }

        public Task<string> GetPasswordHashAsync(ApplicationUser user)
        {
            return Task.FromResult(user.PasswordHash);
        }

        public Task<bool> HasPasswordAsync(ApplicationUser user)
        {
            return Task.FromResult(!string.IsNullOrEmpty(user.PasswordHash));
        }

        public void Dispose()
        {
            // Nothing to dispose
        }

    }
}
