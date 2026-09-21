/**
 * Water desktop top-nav contents.
 *
 * The rail is deliberately short — Dashboard, Quick Links, and four grouped
 * panels — because nine near-identical narrow dropdowns made users hunt for
 * items. Related things now sit side by side inside one wide panel, the way the
 * Reports menu already worked.
 *
 * A builder taking deps (rather than a bare const) so the sidebar can adopt it
 * later: the signature spells out exactly what a consumer has to supply.
 *
 * NOTE: components/dashboard/sidebar.tsx and mobile-bottom-nav.tsx still carry
 * their own copies of the water nav. Changing an item here does NOT change them.
 */

import {
  Activity, AlertTriangle, Banknote, BarChart3, Bell, Boxes, Box, Building2,
  CalendarDays, Cog, Coins, CreditCard, Droplets, FileText, Factory, ListTodo, PackageMinus, Receipt,
  Route as RouteIcon, Settings, ShoppingBag, ShoppingCart, Truck, User, UserCog,
  Users, Users2, Wallet, Wrench, History, Hourglass, Scale, ArrowLeftRight, HandCoins, TrendingUp,
} from "lucide-react"
import type { UserPermissions } from "@/hooks/use-permissions"
import { isWaterNavItemVisible } from "@/lib/utils/water-nav-access"
import type { MegaMenuGroup, NavGroup } from "./nav-model"
import { resolveQuickLinks } from "./quick-links"

export interface WaterNavDeps {
  permissions: UserPermissions
  /** Opens the alerts drawer (useAlertsStore.open). */
  onOpenAlerts: () => void
  /** Badge count on the Alerts row. Currently always 0 — nothing in the app
   *  calls useAlertsStore.setAlerts yet, and only the poultry dashboard mounts
   *  the dialog, so on water pages this row opens nothing for the moment. */
  alertCount?: number
  /**
   * The user's own Quick Links, from migration 318. Undefined or null means
   * they have never customised -- the defaults below stand. `[]` means they
   * cleared the bar, which is a different answer and must survive as one.
   */
  quickLinkHrefs?: string[] | null
}

export interface WaterNavConfig {
  /** Stays a narrow single-column dropdown — it's a 4-item shortcut bar. */
  quickLinks: NavGroup
  operations: MegaMenuGroup[]
  salesMoney: MegaMenuGroup[]
  /**
   * Tools you explore on screen, as opposed to Reports which print a period.
   * Analytics has no landing page of its own — this menu IS the index, so every
   * row links straight to a tool.
   */
  analytics: MegaMenuGroup[]
  setup: MegaMenuGroup[]
  /** Right-hand panel. Mirrors the sidebar's bottom "System" block. */
  system: MegaMenuGroup[]
}

export function buildWaterNavConfig({ permissions, onOpenAlerts, alertCount, quickLinkHrefs }: WaterNavDeps): WaterNavConfig {
  // Same predicates the sidebar uses, so the two surfaces can't disagree about
  // who sees what. The top nav previously applied no gating at all.
  const canSeeStaff = permissions.isAdmin || permissions.featureAccess.canSeeEmployees
  const canSeeActivityLog = permissions.featureAccess.canViewActivityLog

  /**
   * Staff Page Access gate for a `/water-*` row.
   *
   * Applied as a post-processing pass over the whole config below rather than
   * spelled out row by row: the route -> flag map is the single source of truth
   * (lib/utils/water-nav-access), and a row added here later is gated the moment
   * it appears in that map, with nothing to remember to wire up.
   *
   * `visible` set explicitly on a row still wins — that is how Staff and Account
   * keep their own rules.
   */
  const gate = (href: string | undefined) =>
    href === undefined ? true : isWaterNavItemVisible(href, permissions.featureAccess, permissions.isAdmin)

  const gateGroups = (groups: MegaMenuGroup[]): MegaMenuGroup[] =>
    groups.map((g) => ({
      ...g,
      items: g.items.map((item) => ({ ...item, visible: (item.visible ?? true) && gate(item.href) })),
    }))

  const config: WaterNavConfig = {
    quickLinks: {
      label: "Quick Links",
      // WHAT EARNS A PLACE HERE: a page the company opens most days.
      //
      // Not "everything important" -- a shortcut list containing everything is
      // not a shortcut, it is a second copy of the rail. Weekly and monthly
      // work stays one click away in its own group.
      //
      // Ordered by the shape of a day: produce, deliver, sell, collect, then
      // close. Labels match the ones the rail uses for the same pages -- one
      // page, one name, so the two menus cannot look like two destinations.
      items: [
        { href: "/water-production-batches", label: "Water Production", icon: Factory },
        { href: "/water-daily-production",   label: "Batch Production", icon: CalendarDays },
        { href: "/water-driver-returns",     label: "Deliveries",       icon: Truck },
        { href: "/water-sales",              label: "Sales",            icon: ShoppingCart },
        { href: "/water-payments",           label: "Payments",         icon: CreditCard },
        { href: "/water-expenses",           label: "Expenses",         icon: Receipt },
        { href: "/water-daily-closing",      label: "Daily Closing",    icon: FileText },
      ],
    },

    operations: [
      // Production leads — it's the core of the business, and the panel reads
      // make-it -> move-it -> count-it left to right.
      {
        key: "production",
        label: "Production",
        items: [
          // "Water Production", not "Production": a row called Production
          // inside a column called Production tells the user nothing.
          { id: "production",       title: "Water Production", icon: Factory,      href: "/water-production-batches" },
          { id: "batch-production", title: "Batch Production", icon: CalendarDays, href: "/water-daily-production" },
          // Products, Machines and Boreholes are NOT here — they're records you
          // maintain, not things you run. All three live in Setup > Production.
          { id: "maintenance",      title: "Maintenance",      icon: Wrench,       href: "/water-maintenance" },
        ],
      },
      // Inventory sits in the middle column — it's the tallest group, so the
      // panel reads better with its weight centred than pushed to the edge.
      {
        key: "inventory",
        label: "Inventory",
        items: [
          { id: "stock",             title: "Stock movement",            icon: Boxes,         href: "/water-stock" },
          { id: "inventory",         title: "Inventory",                 icon: Boxes,         href: "/water-inventory" },
          { id: "raw-materials",     title: "Raw materials & supplies",  icon: Box,           href: "/water-raw-materials" },
          // Internal Use moved to Sales, Expenses & Money > Expenses, matching
          // the poultry rail. Stock the company consumes itself is a COST, not
          // a stock count -- and migration 212 records it exactly that way, as
          // an expense row with paymentmethod 'NonCash'. The menu now agrees
          // with the books.
          { id: "loss-records",      title: "Damages & loss",            icon: AlertTriangle, href: "/water-loss-records" },
          { id: "production-losses", title: "Production losses",         icon: AlertTriangle, href: "/water-production-losses" },
        ],
      },
      {
        key: "delivery",
        label: "Delivery",
        items: [
          // Drivers, Vehicles and Routes are records you maintain — they live
          // in Setup > Delivery. What's left here is the daily run and its
          // reconciliation.
          { id: "deliveries",    title: "Deliveries",              icon: Truck,      href: "/water-driver-returns" },
          { id: "driver-report", title: "Driver collection report", icon: BarChart3, href: "/water-driver-report" },
        ],
      },
    ],

    analytics: [
      {
        key: "stock",
        label: "Stock",
        items: [
          { id: "inventory-tracker", title: "Inventory tracker", icon: History, href: "/water-inventory-tracker" },
        ],
      },
    ],

    // Three columns split by direction of the money: what comes IN (Sales),
    // what goes OUT (Expenses), and where the cash itself sits (Money).
    // Mirrors the poultry rail.
    salesMoney: [
      {
        key: "sales",
        label: "Sales",
        items: [
          { id: "sales",    title: "Sales",    icon: ShoppingCart, href: "/water-sales" },
          { id: "payments", title: "Payments", icon: CreditCard,   href: "/water-payments" },
          // "Who owes us what" — the collections control centre, so it belongs
          // with the money coming in rather than with the cash accounts.
          { id: "customer-balances", title: "Customer Balances", icon: Users, href: "/water-customer-balances" },
        ],
      },
      {
        key: "expenses",
        label: "Expenses",
        items: [
          { id: "expenses",      title: "Expenses",        icon: Receipt,  href: "/water-expenses" },
          // Second, right under Expenses itself: the two are the same kind of
          // thing, one paid for in cash and one paid for in stock. Moved here
          // from Operations > Inventory; ungated, exactly as it was there, so
          // nobody loses a page they can reach today.
          { id: "internal-use",  title: "Internal Use",    icon: PackageMinus, href: "/water-internal-use" },
          // Payroll is money going out, so it sits with the other outflows
          // rather than with the staff master data in Setup > People.
          { id: "payroll",       title: "Payroll",         icon: Banknote, href: "/water-payroll" },
          // Directly below Payroll, because payroll deduction is how most
          // advances are repaid -- but the page stands on its own: an advance
          // can equally be repaid in cash, and exists whether or not the
          // worker is on any payroll run. Migrations 313/314.
          { id: "employee-loans", title: "Employee Loans & Advances", icon: HandCoins, href: "/water-employee-loans" },
          // The payables mirror of the two Sales rows: what we owe, and what
          // we've paid against it.
          { id: "supplier-payments", title: "Supplier Payments", icon: Receipt, href: "/water-supplier-payments" },
          { id: "supplier-balances", title: "Supplier Balances", icon: Truck, href: "/water-supplier-balances" },
          // Sits with Expenses because that is what it is about: stock cost
          // that has NOT become an expense yet. It is deliberately not under
          // Inventory -- an owner asking "why is my packaging bill low this
          // month" looks here, beside the expenses it explains.
          //
          // "Deferred inventory cost" is the name everywhere, matching the
          // poultry row and the page's own heading.
          { id: "deferred-inventory-costs", title: "Deferred inventory cost", icon: Hourglass, href: "/water-deferred-costs" },
          // Migrations 283-286. Assets sit in the Expenses column because that
          // is where a major purchase is recorded from -- a company buying a
          // borehole pump looks here, not in a separate "capital" menu -- but
          // they are deliberately NOT expenses, which the page says on every
          // screen.
          // "Capital Investments/Assets" matches the poultry row: the page is
          // filed under one name and talked about as the other.
          { id: "assets", title: "Capital Investments/Assets", icon: Building2, href: "/water-assets" },
        ],
      },
      {
        key: "money",
        label: "Money",
        items: [
          { id: "cash-flow",     title: "Cash Flow",       icon: Wallet,   href: "/water-cash-flow" },
          // The same page as Reports > Profit & Loss, surfaced beside Cash Flow.
          { id: "profit-loss",   title: "Profit & Loss",   icon: TrendingUp, href: "/water-reports/profit-loss" },
          // Migration 258. Owner funding in and out -- financing, never trading.
          { id: "owner-money", title: "Owner Money", icon: HandCoins, href: "/water-owner-money" },
          // Migration 259. Borrowing and repayments.
          { id: "loans", title: "Loans", icon: HandCoins, href: "/water-loans" },
          // The accounts themselves and the two things you do TO them, kept
          // together at the foot of the column, same order as the poultry rail:
          // where the money sits, moving it between our own accounts (257), and
          // counting it against what the system says.
          { id: "cash-accounts", title: "Cash accounts",   icon: Wallet,   href: "/water-cash-accounts" },
          { id: "cash-transfers", title: "Cash Transfers", icon: ArrowLeftRight, href: "/water-cash-transfers" },
          { id: "cash-reconciliation", title: "Reconciliation", icon: Scale, href: "/water-cash-reconciliation" },
        ],
      },
    ],

    // Group ORDER is load-bearing: the panel is a 3-column grid filled row by
    // row, so these six groups read as two rows --
    //   Company | Delivery | Production   (the operating chain)
    //   Finance | Plant    | People
    // exactly mirroring the poultry rail, where Plant is water's counterpart of
    // poultry's "Farm" column (the physical assets, as opposed to the catalogue
    // you sell). Reordering here silently reshuffles the panel; keep the pairs
    // of three together, and keep `columns={3}` on the Setup NavMegaMenu in
    // components/dashboard/top-nav.tsx in step with it.
    setup: [
      {
        key: "company",
        label: "Company",
        items: [
          { id: "setup",         title: "Setup",         icon: Settings,  href: "/water-setup" },
          { id: "company-setup", title: "Company Setup", icon: Settings,  href: "/water-company-setup" },
          // Migrations 274 and 276. Sits with the other setup rows because it is
          // configuration, but it is a FINANCE decision -- it changes what the
          // owner reads as profit -- and its own IAM keys gate what you can do
          // once inside.
          { id: "financial-settings", title: "Financial Settings", icon: Coins, href: "/water-financial-settings" },
          { id: "companies",     title: "Companies",     icon: Building2, href: "/companies" },
        ],
      },
      {
        key: "delivery-setup",
        label: "Delivery",
        items: [
          { id: "drivers",  title: "Drivers",  icon: Users2,    href: "/water-drivers" },
          { id: "vehicles", title: "Vehicles", icon: Truck,     href: "/water-vehicles" },
          { id: "routes",   title: "Routes",   icon: RouteIcon, href: "/water-routes" },
        ],
      },
      {
        key: "production-setup",
        label: "Production",
        // Products is ungated, which keeps this column — and the Setup
        // trigger — from ever disappearing. Machines and Boreholes used to sit
        // here too; they moved to Plant so this column carries the catalogue
        // you sell and nothing else, the way the poultry Production column does.
        items: [
          { id: "products",  title: "Products",  icon: ShoppingBag, href: "/water-products" },
        ],
      },
      {
        // Customers sits beside Suppliers: both are master data maintained
        // here, not part of the day's selling flow — but they're the two
        // trading parties every receivable and payable hangs off, so they get
        // their own Finance column rather than sitting under Company. Mirrors
        // the poultry rail.
        key: "finance",
        label: "Finance",
        items: [
          { id: "customers", title: "Customers", icon: Users, href: "/water-customers" },
          { id: "suppliers", title: "Suppliers", icon: Truck, href: "/water-suppliers" },
        ],
      },
      {
        // The physical plant — the water counterpart of the poultry rail's
        // "Farm" column (Houses / Flock Groups). Equipment and sources, not
        // things you sell.
        key: "plant",
        label: "Plant",
        items: [
          { id: "machines",  title: "Machines",  icon: Cog,      href: "/water-machines" },
          { id: "boreholes", title: "Boreholes", icon: Droplets, href: "/water-boreholes" },
        ],
      },
      {
        key: "people",
        label: "People",
        // Both rows share one gate now that Payroll has moved to Sales & Money,
        // so for a staff user without canSeeEmployees the whole column drops
        // out. That's safe — Company and Production are ungated, so the Setup
        // trigger itself can never disappear and the rail can't reflow.
        items: [
          { id: "staff",     title: "Staff",               icon: UserCog, href: "/water-staff", visible: canSeeStaff },
          { id: "employees", title: "Users & Permissions", icon: UserCog, href: "/employees",   visible: canSeeStaff },
        ],
      },
    ],

    // The sidebar's bottom "System" block: the user's own context, kept on the
    // right of the rail. These rows live ONLY here — Setup is company
    // configuration, System is you. Companies belongs to Setup > Company, not
    // here, because it is a company-level thing.
    system: [
      {
        key: "system",
        label: "Your account",
        items: [
          // Hidden for now (2026-08-07) — flip `visible` back to restore it,
          // and put "account" back in the System blurb in top-nav.tsx.
          { id: "profile",    title: "Account",            icon: User,     href: "/profile", visible: false },
          { id: "alerts",     title: "Alerts",             icon: Bell,     onClick: onOpenAlerts, badge: alertCount },
          // The account's own subscription. It was never in the water nav at
          // all -- only the poultry Money column carried it -- so a water owner
          // had no way to reach their billing from here.
          { id: "billing",    title: "Billing",            icon: CreditCard, href: "/billing" },
          { id: "audit-logs", title: "Activity Log",       icon: Activity, href: "/audit-logs", visible: canSeeActivityLog },
          { id: "terms",      title: "Terms & Conditions", icon: ListTodo, href: "/terms" },
        ],
      },
    ],
  }

  // The gate runs FIRST and the user's choice second, over a gated config --
  // so a pinned page this user may not see is dropped rather than revealed.
  // See lib/nav/quick-links.ts.
  const gated: WaterNavConfig = {
    ...config,
    quickLinks: { ...config.quickLinks, items: config.quickLinks.items.filter((i) => gate(i.href)) },
    operations: gateGroups(config.operations),
    salesMoney: gateGroups(config.salesMoney),
    analytics: gateGroups(config.analytics),
    setup: gateGroups(config.setup),
    // `system` is company-neutral (account, alerts, activity log, terms) — no
    // /water-* route in it, so it carries its own gates unchanged.
    system: config.system,
  }

  return {
    ...gated,
    quickLinks: { ...gated.quickLinks, items: resolveQuickLinks(gated, quickLinkHrefs) },
  }
}
