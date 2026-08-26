using System.Text.RegularExpressions;

namespace PoultryFarmAPIWeb.Filters
{
    /// <summary>
    /// The whole access map for the Farm API, in one place (IAM phase 3).
    ///
    /// <para>
    /// There are 114 controller classes and roughly 600 endpoints. Annotating
    /// each one individually would scatter 600 unverifiable decisions across the
    /// codebase; putting them here makes the entire map readable top to bottom
    /// and reviewable in a single sitting. A controller that needs something the
    /// convention cannot express still carries an explicit
    /// <see cref="RequirePermissionAttribute"/>, which wins over this table.
    /// </para>
    ///
    /// <para>
    /// A permission key is <c>module.resource.action</c>:
    /// <list type="bullet">
    /// <item>module comes from the route prefix (<c>api/Water/…</c>) or, for the
    /// shared controllers, from the company type of the farm on the request —
    /// written <c>*</c> here and resolved per request.</item>
    /// <item>resource comes from the table below.</item>
    /// <item>action comes from the HTTP verb, overridden when the route segment
    /// names an approval or an export.</item>
    /// </list>
    /// </para>
    /// </summary>
    public static class IamPermissionMap
    {
        /// <summary>
        /// Routes that carry no permission at all: infrastructure, or endpoints
        /// that guard themselves. IAM's own controller is here because it checks
        /// office.access.* internally and must stay reachable to fix a lockout.
        /// </summary>
        private static readonly string[] Exempt =
        {
            "iam", "chat", "email", "test", "weatherforecast", "announcements",
        };

        /// <summary>
        /// Route prefix (lowercased, after "api/", route parameters removed) to
        /// permission resource. Longest prefix wins, so "poultry/raw-material-purchases"
        /// is matched before "poultry/raw-material-items" can be confused with it.
        ///
        /// "*" means "whichever module this farm is" — the shared controllers
        /// (Sale, Expense, Customer…) serve all three company types.
        /// </summary>
        private static readonly Dictionary<string, string> Map = new(StringComparer.OrdinalIgnoreCase)
        {
            // ---- Shared controllers: module resolved from the farm ----------
            ["sale"] = "*.sales",
            ["customer"] = "*.customers",
            ["supplier"] = "*.suppliers",
            ["expense"] = "*.expenses",
            ["cash"] = "*.cash",
            ["inventoryitem"] = "*.inventory",
            ["inventorytransaction"] = "*.stock",
            ["dashboard"] = "*.reports",

            // ---- Poultry, via the shared/legacy controller names -------------
            ["flock"] = "poultry.flocks",
            ["mainflockbatch"] = "poultry.flock-batches",
            ["house"] = "poultry.houses",
            ["health"] = "poultry.health",
            ["feedusage"] = "poultry.feed-usage",
            ["feedinventoryadjustment"] = "poultry.stock",
            ["eggproduction"] = "poultry.egg-production",
            ["egginventoryadjustment"] = "poultry.egg-stock",
            ["productionrecord"] = "poultry.production-records",
            ["productionbatchrecord"] = "poultry.production-records",
            ["farmobservation"] = "poultry.reports",
            ["farmproductionsettings"] = "office.settings",

            // ---- Poultry, explicitly prefixed --------------------------------
            ["poultry/reports"] = "poultry.reports",
            ["poultry/closing-report"] = "poultry.reports",
            ["poultry/cash-accounts"] = "poultry.cash",
            ["poultry/cash-transfers"] = "poultry.cash",
            ["poultry/drivers"] = "poultry.drivers",
            ["poultry/vehicles"] = "poultry.vehicles",
            ["poultry/routes"] = "poultry.routes",
            ["poultry/vehicle-loadings"] = "poultry.deliveries",
            ["poultry/deliveries"] = "poultry.deliveries",
            ["poultry/driver-returns"] = "poultry.driver-returns",
            ["poultry/driver-shortages"] = "poultry.driver-returns",
            ["poultry/driver-delivery-expenses"] = "poultry.driver-returns",
            ["poultry/feed-formulas"] = "poultry.feed-formulas",
            ["poultry/feed-production"] = "poultry.feed-production",
            ["poultry/raw-material-items"] = "poultry.raw-materials",
            ["poultry/raw-material-adjustments"] = "poultry.raw-materials",
            ["poultry/raw-material-purchases"] = "poultry.raw-materials",
            ["poultry/raw-material-usage"] = "poultry.raw-materials",
            ["poultry/payments"] = "poultry.payments",
            ["poultry/products"] = "poultry.products",
            ["poultry/stock"] = "poultry.stock",
            ["poultry/production-batches"] = "poultry.production-records",
            ["poultry/production-losses"] = "poultry.loss-records",
            ["poultry/loss-records"] = "poultry.loss-records",
            ["poultry/internal-usage"] = "poultry.internal-use",
            ["poultry/daily-closings"] = "poultry.daily-closing",
            ["poultry/staff"] = "poultry.staff",
            ["poultry/staff-attendance"] = "poultry.staff",
            ["poultry/payroll-runs"] = "poultry.payroll",

            // ---- Water --------------------------------------------------------
            ["water/company"] = "office.settings",
            ["water/farm-settings"] = "office.settings",
            ["water/products"] = "water.products",
            ["water/customers"] = "water.customers",
            ["water/stock"] = "water.stock",
            ["water/internal-usage"] = "water.internal-use",
            ["water/sales"] = "water.sales",
            ["water/payments"] = "water.payments",
            ["water/suppliers"] = "water.suppliers",
            ["water/dashboard"] = "water.reports",
            ["water/reports"] = "water.reports",
            ["water/drivers"] = "water.drivers",
            ["water/vehicles"] = "water.vehicles",
            ["water/routes"] = "water.routes",
            ["water/vehicle-loadings"] = "water.deliveries",
            ["water/driver-returns"] = "water.driver-returns",
            ["water/driver-shortages"] = "water.driver-returns",
            ["water/expenses"] = "water.expenses",
            ["water/expense-categories"] = "water.expenses",
            ["water/cash-accounts"] = "water.cash",
            ["water/cash-transfers"] = "water.cash",
            ["water/daily-closings"] = "water.daily-closing",
            ["water/loss-records"] = "water.production-losses",
            ["water/production-batches"] = "water.production-batches",
            ["water/production-losses"] = "water.production-losses",
            ["water/boreholes"] = "water.boreholes",
            ["water/machines"] = "water.machines",
            ["water/maintenance-logs"] = "water.maintenance",
            ["water/quality-tests"] = "water.quality-tests",
            ["water/pumping-logs"] = "water.pumping-logs",
            ["water/raw-material-items"] = "water.raw-materials",
            ["water/raw-material-adjustments"] = "water.raw-materials",
            ["water/raw-material-purchases"] = "water.raw-materials",
            ["water/raw-material-usage"] = "water.raw-materials",
            ["water/staff"] = "water.staff",
            ["water/staff-attendance"] = "water.staff",
            ["water/payroll-runs"] = "water.payroll",

            // ---- Generic company ---------------------------------------------
            // The route carries the farm id ("api/generic-company/{farmId}/sales"),
            // which Normalize strips before matching.
            ["generic-company"] = "office.companies",
            ["generic-company/products"] = "generic.products",
            ["generic-company/service-catalog"] = "generic.products",
            ["generic-company/inventory"] = "generic.inventory",
            ["generic-company/internal-usage"] = "generic.internal-use",
            ["generic-company/suppliers"] = "generic.suppliers",
            ["generic-company/purchases"] = "generic.purchases",
            ["generic-company/expenses"] = "generic.expenses",
            ["generic-company/cash"] = "generic.cash",
            ["generic-company/cash-transfers"] = "generic.cash-transfers",
            ["generic-company/daily-closings"] = "generic.daily-closing",
            ["generic-company/reports"] = "generic.reports",
            ["generic-company/customers"] = "generic.customers",
            ["generic-company/sales"] = "generic.sales",
            ["generic-company/staff"] = "generic.staff",
            ["generic-company/staff-attendance"] = "generic.attendance",
            ["generic-company/payroll-runs"] = "generic.payroll",
            ["business-categories"] = "office.organization",

            // ---- Business office ----------------------------------------------
            ["businessoffice"] = "office.organization",
            ["auditlogs"] = "office.audit-log",
        };

        /// <summary>Route segments that mean "approve", whatever the HTTP verb.</summary>
        private static readonly string[] ApproveSegments =
        {
            "approve", "unapprove", "post", "unpost", "reverse", "confirm", "authorize", "release",
        };

        private static readonly Regex RouteParam = new(@"\{[^}]*\}", RegexOptions.Compiled);

        /// <summary>
        /// Strip "api/", route parameters and empty segments so a template like
        /// "api/generic-company/{farmId}/sales/{id:int}" matches the table entry
        /// "generic-company/sales".
        /// </summary>
        public static string Normalize(string? routeTemplate)
        {
            if (string.IsNullOrWhiteSpace(routeTemplate)) return string.Empty;

            var withoutParams = RouteParam.Replace(routeTemplate, string.Empty);
            var segments = withoutParams
                .Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Where(s => !string.Equals(s, "api", StringComparison.OrdinalIgnoreCase))
                .ToList();

            return string.Join('/', segments).ToLowerInvariant();
        }

        public static bool IsExempt(string normalizedRoute)
        {
            if (string.IsNullOrEmpty(normalizedRoute)) return true;
            var first = normalizedRoute.Split('/')[0];
            return Exempt.Contains(first, StringComparer.OrdinalIgnoreCase);
        }

        /// <summary>
        /// The resource for a route, or null when nothing matches. Longest prefix
        /// wins so more specific entries beat their parents.
        /// </summary>
        public static string? ResolveResource(string normalizedRoute)
        {
            if (string.IsNullOrEmpty(normalizedRoute)) return null;

            if (Map.TryGetValue(normalizedRoute, out var exact)) return exact;

            string? best = null;
            var bestLength = -1;
            foreach (var (prefix, resource) in Map)
            {
                if (prefix.Length <= bestLength) continue;
                if (!normalizedRoute.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) continue;
                // Only match on a segment boundary, so "water/stock" cannot be
                // matched by a route like "water/stocktake".
                if (normalizedRoute.Length > prefix.Length && normalizedRoute[prefix.Length] != '/') continue;
                best = resource;
                bestLength = prefix.Length;
            }

            if (best is not null) return best;

            // Generic company routes carry the farm id as the second segment, so
            // "generic-company/sales" only appears after Normalize strips it. If a
            // literal id slipped through, retry without that segment.
            var parts = normalizedRoute.Split('/');
            if (parts.Length >= 3 && string.Equals(parts[0], "generic-company", StringComparison.OrdinalIgnoreCase))
            {
                var collapsed = string.Join('/', new[] { parts[0] }.Concat(parts.Skip(2)));
                if (Map.TryGetValue(collapsed, out var viaCollapse)) return viaCollapse;
            }

            return null;
        }

        /// <summary>
        /// Action for a request. The HTTP verb decides, except where the route
        /// names an approval or an export — those are separate permissions
        /// precisely because "can post a payroll run" is not "can edit one".
        /// </summary>
        public static string ResolveAction(string httpMethod, string normalizedRoute)
        {
            var segments = normalizedRoute.Split('/', StringSplitOptions.RemoveEmptyEntries);

            if (segments.Any(s => s.Contains("export", StringComparison.OrdinalIgnoreCase)))
                return "export";

            if (segments.Any(s => ApproveSegments.Contains(s, StringComparer.OrdinalIgnoreCase)))
                return "approve";

            return httpMethod.ToUpperInvariant() switch
            {
                "GET" or "HEAD" or "OPTIONS" => "view",
                "POST" => "create",
                "PUT" or "PATCH" => "edit",
                "DELETE" => "delete",
                _ => "view",
            };
        }

        /// <summary>
        /// Build the key for a request, substituting the module for a "*" resource.
        /// Returns null when the route is unmapped or the module is unknown.
        /// </summary>
        public static string? BuildKey(string normalizedRoute, string httpMethod, string? moduleForFarm)
        {
            var resource = ResolveResource(normalizedRoute);
            if (resource is null) return null;

            if (resource.StartsWith("*.", StringComparison.Ordinal))
            {
                if (string.IsNullOrWhiteSpace(moduleForFarm)) return null;
                resource = string.Concat(moduleForFarm, resource.AsSpan(1));
            }

            return $"{resource}.{ResolveAction(httpMethod, normalizedRoute)}";
        }
    }
}
