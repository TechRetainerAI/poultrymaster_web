using PoultryWeb.Models.Authentication.Login;
using PoultryWeb.Models.Authentication.SignUp;
using PoultryWeb.Models.Authentication.User;

namespace PoultryWeb.Business
{
    public interface IAuthenticationService
    {
        Task<BaseResponse> ConfirmEmailAsync(string token, string email);
        Task<LoginResponse> LoginAsync(LoginModel loginModel);
        Task<BaseResponse> LoginWithOTPAsync(string code, string userName);
        Task<LoginResponse> RefreshAccessToken(ResponseData tokens);
        Task<RefreshTokenResponse> RefreshTokenAsync(string refreshToken);
        Task<RegisterResponse> RegisterAsync(RegisterUser registerUser);
        void UpdateSessionWithNewTokens(HttpContext context, LoginResponse newTokens);
    }
}