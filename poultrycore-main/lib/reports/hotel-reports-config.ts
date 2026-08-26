/**
 * Hotel reports catalog — single source of truth for the /hotel-reports index
 * page and the top-nav Reports mega-menu. Same pattern as water-reports-config.ts.
 */

import {
  BarChart3, Bed, Calendar, CalendarCheck, ClipboardCheck, CreditCard,
  DollarSign, FileText, Landmark, ShoppingCart, Users, Wallet, Wrench,
} from "lucide-react"
import type { LucideIcon } from "lucide-react"

export type HotelReportStatus = "ready" | "stub"

export interface HotelReport {
  slug: string
  title: string
  description: string
  icon: LucideIcon
  status: HotelReportStatus
}

export interface HotelReportGroup {
  key: string
  label: string
  color: string
  reports: HotelReport[]
}

export const HOTEL_REPORT_GROUPS: HotelReportGroup[] = [
  {
    key: "financial",
    label: "Financial",
    color: "bg-emerald-600",
    reports: [
      { slug: "revenue-summary",   title: "Revenue Summary",     description: "Daily revenue, expenses, net profit and occupancy trends",                icon: BarChart3,       status: "ready" },
      { slug: "expense-report",    title: "Expense Report",      description: "Expenses grouped by category, vendor and period",                          icon: DollarSign,      status: "ready" },
      { slug: "billing-report",    title: "Billing & Payments",  description: "Guest charges, payments received, outstanding balances",                   icon: CreditCard,      status: "ready" },
      { slug: "payroll-report",    title: "Payroll Report",      description: "Staff payroll runs, totals by period, department breakdown",               icon: Wallet,          status: "ready" },
      { slug: "cash-flow-report",  title: "Cash Flow Report",    description: "Money in/out across all cash accounts with running balances",              icon: Landmark,        status: "ready" },
    ],
  },
  {
    key: "operations",
    label: "Operations",
    color: "bg-violet-600",
    reports: [
      { slug: "bookings-report",   title: "Bookings Report",     description: "All bookings with status, dates, rates and source",                        icon: CalendarCheck,   status: "ready" },
      { slug: "guest-report",      title: "Guest Report",        description: "Guest list, repeat guests, VIP guests, nationality breakdown",             icon: Users,           status: "ready" },
      { slug: "occupancy-report",  title: "Occupancy & ADR",     description: "Occupancy rate, ADR, RevPAR trends from daily closings",                   icon: Bed,             status: "ready" },
      { slug: "maintenance-report",title: "Maintenance Report",  description: "Maintenance requests by status, priority and estimated cost",              icon: Wrench,          status: "ready" },
    ],
  },
  {
    key: "restaurant",
    label: "Restaurant & Bar",
    color: "bg-orange-600",
    reports: [
      { slug: "restaurant-sales",  title: "Restaurant Sales",    description: "Restaurant orders, revenue by period, popular items",                      icon: ShoppingCart,    status: "ready" },
      { slug: "menu-performance",  title: "Menu Performance",    description: "Best-selling items, category breakdown, pricing analysis",                 icon: FileText,        status: "ready" },
    ],
  },
  {
    key: "periodic",
    label: "Periodic Reports",
    color: "bg-sky-600",
    reports: [
      { slug: "daily-report",      title: "Daily Report",        description: "Daily snapshot — arrivals, departures, revenue, expenses, occupancy",      icon: Calendar,        status: "ready" },
      { slug: "weekly-report",     title: "Weekly Report",       description: "Weekly summary — bookings, revenue, expenses, occupancy trends",           icon: Calendar,        status: "ready" },
      { slug: "monthly-report",    title: "Monthly Report",      description: "Monthly overview — revenue, expenses, profit, occupancy, guest stats",     icon: Calendar,        status: "ready" },
    ],
  },
  {
    key: "housekeeping",
    label: "Housekeeping & Inventory",
    color: "bg-rose-600",
    reports: [
      { slug: "housekeeping-report",title: "Housekeeping Report", description: "Task completion rates, turnaround times by status",                       icon: ClipboardCheck,  status: "ready" },
      { slug: "inventory-report",  title: "Inventory Report",    description: "Stock levels, low-stock alerts, reorder suggestions",                      icon: FileText,        status: "ready" },
    ],
  },
]

/** Flat list of all reports for nav mega-menu */
export const ALL_HOTEL_REPORTS = HOTEL_REPORT_GROUPS.flatMap((g) => g.reports)
