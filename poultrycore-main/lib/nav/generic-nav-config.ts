/**
 * Generic company sidebar contents.
 *
 * Moved verbatim out of components/dashboard/sidebar.tsx so the header search
 * can index the same rows the sidebar shows, instead of keeping a third copy.
 * The Generic TOP nav (top-nav.tsx) still builds its own rail inline.
 *
 * React-free: the caller passes in the useGenericModules() answers.
 */

import {
  Activity, Banknote, BarChart3, Boxes, CalendarClock, Cog, CreditCard, DollarSign, FileText, Package,
  PackageMinus, Receipt, Repeat, Scale, Settings, ShoppingBag, ShoppingCart, Truck, Users, Users2, Wallet,
} from "lucide-react"
import type { GenericModulesResult } from "@/hooks/use-generic-modules"
import type { NavItem } from "./nav-model"

export interface GenericNavGroups {
  catalog: NavItem[]
  subscriptions: NavItem[]
  sales: NavItem[]
  purchasing: NavItem[]
  money: NavItem[]
  people: NavItem[]
  admin: NavItem[]
}

export function buildGenericNavGroups(
  genericModules: Pick<GenericModulesResult, "showNew" | "showExisting" | "labels">,
  isAdmin: boolean,
): GenericNavGroups {
  // /generic-inventory is the new at-a-glance stock page (products + cards
  // + filters). /generic-stock-adjustments stays for actually changing stock.
  //
  // Every item here is one of the OPTIONAL modules in section 5 of the spec:
  // a SaaS company, a gym and a school do not sell stock, and a template that
  // turns them off must actually take them off the menu. showExisting rather
  // than showNew, so a failed settings request leaves the menu as it was
  // instead of emptying it.
  const catalog = [
    ...(genericModules.showExisting("enableProducts")
      ? [{ href: "/generic-products", label: "Products", icon: ShoppingBag }] : []),
    ...(genericModules.showExisting("enableInventory")
      ? [{ href: "/generic-inventory", label: "Inventory", icon: Boxes }] : []),
    ...(genericModules.showExisting("enableStockAdjustments")
      ? [{ href: "/generic-stock-adjustments", label: "Stock adjustments", icon: Boxes }] : []),
    ...(genericModules.showExisting("enableInternalUse")
      ? [{ href: "/generic-internal-use", label: "Internal Use", icon: PackageMinus }] : []),
  ]
  // Only the NEW items are gated on module settings. Every item that existed
  // before templates stays ungated -- retro-fitting a gate would take away
  // access people have today.
  const subscriptions = [
    ...(genericModules.showNew("enableSubscriptions")
      ? [
          { href: "/generic-service-plans",  label: genericModules.labels.planPlural,         icon: Repeat },
          { href: "/generic-subscriptions",  label: genericModules.labels.subscriptionPlural, icon: CalendarClock },
          { href: "/generic-billing-runs",   label: "Billing runs",                           icon: Receipt },
        ]
      : []),
  ]
  const sales = [
    { href: "/generic-sales",              label: "Sales",             icon: ShoppingCart },
    ...(genericModules.showNew("enableInvoices")
      ? [{ href: "/generic-invoices", label: genericModules.labels.invoicePlural, icon: FileText }]
      : []),
    { href: "/generic-customers",          label: genericModules.labels.customerPlural, icon: Users },
    { href: "/generic-customer-payments",  label: genericModules.labels.paymentPlural, icon: CreditCard },
    ...(genericModules.showNew("enableCustomerBalances")
      ? [{ href: "/generic-customer-balances", label: genericModules.labels.customerBalance, icon: Scale }]
      : []),
  ]
  const purchasing = [
    { href: "/generic-suppliers",          label: "Suppliers",         icon: Truck },
    // Buying stock is optional too (section 5). A service business owes its
    // vendors through expenses, and Supplier Balances below covers that.
    ...(genericModules.showExisting("enablePurchases")
      ? [{ href: "/generic-purchases", label: "Purchases", icon: Package }] : []),
    { href: "/generic-supplier-payments",  label: "Supplier payments", icon: CreditCard },
    // 251 gave both of these a toggle of their own. Supplier balances no longer
    // rides on Purchases: a service business owes vendors through expenses,
    // which is exactly what 248's payables arm reads, so gating it on stock
    // buying hid it from the companies that needed it most.
    ...(genericModules.showExisting("enableSupplierBalances")
      ? [{ href: "/generic-supplier-balances", label: "Supplier balances", icon: Scale }]
      : []),
    { href: "/generic-expenses",           label: "Expenses",          icon: DollarSign },
    // 348: the shared engine (drafts for review, no month-end drift) replaces
    // the Generic-only page here. /generic-recurring-expenses still works by URL
    // for templates created before it.
    ...(genericModules.showExisting("enableRecurringExpenses")
      ? [{ href: "/recurring-expenses", label: "Recurring expenses", icon: Repeat }]
      : []),
  ]
  const money = [
    ...(genericModules.showExisting("enableCashAccounts")
      ? [
          { href: "/generic-cash",           label: "Cash & Accounts", icon: Wallet },
          { href: "/generic-cash-transfers", label: "Cash transfers",  icon: Activity },
        ]
      : []),
    { href: "/generic-daily-closings", label: "Daily Closing",   icon: FileText },
    { href: "/generic-owner-money",    label: "Owner money",     icon: Wallet },
  ]
  // Generic — People (Phase 6: staff + attendance + payroll, migrations 055/056)
  const people = [
    { href: "/generic-staff",       label: "Staff",      icon: Users2 },
    { href: "/generic-attendance",  label: "Attendance", icon: Activity },
    { href: "/generic-payroll",     label: "Payroll",    icon: Banknote },
    { href: "/generic-staff-payments", label: "Staff payments", icon: Banknote },
  ]
  const admin = [
    { href: "/generic-reports",  label: "Reports",  icon: BarChart3 },
    // Setup is the company PROFILE; Settings is how the company works --
    // which modules it has and what they default to (251). Both admin-only
    // (lib/nav/setup-admin-routes).
    ...(isAdmin ? [
      { href: "/generic-setup",    label: "Setup",    icon: Settings },
      { href: "/generic-settings", label: "Settings", icon: Cog },
    ] : []),
  ]

  return { catalog, subscriptions, sales, purchasing, money, people, admin }
}
