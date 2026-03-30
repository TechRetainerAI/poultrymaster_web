using PoultryWeb.Business;
using PoultryWeb.Models;
using PoultryWeb.Models.Account;
using PoultryWeb.Models.Authentication.Login;
using PoultryWeb.Models.Authentication.SignUp;
using PoultryWeb.Models.Authentication.User;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
//using User.Management.Service.Models;
using User.Management.Service.Services;
using PoultryWeb.Models.Authentication.Login;
using PoultryWeb.Models.Authentication.SignUp;
using PoultryWeb.Models.Authentication.User;
using PoultryWeb.Models.Account;
using AuthenticationService = PoultryWeb.Business.AuthenticationService;
using DocumentFormat.OpenXml.Wordprocessing;

public class AccountController : Controller
{
    private readonly AuthenticationService _authenticationService;

    private readonly UserManager<AppUser> _userManager;
    private readonly SignInManager<AppUser> _signInManager;

    private readonly IEmailService _emailService;


    public AccountController(AuthenticationService authenticationService, UserManager<AppUser> userManager, SignInManager<AppUser> signInManager, IEmailService emailService)
    {
        _userManager = userManager;
        _signInManager = signInManager;
        _authenticationService = authenticationService;
        _emailService = emailService;
    }

    //just for test to see if logged
    public IActionResult UserInfo()
    {
        if (_signInManager.IsSignedIn(User))  //still did not work -- so I am finding a alternative approach
        {
            var userName = _userManager.GetUserName(User);
            return Content($"User is signed in as {userName}");
        }
        else
        {
            return Content("User is not signed in");
        }
    }

    [HttpGet]
    public IActionResult Manage()
    {
        return View(); // Returns the login view where the user can enter their credentials
    }
    
    [HttpGet]
    public IActionResult Login()
    {
        return View(); // Returns the login view where the user can enter their credentials
    }


    [HttpPost]
    public async Task<IActionResult> Login(LoginModel loginModel)
    {
        if (ModelState.IsValid)
        {
            try
            {
                // Sign out the previous user (if any)
                await HttpContext.SignOutAsync("PoultryFarmSoftwareCookieScheme");
                // Clear existing cookies explicitly
                Response.Cookies.Delete("access_token");
                Response.Cookies.Delete("RefreshToken");

                var loginResponse = await _authenticationService.LoginAsync(loginModel);
                if (loginResponse.IsSuccess)
                {
                    //Had to get the user credentials from from response because user is not logged in
                    if (loginResponse.RequiresTwoFactor)
                    {
                        // Redirect to OTP page
                        return RedirectToAction("VerifyOtp", new { userId = loginResponse.UserId, userName = loginResponse.Username });
                        //return RedirectToAction("VerifyOtp", new { userId = loginResponse.UserId, userName = loginResponse.Username });
                        //return Json(new { isSuccess = true, requiresTwoFactor = true, userId = loginResponse.UserId, userName = loginResponse.Username, message = loginResponse.Message });
                    }

                    // Decode the JWT to extract existing claims
                    var handler = new JwtSecurityTokenHandler();
                    var jsonToken = handler.ReadToken(loginResponse.Response.AccessToken.Token) as JwtSecurityToken;
                    var jwtClaims = jsonToken.Claims.ToList();

                    // Add additional claims you want to include in the user session
                    jwtClaims.Add(new Claim("AccessToken", loginResponse.Response.AccessToken.Token));
                    var expiryDateStr = loginResponse.Response.AccessToken.ExpiryTokenDate.ToString("o");
                    jwtClaims.Add(new Claim("AccessTokenExpiryDate", expiryDateStr));
                    jwtClaims.Add(new Claim("IsSubscriber", loginResponse.Response.IsSubscriber.ToString().ToLower()));
                    jwtClaims.Add(new Claim("RememberMe", loginModel.RememberMe.ToString()));      // Add the "Remember Me" claim
                    jwtClaims.Add(new Claim(ClaimTypes.NameIdentifier, loginResponse.Response.UserId));
                    jwtClaims.Add(new Claim(ClaimTypes.Name, loginResponse.Response.Username));

                    // Add farm context
                    jwtClaims.Add(new Claim("IsStaff", loginResponse.Response.IsStaff.ToString().ToLower()));

                    if (!string.IsNullOrEmpty(loginResponse.Response.FarmId))
                    {
                        jwtClaims.Add(new Claim("FarmId", loginResponse.Response.FarmId));
                    }

                    if (!string.IsNullOrEmpty(loginResponse.Response.FarmName))
                    {
                        jwtClaims.Add(new Claim("FarmName", loginResponse.Response.FarmName));
                    }

                    // Add role
                    var role = loginResponse.Response.IsStaff ? "Staff" : "Admin";
                    jwtClaims.Add(new Claim(ClaimTypes.Role, role));


                    // Create the claims identity and principal with the combined claims
                    var claimsIdentity = new ClaimsIdentity(jwtClaims, "PoultryFarmSoftwareCookieScheme", ClaimsIdentity.DefaultNameClaimType, ClaimsIdentity.DefaultRoleClaimType);
                    var claimsPrincipal = new ClaimsPrincipal(claimsIdentity);

                    var authProperties = new AuthenticationProperties
                    {
                        IsPersistent = loginModel.RememberMe,
                        ExpiresUtc = DateTimeOffset.UtcNow.AddDays(14)
                        //ExpiresUtc = loginModel.RememberMe ? DateTimeOffset.UtcNow.AddDays(14) : (DateTimeOffset?)null
                    };

                    // Sign in the user with the created principal
                    await HttpContext.SignInAsync("PoultryFarmSoftwareCookieScheme", claimsPrincipal, authProperties);

                    // Store the tokens in session or cookies as appropriate
                    HttpContext.Session.SetString("access_token", loginResponse.Response.AccessToken.Token);
                    //The HttpOnly attribute means that the cookie cannot be accessed via JavaScript, which would prevent document.cookie from being able to read the access_token cookie.
                    //Response.Cookies.Append("access_token", loginResponse.Response.RefreshToken.Token, new CookieOptions { HttpOnly = true, Secure = true });
                    //Response.Cookies.Append("RefreshToken", loginResponse.Response.RefreshToken.Token, new CookieOptions { HttpOnly = true, Secure = true });


                    Response.Cookies.Append("access_token", loginResponse.Response.AccessToken.Token, new CookieOptions
                    {
                        Secure = true,
                        SameSite = SameSiteMode.Strict, // Or your preferred SameSite setting
                        Expires = DateTime.UtcNow.AddHours(1) // Set appropriate expiration time
                    });
                    Response.Cookies.Append("RefreshToken", loginResponse.Response.RefreshToken.Token, new CookieOptions
                    {
                        HttpOnly = true,
                        Secure = true,
                        SameSite = SameSiteMode.Strict,
                        Expires = DateTime.UtcNow.AddHours(1)
                    });

                    return RedirectToAction("Index", "Home");
                    //return Json(new { isSuccess = true, requiresTwoFactor = false, message = loginResponse.Message });
                    //return Json(new { isSuccess = true });
                }
                else
                {
                    return Json(new { isSuccess = false, message = loginResponse.Message });
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine(ex);
                return Json(new { success = false, message = "An error occurred during login." });
            }
        }
        return Json(new { success = false, message = "Invalid login attempt." });
    }
    //[HttpPost]
    //public async Task<IActionResult> Login(LoginModel loginModel)
    //{
    //    if (ModelState.IsValid)
    //    {
    //        try
    //        {
    //            // Sign out the previous user (if any)
    //            await HttpContext.SignOutAsync("PoultryFarmSoftwareCookieScheme");
    //            // Clear existing cookies explicitly
    //            Response.Cookies.Delete("access_token");
    //            Response.Cookies.Delete("RefreshToken");

    //            var loginResponse = await _authenticationService.LoginAsync(loginModel);
    //            if (loginResponse.IsSuccess)
    //            {
    //                //Had to get the user credentials from from response because user is not logged in
    //                if (loginResponse.RequiresTwoFactor)
    //                {
    //                    // Redirect to OTP page
    //                    //return RedirectToAction("VerifyOtp", new { userId = loginResponse.UserId, userName = loginResponse.Username });
    //                    //return RedirectToAction("VerifyOtp", new { userId = loginResponse.UserId, userName = loginResponse.Username });
    //                    return Json(new { isSuccess = true, requiresTwoFactor = true, userId = loginResponse.UserId, userName = loginResponse.Username, message = loginResponse.Message });
    //                }

    //                // Decode the JWT to extract existing claims
    //                var handler = new JwtSecurityTokenHandler();
    //                var jsonToken = handler.ReadToken(loginResponse.Response.AccessToken.Token) as JwtSecurityToken;
    //                var jwtClaims = jsonToken.Claims.ToList();

    //                // Add additional claims you want to include in the user session
    //                jwtClaims.Add(new Claim("AccessToken", loginResponse.Response.AccessToken.Token));
    //                var expiryDateStr = loginResponse.Response.AccessToken.ExpiryTokenDate.ToString("o");
    //                jwtClaims.Add(new Claim("AccessTokenExpiryDate", expiryDateStr));

    //                // Create the claims identity and principal with the combined claims
    //                var claimsIdentity = new ClaimsIdentity(jwtClaims, "PoultryFarmSoftwareCookieScheme", ClaimsIdentity.DefaultNameClaimType, ClaimsIdentity.DefaultRoleClaimType);
    //                var claimsPrincipal = new ClaimsPrincipal(claimsIdentity);

    //                // Add the "Remember Me" claim
    //                jwtClaims.Add(new Claim("RememberMe", loginModel.RememberMe.ToString()));

    //                var authProperties = new AuthenticationProperties
    //                {
    //                    IsPersistent = loginModel.RememberMe,
    //                    ExpiresUtc = DateTimeOffset.UtcNow.AddDays(14)
    //                    //ExpiresUtc = loginModel.RememberMe ? DateTimeOffset.UtcNow.AddDays(14) : (DateTimeOffset?)null
    //                };

    //                // Sign in the user with the created principal
    //                await HttpContext.SignInAsync("PoultryFarmSoftwareCookieScheme", claimsPrincipal, authProperties);

    //                // Store the tokens in session or cookies as appropriate
    //                HttpContext.Session.SetString("access_token", loginResponse.Response.AccessToken.Token);
    //                //The HttpOnly attribute means that the cookie cannot be accessed via JavaScript, which would prevent document.cookie from being able to read the access_token cookie.
    //                //Response.Cookies.Append("access_token", loginResponse.Response.RefreshToken.Token, new CookieOptions { HttpOnly = true, Secure = true });
    //                //Response.Cookies.Append("RefreshToken", loginResponse.Response.RefreshToken.Token, new CookieOptions { HttpOnly = true, Secure = true });


    //                Response.Cookies.Append("access_token", loginResponse.Response.AccessToken.Token, new CookieOptions
    //                {
    //                    Secure = true,
    //                    SameSite = SameSiteMode.Strict, // Or your preferred SameSite setting
    //                    Expires = DateTime.UtcNow.AddHours(1) // Set appropriate expiration time
    //                });
    //                Response.Cookies.Append("RefreshToken", loginResponse.Response.RefreshToken.Token, new CookieOptions
    //                {
    //                    HttpOnly = true,
    //                    Secure = true,
    //                    SameSite = SameSiteMode.Strict,
    //                    Expires = DateTime.UtcNow.AddHours(1)
    //                });


    //                return Json(new { isSuccess = true, requiresTwoFactor=false, message = loginResponse.Message });
    //                //return Json(new { isSuccess = true });
    //            }
    //            else
    //            {
    //                return Json(new { isSuccess = false, message = loginResponse.Message });
    //            }
    //        }
    //        catch (Exception ex)
    //        {
    //            Console.WriteLine(ex);
    //            return Json(new { success = false, message = "An error occurred during login." });
    //        }
    //    }
    //    return Json(new { success = false, message = "Invalid login attempt." });
    //}

    [HttpGet]
    public IActionResult VerifyOtp(string userId, string userName)
    {
        return View(new Otp { UserId = userId, UserName = userName });
    }

    [HttpPost]
    public async Task<IActionResult> VerifyAndLoginWithOTP(Otp model)
    {
        if (ModelState.IsValid)
        {
            var loginResponse = await _authenticationService.VerifyAndLoginWithOTPAsync(model);
            if (loginResponse.IsSuccess)
            {
                // Handle successful OTP verification
                // Set cookies, session, or other authentication mechanisms here
                // Decode the JWT to extract existing claims
                var handler = new JwtSecurityTokenHandler();
                var jsonToken = handler.ReadToken(loginResponse.Response.AccessToken.Token) as JwtSecurityToken;
                var jwtClaims = jsonToken.Claims.ToList();

                // Add additional claims you want to include in the user session
                jwtClaims.Add(new Claim("AccessToken", loginResponse.Response.AccessToken.Token));
                var expiryDateStr = loginResponse.Response.AccessToken.ExpiryTokenDate.ToString("o");
                jwtClaims.Add(new Claim("AccessTokenExpiryDate", expiryDateStr));

                // Create the claims identity and principal with the combined claims
                var claimsIdentity = new ClaimsIdentity(jwtClaims, "PoultryFarmSoftwareCookieScheme", ClaimsIdentity.DefaultNameClaimType, ClaimsIdentity.DefaultRoleClaimType);
                var claimsPrincipal = new ClaimsPrincipal(claimsIdentity);

                // Sign in the user with the created principal
                //await HttpContext.SignInAsync("PoultryFarmSoftwareCookieScheme", claimsPrincipal);
                var rememberMe = true;  //todo: get from db
                // Set the authentication properties
                var authProperties = new AuthenticationProperties
                {
                    IsPersistent = rememberMe,
                    ExpiresUtc = rememberMe ? DateTimeOffset.UtcNow.AddDays(14) : (DateTimeOffset?)null
                };

                // Sign in the user with the created principal
                await HttpContext.SignInAsync("PoultryFarmSoftwareCookieScheme", claimsPrincipal, authProperties);

                // Store the tokens in session or cookies as appropriate
                HttpContext.Session.SetString("access_token", loginResponse.Response.AccessToken.Token);
                //The HttpOnly attribute means that the cookie cannot be accessed via JavaScript, which would prevent document.cookie from being able to read the access_token cookie.
                //Response.Cookies.Append("access_token", loginResponse.Response.RefreshToken.Token, new CookieOptions { HttpOnly = true, Secure = true });
                //Response.Cookies.Append("RefreshToken", loginResponse.Response.RefreshToken.Token, new CookieOptions { HttpOnly = true, Secure = true });
                Response.Cookies.Append("access_token", loginResponse.Response.AccessToken.Token, new CookieOptions
                {
                    Secure = true,
                    SameSite = SameSiteMode.Strict, // Or your preferred SameSite setting
                    Expires = DateTime.UtcNow.AddHours(1) // Set appropriate expiration time
                });
                Response.Cookies.Append("RefreshToken", loginResponse.Response.RefreshToken.Token, new CookieOptions
                {
                    HttpOnly = true,
                    Secure = true,
                    SameSite = SameSiteMode.Strict,
                    Expires = DateTime.UtcNow.AddHours(1)
                });
                return RedirectToAction("Index", "Home");
            }
            ModelState.AddModelError("", loginResponse.Message);
        }
        return View("OtpVerificationFailure");
    }


    [HttpGet]
    public IActionResult LogoutView()
    {
        return View(); // Returns the login view where the user can enter their credentials
    }

    [HttpPost]
    public async Task<IActionResult> Logout()
    {
        try
        {
            // Optional: Call the API to handle server-side logout if necessary
            var accessToken = HttpContext.Session.GetString("access_token");
            if (!string.IsNullOrEmpty(accessToken))
            {
                await _authenticationService.LogoutAsync(accessToken);
            }

            // Clear the session and cookies
            HttpContext.Session.Remove("access_token");
            Response.Cookies.Delete("RefreshToken");

            // Sign out the user
            await HttpContext.SignOutAsync("PoultryFarmSoftwareCookieScheme");

            return RedirectToAction("Login", "Account");
        }
        catch (Exception ex)
        {
            // Handle exceptions if needed
            Console.WriteLine(ex);
            return RedirectToAction("Login", "Account");
        }
    }


    [HttpGet]
    public IActionResult Register()
    {
        return View(); // Returns the registration view
    }

    [HttpPost]
    public async Task<IActionResult> Register(RegisterUser model)
    {
        // 1) If you expect to do server-side validation:
        if (!ModelState.IsValid)
        {
            return Json(new { success = false, message = "Invalid data." });
        }

        // 2) Then call your registration logic
        var response = await _authenticationService.RegisterAsync(model);
        if (response.IsSuccess)
        {
            //return Json(new { success = true });
            // Handle successful registration - will happen at the UI
            return RedirectToAction("ConfirmEmailPrompt"); // Redirect to confirmation prompt view
            //return RedirectToAction("Login"); // Redirect to login after successful registration  -- test
        }
        else
        {
            // Possibly add ModelState errors if you want
            return Json(new { success = false, message = response.Message });
        }
    }


    //[HttpPost]
    //public async Task<IActionResult> Register1(string FirstName, string LastName, string Username, string Email, string Password, string ConfirmPassword)  
    ////public async Task<IActionResult> Register1(RegisterUser model)
    //{
    //    // 1) If you expect to do server-side validation:
    //    //if (!ModelState.IsValid)
    //    //{
    //    //    return Json(new { success = false, message = "Invalid data." });
    //    //}
    //    RegisterUser model = new RegisterUser();
    //    model.FirstName = FirstName;
    //    model.LastName = LastName;  
    //    model.Username = Username;  
    //    model.Email = Email;    
    //    model.Password = Password;  
    //    model.ConfirmPassword = ConfirmPassword;    

    //    // 2) Then call your registration logic
    //    var response = await _authenticationService.RegisterAsync(model);
    //    if (response.IsSuccess)
    //    {
    //        return Json(new { success = true });
    //        // Handle successful registration - will happen at the UI
    //        //            //return RedirectToAction("ConfirmEmailPrompt"); // Redirect to confirmation prompt view
    //        //            //return RedirectToAction("Login"); // Redirect to login after successful registration
    //    }
    //    else
    //    {
    //        // Possibly add ModelState errors if you want
    //        return Json(new { success = false, message = response.Message });
    //    }
    //}


    //[HttpPost]
    //public async Task<IActionResult> Register(RegisterUser model)
    //{
    //    if (ModelState.IsValid)
    //    {
    //        var response = await _authenticationService.RegisterAsync(model);
    //        if (response.IsSuccess)
    //        {
    //            return Json(new { success = true });
    //            // Handle successful registration - will happen at the UI
    //            //return RedirectToAction("ConfirmEmailPrompt"); // Redirect to confirmation prompt view
    //            //return RedirectToAction("Login"); // Redirect to login after successful registration
    //        }
    //        ModelState.AddModelError("", response.Message);
    //    }
    //    return Json(new { success = false, message = "An error occurred during Registration." });
    //    //return View(model); // Return to registration view with validation messages
    //}

    [HttpGet]
    public IActionResult ConfirmEmailPrompt()
    {
        return View();
    }

    [HttpGet]
    public IActionResult ConfirmEmailSuccess()
    {
        return View();
    }

    [HttpGet]
    public IActionResult ConfirmEmailError()
    {
        return View();
    }

    [HttpGet]
    public async Task<IActionResult> ConfirmEmail(string token, string email)
    {
        var response = await _authenticationService.ConfirmEmailAsync(token, email);
        if (response.IsSuccess)
        {
            // Email confirmed successfully
            ViewBag.Message = "Email confirmed successfully.";
            return View("ConfirmEmailSuccess"); // Redirect to a confirmation success view
        }
        ViewBag.Message = "Error confirming your email.";
        return View("ConfirmEmailError"); // Redirect to an error view if confirmation fails
    }
  
    [HttpPost]
    public async Task<IActionResult> RefreshToken(string refreshToken)
    {
        var response = await _authenticationService.RefreshTokenAsync(refreshToken);
        if (response.IsSuccess)
        {
            // Refresh token successful, update token in client
            return Json(new { AccessToken = response.AccessToken, RefreshToken = response.RefreshToken });
        }
        return BadRequest("Invalid refresh token.");
    }


    #region ForgotPassword
    [HttpGet]
    public IActionResult ForgotPassword()
    {
        return View();
    }


    [HttpPost]
    public async Task<IActionResult> ForgotPassword(ForgotPassword model)
    {
        if (ModelState.IsValid)
        {
            bool result = await _authenticationService.ForgotPasswordAsync(model);
            if (result)
            {
                return RedirectToAction("ForgotPasswordConfirmation");
            }
        }

        return View(model);
    }

    [HttpGet]
    public IActionResult ResetPassword(string token, string email)
    {
        return View(new ResetPassword { Token = token, Email = email });
    }

    [HttpPost]
    public async Task<IActionResult> ResetPassword(ResetPassword model)
    {
        if (ModelState.IsValid)
        {
            bool result = await _authenticationService.ResetPasswordAsync(model);
            if (result)
            {
                return RedirectToAction("ResetPasswordConfirmation");
            }
        }

        return View(model);
    }

    [HttpGet]
    public IActionResult ForgotPasswordConfirmation()
    {
        return View();
    }

    
    [HttpGet]
    public IActionResult ResetPasswordConfirmation()
    {
        return View();
    }
    #endregion
}
