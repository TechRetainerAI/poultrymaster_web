using Microsoft.AspNetCore.Authentication.OAuth;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
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
using User.Management.Service.Helpers;
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
        private readonly ILogger<AuthenticationController> _logger;
        private readonly string _webAppBaseUrl;
        private readonly string _frontendAppBaseUrl;

        public AuthenticationController(UserManager<ApplicationUser> userManager,
            IEmailService emailService,
            IUserManagement user,
            IConfiguration configuration,
            ILogger<AuthenticationController> logger)
        {
            _userManager = userManager;
            _emailService = emailService;
            _user= user;
            _logger = logger;
            _webAppBaseUrl = configuration["WebApp:BaseUrl"];
            _frontendAppBaseUrl = configuration["FrontendApp:BaseUrl"] ?? "http://localhost:3000";
        }

        // Prompt 3 — live availability check for an Organization Code (signup).
        [HttpGet("org-code-available")]
        public IActionResult OrgCodeAvailable([FromQuery] string code)
        {
            var norm = Service.Helpers.OrgCode.Normalize(code);
            var error = Service.Helpers.OrgCode.Validate(norm);
            if (error != null)
                return Ok(new { available = false, reason = error, suggestions = Service.Helpers.OrgCode.Suggestions(norm) });
            var taken = _userManager.Users.Where(u => u.OrganizationCode == norm).ToList().Any();
            if (taken)
                return Ok(new { available = false, reason = "This Organization Code is already taken.", suggestions = Service.Helpers.OrgCode.Suggestions(norm) });
            return Ok(new { available = true, code = norm });
        }

        // Prompt 3 — resolve an Organization Code to its owner so the client can
        // scope the session to that organization's companies after login. This
        // does NOT grant access; the user still authenticates with username +
        // password.
        [HttpGet("org")]
        public IActionResult ResolveOrg([FromQuery] string code)
        {
            var norm = Service.Helpers.OrgCode.Normalize(code);
            if (string.IsNullOrEmpty(norm)) return Ok(new { found = false });
            var owner = _userManager.Users.Where(u => u.OrganizationCode == norm).ToList().FirstOrDefault();
            if (owner == null) return Ok(new { found = false });
            return Ok(new { found = true, ownerUserId = owner.Id, businessOfficeName = owner.BusinessOfficeName, organizationCode = norm });
        }

        [HttpPost]
        [Route("Register")]
        public async Task<IActionResult> Register([FromBody] RegisterUser registerUser)
        {
            // SECURITY: never trust client-supplied roles on a public signup endpoint.
            // The person registering is the farm owner; any other role must be granted by an admin.
            registerUser.Roles = new List<string> { "Admin" };

            var tokenResponse = await _user.CreateUserWithTokenAsync(registerUser);
            if (tokenResponse.IsSuccess && tokenResponse.Response != null)
            {
                await _user.AssignRoleToUserAsync(registerUser.Roles, tokenResponse.Response.User);

                // Account is auto-confirmed at creation time (see UserManagement.CreateUserWithTokenAsync),
                // so we send a welcome email rather than a verification link. A mail failure must NOT
                // fail registration — the account already exists — so swallow-and-log here.
                try
                {
                    var loginUrl = _frontendAppBaseUrl.TrimEnd('/') + "/login";
                    var welcomeHtml = BuildWelcomeEmailHtml(
                        registerUser.FirstName,
                        registerUser.FarmName,
                        registerUser.CompanyType,
                        loginUrl);
                    var subject = string.IsNullOrWhiteSpace(registerUser.FarmName)
                        ? "Welcome to VisibilityCore"
                        : $"Welcome to VisibilityCore, {registerUser.FarmName}";
                    _emailService.SendEmail(new Message(new[] { registerUser.Email! }, subject, welcomeHtml));
                }
                catch (Exception emailEx)
                {
                    _logger.LogError(emailEx,
                        "Welcome email failed for {Email} (registration still succeeded)",
                        registerUser.Email);
                }

                return StatusCode(StatusCodes.Status200OK,
                    new Response { IsSuccess = true, Message = tokenResponse.Message });
            }

            // Map the service status onto a meaningful HTTP code (e.g. duplicate-user → 409).
            var statusCode = tokenResponse.StatusCode switch
            {
                403 => StatusCodes.Status409Conflict,
                > 0 => tokenResponse.StatusCode,
                _   => StatusCodes.Status500InternalServerError,
            };

            return StatusCode(statusCode,
                  new Response { Message = tokenResponse.Message, IsSuccess = false });
        }

        // Friendly post-signup welcome. Accounts are auto-confirmed, so there is no
        // verification link — just a "you're ready, here's how to log in" message.
        private static string BuildWelcomeEmailHtml(string? firstName, string? farmName, string? companyType, string loginUrl)
        {
            var safeName = WebUtility.HtmlEncode(string.IsNullOrWhiteSpace(firstName) ? "there" : firstName);
            var safeFarm = WebUtility.HtmlEncode(string.IsNullOrWhiteSpace(farmName) ? "your account" : farmName);
            var typeLine = string.IsNullOrWhiteSpace(companyType)
                ? ""
                : $"<p style=\"color:#475569;\">Workspace type: <strong>{WebUtility.HtmlEncode(companyType)}</strong></p>";
            return $@"
<div style=""font-family:Arial,Helvetica,sans-serif;color:#1f2937;max-width:560px;margin:0 auto;"">
  <h2 style=""color:#0f172a;"">Welcome, {safeName}!</h2>
  <p>Your Poultry Master account for <strong>{safeFarm}</strong> has been created and is ready to use.</p>
  {typeLine}
  <p style=""margin:20px 0;"">
    <a href=""{loginUrl}"" style=""display:inline-block;background:#0ea5e9;color:#ffffff;text-decoration:none;padding:10px 18px;border-radius:6px;"">Log in to get started</a>
  </p>
  <p style=""color:#64748b;font-size:13px;"">If you didn't create this account, you can safely ignore this email.</p>
</div>";
        }

        [HttpGet("ConfirmEmail")]
        public async Task<IActionResult> ConfirmEmail(string token, string email)
        {
            try
            {
                var user = await _userManager.FindByEmailAsync(email);
                // Use the same generic response for "no such user" and "bad token" so this
                // endpoint can't be used to enumerate registered email addresses.
                if (user == null)
                {
                    return StatusCode(StatusCodes.Status400BadRequest, new Response
                    {
                        IsSuccess = false,
                        Status = "Error",
                        Message = "Invalid or expired confirmation link."
                    });
                }

                var result = await _userManager.ConfirmEmailAsync(user, token);
                if (result.Succeeded)
                {
                    return StatusCode(StatusCodes.Status200OK, new Response
                    {
                        IsSuccess = true,
                        Status = "Success",
                        Message = "Email Verified Successfully"
                    });
                }

                // SECURITY: do not blindly mark EmailConfirmed = true when the token check
                // fails — that would let anyone confirm any account.
                return StatusCode(StatusCodes.Status400BadRequest, new Response
                {
                    IsSuccess = false,
                    Status = "Error",
                    Message = "Invalid or expired confirmation link."
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

                // James (2026-05-30): SMTP failures (e.g. Gmail rejecting the
                // configured password) used to bubble unhandled, surface as a
                // 500, and lock users out of their accounts. Catch and return
                // a real message so the operator sees what's wrong instead of
                // "the login service is having trouble".
                var message = new Message(new string[] { user.Email! }, "Your One-Time Password (OTP) Code", emailBody);
                try
                {
                    _emailService.SendEmail(message);
                }
                catch (Exception emailEx)
                {
                    _logger.LogError(emailEx,
                        "OTP email send failed for user {UserName} ({Email})",
                        user.UserName, user.Email);
                    // 400 (not 5xx) so the frontend's friendly-error fallback
                    // doesn't swallow this specific, actionable message.
                    return BadRequest(new Response
                    {
                        IsSuccess = false,
                        Status = "EmailDeliveryFailed",
                        Message =
                            "Could not send your two-factor code by email. " +
                            "Your account is fine — this is a server-side mail problem. " +
                            "Ask an admin to verify the SMTP credentials, or temporarily disable two-factor authentication on your account.",
                    });
                }

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

            // Belt-and-braces: the previous code only wrapped _emailService.SendEmail
            // in try/catch, so anything that threw earlier (DB connection, Identity
            // DataProtection token-provider blow-up, etc.) bubbled to ASP.NET's
            // default 500 with an empty body — surfaced in the browser as
            // `Forgot password error: {}` with no useful signal. Widen the catch so
            // the entire handler returns a readable 503 + log on ANY failure.
            ApplicationUser? user;
            string token;
            try
            {
                // NOTE: do NOT use UserManager.FindByEmailAsync here. It uses
                // SingleOrDefaultAsync internally, which throws
                // InvalidOperationException("Sequence contains more than one
                // element") when the legacy AspNetUsers table has multiple rows
                // with the same NormalizedEmail (a real condition on this
                // instance — at least 5 emails are duplicated). The login path
                // GetOtpByLoginAsync solves the same issue with FirstOrDefault.
                // Mirror that here: pick a deterministic single row (lowest Id)
                // and proceed. Reset-email will go to the canonical account; data
                // hygiene of removing the dupes is tracked separately.
                var normalizedEmail = model.Email?.Trim().ToUpperInvariant();
                user = await _userManager.Users
                    .Where(u => u.NormalizedEmail == normalizedEmail)
                    .OrderBy(u => u.Id)
                    .FirstOrDefaultAsync();
                if (user == null)
                    return Ok(); // Do not reveal if the user does not exist

                token = await _userManager.GeneratePasswordResetTokenAsync(user);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "ForgotPassword: pre-send failure for {Email}", model.Email);
                return StatusCode(StatusCodes.Status503ServiceUnavailable,
                    new Response
                    {
                        Status = "Error",
                        Message = "Couldn't start the password-reset flow right now. Please try again in a minute or contact support.",
                    });
            }

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
            try
            {
                _emailService.SendEmail(message);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "ForgotPassword: SMTP send failed for {Email}", model.Email);
                return StatusCode(StatusCodes.Status503ServiceUnavailable,
                    new Response
                    {
                        Status = "Error",
                        Message = "Unable to send reset email right now. Please try again later or contact support.",
                    });
            }

            return Ok();
        }

        [HttpPost("ResetPassword")]
        public async Task<IActionResult> ResetPassword(ResetPassword model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            // Same SingleOrDefaultAsync-throws-on-dupes guard as ForgotPassword.
            // Must resolve to the SAME row ForgotPassword picked (lowest Id) so
            // the issued reset token is valid for the chosen user.
            var normalizedEmail = model.Email?.Trim().ToUpperInvariant();
            var user = await _userManager.Users
                .Where(u => u.NormalizedEmail == normalizedEmail)
                .OrderBy(u => u.Id)
                .FirstOrDefaultAsync();
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

        // Self-update for profile fields shown on /profile. UserName is intentionally
        // NOT editable here — it's the JWT claim, changing it would invalidate the
        // current token and any audit history that references it. Use a separate
        // admin-mediated flow if username changes are ever needed.
        public class UpdateProfileRequest
        {
            public string? FirstName { get; set; }
            public string? LastName { get; set; }
            [System.ComponentModel.DataAnnotations.EmailAddress]
            public string? Email { get; set; }
            public string? PhoneNumber { get; set; }
            public string? FarmName { get; set; }
        }

        [HttpPut]
        [Route("update-profile")]
        [Authorize]
        public async Task<IActionResult> UpdateProfile([FromBody] UpdateProfileRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);

            var username = User.Identity?.Name;
            if (string.IsNullOrEmpty(username)) return Unauthorized("User not found in claims");

            var user = await _userManager.FindByNameAsync(username);
            if (user == null) return NotFound("User not found");

            // Only overwrite fields the client actually sent (null = "leave as-is"),
            // and trim everything so we don't store whitespace-only values.
            if (req.FirstName   != null) user.FirstName   = req.FirstName.Trim();
            if (req.LastName    != null) user.LastName    = req.LastName.Trim();
            if (req.PhoneNumber != null) user.PhoneNumber = req.PhoneNumber.Trim();
            if (req.FarmName    != null) user.FarmName    = req.FarmName.Trim();

            // Email is special: Identity tracks NormalizedEmail and the email-confirmed
            // flag. Use SetEmailAsync so both stay in sync. Re-confirmation is left off
            // for now to match the signup auto-confirm behavior (see CreateUserWithTokenAsync).
            if (!string.IsNullOrWhiteSpace(req.Email) &&
                !string.Equals(req.Email, user.Email, StringComparison.OrdinalIgnoreCase))
            {
                var setEmail = await _userManager.SetEmailAsync(user, req.Email.Trim());
                if (!setEmail.Succeeded)
                    return BadRequest(string.Join("; ", setEmail.Errors.Select(e => e.Description)));
                user.EmailConfirmed = true;
            }

            var update = await _userManager.UpdateAsync(user);
            if (!update.Succeeded)
                return BadRequest(string.Join("; ", update.Errors.Select(e => e.Description)));

            return Ok(user);
        }

        // Self-toggle for two-factor authentication. The login flow already
        // checks user.TwoFactorEnabled and emails an OTP via the Email token
        // provider (see Program.cs Identity options) — the missing piece was a
        // way for the user to actually flip the column. The profile page used
        // to call this endpoint and silently fall back to localStorage on 404,
        // which made it look like 2FA was enabled when it never reached the DB.
        [HttpPost]
        [Route("enable-2fa")]
        [Authorize]
        public async Task<IActionResult> Enable2Fa()
        {
            var username = User.Identity?.Name;
            if (string.IsNullOrEmpty(username)) return Unauthorized("User not found in claims");

            var user = await _userManager.FindByNameAsync(username);
            if (user == null) return NotFound("User not found");

            // Pre-flight: 2FA requires a confirmed email (we send OTP there).
            // Signup auto-confirms today; this guard catches manually-created
            // users who somehow still have EmailConfirmed=false.
            if (!user.EmailConfirmed)
                return BadRequest("Your email must be confirmed before enabling two-factor authentication.");

            var setResult = await _userManager.SetTwoFactorEnabledAsync(user, true);
            if (!setResult.Succeeded)
                return BadRequest(string.Join("; ", setResult.Errors.Select(e => e.Description)));

            return Ok(new Response { IsSuccess = true, Status = "Success", Message = "Two-factor authentication enabled." });
        }

        [HttpPost]
        [Route("disable-2fa")]
        [Authorize]
        public async Task<IActionResult> Disable2Fa()
        {
            var username = User.Identity?.Name;
            if (string.IsNullOrEmpty(username)) return Unauthorized("User not found in claims");

            var user = await _userManager.FindByNameAsync(username);
            if (user == null) return NotFound("User not found");

            var setResult = await _userManager.SetTwoFactorEnabledAsync(user, false);
            if (!setResult.Succeeded)
                return BadRequest(string.Join("; ", setResult.Errors.Select(e => e.Description)));

            return Ok(new Response { IsSuccess = true, Status = "Success", Message = "Two-factor authentication disabled." });
        }

    }
}
