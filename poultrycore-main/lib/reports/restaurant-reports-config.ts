/**
 * Restaurant reports catalog — single source of truth for the top-nav Reports
 * mega-menu and the /restaurant-reports index page.
 */

import {
  BarChart3, Clock, DollarSign, LayoutDashboard, Package,
  TrendingUp, Users, UtensilsCrossed, Utensils, Receipt,
  CalendarDays, ShoppingCart, Wallet,
} from "lucide-react"
import type { LucideIcon } from "lucide-react"

export interface RestaurantReport {
  slug: string
  title: string
  description: string
  icon: LucideIcon
}

export interface RestaurantReportGroup {
  key: string
  label: string
  color: string
  reports: RestaurantReport[]
}

export const RESTAURANT_REPORT_GROUPS: RestaurantReportGroup[] = [
  {
    key: "sales",
    label: "Sales & Revenue",
    color: "bg-green-600",
    reports: [
      { slug: "overview",   title: "Overview",          description: "Today's snapshot — orders, revenue, active orders",       icon: LayoutDashboard },
      { slug: "daily",      title: "Daily Sales",       description: "Revenue by day with order counts and averages",           icon: DollarSign },
      { slug: "trends",     title: "Revenue Trends",    description: "Weekly and monthly revenue trends over time",             icon: TrendingUp },
      { slug: "income",     title: "Income & Expenses", description: "Income vs expenses, net profit, breakdowns",             icon: Wallet },
    ],
  },
  {
    key: "menu",
    label: "Menu & Food",
    color: "bg-rose-600",
    reports: [
      { slug: "items",      title: "Top Items",         description: "Best-selling items, category breakdown, popularity",      icon: UtensilsCrossed },
      { slug: "foodcost",   title: "Food Cost",         description: "Cost vs selling price, margins, food cost percentage",    icon: Utensils },
      { slug: "categories", title: "Sales by Category", description: "Revenue and quantity sold per menu category",             icon: Package },
    ],
  },
  {
    key: "operations",
    label: "Operations",
    color: "bg-blue-600",
    reports: [
      { slug: "hours",      title: "Peak Hours",        description: "Busiest hours by orders and revenue",                     icon: Clock },
      { slug: "servers",    title: "Waiter Performance", description: "Orders, covers, revenue and avg ticket per waiter",      icon: Users },
      { slug: "orders",     title: "Order Types",       description: "Dine-in vs takeaway vs delivery breakdown",              icon: ShoppingCart },
    ],
  },
  {
    key: "periodic",
    label: "Periodic",
    color: "bg-amber-600",
    reports: [
      { slug: "daily-report",   title: "Daily Report",   description: "End-of-day summary with all key metrics",               icon: CalendarDays },
      { slug: "weekly-report",  title: "Weekly Report",  description: "Weekly comparison — revenue, orders, top items",         icon: CalendarDays },
      { slug: "monthly-report", title: "Monthly Report", description: "Monthly overview — profit, expenses, growth",            icon: CalendarDays },
      { slug: "expenses",       title: "Expense Report", description: "Expenses by category, supplier, payment method",         icon: Receipt },
    ],
  },
]

/** Flat list of all reports for nav mega-menu */
export const ALL_RESTAURANT_REPORTS = RESTAURANT_REPORT_GROUPS.flatMap((g) => g.reports)
