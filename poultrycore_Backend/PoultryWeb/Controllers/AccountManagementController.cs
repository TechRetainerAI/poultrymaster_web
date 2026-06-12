using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using PoultryWeb.Models;
using PoultryWeb.Models.Account;
using PoultryWeb.Controllers;

[Authorize]
public class AccountManagementController : Controller
{
    private readonly UserManager<AppUser> _userManager;
    private readonly SignInManager<AppUser> _signInManager;

    public AccountManagementController(UserManager<AppUser> userManager, SignInManager<AppUser> signInManager)
    {
        _userManager = userManager;
        _signInManager = signInManager;
    }

    [HttpGet]
    public async Task<IActionResult> Index()
    {
        try
        {
            var UserId = _userManager.GetUserId(User);
            //var user = await _userManager.FindByIdAsync(UserId);
            var user = await _userManager.GetUserAsync(User);
            if (user == null)
            {
                return RedirectToAction(nameof(AccountController.Login), "Account");
            }

            var model = new AccountManagement
            {
                Username = user.UserName,
                Email = user.Email,
                PhoneNumber = user.PhoneNumber
                // Add other properties as needed
            };

            return View(model);
        }
        catch (Exception ex)
        {
            // Log the exception
            //_logger.LogError(ex, "An error occurred while loading the account management page.");

            // Optionally, you can show a friendly error page or message
            // return View("Error", new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });

            // For now, redirect to the login page if an error occurs
            return RedirectToAction(nameof(HomeController.Index), "Home");
        }
    }


    [HttpGet]
    public async Task<IActionResult> Manage()
    {
        var user = await _userManager.GetUserAsync(User);
        if (user == null)
        {
            return RedirectToAction(nameof(AccountController.Login), "Account");
        }

        var model = new AccountManagement
        {
            Username = user.UserName,
            Email = user.Email,
            PhoneNumber = user.PhoneNumber
            // Add other properties as needed
        };

        return View(model);
    }

    [HttpPost]
    public async Task<IActionResult> Manage(AccountManagement model)
    {
        if (ModelState.IsValid)
        {
            var user = await _userManager.GetUserAsync(User);
            if (user == null)
            {
                return RedirectToAction(nameof(AccountController.Login), "Account");
            }

            user.Email = model.Email;
            user.PhoneNumber = model.PhoneNumber;
            // Update other properties as needed

            var result = await _userManager.UpdateAsync(user);
            if (result.Succeeded)
            {
                ViewData["SuccessMessage"] = "Your profile has been updated";
                return RedirectToAction(nameof(Index));
                //return PartialView("_ManageAccount", model);
            }

            foreach (var error in result.Errors)
            {
                ModelState.AddModelError(string.Empty, error.Description);
            }
        }
        return RedirectToAction(nameof(Index));
        //return PartialView("_ManageAccount", model);
    }
    
    [HttpGet]
    public async Task<IActionResult> ChangePassword()
    {
        return PartialView("_ChangePassword", new ChangePassword());
    }

    [HttpPost]
    public async Task<IActionResult> ChangePassword(ChangePassword model)
    {
        if (ModelState.IsValid)
        {
            var user = await _userManager.GetUserAsync(User);
            if (user == null)
            {
                return RedirectToAction(nameof(AccountController.Login), "Account");
            }

            var result = await _userManager.ChangePasswordAsync(user, model.OldPassword, model.NewPassword);
            if (result.Succeeded)
            {
                await _signInManager.RefreshSignInAsync(user);
                ViewData["SuccessMessage"] = "Your password has been changed";
                return RedirectToAction(nameof(Index));
                //return PartialView("_ChangePassword", model);
                //return RedirectToAction(nameof(Manage));
            }

            foreach (var error in result.Errors)
            {
                ModelState.AddModelError(string.Empty, error.Description);
            }
        }
        return RedirectToAction(nameof(Index));
        //return PartialView("_ChangePassword", model);
        //return RedirectToAction(nameof(Manage));
    }

    [HttpGet]
    public async Task<IActionResult> ChangeEmail()
    {
        var user = await _userManager.GetUserAsync(User);
        if (user == null)
        {
            return RedirectToAction(nameof(AccountController.Login), "Account");
        }

        var model = new ChangeEmail
        {
            Email = user.Email
        };
        return PartialView("_ChangeEmail", model);
    }

    [HttpPost]
    public async Task<IActionResult> ChangeEmail(ChangeEmail model)
    {
        if (ModelState.IsValid)
        {
            var user = await _userManager.GetUserAsync(User);
            if (user == null)
            {
                return RedirectToAction(nameof(Index));
            }

            user.Email = model.Email;
            var result = await _userManager.UpdateAsync(user);
            if (result.Succeeded)
            {
                ViewData["SuccessMessage"] = "Your email has been changed";
                return RedirectToAction(nameof(Index));
                //return PartialView("_ChangeEmail", model);
                //return Json(new { success = true, message = "Your email has been changed." });
            }

            foreach (var error in result.Errors)
            {
                ModelState.AddModelError(string.Empty, error.Description);
            }
        }
        return RedirectToAction(nameof(Index));
        //return PartialView("_ChangeEmail", model);
    }

    //[HttpGet]
    //public IActionResult CloseAccount()
    //{
    //    return PartialView("_CloseAccount");
    //}

    [HttpPost]
    public async Task<IActionResult> CloseAccount()
    {
        var user = await _userManager.GetUserAsync(User);
        if (user != null)
        {
            await _userManager.DeleteAsync(user);
            await _signInManager.SignOutAsync();
            return RedirectToAction(nameof(AccountController.Register), "Account");
            //return RedirectToAction(nameof(HomeController.Index), "Home");
        }

        return RedirectToAction(nameof(Index));
        //return RedirectToAction(nameof(Index));
    }

    //[HttpPost]
    //public async Task<IActionResult> Logout()
    //{
    //    await _signInManager.SignOutAsync();
    //    return RedirectToAction(nameof(HomeController.Index), "Home");
    //}




    //staff management
    [HttpGet]
    public async Task<IActionResult> CreateStaff()
    {
        var model = new ChangeEmail();
        return PartialView("_CreateStaff", model);
    }

    [HttpPost]
    public async Task<IActionResult> CreateStaff(Staff model, string password)
    {
        if (!ModelState.IsValid)
            return View(model);

        var farmId = User.FindFirst("FarmId")?.Value;
        var farmName = User.FindFirst("FarmName")?.Value;
        var isSubscriber = User.FindFirst("IsSubscriber")?.Value;
        //note, FirstName and LastName are already saved in the model
        //Basically setting up these important fields to assign the staff to the Farm
        //model.FarmId = farmId;
        //model.FarmName = farmName;
        //model.IsStaff = true;
        //model.NormalizedUserName = model.UserName.ToUpperInvariant();

        //var staffUser = new AppUser
        //{
        //    Id = Guid.NewGuid().ToString(),      //Creating the userID here directly
        //    FirstName = model.FirstName,
        //    LastName = model.LastName,
        //    UserName = model.UserName,
        //    PhoneNumber = model.PhoneNumber,
        //    Email = model.Email,
        //    FarmId = farmId,             //Basically setting up these important fields to assign the staff to the Farm
        //    FarmName = farmName,
        //    IsStaff = true,
        //    EmailConfirmed = true,      //Skipping because the staff account is created internally (not self-registered). You trust the admin creating the staff(no identity fraud risk).
        //    PhoneNumberConfirmed = true,
        //    TwoFactorEnabled = false,
        //    isSubscriber = Convert.ToBoolean(isSubscriber), // ✅ Corrected: capitalized + valid conversion
        //    NormalizedUserName = model.UserName.ToUpperInvariant()
        //};

        var staffUser = new AppUser
        {
            Id = Guid.NewGuid().ToString(),

            // Identity fields
            UserName = model.UserName,
            NormalizedUserName = model.UserName.ToUpperInvariant(),
            Email = model.Email,
            NormalizedEmail = model.Email?.ToUpperInvariant(),
            EmailConfirmed = true,
            PhoneNumber = model.PhoneNumber,
            PhoneNumberConfirmed = true,
            PasswordHash = "",

            // Security & Login tracking
            TwoFactorEnabled = false,
            LockoutEnabled = false,
            AccessFailedCount = 0,
            SecurityStamp = Guid.NewGuid().ToString(),
            ConcurrencyStamp = Guid.NewGuid().ToString(),

            // Custom fields
            FirstName = model.FirstName,
            LastName = model.LastName,
            FarmId = farmId,
            FarmName = farmName,
            IsStaff = true,
            IsSubscriber = Convert.ToBoolean(isSubscriber)
        };



        var result = await _userManager.CreateAsync(staffUser, password);
        if (result.Succeeded)
        {
            await _userManager.AddToRoleAsync(staffUser, "Staff");
            TempData["Success"] = "Staff user created.";
            return RedirectToAction("Create");
        }

        ModelState.AddModelError("", "Error creating staff user.");
        return PartialView("_CreateStaff", model);
    }
}
