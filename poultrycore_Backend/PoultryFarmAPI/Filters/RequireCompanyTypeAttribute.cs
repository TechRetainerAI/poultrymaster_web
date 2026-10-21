using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using PoultryFarmAPIWeb.Business;
using System.Security.Claims;

namespace PoultryFarmAPIWeb.Filters
{
    /// <summary>
    /// Marks a controller as restricted to one or more company types.
    ///
    /// <para>
    /// When applied, the <see cref="CompanyTypeFilter"/> (registered globally)
    /// reads this attribute and verifies the requesting farm's type in the
    /// database via <see cref="IIamService.GetModuleForFarmAsync"/>. If the
    /// farm's type does not match, the request is rejected with a 403.
    /// </para>
    ///
    /// <example>
    /// <code>[RequireCompanyType("Hotel")]</code>
    /// <code>[RequireCompanyType("Poultry", "Generic")]</code>
    /// </example>
    /// </summary>
    [AttributeUsage(AttributeTargets.Class, AllowMultiple = false, Inherited = true)]
    public sealed class RequireCompanyTypeAttribute : Attribute
    {
        public string[] AllowedTypes { get; }

        public RequireCompanyTypeAttribute(params string[] allowedTypes)
        {
            AllowedTypes = allowedTypes;
        }
    }

    /// <summary>
    /// Global authorization filter that enforces <see cref="RequireCompanyTypeAttribute"/>
    /// on controllers. Looks up the farm's actual type from the database (never
    /// trusts the frontend) and blocks requests where the type doesn't match.
    ///
    /// Controllers without the attribute are unaffected — shared controllers
    /// (Sale, Expense, Customer, etc.) continue working for all company types.
    /// </summary>
    public class CompanyTypeFilter : IAsyncAuthorizationFilter
    {
        private readonly IIamService _iam;
        private readonly ILogger<CompanyTypeFilter> _logger;

        public CompanyTypeFilter(IIamService iam, ILogger<CompanyTypeFilter> logger)
        {
            _iam = iam;
            _logger = logger;
        }

        public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
        {
            // Only act on controllers decorated with [RequireCompanyType]
            var attr = context.ActionDescriptor.EndpointMetadata
                .OfType<RequireCompanyTypeAttribute>()
                .FirstOrDefault();
            if (attr == null) return;

            var user = context.HttpContext.User;
            var userId = user?.FindFirst(ClaimTypes.NameIdentifier)?.Value;

            // Anonymous requests are handled by [Authorize] or the IAM filter
            if (string.IsNullOrWhiteSpace(userId)) return;

            var farmId = context.HttpContext.Request.Query["farmId"].FirstOrDefault()
                         ?? context.RouteData.Values["farmId"]?.ToString()
                         ?? user!.FindFirst("FarmId")?.Value;

            if (string.IsNullOrWhiteSpace(farmId))
            {
                // No farmId — can't determine type, let other filters handle it
                return;
            }

            var module = await _iam.GetModuleForFarmAsync(farmId);
            if (module == null)
            {
                _logger.LogWarning(
                    "CompanyTypeFilter: could not resolve type for farm {FarmId}, user {UserId}",
                    farmId, userId);
                // Fail open when the farm isn't found — the controller's own
                // farmId validation will catch it
                return;
            }

            // module is lowercase ("poultry", "water", etc.), AllowedTypes are
            // PascalCase ("Poultry", "Water", etc.)
            var allowed = attr.AllowedTypes.Any(t =>
                string.Equals(t, module, StringComparison.OrdinalIgnoreCase));

            if (!allowed)
            {
                _logger.LogWarning(
                    "CompanyTypeFilter DENIED: farm {FarmId} is {Module} but endpoint requires {Allowed}, user {UserId}",
                    farmId, module, string.Join("/", attr.AllowedTypes), userId);

                context.Result = new ObjectResult(new
                {
                    message = "This endpoint is not available for your company type."
                })
                { StatusCode = 403 };
            }
        }
    }
}
