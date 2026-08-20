// =============================================================================
// Reading and writing an employee's permission snapshot.
//
// Extracted from components/employees/edit-employee-dialog.tsx so the Business
// Office "Manage access" dialog can show the same Admin Access / Staff Page
// Access controls without a second copy of this resolution logic.
//
// The backend is inconsistent about casing (isAdmin vs IsAdmin, permissions vs
// Permissions) and older records answer without permission fields at all, hence
// the normalise step and the localStorage fallback.
// =============================================================================

import {
  type AdminPermissionKey,
  DEFAULT_ADMIN_PERMISSIONS,
  ADMIN_PERMISSION_OPTIONS,
  type StaffFeaturePermissionKey,
  DEFAULT_STAFF_FEATURE_PERMISSIONS,
  STAFF_FEATURE_PERMISSION_OPTIONS,
} from "@/lib/employees/permissions"

export type EmployeePermissionSnapshot = {
  isAdmin: boolean
  adminTitle: string
  adminPermissions: Record<AdminPermissionKey, boolean>
  featurePermissions: Record<StaffFeaturePermissionKey, boolean>
}

export const blankPermissionSnapshot = (): EmployeePermissionSnapshot => ({
  isAdmin: false,
  adminTitle: "",
  adminPermissions: { ...DEFAULT_ADMIN_PERMISSIONS },
  featurePermissions: { ...DEFAULT_STAFF_FEATURE_PERMISSIONS },
})

export const toBoolean = (value: unknown): boolean | undefined => {
  if (typeof value === "boolean") return value
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase()
    if (normalized === "true") return true
    if (normalized === "false") return false
  }
  return undefined
}

export const normalizeAdminPermissions = (source: unknown): Record<AdminPermissionKey, boolean> => {
  const normalized = { ...DEFAULT_ADMIN_PERMISSIONS }
  if (!source || typeof source !== "object") return normalized

  const record = source as Record<string, unknown>
  for (const option of ADMIN_PERMISSION_OPTIONS) {
    const raw = toBoolean(record[option.key] ?? record[option.key.charAt(0).toUpperCase() + option.key.slice(1)])
    if (raw !== undefined) normalized[option.key] = raw
  }

  return normalized
}

export const normalizeFeaturePermissions = (source: unknown): Record<StaffFeaturePermissionKey, boolean> => {
  const normalized = { ...DEFAULT_STAFF_FEATURE_PERMISSIONS }
  if (!source || typeof source !== "object") return normalized

  const record = source as Record<string, unknown>
  for (const option of STAFF_FEATURE_PERMISSION_OPTIONS) {
    const raw = toBoolean(record[option.key] ?? record[option.key.charAt(0).toUpperCase() + option.key.slice(1)])
    if (raw !== undefined) normalized[option.key] = raw
  }

  return normalized
}

const EMPLOYEE_PERMISSION_CACHE_KEY = "employeePermissionOverrides"

export const loadCachedEmployeePermissions = (employeeId: string): EmployeePermissionSnapshot | null => {
  if (typeof window === "undefined") return null
  try {
    const raw = localStorage.getItem(EMPLOYEE_PERMISSION_CACHE_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as Record<string, unknown>
    const entry = parsed?.[employeeId]
    if (!entry || typeof entry !== "object") return null
    const record = entry as Record<string, unknown>
    return {
      isAdmin: toBoolean(record.isAdmin) ?? false,
      adminTitle: typeof record.adminTitle === "string" ? record.adminTitle : "",
      adminPermissions: normalizeAdminPermissions(record.adminPermissions),
      featurePermissions: normalizeFeaturePermissions(record.featurePermissions),
    }
  } catch {
    return null
  }
}

export const cacheEmployeePermissions = (employeeId: string, snapshot: EmployeePermissionSnapshot) => {
  if (typeof window === "undefined") return
  try {
    const raw = localStorage.getItem(EMPLOYEE_PERMISSION_CACHE_KEY)
    const parsed = raw ? (JSON.parse(raw) as Record<string, unknown>) : {}
    localStorage.setItem(EMPLOYEE_PERMISSION_CACHE_KEY, JSON.stringify({ ...parsed, [employeeId]: snapshot }))
  } catch {
    // Ignore cache failures: API data remains the source of truth when available.
  }
}

/** Shape of a getEmployee() payload, allowing for both casings. */
export type EmployeePermissionSource = {
  isAdmin?: boolean | string
  IsAdmin?: boolean | string
  adminTitle?: string | null
  AdminTitle?: string | null
  permissions?: Record<string, unknown> | null
  Permissions?: Record<string, unknown> | null
  featurePermissions?: Record<string, unknown> | null
  FeaturePermissions?: Record<string, unknown> | null
  featureAccess?: Record<string, unknown> | null
  FeatureAccess?: Record<string, unknown> | null
}

/**
 * Turn an API employee record into a snapshot, falling back to the local cache
 * when the API answered without any permission fields at all (older records).
 */
export function resolveEmployeePermissions(
  data: EmployeePermissionSource,
  employeeId: string,
): EmployeePermissionSnapshot {
  const isAdmin = toBoolean(data.isAdmin) ?? toBoolean(data.IsAdmin) ?? false
  const adminTitle = data.adminTitle ?? data.AdminTitle ?? ""
  const apiAdmin = data.permissions ?? data.Permissions
  const apiFeature = data.featurePermissions ?? data.FeaturePermissions ?? data.featureAccess ?? data.FeatureAccess

  const hasApiPermissions =
    apiAdmin !== undefined ||
    apiFeature !== undefined ||
    data.isAdmin !== undefined ||
    data.IsAdmin !== undefined ||
    data.adminTitle !== undefined ||
    data.AdminTitle !== undefined

  const cached = loadCachedEmployeePermissions(employeeId)

  return {
    isAdmin: hasApiPermissions ? isAdmin : (cached?.isAdmin ?? false),
    adminTitle: hasApiPermissions ? (adminTitle ?? "") : (cached?.adminTitle ?? ""),
    adminPermissions: hasApiPermissions
      ? normalizeAdminPermissions(apiAdmin)
      : cached?.adminPermissions ?? { ...DEFAULT_ADMIN_PERMISSIONS },
    featurePermissions: hasApiPermissions
      ? normalizeFeaturePermissions(apiFeature)
      : cached?.featurePermissions ?? { ...DEFAULT_STAFF_FEATURE_PERMISSIONS },
  }
}
