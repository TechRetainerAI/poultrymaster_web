// Shared employee permission constants used by the Add-Employee dialog
// (components/employees/add-employee-dialog.tsx) and the /employees page's
// edit flow. Keep a single source so the admin/staff option lists stay in sync.

export type AdminPermissionKey =
  | "changeGroupInfo"
  | "deleteMessages"
  | "banUsers"
  | "inviteUsers"
  | "pinMessages"
  | "manageStories"
  | "manageVideoChats"
  | "remainAnonymous"
  | "addNewAdmins"

export const DEFAULT_ADMIN_PERMISSIONS: Record<AdminPermissionKey, boolean> = {
  changeGroupInfo: true,
  deleteMessages: true,
  banUsers: true,
  inviteUsers: true,
  pinMessages: true,
  manageStories: false,
  manageVideoChats: true,
  remainAnonymous: false,
  addNewAdmins: false,
}

export const ADMIN_PERMISSION_OPTIONS: Array<{ key: AdminPermissionKey; label: string; hint?: string }> = [
  { key: "changeGroupInfo", label: "Change group info" },
  { key: "deleteMessages", label: "Delete messages" },
  { key: "banUsers", label: "Ban users" },
  { key: "inviteUsers", label: "Invite users via link" },
  { key: "pinMessages", label: "Pin messages" },
  { key: "manageStories", label: "Manage stories", hint: "0/3 by default" },
  { key: "manageVideoChats", label: "Manage video chats" },
  { key: "remainAnonymous", label: "Remain anonymous" },
  { key: "addNewAdmins", label: "Add new admins" },
]

export type StaffFeaturePermissionKey =
  | "canEnterSales"
  | "canEnterExpenses"
  | "canViewCashLedger"
  | "canSeeEmployees"
  | "canViewReports"
  | "canViewFinancial"
  | "canViewCustomers"
  | "canViewActivityLog"
  | "canViewSettings"
  | "canViewFeedProduction"
  | "canManageFeedProduction"
  | "canViewFeedProductionCost"
  | "canViewWaterProduction"
  | "canViewWaterDeliveries"
  | "canViewWaterInventory"
  | "canViewWaterMaintenance"
  | "canViewWaterPayroll"
  | "canViewWaterSetup"

export const DEFAULT_STAFF_FEATURE_PERMISSIONS: Record<StaffFeaturePermissionKey, boolean> = {
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
  canViewWaterMaintenance: true,
  canViewWaterPayroll: true,
  canViewWaterSetup: true,
}

/**
 * Which company type a toggle belongs to.
 *
 * `core` flags are company-neutral — sales, expenses, cash and the rest exist in
 * every module, and the same flag gates the poultry, water and generic version
 * of that page. `poultry` and `water` flags gate module-specific pages and are
 * only worth showing to someone administering a company of that type.
 */
export type StaffPermissionModule = "core" | "poultry" | "water"

export const STAFF_FEATURE_PERMISSION_OPTIONS: Array<{
  key: StaffFeaturePermissionKey
  label: string
  module: StaffPermissionModule
  hint?: string
}> = [
  { key: "canEnterSales", label: "Enter Sales", module: "core" },
  { key: "canEnterExpenses", label: "Enter Expenses", module: "core" },
  { key: "canViewCashLedger", label: "View Cash Ledger", module: "core" },
  { key: "canSeeEmployees", label: "See Employees", module: "core" },
  { key: "canViewReports", label: "View reports", module: "core" },
  { key: "canViewFinancial", label: "View Financial (Cash, Payments umbrella)", module: "core" },
  { key: "canViewCustomers", label: "View Customers", module: "core" },
  { key: "canViewActivityLog", label: "View Activity Log", module: "core" },
  { key: "canViewSettings", label: "View Settings", module: "core" },
  { key: "canViewFeedProduction", label: "View Feed Production", module: "poultry" },
  { key: "canManageFeedProduction", label: "Manage Feed Production (produce, post, reverse)", module: "poultry" },
  { key: "canViewFeedProductionCost", label: "View Feed Production Costs", module: "poultry" },
  // Water — one toggle per sidebar group, matching how the water nav is laid
  // out so an admin can reason about it by looking at the menu.
  {
    key: "canViewWaterProduction",
    label: "View Water Production",
    module: "water",
    hint: "Production, Batch Production, Products, Machines, Boreholes",
  },
  {
    key: "canViewWaterDeliveries",
    label: "View Deliveries",
    module: "water",
    hint: "Driver returns, Drivers, Vehicles, Routes, Driver collection report",
  },
  {
    key: "canViewWaterInventory",
    label: "View Water Inventory",
    module: "water",
    hint: "Stock movement, Inventory, Raw materials, Damages & loss, Production losses",
  },
  { key: "canViewWaterMaintenance", label: "View Maintenance", module: "water" },
  { key: "canViewWaterPayroll", label: "View Water Payroll", module: "water" },
  {
    key: "canViewWaterSetup",
    label: "View Water Setup",
    module: "water",
    hint: "Setup and Company Setup",
  },
]

/** The water flags, for the grandfathering rule in hooks/use-permissions.ts. */
export const WATER_STAFF_FEATURE_KEYS = STAFF_FEATURE_PERMISSION_OPTIONS
  .filter((o) => o.module === "water")
  .map((o) => o.key)

/** The module a company type contributes. Generic contributes nothing beyond core. */
function moduleForType(companyType: string | null | undefined): StaffPermissionModule | null {
  switch ((companyType ?? "").toLowerCase()) {
    case "water": return "water"
    case "poultry": return "poultry"
    default: return null
  }
}

/**
 * The toggles worth showing for someone whose company access spans
 * `companyTypes`.
 *
 * Water-only access shows the core + water switches; poultry-only shows core +
 * poultry; someone in BOTH a water and a poultry company sees everything,
 * because both halves genuinely apply to them. Generic-only leaves just the
 * core switches — the generic module has no pages of its own to gate.
 *
 * Everything is still STORED — the snapshot the dialogs save carries every key
 * regardless of what is on screen, so tightening a water user's access can
 * never wipe the poultry flags of someone who has both. This only decides what
 * is rendered.
 *
 * An empty or unrecognised list falls back to the full set: better to show a
 * toggle that doesn't apply than to silently hide one that does.
 */
export function staffPermissionOptionsForCompanyTypes(companyTypes: Array<string | null | undefined>) {
  const modules = new Set(companyTypes.map(moduleForType).filter(Boolean) as StaffPermissionModule[])

  // Nothing recognisable to narrow by — e.g. an employee with no company
  // assigned yet, or a generic-only one. Generic-only is the case worth
  // distinguishing: it IS a known answer (core only), not a missing one.
  if (modules.size === 0) {
    const sawGeneric = companyTypes.some((t) => (t ?? "").toLowerCase() === "generic")
    return sawGeneric
      ? STAFF_FEATURE_PERMISSION_OPTIONS.filter((o) => o.module === "core")
      : STAFF_FEATURE_PERMISSION_OPTIONS
  }

  return STAFF_FEATURE_PERMISSION_OPTIONS.filter((o) => o.module === "core" || modules.has(o.module))
}

/** Single-company convenience wrapper — the same rule for one type. */
export function staffPermissionOptionsForCompanyType(companyType: string | null | undefined) {
  return staffPermissionOptionsForCompanyTypes([companyType])
}
