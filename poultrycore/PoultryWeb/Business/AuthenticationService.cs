using PoultryWeb.Models.Authentication.User;
using System.Net.Http;
using System.Net.Http.Json;
using System.Threading.Tasks;
using PoultryWeb.Models.Authentication.Login;
using PoultryWeb.Models.Authentication.SignUp;
using System.Net;
using Newtonsoft.Json;
using System.Text;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using PoultryWeb.Models;
using System.Net.Http.Headers;
using PoultryWeb.Models.Account;
using PoultryWeb.Business;
using PoultryWeb.Models.Authentication.User;
using PoultryWeb.Models.Authentication.Login;
using PoultryWeb.Models.Authentication.SignUp;
using PoultryWeb.Models.Account;

namespace PoultryWeb.Business
{
    public class AuthenticationService : IAuthenticationService
    {
        //private readonly HttpClient _httpClient;
        //private readonly ILogger<TaxService> _logger;
        //private readonly IConfiguration _configuration;
        //public AuthService(IConfiguration configuration, ILogger<TaxService> logger, HttpClient httpClient)
        //{
        //    _httpClient = httpClient;
        //    _configuration = configuration;
        //    _logger = logger;
        //}

        //var loginModel = new { Email = email, Password = password };
        //var response = await _httpClient.PostAsJsonAsync("api/authentication/login", loginModel);
        //response.EnsureSuccessStatusCode(); // Throws an exception if the HTTP response status indicates failure
        //return await response.Content.ReadFromJsonAsync<LoginResponse>();

        private readonly HttpClient _httpClient;
        private readonly ILogger<AuthenticationService> _logger;
        private readonly string _loginUrl;
        private readonly IConfiguration _configuration;

        public AuthenticationService(IHttpClientFactory httpClientFactory, IConfiguration configuration, ILogger<AuthenticationService> logger)
        {
            _httpClient = httpClientFactory.CreateClient();
            _configuration = configuration;
            _logger = logger;
            _loginUrl = configuration["LoginUrl"];  // Assuming LoginUrl is correctly set in your appsettings.json or other configuration source
        }

        public async Task<LoginResponse> LoginAsync(LoginModel loginModel)
        {
            var url = $"{_loginUrl}/api/authentication/login";

            try
            {
                var jsonContent = new StringContent(JsonConvert.SerializeObject(loginModel), Encoding.UTF8, "application/json");
                var response = await _httpClient.PostAsync(url, jsonContent);

                if (response.IsSuccessStatusCode)
                {
                    var content = await response.Content.ReadAsStringAsync();
                    var result = JsonConvert.DeserializeObject<LoginResponse>(content);
                    //Reading the values to these properties as well
                    result.UserId = result.Response.UserId;
                    result.Username = result.Response.Username;

                    result.IsStaff = result.Response.IsStaff;
                    result.FarmId = result.Response.FarmId;
                    result.FarmName = result.Response.FarmName;
                    result.IsSubscriber = result.Response.IsSubscriber;

                    _logger.LogInformation("User {Username} login successful", loginModel.Username);
                    return result;
                }
                else
                {
                    _logger.LogWarning("Login failed with status code {StatusCode} for user {Username}", response.StatusCode, loginModel.Username);
                    return new LoginResponse { IsSuccess = false, Message = "Login failed with status: " + response.StatusCode };
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred during login for user {Username}", loginModel.Username);
                return new LoginResponse { IsSuccess = false, Message = "Login failed due to an exception." };
            }
        }

        //public async Task LogoutAsync(string accessToken)
        //{
        //    // Call the API to logout
        //    var request = new HttpRequestMessage(HttpMethod.Post, "api/logout");
        //    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        //    var response = await _httpClient.SendAsync(request);
        //    response.EnsureSuccessStatusCode();
        //}

        public async Task<BaseResponse> LogoutAsync(string token)
        {
            var url = $"{_loginUrl}/api/authentication/logout";

            try
            {
                // You may need to pass the token in the request headers or body depending on your API design
                // Here, assuming the token is passed in the Authorization header
                _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

                var response = await _httpClient.PostAsync(url, null);

                if (response.IsSuccessStatusCode)
                {
                    _logger.LogInformation("Logout successful");
                    return new BaseResponse { IsSuccess = true, Message = "Logout successful" };
                }
                else
                {
                    _logger.LogWarning("Logout failed with status code {StatusCode}", response.StatusCode);
                    return new BaseResponse { IsSuccess = false, Message = "Logout failed with status: " + response.StatusCode };
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred during logout");
                return new BaseResponse { IsSuccess = false, Message = "Logout failed due to an exception." };
            }
        }


        public async Task<LoginResponse> RefreshAccessToken(ResponseData tokens)
        {
            var url = $"{_loginUrl}/api/authentication/Refresh-Token";

            try
            {
                var jsonContent = new StringContent(JsonConvert.SerializeObject(tokens), Encoding.UTF8, "application/json");
                var response = await _httpClient.PostAsync(url, jsonContent);

                if (response.IsSuccessStatusCode)
                {
                    var content = await response.Content.ReadAsStringAsync();
                    var result = JsonConvert.DeserializeObject<LoginResponse>(content);
                    _logger.LogInformation("User {Username} login successful");
                    return result;
                }
                else
                {
                    _logger.LogWarning("Login failed with status code {StatusCode} for user {Username}", response.StatusCode);
                    return new LoginResponse { IsSuccess = false, Message = "Login failed with status: " + response.StatusCode };
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred during login for user {Username}");
                return new LoginResponse { IsSuccess = false, Message = "Login failed due to an exception." };
            }
        }

        public void UpdateSessionWithNewTokens(HttpContext context, LoginResponse newTokens)
        {
            // Update session and cookies with the new tokens
            context.Session.SetString("AccessToken", newTokens.Response.AccessToken.Token);
            context.Response.Cookies.Append("RefreshToken", newTokens.Response.RefreshToken.Token, new CookieOptions { HttpOnly = true, Secure = true });

            // Convert the expiry date of the access token to a string
            var expiryDateStr = newTokens.Response.AccessToken.ExpiryTokenDate.ToString("o");
            context.Session.SetString("AccessTokenExpiryDate", expiryDateStr);
        }



        //public async Task<LoginResponse> LoginAsync(LoginModel loginModel)
        //{
        //    string loginUrl = _configuration["LoginUrl"];

        //    try
        //    {
        //        var url = $"{loginUrl}/authentication/login/{loginModel}";

        //        using (HttpClient client = new HttpClient())   // Create HttpClient instance
        //        {
        //            //Set security protocol
        //            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;

        //            HttpResponseMessage response = client.PostAsync(url, null).Result;  // Execute the request

        //            // Check if the response status code is OK (200)
        //            if (response.IsSuccessStatusCode)
        //            {
        //                if (response.Content != null)
        //                {
        //                    // Deserialize the JSON response to a boolean
        //                    string content = response.Content.ReadAsStringAsync().Result;

        //                    _logger.LogInformation("User {} Calculation successful", loginModel.Username);
        //                    return "success"; // Or return the response content or any other result
        //                }
        //            }
        //        }
        //    }
        //    catch (Exception ex)
        //    {
        //        //Log.Error(ex);
        //        _logger.LogError("User {} Error occurred during calculation", loginModel.Username);
        //        return "failed"; // Default value in case of failure
        //    }

        //    return "failed"; // Default value in case of failure
        //}

        public async Task<RegisterResponse> RegisterAsync(RegisterUser registerUser)
        {
            var url = $"{_loginUrl}/api/authentication/Register";

            //Assign this default role to everyone who logs in. Admin and HR roles can be manually updated in the db for now.
            //uncomment
            //registerUser.Roles.Add("User");   
            
            try
            {
                var jsonContent = new StringContent(JsonConvert.SerializeObject(registerUser), Encoding.UTF8, "application/json");
                var response = await _httpClient.PostAsync(url, jsonContent);

                if (response.IsSuccessStatusCode)
                {
                    var content = await response.Content.ReadAsStringAsync();
                    var result = JsonConvert.DeserializeObject<RegisterResponse>(content);
                    _logger.LogInformation("User {Username} registration successful", registerUser.Username);
                    return result;
                }
                else
                {
                    _logger.LogWarning("Registration failed with status code {StatusCode} for user {Username}", response.StatusCode, registerUser.Username);
                    return new RegisterResponse { IsSuccess = false, Message = "Registration failed with status: " + response.StatusCode };
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred during login for user {Username}", registerUser.Username);
                return new RegisterResponse { IsSuccess = false, Message = "Login failed due to an exception." };
            }
        }

        public async Task<BaseResponse> ConfirmEmailAsync(string token, string email)
        {
            //I realised the encoded token sent to the email is automatically decoding by the time it gets here
            // since i WOULD NEED TO SENT IT TO THE API, i WOULD LIKE TO ENCODE IT AGAIN SO THAT IT WILL DECODE BY THE TIME IT GETS TO THE API
            token = WebUtility.UrlEncode(token);
            var url = $"{_loginUrl}/api/authentication/ConfirmEmail?token={token}&email={email}";

            try
            {
                // Create an empty content since we are using GET with query parameters
                var response = await _httpClient.GetAsync(url);

                if (response.IsSuccessStatusCode)
                {
                    var content = await response.Content.ReadAsStringAsync();
                    var result = JsonConvert.DeserializeObject<BaseResponse>(content);
                    _logger.LogInformation("Email confirmation successful for email {Email}", email);
                    return result;
                }
                else
                {
                    _logger.LogWarning("Email confirmation failed with status code {StatusCode} for email {Email}", response.StatusCode, email);
                    return new BaseResponse { IsSuccess = false, Message = "Email confirmation failed with status: " + response.StatusCode };
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred during email confirmation for email {Email}", email);
                return new BaseResponse { IsSuccess = false, Message = "Email confirmation failed due to an exception." };
            }
        }

        public async Task<LoginResponse> VerifyAndLoginWithOTPAsync(Otp model)
        {
            var url = $"{_loginUrl}/api/authentication/login-2FA";
            //var url = $"{_loginUrl}/api/authentication/login-2FA?code={model.OtpCode}&email={model.UserName}";

            try
            {
                var jsonContent = new StringContent(JsonConvert.SerializeObject(model), Encoding.UTF8, "application/json");
                var response = await _httpClient.PostAsync(url, jsonContent);

                if (response.IsSuccessStatusCode)
                {
                    var content = await response.Content.ReadAsStringAsync();
                    var result = JsonConvert.DeserializeObject<LoginResponse>(content);
                    _logger.LogInformation("OTP verification successful for user {Username}", model.UserName);
                    return result;
                }
                else
                {
                    _logger.LogWarning("OTP verification failed with status code {StatusCode} for user {Username}", response.StatusCode, model.UserName);
                    return new LoginResponse { IsSuccess = false, Message = "OTP verification failed with status: " + response.StatusCode };
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred during OTP verification for user {Username}", model.UserName);
                return new LoginResponse { IsSuccess = false, Message = "OTP verification failed due to an exception." };
            }
        }

        public async Task<BaseResponse> LoginWithOTPAsync(string code, string userName)
        {
            var response = await _httpClient.PostAsJsonAsync("api/authentication/login-2FA", new { Code = code, UserName = userName });
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadFromJsonAsync<BaseResponse>();
        }

        public async Task<RefreshTokenResponse> RefreshTokenAsync(string refreshToken)
        {
            
            var response = await _httpClient.PostAsJsonAsync("api/authentication/refresh-token", new { RefreshToken = refreshToken });
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadFromJsonAsync<RefreshTokenResponse>();
        }

        // You might need to create DTO classes that match the expected request body for each API call

        public async Task<bool> ForgotPasswordAsync(ForgotPassword model)
        {
            var url = $"{_loginUrl}/api/authentication/ForgotPassword";
            var content = new StringContent(JsonConvert.SerializeObject(model), Encoding.UTF8, "application/json");
            var response = await _httpClient.PostAsync(url, content);

            return response.IsSuccessStatusCode;
        }

        public async Task<bool> ResetPasswordAsync(ResetPassword model)
        {
            var url = $"{_loginUrl}/api/authentication/ResetPassword";

            var content = new StringContent(JsonConvert.SerializeObject(model), Encoding.UTF8, "application/json");
            var response = await _httpClient.PostAsync(url, content);

            return response.IsSuccessStatusCode;
        }
    }


}
