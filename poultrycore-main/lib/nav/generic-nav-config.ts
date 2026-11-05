/**
 * Generic Company desktop nav contents.
 *
 * Mirrors the pattern of water-nav-config.ts: a builder that returns grouped
 * nav items for the top-nav mega menus and the sidebar. The groups adapt based
 * on business type (subscription vs retail) and industry (school, gym, etc.).
 *
 * Items use the MegaMenuItem shape (id + title) for the top-nav mega menus.
 * The sidebar flattens them back to { href, label, icon } via the flat() helper.
 */

import {
  Activity, AlertTriangle, ArrowUpDown, Banknote, BarChart3, Boxes, Building2, CalendarClock, CalendarDays,
  ClipboardCheck, CreditCard, DollarSign, FileText, Gift, GraduationCap, HandCoins, Landmark,
  Package, PackageMinus, Receipt, Repeat, Scale, Settings, Timer, TrendingUp,
  ShoppingBag, ShoppingCart, Truck, User, Users, Users2, Wallet, Zap, Cog,
} from "lucide-react"
import type { MegaMenuGroup, MegaMenuItem } from "./nav-model"
import type { GenericModulesResult } from "@/hooks/use-generic-modules"
import type { UserPermissions } from "@/hooks/use-permissions"
import { isFinancialNavItemVisible } from "@/lib/utils/financial-nav-access"

export interface GenericNavConfig {
  billing: MegaMenuGroup[]
  salesOrStudents: MegaMenuGroup[]
  catalog: MegaMenuGroup[]
  expenses: MegaMenuGroup[]
  money: MegaMenuGroup[]
  people: MegaMenuGroup[]
  school: MegaMenuGroup[]
  admin: MegaMenuGroup[]
}

/** Shorthand to build a MegaMenuItem from an href and label. */
function item(href: string, title: string, icon: MegaMenuItem["icon"], visible?: boolean): MegaMenuItem {
  return { id: href, title, icon, href, ...(visible === false ? { visible: false } : {}) }
}

/** Filter out items where visible === false. */
function gated(items: MegaMenuItem[]): MegaMenuItem[] {
  return items.filter((i) => i.visible !== false)
}

export function buildGenericNavConfig(modules: GenericModulesResult, permissions?: UserPermissions): GenericNavConfig {
  const { showNew, showExisting, labels, isSubscriptionBusiness: isSub, industry } = modules
  const isSchool = industry === "School"
  const { featureAccess, isAdmin } = permissions ?? { featureAccess: {} as any, isAdmin: true }
  /** Gate a nav item on financial permissions. Admins always pass. No permissions = show all. */
  const canSee = (href: string) => !permissions || isFinancialNavItemVisible(href, featureAccess, isAdmin)

  // ---- Billing / Subscriptions ----
  const billing: MegaMenuGroup[] = showNew("enableSubscriptions") ? [{
    key: "billing",
    label: isSchool ? "Fees & Billing" : isSub ? "Billing" : "Subscriptions",
    items: [
      item("/generic-service-plans", labels.planPlural,         Repeat),
      item("/generic-subscriptions", labels.subscriptionPlural, CalendarClock),
      item("/generic-billing-runs",  "Billing runs",            Receipt),
      ...(showNew("enableInvoices")
        ? [item("/generic-invoices", labels.invoicePlural, FileText)]
        : []),
    ],
  }] : []

  // ---- Sales / Students & Payments ----
  const salesOrStudents: MegaMenuGroup[] = [{
    key: "sales",
    label: isSub ? `${labels.customerPlural} & Payments` : "Sales",
    items: gated([
      ...(!isSub ? [item("/generic-sales", "Sales", ShoppingCart, canSee("/generic-sales"))] : []),
      ...(showNew("enableInvoices") && !isSub
        ? [item("/generic-invoices", labels.invoicePlural, FileText)]
        : []),
      item("/generic-customers",         labels.customerPlural, Users, canSee("/generic-customers")),
      item("/generic-customer-payments", labels.paymentPlural,  CreditCard, canSee("/generic-customer-payments")),
      ...(showNew("enableCustomerBalances")
        ? [item("/generic-customer-balances", labels.customerBalance, Scale, canSee("/generic-customer-balances"))]
        : []),
      item("/generic-customer-credits", "Customer Credits", Gift, canSee("/generic-customer-credits")),
    ]),
  }]

  // ---- Catalog / Stock ----
  const catalog: MegaMenuGroup[] = []
  const catalogItems: MegaMenuItem[] = [
    ...(showExisting("enableProducts")
      ? [item("/generic-products", "Products", ShoppingBag)] : []),
    ...(showExisting("enableInventory")
      ? [item("/generic-inventory", "Inventory & Purchases", Boxes)] : []),
    ...(showExisting("enableStockAdjustments")
      ? [item("/generic-inventory?tab=adjustments", "Stock adjustments", Boxes)] : []),
    ...(showExisting("enableInventory")
      ? [item("/generic-stock-movements", "Stock Movements", ArrowUpDown)] : []),
    ...(showExisting("enablePurchases")
      ? [item("/generic-purchases/new", "Record Purchase", ShoppingCart)] : []),
    ...(showExisting("enableInternalUse")
      ? [item("/generic-internal-use", "Internal Use", PackageMinus)] : []),
    item("/generic-loss-records", "Loss & Damage", AlertTriangle),
    item("/generic-deliveries", "Deliveries", Truck),
  ]
  if (catalogItems.length > 0) {
    catalog.push({ key: "catalog", label: "Catalog & Stock", items: catalogItems })
  }

  // ---- Expenses & Vendors / Purchasing ----
  const expenses: MegaMenuGroup[] = [{
    key: "expenses",
    label: isSub ? "Expenses & Vendors" : "Purchasing",
    items: gated([
      item("/generic-suppliers",         isSub ? "Vendors" : "Suppliers", Truck, canSee("/generic-suppliers")),
      ...(showExisting("enablePurchases")
        ? [item("/generic-inventory?tab=purchases", "Purchases", Package)] : []),
      item("/generic-supplier-payments", isSub ? "Vendor payments" : "Supplier payments", CreditCard, canSee("/generic-supplier-payments")),
      ...(showExisting("enableSupplierBalances")
        ? [item("/generic-supplier-balances", isSub ? "Vendor balances" : "Supplier balances", Scale, canSee("/generic-supplier-balances"))]
        : []),
      item("/generic-supplier-credits",  isSub ? "Vendor credits" : "Supplier Credits & Advances", HandCoins, canSee("/generic-supplier-credits")),
      item("/generic-expenses",          "Expenses",          DollarSign, canSee("/generic-expenses")),
      ...(showExisting("enableRecurringExpenses")
        ? [item("/recurring-expenses", "Recurring expenses", Repeat, canSee("/recurring-expenses"))]
        : []),
      item("/generic-deferred-costs",    "Deferred Inventory Cost", Timer, canSee("/generic-deferred-costs")),
      item("/generic-assets",            "Capital Investments/Assets", Building2, canSee("/generic-assets")),
    ]),
  }]

  // ---- Money ----
  const money: MegaMenuGroup[] = [{
    key: "money",
    label: "Money",
    items: gated([
      item("/generic-cash-flow",             "Cash Flow",              Wallet, canSee("/generic-cash-flow")),
      item("/generic-financial-activity",    "Financial Activity",     Activity, canSee("/generic-financial-activity")),
      item("/generic-profit-loss",           "Profit & Loss",          TrendingUp, canSee("/generic-profit-loss")),
      ...(showExisting("enableCashAccounts") ? [
        item("/generic-cash",                "Cash & Accounts",    Wallet, canSee("/generic-cash")),
        item("/generic-cash-transfers",      "Cash transfers",     Activity, canSee("/generic-cash-transfers")),
        item("/generic-cash-reconciliation", "Reconciliation",     Scale, canSee("/generic-cash-reconciliation")),
      ] : []),
      item("/generic-daily-closings", "Daily Closing",                       FileText, canSee("/generic-daily-closings")),
      item("/generic-owner-money",    isSub ? "Owner funds" : "Owner money", Wallet, canSee("/generic-owner-money")),
      item("/generic-loans",          "Loans (Financing)",                   Landmark, canSee("/generic-loans")),
    ]),
  }]

  // ---- People / Staff ----
  // Only show when staff payments are explicitly enabled in module settings.
  // A solo yam seller can turn this off in Settings to hide the section.
  const hasStaff = Boolean(modules.settings?.enableStaffPayments) || isSchool
  const people: MegaMenuGroup[] = hasStaff ? [{
    key: "people",
    label: isSchool ? "Staff & Teachers" : "Employees",
    items: gated([
      item("/generic-staff",      isSchool ? "Staff" : "Employees",  Users2),
      item("/generic-attendance", "Attendance", Activity),
      item("/generic-payroll",    "Payroll",    Banknote, canSee("/generic-payroll")),
      ...(showExisting("enableStaffPayments")
        ? [item("/generic-staff-payments", isSchool ? "Staff payments" : "Employee payments", Banknote, canSee("/generic-staff-payments"))] : []),
      item("/generic-employee-loans", "Employee loans", HandCoins, canSee("/generic-employee-loans")),
    ]),
  }] : []

  // ---- School ----
  const school: MegaMenuGroup[] = isSchool ? [{
    key: "school",
    label: "School",
    items: [
      item("/generic-classes",            "Classes",            GraduationCap),
      item("/generic-terms",              "Academic Terms",     CalendarDays),
      item("/generic-student-attendance", "Student Attendance", ClipboardCheck),
    ],
  }] : []

  // ---- Admin ----
  const admin: MegaMenuGroup[] = [{
    key: "admin",
    label: "Admin",
    items: gated([
      item("/generic-reports",            "Reports",           BarChart3, canSee("/generic-reports")),
      item("/generic-setup",              "Setup",             Settings, canSee("/generic-setup")),
      item("/generic-business-features",  "Business Features", Settings, canSee("/generic-business-features")),
      item("/generic-settings",           "Settings",          Cog, canSee("/generic-settings")),
      item("/profile",                    "Account",           User),
    ]),
  }]

  return { billing, salesOrStudents, catalog, expenses, money, people, school, admin }
}

// Compatibility export for use-global-search.ts which expects flat NavItem arrays.
type NavItem = { href: string; label: string; icon: any }
export interface GenericNavGroups {
  catalog: NavItem[]; subscriptions: NavItem[]; sales: NavItem[]
  purchasing: NavItem[]; money: NavItem[]; people: NavItem[]; admin: NavItem[]
}
function flattenGroup(groups: MegaMenuGroup[]): NavItem[] {
  return groups.flatMap((g) => g.items.filter((i) => i.visible !== false).map((i) => ({ href: i.href!, label: i.title, icon: i.icon })))
}
export function buildGenericNavGroups(
  modules: Pick<GenericModulesResult, "showNew" | "showExisting" | "labels">,
  isAdmin: boolean,
): GenericNavGroups {
  const full = buildGenericNavConfig(modules as GenericModulesResult)
  return {
    catalog: flattenGroup(full.catalog),
    subscriptions: flattenGroup(full.billing),
    sales: flattenGroup(full.salesOrStudents),
    purchasing: flattenGroup(full.expenses),
    money: flattenGroup(full.money),
    people: flattenGroup(full.people),
    admin: flattenGroup(full.admin),
  }
}
