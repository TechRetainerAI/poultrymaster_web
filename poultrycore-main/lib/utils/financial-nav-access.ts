import type { FeatureAccessPermissions } from "@/hooks/use-permissions"

/**
 * Per-route visibility for Financial nav items.
 * Staff no longer need blanket "View Financial" to see Sales or Customers-only access.
 */
export function isFinancialNavItemVisible(
  href: string,
  featureAccess: FeatureAccessPermissions,
  isAdmin: boolean,
  options?: { tempShowPayments?: boolean }
): boolean {
  const f = featureAccess
  if (href === "/sales") return f.canEnterSales
  if (href === "/expenses") return f.canEnterExpenses
  if (href === "/cash") return f.canViewCashLedger
  if (href === "/poultry-cash-accounts") return f.canViewCashLedger
  if (href === "/poultry-payments") return isAdmin || f.canViewFinancial || f.canEnterSales
  if (href === "/customers") {
    return (
      isAdmin ||
      f.canViewCustomers ||
      f.canViewFinancial ||
      f.canEnterSales
    )
  }
  if (href === "/suppliers") {
    return (
      isAdmin ||
      f.canViewCustomers ||
      f.canViewFinancial ||
      f.canEnterSales
    )
  }
  if (href === "/billing") {
    return options?.tempShowPayments === true || isAdmin || f.canViewFinancial
  }
  return false
}

export function canAccessCustomersPage(
  featureAccess: FeatureAccessPermissions,
  isAdmin: boolean
): boolean {
  return isFinancialNavItemVisible("/customers", featureAccess, isAdmin)
}

export function canAccessSuppliersPage(
  featureAccess: FeatureAccessPermissions,
  isAdmin: boolean
): boolean {
  return isFinancialNavItemVisible("/suppliers", featureAccess, isAdmin)
}
