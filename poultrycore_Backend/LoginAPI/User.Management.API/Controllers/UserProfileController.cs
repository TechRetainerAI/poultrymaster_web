using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using User.Management.Data;
using User.Management.Data.Models;
using User.Management.Service.Services;

/// <summary>
/// Read/update of user profile rows.
///
/// Page access upgrade (security fix b): this controller had no [Authorize],
/// so anyone could read any account — password hash and security stamp
/// included — or rewrite any account's IsAdmin / FeaturePermissions. Now:
/// signed-in only; you read and update your own profile (or, for reads, an
/// employee you may manage); secrets never leave the server; access fields
/// (admin, staff, permissions, company) cannot be changed here at all; and
/// accounts are created and deleted only through the employee screens.
/// </summary>
[ApiController]
[Authorize]
[Route("api/[controller]")]
public class UserProfileController : ControllerBase
{
    private readonly IUserProfileService _userProfileService;
    private readonly ICompanyDAL _companies;

    public UserProfileController(IUserProfileService userProfileService, ICompanyDAL companies)
    {
        _userProfileService = userProfileService;
        _companies = companies;
    }

    private string? CallerId => User.FindFirstValue(ClaimTypes.NameIdentifier);
    private string? CallerName => User.FindFirstValue(ClaimTypes.Name);

    private ObjectResult Denied(string message) =>
        StatusCode(StatusCodes.Status403Forbidden, new { code = "forbidden", message });

    /// <summary>Never send credentials or tokens to a browser.</summary>
    private static ApplicationUser? Scrub(ApplicationUser? user)
    {
        if (user is null) return null;
        user.PasswordHash = null;
        user.SecurityStamp = null;
        user.ConcurrencyStamp = null;
        user.RefreshToken = null;
        return user;
    }

    private async Task<bool> MayRead(ApplicationUser target)
    {
        var caller = CallerId;
        if (string.IsNullOrWhiteSpace(caller)) return false;
        if (string.Equals(target.Id, caller, StringComparison.OrdinalIgnoreCase)) return true;
        return await _companies.MayManageEmployeeAsync(caller, target.Id, "office.employees.view");
    }

    [HttpPost("create")]
    public IActionResult CreateUser([FromBody] ApplicationUser user)
        => Denied("Accounts are created through registration or the employee screens.");

    [HttpPut]
    [Route("update")]
    public async Task<IActionResult> UpdateUser([FromBody] ApplicationUser user)
    {
        var caller = CallerId;
        if (string.IsNullOrWhiteSpace(caller) || !string.Equals(user.Id, caller, StringComparison.OrdinalIgnoreCase))
            return Denied("You can only update your own profile.");

        var existing = await _userProfileService.FindByIdAsync(caller);
        if (existing is null) return NotFound();

        // Access fields and credentials always come from the stored record.
        user.IsStaff = existing.IsStaff;
        user.IsAdmin = existing.IsAdmin;
        user.AdminTitle = existing.AdminTitle;
        user.Permissions = existing.Permissions;
        user.FeaturePermissions = existing.FeaturePermissions;
        user.IsSubscriber = existing.IsSubscriber;
        user.FarmId = existing.FarmId;
        user.FarmName = existing.FarmName;
        user.OrganizationCode = existing.OrganizationCode;
        user.PasswordHash = existing.PasswordHash;
        user.SecurityStamp = existing.SecurityStamp;
        user.RefreshToken = existing.RefreshToken;
        user.UserName = existing.UserName;
        user.NormalizedUserName = existing.NormalizedUserName;

        var result = await _userProfileService.UpdateAsync(user);
        return Ok(result);
    }

    [HttpDelete("{id}")]
    public IActionResult DeleteUser(string id)
        => Denied("Employees are removed through the employee screens.");

    [HttpGet("find")]
    public async Task<IActionResult> FindById(string id)
    {
        var result = await _userProfileService.FindByIdAsync(id);
        if (result is null) return NotFound();
        if (!await MayRead(result)) return Denied("You can only view your own profile.");
        return Ok(Scrub(result));
    }

    [HttpGet("findByUserName")]
    public async Task<IActionResult> FindByUserName(string normalizedUserName)
    {
        var result = await _userProfileService.FindByNameAsync(normalizedUserName);
        if (result is null) return NotFound();
        if (!await MayRead(result)) return Denied("You can only view your own profile.");
        return Ok(Scrub(result));
    }
}
