
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
        // Signup creates its first company through the SAME path as the Business
        // Office (ICompanyDAL -> spcompany_create). See CreateUserWithTokenAsync.
        private readonly ICompanyDAL _companyDal;

        public UserManagement(UserManager<ApplicationUser> userManager,
            RoleManager<IdentityRole> roleManager,
            SignInManager<ApplicationUser> signInManager, IConfiguration configuration,
            ISubscriptionService subscriptionService, ICompanyDAL companyDal)
        {
            _userManager = userManager;
            _roleManager = roleManager;
            _signInManager = signInManager;
            _configuration = configuration;
            _subscriptionService = subscriptionService;
            _companyDal = companyDal;
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
                // Check if user exists. Deliberately NOT using FindByEmailAsync:
                // that helper does a SingleOrDefault on NormalizedEmail and throws
                // "Sequence contains more than one element" when the DB holds
                // duplicate rows for the same email (Identity doesn't enforce
                // unique emails by default). A FirstOrDefault lookup is duplicate-safe.
                var normalizedEmail = _userManager.NormalizeEmail(registerUser.Email);
                var userExist = _userManager.Users
                    .Where(u => u.NormalizedEmail == normalizedEmail)
                    .ToList()
                    .FirstOrDefault();
                if (userExist != null)
                {
                    // Name the field that actually clashed. "User already exists!" left people
                    // guessing whether it was the email, the username, or the company — and
                    // gave them no idea what to do next.
                    return new ApiResponse<CreateUserResponse>
                    {
                        IsSuccess = false,
                        StatusCode = 409,
                        Message = $"An account with the email {registerUser.Email} already exists. "
                                + "Please log in instead, or use \"Forgot password\" if you cannot get in."
                    };
                }

                // Prompt 3 — Organization Code: normalize, validate, and ensure
                // it's globally unique before we create anything (fail fast so we
                // don't orphan a user when the code is taken).
                var orgCode = User.Management.Service.Helpers.OrgCode.Normalize(registerUser.OrganizationCode);
                if (!string.IsNullOrEmpty(orgCode))
                {
                    var codeError = User.Management.Service.Helpers.OrgCode.Validate(orgCode);
                    if (codeError != null)
                        return new ApiResponse<CreateUserResponse> { IsSuccess = false, StatusCode = 400, Message = codeError };

                    var codeTaken = _userManager.Users.Where(u => u.OrganizationCode == orgCode).ToList().Any();
                    if (codeTaken)
                        return new ApiResponse<CreateUserResponse> { IsSuccess = false, StatusCode = 409, Message = "This Organization Code is already taken." };
                }

                // Company is optional at signup — owners can create their first
                // company later in the Business Office. Only mint a FarmId when a
                // company is actually being created.
                bool hasCompany = !string.IsNullOrWhiteSpace(registerUser.FarmName)
                               && !string.IsNullOrWhiteSpace(registerUser.CompanyType);
                var farmId = hasCompany ? Guid.NewGuid().ToString() : string.Empty;

                // Create the user.
                // EmailConfirmed = true: signup auto-confirms; the controller does not send a
                // verification email. Flip this (and the controller) if you want strict verification.
                ApplicationUser user = new()
                {
                    FarmId = farmId,                                 //saving farmID as well
                    FarmName = registerUser.FarmName ?? string.Empty,
                    FirstName = registerUser.FirstName,
                    LastName = registerUser.LastName,
                    Email = registerUser.Email,
                    EmailConfirmed = true,
                    PhoneNumber = registerUser.PhoneNumber,
                    SecurityStamp = Guid.NewGuid().ToString(),
                    UserName = registerUser.Username,
                    // Prompt 2 — persist the owner's Business Office (migration 118).
                    BusinessOfficeName = registerUser.BusinessOfficeName,
                    BusinessOfficeCurrency = registerUser.BusinessOfficeCurrency,
                    BusinessOfficeCountry = registerUser.BusinessOfficeCountry,
                    OrganizationCode = string.IsNullOrEmpty(orgCode) ? null : orgCode,
                    IsOrgCodeActive = string.IsNullOrEmpty(orgCode) ? (bool?)null : true,
                    TwoFactorEnabled = false // true  // TOD0--- EITHER HARDCODE OR determine from UI Based on user preference
                };

                // 1. Create user
                var result = await _userManager.CreateAsync(user, registerUser.Password);
                if (result.Succeeded)
                {
                    // Belt-and-braces: some Identity store configurations don't persist
                    // ApplicationUser custom columns (FirstName/LastName/PhoneNumber/FarmName/
                    // EmailConfirmed) on the initial CreateAsync. AdminService.CreateEmployeeAsync
                    // hit the same issue and worked around it with an explicit UpdateAsync —
                    // mirror that here so /profile shows what the user actually typed at signup.
                    user.FirstName       = registerUser.FirstName;
                    user.LastName        = registerUser.LastName;
                    user.PhoneNumber     = registerUser.PhoneNumber;
                    // Coalesce: a Business-Office-only signup sends no company, and a null
                    // here would later blow up the "FarmName" JWT claim (Claim() rejects null).
                    user.FarmName        = registerUser.FarmName ?? string.Empty;
                    user.EmailConfirmed  = true;
                    user.BusinessOfficeName     = registerUser.BusinessOfficeName;
                    user.BusinessOfficeCurrency = registerUser.BusinessOfficeCurrency;
                    user.BusinessOfficeCountry  = registerUser.BusinessOfficeCountry;
                    user.OrganizationCode       = string.IsNullOrEmpty(orgCode) ? null : orgCode;
                    user.IsOrgCodeActive        = string.IsNullOrEmpty(orgCode) ? (bool?)null : true;
                    var ensureFields = await _userManager.UpdateAsync(user);
                    if (!ensureFields.Succeeded)
                    {
                        // Console matches the diagnostic style used elsewhere in this
                        // codebase (e.g. SubscriptionDAL). Failure here is non-fatal — the
                        // user still exists, just with stale profile columns we can repair
                        // later on /profile save.
                        Console.WriteLine(
                            $"[CreateUserWithTokenAsync] UpdateAsync after CreateAsync failed for {user.UserName}: " +
                            string.Join("; ", ensureFields.Errors.Select(e => e.Description)));
                    }

                    // 2. Create the first company — ONLY if one was provided. Owners
                    // may register with no company and create it later in the
                    // Business Office.
                    //
                    // This goes through ICompanyDAL.CreateAsync (spcompany_create) — the
                    // exact same path as POST /api/Companies from the Business Office —
                    // rather than the old sp_createfarm. sp_createfarm only INSERTs the
                    // farms row: it never sets farms.owneruserid and never writes the
                    // userfarms membership row. spCompany_GetByUserId (/Companies/mine)
                    // returns a company only when one of those two exists, so a company
                    // created at signup was invisible to the person who just created it —
                    // it looked like "only the Business Office was created".
                    // spcompany_create writes farms + owneruserid + userfarms together and
                    // handles all three company types via p_type, so there is one company
                    // creation path for the whole product.
                    if (hasCompany)
                    {
                        var companyRequest = new CreateCompanyRequest
                        {
                            Name = registerUser.FarmName!,
                            Type = registerUser.CompanyType!,
                            Email = registerUser.Email,
                            PhoneNumber = registerUser.PhoneNumber
                        };

                        var companyCreated = false;
                        try
                        {
                            // Throws (rather than returning false) when the SP yields no row.
                            await _companyDal.CreateAsync(farmId, companyRequest, user.Id);
                            companyCreated = true;
                        }
                        catch (Exception companyEx)
                        {
                            Console.WriteLine(
                                $"[CreateUserWithTokenAsync] Company creation failed for {user.UserName} " +
                                $"(FarmId={farmId}, Type={registerUser.CompanyType}): {companyEx.Message}");
                        }

                        if (!companyCreated)
                        {
                            // The account is NOT coupled to the company. Signup can create a
                            // Business Office on its own, so a company failure is a partial
                            // success, not a reason to destroy a valid account — this used to
                            // compensating-delete the user and hand back a 500.
                            //
                            // Clear the minted FarmId/FarmName: the Farms row was never
                            // inserted, and leaving them set would point the account at a farm
                            // that does not exist (the orphan-FarmId mess migration 046 had to
                            // clean up). Blank is exactly the "Business Office only" state, so
                            // the owner just creates the company from there.
                            user.FarmId = string.Empty;
                            user.FarmName = string.Empty;
                            await _userManager.UpdateAsync(user);

                            return new ApiResponse<CreateUserResponse>
                            {
                                Response = new CreateUserResponse { User = user, Token = string.Empty },
                                IsSuccess = true,
                                StatusCode = 201,
                                Message = "Account created, but the company could not be set up. "
                                        + "You can add it from your Business Office after logging in."
                            };
                        }
                    }

                    // 4. Return success (no email-confirmation token: signup is auto-confirmed).
                    return new ApiResponse<CreateUserResponse>
                    {
                        Response = new CreateUserResponse()
                        {
                            User = user,
                            Token = string.Empty
                        },
                        IsSuccess = true,
                        StatusCode = 201,
                        Message = "User and Farm Created"
                    };
                }
                else
                {
                    // A taken username is a conflict, not a malformed request, and it deserves
                    // the same plain wording as the duplicate-email case above. Identity reports
                    // it as DuplicateUserName; everything else here is genuine validation
                    // (password rules, invalid characters) and is already readable on its own.
                    if (result.Errors.Any(e => e.Code == "DuplicateUserName"))
                    {
                        return new ApiResponse<CreateUserResponse>
                        {
                            IsSuccess = false,
                            StatusCode = 409,
                            Message = $"The username {registerUser.Username} is already taken. "
                                    + "Please choose a different one."
                        };
                    }

                    // Collect all validation errors
                    var errors = string.Join(", ", result.Errors.Select(e => e.Description));
                    return new ApiResponse<CreateUserResponse>
                    {
                        IsSuccess = false,
                        StatusCode = 400,
                        Message = errors
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
                
                // If not found by username, try to find by email. Use a
                // FirstOrDefault lookup, not FindByEmailAsync — the latter does a
                // SingleOrDefault on NormalizedEmail and throws "Sequence contains
                // more than one element" when duplicate rows share an email
                // (Identity allows non-unique emails). FirstOrDefault is safe.
                if (user == null)
                {
                    Console.WriteLine($"[Login] Trying email lookup for: {loginModel.Username}");
                    var normalizedEmail = _userManager.NormalizeEmail(loginModel.Username);
                    user = _userManager.Users
                        .Where(u => u.NormalizedEmail == normalizedEmail)
                        .ToList()
                        .FirstOrDefault();
                    Console.WriteLine($"[Login] Email lookup result: {(user != null ? $"Found user {user.UserName} (IsStaff={user.IsStaff}, EmailConfirmed={user.EmailConfirmed})" : "User not found by email")}");
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
                // Claim(type, value) throws on a null value. An owner who registered with
                // a Business Office but no company legitimately has neither yet, so
                // coalesce rather than crash their login.
                new Claim("FarmId", user.FarmId ?? string.Empty),
                new Claim("FarmName", user.FarmName ?? string.Empty),
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
                    BusinessOfficeName = user.BusinessOfficeName,
                    OrganizationCode = user.OrganizationCode,
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
            // Robust lookup: by username, then by email (the user may have signed in
            // with either). FirstOrDefault — not FindByEmailAsync — so duplicate
            // emails don't throw.
            var user = await _userManager.FindByNameAsync(userName);
            if (user == null && !string.IsNullOrWhiteSpace(userName))
            {
                var ne = _userManager.NormalizeEmail(userName);
                user = _userManager.Users.Where(u => u.NormalizedEmail == ne).ToList().FirstOrDefault();
            }

            if (user != null && !string.IsNullOrWhiteSpace(otp))
            {
                // Stateless verification. _signInManager.TwoFactorSignInAsync needs the
                // two-factor cookie that PasswordSignInAsync sets — but this JWT API
                // (behind the same-origin proxy / Cloud Run, no cookies) never
                // establishes it, so it always failed with "Invalid Otp".
                // VerifyTwoFactorTokenAsync checks the code directly against the user's
                // security stamp + time window — no cookie required.
                var valid = await _userManager.VerifyTwoFactorTokenAsync(user, "Email", otp.Trim());
                if (valid)
                    return await GetJwtTokenAsync(user);
            }

            return new ApiResponse<LoginResponse>()
            {
                Response = new LoginResponse() { },
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
