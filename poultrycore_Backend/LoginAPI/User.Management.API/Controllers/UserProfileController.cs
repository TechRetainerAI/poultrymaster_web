using Microsoft.AspNetCore.Mvc;
using User.Management.Data.Models;
using User.Management.Service.Services;

[ApiController]
[Route("api/[controller]")]
public class UserProfileController : ControllerBase
{
    private readonly IUserProfileService _userProfileService;

    public UserProfileController(IUserProfileService userProfileService)
    {
        _userProfileService = userProfileService;
    }

    [HttpPost("create")]
    public async Task<IActionResult> CreateUser([FromBody] ApplicationUser user)
    {
        var result = await _userProfileService.CreateAsync(user);
        return Ok(result);
    }

    //[HttpPut("update")]
    [HttpPut]
    [Route("update")]
    public async Task<IActionResult> UpdateUser([FromBody] ApplicationUser user)
    {
        var result = await _userProfileService.UpdateAsync(user);
        return Ok(result);
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> DeleteUser(string id)
    {
        var result = await _userProfileService.DeleteAsync(id);
        return Ok(result);
    }

    //[HttpGet("find/{id}")]
    [HttpGet("find")]
    public async Task<IActionResult> FindById(string id)
    {
        var result = await _userProfileService.FindByIdAsync(id);
        return Ok(result);
    }

    //[HttpGet("find/username/{normalizedUserName}")]
    [HttpGet("findByUserName")]
    public async Task<IActionResult> FindByUserName(string normalizedUserName)
    {
        var result = await _userProfileService.FindByNameAsync(normalizedUserName);
        return Ok(result);
    }



    //COMMENTED OUT BECAUE THERE IS NO NEED TO CALL THESE ENDPOINTS HERE -- WE WILL CALL THEM DIRECTLY IN THE CUSTOMUSERSTORE
    ////[HttpGet("password-hash/{id}")]
    //[HttpGet("passwordHash")]
    //public async Task<IActionResult> GetPasswordHash([FromBody] ApplicationUser user)
    //{
    //    var result = await _userProfileService.GetPasswordHashAsync(user);
    //    return Ok(result);
    //}

    ////[HttpPost("set-password-hash/{id}")]
    //[HttpPost("set-password-hash")]
    //public async Task<IActionResult> SetPasswordHash([FromBody] ApplicationUser user, string passwordHash)
    //{
    //    await _userProfileService.SetPasswordHashAsync(user, passwordHash);
    //    return Ok(true);
    //}

    ////[HttpGet("has-password/{id}")]
    //[HttpGet("password")]
    //public async Task<IActionResult> HasPassword([FromBody] ApplicationUser user)
    //{
    //    var result = await _userProfileService.HasPasswordAsync(user);
    //    return Ok(result);
    //}
}
