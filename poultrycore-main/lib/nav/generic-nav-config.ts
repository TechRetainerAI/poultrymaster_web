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
  Activity, Banknote, BarChart3, Boxes, CalendarClock, CalendarDays,
  ClipboardCheck, CreditCard, DollarSign, FileText, GraduationCap,
  Package, PackageMinus, Receipt, Repeat, Scale, Settings,
  ShoppingBag, ShoppingCart, Truck, User, Users, Users2, Wallet, Zap, Cog,
} from "lucide-react"
import type { MegaMenuGroup, MegaMenuItem } from "./nav-model"
import type { GenericModulesResult } from "@/hooks/use-generic-modules"

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
function item(href: string, title: string, icon: MegaMenuItem["icon"]): MegaMenuItem {
  return { id: href, title, icon, href }
}

export function buildGenericNavConfig(modules: GenericModulesResult): GenericNavConfig {
  const { showNew, showExisting, labels, isSubscriptionBusiness: isSub, industry } = modules
  const isSchool = industry === "School"

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
    items: [
      ...(!isSub ? [item("/generic-pos",   "Quick Sale", Zap)]          : []),
      ...(!isSub ? [item("/generic-sales", "Sales",      ShoppingCart)] : []),
      ...(showNew("enableInvoices") && !isSub
        ? [item("/generic-invoices", labels.invoicePlural, FileText)]
        : []),
      item("/generic-customers",         labels.customerPlural, Users),
      item("/generic-customer-payments", labels.paymentPlural,  CreditCard),
      ...(showNew("enableCustomerBalances")
        ? [item("/generic-customer-balances", labels.customerBalance, Scale)]
        : []),
    ],
  }]

  // ---- Catalog / Stock ----
  const catalog: MegaMenuGroup[] = []
  const catalogItems: MegaMenuItem[] = [
    ...(showExisting("enableProducts")
      ? [item("/generic-products", "Products", ShoppingBag)] : []),
    ...(showExisting("enableInventory")
      ? [item("/generic-inventory", "Inventory", Boxes)] : []),
    ...(showExisting("enableStockAdjustments")
      ? [item("/generic-stock-adjustments", "Stock adjustments", Boxes)] : []),
    ...(showExisting("enableInternalUse")
      ? [item("/generic-internal-use", "Internal Use", PackageMinus)] : []),
  ]
  if (catalogItems.length > 0) {
    catalog.push({ key: "catalog", label: "Catalog & Stock", items: catalogItems })
  }

  // ---- Expenses & Vendors / Purchasing ----
  const expenses: MegaMenuGroup[] = [{
    key: "expenses",
    label: isSub ? "Expenses & Vendors" : "Purchasing",
    items: [
      item("/generic-suppliers",         isSub ? "Vendors" : "Suppliers", Truck),
      ...(showExisting("enablePurchases")
        ? [item("/generic-purchases", "Purchases", Package)] : []),
      item("/generic-supplier-payments", isSub ? "Vendor payments" : "Supplier payments", CreditCard),
      ...(showExisting("enableSupplierBalances")
        ? [item("/generic-supplier-balances", isSub ? "Vendor balances" : "Supplier balances", Scale)]
        : []),
      item("/generic-expenses",          "Expenses",          DollarSign),
      ...(showExisting("enableRecurringExpenses")
        ? [item("/recurring-expenses", "Recurring expenses", Repeat)]
        : []),
    ],
  }]

  // ---- Money ----
  const money: MegaMenuGroup[] = [{
    key: "money",
    label: "Money",
    items: [
      ...(showExisting("enableCashAccounts") ? [
        item("/generic-cash",           "Cash & Accounts", Wallet),
        item("/generic-cash-transfers", "Cash transfers",  Activity),
      ] : []),
      item("/generic-daily-closings", "Daily Closing",                       FileText),
      item("/generic-owner-money",    isSub ? "Owner funds" : "Owner money", Wallet),
    ],
  }]

  // ---- People / Staff ----
  // Only show when staff payments are explicitly enabled in module settings.
  // A solo yam seller can turn this off in Settings to hide the section.
  const hasStaff = Boolean(modules.settings?.enableStaffPayments) || isSchool
  const people: MegaMenuGroup[] = hasStaff ? [{
    key: "people",
    label: isSchool ? "Staff & Teachers" : "Employees",
    items: [
      item("/generic-staff",      isSchool ? "Staff" : "Employees",  Users2),
      item("/generic-attendance", "Attendance", Activity),
      item("/generic-payroll",    "Payroll",    Banknote),
      ...(showExisting("enableStaffPayments")
        ? [item("/generic-staff-payments", isSchool ? "Staff payments" : "Employee payments", Banknote)] : []),
    ],
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
    items: [
      item("/generic-reports",  "Reports",  BarChart3),
      item("/generic-setup",    "Setup",    Settings),
      item("/generic-settings", "Settings", Cog),
      item("/profile",          "Account",  User),
    ],
  }]

  return { billing, salesOrStudents, catalog, expenses, money, people, school, admin }
}
