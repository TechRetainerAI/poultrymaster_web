// =============================================================================
// Setup (company master data) is for the account owner and employees granted
// admin -- not ordinary employees, who could otherwise add drivers, routes and
// products, rename the company or change its financial settings.
//
// This list is the one place that says which pages that covers. It drives:
//   - SetupAccessGuard (app/layout.tsx): an ordinary employee who opens one of
//     these by URL is sent to their dashboard;
//   - the Setup menus (each company type's nav config / access map);
//   - and mirrors the Farm API's [SetupAdminOnly] controllers, which refuse the
//     writes themselves -- hiding a page is not access control.
//
// Deliberately NOT here, because they are daily work: flocks, stock movements,
// raw-material items (created while purchasing), hotel rooms / maintenance /
// supplies, Staff and Users & Permissions (they keep their own gates).
// Customers and suppliers ARE here: managing the list is admin work, though
// anyone may still add one from inside a sale or purchase.
// =============================================================================

export const SETUP_ADMIN_ROUTES: readonly string[] = [
  // Poultry
  "/poultry-setup", "/poultry-company-setup", "/poultry-financial-settings", "/poultry-farm-setup",
  "/poultry-drivers", "/poultry-vehicles", "/poultry-routes",
  "/poultry-products", "/poultry-feed-formulas", "/poultry-egg-sorting-settings", "/business-office/egg-pick-settings",
  "/customers", "/suppliers", "/houses",
  // Water
  "/water-setup", "/water-company-setup", "/water-financial-settings",
  "/water-drivers", "/water-vehicles", "/water-routes",
  "/water-products", "/water-machines", "/water-boreholes",
  "/water-customers", "/water-suppliers",
  // Generic
  "/generic-setup", "/generic-settings",
  // Hotel
  "/hotel-company-setup", "/hotel-setup", "/hotel-customers", "/hotel-suppliers",
  // Restaurant
  "/restaurant-setup", "/restaurant-menu", "/restaurant-suppliers",
]

/** True for a Setup page or anything under it (/water-products/12, /generic-setup/wizard). */
export function isSetupAdminRoute(pathname: string | null | undefined): boolean {
  if (!pathname) return false
  return SETUP_ADMIN_ROUTES.some((r) => pathname === r || pathname.startsWith(r + "/"))
}
