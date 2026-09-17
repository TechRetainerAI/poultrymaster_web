/**
 * Restaurant reports catalog — the single source of truth for the top-nav
 * Reports mega-menu, the /restaurant-reports index page, and the report router
 * at /restaurant-reports/[slug].
 *
 * WHY THIS FILE WAS REWRITTEN
 * The previous catalog listed 14 reports in four groups, of which seven had no
 * implementation at all (`income`, `categories`, `orders`, `daily-report`,
 * `weekly-report`, `monthly-report`, `expenses`). It also pointed every entry at
 * `/restaurant-reports?tab=<slug>`, a query string the page never read -- so all
 * fourteen menu items, including the seven that did exist, landed on Overview.
 *
 * Three rules now keep the catalog honest:
 *
 *   1. Every entry here resolves to a real report. There is no "coming soon"
 *      state, because a menu that lies is worse than a shorter menu.
 *   2. `dateMode` declares what date control the report needs, so the shared
 *      shell can render the right one instead of each report growing its own.
 *      A report that ignores dates (stock on hand) says so and gets no control,
 *      rather than showing a filter that changes nothing.
 *   3. Three of the old "Periodic" entries are gone on purpose. `daily-report`,
 *      `weekly-report` and `monthly-report` were Daily Sales and Revenue Trend
 *      with a different preset; the shell's Today / 7d / 30d / This month
 *      presets do that job without three near-identical pages to maintain.
 */

import {
  BarChart3, Clock, DollarSign, TrendingUp, Users, UtensilsCrossed, Utensils,
  Receipt, CalendarDays, ShoppingCart, Wallet, Timer, Table2, Coins, Ban,
  Boxes, Trash2, Heart, Star, Truck, Store, PieChart, Percent, Soup,
} from "lucide-react"
import type { LucideIcon } from "lucide-react"

/** What date control the shared shell should render for a report. */
export type ReportDateMode =
  /** From + To, plus the presets. The default for almost everything. */
  | "range"
  /** A single day with a back/forward stepper (daily sales, peak hours). */
  | "single"
  /** No control at all — the report is a position, not a period. */
  | "none"

export interface RestaurantReport {
  slug: string
  title: string
  description: string
  icon: LucideIcon
  dateMode: ReportDateMode
  /** Shown on the index card. Keeps "what is actually new here" visible. */
  isNew?: boolean
}

export interface RestaurantReportGroup {
  key: string
  label: string
  /** Tailwind background class for the group's icon chip. */
  color: string
  reports: RestaurantReport[]
}

/**
 * The catalog as authored. Icons are attached below from a lookup table rather
 * than written on each line, which keeps these entries to the three things that
 * actually differ between reports: what it is called, what it does, and what
 * date control it needs.
 */
type RawReport = Omit<RestaurantReport, "icon">
interface RawGroup { key: string; label: string; color: string; reports: RawReport[] }

const RAW_GROUPS: RawGroup[] = [
  {
    key: "money",
    label: "Money",
    color: "bg-emerald-600",
    reports: [
      { slug: "pnl", title: "Profit & Loss", dateMode: "range", isNew: true,
        description: "Revenue, cost of goods, expenses and net profit for the period" },
      { slug: "sales-summary", title: "Sales Summary", dateMode: "range", isNew: true,
        description: "Every headline sales number for a date range, in one place" },
      { slug: "payment-methods", title: "Payment Methods", dateMode: "range", isNew: true,
        description: "Cash, card and mobile money split, with tips and share of take" },
      { slug: "expenses", title: "Expenses", dateMode: "range", isNew: true,
        description: "Spend by category, supplier and payment method" },
      { slug: "discounts", title: "Discounts & Promotions", dateMode: "range", isNew: true,
        description: "What each discount was actually given away, and on what" },
    ],
  },
  {
    key: "sales",
    label: "Sales",
    color: "bg-rose-600",
    reports: [
      { slug: "daily-sales", title: "Daily Sales", dateMode: "single",
        description: "One day in full — revenue, order types and payment split" },
      { slug: "revenue-trend", title: "Revenue Trend", dateMode: "range",
        description: "Daily revenue and order count across the period" },
      { slug: "top-items", title: "Top Selling Items", dateMode: "range",
        description: "Best sellers by revenue, quantity and order count" },
      { slug: "sales-by-category", title: "Sales by Category", dateMode: "range",
        description: "Revenue and quantity sold per menu category" },
      { slug: "peak-hours", title: "Peak Hours", dateMode: "single",
        description: "Busiest hours of a day by orders and revenue" },
    ],
  },
  {
    key: "menu",
    label: "Menu & Food",
    color: "bg-amber-600",
    reports: [
      { slug: "menu-engineering", title: "Menu Engineering", dateMode: "range", isNew: true,
        description: "Popularity against margin — Stars, Plowhorses, Puzzles and Dogs" },
      { slug: "food-cost", title: "Food Cost", dateMode: "none",
        description: "Recipe cost against selling price, margin and food cost percent" },
      { slug: "waste", title: "Waste", dateMode: "range", isNew: true,
        description: "What was thrown away, why, and what it cost" },
    ],
  },
  {
    key: "operations",
    label: "Operations",
    color: "bg-blue-600",
    reports: [
      { slug: "kitchen-performance", title: "Kitchen Performance", dateMode: "range", isNew: true,
        description: "Queue and cook times per station, and the slowest item on each" },
      { slug: "table-turnover", title: "Table Turnover", dateMode: "range", isNew: true,
        description: "Dwell time, turns per day and revenue per cover, per table" },
      { slug: "waiter-performance", title: "Waiter Performance", dateMode: "range",
        description: "Orders, covers, revenue and average ticket per waiter" },
      { slug: "tips", title: "Tips", dateMode: "range", isNew: true,
        description: "Tips per waiter as an amount and as a percentage of their sales" },
      { slug: "voids", title: "Voids & Cancellations", dateMode: "range", isNew: true,
        description: "Cancelled and refunded orders grouped by the reason given" },
      { slug: "stock-on-hand", title: "Stock on Hand", dateMode: "none", isNew: true,
        description: "Current stock against par and reorder levels, worst first" },
    ],
  },
  {
    key: "guests",
    label: "Guests & Channels",
    color: "bg-violet-600",
    reports: [
      { slug: "customer-retention", title: "Customer Retention", dateMode: "range", isNew: true,
        description: "New against returning guests, repeat rate, visits and spend" },
      { slug: "feedback", title: "Guest Feedback", dateMode: "range", isNew: true,
        description: "Ratings by source, including QR guest ratings" },
      { slug: "delivery-performance", title: "Delivery Performance", dateMode: "range", isNew: true,
        description: "Promised against actual delivery times, per driver" },
      { slug: "channel", title: "Channel Profitability", dateMode: "range", isNew: true,
        description: "What each delivery platform keeps in commission and fees" },
      { slug: "events", title: "Events & Catering", dateMode: "range", isNew: true,
        description: "Booked value, deposits taken and balances still owed" },
    ],
  },
]

/** Icons, kept out of the group literals above so those stay readable. */
const ICONS: Record<string, LucideIcon> = {
  "pnl": Wallet,
  "sales-summary": DollarSign,
  "payment-methods": Coins,
  "expenses": Receipt,
  "discounts": Percent,
  "daily-sales": DollarSign,
  "revenue-trend": TrendingUp,
  "top-items": UtensilsCrossed,
  "sales-by-category": PieChart,
  "peak-hours": Clock,
  "menu-engineering": Soup,
  "food-cost": Utensils,
  "waste": Trash2,
  "kitchen-performance": Timer,
  "table-turnover": Table2,
  "waiter-performance": Users,
  "tips": Coins,
  "voids": Ban,
  "stock-on-hand": Boxes,
  "customer-retention": Heart,
  "feedback": Star,
  "delivery-performance": Truck,
  "channel": Store,
  "events": CalendarDays,
}
export const RESTAURANT_REPORT_GROUPS: RestaurantReportGroup[] = RAW_GROUPS.map((g) => ({
  key: g.key,
  label: g.label,
  color: g.color,
  reports: g.reports.map((r) => ({ ...r, icon: ICONS[r.slug] ?? BarChart3 })),
}))

/** Flat list, in catalog order. */
export const ALL_RESTAURANT_REPORTS: RestaurantReport[] =
  RESTAURANT_REPORT_GROUPS.flatMap((g) => g.reports)

export const TOTAL_RESTAURANT_REPORTS = ALL_RESTAURANT_REPORTS.length

/** Look a report up by slug, with its group, for the router and the nav. */
export function findRestaurantReport(
  slug: string,
): { report: RestaurantReport; group: RestaurantReportGroup } | null {
  for (const g of RESTAURANT_REPORT_GROUPS) {
    const r = g.reports.find((x) => x.slug === slug)
    if (r) return { report: r, group: g }
  }
  return null
}

/**
 * Slugs the old catalog used, mapped to where that report lives now.
 *
 * These are not dead weight. The previous mega-menu shipped `?tab=<slug>` links
 * for all of them, and anyone who bookmarked one -- or any page still holding a
 * stale link -- would otherwise get a 404 on a report that plainly exists. The
 * three period presets map onto the reports that replaced them.
 */
export const LEGACY_SLUG_REDIRECTS: Record<string, string> = {
  "overview": "sales-summary",
  "daily": "daily-sales",
  "trends": "revenue-trend",
  "income": "pnl",
  "items": "top-items",
  "foodcost": "food-cost",
  "categories": "sales-by-category",
  "hours": "peak-hours",
  "servers": "waiter-performance",
  "orders": "sales-summary",
  "daily-report": "daily-sales",
  "weekly-report": "revenue-trend",
  "monthly-report": "revenue-trend",
}
