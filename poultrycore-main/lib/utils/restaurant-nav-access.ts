import type { FeatureAccessPermissions } from "@/hooks/use-permissions"

const RESTAURANT_ROUTE_ACCESS: Record<string, (f: FeatureAccessPermissions, isAdmin: boolean) => boolean> = {
  // --- POS & Orders --------------------------------------------------------
  "/restaurant-pos":              (f) => f.canViewRestaurantPOS,
  "/restaurant-orders":           (f) => f.canViewRestaurantPOS,
  // Accepting a guest order puts it in the kitchen and takes a table, so it
  // belongs with the POS permission rather than the read-only online settings.
  "/restaurant-pending-orders":   (f) => f.canViewRestaurantPOS,

  // --- Kitchen -------------------------------------------------------------
  "/restaurant-kds":              (f) => f.canViewRestaurantKDS,

  // --- Menu ----------------------------------------------------------------
  "/restaurant-menu":             (f) => f.canViewRestaurantMenu,

  // --- Floor Plan & Tables -------------------------------------------------
  "/restaurant-floor-plan":       (f) => f.canViewRestaurantFloorPlan,

  // --- Reservations & Waitlist ---------------------------------------------
  "/restaurant-reservations":     (f) => f.canViewRestaurantReservations,

  // --- Online Ordering -----------------------------------------------------
  "/restaurant-qr-print":         (f) => f.canViewRestaurantOnlineOrders,
  "/restaurant-online-orders":    (f) => f.canViewRestaurantOnlineOrders,
  "/restaurant-order-online":     () => true, // public page

  // --- Delivery Management -------------------------------------------------
  "/restaurant-delivery":         (f) => f.canViewRestaurantDelivery,

  // --- Staff ---------------------------------------------------------------
  "/restaurant-staff":            (f, isAdmin) => isAdmin || f.canViewRestaurantStaff,

  // --- Setup ---------------------------------------------------------------
  "/restaurant-setup":            (f, isAdmin) => isAdmin || f.canViewRestaurantSetup,

  // --- Dashboard -----------------------------------------------------------
  "/restaurant-dashboard":        () => true,

  // --- Reports -------------------------------------------------------------
  // Reports expose revenue, margins, profit and per-waiter performance, so they
  // follow the generic reporting flag rather than defaulting to visible.
  //
  // This entry is the fix for a real hole: unknown routes fall through to
  // `true` below, and /restaurant-reports was never listed — so every waiter,
  // driver and kitchen user could open the takings. The report pages check the
  // same flag themselves, because hiding a nav row does not stop anyone typing
  // the URL.
  "/restaurant-reports":          (f) => f.canViewReports,

  // --- Money (migration 323) -----------------------------------------------
  // These were missing, so they fell through to `true` below and every staff
  // member saw the takings. Tills are the cashier's screen, so the POS flag
  // opens them; everything else is the cash ledger. The pages check the same
  // flags themselves — hiding a nav row does not stop someone typing the URL.
  "/restaurant-tills":            (f) => f.canViewRestaurantPOS || f.canViewCashLedger,
  "/restaurant-cash-accounts":    (f) => f.canViewCashLedger,
  "/restaurant-cash-transfers":   (f) => f.canViewCashLedger,
  "/restaurant-cash-reconciliation": (f) => f.canViewCashLedger,
  "/restaurant-owner-money":      (f) => f.canViewCashLedger,
  "/restaurant-loans":            (f) => f.canViewCashLedger,
  "/restaurant-daily-closing":    (f) => f.canViewCashLedger,
  "/restaurant-cash-flow":        (f) => f.canViewCashLedger,
  "/restaurant-profit-loss":      (f) => f.canViewCashLedger,
  "/restaurant-payments":         (f) => f.canViewCashLedger,
  // Migration 326: payroll and money lent to staff ride on the "Staff & payroll"
  // flag. Without a rule here an unlisted route falls through to visible.
  "/restaurant-payroll":          (f) => f.canViewRestaurantStaff,
  "/restaurant-staff-loans":      (f) => f.canViewRestaurantStaff,
  // /restaurant-expenses is deliberately NOT listed: staff record expenses
  // there today, and gating it was not part of this change.
}

/**
 * Returns true if the given route should be visible to this user.
 * Unknown routes default to true (admin-only pages should use isAdmin directly).
 */
export function isRestaurantNavItemVisible(
  href: string,
  featureAccess: FeatureAccessPermissions,
  isAdmin: boolean,
): boolean {
  if (isAdmin) return true
  const check = RESTAURANT_ROUTE_ACCESS[href]
  return check ? check(featureAccess, isAdmin) : true
}

/**
 * Filter nav items based on restaurant permissions.
 * Same pattern as filterHotelNavItems / filterWaterNavItems.
 */
export function filterRestaurantNavItems<T extends { href: string }>(
  items: T[],
  featureAccess: FeatureAccessPermissions,
  isAdmin: boolean,
): T[] {
  return items.filter((item) => isRestaurantNavItemVisible(item.href, featureAccess, isAdmin))
}
