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
  CheckCircle2, ClipboardCheck, CreditCard, DollarSign, Factory, FileText, Gift, GraduationCap, HandCoins, History, Landmark,
  Hourglass, MapPin, PiggyBank, Package, PackageMinus, Receipt, Repeat, Scale, Settings, Timer, TrendingUp,
  PieChart, ShoppingBag, ShoppingCart, Truck, User, Users, Users2, Wallet, Zap, Cog,
  Briefcase, Columns3, Link2, FolderPlus, Tag,
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
  reports: MegaMenuGroup[]
  setup: MegaMenuGroup[]
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
      item("/generic-coupons",       "Coupons",                 Tag),
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
      // Invoices appear here for all company types when enabled (independent of subscriptions).
      // Subscription businesses also see it under the Billing group for convenience.
      ...(showNew("enableInvoices") && !isSub
        ? [item("/generic-invoices", labels.invoicePlural, FileText, canSee("/generic-invoices"))]
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
  // Split into two groups so the mega-menu renders as two columns with headers,
  // matching the poultry Operations panel pattern.
  const catalog: MegaMenuGroup[] = []
  const catalogStockItems: MegaMenuItem[] = [
    ...(showExisting("enableProducts")
      ? [item("/generic-products", "Products & Services", ShoppingBag)] : []),
    ...(showExisting("enableInventory")
      ? [item("/generic-inventory", "Inventory & Purchases", Boxes)] : []),
    ...(showExisting("enableStockAdjustments")
      ? [item("/generic-inventory?tab=adjustments", "Stock adjustments", Boxes)] : []),
    ...(showExisting("enableInventory")
      ? [item("/generic-stock-movements", "Stock Movements", ArrowUpDown)] : []),
    ...(showExisting("enableProducts")
      ? [item("/generic-product-tracker", "Product Tracker", History)] : []),
    // Purchases sit with the stock they buy (Report 40, Part 3: they left the
    // Expenses column, which now lists exactly Poultry's Expenses rows).
    ...(showExisting("enablePurchases")
      ? [item("/generic-inventory?tab=purchases", "Purchases", Package)] : []),
    ...(showExisting("enablePurchases")
      ? [item("/generic-purchases/new", "Record Purchase", ShoppingCart)] : []),
    item("/generic-loss-records", "Loss & Damage", AlertTriangle),
  ]
  const catalogLogisticsItems: MegaMenuItem[] = [
    item("/generic-deliveries", "Deliveries", Truck),
    item("/generic-drivers", "Drivers", Users2),
    item("/generic-routes", "Routes", MapPin),
  ]
  if (catalogStockItems.length > 0) {
    catalog.push({ key: "catalog-stock", label: "Catalog & Stock", items: catalogStockItems })
  }
  if (catalogLogisticsItems.length > 0) {
    catalog.push({ key: "catalog-logistics", label: "Logistics", items: catalogLogisticsItems })
  }
  // 482: Projects & Contracts -- Operations, only when the company turned it on.
  // A NEW item, so showNew: hidden while settings load and for every company
  // that has not chosen it.
  if (showNew("enableProjects")) {
    const projectItems = gated([
      item("/generic-projects",         "Projects & Contracts",      Briefcase, canSee("/generic-projects")),
      item("/generic-projects/new",     "New project / contract",    FolderPlus, canSee("/generic-projects/new")),
      item("/generic-projects/compare", "Compare projects",          Columns3, canSee("/generic-projects/compare")),
      item("/generic-projects/link",    "Link older transactions",   Link2, canSee("/generic-projects/link")),
    ])
    if (projectItems.length > 0) catalog.push({ key: "catalog-projects", label: "Projects & Contracts", items: projectItems })
  }

  // ---- Expenses ----
  // Report 40, Part 3: the same rows, names and order as Poultry's Expenses
  // column (lib/nav/poultry-nav-config.ts salesMoney "expenses"). Suppliers live
  // in Setup > Finance and Purchases with the stock, as on Poultry.
  const expenses: MegaMenuGroup[] = [{
    key: "expenses",
    label: isSub ? "Expenses & Vendors" : "Expenses",
    items: gated([
      item("/generic-expenses",          "Expenses",          DollarSign, canSee("/generic-expenses")),
      item("/generic-supplier-payments", isSub ? "Vendor Payments" : "Supplier Payments", Receipt, canSee("/generic-supplier-payments")),
      ...(showExisting("enableSupplierBalances")
        ? [item("/generic-supplier-balances", isSub ? "Vendor Balances" : "Supplier Balances", Truck, canSee("/generic-supplier-balances"))]
        : []),
      item("/generic-supplier-credits",  isSub ? "Vendor Credits & Advances" : "Supplier Credits & Advances", Wallet, canSee("/generic-supplier-credits")),
      ...(showExisting("enableInternalUse")
        ? [item("/generic-internal-use", "Internal Use", PackageMinus)] : []),
      item("/generic-payroll",           "Payroll",           Banknote, canSee("/generic-payroll")),
      item("/generic-employee-loans",    "Employee Loans & Advances", HandCoins, canSee("/generic-employee-loans")),
      item("/generic-employee-credit",   "Employee Credit",   PiggyBank, canSee("/generic-employee-credit")),
      item("/generic-deferred-costs",    "Deferred inventory cost", Hourglass, canSee("/generic-deferred-costs")),
      item("/generic-assets",            "Capital Investments/Assets", Building2, canSee("/generic-assets")),
      // Poultry files Recurring Expenses under Tools; Generic has no Tools menu.
      ...(showExisting("enableRecurringExpenses")
        ? [item("/recurring-expenses", "Recurring Expenses", Repeat, canSee("/recurring-expenses"))]
        : []),
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
        item("/generic-cash",                "Cash Accounts",    Wallet, canSee("/generic-cash")),
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
  const people: MegaMenuGroup[] = hasStaff ? [
    {
      key: "people-team",
      label: isSchool ? "Staff" : "Team",
      items: gated([
        item("/generic-staff",      "Staff",  Users2),
        item("/generic-attendance", "Attendance", Activity),
      ]),
    },
    // Payroll and Employee Loans & Advances moved to Expenses (as on Poultry,
    // Report 40 Part 3); only the staff payments page is left here.
    ...(showExisting("enableStaffPayments") ? [{
      key: "people-payroll",
      label: "Payments",
      items: gated([
        item("/generic-staff-payments", isSchool ? "Staff payments" : "Employee payments", Banknote, canSee("/generic-staff-payments")),
      ]),
    }] : []),
  ] : []

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

  // ---- Reports ----
  // Its own top-level section, matching the poultry Reports menu.
  const reports: MegaMenuGroup[] = [
    {
      key: "reports-financial",
      label: "Financial",
      items: gated([
        item("/generic-reports",                          "All Reports",        BarChart3, canSee("/generic-reports")),
        item("/generic-reports/period-pnl",               "Profit & Loss",      DollarSign, canSee("/generic-reports")),
        item("/generic-reports/daily-summary",            "Daily Business Summary", BarChart3, canSee("/generic-reports")),
        item("/generic-reports/cash-summary",             "Cash Flow",          Wallet, canSee("/generic-reports")),
        item("/generic-reports/expenses-by-category",     "Expense Report",     PieChart, canSee("/generic-reports")),
        item("/generic-reports/cash-accounts",            "Cash Account Report", Landmark, canSee("/generic-reports")),
        item("/generic-reports/cash-movement",            "Cash Movement",      Wallet, canSee("/generic-reports")),
        item("/generic-reports/money-movement",           "Money Movement",     ArrowUpDown, canSee("/generic-reports")),
        item("/generic-reports/closing-report",           "Closing Report",     FileText, canSee("/generic-reports")),
        item("/generic-reports/closing-by-category",      "Closing by Category", BarChart3, canSee("/generic-reports")),
        item("/generic-reports/customer-balance",         "Customer Balance",   Users, canSee("/generic-reports")),
        item("/generic-reports/supplier-balance",         "Supplier Balance",   Truck, canSee("/generic-reports")),
        item("/generic-reports/staff-cost",               "Staff & Contractor Cost", Users2, canSee("/generic-reports")),
      ]),
    },
    ...(showNew("enableInvoices") ? [{
      key: "reports-invoicing",
      label: "Invoicing",
      items: gated([
        item("/generic-reports/invoice-aging", "Invoice Aging",   FileText, canSee("/generic-reports")),
        item("/generic-reports/collections",   "Collections",     HandCoins, canSee("/generic-reports")),
      ]),
    }] : []),
    {
      key: "reports-sales",
      label: "Sales & Stock",
      items: gated([
        ...(showExisting("enableProducts") ? [
          item("/generic-reports/sales-by-product",        "Sales by Product",        ShoppingCart, canSee("/generic-reports")),
          item("/generic-reports/sales-by-customer",       "Sales by Customer",       Users, canSee("/generic-reports")),
          item("/generic-reports/inventory-value",         "Inventory Value",         Boxes, canSee("/generic-reports")),
          item("/generic-reports/inventory-balance",       "Inventory Balance",       Boxes, canSee("/generic-reports")),
          item("/generic-reports/internal-consumption",    "Internal Consumption",    PackageMinus, canSee("/generic-reports")),
          item("/generic-reports/restock-forecast",        "Restock Forecast",        TrendingUp, canSee("/generic-reports")),
          item("/generic-reports/inventory-reconciliation","Inventory Reconciliation",CheckCircle2, canSee("/generic-reports")),
          item("/generic-reports/delivery-report",         "Delivery Report",         Truck, canSee("/generic-reports")),
        ] : []),
      ]),
    },
    ...(isSub ? [{
      key: "reports-subscription",
      label: "Subscription",
      items: gated([
        item("/generic-reports/subscription-revenue", `${labels.subscription} Revenue`, Repeat, canSee("/generic-reports")),
        item("/generic-reports/mrr",                  "Monthly Recurring Revenue",      TrendingUp, canSee("/generic-reports")),
        item("/generic-reports/customer-payments",    `${labels.customer} Payments`,    CreditCard, canSee("/generic-reports")),
        item("/generic-reports/unpaid-customers",     `Unpaid ${labels.customerPlural}`, AlertTriangle, canSee("/generic-reports")),
        item("/generic-reports/break-even",           "Break-even",                     Scale, canSee("/generic-reports")),
      ]),
    }] : []),
  ]

  // ---- Setup ----
  // Mirrors the poultry Setup menu: Company, Finance, Delivery, People.
  const setup: MegaMenuGroup[] = [
    {
      key: "setup-company",
      label: "Company",
      items: gated([
        item("/generic-setup",              "Business Profile",  Settings, canSee("/generic-setup")),
        item("/generic-business-features",  "Business Features", Zap, canSee("/generic-business-features")),
        item("/generic-settings",           "Settings",          Cog, canSee("/generic-settings")),
      ]),
    },
    {
      key: "setup-finance",
      label: "Finance",
      items: gated([
        item("/generic-customers",  labels.customerPlural, Users, canSee("/generic-customers")),
        item("/generic-suppliers",  isSub ? "Vendors" : "Suppliers", Truck, canSee("/generic-suppliers")),
        ...(showExisting("enableCashAccounts") ? [
          item("/generic-cash",     "Cash Accounts", Wallet, canSee("/generic-cash")),
        ] : []),
      ]),
    },
    ...(showExisting("enableProducts") ? [{
      key: "setup-production",
      label: "Production",
      items: gated([
        item("/generic-products",    "Products", ShoppingBag),
        item("/generic-production",  "Production Records", Factory),
      ]),
    }] : []),
    {
      key: "setup-delivery",
      label: "Delivery",
      items: gated([
        item("/generic-drivers",  "Drivers",  Users2),
        item("/generic-routes",   "Routes",   MapPin),
      ]),
    },
    {
      key: "setup-people",
      label: "People",
      items: gated([
        item("/generic-staff",  "Staff", Users2),
        item("/employees",      "Users & Permissions",            User),
      ]),
    },
  ]

  // ---- Admin ----
  const admin: MegaMenuGroup[] = [
    {
      key: "admin-account",
      label: "Account",
      items: gated([
        item("/profile", "Account", User),
      ]),
    },
  ]

  return { billing, salesOrStudents, catalog, expenses, money, people, school, reports, setup, admin }
}

// Compatibility export for use-global-search.ts which expects flat NavItem arrays.
type NavItem = { href: string; label: string; icon: any }
export interface GenericNavGroups {
  catalog: NavItem[]; subscriptions: NavItem[]; sales: NavItem[]
  purchasing: NavItem[]; money: NavItem[]; people: NavItem[]
  reports: NavItem[]; setup: NavItem[]; admin: NavItem[]
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
    reports: flattenGroup(full.reports),
    setup: flattenGroup(full.setup),
    admin: flattenGroup(full.admin),
  }
}
