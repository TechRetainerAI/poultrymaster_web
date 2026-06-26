// =============================================================================
// Advanced Poultry Reports — catalogue (for the landing page + sidebar).
//
// Grouped under the heading "Advanced Poultry Reports". Brand-new and additive;
// does not change the existing /reports poultry dashboard, water-reports or
// generic-reports catalogues.
// =============================================================================

import type { LucideIcon } from "lucide-react"
import {
  LayoutDashboard, Egg, BarChart3, Activity, HeartPulse, Bird, Skull,
  Wheat, Package, Boxes, Coins, Users, Receipt, Wallet, TrendingUp,
  Calculator, Syringe, Pill, ClipboardCheck, Flag, CalendarDays,
} from "lucide-react"
import type { PoultryReportSlug } from "@/lib/api/poultry-reports"

export interface PoultryReportCatalogItem {
  slug: PoultryReportSlug
  title: string
  description: string
  icon: LucideIcon
}

export interface PoultryReportGroup {
  key: string
  label: string
  color: string // Tailwind bg-* used for the icon tile
  reports: PoultryReportCatalogItem[]
}

export const poultryReportHref = (slug: PoultryReportSlug) => `/poultry/reports/${slug}`

export const POULTRY_REPORT_GROUPS: PoultryReportGroup[] = [
  {
    key: "executive",
    label: "Executive",
    color: "bg-amber-600",
    reports: [
      { slug: "farm-summary", title: "Poultry Farm Summary", description: "High-level snapshot of the whole farm for the period.", icon: LayoutDashboard },
    ],
  },
  {
    key: "production",
    label: "Production",
    color: "bg-emerald-600",
    reports: [
      { slug: "daily-egg-production", title: "Daily Egg Production", description: "Eggs by day and flock, with collection times.", icon: Egg },
      { slug: "flock-production-summary", title: "Flock Production Summary", description: "Compare production performance across flocks.", icon: BarChart3 },
      { slug: "hen-day-production", title: "Hen-Day Production", description: "Production relative to live birds.", icon: Activity },
      { slug: "missing-daily-records", title: "Missing Daily Records", description: "Active flocks missing required daily records.", icon: ClipboardCheck },
    ],
  },
  {
    key: "birds-mortality",
    label: "Birds & Mortality",
    color: "bg-rose-600",
    reports: [
      { slug: "mortality", title: "Mortality", description: "Deaths and mortality percentages.", icon: Skull },
      { slug: "birds-on-hand", title: "Birds on Hand", description: "Current bird count and reconciliation.", icon: Bird },
      { slug: "end-of-flock", title: "End-of-Flock", description: "Final lifecycle performance per flock.", icon: Flag },
    ],
  },
  {
    key: "feed",
    label: "Feed",
    color: "bg-yellow-600",
    reports: [
      { slug: "feed-usage", title: "Feed Usage", description: "Feed consumed by flock, date and type.", icon: Wheat },
      { slug: "feed-inventory-balance", title: "Feed Inventory Balance", description: "Current feed stock and days remaining.", icon: Package },
      { slug: "feed-cost-per-egg", title: "Feed Cost Per Egg", description: "How feed cost relates to egg production.", icon: Calculator },
    ],
  },
  {
    key: "inventory",
    label: "Inventory",
    color: "bg-sky-600",
    reports: [
      { slug: "egg-stock-balance", title: "Egg Stock Balance", description: "Egg inventory on hand, in eggs and crates.", icon: Boxes },
    ],
  },
  {
    key: "sales-customers",
    label: "Sales & Customers",
    color: "bg-indigo-600",
    reports: [
      { slug: "egg-sales", title: "Egg Sales", description: "Sales by date, customer and product.", icon: Coins },
      { slug: "customer-balance", title: "Customer Balance", description: "Customer receivables.", icon: Users },
    ],
  },
  {
    key: "expenses-cash",
    label: "Expenses & Cash",
    color: "bg-orange-600",
    reports: [
      { slug: "expense-summary", title: "Expense Summary", description: "Farm expenses by category and flock.", icon: Receipt },
      { slug: "cash-movement", title: "Cash Movement", description: "Cash inflows and outflows.", icon: Wallet },
    ],
  },
  {
    key: "profitability",
    label: "Profitability",
    color: "bg-green-700",
    reports: [
      { slug: "profit-loss-by-flock", title: "Profit & Loss by Flock", description: "Revenue, expenses and profit per flock.", icon: TrendingUp },
      { slug: "cost-per-egg", title: "Cost Per Egg", description: "Total allocated cost per egg.", icon: Calculator },
    ],
  },
  {
    key: "health",
    label: "Health",
    color: "bg-teal-600",
    reports: [
      { slug: "vaccination-schedule", title: "Vaccination Schedule", description: "Recorded and upcoming vaccinations.", icon: Syringe },
      { slug: "medicine-usage", title: "Medicine Usage", description: "Medicines used by flock and date.", icon: Pill },
    ],
  },
]

/** Flat lookup of every catalogue item by slug. */
export const POULTRY_REPORT_BY_SLUG: Record<string, PoultryReportCatalogItem> =
  Object.fromEntries(POULTRY_REPORT_GROUPS.flatMap((g) => g.reports.map((r) => [r.slug, r])))

// -----------------------------------------------------------------------------
// Unified menu groups (used by the top-nav mega-menu AND the /poultry/reports
// catalogue). This prepends the classic /reports dashboard tabs as a "Farm
// Dashboards" group, then the 20 advanced reports — each item carries a ready
// `href` so callers don't special-case the two kinds.
// -----------------------------------------------------------------------------
export interface PoultryReportMenuItem {
  id: string
  title: string
  description: string
  icon: LucideIcon
  href: string
}

export interface PoultryReportMenuGroup {
  key: string
  label: string
  color: string
  items: PoultryReportMenuItem[]
}

/**
 * The four farm dashboards. Each now opens its own dedicated page under
 * /poultry/reports/<view> (so they behave like the other advanced reports —
 * own URL, header and back button) instead of deep-linking into the legacy
 * /reports tab dashboard.
 */
export const POULTRY_DASHBOARD_GROUP: PoultryReportMenuGroup = {
  key: "dashboards",
  label: "Farm Dashboards",
  color: "bg-blue-600",
  items: [
    { id: "production", title: "Production", description: "Egg production trends, collection times and flock metrics.", icon: Egg, href: "/poultry/reports/production" },
    { id: "financial", title: "Financial", description: "Revenue, expenses and net profit / loss.", icon: Wallet, href: "/poultry/reports/financial" },
    { id: "daily", title: "Daily Report", description: "Daily eggs vs expenses, best and worst days.", icon: CalendarDays, href: "/poultry/reports/daily" },
    { id: "more", title: "More Reports", description: "Sales by product, expense categories and flock performance.", icon: TrendingUp, href: "/poultry/reports/more" },
  ],
}

export const POULTRY_REPORT_MENU_GROUPS: PoultryReportMenuGroup[] = [
  POULTRY_DASHBOARD_GROUP,
  ...POULTRY_REPORT_GROUPS.map((g) => ({
    key: g.key,
    label: g.label,
    color: g.color,
    items: g.reports.map((r) => ({
      id: r.slug,
      title: r.title,
      description: r.description,
      icon: r.icon,
      href: poultryReportHref(r.slug),
    })),
  })),
]
