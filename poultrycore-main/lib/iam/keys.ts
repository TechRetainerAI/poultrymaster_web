// IAM permission keys — the bridge between the legacy feature flags and the
// catalog seeded by migration 199.
//
// The catalog itself is NOT duplicated here. Labels, grouping and the full key
// list are read from GET /Iam/catalog, so there is only ever one copy and a
// module added by a migration shows up in the UI without a frontend change.
// What does live here is the mapping from the twelve legacy booleans on
// AspNetUsers.FeaturePermissions onto catalog keys — that mapping is fixed,
// small, and load-bearing: while IAM is additive it is what answers `can()`
// for the users who have no roles assigned yet, which on day one is everyone.

import type { StaffFeaturePermissionKey } from "@/lib/employees/permissions"

/** `module.resource.action`, e.g. `poultry.sales.create`. */
export type PermissionKey = string

/** The three company-type modules. `office` is company-neutral and handled separately. */
export const COMMERCIAL_MODULES = ["poultry", "water", "generic"] as const
export type CommercialModule = (typeof COMMERCIAL_MODULES)[number]

/** Company type as stored on the auth store / `localStorage.farmType`. */
export type IamCompanyType = "Poultry" | "Water" | "Generic"

const MODULE_BY_COMPANY_TYPE: Record<IamCompanyType, CommercialModule> = {
  Poultry: "poultry",
  Water: "water",
  Generic: "generic",
}

export function moduleForCompanyType(type: string | null | undefined): CommercialModule | null {
  if (!type) return null
  return MODULE_BY_COMPANY_TYPE[type as IamCompanyType] ?? null
}

/**
 * Expand `resource` + actions into keys for every commercial module.
 * The legacy flags are org-wide and type-agnostic, so a person who could enter
 * sales could do it in whichever company they were in — the mapping has to
 * preserve that or switching company would silently drop access.
 */
function everyModule(resource: string, actions: string[]): PermissionKey[] {
  return COMMERCIAL_MODULES.flatMap((m) => actions.map((a) => `${m}.${resource}.${a}`))
}

/**
 * Legacy flag → the catalog keys it stands for.
 *
 * Read generously on purpose. Under the additive rule IAM can only widen
 * access, so an over-broad mapping preserves today's behaviour; an under-broad
 * one would take something away the moment a page moves to `can()`.
 */
export const LEGACY_PERMISSION_MAP: Record<StaffFeaturePermissionKey, PermissionKey[]> = {
  canEnterSales: everyModule("sales", ["view", "create", "edit", "export"]),

  canEnterExpenses: everyModule("expenses", ["view", "create", "edit", "export"]),

  canViewCashLedger: [
    ...everyModule("cash", ["view", "export"]),
    "generic.cash-transfers.view",
  ],

  canSeeEmployees: [...everyModule("staff", ["view"]), "office.employees.view"],

  canViewReports: everyModule("reports", ["view", "export"]),

  // The old umbrella flag. It gated cash, payments, closing and customers as one
  // switch, so it has to grant all four.
  canViewFinancial: [
    ...everyModule("cash", ["view", "export"]),
    ...everyModule("payments", ["view"]),
    ...everyModule("daily-closing", ["view"]),
    ...everyModule("customers", ["view"]),
    "generic.supplier-payments.view",
    "generic.cash-transfers.view",
  ],

  canViewCustomers: everyModule("customers", ["view", "export"]),

  canViewActivityLog: ["office.audit-log.view", "office.audit-log.export"],

  canViewSettings: ["office.settings.view"],

  canViewFeedProduction: ["poultry.feed-production.view", "poultry.feed-formulas.view"],

  canManageFeedProduction: [
    "poultry.feed-production.create",
    "poultry.feed-production.edit",
    "poultry.feed-production.delete",
    "poultry.feed-production.approve",
    "poultry.feed-formulas.create",
    "poultry.feed-formulas.edit",
    "poultry.feed-formulas.delete",
  ],

  canViewFeedProductionCost: ["poultry.feed-production-cost.view"],

  // Water — the module-specific half, mirroring the sidebar groups these flags
  // gate (lib/utils/water-nav-access). Read generously like the rest of this
  // map: a "view the group" flag maps onto the full CRUD set for its resources,
  // because that is exactly what the flag lets you do today. Narrowing happens
  // when someone is given a real IAM role, not here.
  canViewWaterProduction: [
    "water.daily-production.view", "water.daily-production.create",
    "water.daily-production.edit", "water.daily-production.delete", "water.daily-production.export",
    "water.production-batches.view", "water.production-batches.create",
    "water.production-batches.edit", "water.production-batches.delete", "water.production-batches.approve",
    "water.products.view", "water.products.create", "water.products.edit", "water.products.delete",
    "water.machines.view", "water.machines.create", "water.machines.edit", "water.machines.delete",
    "water.boreholes.view", "water.boreholes.create", "water.boreholes.edit", "water.boreholes.delete",
    "water.production-losses.view", "water.production-losses.create",
    "water.production-losses.edit", "water.production-losses.delete",
  ],

  canViewWaterDeliveries: [
    "water.drivers.view", "water.drivers.create", "water.drivers.edit", "water.drivers.delete",
    "water.vehicles.view", "water.vehicles.create", "water.vehicles.edit", "water.vehicles.delete",
    "water.routes.view", "water.routes.create", "water.routes.edit", "water.routes.delete",
    "water.driver-returns.view", "water.driver-returns.create",
    "water.driver-returns.edit", "water.driver-returns.delete", "water.driver-returns.approve",
  ],

  canViewWaterInventory: [
    "water.raw-materials.view", "water.raw-materials.create",
    "water.raw-materials.edit", "water.raw-materials.delete",
    "water.inventory.view", "water.inventory.create", "water.inventory.edit", "water.inventory.delete",
    "water.stock.view", "water.stock.edit", "water.stock.export",
    "water.production-losses.view", "water.production-losses.create",
    "water.production-losses.edit", "water.production-losses.delete",
  ],

  canViewWaterMaintenance: [
    "water.maintenance.view", "water.maintenance.create",
    "water.maintenance.edit", "water.maintenance.delete", "water.maintenance.approve",
  ],

  canViewWaterPayroll: [
    "water.payroll.view", "water.payroll.create",
    "water.payroll.edit", "water.payroll.delete", "water.payroll.approve", "water.payroll.export",
  ],

  // No `water.settings.*` in the catalog — company configuration is the
  // company-neutral office module, same key the poultry Settings flag uses.
  canViewWaterSetup: ["office.settings.view"],
}

/** Every key the legacy flags can produce, for the "is this key legacy-covered?" check. */
export function legacyToPermissionKeys(
  flags: Partial<Record<StaffFeaturePermissionKey, boolean>>
): Set<PermissionKey> {
  const keys = new Set<PermissionKey>()
  for (const [flag, granted] of Object.entries(flags)) {
    if (!granted) continue
    for (const key of LEGACY_PERMISSION_MAP[flag as StaffFeaturePermissionKey] ?? []) {
      keys.add(key)
    }
  }
  return keys
}
