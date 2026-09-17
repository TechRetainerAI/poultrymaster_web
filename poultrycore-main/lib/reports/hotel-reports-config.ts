/**
 * Hotel reports catalog — single source of truth for the /hotel-reports index
 * page and the top-nav Reports mega-menu. Same pattern as water-reports-config.ts.
 */

import {
  BarChart3, Bed, Calendar, CalendarCheck, ClipboardCheck, CreditCard,
  DollarSign, FileText, Landmark, ShoppingCart, Users, Wallet, Wrench,
  Gauge, Globe, TimerReset, LayoutGrid, CalendarX2, MoonStar, Receipt,
  Timer, Award,
} from "lucide-react"
import type { LucideIcon } from "lucide-react"

export type HotelReportStatus = "ready" | "stub"

/**
 * What date control the shared report shell should render. Only the reports
 * added in migration 299 go through that shell, so this is optional: the 17
 * original reports each own their page and their own filters, and the router
 * defaults a missing value to "range".
 */
export type HotelReportDateMode = "range" | "single" | "none"

export interface HotelReport {
  slug: string
  title: string
  description: string
  icon: LucideIcon
  status: HotelReportStatus
  dateMode?: HotelReportDateMode
  /** Shown on the index card, so what is actually new stays visible. */
  isNew?: boolean
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
      { slug: "guest-ledger",      title: "Guest Ledger",        description: "Unpaid invoices aged by due date — who owes what, and for how long",      icon: Receipt,         status: "ready", dateMode: "none",  isNew: true },
      { slug: "ancillary-revenue", title: "Ancillary Revenue",   description: "Spend beyond the room — by charge type, per stay",                        icon: ShoppingCart,    status: "ready", dateMode: "range", isNew: true },
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
      { slug: "loyalty-report",    title: "Loyalty Programme",   description: "Members and points by tier, earned and redeemed in the period",            icon: Award,           status: "ready", dateMode: "range", isNew: true },
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
      { slug: "housekeeping-productivity", title: "Housekeeping Productivity", description: "Minutes per room and rooms per shift, by attendant",          icon: Timer,           status: "ready", dateMode: "range", isNew: true },
    ],
  },
  {
    // The revenue-management set. None of these existed: the module had ADR and
    // RevPAR stored per night in hoteldailyclosings and nothing that read
    // booking.source, booking lead time, or room type at all.
    key: "revenue",
    label: "Revenue Management",
    color: "bg-indigo-600",
    reports: [
      { slug: "performance-kpis",      title: "Performance & KPIs",  description: "Occupancy, ADR, RevPAR, TRevPAR and GOPPAR for the period",             icon: Gauge,      status: "ready", dateMode: "range", isNew: true },
      { slug: "source-of-business",    title: "Source of Business",  description: "Room nights and revenue by booking channel, with lead time",            icon: Globe,      status: "ready", dateMode: "range", isNew: true },
      { slug: "booking-pace",          title: "Booking Pace",        description: "How far ahead bookings arrive, bucketed by lead time",                  icon: TimerReset, status: "ready", dateMode: "range", isNew: true },
      { slug: "room-type-performance", title: "Room Type Performance", description: "Occupancy, ADR and RevPAR for each room type",                        icon: LayoutGrid, status: "ready", dateMode: "range", isNew: true },
      { slug: "length-of-stay",        title: "Length of Stay",      description: "How long guests actually stay, and what each length is worth",          icon: MoonStar,   status: "ready", dateMode: "range", isNew: true },
      { slug: "cancellations",         title: "Cancellations",       description: "Cancelled bookings and lost value, by the channel that produced them",  icon: CalendarX2, status: "ready", dateMode: "range", isNew: true },
    ],
  },
]

/** Flat list of all reports for nav mega-menu */
export const ALL_HOTEL_REPORTS = HOTEL_REPORT_GROUPS.flatMap((g) => g.reports)
