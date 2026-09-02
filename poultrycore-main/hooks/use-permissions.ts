import { useEffect, useState, useCallback, useMemo } from "react"
import { refreshFeaturePermissionsFromServer } from "@/lib/api/auth"
import { getEffectivePermissions, getIamStatus } from "@/lib/api/iam"
import { resolveEffectivePermissions } from "@/lib/iam/resolve"
import { COMPANY_CHANGED_EVENT } from "@/lib/store/auth-store"
import { WATER_STAFF_FEATURE_KEYS } from "@/lib/employees/permissions"
import type { PermissionKey } from "@/lib/iam/keys"

export interface FeatureAccessPermissions {
  canEnterSales: boolean
  canEnterExpenses: boolean
  canViewCashLedger: boolean
  canSeeEmployees: boolean
  canViewReports: boolean
  canViewFinancial: boolean
  /** Customers page / CRM; independent of full financial umbrella when set from API */
  canViewCustomers: boolean
  canViewActivityLog: boolean
  canViewSettings: boolean
  /** Feed Production module: see the pages/batches/formulas. */
  canViewFeedProduction: boolean
  /** Feed Production module: create/edit/post/reverse batches + manage formulas. */
  canManageFeedProduction: boolean
  /** Feed Production module: see cost figures (unit costs, totals, cost reports). */
  canViewFeedProductionCost: boolean
  /** Water: Production, Batch Production, Products, Machines, Boreholes. */
  canViewWaterProduction: boolean
  /** Water: Driver returns, Drivers, Vehicles, Routes, Driver collection report. */
  canViewWaterDeliveries: boolean
  /** Water: Stock movement, Inventory, Raw materials, Damages & loss, Production losses. */
  canViewWaterInventory: boolean
  /**
   * Internal Use — stock consumed internally (staff welfare, owner use,
   * donations, samples, testing). One flag across all three company types, the
   * way canViewWaterInventory covers five water pages.
   */
  canViewInternalUse: boolean
  /** Water: the Maintenance register. */
  canViewWaterMaintenance: boolean
  /** Water: Payroll runs. */
  canViewWaterPayroll: boolean
  /** Water: Setup and Company Setup. */
  canViewWaterSetup: boolean
  /** Hotel: Room inventory, housekeeping, room service. */
  canViewHotelRooms: boolean
  /** Hotel: Bookings, check-in/out, guests. */
  canViewHotelBookings: boolean
  /** Hotel: Housekeeping tasks. */
  canViewHotelHousekeeping: boolean
  /** Hotel: Billing, invoices. */
  canViewHotelBilling: boolean
  /** Hotel: Restaurant POS, tables, menu, kitchen. */
  canViewHotelRestaurant: boolean
  /** Hotel: Staff management. */
  canViewHotelStaff: boolean
  /** Hotel: Payroll runs. */
  canViewHotelPayroll: boolean
  /** Hotel: Inventory / supplies. */
  canViewHotelInventory: boolean
  /** Hotel: Maintenance requests. */
  canViewHotelMaintenance: boolean
  /** Hotel: Setup. */
  canViewHotelSetup: boolean
  /** Restaurant: POS / Orders. */
  canViewRestaurantPOS: boolean
  /** Restaurant: Kitchen Display. */
  canViewRestaurantKDS: boolean
  /** Restaurant: Menu management. */
  canViewRestaurantMenu: boolean
  /** Restaurant: Floor plan & tables. */
  canViewRestaurantFloorPlan: boolean
  /** Restaurant: Reservations & waitlist. */
  canViewRestaurantReservations: boolean
  /** Restaurant: Online ordering. */
  canViewRestaurantOnlineOrders: boolean
  /** Restaurant: Delivery management. */
  canViewRestaurantDelivery: boolean
  /** Restaurant: Staff & payroll. */
  canViewRestaurantStaff: boolean
  /** Restaurant: Setup / config. */
  canViewRestaurantSetup: boolean
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
  /**
   * IAM check (migration 199). `can("poultry.sales.create")`.
   *
   * While IAM is additive this answers from the legacy flags mapped onto
   * catalog keys, unioned with anything IAM grants for the ACTIVE company — so
   * it is safe to migrate a page from `featureAccess.canEnterSales` to
   * `can("poultry.sales.create")` today without waiting for roles to be
   * assigned. See lib/iam/resolve.ts for the rule and when it changes.
   */
  can: (key: PermissionKey) => boolean
  /** Every key held in the active company. Empty when `isSuperuser`. */
  permissionKeys: Set<PermissionKey>
  /** Holds everything, including keys added later. Legacy admins qualify. */
  isSuperuser: boolean
}

const DEFAULT_FEATURE_ACCESS: FeatureAccessPermissions = {
  canEnterSales: true,
  canEnterExpenses: true,
  canViewCashLedger: true,
  canSeeEmployees: false,
  canViewReports: true,
  canViewFinancial: true,
  canViewCustomers: true,
  canViewActivityLog: true,
  canViewSettings: true,
  canViewFeedProduction: true,
  canManageFeedProduction: true,
  canViewFeedProductionCost: true,
  canViewWaterProduction: true,
  canViewWaterDeliveries: true,
  canViewWaterInventory: true,
  canViewInternalUse: true,
  canViewWaterMaintenance: true,
  canViewWaterPayroll: true,
  canViewWaterSetup: true,
  canViewHotelRooms: true,
  canViewHotelBookings: true,
  canViewHotelHousekeeping: true,
  canViewHotelBilling: true,
  canViewHotelRestaurant: true,
  canViewHotelStaff: true,
  canViewHotelPayroll: true,
  canViewHotelInventory: true,
  canViewHotelMaintenance: true,
  canViewHotelSetup: true,
  canViewRestaurantPOS: true,
  canViewRestaurantKDS: true,
  canViewRestaurantMenu: true,
  canViewRestaurantFloorPlan: true,
  canViewRestaurantReservations: true,
  canViewRestaurantOnlineOrders: true,
  canViewRestaurantDelivery: true,
  canViewRestaurantStaff: true,
  canViewRestaurantSetup: true,
}

/** Staff must be deny-by-default; merging with DEFAULT_FEATURE_ACCESS let missing keys stay "on". */
const STAFF_FEATURE_BASE: FeatureAccessPermissions = {
  canEnterSales: false,
  canEnterExpenses: false,
  canViewCashLedger: false,
  canSeeEmployees: false,
  canViewReports: false,
  canViewFinancial: false,
  canViewCustomers: false,
  canViewActivityLog: false,
  canViewSettings: false,
  canViewFeedProduction: false,
  canManageFeedProduction: false,
  canViewFeedProductionCost: false,
  canViewWaterProduction: false,
  canViewWaterDeliveries: false,
  canViewWaterInventory: false,
  canViewInternalUse: false,
  canViewWaterMaintenance: false,
  canViewWaterPayroll: false,
  canViewWaterSetup: false,
  canViewHotelRooms: false,
  canViewHotelBookings: false,
  canViewHotelHousekeeping: false,
  canViewHotelBilling: false,
  canViewHotelRestaurant: false,
  canViewHotelStaff: false,
  canViewHotelPayroll: false,
  canViewHotelInventory: false,
  canViewHotelMaintenance: false,
  canViewHotelSetup: false,
  canViewRestaurantPOS: false,
  canViewRestaurantKDS: false,
  canViewRestaurantMenu: false,
  canViewRestaurantFloorPlan: false,
  canViewRestaurantReservations: false,
  canViewRestaurantOnlineOrders: false,
  canViewRestaurantDelivery: false,
  canViewRestaurantStaff: false,
  canViewRestaurantSetup: false,
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

  const customers = toBoolean(
    raw.canViewCustomers ??
      raw.CanViewCustomers ??
      raw.viewCustomers ??
      raw.ViewCustomers ??
      raw.customers ??
      raw.Customers
  )
  if (customers !== undefined) normalized.canViewCustomers = customers

  const activityLog = toBoolean(raw.canViewActivityLog ?? raw.CanViewActivityLog ?? raw.viewActivityLog ?? raw.ViewActivityLog ?? raw.activityLog ?? raw.ActivityLog)
  if (activityLog !== undefined) normalized.canViewActivityLog = activityLog

  const settings = toBoolean(raw.canViewSettings ?? raw.CanViewSettings ?? raw.viewSettings ?? raw.ViewSettings ?? raw.settings ?? raw.Settings)
  if (settings !== undefined) normalized.canViewSettings = settings

  const viewFeedProd = toBoolean(raw.canViewFeedProduction ?? raw.CanViewFeedProduction ?? raw.viewFeedProduction ?? raw.ViewFeedProduction)
  if (viewFeedProd !== undefined) normalized.canViewFeedProduction = viewFeedProd

  const manageFeedProd = toBoolean(raw.canManageFeedProduction ?? raw.CanManageFeedProduction ?? raw.manageFeedProduction ?? raw.ManageFeedProduction)
  if (manageFeedProd !== undefined) normalized.canManageFeedProduction = manageFeedProd

  const feedProdCost = toBoolean(raw.canViewFeedProductionCost ?? raw.CanViewFeedProductionCost ?? raw.viewFeedProductionCost ?? raw.ViewFeedProductionCost)
  if (feedProdCost !== undefined) normalized.canViewFeedProductionCost = feedProdCost

  for (const key of WATER_STAFF_FEATURE_KEYS) {
    const pascal = key.charAt(0).toUpperCase() + key.slice(1)
    const value = toBoolean(raw[key] ?? raw[pascal])
    if (value !== undefined) normalized[key] = value
  }

  return normalized
}

/**
 * Has anyone ever set a water flag on this record?
 *
 * The water flags were added after the water module shipped, so every existing
 * employee's stored `FeaturePermissions` predates them. Staff are
 * deny-by-default, which would mean the day this deploys every water staff
 * member loses Production, Deliveries, Inventory, Maintenance, Payroll and
 * Setup at once — not because an admin decided that, but because the keys are
 * absent.
 *
 * So: a record with NO water flag at all is grandfathered (all six granted,
 * which is exactly today's behaviour — the water nav is ungated). The first
 * time an admin saves the access dialog every water key is written, and from
 * then on absence means denied like every other flag.
 */
function hasAnyWaterFlag(raw: Record<string, unknown>): boolean {
  return WATER_STAFF_FEATURE_KEYS.some((key) => {
    const pascal = key.charAt(0).toUpperCase() + key.slice(1)
    return toBoolean(raw[key] ?? raw[pascal]) !== undefined
  })
}

/** The legacy half, before IAM is layered on. Kept separate so state stays plain data. */
type BasePermissions = Omit<UserPermissions, "can" | "permissionKeys" | "isSuperuser">

export function usePermissions(): UserPermissions {
  const [iamGrants, setIamGrants] = useState<string[]>([])
  // Whether the API enforces permissions. Owned by the server (Iam:Enforced) so
  // the two sides cannot disagree about which era they are in; false until it
  // says otherwise, which is the permissive direction.
  const [iamEnforced, setIamEnforced] = useState(false)
  const [permissions, setPermissions] = useState<BasePermissions>({
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

  const computeFromStorage = useCallback((): BasePermissions => {
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
    // #D: a staff member can be explicitly flagged admin on their account
    // (AspNetUsers.IsAdmin); the login response carries it. Honor it so
    // staff-admins (e.g. Christy) get Delete and other admin-only actions.
    const isAdminFlag = localStorage.getItem("isAdmin") === "true"
    const isAdmin = isAdminFlag || hasAdminRole || isSubscriber || !isStaff
    const isStaffOnly = isStaff && !isAdmin

    let storedFeatureAccess: Partial<FeatureAccessPermissions> = {}
    // See hasAnyWaterFlag: an untouched record is grandfathered into the water
    // pages rather than locked out of them.
    let waterFlagsConfigured = false
    const featureAccessRaw = localStorage.getItem("featurePermissions")
    if (featureAccessRaw) {
      try {
        const parsed = JSON.parse(featureAccessRaw)
        if (parsed && typeof parsed === "object") {
          storedFeatureAccess = normalizeFeatureAccess(parsed as Record<string, unknown>)
          waterFlagsConfigured = hasAnyWaterFlag(parsed as Record<string, unknown>)
        }
      } catch (e) {
        console.error("[v0] Error parsing featurePermissions:", e)
        storedFeatureAccess = {}
      }
    }

    const featureBase = isStaffOnly ? STAFF_FEATURE_BASE : DEFAULT_FEATURE_ACCESS
    const waterGrandfather: Partial<FeatureAccessPermissions> =
      isStaffOnly && !waterFlagsConfigured
        ? (Object.fromEntries(WATER_STAFF_FEATURE_KEYS.map((k) => [k, true])) as Partial<FeatureAccessPermissions>)
        : {}
    const featureAccess: FeatureAccessPermissions = {
      ...featureBase,
      ...waterGrandfather,
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

    // IAM grants are scoped to the company you are in, so they have to be
    // re-read whenever that changes. Without this, someone who is an Accountant
    // in one company and Data Entry in another keeps the wider set until they
    // reload the page.
    const loadIam = async () => {
      if (!localStorage.getItem("auth_token")) return
      const farmId = localStorage.getItem("farmId")
      const [status, res] = await Promise.all([getIamStatus(), getEffectivePermissions(farmId)])
      if (cancelled) return
      setIamEnforced(status?.enforced === true)
      // null means the endpoint is unavailable or migration 199 has not been
      // applied here — fall back to legacy flags alone rather than to nothing.
      setIamGrants(res?.grants?.map((g) => g.permissionKey) ?? [])
    }
    void loadIam()

    const onCompanyChanged = () => {
      setIamGrants([])
      void loadIam()
    }
    window.addEventListener(COMPANY_CHANGED_EVENT, onCompanyChanged)

    return () => {
      cancelled = true
      window.removeEventListener(COMPANY_CHANGED_EVENT, onCompanyChanged)
    }
  }, [computeFromStorage])

  const resolved = useMemo(
    () =>
      resolveEffectivePermissions({
        legacy: permissions.featureAccess,
        isAdmin: permissions.isAdmin,
        iamAllow: iamGrants,
        authoritative: iamEnforced,
      }),
    [permissions.featureAccess, permissions.isAdmin, iamGrants, iamEnforced]
  )

  return {
    ...permissions,
    can: resolved.can,
    permissionKeys: resolved.keys,
    isSuperuser: resolved.isSuperuser,
  }
}

// Helper function to check if user has specific permission
export function hasPermission(permission: keyof UserPermissions, permissions: UserPermissions): boolean {
  return permissions[permission] === true
}

