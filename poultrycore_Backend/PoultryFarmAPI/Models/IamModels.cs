namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// One entry in the permission catalog (migration 199). The catalog is the
    /// source of truth for what can be granted; the frontend renders the matrix
    /// straight off these rows rather than keeping its own copy of the keys.
    /// </summary>
    public class IamPermissionModel
    {
        public string PermissionKey { get; set; } = string.Empty;   // module.resource.action
        public string Module { get; set; } = string.Empty;          // poultry|water|generic|office
        public string Resource { get; set; } = string.Empty;
        public string Action { get; set; } = string.Empty;          // view|create|edit|delete|approve|export
        public string PermissionGroup { get; set; } = string.Empty; // UI grouping, e.g. "Finance"
        public string ResourceLabel { get; set; } = string.Empty;
        public string? Description { get; set; }
        /// <summary>Poultry|Water|Generic, or null for company-neutral office permissions.</summary>
        public string? CompanyType { get; set; }
        public bool IsDangerous { get; set; }
        public int SortOrder { get; set; }
    }

    /// <summary>A single resolved grant, with the role (or override) that produced it.</summary>
    public class IamGrantModel
    {
        public string PermissionKey { get; set; } = string.Empty;
        /// <summary>"role:Accountant", "override", or "superuser".</summary>
        public string Source { get; set; } = string.Empty;
    }

    /// <summary>
    /// What a user can do in one company. FarmId null means the caller asked for
    /// the org-wide set only.
    /// </summary>
    public class IamEffectivePermissionsModel
    {
        public string UserId { get; set; } = string.Empty;
        public string? FarmId { get; set; }
        public List<IamGrantModel> Grants { get; set; } = new();
    }

    /// <summary>A role, built-in or custom (migration 200).</summary>
    public class IamRoleModel
    {
        public int RoleId { get; set; }
        /// <summary>Stable id for built-ins ("sys-accountant"); null for custom roles.</summary>
        public string? RoleKey { get; set; }
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
        /// <summary>Role only offered for this company type; null means any.</summary>
        public string? CompanyType { get; set; }
        public bool IsSystem { get; set; }
        public bool IsSuperuser { get; set; }
        public bool IsActive { get; set; }
        /// <summary>Keys granted. For a superuser role this is the whole catalog.</summary>
        public int PermissionCount { get; set; }
        /// <summary>People in the CALLER's organization holding this role (migration 201).</summary>
        public int AssignedUserCount { get; set; }
    }

    /// <summary>A per-user permission override layered on top of their roles.</summary>
    public class IamOverrideModel
    {
        public int Id { get; set; }
        public string PermissionKey { get; set; } = string.Empty;
        /// <summary>Allow | Deny.</summary>
        public string Effect { get; set; } = string.Empty;
        public string? Reason { get; set; }
        public string? GrantedBy { get; set; }
        public DateTime GrantedAt { get; set; }
        public DateTime? ExpiresAt { get; set; }
        public string? FarmId { get; set; }
        public bool IsOrgWide { get; set; }
        /// <summary>Lapsed overrides are returned, flagged, rather than hidden.</summary>
        public bool HasExpired { get; set; }
        public string ResourceLabel { get; set; } = string.Empty;
        public string Action { get; set; } = string.Empty;
        public string Module { get; set; } = string.Empty;
        public string PermissionGroup { get; set; } = string.Empty;
    }

    // ---- Request bodies --------------------------------------------------

    public class IamRoleSaveRequest
    {
        public int? RoleId { get; set; }
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
        public string? CompanyType { get; set; }
        /// <summary>Clone this role's grants. Only honoured when creating.</summary>
        public int? CopyFromRoleId { get; set; }
    }

    public class IamRolePermissionsRequest
    {
        public List<string> PermissionKeys { get; set; } = new();
    }

    public class IamAssignRoleRequest
    {
        public string UserId { get; set; } = string.Empty;
        public int RoleId { get; set; }
        /// <summary>Null assigns across every company in the organization.</summary>
        public string? FarmId { get; set; }
        public DateTime? ExpiresAt { get; set; }
    }

    // ---- Phase 4: governance (migration 203) -----------------------------

    /// <summary>A sign-in. Revoking one stops that device; revoking all stamps a watermark.</summary>
    public class IamSessionModel
    {
        public string SessionId { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string? FarmId { get; set; }
        public string? IpAddress { get; set; }
        public string? UserAgent { get; set; }
        public string? Device { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime LastSeenAt { get; set; }
        public DateTime? RevokedAt { get; set; }
        public string? RevokedBy { get; set; }
        public bool IsActive { get; set; }
    }

    /// <summary>
    /// Password and session rules for an organization.
    /// Stored here; password rules are enforced by the Login API.
    /// </summary>
    public class IamPolicyModel
    {
        public string OwnerUserId { get; set; } = string.Empty;
        public int PasswordMinLength { get; set; } = 8;
        public bool PasswordRequireUpper { get; set; } = true;
        public bool PasswordRequireDigit { get; set; } = true;
        public bool PasswordRequireSymbol { get; set; }
        /// <summary>0 = never expires.</summary>
        public int PasswordExpiryDays { get; set; }
        /// <summary>0 = no idle timeout.</summary>
        public int SessionIdleMinutes { get; set; }
        /// <summary>0 = no cap.</summary>
        public int SessionMaxHours { get; set; }
        public bool RequireMfaForAdmins { get; set; }
        public int DormantAfterDays { get; set; } = 90;
        /// <summary>How long an access review stays fresh before it reads as stale.</summary>
        public int AccessReviewDays { get; set; } = 180;
        public DateTime UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
    }

    /// <summary>One recorded change to someone's access, written by trigger.</summary>
    public class IamAccessAuditModel
    {
        public long Id { get; set; }
        public DateTime OccurredAt { get; set; }
        /// <summary>Role | RolePermission | UserRole | UserPermission.</summary>
        public string Entity { get; set; } = string.Empty;
        /// <summary>Insert | Update | Delete.</summary>
        public string Operation { get; set; } = string.Empty;
        public string? SubjectId { get; set; }
        public string? ActorId { get; set; }
        public string? FarmId { get; set; }
        public string? Detail { get; set; }
        public string? SubjectName { get; set; }
        public string? ActorName { get; set; }
    }

    /// <summary>One row of the access review: who has what, and how stale that is.</summary>
    public class IamAccessReviewRow
    {
        public string UserId { get; set; } = string.Empty;
        public string? FirstName { get; set; }
        public string? LastName { get; set; }
        public string? Email { get; set; }
        public string? UserName { get; set; }
        public bool IsStaff { get; set; }
        public int RoleCount { get; set; }
        public int OverrideCount { get; set; }
        public DateTime? LastSeenAt { get; set; }
        public DateTime? LastReviewedAt { get; set; }
        public string? LastDecision { get; set; }
        public bool IsDormant { get; set; }
        public bool ReviewIsStale { get; set; }
    }

    public class IamRevokeAllRequest
    {
        public string UserId { get; set; } = string.Empty;
    }

    public class IamAccessReviewRequest
    {
        public string UserId { get; set; } = string.Empty;
        public string? FarmId { get; set; }
        /// <summary>Confirmed | Flagged.</summary>
        public string Decision { get; set; } = string.Empty;
        public string? Note { get; set; }
    }

    public class IamOverrideRequest
    {
        public string UserId { get; set; } = string.Empty;
        public string? FarmId { get; set; }
        public string PermissionKey { get; set; } = string.Empty;
        public string Effect { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
        public DateTime? ExpiresAt { get; set; }
    }

    /// <summary>One role held by one person, in one company or org-wide.</summary>
    public class IamUserRoleModel
    {
        public int Id { get; set; }
        public int RoleId { get; set; }
        public string? RoleKey { get; set; }
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
        public bool IsSystem { get; set; }
        public bool IsSuperuser { get; set; }
        public string? FarmId { get; set; }
        public bool IsOrgWide { get; set; }
        public string? AssignedBy { get; set; }
        public DateTime AssignedAt { get; set; }
        public DateTime? ExpiresAt { get; set; }
    }
}
