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
  "/hotel-payments":        (f, isAdmin) => isAdmin || f.canViewFinancial || f.canEnterSales || f.canViewHotelBilling,
  // Migration 332, Poultry's rules (financial-nav-access.ts): Sales rides
  // canEnterSales (plus the hotel's billing desk flag, which reached the old
  // Sales row); the balances pages are read generously, as Poultry's are.
  "/hotel-sales":             (f) => f.canEnterSales || f.canViewHotelBilling,
  "/hotel-customer-balances": (f, isAdmin) => isAdmin || f.canViewFinancial || f.canEnterSales || f.canViewCustomers || f.canViewHotelBilling,
  // Migration 334: Internal Use rides the Supplies gate; Deferred inventory cost
  // is read by whoever enters expenses or sees the financials.
  "/hotel-internal-use":      (f) => f.canViewHotelInventory === true,
  "/hotel-deferred-costs":    (f, isAdmin) => isAdmin || f.canEnterExpenses || f.canViewFinancial,
  "/hotel-supplier-balances": (f, isAdmin) => isAdmin || f.canViewFinancial || f.canEnterExpenses || f.canViewCustomers,
  "/hotel-expenses":        (f) => f.canEnterExpenses,
  "/hotel-cash-accounts":   (f) => f.canViewCashLedger,
  // Migration 331. Poultry's rule for its four pages (financial-nav-access.ts):
  // owner money, loans, transfers and reconciliation all ride canViewCashLedger.
  "/hotel-owner-money":         (f) => f.canViewCashLedger,
  "/hotel-loans":               (f) => f.canViewCashLedger,
  "/hotel-cash-transfers":      (f) => f.canViewCashLedger,
  "/hotel-cash-reconciliation": (f) => f.canViewCashLedger,
  // These seven had no rule, so the top nav borrowed another page's rule for
  // them while the sidebar -- which filters by each row's own href -- fell
  // through to `return true` and showed them to every staff member. Each now
  // has the exact rule the top nav was already borrowing, so the top nav's
  // answer does not change and the sidebar and mobile nav now agree with it.
  "/hotel-cash-flow":         (f) => f.canViewCashLedger,
  // Migration 336: Poultry gates Financial Activity with the cash ledger flag.
  "/hotel-financial-activity": (f) => f.canViewCashLedger === true,
  "/hotel-profit-loss":       (f) => f.canEnterExpenses,
  "/hotel-customers":         (f) => f.canViewHotelBilling,
  "/hotel-customer-payments": (f) => f.canViewHotelBilling,
  "/hotel-suppliers":         (f) => f.canEnterExpenses,
  "/hotel-supplier-payments": (f, isAdmin) => isAdmin || f.canViewFinancial || f.canEnterExpenses || f.canViewCustomers,
  "/hotel-assets":            (f) => f.canEnterExpenses,
  "/hotel-daily-closing":   (f, isAdmin) => isAdmin || f.canViewFinancial || f.canViewCashLedger,
  "/hotel-night-audit":     (f, isAdmin) => isAdmin || f.canViewFinancial || f.canViewCashLedger,

  // --- People --------------------------------------------------------------
  "/hotel-staff":           (f, isAdmin) => isAdmin || f.canSeeEmployees,
  "/hotel-payroll":         (f) => f.canViewHotelPayroll,
  // Staff loans ride on payroll: the same people set the deductions. Without a
  // rule here the sidebar showed the page to every staff member.
  "/hotel-employee-loans":  (f) => f.canViewHotelPayroll,

  // --- Inventory & Maintenance ---------------------------------------------
  "/hotel-inventory":       (f) => f.canViewHotelInventory,
  "/hotel-maintenance":     (f) => f.canViewHotelMaintenance,

  // --- Reports / Setup -----------------------------------------------------
  "/hotel-reports":         (f) => f.canViewReports,
  "/hotel-setup":           (f) => f.canViewHotelSetup,
  "/hotel-company-setup":   (f) => f.canViewHotelSetup,
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
