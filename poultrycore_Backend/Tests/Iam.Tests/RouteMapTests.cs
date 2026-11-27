using System.Text.Json;
using PoultryFarmAPIWeb.Filters;
using Xunit;

namespace Iam.Tests;

public class RouteMapTests
{
    /// <summary>
    /// Every page key the Staff Page Access editor shows, written by
    /// poultrycore-main/scripts/iam/gen-page-catalog-sql.mjs from the page catalog.
    /// </summary>
    private static readonly HashSet<string> PageKeys = new(
        JsonSerializer.Deserialize<string[]>(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "page-keys.json")))!,
        StringComparer.OrdinalIgnoreCase);

    /// <summary>The shared controllers ("*.") serve these company types.</summary>
    private static readonly string[] SharedModules = { "poultry", "water", "generic" };

    private static string? WithFallback(string key)
    {
        if (PageKeys.Contains(key)) return key;
        var dot = key.LastIndexOf('.');
        var stem = key[..dot];
        foreach (var f in IamPermissionMap.FallbackActions[key[(dot + 1)..]])
            if (PageKeys.Contains($"{stem}.{f}")) return $"{stem}.{f}";
        return null;
    }

    /// <summary>
    /// Tests 14, 29, 30: every endpoint resolves to a permission or is
    /// explicitly exempt — a new controller cannot slip past the map unnoticed.
    /// </summary>
    [Fact]
    public void EveryRouteIsMappedOrExempt()
    {
        var unmapped = RouteInventory.All()
            .Select(r => (Route: IamPermissionMap.Normalize(r.Template), r.Verb, r.Controller))
            .Where(r => !IamPermissionMap.IsExempt(r.Route) && IamPermissionMap.ResolveResource(r.Route) is null)
            .Select(r => $"{r.Controller}: {r.Verb} {r.Route}")
            .Distinct()
            .OrderBy(s => s)
            .ToList();

        Assert.True(unmapped.Count == 0, $"{unmapped.Count} unmapped route(s):\n" + string.Join("\n", unmapped));
    }

    /// <summary>
    /// Test 30: the API enforces the same keys the editor shows. Every mapped
    /// route resolves (after the stronger-action fallback) to a page key, so a
    /// ticked page always opens its own data and an unticked one never does.
    /// </summary>
    [Fact]
    public void EveryRouteResolvesToAPagePermission()
    {
        var bad = new List<string>();
        foreach (var (template, verb, controller) in RouteInventory.All())
        {
            var route = IamPermissionMap.Normalize(template);
            if (IamPermissionMap.IsExempt(route)) continue;
            var resource = IamPermissionMap.ResourceOf(route);
            if (resource is null) continue; // reported by the test above

            var modules = resource.StartsWith("*.") ? SharedModules : new string?[] { null };
            foreach (var module in modules)
            {
                var req = IamPermissionMap.Resolve(route, verb, module);
                if (req is null || req.MemberOnly) continue;
                if (req.Key is null || WithFallback(req.Key) is null)
                    bad.Add($"{controller}: {verb} {route} -> {req.Key}");
            }
        }

        bad = bad.Distinct().OrderBy(s => s).ToList();
        Assert.True(bad.Count == 0, $"{bad.Count} route(s) need a key the page catalog does not define:\n" + string.Join("\n", bad));
    }

    [Theory]
    [InlineData("poultry/profit-loss", "GET", "poultry.profit-loss.view")]
    [InlineData("poultry/payroll-runs", "GET", "poultry.payroll.view")]
    [InlineData("poultry/supplier-balances", "GET", "poultry.supplier-balances.view")]
    [InlineData("poultry/cash-accounts", "GET", "poultry.cash.view")]
    [InlineData("poultry/owner-money", "GET", "poultry.owner-money.view")]
    [InlineData("poultry/cash-flow", "GET", "poultry.cash-flow.view")]
    [InlineData("water/profit-loss", "GET", "water.profit-loss.view")]
    [InlineData("hotel/payroll-runs", "GET", "hotel.payroll.view")]
    [InlineData("restaurant/finance/pnl-lines", "GET", "restaurant.profit-loss.view")]
    [InlineData("generic-company/cash-flow", "GET", "generic.cash-flow.view")]
    public void SensitiveFinancialEndpointsNeedTheirOwnPage(string route, string verb, string expected)
    {
        var req = IamPermissionMap.Resolve(route, verb, null);
        Assert.NotNull(req);
        Assert.False(req!.MemberOnly);
        Assert.Equal(expected, req.Key);
    }

    [Fact]
    public void SalesCreateAndApproveAreDifferentKeys()
    {
        // Tests 17/18: creating a sale and approving one are separate permissions.
        Assert.Equal("poultry.sales.create", IamPermissionMap.Resolve("sale", "POST", "poultry")!.Key);
        Assert.Equal("poultry.sales.approve", IamPermissionMap.Resolve("sale/approve", "POST", "poultry")!.Key);
        Assert.Equal("poultry.sales.reverse", IamPermissionMap.Resolve("sale/reverse", "POST", "poultry")!.Key);
        Assert.Equal("poultry.sales.view", IamPermissionMap.Resolve("sale", "GET", "poultry")!.Key);
    }

    [Fact]
    public void ExportsAreTheirOwnAction()
    {
        Assert.EndsWith(".export", IamPermissionMap.Resolve("poultry/reports/export", "GET", null)!.Key);
    }

    [Fact]
    public void ReferenceListsAreReadableByMembersButChangesNeedThePage()
    {
        // Customers: the sales form needs the list even when the Customers page is unticked.
        Assert.True(IamPermissionMap.Resolve("customer", "GET", "poultry")!.MemberOnly);
        Assert.Equal("poultry.customers.create", IamPermissionMap.Resolve("customer", "POST", "poultry")!.Key);
    }

    [Fact]
    public void FallbackNeverWeakensAnAction()
    {
        // A missing approve/reverse/delete key must fall back to something at
        // least as strong — never to view.
        foreach (var (action, fallbacks) in IamPermissionMap.FallbackActions)
        {
            if (action is "view" or "export") continue;
            Assert.DoesNotContain("view", fallbacks);
        }
    }

    [Fact]
    public void UnknownSubRoutesDoNotInheritABareRoot()
    {
        Assert.Null(IamPermissionMap.ResolveResource("generic-company/some-new-thing"));
    }
}
