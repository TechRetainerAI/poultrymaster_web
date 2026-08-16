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
