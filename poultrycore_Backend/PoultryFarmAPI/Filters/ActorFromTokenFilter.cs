using Microsoft.AspNetCore.Mvc.Filters;
using System.Security.Claims;

namespace PoultryFarmAPIWeb.Filters
{
    /// <summary>
    /// Who approved, reversed or posted a record comes from the signed-in
    /// token, never from the request.
    ///
    /// <para>
    /// About 40 approve/reverse endpoints take <c>approvedBy</c> (and friends)
    /// as a query or form value the browser fills in with the user's id. A
    /// caller could put someone else's id there and have their own approval
    /// recorded under another name — which would defeat keeping "may create"
    /// and "may approve" separate (page access upgrade, tests 17/18). This
    /// filter overwrites those string arguments with the token's user id
    /// whenever the request is authenticated. Anonymous requests are left
    /// alone; the enforcement filter decides whether they may run at all.
    /// </para>
    /// </summary>
    public class ActorFromTokenFilter : IActionFilter
    {
        private static readonly HashSet<string> ActorArguments = new(StringComparer.OrdinalIgnoreCase)
        {
            "approvedBy", "reversedBy", "postedBy", "rejectedBy", "voidedBy", "unapprovedBy", "reapprovedBy",
        };

        public void OnActionExecuting(ActionExecutingContext context)
        {
            var userId = context.HttpContext.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(userId)) return;

            // Walk the declared parameters, not the bound ones: an argument the
            // browser left out is not in ActionArguments but must still be set.
            foreach (var p in context.ActionDescriptor.Parameters)
            {
                if (ActorArguments.Contains(p.Name) && p.ParameterType == typeof(string))
                    context.ActionArguments[p.Name] = userId;
            }
        }

        public void OnActionExecuted(ActionExecutedContext context) { }
    }
}
