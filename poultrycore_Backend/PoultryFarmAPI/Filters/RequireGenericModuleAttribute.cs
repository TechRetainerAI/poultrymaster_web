using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using PoultryFarmAPIWeb.Business;
using System.Security.Claims;

namespace PoultryFarmAPIWeb.Filters
{
    /// <summary>
    /// Marks a Generic controller as gated by one or more module toggles from
    /// <see cref="Models.GenericModuleSettings"/>.
    ///
    /// <para>
    /// When applied, the <see cref="GenericModuleFilter"/> (registered globally)
    /// reads the company's module settings and blocks <b>write</b> operations
    /// (POST, PUT, DELETE) when the required module is disabled. GET requests
    /// always pass through so historical data remains accessible.
    /// </para>
    ///
    /// <para>
    /// Multiple module names means ANY ONE of them must be enabled (OR logic).
    /// This covers controllers that serve more than one toggle, e.g. a cash
    /// controller gated on EnableCashAccounts.
    /// </para>
    ///
    /// <example>
    /// <code>[RequireGenericModule("EnableProducts")]</code>
    /// <code>[RequireGenericModule("EnableSubscriptions", "EnableInvoices")]</code>
    /// </example>
    /// </summary>
    [AttributeUsage(AttributeTargets.Class, AllowMultiple = false, Inherited = true)]
    public sealed class RequireGenericModuleAttribute : Attribute
    {
        public string[] ModuleNames { get; }

        public RequireGenericModuleAttribute(params string[] moduleNames)
        {
            ModuleNames = moduleNames;
        }
    }

    /// <summary>
    /// Global filter that enforces <see cref="RequireGenericModuleAttribute"/>.
    ///
    /// <list type="bullet">
    /// <item>GET requests always pass — disabled modules must not hide historical data.</item>
    /// <item>POST / PUT / DELETE are blocked with 403 when every listed module is disabled.</item>
    /// <item>If module settings cannot be loaded (new company, network error), the filter
    ///        fails open — the controller's own guard will catch real problems.</item>
    /// </list>
    /// </summary>
    public class GenericModuleFilter : IAsyncAuthorizationFilter
    {
        private readonly IGenericBusinessTemplateService _templateSvc;
        private readonly ILogger<GenericModuleFilter> _logger;

        public GenericModuleFilter(
            IGenericBusinessTemplateService templateSvc,
            ILogger<GenericModuleFilter> logger)
        {
            _templateSvc = templateSvc;
            _logger = logger;
        }

        public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
        {
            var attr = context.ActionDescriptor.EndpointMetadata
                .OfType<RequireGenericModuleAttribute>()
                .FirstOrDefault();
            if (attr == null) return;

            // GET requests always pass — historical data must stay accessible
            var method = context.HttpContext.Request.Method;
            if (string.Equals(method, "GET", StringComparison.OrdinalIgnoreCase))
                return;

            var farmId = context.RouteData.Values["farmId"]?.ToString()
                         ?? context.HttpContext.Request.Query["farmId"].FirstOrDefault();

            if (string.IsNullOrWhiteSpace(farmId))
                return; // No farmId — let the controller's own guard handle it

            try
            {
                var settings = await _templateSvc.GetModuleSettings(farmId);
                if (settings == null) return; // Fail open

                // Check if ANY of the required modules is enabled (OR logic)
                var anyEnabled = false;
                foreach (var name in attr.ModuleNames)
                {
                    if (IsModuleEnabled(settings, name))
                    {
                        anyEnabled = true;
                        break;
                    }
                }

                if (!anyEnabled)
                {
                    _logger.LogWarning(
                        "GenericModuleFilter DENIED {Method} on farm {FarmId}: " +
                        "required module(s) [{Modules}] are all disabled",
                        method, farmId, string.Join(", ", attr.ModuleNames));

                    context.Result = new ObjectResult(new
                    {
                        message = "This feature is currently disabled for your business. " +
                                  "You can enable it in Settings."
                    })
                    { StatusCode = 403 };
                }
            }
            catch (Exception ex)
            {
                // Fail open — don't break the API if settings can't be loaded
                _logger.LogError(ex,
                    "GenericModuleFilter: failed to load module settings for farm {FarmId}",
                    farmId);
            }
        }

        private static bool IsModuleEnabled(Models.GenericModuleSettings s, string name)
        {
            return name switch
            {
                "EnableProducts"          => s.EnableProducts,
                "EnableInventory"         => s.EnableInventory,
                "EnableStockAdjustments"  => s.EnableStockAdjustments,
                "EnableInternalUse"       => s.EnableInternalUse,
                "EnablePurchases"         => s.EnablePurchases,
                "EnableSubscriptions"     => s.EnableSubscriptions,
                "EnableInvoices"          => s.EnableInvoices,
                "EnableCustomerBalances"  => s.EnableCustomerBalances,
                "EnableStaffPayments"     => s.EnableStaffPayments,
                "EnableCashAccounts"      => s.EnableCashAccounts,
                "EnableRecurringExpenses" => s.EnableRecurringExpenses,
                "EnableSupplierBalances"  => s.EnableSupplierBalances,
                _ => true // Unknown module name — fail open
            };
        }
    }
}
