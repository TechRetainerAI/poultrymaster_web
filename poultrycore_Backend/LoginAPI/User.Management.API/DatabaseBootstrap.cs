using Microsoft.AspNetCore.Identity;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using User.Management.Data.Models;
using User.Management.Service.Services;

namespace User.Management.API;

/// <summary>
/// Optional EF migrations + Identity role/user seeding (see appsettings DatabaseBootstrap and DATABASE_SETUP.txt).
/// </summary>
public static class DatabaseBootstrap
{
    private static readonly string[] RolesToEnsure =
    {
        "SystemAdmin", "PlatformOwner", "Staff", "FarmAdmin", "Admin", "User", "HR",
    };

    private static readonly string[] PlatformOwnerRoles = { "SystemAdmin", "PlatformOwner" };

    private static async Task EnsurePlatformDirectoryRolesAsync(
        UserManager<ApplicationUser> userManager,
        ApplicationUser user,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        foreach (var role in PlatformOwnerRoles)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (await userManager.IsInRoleAsync(user, role))
                continue;
            var r = await userManager.AddToRoleAsync(user, role);
            if (!r.Succeeded)
            {
                logger.LogWarning(
                    "DatabaseBootstrap: could not add role {Role} to {User}: {Errors}",
                    role,
                    user.UserName,
                    string.Join("; ", r.Errors.Select(e => e.Description)));
            }
        }
    }

    public static async Task ApplyAsync(WebApplication app, CancellationToken cancellationToken = default)
    {
        var config = app.Configuration;
        var logger = app.Logger;

        using var scope = app.Services.CreateScope();
        var services = scope.ServiceProvider;
        var db = services.GetRequiredService<ApplicationDbContext>();

        if (config.GetValue("DatabaseBootstrap:ApplyMigrations", false))
        {
            try
            {
                await db.Database.MigrateAsync(cancellationToken);
                logger.LogInformation("DatabaseBootstrap: EF Core migrations applied.");
            }
            catch (SqlException ex) when (ex.Number is 2714 or 1913)
            {
                // 2714: object already exists — DB was created outside EF or migrations partially applied.
                // 1913: operation failed because another object depends on it (varies by server state).
                logger.LogWarning(
                    ex,
                    "DatabaseBootstrap: MigrateAsync stopped ({Number}); treating database as already initialized.",
                    ex.Number);
            }
        }

        if (!config.GetValue("DatabaseBootstrap:SeedIdentity", false))
            return;

        var roleManager = services.GetRequiredService<RoleManager<IdentityRole>>();
        var userManager = services.GetRequiredService<UserManager<ApplicationUser>>();
        var subscriptionService = services.GetRequiredService<ISubscriptionService>();

        foreach (var roleName in RolesToEnsure.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (!await roleManager.RoleExistsAsync(roleName))
            {
                var r = await roleManager.CreateAsync(new IdentityRole(roleName));
                if (!r.Succeeded)
                {
                    logger.LogError(
                        "DatabaseBootstrap: failed to create role {Role}: {Errors}",
                        roleName,
                        string.Join("; ", r.Errors.Select(e => e.Description)));
                }
                else
                {
                    logger.LogInformation("DatabaseBootstrap: created Identity role {Role}.", roleName);
                }
            }
        }

        var userName = (config["DatabaseBootstrap:SystemAdminUserName"] ?? "systemadmin").Trim();
        var email = (config["DatabaseBootstrap:SystemAdminEmail"] ?? "systemadmin@localhost").Trim();
        var password = config["DatabaseBootstrap:SystemAdminPassword"];

        if (string.IsNullOrWhiteSpace(password))
        {
            logger.LogWarning(
                "DatabaseBootstrap:SeedIdentity is true but SystemAdminPassword is empty. " +
                "Set DatabaseBootstrap:SystemAdminPassword (User Secrets or env DatabaseBootstrap__SystemAdminPassword). Skipping user seed.");
            return;
        }

        var existing = await userManager.FindByNameAsync(userName);
        if (existing != null)
        {
            await EnsurePlatformDirectoryRolesAsync(userManager, existing, logger, cancellationToken);
            logger.LogInformation(
                "DatabaseBootstrap: user {UserName} already exists; ensured SystemAdmin + PlatformOwner roles.",
                userName);
            return;
        }

        var farmId = Guid.NewGuid().ToString();
        var farm = new Farm
        {
            FarmId = farmId,
            Name = "Platform (system admin)",
            Type = "System",
            Email = email,
            PhoneNumber = "",
            CreatedAt = DateTime.UtcNow,
        };

        if (!await subscriptionService.CreateFarmAsync(farm))
        {
            logger.LogError("DatabaseBootstrap: CreateFarmAsync failed for system admin farm. Skipping user seed.");
            return;
        }

        var user = new ApplicationUser
        {
            UserName = userName,
            Email = email,
            EmailConfirmed = true,
            FarmId = farmId,
            FarmName = farm.Name,
            FirstName = "System",
            LastName = "Admin",
            PhoneNumber = "",
            IsStaff = false,
            IsAdmin = true,
            TwoFactorEnabled = false,
            SecurityStamp = Guid.NewGuid().ToString(),
        };

        var create = await userManager.CreateAsync(user, password);
        if (!create.Succeeded)
        {
            logger.LogError(
                "DatabaseBootstrap: failed to create user {UserName}: {Errors}",
                userName,
                string.Join("; ", create.Errors.Select(e => e.Description)));
            return;
        }

        foreach (var role in PlatformOwnerRoles)
        {
            var roleResult = await userManager.AddToRoleAsync(user, role);
            if (!roleResult.Succeeded)
            {
                logger.LogError(
                    "DatabaseBootstrap: user created but failed to add role {Role}: {Errors}",
                    role,
                    string.Join("; ", roleResult.Errors.Select(e => e.Description)));
                return;
            }
        }

        logger.LogInformation(
            "DatabaseBootstrap: created platform owner user {UserName} ({Email}) with SystemAdmin + PlatformOwner. Change this password before any shared or production use.",
            userName,
            email);
    }
}
