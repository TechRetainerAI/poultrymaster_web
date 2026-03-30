
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Org.BouncyCastle.Asn1.Ocsp;
using System.Data;
using System;
using System.Linq;
using User.Management.Service.Models;
using User.Management.Service.Models.Authentication.SignUp;
using Microsoft.Extensions.Configuration;
using User.Management.Service.Models.Authentication.User;
using User.Management.Service.Models.Authentication.Login;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.IdentityModel.Tokens;
using System.Text;
using User.Management.Data.Models;
using System.Security.Cryptography;
using User.Management.Data;
using DocumentFormat.OpenXml.Wordprocessing;
using System.Text.Json;

namespace User.Management.Service.Services
{
    public class UserManagement : IUserManagement
    {
        private static readonly JsonSerializerOptions JsonOptions = new()
        {
            PropertyNameCaseInsensitive = true
        };

        private static Dictionary<string, bool>? DeserializePermissions(string? value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return null;
            }

            try
            {
                return JsonSerializer.Deserialize<Dictionary<string, bool>>(value, JsonOptions);
            }
            catch
            {
                return null;
            }
        }

        private readonly UserManager<ApplicationUser> _userManager;
        private readonly SignInManager<ApplicationUser> _signInManager;
        private readonly RoleManager<IdentityRole> _roleManager;
        private readonly IConfiguration _configuration;
        private readonly ISubscriptionService _subscriptionService;

        public UserManagement(UserManager<ApplicationUser> userManager,
            RoleManager<IdentityRole> roleManager,
            SignInManager<ApplicationUser> signInManager, IConfiguration configuration, ISubscriptionService subscriptionService)
        {
            _userManager = userManager;
            _roleManager = roleManager;
            _signInManager = signInManager;
            _configuration = configuration;
            _subscriptionService = subscriptionService;
        }

        public async Task<ApiResponse<List<string>>> AssignRoleToUserAsync(List<string> roles, ApplicationUser user)
        {
            var assignedRole = new List<string>();
            foreach (var role in roles)
            {
                if (await _roleManager.RoleExistsAsync(role))
                {
                    if (!await _userManager.IsInRoleAsync(user, role))
                    {
                        await _userManager.AddToRoleAsync(user, role);
                        assignedRole.Add(role);
                    }
                }
            }

            return new ApiResponse<List<string>> { IsSuccess=true,StatusCode=200,Message="Roles has been assigned"
            ,Response=assignedRole
            };
        }


        public async Task<ApiResponse<CreateUserResponse>> CreateUserWithTokenAsync(RegisterUser registerUser)
        {
            try
            {
                // Check if user exists
                var userExist = await _userManager.FindByEmailAsync(registerUser.Email);
                if (userExist != null)
                {
                    return new ApiResponse<CreateUserResponse>
                    {
                        IsSuccess = false,
                        StatusCode = 403,
                        Message = "User already exists!"
                    };
                }


                var farmId = Guid.NewGuid().ToString();

                // Create the user
                ApplicationUser user = new()
                {
                    FarmId = farmId,                                 //saving farmID as well
                    FarmName = registerUser.FarmName,
                    FirstName = registerUser.FirstName,
                    LastName = registerUser.LastName,
                    Email = registerUser.Email,
                    EmailConfirmed = true, // Auto-confirm email for development
                    PhoneNumber = registerUser.PhoneNumber,
                    SecurityStamp = Guid.NewGuid().ToString(),
                    UserName = registerUser.Username,
                    TwoFactorEnabled = false // true  // TOD0--- EITHER HARDCODE OR determine from UI Based on user preference
                };

                // 1. Create user
                var result = await _userManager.CreateAsync(user, registerUser.Password);
                if (result.Succeeded)
                {

                    // 2. Create the farm and get farmId
                    Farm farm = new Farm
                    {
                        FarmId = farmId,
                        Name = registerUser.FarmName,
                        Type = "Poultry",
                        Email = registerUser.Email,
                        PhoneNumber = registerUser.PhoneNumber
                    };
                    var createFarmResult = await _subscriptionService.CreateFarmAsync(farm);   
                    if (!createFarmResult)
                    {
                        //await _subscriptionService.UpdateUserFarmIdAsync(user.Id, farmId);
                        return new ApiResponse<CreateUserResponse>
                        {
                            IsSuccess = false,
                            StatusCode = 500,
                            Message = "User Created Successfully but Farm creation Failed"
                        };
                    }

                    // 4. Return success
                    var token = await _userManager.GenerateEmailConfirmationTokenAsync(user);
                    return new ApiResponse<CreateUserResponse>
                    {
                        Response = new CreateUserResponse()
                        {
                            User = user,
                            Token = token
                        },
                        IsSuccess = true,
                        StatusCode = 201,
                        Message = "User and Farm Created"
                    };
                }
                else
                {
                    // Collect all validation errors
                    var errors = string.Join(", ", result.Errors.Select(e => e.Description));
                    return new ApiResponse<CreateUserResponse>
                    {
                        IsSuccess = false,
                        StatusCode = 400,
                        Message = $"User Failed to Create: {errors}"
                    };
                }
            }
            catch (Exception ex)
            {
                // Optional: log the exception
                // _logger.LogError(ex, "Error creating user with token");

                return new ApiResponse<CreateUserResponse>
                {
                    IsSuccess = false,
                    StatusCode = 500,
                    Message = $"An unexpected error occurred: {ex.Message}"
                };
            }
        }



        //public async Task<ApiResponse<CreateUserResponse>> CreateUserWithTokenAsync(RegisterUser registerUser)
        //{
        //    //Check User Exist 
        //    var userExist = await _userManager.FindByEmailAsync(registerUser.Email);
        //    if (userExist != null)
        //    {
        //        return new ApiResponse<CreateUserResponse> { IsSuccess = false, StatusCode = 403, Message = "User already exists!" };
        //    }

        //    ApplicationUser user = new()
        //    {
        //        FirstName = registerUser.FirstName,
        //        LastName = registerUser.LastName,
        //        Email = registerUser.Email,
        //        SecurityStamp = Guid.NewGuid().ToString(),
        //        UserName = registerUser.Username,
        //        TwoFactorEnabled = true   //Give them a checkbox in the UI to determine the value of this
        //    };

        //    var result = await _userManager.CreateAsync(user, registerUser.Password);
        //    if (result.Succeeded)
        //    {
        //        var token = await _userManager.GenerateEmailConfirmationTokenAsync(user);
        //        return new ApiResponse<CreateUserResponse> { Response=new CreateUserResponse() { User= user ,Token= token },IsSuccess = true, StatusCode = 201, Message = "User Created" };
        //    }
        //    else
        //    {
        //        return new ApiResponse<CreateUserResponse> { IsSuccess = false, StatusCode = 500, Message = "User Failed to Create" };
        //    }
        //}


        public async Task<ApiResponse<LoginOtpResponse>> GetOtpByLoginAsync(LoginModel loginModel)
        {
            try
            {
                Console.WriteLine($"[Login] Attempting login for: {loginModel.Username}");
                
                // Try to find user by username first
                var user = await _userManager.FindByNameAsync(loginModel.Username);
                Console.WriteLine($"[Login] FindByNameAsync result: {(user != null ? $"Found user {user.UserName} (IsStaff={user.IsStaff}, EmailConfirmed={user.EmailConfirmed})" : "User not found by username")}");
                
                // If not found by username, try to find by email
                if (user == null)
                {
                    Console.WriteLine($"[Login] Trying FindByEmailAsync for: {loginModel.Username}");
                    user = await _userManager.FindByEmailAsync(loginModel.Username);
                    Console.WriteLine($"[Login] FindByEmailAsync result: {(user != null ? $"Found user {user.UserName} (IsStaff={user.IsStaff}, EmailConfirmed={user.EmailConfirmed})" : "User not found by email")}");
                }
                
                // If still not found, try a direct database query to see if employee exists
                if (user == null)
                {
                    Console.WriteLine($"[Login] User not found by username or email. Searching all users for potential match...");
                    var allUsers = _userManager.Users.ToList();
                    var potentialMatches = allUsers.Where(u => 
                        (u.UserName != null && u.UserName.Equals(loginModel.Username, StringComparison.OrdinalIgnoreCase)) ||
                        (u.Email != null && u.Email.Equals(loginModel.Username, StringComparison.OrdinalIgnoreCase))
                    ).ToList();
                    
                    if (potentialMatches.Any())
                    {
                        Console.WriteLine($"[Login] Found {potentialMatches.Count} potential matches (case-insensitive):");
                        foreach (var match in potentialMatches)
                        {
                            Console.WriteLine($"[Login]   - UserName: '{match.UserName}', NormalizedUserName: '{match.NormalizedUserName}', Email: '{match.Email}', NormalizedEmail: '{match.NormalizedEmail}', IsStaff: {match.IsStaff}");
                        }
                        // Try to use the first match if it's an exact case-insensitive match
                        user = potentialMatches.FirstOrDefault();
                        if (user != null)
                        {
                            Console.WriteLine($"[Login] Using case-insensitive match: {user.UserName}");
                        }
                    }
                    else
                    {
                        Console.WriteLine($"[Login] No potential matches found. Total users in database: {allUsers.Count}");
                        // Log all employees for debugging
                        var allEmployees = allUsers.Where(u => u.IsStaff).ToList();
                        Console.WriteLine($"[Login] Total employees (IsStaff=true) in database: {allEmployees.Count}");
                        foreach (var emp in allEmployees.Take(10)) // Log first 10 employees
                        {
                            Console.WriteLine($"[Login]   Employee - UserName: '{emp.UserName}', NormalizedUserName: '{emp.NormalizedUserName}', Email: '{emp.Email}', NormalizedEmail: '{emp.NormalizedEmail}'");
                        }
                    }
                }
                
                if (user != null)
                {
                    // Check if user is locked out
                    if (await _userManager.IsLockedOutAsync(user))
                    {
                        return new ApiResponse<LoginOtpResponse>
                        {
                            IsSuccess = false,
                            StatusCode = 401,
                            Message = "Account is locked out. Please try again later."
                        };
                    }
                    
                    // For employees (IsStaff = true), ensure email is confirmed
                    // Employees are created by admins and should always have confirmed emails
                    if (user.IsStaff && !user.EmailConfirmed)
                    {
                        user.EmailConfirmed = true;
                        var updateResult = await _userManager.UpdateAsync(user);
                        if (!updateResult.Succeeded)
                        {
                            // Log warning but continue - email confirmation update failed
                            Console.WriteLine($"Warning: Failed to auto-confirm email for employee {user.UserName}");
                        }
                    }
                    
                    // Verify password before proceeding
                    var passwordValid = await _signInManager.CheckPasswordSignInAsync(user, loginModel.Password, lockoutOnFailure: true);
                    
                    if (!passwordValid.Succeeded)
                    {
                        // Provide more specific error message
                        if (passwordValid.IsLockedOut)
                        {
                            return new ApiResponse<LoginOtpResponse>
                            {
                                IsSuccess = false,
                                StatusCode = 401,
                                Message = "Account is locked out due to multiple failed login attempts."
                            };
                        }
                        else if (passwordValid.IsNotAllowed)
                        {
                            // For employees, if email is still not confirmed after our attempt, provide helpful message
                            if (user.IsStaff && !user.EmailConfirmed)
                            {
                                return new ApiResponse<LoginOtpResponse>
                                {
                                    IsSuccess = false,
                                    StatusCode = 401,
                                    Message = "Employee account email confirmation issue. Please contact your administrator."
                                };
                            }
                            return new ApiResponse<LoginOtpResponse>
                            {
                                IsSuccess = false,
                                StatusCode = 401,
                                Message = "Login not allowed. Please verify your email."
                            };
                        }
                        else
                        {
                            return new ApiResponse<LoginOtpResponse>
                            {
                                IsSuccess = false,
                                StatusCode = 401,
                                Message = $"Invalid password. User: {user.UserName}, Email: {user.Email}"
                            };
                        }
                    }
                    
                    // Update last login time (commented out until database column is added)
                    // user.LastLoginTime = DateTime.UtcNow;
                    // await _userManager.UpdateAsync(user);
                    
                    if (user.TwoFactorEnabled)
                    {
                        var token = await _userManager.GenerateTwoFactorTokenAsync(user, "Email");
                        return new ApiResponse<LoginOtpResponse>
                        {
                            Response = new LoginOtpResponse()
                            {
                                User = user,
                                Token = token,
                                IsTwoFactorEnable = user.TwoFactorEnabled
                            },
                            IsSuccess = true,
                            StatusCode = 200,
                            Message = $"OTP send to the email {user.Email}"
                        };

                    }
                    else
                    {
                        return new ApiResponse<LoginOtpResponse>
                        {
                            Response = new LoginOtpResponse()
                            {
                                User = user,
                                Token = string.Empty,
                                IsTwoFactorEnable = user.TwoFactorEnabled
                            },
                            IsSuccess = true,
                            StatusCode = 200,
                            Message = $"2FA is not enabled"
                        };
                    }
                }
                else
                {
                    return new ApiResponse<LoginOtpResponse>
                    {
                        IsSuccess = false,
                        StatusCode = 404,
                        Message = $"User doesnot exist."
                    };
                }
            }
            catch (Exception ex)
            {
                // Optional: Log the exception here using your logging service
                // _logger.LogError(ex, "Error occurred in GetOtpByLoginAsync");

                return new ApiResponse<LoginOtpResponse>
                {
                    IsSuccess = false,
                    StatusCode = 500,
                    Message = $"An error occurred while processing the request. Details: {ex.Message}"
                };
            }
        }

        public async Task<ApiResponse<LoginResponse>> GetJwtTokenAsync(ApplicationUser user)
        {
            var subscription = _subscriptionService.GetSubscriberByCustomerId(user.CustomerId);  //TODO -- can make this await/async as well
            DateTime expDate;
            var isSubscriber = false;

            if (subscription != null && subscription.Status == "active")
            {
                isSubscriber = true;
                expDate = subscription.CurrentPeriodEnd;
            }
            else
            {
                expDate = DateTime.Now.AddDays(Convert.ToDouble(_configuration["TokenValidityInMinutes"]));
            }

            // Add role
            var userRole = user.IsStaff ? "Staff" : "FarmAdmin";

            var authClaims = new List<Claim>
            {
                new Claim(ClaimTypes.Name, user.UserName),
                new Claim(ClaimTypes.NameIdentifier, user.Id),
                new Claim(ClaimTypes.Email, user.Email),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
                new Claim("isSubscriber", isSubscriber.ToString()),
                new Claim("IsStaff", user.IsStaff.ToString().ToLower()),
                new Claim("FarmId", user.FarmId),
                new Claim("FarmName", user.FarmName),
                new Claim(ClaimTypes.Role, userRole)
            };

            //todo - USE THE ROLE TABLES IN THE DB SO THAT THIS WILL RETURN SOMETHING
            var userRoles = await _userManager.GetRolesAsync(user);
            foreach (var role in userRoles)
            {
                authClaims.Add(new Claim(ClaimTypes.Role, role));
            }

            var jwtToken = GetToken(authClaims); //access token
            var refreshToken = GenerateRefreshToken();
            _ = int.TryParse(_configuration["JWT:RefreshTokenValidity"], out int refreshTokenValidity);

            user.RefreshToken = refreshToken;
            user.RefreshTokenExpiry = DateTime.UtcNow.AddDays(refreshTokenValidity);
            user.IsSubscriber = isSubscriber;

          await  _userManager.UpdateAsync(user);

            return new ApiResponse<LoginResponse>
            { 
                Response=new LoginResponse()
                {
                    AccessToken=new TokenType()
                    {
                        Token = new JwtSecurityTokenHandler().WriteToken(jwtToken),
                        ExpiryTokenDate = jwtToken.ValidTo
                    },
                    RefreshToken=new TokenType()
                    {
                        Token = user.RefreshToken,
                        ExpiryTokenDate = (DateTime)user.RefreshTokenExpiry
                    },
                    UserId = user.Id,
                    Username = user.UserName,
                    IsStaff = user.IsStaff,
                    FarmId = user.FarmId,
                    FarmName = user.FarmName,
                    IsSubscriber = user.IsSubscriber,
                    IsAdmin = user.IsAdmin,
                    AdminTitle = user.AdminTitle,
                    Permissions = DeserializePermissions(user.Permissions),
                    FeaturePermissions = DeserializePermissions(user.FeaturePermissions)

                },

                IsSuccess = true,
                StatusCode = 200,
                Message = $"Token created"
            };
        }
        public async Task<ApiResponse<LoginResponse>> LoginUserWithJWTokenAsync(string otp, string userName)
        {
            var user = await _userManager.FindByNameAsync(userName);
            var signIn = await _signInManager.TwoFactorSignInAsync("Email", otp, false, false);
            if (signIn.Succeeded)
            {
                if (user != null)
                {
                    return await GetJwtTokenAsync(user);
                }
            }
            return new ApiResponse<LoginResponse>() { 

                Response=new LoginResponse()
                {

                },
                IsSuccess = false,
                StatusCode = 400,
                Message = $"Invalid Otp"
            };
        }
        public async Task InvalidateToken(string token, ApplicationUser user)
        {
            // Ensure the token being invalidated matches the user's current refresh token.
            if (user.RefreshToken == token)
            {
                // Clear the refresh token and its expiry date
                user.RefreshToken = null;
                user.RefreshTokenExpiry = DateTime.UtcNow; // Set this to ensure logical consistency

                // Update the user in the database
                var result = await _userManager.UpdateAsync(user);

                // Optionally, check the result of the update operation for success
                if (!result.Succeeded)
                {
                    //_logger.LogError("Failed to invalidate refresh token for user {UserId}. Errors: {Errors}",
                    //    user.Id, string.Join(", ", result.Errors.Select(e => e.Description)));
                    throw new ApplicationException($"Failed to update user {user.Id} during token invalidation.");
                }
            }
            else
            {
                // Log if the token does not match the user's current refresh token
                //_logger.LogWarning("Attempt to invalidate a token that does not match the current token for user {UserId}.",
                //    user.Id);
            }
        }



        public async Task<ApiResponse<LoginResponse>> RenewAccessTokenAsync(LoginResponse tokens)
        {
            var accessToken = tokens.AccessToken;
            var refreshToken = tokens.RefreshToken;
            var principal= GetClaimsPrincipal(accessToken.Token);
            var user =await _userManager.FindByNameAsync(principal.Identity.Name);
            if (refreshToken.Token!=user.RefreshToken && refreshToken.ExpiryTokenDate<=DateTime.Now )
            {
                return new ApiResponse<LoginResponse>
                {
                   
                    IsSuccess = false,
                    StatusCode = 400,
                    Message = $"Token invalid or expired"
                };
            }
            var response = await GetJwtTokenAsync(user);
            return response;
         }


        #region PrivateMethods
        private JwtSecurityToken GetToken(List<Claim> authClaims)
        {
            var authSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_configuration["JWT:Secret"]));
            _ = int.TryParse(_configuration["JWT:TokenValidityInMinutes"], out int tokenValidityInMinutes);
            var expirationTimeUtc = DateTime.UtcNow.AddMinutes(tokenValidityInMinutes);
            var localTimeZone = TimeZoneInfo.Local;
            var expirationTimeInLocalTimeZone = TimeZoneInfo.ConvertTimeFromUtc(expirationTimeUtc, localTimeZone);


            //var audiences = new List<string>
            //{
            //  "https://localhost:7010", // WebApp (token issuer)
            //  "https://localhost:7190" // PoultryAPI (resource)
            //};
            //
            //var token = new JwtSecurityToken(
            //    issuer: _configuration["JWT:ValidIssuer"],
            //    audience: audiences,     //_configuration["JWT:ValidAudience"],
            //    expires: expirationTimeInLocalTimeZone,
            //    claims: authClaims,
            //    signingCredentials: new SigningCredentials(authSigningKey, SecurityAlgorithms.HmacSha256)
            //    );
            
            var token = new JwtSecurityToken(
                issuer: _configuration["JWT:ValidIssuer"],
                audience: _configuration["JWT:ValidAudience"],
                expires: expirationTimeInLocalTimeZone,
                claims: authClaims,
                signingCredentials: new SigningCredentials(authSigningKey, SecurityAlgorithms.HmacSha256)
                );

            return token;
        }
        private string GenerateRefreshToken()
        {
            var randomNumber = new Byte[64];
            var range = RandomNumberGenerator.Create();
            range.GetBytes(randomNumber);
            return Convert.ToBase64String(randomNumber);
        }

        private ClaimsPrincipal GetClaimsPrincipal(string accessToken) 
        {
            var tokenValidationParameters = new TokenValidationParameters
            {
                ValidateAudience = false,
                ValidateIssuer = false,
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_configuration["JWT:Secret"])),
                ValidateLifetime = false
            };

            var tokenHandler = new JwtSecurityTokenHandler();
            var principal = tokenHandler.ValidateToken(accessToken, tokenValidationParameters, out SecurityToken securityToken);

            return principal;

        }



        #endregion
    }
}
