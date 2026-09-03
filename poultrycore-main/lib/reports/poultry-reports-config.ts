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
  Calculator, Syringe, Pill, ClipboardCheck, ClipboardList, Flag, CalendarDays, Scale,
  History, Factory, Truck, PieChart, Landmark,
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
      { slug: "supplier-balance", title: "Supplier Balance", description: "Supplier payables.", icon: Truck },
    ],
  },
  {
    key: "expenses-cash",
    label: "Expenses & Cash",
    color: "bg-orange-600",
    reports: [
      { slug: "expense-summary", title: "Expense Summary", description: "Farm expenses by category and flock.", icon: Receipt },
      { slug: "cash-movement", title: "Cash Movement", description: "Cash inflows and outflows.", icon: Wallet },
      { slug: "cash-flow-detail", title: "Cash Flow Detail", description: "Where cash came from and what it went on, with analysis.", icon: PieChart },
    ],
  },
  {
    key: "profitability",
    label: "Profitability",
    color: "bg-green-700",
    reports: [
      { slug: "profit-loss", title: "Profit & Loss (Company)", description: "Company-wide revenue, expenses and net profit.", icon: Scale },
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
  /** bg + text pair for the icon tile on the /poultry/reports cards. Twenty-nine
   *  saturated tiles shouted; the tint keeps the accent without the noise. */
  tint: string
  /** One line under the group name on the index card. */
  blurb: string
  items: PoultryReportMenuItem[]
}

/** Catalogue entry -> menu item. Throws on an unknown slug, which surfaces a
 *  bad edit at module load (i.e. at build time) instead of rendering a hole. */
const item = (slug: PoultryReportSlug): PoultryReportMenuItem => {
  const r = POULTRY_REPORT_BY_SLUG[slug]
  if (!r) throw new Error(`poultry-reports-config: no catalogue entry for "${slug}"`)
  return { id: r.slug, title: r.title, description: r.description, icon: r.icon, href: poultryReportHref(r.slug) }
}

/**
 * The display taxonomy — FOUR groups, deliberately coarser than the eight
 * catalogue groups above.
 *
 * The menu used to render the catalogue groups verbatim plus three standalone
 * ones: eleven groups of 3/2/2/5/4/3/1/2/4/1/2. Both surfaces lay groups out
 * side by side, so a third of the catalogue was single-row sections whose
 * heading outweighed their contents, and neither the menu nor the index page
 * had a readable shape. These four merge the stragglers into the section a user
 * would look in anyway:
 *
 *   Inventory (Egg Stock Balance)     -> Production & Eggs
 *   Sales & Customers, Expenses & Cash-> Sales, Money & Profit (+ Closing)
 *   Health (2) + Birds & Mortality    -> Feed, Birds & Health
 *   Activity + Dashboards             -> Overview & Dashboards
 *
 * ORDER is the layout: the Reports mega-menu is four columns, so these four
 * groups are one column each, and Overview & Dashboards sits last.
 *
 * Nothing was dropped: all 29 entries survive the merge. The catalogue above
 * (POULTRY_REPORT_GROUPS) keeps its finer grouping — it's the slug source of
 * truth, not a layout.
 */
export const POULTRY_REPORT_MENU_GROUPS: PoultryReportMenuGroup[] = [
  {
    key: "money",
    label: "Sales, Money & Profit",
    blurb: "Money in, money out, what's left",
    color: "bg-green-700",
    tint: "bg-green-50 text-green-700",
    // Profit & Loss (Company) leads — it's the "how did we do" answer people
    // open this section for — then the two day wrap-ups, widest first: one day
    // in full, then that day's closing. Everything after them still runs in the
    // order the money flows: revenue -> receivables -> costs.
    items: [
      item("profit-loss"),
      // Standalone pages, not /poultry/reports/<slug> reports.
      { id: "daily-business-summary", title: "Daily Business Summary", description: "Full daily snapshot — income, production, purchases, expenses, losses, cash.", icon: BarChart3, href: "/poultry-daily-summary" },
      { id: "closing-report", title: "Closing Report", description: "Every daily closing, with cash reconciliation and approval status.", icon: ClipboardList, href: "/poultry-closing-report-daily" },
      { id: "closing-by-category", title: "Closing by Category", description: "Period totals grouped into financial, production, inventory and birds.", icon: ClipboardCheck, href: "/poultry-closing-report" },
      item("profit-loss-by-flock"),
      item("egg-sales"),
      item("customer-balance"),
      item("supplier-balance"),
      item("expense-summary"),
      item("cash-movement"),
      item("cash-flow-detail"),
      // Standalone (no backend route), so a literal href rather than item():
      // item() demands a catalogue entry, which demands a PoultryReportSlug
      // union member and a POULTRY_REPORT_DEFS record, which demand a server
      // endpoint this report does not need.
      //
      // It sits beside the two above and deliberately disagrees with them. They
      // read business transactions and say what the company earned and spent;
      // this reads the cash-account LEDGER and says where the money sits. The
      // two closing figures are not expected to match -- that gap is what
      // reconciliation exists to explain, and it is not a bug to be fixed.
      { id: "cash-accounts", title: "Cash Account Report", description: "Per-account opening, in, out and closing, with drift and reconciliation status.", icon: Landmark, href: "/poultry/reports/cash-accounts" },
      item("cost-per-egg"),
    ],
  },
  {
    key: "production",
    label: "Production & Eggs",
    blurb: "What the birds laid, and what's in store",
    color: "bg-emerald-600",
    tint: "bg-emerald-50 text-emerald-700",
    items: [
      item("daily-egg-production"),
      item("flock-production-summary"),
      item("hen-day-production"),
      // Standalone client-side report (aggregates production records by flock
      // batch — no backend endpoint), so it carries its own href.
      { id: "batch-production-summary", title: "Batch Production Summary", description: "Production performance rolled up per flock batch.", icon: Boxes, href: "/poultry/reports/batch-production-summary" },
      // Was a one-report "Inventory" group of its own; eggs on hand is the tail
      // end of production, so it lands here.
      item("egg-stock-balance"),
      item("missing-daily-records"),
    ],
  },
  {
    // Feed and Birds & Health were two adjacent groups of 4 and 5. Feed goes in
    // and mortality/medicine come out of the same flock, so they read as one
    // section — and one group of 9 fills a menu column instead of leaving two
    // half-empty ones.
    key: "feed-birds-health",
    label: "Feed, Birds & Health",
    blurb: "Feed, head count, losses, vaccines and medicine",
    color: "bg-yellow-600",
    tint: "bg-yellow-50 text-yellow-700",
    items: [
      item("feed-usage"),
      item("feed-inventory-balance"),
      item("feed-cost-per-egg"),
      // Standalone page (feed produced + ingredient usage with full costing).
      { id: "feed-production-report", title: "Feed Production", description: "Feed produced and ingredient usage, with full costing.", icon: Factory, href: "/poultry-feed-production/reports" },
      item("mortality"),
      item("birds-on-hand"),
      item("end-of-flock"),
      item("vaccination-schedule"),
      item("medicine-usage"),
    ],
  },
  {
    // Last column: the dashboards are where you *land*, not where you look
    // something up, so the report sections come first on both surfaces.
    key: "overview",
    label: "Overview & Dashboards",
    blurb: "The whole farm at a glance",
    color: "bg-blue-600",
    tint: "bg-blue-50 text-blue-700",
    items: [
      // farm-summary is a data-driven report but has no catalogue entry (it's
      // the one slug POULTRY_REPORT_GROUPS doesn't list), so it's spelled out.
      { id: "farm-summary", title: "Poultry Farm Summary", description: "High-level snapshot of the whole farm for the period.", icon: LayoutDashboard, href: poultryReportHref("farm-summary") },
      // The four interactive dashboards. Each opens its own page under
      // /poultry/reports/<view> rather than deep-linking the legacy tabs.
      { id: "production-dashboard", title: "Production Dashboard", description: "Egg production trends, collection times and flock metrics.", icon: Egg, href: "/poultry/reports/production" },
      { id: "financial-dashboard", title: "Financial Dashboard", description: "Revenue, expenses and net profit / loss.", icon: Wallet, href: "/poultry/reports/financial" },
      { id: "daily", title: "Daily Report", description: "Daily eggs vs expenses, best and worst days.", icon: CalendarDays, href: "/poultry/reports/daily" },
      { id: "more", title: "More Reports", description: "Sales by product, expense categories and flock performance.", icon: TrendingUp, href: "/poultry/reports/more" },
      // A standalone page, not a /poultry/reports/<slug> report. (Closing Report
      // used to sit here too; it now lives in Sales, Money & Profit.)
      { id: "changes", title: "Changes Report", description: "Every create, update and delete of records — who changed what, and when.", icon: History, href: "/poultry/reports/changes" },
    ],
  },
]
