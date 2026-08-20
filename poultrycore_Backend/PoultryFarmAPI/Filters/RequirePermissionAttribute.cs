using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using PoultryFarmAPIWeb.Business;
using System.Security.Claims;

namespace PoultryFarmAPIWeb.Filters
{
    /// <summary>
    /// Server-side permission check for a single endpoint.
    ///
    /// <para>
    /// Written in phase 0 and deliberately applied to NOTHING yet. Rolling it
    /// across the ~50 controllers is phase 3; until then permissions are advisory
    /// and the frontend shim is the only thing acting on them. Having the
    /// attribute in place from the start means the catalog keys are exercised by
    /// real code and the shape of enforcement is settled before it matters.
    /// </para>
    ///
    /// <para>
    /// Usage: <c>[RequirePermission("poultry.sales.create")]</c> on an action or
    /// controller. The company is taken from the <c>farmId</c> query/route value
    /// if present, otherwise the FarmId claim — so an endpoint cannot be checked
    /// against one company and then act on another.
    /// </para>
    /// </summary>
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = true)]
    public class RequirePermissionAttribute : Attribute, IAsyncAuthorizationFilter
    {
        private readonly string _permissionKey;

        public RequirePermissionAttribute(string permissionKey)
        {
            _permissionKey = permissionKey;
        }

        public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
        {
            var user = context.HttpContext.User;
            if (user?.Identity?.IsAuthenticated != true)
            {
                context.Result = new UnauthorizedObjectResult(new { message = "Authentication required." });
                return;
            }

            var userId = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(userId))
            {
                context.Result = new UnauthorizedObjectResult(new { message = "No user id on the token." });
                return;
            }

            // Prefer the company the request is actually operating on over the
            // claim, which only reflects the company at sign-in time.
            var farmId = context.HttpContext.Request.Query["farmId"].FirstOrDefault()
                         ?? context.RouteData.Values["farmId"]?.ToString()
                         ?? user.FindFirst("FarmId")?.Value;

            var iam = context.HttpContext.RequestServices.GetService(typeof(IIamService)) as IIamService;
            if (iam is null)
            {
                // Fail closed. A misconfigured container must not become an
                // accidental grant.
                context.Result = new ObjectResult(new { message = "Access control unavailable." }) { StatusCode = 503 };
                return;
            }

            if (!await iam.HasPermissionAsync(userId, farmId, _permissionKey))
            {
                context.Result = new ObjectResult(new
                {
                    message = "You do not have permission to do this.",
                    requiredPermission = _permissionKey,
                })
                { StatusCode = 403 };
            }
        }
    }
}
