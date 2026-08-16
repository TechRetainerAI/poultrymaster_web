// Identity & Access Management — client for the Farm API's /Iam endpoints
// (migration 199). "Iam" is not one of the proxy's Login-API prefixes, so
// /api/proxy/Iam/* reaches the Farm API without any proxy change.
//
// Every call here degrades to null rather than throwing. Phase 0 ships ahead of
// the migration being applied everywhere, and the permission shim runs on every
// page load — a farm whose database is a migration behind must keep working on
// its legacy flags, not white-screen.

import { farmApiUrl, getAuthHeaders } from "@/lib/api/config"

export interface IamPermission {
  permissionKey: string
  module: string
  resource: string
  action: string
  permissionGroup: string
  resourceLabel: string
  description: string | null
  /** Poultry | Water | Generic, or null for company-neutral office permissions. */
  companyType: string | null
  isDangerous: boolean
  sortOrder: number
}

export interface IamGrant {
  permissionKey: string
  /** "role:Accountant", "override", or "superuser". */
  source: string
}

export interface IamEffectivePermissions {
  userId: string
  farmId: string | null
  grants: IamGrant[]
}

/** Backend JSON is PascalCase; lowercase the first char so the TS layer stays camelCase. */
function lower<T>(value: unknown): T {
  if (Array.isArray(value)) return value.map((v) => lower(v)) as T
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {}
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k.charAt(0).toLowerCase() + k.slice(1)] = lower(v)
    }
    return out as T
  }
  return value as T
}

export interface IamOverride {
  id: number
  permissionKey: string
  /** Allow | Deny. */
  effect: string
  reason: string | null
  grantedBy: string | null
  grantedAt: string
  expiresAt: string | null
  farmId: string | null
  isOrgWide: boolean
  /** Lapsed overrides are returned flagged rather than hidden. */
  hasExpired: boolean
  resourceLabel: string
  action: string
  module: string
  permissionGroup: string
}

export interface IamMutationResult {
  success: boolean
  message?: string
  /** Role id returned by a save. */
  roleId?: number
}

async function getJson<T>(path: string): Promise<T | null> {
  try {
    const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
    if (!res.ok) return null
    const text = await res.text()
    if (!text?.trim()) return null
    return lower<T>(JSON.parse(text))
  } catch {
    return null
  }
}

export interface IamRole {
  roleId: number
  /** Stable id for built-ins ("sys-accountant"); null for custom roles. */
  roleKey: string | null
  name: string
  description: string | null
  companyType: string | null
  isSystem: boolean
  isSuperuser: boolean
  isActive: boolean
  /** Keys granted. For a superuser role this is the whole catalog. */
  permissionCount: number
  /**
   * People in YOUR organization holding this role. Built-in roles are shared
   * across organizations, so this is deliberately scoped rather than global.
   * Zero against a database still on migration 200, which does not return it.
   */
  assignedUserCount: number
}

export interface IamUserRole {
  id: number
  roleId: number
  roleKey: string | null
  name: string
  description: string | null
  isSystem: boolean
  isSuperuser: boolean
  farmId: string | null
  isOrgWide: boolean
  assignedBy: string | null
  assignedAt: string
  expiresAt: string | null
}

export interface IamStatus {
  /** True once the API enforces permissions (`Iam:Enforced`). */
  enforced: boolean
  /** Whether a route with no permission mapping is blocked. */
  denyUnmapped: boolean
}

/**
 * Whether the API is enforcing permissions yet. The server owns this — see
 * lib/iam/resolve.ts for why the client must not decide it independently.
 */
export async function getIamStatus(): Promise<IamStatus | null> {
  return getJson<IamStatus>("Iam/status")
}

/** The permission catalog. Static — cache it for the session. */
export async function getIamCatalog(): Promise<IamPermission[] | null> {
  return getJson<IamPermission[]>("Iam/catalog")
}

/** Built-in roles plus any this organization owns. */
export async function getIamRoles(farmId?: string | null): Promise<IamRole[] | null> {
  return getJson<IamRole[]>(`Iam/roles${farmId ? `?farmId=${encodeURIComponent(farmId)}` : ""}`)
}

/** The keys one role grants. */
export async function getRolePermissions(roleId: number, farmId?: string | null): Promise<string[] | null> {
  return getJson<string[]>(
    `Iam/roles/${roleId}/permissions${farmId ? `?farmId=${encodeURIComponent(farmId)}` : ""}`
  )
}

/** The roles one person holds in one company. Omit userId for yourself. */
export async function getUserRoles(
  farmId?: string | null,
  userId?: string | null
): Promise<IamUserRole[] | null> {
  const params = new URLSearchParams()
  if (userId) params.set("userId", userId)
  if (farmId) params.set("farmId", farmId)
  const qs = params.toString()
  return getJson<IamUserRole[]>(`Iam/user-roles${qs ? `?${qs}` : ""}`)
}

/** Overrides on one person. Omit userId for yourself. */
export async function getUserOverrides(
  farmId?: string | null,
  userId?: string | null
): Promise<IamOverride[] | null> {
  const params = new URLSearchParams()
  if (userId) params.set("userId", userId)
  if (farmId) params.set("farmId", farmId)
  const qs = params.toString()
  return getJson<IamOverride[]>(`Iam/overrides${qs ? `?${qs}` : ""}`)
}

// ---- Writes ----------------------------------------------------------------
//
// Unlike the reads, these surface their failure message. The stored procedures
// reject rule violations with a sentence written for an admin ("This role is
// still assigned to 3 person(s)"), and swallowing that would leave the UI saying
// nothing more useful than "failed".

async function mutate(path: string, method: "POST" | "PUT" | "DELETE", body?: unknown): Promise<IamMutationResult> {
  try {
    const res = await fetch(farmApiUrl(path), {
      method,
      headers: getAuthHeaders(), // already sets Content-Type: application/json
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    })

    const text = await res.text()
    let payload: Record<string, unknown> = {}
    if (text?.trim()) {
      try { payload = lower<Record<string, unknown>>(JSON.parse(text)) } catch { /* non-JSON body */ }
    }

    if (!res.ok) {
      const message = typeof payload.message === "string" && payload.message
        ? payload.message
        : res.status === 403
          ? "You do not have permission to change access settings."
          : `Request failed (${res.status}).`
      return { success: false, message }
    }

    return { success: true, roleId: typeof payload.roleId === "number" ? payload.roleId : undefined }
  } catch (e) {
    return { success: false, message: e instanceof Error ? e.message : "Network error." }
  }
}

/** Create a custom role (omit roleId) or rename one. Built-ins are rejected. */
export async function saveRole(input: {
  roleId?: number
  name: string
  description?: string | null
  companyType?: string | null
  copyFromRoleId?: number | null
}, farmId?: string | null): Promise<IamMutationResult> {
  return mutate(`Iam/roles${farmId ? `?farmId=${encodeURIComponent(farmId)}` : ""}`, "POST", input)
}

export async function deleteRole(roleId: number, farmId?: string | null): Promise<IamMutationResult> {
  return mutate(`Iam/roles/${roleId}${farmId ? `?farmId=${encodeURIComponent(farmId)}` : ""}`, "DELETE")
}

/** Replace a custom role's grants with exactly this set. */
export async function setRolePermissions(
  roleId: number,
  permissionKeys: string[],
  farmId?: string | null
): Promise<IamMutationResult> {
  return mutate(
    `Iam/roles/${roleId}/permissions${farmId ? `?farmId=${encodeURIComponent(farmId)}` : ""}`,
    "PUT",
    { permissionKeys }
  )
}

/** Assign a role. farmId null assigns across every company in the organization. */
export async function assignRole(input: {
  userId: string
  roleId: number
  farmId?: string | null
  expiresAt?: string | null
}): Promise<IamMutationResult> {
  return mutate("Iam/assignments", "POST", input)
}

export async function revokeRole(id: number, farmId?: string | null): Promise<IamMutationResult> {
  return mutate(`Iam/assignments/${id}${farmId ? `?farmId=${encodeURIComponent(farmId)}` : ""}`, "DELETE")
}

/** Grant or deny one permission for one person. The reason is mandatory. */
export async function setOverride(input: {
  userId: string
  farmId?: string | null
  permissionKey: string
  effect: "Allow" | "Deny"
  reason: string
  expiresAt?: string | null
}): Promise<IamMutationResult> {
  return mutate("Iam/overrides", "POST", input)
}

export async function clearOverride(id: number, farmId?: string | null): Promise<IamMutationResult> {
  return mutate(`Iam/overrides/${id}${farmId ? `?farmId=${encodeURIComponent(farmId)}` : ""}`, "DELETE")
}

// ---- Phase 4: governance ---------------------------------------------------

export interface IamSession {
  sessionId: string
  userId: string
  farmId: string | null
  ipAddress: string | null
  userAgent: string | null
  device: string | null
  createdAt: string
  lastSeenAt: string
  revokedAt: string | null
  revokedBy: string | null
  isActive: boolean
}

export interface IamPolicy {
  ownerUserId: string
  passwordMinLength: number
  passwordRequireUpper: boolean
  passwordRequireDigit: boolean
  passwordRequireSymbol: boolean
  /** 0 = never expires. */
  passwordExpiryDays: number
  /** 0 = no idle timeout. */
  sessionIdleMinutes: number
  /** 0 = no cap. */
  sessionMaxHours: number
  requireMfaForAdmins: boolean
  dormantAfterDays: number
  accessReviewDays: number
  updatedAt: string
  updatedBy: string | null
}

export interface IamAccessAuditEntry {
  id: number
  occurredAt: string
  entity: string
  operation: string
  subjectId: string | null
  actorId: string | null
  farmId: string | null
  detail: string | null
  subjectName: string | null
  actorName: string | null
}

export interface IamAccessReviewRow {
  userId: string
  firstName: string | null
  lastName: string | null
  email: string | null
  userName: string | null
  isStaff: boolean
  roleCount: number
  overrideCount: number
  lastSeenAt: string | null
  lastReviewedAt: string | null
  lastDecision: string | null
  isDormant: boolean
  reviewIsStale: boolean
}

/** Where someone is signed in. Omit userId for yourself. */
export async function getSessions(userId?: string | null, includeRevoked = false): Promise<IamSession[] | null> {
  const params = new URLSearchParams()
  if (userId) params.set("userId", userId)
  if (includeRevoked) params.set("includeRevoked", "true")
  const qs = params.toString()
  return getJson<IamSession[]>(`Iam/sessions${qs ? `?${qs}` : ""}`)
}

export async function revokeSession(sessionId: string, farmId?: string | null): Promise<IamMutationResult> {
  return mutate(
    `Iam/sessions/${encodeURIComponent(sessionId)}${farmId ? `?farmId=${encodeURIComponent(farmId)}` : ""}`,
    "DELETE"
  )
}

/** Sign someone out of every device, including tokens already issued. */
export async function revokeAllSessions(userId: string, farmId?: string | null): Promise<IamMutationResult> {
  return mutate(
    `Iam/sessions/revoke-all${farmId ? `?farmId=${encodeURIComponent(farmId)}` : ""}`,
    "POST",
    { userId }
  )
}

export async function getPolicy(farmId?: string | null): Promise<IamPolicy | null> {
  return getJson<IamPolicy>(`Iam/policy${farmId ? `?farmId=${encodeURIComponent(farmId)}` : ""}`)
}

export async function savePolicy(policy: IamPolicy, farmId?: string | null): Promise<IamMutationResult> {
  return mutate(`Iam/policy${farmId ? `?farmId=${encodeURIComponent(farmId)}` : ""}`, "PUT", policy)
}

/** Who changed whose access, and when. */
export async function getAccessAudit(subjectId?: string | null, days = 90): Promise<IamAccessAuditEntry[] | null> {
  const params = new URLSearchParams()
  if (subjectId) params.set("subjectId", subjectId)
  params.set("days", String(days))
  return getJson<IamAccessAuditEntry[]>(`Iam/access-audit?${params.toString()}`)
}

export async function getAccessReview(farmId?: string | null): Promise<IamAccessReviewRow[] | null> {
  return getJson<IamAccessReviewRow[]>(`Iam/access-review${farmId ? `?farmId=${encodeURIComponent(farmId)}` : ""}`)
}

export async function recordAccessReview(input: {
  userId: string
  farmId?: string | null
  decision: "Confirmed" | "Flagged"
  note?: string | null
}, farmId?: string | null): Promise<IamMutationResult> {
  return mutate(`Iam/access-review${farmId ? `?farmId=${encodeURIComponent(farmId)}` : ""}`, "POST", input)
}

/**
 * What a user can do in one company. Omit both arguments for "me, in my active
 * company". Reading someone else's set requires office.access.view.
 */
export async function getEffectivePermissions(
  farmId?: string | null,
  userId?: string | null
): Promise<IamEffectivePermissions | null> {
  const params = new URLSearchParams()
  if (userId) params.set("userId", userId)
  if (farmId) params.set("farmId", farmId)
  const qs = params.toString()
  return getJson<IamEffectivePermissions>(`Iam/effective-permissions${qs ? `?${qs}` : ""}`)
}
