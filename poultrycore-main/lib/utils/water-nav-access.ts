// =============================================================================
// Per-route visibility for the Water company's nav.
//
// The water module shipped with no gating at all: lib/utils/financial-nav-access
// only ever knew about the poultry routes (/sales, /cash, /poultry-*), so every
// Staff Page Access toggle was a no-op once you switched into a water company
// and staff saw the whole rail. This is that file's water half.
//
// Grouping matches the sidebar (components/dashboard/sidebar.tsx) one-for-one,
// which is also how the toggles are labelled — an admin should be able to read
// the menu and know which switch hides what.
//
// The shared "core" flags keep gating their water equivalents (a person who can
// enter sales can enter water sales), so this only introduces new flags where
// the water module has pages poultry has no counterpart for.
// =============================================================================

import type { FeatureAccessPermissions } from "@/hooks/use-permissions"

/** Every `/water-*` route that this file makes a decision about. */
const WATER_ROUTE_ACCESS: Record<string, (f: FeatureAccessPermissions, isAdmin: boolean) => boolean> = {
  // --- Production ----------------------------------------------------------
  "/water-production-batches": (f) => f.canViewWaterProduction,
  "/water-daily-production": (f) => f.canViewWaterProduction,
  "/water-products": (f) => f.canViewWaterProduction,
  "/water-machines": (f) => f.canViewWaterProduction,
  "/water-boreholes": (f) => f.canViewWaterProduction,
  "/water-maintenance": (f) => f.canViewWaterMaintenance,

  // --- Delivery ------------------------------------------------------------
  "/water-driver-returns": (f) => f.canViewWaterDeliveries,
  "/water-drivers": (f) => f.canViewWaterDeliveries,
  "/water-vehicles": (f) => f.canViewWaterDeliveries,
  "/water-routes": (f) => f.canViewWaterDeliveries,
  // A report, but it belongs to the delivery flow and is reached from the
  // Delivery menu — gate it on either.
  "/water-driver-report": (f) => f.canViewWaterDeliveries || f.canViewReports,

  // --- Inventory -----------------------------------------------------------
  "/water-stock": (f) => f.canViewWaterInventory,
  "/water-inventory": (f) => f.canViewWaterInventory,
  "/water-raw-materials": (f) => f.canViewWaterInventory,
  "/water-loss-records": (f) => f.canViewWaterInventory,
  "/water-internal-use": (f) => f.canViewInternalUse,
  // Losses recorded against a production run: either lens should reach it.
  "/water-production-losses": (f) => f.canViewWaterInventory || f.canViewWaterProduction,

  // --- Analytics -----------------------------------------------------------
  // Inventory Tracker is an inventory lens rendered as an analytic, so either
  // flag reaches it — same reasoning as /water-driver-report above, which is a
  // report that belongs to the delivery flow.
  "/water-inventory-tracker": (f) => f.canViewWaterInventory || f.canViewReports,

  // --- Sales & money -------------------------------------------------------
  // Same predicates the poultry rail uses for its equivalents, so a staff
  // member's access doesn't change shape when they switch company.
  "/water-sales": (f) => f.canEnterSales,
  "/water-expenses": (f) => f.canEnterExpenses,
  "/water-cash-accounts": (f) => f.canViewCashLedger,
  // Counting cash is a cash-ledger job; it rides the same flag rather than
  // introducing a permission nobody has been granted yet.
  "/water-cash-reconciliation": (f) => f.canViewCashLedger,
  "/water-payments": (f, isAdmin) => isAdmin || f.canViewFinancial || f.canEnterSales,
  "/water-daily-closing": (f, isAdmin) => isAdmin || f.canViewFinancial || f.canViewCashLedger,

  // --- Finance (master data) ----------------------------------------------
  "/water-customers": (f, isAdmin) => isAdmin || f.canViewCustomers || f.canViewFinancial || f.canEnterSales,
  "/water-suppliers": (f, isAdmin) => isAdmin || f.canViewCustomers || f.canViewFinancial || f.canEnterSales,

  // --- People --------------------------------------------------------------
  "/water-staff": (f, isAdmin) => isAdmin || f.canSeeEmployees,
  "/water-payroll": (f) => f.canViewWaterPayroll,

  // --- Reports / Setup -----------------------------------------------------
  "/water-reports": (f) => f.canViewReports,
  "/water-setup": (f) => f.canViewWaterSetup,
  "/water-company-setup": (f) => f.canViewWaterSetup,
}

/**
 * Can this user see `href`?
 *
 * Admins pass everything — matching how the rest of the app treats them, and
 * matching DEFAULT_FEATURE_ACCESS being default-allow for non-staff.
 *
 * A route with no entry (the dashboard, and anything added later that nobody
 * has classified yet) is visible. Failing open is deliberate: a new water page
 * appearing for everyone is a smaller problem than one silently vanishing.
 */
export function isWaterNavItemVisible(
  href: string,
  featureAccess: FeatureAccessPermissions,
  isAdmin: boolean,
): boolean {
  if (isAdmin) return true
  const rule = WATER_ROUTE_ACCESS[href]
  if (!rule) return true
  return rule(featureAccess, isAdmin)
}

/** True when this file has an opinion about `href` — i.e. it is a gated water route. */
export function isGatedWaterRoute(href: string): boolean {
  return href in WATER_ROUTE_ACCESS
}

/** Filter a nav item list in place of a per-item `visible` flag. */
export function filterWaterNavItems<T extends { href: string }>(
  items: T[],
  featureAccess: FeatureAccessPermissions,
  isAdmin: boolean,
): T[] {
  return items.filter((item) => isWaterNavItemVisible(item.href, featureAccess, isAdmin))
}
