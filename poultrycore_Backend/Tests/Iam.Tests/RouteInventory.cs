using System.Reflection;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Routing;

namespace Iam.Tests;

/// <summary>Every attribute-routed Farm API endpoint, as (template, verb).</summary>
public static class RouteInventory
{
    public static IEnumerable<(string Template, string Verb, string Controller)> All()
    {
        var asm = typeof(PoultryFarmAPIWeb.Filters.IamPermissionMap).Assembly;
        foreach (var type in asm.GetTypes().Where(t => typeof(ControllerBase).IsAssignableFrom(t) && !t.IsAbstract))
        {
            var controllerName = type.Name.EndsWith("Controller") ? type.Name[..^"Controller".Length] : type.Name;
            var prefixes = type.GetCustomAttributes<RouteAttribute>(true).Select(r => r.Template).DefaultIfEmpty("").ToList();
            foreach (var method in type.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly))
            {
                if (method.IsSpecialName || method.GetCustomAttribute<NonActionAttribute>() is not null) continue;
                var verbs = method.GetCustomAttributes<HttpMethodAttribute>(true).ToList();
                if (verbs.Count == 0) continue;
                foreach (var v in verbs)
                foreach (var prefix in prefixes)
                {
                    var t = v.Template;
                    string full = t is not null && t.StartsWith("/") ? t.TrimStart('/')
                        : t is not null && t.StartsWith("~/") ? t[2..]
                        : string.IsNullOrEmpty(t) ? prefix : $"{prefix}/{t}";
                    full = full.Replace("[controller]", controllerName, StringComparison.OrdinalIgnoreCase)
                               .Replace("[action]", method.Name, StringComparison.OrdinalIgnoreCase);
                    foreach (var verb in v.HttpMethods)
                        yield return (full, verb, type.Name);
                }
            }
        }
    }
}
