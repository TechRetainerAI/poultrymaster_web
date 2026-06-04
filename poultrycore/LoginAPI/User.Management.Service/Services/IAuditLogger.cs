using Microsoft.AspNetCore.Http;

namespace User.Management.Service.Services
{
    /// <summary>
    /// Writes a row to the shared dbo.AuditLogs table — the same table the Farm
    /// API populates via its global AuditLogActionFilter. The Login API doesn't
    /// have that filter, so any action we want audited (employee create today,
    /// company create / 2FA toggle / profile update later) must call this
    /// explicitly. Fire-and-forget: failures are logged but never block the
    /// originating request.
    /// </summary>
    public interface IAuditLogger
    {
        /// <param name="httpContext">Current request — used to capture IP, User-Agent, and ClaimsPrincipal.</param>
        /// <param name="action">HTTP verb: "POST" | "PUT" | "DELETE".</param>
        /// <param name="resource">Resource label, e.g. "Employee", "Company", "Profile".</param>
        /// <param name="resourceId">PK of the affected row (employee Id, company FarmId, etc.).</param>
        /// <param name="farmId">Owning farm. Falls back to FarmId claim when null.</param>
        /// <param name="details">Free-text summary, e.g. "POST Employee - Created".</param>
        /// <param name="data">Optional JSON snapshot of the request/response.</param>
        /// <param name="status">"Success" or "Failed".</param>
        Task LogAsync(
            HttpContext httpContext,
            string action,
            string resource,
            string? resourceId,
            string? farmId = null,
            string? details = null,
            string? data = null,
            string status = "Success");
    }
}
