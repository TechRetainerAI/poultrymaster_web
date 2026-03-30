import { useEffect, useState, useCallback } from "react"
import { refreshFeaturePermissionsFromServer } from "@/lib/api/auth"

export interface FeatureAccessPermissions {
  canEnterSales: boolean
  canEnterExpenses: boolean
  canViewCashLedger: boolean
  canSeeEmployees: boolean
  canViewReports: boolean
  canViewFinancial: boolean
  canViewActivityLog: boolean
  canViewSettings: boolean
}

export interface UserPermissions {
  canDelete: boolean
  canEdit: boolean
  canCreate: boolean
  canView: boolean
  isAdmin: boolean
  isStaff: boolean
  isSubscriber: boolean
  roles: string[]
  featureAccess: FeatureAccessPermissions
  isLoading: boolean
}

const DEFAULT_FEATURE_ACCESS: FeatureAccessPermissions = {
  canEnterSales: true,
  canEnterExpenses: true,
  canViewCashLedger: true,
  canSeeEmployees: false,
  canViewReports: true,
  canViewFinancial: true,
  canViewActivityLog: true,
  canViewSettings: true,
}

/** Staff must be deny-by-default; merging with DEFAULT_FEATURE_ACCESS let missing keys stay "on". */
const STAFF_FEATURE_BASE: FeatureAccessPermissions = {
  canEnterSales: false,
  canEnterExpenses: false,
  canViewCashLedger: false,
  canSeeEmployees: false,
  canViewReports: false,
  canViewFinancial: false,
  canViewActivityLog: false,
  canViewSettings: false,
}

function toBoolean(value: unknown): boolean | undefined {
  if (typeof value === "boolean") return value
  if (typeof value === "number") {
    if (value === 1) return true
    if (value === 0) return false
  }
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase()
    if (normalized === "true" || normalized === "1") return true
    if (normalized === "false" || normalized === "0") return false
  }
  return undefined
}

function normalizeFeatureAccess(raw: Record<string, unknown>): Partial<FeatureAccessPermissions> {
  const normalized: Partial<FeatureAccessPermissions> = {}

  const sales = toBoolean(raw.canEnterSales ?? raw.CanEnterSales ?? raw.canViewSales ?? raw.CanViewSales ?? raw.viewSales ?? raw.ViewSales ?? raw.sales ?? raw.Sales)
  if (sales !== undefined) normalized.canEnterSales = sales

  const expenses = toBoolean(raw.canEnterExpenses ?? raw.CanEnterExpenses ?? raw.canViewExpenses ?? raw.CanViewExpenses ?? raw.viewExpenses ?? raw.ViewExpenses ?? raw.expenses ?? raw.Expenses)
  if (expenses !== undefined) normalized.canEnterExpenses = expenses

  const cash = toBoolean(raw.canViewCashLedger ?? raw.CanViewCashLedger ?? raw.canViewCash ?? raw.CanViewCash ?? raw.viewCash ?? raw.ViewCash ?? raw.cash ?? raw.Cash)
  if (cash !== undefined) normalized.canViewCashLedger = cash

  const employees = toBoolean(raw.canSeeEmployees ?? raw.CanSeeEmployees ?? raw.seeEmployees ?? raw.SeeEmployees ?? raw.viewEmployees ?? raw.ViewEmployees ?? raw.employees ?? raw.Employees)
  if (employees !== undefined) normalized.canSeeEmployees = employees

  const reports = toBoolean(raw.canViewReports ?? raw.CanViewReports ?? raw.viewReports ?? raw.ViewReports ?? raw.reports ?? raw.Reports)
  if (reports !== undefined) normalized.canViewReports = reports

  const financial = toBoolean(raw.canViewFinancial ?? raw.CanViewFinancial ?? raw.viewFinancial ?? raw.ViewFinancial ?? raw.financial ?? raw.Financial)
  if (financial !== undefined) normalized.canViewFinancial = financial

  const activityLog = toBoolean(raw.canViewActivityLog ?? raw.CanViewActivityLog ?? raw.viewActivityLog ?? raw.ViewActivityLog ?? raw.activityLog ?? raw.ActivityLog)
  if (activityLog !== undefined) normalized.canViewActivityLog = activityLog

  const settings = toBoolean(raw.canViewSettings ?? raw.CanViewSettings ?? raw.viewSettings ?? raw.ViewSettings ?? raw.settings ?? raw.Settings)
  if (settings !== undefined) normalized.canViewSettings = settings

  return normalized
}

export function usePermissions(): UserPermissions {
  const [permissions, setPermissions] = useState<UserPermissions>({
    canDelete: false,
    canEdit: false,
    canCreate: false,
    canView: false,
    isAdmin: false,
    isStaff: false,
    isSubscriber: false,
    roles: [],
    featureAccess: DEFAULT_FEATURE_ACCESS,
    isLoading: true,
  })

  const computeFromStorage = useCallback((): UserPermissions => {
    const isStaffStr = localStorage.getItem("isStaff")
    const isStaff = isStaffStr === "true" || isStaffStr === true
    const isSubscriberStr = localStorage.getItem("isSubscriber")
    const isSubscriber = isSubscriberStr === "true" || isSubscriberStr === true
    const rolesString = localStorage.getItem("roles") || "[]"

    let roles: string[] = []
    try {
      roles = JSON.parse(rolesString)
    } catch (e) {
      console.error("[v0] Error parsing roles:", e)
      roles = []
    }

    if (roles.length === 0) {
      if (isStaff) {
        roles = ["Staff", "User"]
        localStorage.setItem("roles", JSON.stringify(roles))
        console.log("[v0] No roles found, defaulting to Staff for employee")
      } else {
        roles = ["Admin", "FarmAdmin"]
        localStorage.setItem("roles", JSON.stringify(roles))
        console.log("[v0] No roles found, defaulting to Admin for non-staff user")
      }
    }

    const hasAdminRole = roles.includes("Admin") || roles.includes("FarmAdmin") || roles.includes("Owner")
    const isAdmin = hasAdminRole || isSubscriber || !isStaff
    const isStaffOnly = isStaff && !isAdmin

    let storedFeatureAccess: Partial<FeatureAccessPermissions> = {}
    const featureAccessRaw = localStorage.getItem("featurePermissions")
    if (featureAccessRaw) {
      try {
        const parsed = JSON.parse(featureAccessRaw)
        if (parsed && typeof parsed === "object") {
          storedFeatureAccess = normalizeFeatureAccess(parsed as Record<string, unknown>)
        }
      } catch (e) {
        console.error("[v0] Error parsing featurePermissions:", e)
        storedFeatureAccess = {}
      }
    }

    const featureBase = isStaffOnly ? STAFF_FEATURE_BASE : DEFAULT_FEATURE_ACCESS
    const featureAccess: FeatureAccessPermissions = {
      ...featureBase,
      ...(isAdmin ? { canSeeEmployees: true } : {}),
      ...storedFeatureAccess,
    }

    return {
      canView: true,
      canCreate: true,
      canEdit: true,
      canDelete: isAdmin,
      isAdmin,
      isStaff,
      isSubscriber,
      roles,
      featureAccess,
      isLoading: false,
    }
  }, [])

  useEffect(() => {
    if (typeof window === "undefined") return

    const apply = () => {
      const userPermissions = computeFromStorage()
      console.log("[v0] ===== USER PERMISSIONS =====")
      console.log("[v0] isStaff:", userPermissions.isStaff)
      console.log("[v0] isSubscriber:", userPermissions.isSubscriber)
      console.log("[v0] roles:", userPermissions.roles)
      console.log("[v0] isAdmin:", userPermissions.isAdmin)
      console.log("[v0] canDelete:", userPermissions.canDelete)
      console.log("[v0] featureAccess:", userPermissions.featureAccess)
      console.log("[v0] ===============================")
      setPermissions(userPermissions)
    }

    apply()

    let cancelled = false
    void (async () => {
      if (!localStorage.getItem("auth_token")) return
      await refreshFeaturePermissionsFromServer()
      if (!cancelled) apply()
    })()

    return () => {
      cancelled = true
    }
  }, [computeFromStorage])

  return permissions
}

// Helper function to check if user has specific permission
export function hasPermission(permission: keyof UserPermissions, permissions: UserPermissions): boolean {
  return permissions[permission] === true
}

