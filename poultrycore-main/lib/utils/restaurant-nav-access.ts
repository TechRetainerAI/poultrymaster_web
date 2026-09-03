import type { FeatureAccessPermissions } from "@/hooks/use-permissions"

const RESTAURANT_ROUTE_ACCESS: Record<string, (f: FeatureAccessPermissions, isAdmin: boolean) => boolean> = {
  // --- POS & Orders --------------------------------------------------------
  "/restaurant-pos":              (f) => f.canViewRestaurantPOS,
  "/restaurant-orders":           (f) => f.canViewRestaurantPOS,

  // --- Kitchen -------------------------------------------------------------
  "/restaurant-kds":              (f) => f.canViewRestaurantKDS,

  // --- Menu ----------------------------------------------------------------
  "/restaurant-menu":             (f) => f.canViewRestaurantMenu,

  // --- Floor Plan & Tables -------------------------------------------------
  "/restaurant-floor-plan":       (f) => f.canViewRestaurantFloorPlan,

  // --- Reservations & Waitlist ---------------------------------------------
  "/restaurant-reservations":     (f) => f.canViewRestaurantReservations,

  // --- Online Ordering -----------------------------------------------------
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
