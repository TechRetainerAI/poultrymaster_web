using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Controllers;
using Microsoft.AspNetCore.Mvc.Filters;
using PoultryFarmAPIWeb.Business;
using System.Collections.Concurrent;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;

namespace PoultryFarmAPIWeb.Filters
{
    /// <summary>
    /// Global permission enforcement for the Farm API (IAM phase 3).
    ///
    /// <para>
    /// <b>Shadow mode is the default and that is deliberate.</b> With
    /// <c>Iam:Enforced</c> false, this filter decides what it WOULD have blocked
    /// and logs it, then lets the request through untouched. Turning enforcement
    /// on across ~600 endpoints that have never had a permission check is not
    /// something to do blind: run it in shadow for a while, read the
    /// "IAM SHADOW" lines, fix the map or the roles they expose, and only then
    /// set <c>Iam:Enforced</c> to true.
    /// </para>
    ///
    /// <para>
    /// Endpoints carrying an explicit <see cref="RequirePermissionAttribute"/>
    /// are skipped — that attribute is the override for cases the route
    /// convention cannot express, and it enforces immediately regardless of this
    /// filter's mode.
    /// </para>
    /// </summary>
    public class IamEnforcementFilter : IAsyncAuthorizationFilter
    {
        private readonly IIamService _iam;
        private readonly ILogger<IamEnforcementFilter> _logger;
        private readonly bool _enforced;
        private readonly bool _denyUnmapped;

        public IamEnforcementFilter(IIamService iam, ILogger<IamEnforcementFilter> logger, IConfiguration config)
        {
            _iam = iam;
            _logger = logger;
            _enforced = config.GetValue("Iam:Enforced", false);
            // An unmapped route is a hole in IamPermissionMap, not necessarily an
            // attack. Defaulting this to false means adding a controller cannot
            // accidentally take the API down; the log line is how it gets noticed.
            _denyUnmapped = config.GetValue("Iam:DenyUnmapped", false);
        }

        public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
        {
            // Explicitly annotated endpoints police themselves.
            if (context.ActionDescriptor.EndpointMetadata.OfType<RequirePermissionAttribute>().Any())
                return;

            var route = IamPermissionMap.Normalize(ResolveTemplate(context));
            if (IamPermissionMap.IsExempt(route)) return;

            var method = context.HttpContext.Request.Method;
            var user = context.HttpContext.User;
            var userId = user?.FindFirst(ClaimTypes.NameIdentifier)?.Value;

            if (string.IsNullOrWhiteSpace(userId))
            {
                // Most controllers in this API carry no [Authorize] at all, so an
                // anonymous request currently succeeds. Enforcement closes that,
                // but only once it is switched on.
                Report(context, route, method, null, "anonymous request", deny: _enforced,
                    result: new UnauthorizedObjectResult(new { message = "Authentication required." }));
                return;
            }

            var farmId = context.HttpContext.Request.Query["farmId"].FirstOrDefault()
                         ?? context.RouteData.Values["farmId"]?.ToString()
                         ?? user!.FindFirst("FarmId")?.Value;

            // Phase 4: "sign out everywhere" stamps a watermark, and any token
            // issued before it stops working — including tokens already in the
            // wild that have no session row. Gated on the same switch as the rest
            // of enforcement so there is one story about when IAM starts biting.
            if (await IsTokenRevoked(user!, userId))
            {
                Report(context, route, method, userId, "token issued before the user was signed out everywhere",
                    deny: _enforced,
                    result: new UnauthorizedObjectResult(new { message = "Your session has been ended. Please sign in again." }));
                if (context.Result is not null) return;
            }

            await RecordSession(context, userId, farmId);

            // Only the shared controllers need the farm's type; skip the lookup
            // for the ~80% of routes that name their module in the path.
            string? module = null;
            var resource = IamPermissionMap.ResolveResource(route);
            if (resource is not null && resource.StartsWith("*.", StringComparison.Ordinal))
                module = await _iam.GetModuleForFarmAsync(farmId);

            var key = IamPermissionMap.BuildKey(route, method, module);

            if (key is null)
            {
                Report(context, route, method, userId,
                    resource is null ? "route is not in IamPermissionMap" : "company type could not be resolved",
                    deny: _enforced && _denyUnmapped,
                    result: new ObjectResult(new { message = "This action has no permission mapping." }) { StatusCode = 403 });
                return;
            }

            if (await _iam.HasPermissionAsync(userId, farmId, key)) return;

            Report(context, route, method, userId, $"missing {key}", deny: _enforced,
                result: new ObjectResult(new
                {
                    message = "You do not have permission to do this.",
                    requiredPermission = key,
                })
                { StatusCode = 403 });
        }

        /// <summary>
        /// Was this token issued before the user was signed out everywhere?
        ///
        /// Compares the JWT's <c>iat</c> to IamUserSecurity.TokensValidFrom. Both
        /// missing pieces fail OPEN: a token with no <c>iat</c>, or a database
        /// without migration 203, means "not revoked". Failing shut here would
        /// sign out every user at once, which is a far worse failure than a
        /// revocation taking effect a little later than intended.
        /// </summary>
        private async Task<bool> IsTokenRevoked(ClaimsPrincipal user, string userId)
        {
            var iatClaim = user.FindFirst("iat")?.Value;
            if (!long.TryParse(iatClaim, out var iatSeconds)) return false;

            var validFrom = await _iam.GetTokensValidFromAsync(userId);
            if (validFrom is null) return false;

            var issuedAt = DateTimeOffset.FromUnixTimeSeconds(iatSeconds).UtcDateTime;
            return issuedAt < validFrom.Value;
        }

        /// <summary>
        /// Keep the session row fresh, at most once every few minutes per session.
        ///
        /// Without the throttle this would add a write to every single request.
        /// LastSeenAt only needs to be accurate enough to answer "is this person
        /// still using the system", so a few minutes of lag costs nothing.
        /// </summary>
        private async Task RecordSession(AuthorizationFilterContext context, string userId, string? farmId)
        {
            try
            {
                var request = context.HttpContext.Request;
                var userAgent = request.Headers.UserAgent.ToString();
                var ip = context.HttpContext.Connection.RemoteIpAddress?.ToString();

                // The JWT carries no session id, so derive a stable one per
                // (user, device, address). That groups a person's requests from
                // one browser into a single row an admin can recognise and end.
                var sessionId = StableSessionId(userId, userAgent, ip);

                var now = DateTime.UtcNow;
                if (LastTouched.TryGetValue(sessionId, out var previous) && now - previous < TouchInterval) return;
                LastTouched[sessionId] = now;

                await _iam.TouchSessionAsync(sessionId, userId, farmId, ip, Truncate(userAgent, 400), DescribeDevice(userAgent));
            }
            catch (Exception ex)
            {
                // Session bookkeeping must never break a request.
                _logger.LogDebug(ex, "IAM: could not record session for {User}.", userId);
            }
        }

        private static readonly ConcurrentDictionary<string, DateTime> LastTouched = new();
        private static readonly TimeSpan TouchInterval = TimeSpan.FromMinutes(5);

        private static string StableSessionId(string userId, string? userAgent, string? ip)
        {
            var raw = $"{userId}|{userAgent}|{ip}";
            var hash = SHA256.HashData(Encoding.UTF8.GetBytes(raw));
            return Convert.ToHexString(hash)[..32];
        }

        /// <summary>A recognisable name for a device, so an admin can tell their sessions apart.</summary>
        private static string DescribeDevice(string? userAgent)
        {
            if (string.IsNullOrWhiteSpace(userAgent)) return "Unknown device";

            var platform =
                userAgent.Contains("Android", StringComparison.OrdinalIgnoreCase) ? "Android" :
                userAgent.Contains("iPhone", StringComparison.OrdinalIgnoreCase) ? "iPhone" :
                userAgent.Contains("iPad", StringComparison.OrdinalIgnoreCase) ? "iPad" :
                userAgent.Contains("Windows", StringComparison.OrdinalIgnoreCase) ? "Windows" :
                userAgent.Contains("Mac OS", StringComparison.OrdinalIgnoreCase) ? "Mac" :
                userAgent.Contains("Linux", StringComparison.OrdinalIgnoreCase) ? "Linux" : "Unknown";

            // Order matters: Edge and Chrome both claim "Chrome", Safari claims both.
            var browser =
                userAgent.Contains("Edg/", StringComparison.OrdinalIgnoreCase) ? "Edge" :
                userAgent.Contains("OPR/", StringComparison.OrdinalIgnoreCase) ? "Opera" :
                userAgent.Contains("Firefox", StringComparison.OrdinalIgnoreCase) ? "Firefox" :
                userAgent.Contains("Chrome", StringComparison.OrdinalIgnoreCase) ? "Chrome" :
                userAgent.Contains("Safari", StringComparison.OrdinalIgnoreCase) ? "Safari" : "Browser";

            return $"{browser} on {platform}";
        }

        private static string? Truncate(string? value, int max)
            => string.IsNullOrEmpty(value) ? value : value.Length <= max ? value : value[..max];

        /// <summary>
        /// The route template with its tokens resolved.
        ///
        /// ASP.NET normally substitutes <c>[controller]</c> before the descriptor
        /// is built, but relying on that would be a poor bet here: an unsubstituted
        /// token would match nothing in the map, and an unmapped route is not
        /// enforced. Substituting it explicitly means the map is consulted for the
        /// real route either way.
        /// </summary>
        private static string? ResolveTemplate(AuthorizationFilterContext context)
        {
            var template = context.ActionDescriptor.AttributeRouteInfo?.Template;
            if (string.IsNullOrWhiteSpace(template)) return template;
            if (!template.Contains('[')) return template;

            if (context.ActionDescriptor is ControllerActionDescriptor cad)
            {
                template = template
                    .Replace("[controller]", cad.ControllerName, StringComparison.OrdinalIgnoreCase)
                    .Replace("[action]", cad.ActionName, StringComparison.OrdinalIgnoreCase);
            }

            return template;
        }

        /// <summary>
        /// One place that decides whether a finding blocks the request or is only
        /// written down, so shadow and enforced mode can never drift apart.
        /// </summary>
        private void Report(
            AuthorizationFilterContext context,
            string route, string method, string? userId, string reason,
            bool deny, IActionResult result)
        {
            if (deny)
            {
                _logger.LogWarning("IAM DENIED {Method} /{Route} for {User}: {Reason}", method, route, userId ?? "anonymous", reason);
                context.Result = result;
                return;
            }

            _logger.LogInformation("IAM SHADOW would block {Method} /{Route} for {User}: {Reason}", method, route, userId ?? "anonymous", reason);
        }
    }
}
