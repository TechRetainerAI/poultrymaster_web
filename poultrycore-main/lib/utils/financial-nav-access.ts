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
  // Company-wide money movement. Rides canViewCashLedger rather than a new flag:
  // staff are deny-by-default, so a fresh permission would quietly remove this
  // page from everyone who can see it today until an admin re-granted it. Same
  // reasoning as cash-reconciliation below.
  if (href === "/cash-flow") return f.canViewCashLedger
  if (href === "/poultry-cash-accounts") return f.canViewCashLedger
  // Counting cash is a cash-ledger job; it rides the same flag rather than
  // introducing a permission nobody has been granted yet.
  if (href === "/poultry-cash-reconciliation") return f.canViewCashLedger
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
  // Customer Balances / Supplier Balances. Read generously, matching the pages
  // they summarise: anyone who can see the sales or the customers can see what
  // is outstanding on them. Taking the payment is gated separately, inside the
  // page, on `poultry.customer-payments.create`.
  if (href === "/customer-balances") {
    return isAdmin || f.canViewFinancial || f.canEnterSales || f.canViewCustomers
  }
  if (href === "/supplier-balances") {
    return isAdmin || f.canViewFinancial || f.canEnterExpenses || f.canViewCustomers
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
