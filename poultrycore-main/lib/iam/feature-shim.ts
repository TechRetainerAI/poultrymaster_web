// The old Staff Page Access flags, answered from IAM keys.
//
// About 65 places still read `featureAccess.canEnterSales` and friends. Once
// per-company page access is live (migrations 506/507) those flags are derived
// here from the keys the person holds in the ACTIVE company, so every old check
// agrees with the page editor without touching each call site at once.

import type { FeatureAccessPermissions } from "@/hooks/use-permissions"
import { moduleForCompanyType } from "@/lib/iam/page-catalog"

type Flag = keyof FeatureAccessPermissions

/** flag → the view key(s) that answer it; `{m}` is the active company's module. */
const FLAG_KEYS: Record<Flag, readonly string[]> = {
  canEnterSales: ["{m}.sales.view"],
  canEnterExpenses: ["{m}.expenses.view"],
  canViewCashLedger: ["{m}.cash.view"],
  canSeeEmployees: ["office.employees.view"],
  canViewReports: ["{m}.reports.view"],
  canViewFinancial: ["{m}.profit-loss.view"],
  canViewCustomers: ["{m}.customers.view"],
  canViewActivityLog: ["office.audit-log.view"],
  canViewSettings: ["{m}.setup.view"],
  canViewFeedProduction: ["poultry.feed-production.view"],
  canManageFeedProduction: ["poultry.feed-production.create"],
  canViewFeedProductionCost: ["poultry.feed-production-cost.view"],
  canViewWaterProduction: ["water.production-batches.view"],
  canViewWaterDeliveries: ["water.driver-returns.view"],
  canViewWaterInventory: ["water.inventory.view"],
  canViewInternalUse: ["{m}.internal-use.view"],
  canViewWaterMaintenance: ["water.maintenance.view"],
  canViewWaterPayroll: ["water.payroll.view"],
  canViewWaterSetup: ["water.setup.view"],
  canViewHotelRooms: ["hotel.rooms.view"],
  canViewHotelBookings: ["hotel.bookings.view"],
  canViewHotelHousekeeping: ["hotel.housekeeping.view"],
  canViewHotelBilling: ["hotel.billing.view"],
  canViewHotelRestaurant: ["hotel.restaurant.view"],
  canViewHotelStaff: ["hotel.staff.view"],
  canViewHotelPayroll: ["hotel.payroll.view"],
  canViewHotelInventory: ["hotel.inventory.view"],
  canViewHotelMaintenance: ["hotel.maintenance.view"],
  canViewHotelSetup: ["hotel.setup.view"],
  canViewRestaurantPOS: ["restaurant.pos.view"],
  canViewRestaurantKDS: ["restaurant.kitchen.view"],
  canViewRestaurantMenu: ["restaurant.menu.view"],
  canViewRestaurantFloorPlan: ["restaurant.floor-plan.view"],
  canViewRestaurantReservations: ["restaurant.reservations.view"],
  canViewRestaurantOnlineOrders: ["restaurant.online-orders.view"],
  canViewRestaurantDelivery: ["restaurant.delivery.view"],
  canViewRestaurantStaff: ["restaurant.staff.view"],
  canViewRestaurantSetup: ["restaurant.setup.view"],
}

export function featureAccessFromKeys(
  can: (key: string) => boolean,
  companyType: string | null | undefined,
): FeatureAccessPermissions {
  const m = moduleForCompanyType(companyType) ?? "poultry"
  const out = {} as Record<Flag, boolean>
  for (const [flag, keys] of Object.entries(FLAG_KEYS) as [Flag, readonly string[]][]) {
    out[flag] = keys.some((k) => can(k.replace("{m}", m)))
  }
  return out as FeatureAccessPermissions
}
