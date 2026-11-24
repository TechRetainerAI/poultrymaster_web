using System.Reflection;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using PoultryFarmAPIWeb.Business;

namespace PoultryFarmAPIWeb.Filters
{
    /// <summary>
    /// Projects &amp; Contracts (483): a purchase, sale, expense, owner entry or
    /// payment saved WITH a project split also needs
    /// <c>generic.project-allocations.create</c>, on top of the permission for
    /// the transaction itself (checked by <see cref="IamEnforcementFilter"/> from
    /// the route).
    ///
    /// Same switch and same shadow behaviour as the route filter: with
    /// <c>Iam:Enforced</c> false it only logs what it would have blocked, so
    /// project assignment is never more strictly enforced than every other
    /// permission in the API.
    /// </summary>
    public class ProjectAssignmentPermissionFilter : IAsyncActionFilter
    {
        private const string Key = "generic.project-allocations.create";
        private readonly IIamService _iam;
        private readonly ILogger<ProjectAssignmentPermissionFilter> _logger;
        private readonly bool _enforced;

        public ProjectAssignmentPermissionFilter(IIamService iam, ILogger<ProjectAssignmentPermissionFilter> logger, IConfiguration config)
        {
            _iam = iam;
            _logger = logger;
            _enforced = config.GetValue("Iam:Enforced", false);
        }

        public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
        {
            if (!CarriesProjects(context.ActionArguments.Values))
            {
                await next();
                return;
            }

            var user = context.HttpContext.User;
            var userId = user?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            var farmId = context.RouteData.Values["farmId"]?.ToString()
                         ?? context.HttpContext.Request.Query["farmId"].FirstOrDefault()
                         ?? user?.FindFirst("FarmId")?.Value;

            var allowed = userId is not null && await _iam.HasPermissionAsync(userId, farmId, Key);
            if (!allowed)
            {
                _logger.LogWarning("IAM {Mode}: {Method} {Path} by {User} on {Farm} carries a project split but lacks {Key}.",
                    _enforced ? "DENY" : "SHADOW", context.HttpContext.Request.Method, context.HttpContext.Request.Path,
                    userId ?? "(anonymous)", farmId, Key);
                if (_enforced)
                {
                    context.Result = new ObjectResult(new
                    {
                        message = "You do not have permission to assign transactions to projects.",
                        requiredPermission = Key,
                    }) { StatusCode = 403 };
                    return;
                }
            }
            await next();
        }

        private static readonly Type JsonElementNullable = typeof(JsonElement?);

        private static bool CarriesProjects(IEnumerable<object?> args)
        {
            foreach (var arg in args)
            {
                if (arg is null) continue;
                var prop = arg.GetType().GetProperty("Projects", BindingFlags.Public | BindingFlags.Instance);
                if (prop is null || prop.PropertyType != JsonElementNullable) continue;
                if (GenericProjectAttach.Has((JsonElement?)prop.GetValue(arg))) return true;
            }
            return false;
        }
    }
}
