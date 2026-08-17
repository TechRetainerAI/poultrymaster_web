using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;
using System.Security.Claims;

namespace PoultryFarmAPIWeb.Controllers
{
    /// <summary>
    /// Identity &amp; Access Management, read side (migration 199).
    ///
    /// Lives on the Farm API rather than the Login API for two reasons: this is
    /// the service that will enforce permissions in phase 3, and "Iam" is not in
    /// the proxy's Login-API prefix list, so /api/proxy/Iam/* routes here with no
    /// proxy change.
    ///
    /// Unlike most controllers in this API, these endpoints are authorized from
    /// day one — the screen that configures permissions is a poor place to start
    /// trusting the client.
    /// </summary>
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class IamController : ControllerBase
    {
        private readonly IIamService _service;
        private readonly ILogger<IamController> _logger;

        public IamController(IIamService service, ILogger<IamController> logger)
        {
            _service = service;
            _logger = logger;
        }

        /// <summary>
        /// Whether the API is actually enforcing permissions yet.
        ///
        /// The frontend reads this to decide how to resolve access: while
        /// enforcement is off, IAM is additive and can only widen what the legacy
        /// staff permissions already allow. One flag, read from the server, so the
        /// two sides cannot disagree about which era they are in.
        /// </summary>
        [HttpGet("status")]
        [AllowAnonymous]
        public ActionResult GetStatus([FromServices] IConfiguration config)
        {
            return Ok(new
            {
                enforced = config.GetValue("Iam:Enforced", false),
                denyUnmapped = config.GetValue("Iam:DenyUnmapped", false),
            });
        }

        /// <summary>The permission catalog. Static, small, and the same for everyone.</summary>
        [HttpGet("catalog")]
        public async Task<ActionResult<IEnumerable<IamPermissionModel>>> GetCatalog()
        {
            try
            {
                return Ok(await _service.GetCatalogAsync());
            }
            catch (PostgresException ex)
            {
                return MissingSchema(ex, "catalog");
            }
        }

        /// <summary>
        /// What a user can do in one company. Defaults to the caller and their
        /// active company; reading anyone else's requires office.access.view,
        /// checked against the caller's own effective permissions.
        /// </summary>
        [HttpGet("effective-permissions")]
        public async Task<ActionResult<IamEffectivePermissionsModel>> GetEffectivePermissions(
            [FromQuery] string? userId,
            [FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            var targetId = string.IsNullOrWhiteSpace(userId) ? callerId : userId.Trim();
            var scopeFarmId = string.IsNullOrWhiteSpace(farmId)
                ? User.FindFirst("FarmId")?.Value
                : farmId.Trim();

            try
            {
                if (!string.Equals(targetId, callerId, StringComparison.OrdinalIgnoreCase))
                {
                    var mayRead = await _service.HasPermissionAsync(callerId, scopeFarmId, "office.access.view");
                    if (!mayRead)
                    {
                        _logger.LogWarning(
                            "IAM: {Caller} tried to read effective permissions for {Target} without office.access.view.",
                            callerId, targetId);
                        return Forbid();
                    }
                }

                return Ok(await _service.GetEffectivePermissionsAsync(targetId, scopeFarmId));
            }
            catch (PostgresException ex)
            {
                return MissingSchema(ex, "effective permissions");
            }
        }

        /// <summary>
        /// Roles visible to the caller: the built-ins, plus any custom role their
        /// organization owns.
        /// </summary>
        /// <remarks>
        /// Ownership is keyed off the caller's own id. That is correct for account
        /// owners and harmless today because no custom roles exist yet — but a
        /// staff member in an organization that HAS custom roles would not see
        /// them. Resolving the real organization owner (it lives in the Login
        /// API) is phase 2 work, alongside the role editor that can create them.
        /// </remarks>
        [HttpGet("roles")]
        public async Task<ActionResult<IEnumerable<IamRoleModel>>> GetRoles([FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            try
            {
                if (!await MayManageAccess(callerId, farmId)) return Forbid();
                return Ok(await _service.GetRolesAsync(callerId));
            }
            catch (PostgresException ex)
            {
                return MissingSchema(ex, "roles");
            }
        }

        /// <summary>The keys one role grants, for the permission matrix.</summary>
        [HttpGet("roles/{roleId:int}/permissions")]
        public async Task<ActionResult<IEnumerable<string>>> GetRolePermissions(int roleId, [FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            try
            {
                if (!await MayManageAccess(callerId, farmId)) return Forbid();
                return Ok(await _service.GetRolePermissionsAsync(roleId));
            }
            catch (PostgresException ex)
            {
                return MissingSchema(ex, "role permissions");
            }
        }

        /// <summary>
        /// The roles one person holds in one company. Same rule as
        /// effective-permissions: your own, or anyone's with office.access.view.
        /// </summary>
        [HttpGet("user-roles")]
        public async Task<ActionResult<IEnumerable<IamUserRoleModel>>> GetUserRoles(
            [FromQuery] string? userId,
            [FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            var targetId = string.IsNullOrWhiteSpace(userId) ? callerId : userId.Trim();
            var scopeFarmId = string.IsNullOrWhiteSpace(farmId)
                ? User.FindFirst("FarmId")?.Value
                : farmId.Trim();

            try
            {
                if (!string.Equals(targetId, callerId, StringComparison.OrdinalIgnoreCase)
                    && !await MayManageAccess(callerId, scopeFarmId))
                {
                    return Forbid();
                }

                return Ok(await _service.GetUserRolesAsync(targetId, scopeFarmId));
            }
            catch (PostgresException ex)
            {
                return MissingSchema(ex, "user roles");
            }
        }

        /// <summary>Overrides on one person, in one company. Expired ones included, flagged.</summary>
        [HttpGet("overrides")]
        public async Task<ActionResult<IEnumerable<IamOverrideModel>>> GetOverrides(
            [FromQuery] string? userId,
            [FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            var targetId = string.IsNullOrWhiteSpace(userId) ? callerId : userId.Trim();
            var scopeFarmId = string.IsNullOrWhiteSpace(farmId) ? User.FindFirst("FarmId")?.Value : farmId.Trim();

            try
            {
                if (!string.Equals(targetId, callerId, StringComparison.OrdinalIgnoreCase)
                    && !await MayManageAccess(callerId, scopeFarmId))
                {
                    return Forbid();
                }

                return Ok(await _service.GetUserOverridesAsync(targetId, scopeFarmId));
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "overrides");
            }
        }

        // ---- Writes (migration 201) ------------------------------------------

        /// <summary>Create a custom role, or rename one. Built-ins are rejected by the proc.</summary>
        [HttpPost("roles")]
        public async Task<ActionResult> SaveRole([FromBody] IamRoleSaveRequest request, [FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            // Creating and changing are separate permissions, so a role that can
            // adjust existing roles cannot invent new ones.
            var needed = request.RoleId is null ? "office.access.create" : "office.access.edit";

            try
            {
                if (!await Holds(callerId, farmId, needed)) return Forbid();
                var roleId = await _service.SaveRoleAsync(request, callerId);
                _logger.LogInformation("IAM: {Caller} saved role {RoleId} ({Name}).", callerId, roleId, request.Name);
                return Ok(new { roleId });
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "role save");
            }
        }

        [HttpDelete("roles/{roleId:int}")]
        public async Task<ActionResult> DeleteRole(int roleId, [FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            try
            {
                if (!await Holds(callerId, farmId, "office.access.delete")) return Forbid();
                await _service.DeleteRoleAsync(roleId, callerId);
                _logger.LogInformation("IAM: {Caller} deleted role {RoleId}.", callerId, roleId);
                return Ok(new { deleted = true });
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "role delete");
            }
        }

        /// <summary>Replace a custom role's grants with exactly this set.</summary>
        [HttpPut("roles/{roleId:int}/permissions")]
        public async Task<ActionResult> SetRolePermissions(
            int roleId,
            [FromBody] IamRolePermissionsRequest request,
            [FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            try
            {
                if (!await Holds(callerId, farmId, "office.access.edit")) return Forbid();
                var count = await _service.SetRolePermissionsAsync(roleId, callerId, request.PermissionKeys ?? new List<string>());
                _logger.LogInformation("IAM: {Caller} set {Count} permission(s) on role {RoleId}.", callerId, count, roleId);
                return Ok(new { grantedCount = count });
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "role permissions");
            }
        }

        /// <summary>Give someone a role, in one company or across the organization.</summary>
        [HttpPost("assignments")]
        public async Task<ActionResult> AssignRole([FromBody] IamAssignRoleRequest request)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            if (string.IsNullOrWhiteSpace(request.UserId))
                return BadRequest(new { message = "A user is required." });

            try
            {
                if (!await Holds(callerId, request.FarmId, "office.access.edit")) return Forbid();
                await _service.AssignUserRoleAsync(request, callerId);
                _logger.LogInformation(
                    "IAM: {Caller} assigned role {RoleId} to {User} (farm {Farm}).",
                    callerId, request.RoleId, request.UserId, request.FarmId ?? "org-wide");
                return Ok(new { assigned = true });
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "role assignment");
            }
        }

        [HttpDelete("assignments/{id:int}")]
        public async Task<ActionResult> RevokeRole(int id, [FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            try
            {
                if (!await Holds(callerId, farmId, "office.access.edit")) return Forbid();
                await _service.RevokeUserRoleAsync(id);
                _logger.LogInformation("IAM: {Caller} revoked assignment {Id}.", callerId, id);
                return Ok(new { revoked = true });
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "role revoke");
            }
        }

        /// <summary>Grant or deny one permission for one person. A reason is required.</summary>
        [HttpPost("overrides")]
        public async Task<ActionResult> SetOverride([FromBody] IamOverrideRequest request)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            if (string.IsNullOrWhiteSpace(request.Reason))
                return BadRequest(new { message = "A reason is required for a permission override." });

            try
            {
                if (!await Holds(callerId, request.FarmId, "office.access.edit")) return Forbid();
                await _service.SetUserPermissionAsync(request, callerId);
                _logger.LogInformation(
                    "IAM: {Caller} set override {Effect} {Key} for {User}.",
                    callerId, request.Effect, request.PermissionKey, request.UserId);
                return Ok(new { saved = true });
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "override save");
            }
        }

        [HttpDelete("overrides/{id:int}")]
        public async Task<ActionResult> ClearOverride(int id, [FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            try
            {
                if (!await Holds(callerId, farmId, "office.access.edit")) return Forbid();
                await _service.ClearUserPermissionAsync(id);
                _logger.LogInformation("IAM: {Caller} cleared override {Id}.", callerId, id);
                return Ok(new { cleared = true });
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "override clear");
            }
        }

        // ---- Phase 4: governance (migration 203) ------------------------------

        /// <summary>Where someone is signed in. Your own, or anyone's with office.access.view.</summary>
        [HttpGet("sessions")]
        public async Task<ActionResult<IEnumerable<IamSessionModel>>> GetSessions(
            [FromQuery] string? userId,
            [FromQuery] bool includeRevoked = false,
            [FromQuery] string? farmId = null)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            var targetId = string.IsNullOrWhiteSpace(userId) ? callerId : userId.Trim();

            try
            {
                if (!string.Equals(targetId, callerId, StringComparison.OrdinalIgnoreCase)
                    && !await MayManageAccess(callerId, farmId))
                {
                    return Forbid();
                }

                return Ok(await _service.GetSessionsAsync(targetId, includeRevoked));
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "sessions");
            }
        }

        /// <summary>
        /// End one session. Anyone may end their own; ending someone else's needs
        /// office.access.edit.
        /// </summary>
        [HttpDelete("sessions/{sessionId}")]
        public async Task<ActionResult> RevokeSession(string sessionId, [FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            try
            {
                // Look up the owner first — otherwise anyone holding a session id
                // could end a stranger's session.
                var mine = await _service.GetSessionsAsync(callerId, includeRevoked: true);
                var isOwn = mine.Any(s => string.Equals(s.SessionId, sessionId, StringComparison.Ordinal));

                if (!isOwn && !await Holds(callerId, farmId, "office.access.edit")) return Forbid();

                await _service.RevokeSessionAsync(sessionId, callerId);
                _logger.LogInformation("IAM: {Caller} revoked session {Session}.", callerId, sessionId);
                return Ok(new { revoked = true });
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "session revoke");
            }
        }

        /// <summary>
        /// Sign someone out everywhere. Stamps a watermark so tokens already
        /// issued stop being accepted, not just the sessions we have rows for.
        /// </summary>
        [HttpPost("sessions/revoke-all")]
        public async Task<ActionResult> RevokeAllSessions([FromBody] IamRevokeAllRequest request, [FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            var targetId = string.IsNullOrWhiteSpace(request?.UserId) ? callerId : request!.UserId.Trim();

            try
            {
                if (!string.Equals(targetId, callerId, StringComparison.OrdinalIgnoreCase)
                    && !await Holds(callerId, farmId, "office.access.edit"))
                {
                    return Forbid();
                }

                await _service.RevokeAllSessionsAsync(targetId, callerId);
                _logger.LogWarning("IAM: {Caller} signed {Target} out of every device.", callerId, targetId);
                return Ok(new { revoked = true });
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "sign out everywhere");
            }
        }

        [HttpGet("policy")]
        public async Task<ActionResult<IamPolicyModel>> GetPolicy([FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            try
            {
                if (!await MayManageAccess(callerId, farmId)) return Forbid();
                return Ok(await _service.GetPolicyAsync(callerId));
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "policy");
            }
        }

        [HttpPut("policy")]
        public async Task<ActionResult> SetPolicy([FromBody] IamPolicyModel policy, [FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            try
            {
                if (!await Holds(callerId, farmId, "office.access.edit")) return Forbid();
                await _service.SetPolicyAsync(callerId, policy);
                _logger.LogInformation("IAM: {Caller} updated the security policy.", callerId);
                return Ok(new { saved = true });
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "policy save");
            }
        }

        /// <summary>Who changed whose access, and when.</summary>
        [HttpGet("access-audit")]
        public async Task<ActionResult<IEnumerable<IamAccessAuditModel>>> GetAccessAudit(
            [FromQuery] string? subjectId,
            [FromQuery] int days = 90,
            [FromQuery] string? farmId = null)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            try
            {
                if (!await MayManageAccess(callerId, farmId)) return Forbid();
                return Ok(await _service.GetAccessAuditAsync(callerId, subjectId, days));
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "access audit");
            }
        }

        /// <summary>Everyone in the organization, with how stale their review and activity are.</summary>
        [HttpGet("access-review")]
        public async Task<ActionResult<IEnumerable<IamAccessReviewRow>>> GetAccessReview([FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            try
            {
                if (!await MayManageAccess(callerId, farmId)) return Forbid();
                return Ok(await _service.GetAccessReviewAsync(callerId));
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "access review");
            }
        }

        [HttpPost("access-review")]
        public async Task<ActionResult> RecordAccessReview([FromBody] IamAccessReviewRequest request, [FromQuery] string? farmId)
        {
            var callerId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrWhiteSpace(callerId))
                return Unauthorized(new { message = "No user id on the token." });

            if (string.IsNullOrWhiteSpace(request?.UserId))
                return BadRequest(new { message = "A user is required." });

            try
            {
                if (!await Holds(callerId, farmId, "office.access.edit")) return Forbid();
                await _service.RecordAccessReviewAsync(request, callerId);
                _logger.LogInformation(
                    "IAM: {Caller} reviewed {Target} as {Decision}.", callerId, request.UserId, request.Decision);
                return Ok(new { recorded = true });
            }
            catch (PostgresException ex)
            {
                return HandleSql(ex, "access review");
            }
        }

        private Task<bool> MayManageAccess(string callerId, string? farmId)
            => Holds(callerId, farmId, "office.access.view");

        private Task<bool> Holds(string callerId, string? farmId, string permissionKey)
        {
            var scope = string.IsNullOrWhiteSpace(farmId) ? User.FindFirst("FarmId")?.Value : farmId;
            return _service.HasPermissionAsync(callerId, scope, permissionKey);
        }

        // The procs RAISERROR at severity 16 for rule violations — a built-in role
        // being edited, a role still assigned to someone. Those are the admin's
        // problem to fix, so the message goes back as a 400 rather than being
        // flattened into a 500 alongside genuine schema failures.
        private ActionResult HandleSql(PostgresException ex, string what)
        {
            // T-SQL raised these with RAISERROR severity 16; the converted
            // functions use RAISE EXCEPTION, which PostgreSQL reports as
            // SQLSTATE P0001 (raise_exception). Anything else is a real fault.
            if (ex.SqlState == "P0001")
            {
                _logger.LogInformation("IAM {What} rejected: {Message}", what, ex.Message);
                return BadRequest(new { message = ex.Message });
            }
            return MissingSchema(ex, what);
        }

        // A farm that has not had 199 applied yet should say so plainly rather
        // than surfacing a raw SQL error — this API is called on every page load
        // once the frontend shim is wired in.
        private ActionResult MissingSchema(PostgresException ex, string what)
        {
            _logger.LogError(ex, "IAM {What} query failed (SQL {SqlState})", what, ex.SqlState);
            return StatusCode(500, new
            {
                message = $"IAM {what} unavailable. Apply Migrations/199_IamFoundation.sql.",
                sqlState = ex.SqlState,
                sqlMessage = ex.Message,
            });
        }
    }
}
