using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Npgsql;

namespace PoultryFarmAPIWeb.Filters
{
    /// <summary>
    /// Setup (company master data: products, drivers, routes, vehicles, houses,
    /// suppliers, settings...) is changed by the account owner or an employee
    /// granted admin -- never by an ordinary employee.
    ///
    /// <para>
    /// Only WRITES are refused. Reads stay open on purpose: daily screens
    /// (sales, deliveries, production) read this data to fill their pickers.
    /// </para>
    ///
    /// <para>
    /// Allowed: a non-staff account (the owner), staff flagged admin
    /// (aspnetusers.isadmin), and any account that owns a company -- some older
    /// owner accounts carry IsStaff, the same rule CompanyService.CreateAsync
    /// uses. The token has no admin flag, so this is read from the database.
    /// </para>
    ///
    /// <para>
    /// Put it on a controller; mark an action <see cref="AllowStaffSetupWriteAttribute"/>
    /// to exempt it (e.g. adding a customer from inside a sale).
    /// </para>
    /// </summary>
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
    public class SetupAdminOnlyAttribute : Attribute, IAsyncAuthorizationFilter
    {
        private const string CacheKey = "SetupAdminOnly.allowed";

        public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
        {
            var method = context.HttpContext.Request.Method;
            if (HttpMethods.IsGet(method) || HttpMethods.IsHead(method) || HttpMethods.IsOptions(method)) return;
            if (context.ActionDescriptor.EndpointMetadata.OfType<AllowStaffSetupWriteAttribute>().Any()) return;

            var userId = context.HttpContext.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(userId))
            {
                context.Result = new UnauthorizedObjectResult(new { message = "Authentication required." });
                return;
            }

            if (!await IsSetupAdminAsync(context.HttpContext, userId))
            {
                context.Result = new ObjectResult(new
                {
                    message = "Only the account owner or an admin can change setup.",
                })
                { StatusCode = 403 };
            }
        }

        private static async Task<bool> IsSetupAdminAsync(HttpContext http, string userId)
        {
            if (http.Items.TryGetValue(CacheKey, out var cached) && cached is bool b) return b;

            var cs = http.RequestServices.GetRequiredService<IConfiguration>().GetConnectionString("PoultryConn");
            await using var conn = new NpgsqlConnection(cs);
            await using var cmd = new NpgsqlCommand(@"
                SELECT (NOT COALESCE(u.isstaff, false))
                    OR COALESCE(u.isadmin, false)
                    OR EXISTS (SELECT 1 FROM public.farms f
                                WHERE f.owneruserid = u.id AND NOT COALESCE(f.isdeleted, false))
                  FROM public.aspnetusers u
                 WHERE u.id = @U", conn);
            cmd.Parameters.AddWithValue("@U", userId);
            await conn.OpenAsync();
            // Unknown user: fail closed.
            var allowed = await cmd.ExecuteScalarAsync() is true;
            http.Items[CacheKey] = allowed;
            return allowed;
        }
    }

    /// <summary>Exempts one action of a <see cref="SetupAdminOnlyAttribute"/> controller.</summary>
    [AttributeUsage(AttributeTargets.Method)]
    public class AllowStaffSetupWriteAttribute : Attribute { }
}
