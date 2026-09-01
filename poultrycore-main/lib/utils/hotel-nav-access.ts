import type { FeatureAccessPermissions } from "@/hooks/use-permissions"

const HOTEL_ROUTE_ACCESS: Record<string, (f: FeatureAccessPermissions, isAdmin: boolean) => boolean> = {
  // --- Rooms ---------------------------------------------------------------
  "/hotel-rooms":           (f) => f.canViewHotelRooms,
  "/hotel-housekeeping":    (f) => f.canViewHotelHousekeeping,
  "/hotel-room-service":    (f) => f.canViewHotelRooms,

  // --- Front Desk ----------------------------------------------------------
  "/hotel-bookings":        (f) => f.canViewHotelBookings,
  "/hotel-guests":          (f) => f.canViewHotelBookings,
  "/hotel-check-in":        (f) => f.canViewHotelBookings,
  "/hotel-check-out":       (f) => f.canViewHotelBookings,

  // --- Restaurant & Bar ----------------------------------------------------
  "/hotel-restaurant":      (f) => f.canViewHotelRestaurant,
  "/hotel-restaurant-tables": (f) => f.canViewHotelRestaurant,
  "/hotel-menu":            (f) => f.canViewHotelRestaurant,
  "/hotel-kitchen":         (f) => f.canViewHotelRestaurant,

  // --- Finance -------------------------------------------------------------
  "/hotel-billing":         (f) => f.canViewHotelBilling,
  "/hotel-invoices":        (f) => f.canViewHotelBilling,
  "/hotel-payments":        (f, isAdmin) => isAdmin || f.canViewFinancial || f.canViewHotelBilling,
  "/hotel-expenses":        (f) => f.canEnterExpenses,
  "/hotel-cash-accounts":   (f) => f.canViewCashLedger,
  "/hotel-daily-closing":   (f, isAdmin) => isAdmin || f.canViewFinancial || f.canViewCashLedger,
  "/hotel-night-audit":     (f, isAdmin) => isAdmin || f.canViewFinancial || f.canViewCashLedger,

  // --- People --------------------------------------------------------------
  "/hotel-staff":           (f, isAdmin) => isAdmin || f.canSeeEmployees,
  "/hotel-payroll":         (f) => f.canViewHotelPayroll,

  // --- Inventory & Maintenance ---------------------------------------------
  "/hotel-inventory":       (f) => f.canViewHotelInventory,
  "/hotel-maintenance":     (f) => f.canViewHotelMaintenance,

  // --- Reports / Setup -----------------------------------------------------
  "/hotel-reports":         (f) => f.canViewReports,
  "/hotel-setup":           (f) => f.canViewHotelSetup,
}

export function isHotelNavItemVisible(
  href: string,
  featureAccess: FeatureAccessPermissions,
  isAdmin: boolean,
): boolean {
  if (isAdmin) return true
  const rule = HOTEL_ROUTE_ACCESS[href]
  if (!rule) return true
  return rule(featureAccess, isAdmin)
}

export function isGatedHotelRoute(href: string): boolean {
  return href in HOTEL_ROUTE_ACCESS
}

export function filterHotelNavItems<T extends { href: string }>(
  items: T[],
  featureAccess: FeatureAccessPermissions,
  isAdmin: boolean,
): T[] {
  return items.filter((item) => isHotelNavItemVisible(item.href, featureAccess, isAdmin))
}
