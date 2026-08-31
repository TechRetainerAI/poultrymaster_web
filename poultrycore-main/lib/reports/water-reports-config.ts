/**
 * Water reports catalog — single source of truth for the Reports index
 * page and the top-nav Reports mega-menu.
 *
 * 4 groups by design (Financial / Sales & Customers / Production & Inventory
 * / Delivery & Operations); the mega-menu renders one column per group, the
 * /water-reports index renders one section per group. Add a new report by
 * appending to the relevant group's `reports` array — it shows up in both
 * places automatically.
 */

import {
  BarChart3, Receipt, DollarSign, Users, Factory, Boxes, Truck,
  Route as RouteIcon, TrendingDown, FileText, ShoppingCart, ShoppingBag,
  PiggyBank, History, Layers, Wallet, Gauge, type LucideIcon,
} from "lucide-react"

export type WaterReportStatus = "ready" | "stub"

export type WaterReport = {
  slug: string
  title: string
  description: string
  icon: LucideIcon
  status: WaterReportStatus
}

export type WaterReportGroup = {
  key: "financial" | "sales-customers" | "production-inventory" | "delivery-operations"
  label: string
  /** Tailwind bg class used by the index page card icons + section dot. */
  color: string
  reports: WaterReport[]
}

export const WATER_REPORT_GROUPS: WaterReportGroup[] = [
  {
    key: "financial",
    label: "Financial",
    color: "bg-emerald-600",
    // Closing Report leads, then Profit & Loss — same order as the poultry
    // "Sales, Money & Profit" column, so the two rails read alike.
    reports: [
      { slug: "closing-report",    title: "Closing Report",         description: "Daily closings (including reopened + superseded).",                               icon: FileText,     status: "ready" },
      { slug: "profit-loss",       title: "Profit & Loss",          description: "Revenue, costs, expenses, losses, gross & net profit by period.",                 icon: TrendingDown, status: "ready" },
      { slug: "daily-summary",     title: "Daily Business Summary", description: "Full daily snapshot — sales, payments, expenses, production, losses, cash.",       icon: BarChart3,    status: "ready" },
      // Cash Flow retired here — it lived at /water-reports/cash-flow and counted
      // internal transfers as inflow AND outflow, so a MoMo-to-Bank move inflated
      // both, and its bare toDate excluded everything recorded today. The
      // operational page at /water-cash-flow (Sales & Money) replaces it with both
      // fixed. Do not re-add a second Cash Flow here.
      { slug: "expense-report",    title: "Expense Report",         description: "Expenses grouped by category, source, payment method.",                           icon: Receipt,      status: "ready" },
      { slug: "supplier-activity", title: "Supplier Activity",      description: "Per-supplier purchases, expenses paid, outstanding balance, last activity.",      icon: Receipt,      status: "ready" },
    ],
  },
  {
    key: "sales-customers",
    label: "Sales & Customers",
    color: "bg-sky-600",
    reports: [
      { slug: "sales-report",      title: "Sales Report",           description: "All sales — date, customer, products, status, source.",      icon: ShoppingCart, status: "ready" },
      { slug: "payments-received", title: "Payments Received",      description: "Collections by date, customer, method, source.",              icon: DollarSign,   status: "ready" },
      { slug: "customer-balances", title: "Customer Balances",      description: "Receivables with aging.",                                     icon: PiggyBank,    status: "ready" },
      { slug: "customer-history",  title: "Customer Sales History", description: "Per-customer sales + payment timeline.",                      icon: History,      status: "ready" },
      { slug: "top-customers",     title: "Top Customers",          description: "Highest-value customers by total sales for the period.",      icon: Users,        status: "ready" },
    ],
  },
  {
    key: "production-inventory",
    label: "Production & Inventory",
    color: "bg-indigo-600",
    reports: [
      { slug: "production-report",     title: "Production Report",      description: "Production records, machine, product, good bags, cost/bag, efficiency.", icon: Factory,     status: "ready" },
      { slug: "raw-material-usage",    title: "Raw Material Usage",     description: "Expected vs actual usage with variance.",                     icon: Layers,      status: "ready" },
      { slug: "raw-material-purchase", title: "Raw Material Purchases", description: "Suppliers, costs, payment methods.",                          icon: ShoppingBag, status: "ready" },
      { slug: "inventory-report",      title: "Inventory / Stock",      description: "Current stock by product/material with low-stock alerts.",    icon: Boxes,       status: "ready" },
      { slug: "stock-movement",        title: "Stock Movement",         description: "All inventory movements — type, direction, source.",          icon: Gauge,       status: "ready" },
      { slug: "product-performance",   title: "Product Performance",    description: "Per-product sales, cost, gross profit estimate.",             icon: ShoppingBag, status: "ready" },
    ],
  },
  {
    key: "delivery-operations",
    label: "Delivery & Operations",
    color: "bg-rose-600",
    reports: [
      { slug: "delivery-run-report",   title: "Delivery Run Report",    description: "Loadings, returns, shortages, status.",                                  icon: Truck,        status: "ready" },
      { slug: "driver-accountability", title: "Driver Accountability",  description: "Per-driver loadings, sales, returns, damages, shortages.",               icon: Users,        status: "ready" },
      { slug: "route-performance",     title: "Route Performance",      description: "Per-route sales, collections, customers served.",                        icon: RouteIcon,    status: "ready" },
      { slug: "driver-collection",     title: "Driver Collection",      description: "Per-driver cash/MoMo/bank collections, credit, shortages, per-product detail.", icon: Wallet,  status: "ready" },
      { slug: "vehicle-usage",         title: "Vehicle Usage",          description: "Per-vehicle runs, sales, expenses.",                                     icon: Truck,        status: "ready" },
      { slug: "loss-report",           title: "Loss Report",            description: "Damages, rejected, manual + delivery losses by source.",                 icon: TrendingDown, status: "ready" },
      { slug: "operational",           title: "Operational dashboard",  description: "Route profitability, driver reconciliation, raw material variance.",      icon: BarChart3,    status: "ready" },
    ],
  },
]

/** Path to a water report page given its slug. */
export const waterReportHref = (slug: string) => `/water-reports/${slug}`
