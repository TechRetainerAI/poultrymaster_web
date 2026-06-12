using Microsoft.AspNetCore.Identity;
using User.Management.Data.Models;
using User.Management.Service.Models;
using User.Management.Service.Models.Authentication.Login;
using User.Management.Service.Models.Authentication.SignUp;
using User.Management.Service.Models.Authentication.User;

namespace User.Management.Service.Services
{
    public interface IUserManagement
    { 
        
        /// <summary>
       /// Brief description of what the method does.
       /// </summary>
       /// <param name="registerUser">Description of the parameter.</param>
       /// <returns>Description of the return value.</returns>

        Task<ApiResponse<CreateUserResponse>> CreateUserWithTokenAsync(RegisterUser registerUser);
        Task<ApiResponse<List<string>>> AssignRoleToUserAsync(List<string> roles, ApplicationUser user);
        Task<ApiResponse<LoginOtpResponse>> GetOtpByLoginAsync(LoginModel loginModel);
        Task<ApiResponse<LoginResponse>> GetJwtTokenAsync(ApplicationUser user);
        Task<ApiResponse<LoginResponse>> LoginUserWithJWTokenAsync(string otp, string userName);
        Task<ApiResponse<LoginResponse>> RenewAccessTokenAsync(LoginResponse tokens);
        Task InvalidateToken(string token, ApplicationUser user);



        //new
        //Task<IdentityResult> CreateUserAsync(ApplicationUser user);
        //Task<IdentityResult> DeleteUserAsync(string userId);
        //Task<ApplicationUser> FindByIdAsync(string userId);
        //Task<ApplicationUser> FindByNameAsync(string normalizedUserName);
        //Task<string> GetPasswordHashAsync(string userId);
        //Task<bool> HasPasswordAsync(string userId);
        //Task<bool> SetPasswordHashAsync(string userId, string hash);
    }
}
