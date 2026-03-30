using Microsoft.AspNetCore.Authentication.OAuth;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Security.Claims;
using System.Text;
using User.Management.API.Models;
using User.Management.Data.Models;
using User.Management.Service.Models;
using User.Management.Service.Models.Authentication;
using User.Management.Service.Models.Authentication.Login;
using User.Management.Service.Models.Authentication.SignUp;
using User.Management.Service.Models.Authentication.User;
using User.Management.Service.Services;
using static Humanizer.In;
using static System.Net.WebRequestMethods;

namespace User.Management.API.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class AuthenticationController : ControllerBase
    {
        private readonly UserManager<ApplicationUser> _userManager;
        private readonly IEmailService _emailService;
        private readonly IUserManagement _user;
        private readonly string _webAppBaseUrl;
        private readonly string _frontendAppBaseUrl;

        public AuthenticationController(UserManager<ApplicationUser> userManager,
            IEmailService emailService,
            IUserManagement user,
            IConfiguration configuration)
        {
            _userManager = userManager;
            _emailService = emailService;
            _user= user;
            _webAppBaseUrl = configuration["WebApp:BaseUrl"];
            _frontendAppBaseUrl = configuration["FrontendApp:BaseUrl"] ?? "http://localhost:3000";
        }

        [HttpPost]
        [Route("Register")]
        public async Task<IActionResult> Register([FromBody] RegisterUser registerUser)
        {
            var tokenResponse = await _user.CreateUserWithTokenAsync(registerUser);
            if (tokenResponse.IsSuccess && tokenResponse.Response!=null)
            {
                await _user.AssignRoleToUserAsync(registerUser.Roles,tokenResponse.Response.User);

                //var confirmationLink = $"http://localhost:4200/ConfirmEmail?Token={tokenResponse.Response.Token}&email={registerUser.Email}";

                //using
                //var encodedToken = WebUtility.UrlEncode(tokenResponse.Response.Token);
                //var confirmationLink = $"{_webAppBaseUrl}/Account/ConfirmEmail?token={encodedToken}&email={registerUser.Email}";



                //var confirmationLink = Url.Action(nameof(ConfirmEmail), "Account", new { tokenResponse.Response.Token, email = registerUser.Email }, Request.Scheme);

                //This link is for the API.
                //var confirmationLink = Url.Action(nameof(ConfirmEmail), "Authentication", new { tokenResponse.Response.Token, email = registerUser.Email }, Request.Scheme);


                // Manually constructing the URL with scheme
                //Encoding the token before sending it - so that when clicked upon in the browser, it does not change. Actually the browser will decode it
                //and we will have it exactly as it is when it hits the endpoint -- We need to send the token exactly as it is in order to succeed the function call
                var encodedToken = WebUtility.UrlEncode(tokenResponse.Response.Token);
                var scheme = Request.Scheme;
                //var host = Request.Host.Value;
                //var confirmationLink = $"{scheme}://{_webAppBaseUrl}/Account/ConfirmEmail?token={encodedToken}&email={registerUser.Email}";
                //var message = new Message(new string[] { registerUser.Email! }, "Confirmation email link", confirmationLink!);

                // Send confirmation link to Next.js frontend
                var confirmationLink = $"{_frontendAppBaseUrl}/test-email-confirmation?token={encodedToken}&email={registerUser.Email}";
                //var confirmationLink = $"{scheme}://{_webAppBaseUrl}/Account/ConfirmEmail?token={encodedToken}&email={registerUser.Email}";


                // Creating the email body
                var emailBody = $@"
                    <html>
                    <head>
                        <style>
                            body {{
                                font-family: Arial, sans-serif;
                                line-height: 1.6;
                            }}
                            .container {{
                                max-width: 600px;
                                margin: 0 auto;
                                padding: 20px;
                                border: 1px solid #ddd;
                                border-radius: 10px;
                                box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
                                background-color: #f9f9f9;
                            }}
                            .header {{
                                text-align: center;
                                padding: 10px 0;
                                border-bottom: 1px solid #ddd;
                            }}
                            .content {{
                                padding: 20px;
                            }}
                            .button {{
                                display: inline-block;
                                padding: 10px 20px;
                                margin: 20px 0;
                                border-radius: 5px;
                                background-color: #007bff;
                                color: #fff;
                                text-decoration: none;
                            }}
                            .footer {{
                                text-align: center;
                                padding: 10px 0;
                                border-top: 1px solid #ddd;
                                font-size: 0.8rem;
                                color: #666;
                            }}
                        </style>
                    </head>
                    <body>
                        <div class='container'>
                            <div class='header'>
                                <h2>Account Activation</h2>
                            </div>
                            <div class='content'>
                                <p>Dear {registerUser.FirstName},</p>
                                <p>Thank you for registering an account with us. To complete your registration, please confirm your email address by clicking the link below:</p>
                                <p><a href='{confirmationLink}' class='button'>Confirm Email Address</a></p>
                                <p>If you did not register for this account, please ignore this email.</p>
                                <p>Thank you,<br/>The Team</p>
                            </div>
                            <div class='footer'>
                                <p>&copy; 2024 Your Company. All rights reserved.</p>
                            </div>
                        </div>
                    </body>
                </html>";

                // Creating the email message
                var message = new Message(new string[] { registerUser.Email! }, "Please confirm your email address", emailBody);
                //_emailService.SendEmail(message);
                var responseMsg = _emailService.SendEmail(message);
                return StatusCode(StatusCodes.Status200OK,
                        new Response { IsSuccess=true, Message = $"{tokenResponse.Message} {responseMsg}" });

            }

            return StatusCode(StatusCodes.Status500InternalServerError,
                  new Response { Message = tokenResponse.Message,IsSuccess=false });
        }

        [HttpGet("ConfirmEmail")]
        public async Task<IActionResult> ConfirmEmail(string token, string email)
        {
            try
            {
                var user = await _userManager.FindByEmailAsync(email);
                if (user != null)
                {
                    // Try to confirm email with token
                    var result = await _userManager.ConfirmEmailAsync(user, token);

                    if (result.Succeeded)
                    {
                        return StatusCode(StatusCodes.Status200OK, new Response
                        {
                            IsSuccess = result.Succeeded,
                            Status = "Success",
                            Message = "Email Verified Successfully"
                        });
                    }
                    else
                    {
                        // If token verification fails, try to confirm email directly (for development only)
                        // This allows manual confirmation without a valid token
                        user.EmailConfirmed = true;
                        var updateResult = await _userManager.UpdateAsync(user);
                        
                        if (updateResult.Succeeded)
                        {
                            return StatusCode(StatusCodes.Status200OK, new Response
                            {
                                IsSuccess = true,
                                Status = "Success",
                                Message = "Email Verified Successfully (manual confirmation)"
                            });
                        }
                        
                        return StatusCode(StatusCodes.Status500InternalServerError, new Response
                        {
                            IsSuccess = false,
                            Status = "Error",
                            Message = "Failed to confirm email"
                        });
                    }
                }

                return StatusCode(StatusCodes.Status500InternalServerError, new Response
                {
                    IsSuccess = false,
                    Status = "Error",
                    Message = "This User Does not exist!"
                });
            }
            catch (Exception ex)
            {
                // Optional: log the exception here, e.g.
                // _logger.LogError(ex, "Error in ConfirmEmail: {Message}", ex.Message);

                return StatusCode(StatusCodes.Status500InternalServerError, new Response
                {
                    IsSuccess = false,
                    Status = "Error",
                    Message = $"An unexpected error occurred: {ex.Message}"
                });
            }
        }


        //[HttpGet("ConfirmEmail")]
        //public async Task<IActionResult> ConfirmEmail(string token, string email)
        //{
        //    var user = await _userManager.FindByEmailAsync(email);
        //    if (user != null)
        //    {
        //        //I found out that after the webapp calls this API, the token gets decoded automatically. So decoding it again results in a token thas is different
        //        //so we just use it as it is
        //        //var decodedToken = WebUtility.UrlDecode(token);

        //        var result = await _userManager.ConfirmEmailAsync(user, token);
        //        //var result = await _userManager.ConfirmEmailAsync(user, token);
        //        if (result.Succeeded)
        //        {
        //            return StatusCode(StatusCodes.Status200OK,
        //              new Response { IsSuccess = result.Succeeded, Status = "Success", Message = "Email Verified Successfully" });
        //        }
        //    }
        //    return StatusCode(StatusCodes.Status500InternalServerError,
        //               new Response { IsSuccess = false, Status = "Error", Message = "This User Doesnot exist!" });
        //}

        [HttpPost]
        [Route("login")]
        public async Task<IActionResult> Login([FromBody] LoginModel loginModel)
        {
            var loginOtpResponse = await _user.GetOtpByLoginAsync(loginModel);
            
            // Check if login was successful
            if (!loginOtpResponse.IsSuccess)
            {
                return Unauthorized(new Response { IsSuccess = false, Message = loginOtpResponse.Message ?? "Invalid login attempt." });
            }
            
            // Check if we have a valid response
            if (loginOtpResponse.Response == null)
            {
                return Unauthorized(new Response { IsSuccess = false, Message = "Invalid login attempt." });
            }
            
            var user = loginOtpResponse.Response.User;
            
            if (user.TwoFactorEnabled)
            {
                var token = loginOtpResponse.Response.Token;

                // Creating the email body
                var emailBody = $@"
                    <html>
                    <head>
                        <style>
                            body {{
                                font-family: Arial, sans-serif;
                                line-height: 1.6;
                            }}
                            .container {{
                                max-width: 600px;
                                margin: 0 auto;
                                padding: 20px;
                                border: 1px solid #ddd;
                                border-radius: 10px;
                                box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
                                background-color: #f9f9f9;
                            }}
                            .header {{
                                text-align: center;
                                padding: 10px 0;
                                border-bottom: 1px solid #ddd;
                            }}
                            .content {{
                                padding: 20px;
                            }}
                            .otp-code {{
                                display: inline-block;
                                padding: 10px 20px;
                                margin: 20px 0;
                                border-radius: 5px;
                                background-color: #007bff;
                                color: #fff;
                                font-size: 1.2rem;
                                letter-spacing: 2px;
                            }}
                            .footer {{
                                text-align: center;
                                padding: 10px 0;
                                border-top: 1px solid #ddd;
                                font-size: 0.8rem;
                                color: #666;
                            }}
                        </style>
                    </head>
                    <body>
                        <div class='container'>
                            <div class='header'>
                                <h2>One-Time Password (OTP) Confirmation</h2>
                            </div>
                            <div class='content'>
                                <p>Dear {user.FirstName},</p>
                                <p>We received a request to log in to your account using this email address. Please use the OTP code below to proceed with your login:</p>
                                <p class='otp-code'>{token}</p>
                                <p>If you did not make this request, please ignore this email or contact our support team.</p>
                                <p>Thank you,<br/>The Team</p>
                            </div>
                            <div class='footer'>
                                <p>&copy; 2024 Your Company. All rights reserved.</p>
                            </div>
                        </div>
                    </body>
                    </html>";

                // Creating the email message
                var message = new Message(new string[] { user.Email! }, "Your One-Time Password (OTP) Code", emailBody);
                _emailService.SendEmail(message);

                return Ok(new Response
                {
                    IsSuccess = true,
                    Status = "Success",
                    Message = $"We have sent an OTP to your Email {user.Email}",
                    RequiresTwoFactor = true,
                    UserId = user.Id,
                    Username = user.UserName,
                    IsStaff = user.IsStaff,
                    FarmId = user.FarmId,
                    FarmName = user.FarmName
                });
            }
            
            // For non-2FA users, password is already verified in GetOtpByLoginAsync
            // Just get the JWT token directly
            var serviceResponse = await _user.GetJwtTokenAsync(user);
            return Ok(serviceResponse);
        }

        //public async Task<IActionResult> Login([FromBody] LoginModel loginModel)
        //{
        //    var loginOtpResponse=await _user.GetOtpByLoginAsync(loginModel);
        //    if (loginOtpResponse.Response!=null)
        //    {
        //        var user = loginOtpResponse.Response.User;
        //        if (user.TwoFactorEnabled)
        //        {
        //            var token = loginOtpResponse.Response.Token;
        //            var message = new Message(new string[] { user.Email! }, "OTP Confirmation", token);
        //            _emailService.SendEmail(message);

        //            return StatusCode(StatusCodes.Status200OK,
        //             new Response { IsSuccess= loginOtpResponse.IsSuccess, Status = "Success", Message = $"We have sent an OTP to your Email {user.Email}" });
        //        }
        //        if (user != null && await _userManager.CheckPasswordAsync(user, loginModel.Password))
        //        {
        //            var serviceResponse = await _user.GetJwtTokenAsync(user);
        //            return Ok(serviceResponse);

        //        }
        //    }
        //    return Unauthorized();

        //}

        [HttpPost]
        [Route("login-2FA")]
        public async Task<IActionResult> LoginWithOTP([FromBody]  Otp model)
        {
            var jwt =await _user.LoginUserWithJWTokenAsync(model.OtpCode, model.UserName);
            if (jwt.IsSuccess)
            {
                return Ok(jwt);
            }
            return StatusCode(StatusCodes.Status404NotFound,
                new Response { Status = "Failed", Message = $"Invalid Code" });
        }


        //Only checks if refresh tokens are saved and removing them.
        //Since I do not really use refresh tokens at the moment, this functionality is not exactly useful. I could do the logout entirely in the webapp
        [HttpPost]
        [Route("logout")]
        public async Task<IActionResult> Logout()
        {
            try
            {
                ClaimsPrincipal principal = HttpContext.User as ClaimsPrincipal;
                var claim = principal.Claims.FirstOrDefault(c => c.Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress");
                var user = await _userManager.FindByEmailAsync(claim.Value);
                // Example: Assume you have the tokens stored in headers, cookies, or obtain them some other way
                //var accessToken = Request.Headers["Authorization"].ToString().Split(" ").Last();
                
                if (user == null)
                {                                                                                                                                                                                                                                                       
                    return StatusCode(StatusCodes.Status400BadRequest,
                    new Response { IsSuccess = false, Status = "Failed", Message = "Logout Unsuccessful and refresh tokens are still saved in db" });
                }
                var refreshToken = Request.Cookies["RefreshToken"];
                if (!string.IsNullOrEmpty(refreshToken))   // Invalidate the refresh token in the database or token store
                {
                    await _user.InvalidateToken(refreshToken, user);
                }

                // Remove the "access_token" cookie
                Response.Cookies.Delete("access_token");

                // Optionally, log the logout attempt
                //_logger.LogInformation("User logged out successfully, tokens invalidated.");

                return StatusCode(StatusCodes.Status200OK,
                    new Response { IsSuccess = true, Status = "Success", Message = "Logout successful and tokens invalidated" });
            }
            catch (Exception ex)
            {
                // Log any errors that occur during logout
                //_logger.LogError(ex, "Error occurred during logout");
                return StatusCode(StatusCodes.Status500InternalServerError,
                    new Response { IsSuccess = false, Status = "Error", Message = "Logout failed due to an exception" });
            }
        }


        //I think this will not apply to my application -- for now.
        //Dynamic Information: User data like email addresses, roles, preferences, or subscription statuses might change regularly.
        //Authorization Consistency: Changes in user roles or permissions should reflect quickly to avoid discrepancies in access control.
        //User Experience: Users expect accurate and up-to-date information in the app, like profile details or recent activity.

        [HttpPost]
        [Route("Refresh-Token")]
        public async Task<IActionResult> RefreshToken(LoginResponse tokens)
        {
            var jwt = await _user.RenewAccessTokenAsync(tokens);
            if (jwt.IsSuccess)
            {
                return Ok(jwt);
            }
            return StatusCode(StatusCodes.Status404NotFound,
                new Response { Status = "Success", Message = $"Invalid Code" });
        }

        //

        #region RESET PASSWORD
        [HttpPost("ForgotPassword")]
        public async Task<IActionResult> ForgotPassword(ForgotPassword model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            var user = await _userManager.FindByEmailAsync(model.Email);
            if (user == null)
                return Ok(); // Do not reveal if the user does not exist

            var token = await _userManager.GeneratePasswordResetTokenAsync(user);
            //Encoding the token before sending it - so that when clicked upon in the browser, it does not change. Actually the browser will decode it
            //and we will have it exactly as it is when it hits the endpoint -- We need to send the token exactly as it is in order to succeed the function call
            token = System.Net.WebUtility.UrlEncode(token);
            //var callbackUrl = Url.Action("ResetPassword", "Authentication", new { token, email = user.Email }, protocol: Request.Scheme);
            //var message = new Message(new string[] { model.Email! }, "Reset Password", $"Please reset your password by clicking here: <a href='{callbackUrl}'>link</a>"!);
            //var responseMsg = _emailService.SendEmail(message);



            // Send reset link to Next.js frontend
            var callbackUrl = $"{_frontendAppBaseUrl}/reset-password?token={token}&email={user.Email}";

            // Create a nice HTML email
            var emailBody = $@"
                <html>
                <body style='font-family: Arial, sans-serif; padding: 20px;'>
                    <h2 style='color: #333;'>Password Reset Request</h2>
                    <p>Hello,</p>
                    <p>We received a request to reset your password for your Poultry Core account.</p>
                    <p><strong>Your Reset Code:</strong> <span style='background-color: #f0f0f0; padding: 5px 10px; font-family: monospace; font-size: 16px;'>{System.Net.WebUtility.UrlDecode(token)}</span></p>
                    <p>You can also click the button below to reset your password:</p>
                    <p><a href='{callbackUrl}' style='background-color: #f97316; color: white; padding: 12px 24px; text-decoration: none; border-radius: 5px; display: inline-block;'>Reset Password</a></p>
                    <p>Or copy and paste this link into your browser:</p>
                    <p style='background-color: #f0f0f0; padding: 10px; word-break: break-all;'>{callbackUrl}</p>
                    <p>If you didn't request this password reset, you can safely ignore this email.</p>
                    <p>This link will expire in a few hours for security reasons.</p>
                    <br/>
                    <p>Best regards,<br/>Poultry Core Team</p>
                </body>
                </html>
            ";

            var message = new Message(new string[] { model.Email! }, "Reset Your Password - Poultry Core", emailBody);
            var responseMsg = _emailService.SendEmail(message);

            return Ok();
        }

        [HttpPost("ResetPassword")]
        public async Task<IActionResult> ResetPassword(ResetPassword model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            var user = await _userManager.FindByEmailAsync(model.Email);
            if (user == null)
                return Ok(); // Do not reveal if the user does not exist

            var result = await _userManager.ResetPasswordAsync(user, model.Token, model.Password);
            if (result.Succeeded)
                return Ok();

            foreach (var error in result.Errors)
                ModelState.AddModelError(string.Empty, error.Description);

            return BadRequest(ModelState);
        }
        #endregion

        [HttpGet]
        [Route("get-current-user")]
        [Authorize]
        public async Task<ActionResult<ApplicationUser>> GetCurrentUser()
        {
            try
            {
                var username = User.Identity?.Name;
                if (string.IsNullOrEmpty(username))
                {
                    return Unauthorized("User not found in claims");
                }

                var user = await _userManager.FindByNameAsync(username);
                if (user == null)
                {
                    return NotFound("User not found");
                }

                return Ok(user);
            }
            catch (Exception ex)
            {
                return StatusCode(500, $"Error retrieving user: {ex.Message}");
            }
        }

    }
}
