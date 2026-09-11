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
  // The older page, kept alongside it. Same data class, same flag — see the
  // note on the nav entry for what actually differs between the two.
  if (href === "/cash") return f.canViewCashLedger
  if (href === "/poultry-cash-accounts") return f.canViewCashLedger
  // Counting cash is a cash-ledger job; it rides the same flag rather than
  // introducing a permission nobody has been granted yet.
  if (href === "/poultry-cash-reconciliation") return f.canViewCashLedger
  // Migrations 252-254. This function is an ALLOWLIST -- it ends in `return
  // false` -- so a Money nav item that is not named here is hidden from
  // everyone, admins included. All three ride canViewCashLedger, the same flag
  // as the two lines above and for the same reason: staff are deny-by-default,
  // so a fresh permission would hide the page from every person who can see the
  // cash pages today until an admin went and granted it.
  //
  // What each page lets you DO is gated separately, inside it, on the keys
  // migration 255 seeded (poultry.cash-transfers.approve for reversing a
  // transfer, and so on).
  if (href === "/poultry-cash-transfers") return f.canViewCashLedger
  if (href === "/poultry-owner-money") return f.canViewCashLedger
  if (href === "/poultry-loans") return f.canViewCashLedger
  // Migration 288. Deferred Inventory Costs shows what stock cost and where
  // that cost went, so it rides the expense flag rather than the inventory
  // one: someone who can count the feed is not automatically someone who may
  // see what it cost and what it did to the P&L. canViewFinancial is included
  // for the same reason the Balances rows below include it -- a finance-only
  // reader needs the page that explains their expense lines.
  if (href === "/poultry-deferred-costs") return f.canEnterExpenses || f.canViewFinancial
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
  // Supplier Payments is the same audience as Supplier Balances -- it is the
  // paid side of the same ledger. Reversing is gated separately, inside the
  // page, on poultry.supplier-payments.reverse.
  if (href === "/supplier-payments") {
    return isAdmin || f.canViewFinancial || f.canEnterExpenses || f.canViewCustomers
  }
  if (href === "/billing") {
    return options?.tempShowPayments === true || isAdmin || f.canViewFinancial
  }
  // Profit & Loss surfaced in the Money group, one row under Cash Flow. It is
  // the same page as the report, so it reads to whoever can see EITHER the
  // financial pages or the reports -- this list is default-deny, so without a
  // rule here the row would silently never render.
  if (href === "/poultry/reports/profit-loss") {
    return isAdmin || f.canViewFinancial || f.canViewReports
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
