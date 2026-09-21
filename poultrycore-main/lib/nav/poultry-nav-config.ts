/**
 * Poultry desktop top-nav contents.
 *
 * Same treatment as lib/nav/water-nav-config.ts: nine narrow dropdowns collapse
 * into a handful of wide grouped panels, so related things sit side by side
 * instead of being spread across menus that all look alike.
 *
 * Rail: Dashboard | Quick Links | Operations | Sales, Expenses & Money |
 *       Analytics | Reports | Setup                             -> System
 *
 * NOTE: components/dashboard/sidebar.tsx and mobile-bottom-nav.tsx still carry
 * their own copies of the poultry nav. Changing an item here does NOT change
 * them.
 */

import {
  Activity, AlertTriangle, ArrowLeftRight, Banknote, BarChart3, Bell, Bird, BookOpen, Box, Boxes,
  Building2, Clock, CreditCard, DollarSign, Egg, Factory, FileText, HelpCircle, History, Hourglass,
  Coins, HandCoins, ListTodo, Package, PackageMinus, Pill, Receipt, Scale, Settings, ShoppingCart, Truck, User, UserCog, Users,
  Users2, Wallet, Wheat, TrendingUp,
} from "lucide-react"
import type { UserPermissions } from "@/hooks/use-permissions"
import { isFinancialNavItemVisible } from "@/lib/utils/financial-nav-access"
import type { MegaMenuGroup, NavGroup, NavItem } from "./nav-model"
import { resolveQuickLinks } from "./quick-links"

export interface PoultryNavDeps {
  permissions: UserPermissions
  /** Opens the alerts drawer (useAlertsStore.open). */
  onOpenAlerts: () => void
  alertCount?: number

  /**
   * The user's own Quick Links, from migration 318. Undefined or null means
   * they have never customised -- the defaults below stand. `[]` means they
   * cleared the bar, which is a different answer and must survive as one.
   */
  quickLinkHrefs?: string[] | null
}

export interface PoultryNavConfig {
  /** Stays a narrow single-column dropdown — a shortcut bar, not a menu. */
  quickLinks: NavGroup
  operations: MegaMenuGroup[]
  salesMoney: MegaMenuGroup[]
  analytics: MegaMenuGroup[]
  setup: MegaMenuGroup[]
  /** Right-hand panel. Mirrors the sidebar's bottom "System" group. */
  system: MegaMenuGroup[]
}

export function buildPoultryNavConfig(
  { permissions, onOpenAlerts, alertCount, quickLinkHrefs }: PoultryNavDeps,
): PoultryNavConfig {
  const { featureAccess, isAdmin } = permissions
  const canSeeStaff = isAdmin || featureAccess.canSeeEmployees

  // The financial allow-list is default-deny and keyed on href, so it has to
  // follow each row wherever it lands. tempShowPayments matches what the
  // sidebar passes — the old top nav omitted it, which hid /billing here while
  // showing it in the sidebar for the same user.
  const money = (href: string) =>
    isFinancialNavItemVisible(href, featureAccess, isAdmin, { tempShowPayments: true })

  const config: PoultryNavConfig = {
    quickLinks: {
      label: "Quick Links",
      // WHAT EARNS A PLACE HERE: a page the farm opens most days.
      //
      // Not "everything important" -- a shortcut list containing everything is
      // not a shortcut, it is a second copy of the rail, and the thing you
      // actually wanted stops being findable. Weekly and monthly work
      // (deliveries, stock, payroll, the report catalogue) stays one click away
      // in its own group, which is where someone looking for it goes.
      //
      // Ordered by the shape of a day: record what was produced and what went
      // into it, record what was sold and collected and who still owes, record
      // what was spent, check where the money actually stands, then close the
      // day.
      //
      // THE LAST THREE ARE VIEWS, NOT ENTRY SCREENS. Customer Balances, Cash
      // Flow and Profit & Loss record nothing -- they are here because they
      // are what an owner opens to ask "where are we?", which is a daily
      // question even though none of them is a daily task. They sit after the
      // rows that put the numbers there, so the list still reads in the order
      // the work happens.
      //
      // AND GATED, which it was not before. Quick Links carries pages that are
      // permission-checked in their own groups -- /sales has been money()-gated
      // in the Sales column for as long as it has been here, and Payments and
      // Expenses are too. Returning this list unfiltered made the shortcut a
      // way AROUND the permission: a staff member denied Sales in the rail
      // could still reach it from here. The water rail already filters its
      // quick links; this brings poultry into line.
      //
      // Only the financial rows carry a gate. money() is a default-DENY
      // allow-list, so running the production rows through it would hide
      // Production Records and Feed Usage from everyone.
      items: ([
        { href: "/production-records",    label: "Production Records", icon: Factory },
        { href: "/egg-production",        label: "Egg sorting",        icon: Egg },
        // Ungated, like the production rows above it and like its own row in
        // Operations > Purchase. money() is a default-DENY allow-list, so
        // sending a non-financial page through it hides it from everyone.
        //
        // "Raw Materials", not the full "Raw Materials & Supplies" it carries in
        // Operations: NavDropdown's panel is a fixed w-52 (208px) and its rows
        // do not truncate, so the full name is the one label here that wraps to
        // a second line. Same page, and the shortcut bar does not need the
        // qualifier to be unambiguous.
        { href: "/poultry-raw-materials", label: "Raw Materials",       icon: Box },
        { href: "/sales",                 label: "Sales",              icon: ShoppingCart,
          visible: money("/sales") },
        { href: "/poultry-payments",      label: "Payments received",  icon: Wallet,
          visible: money("/poultry-payments") },
        { href: "/customer-balances",     label: "Customer Balances",  icon: Users,
          visible: money("/customer-balances") },
        { href: "/expenses",              label: "Expenses",           icon: DollarSign,
          visible: money("/expenses") },
        { href: "/cash-flow",             label: "Cash Flow",          icon: Wallet,
          visible: money("/cash-flow") },
        // The Money-page skin, NOT the report route: this row is beside Cash
        // Flow and Expenses, and a report's back button on it would offer to
        // return you to a catalogue you never opened.
        { href: "/poultry-profit-loss", label: "Profit & Loss", icon: TrendingUp,
          visible: money("/poultry-profit-loss") },
        { href: "/poultry-daily-closing", label: "Daily Closing",      icon: FileText },
      ] as (NavItem & { visible?: boolean })[])
        .filter((i) => i.visible !== false)
        .map(({ visible, ...item }) => item),
    },

    operations: [
      {
        key: "production",
        label: "Production",
        items: [
          { id: "production-records", title: "Production Records", icon: FileText, href: "/production-records" },
          { id: "batch-production",   title: "Batch Production",   icon: Boxes,    href: "/batch-production-records" },
          { id: "egg-sorting",        title: "Egg sorting",        icon: Egg,      href: "/egg-production" },
          { id: "feed-usage",         title: "Feed Usage",         icon: Package,  href: "/feed-usage" },
          // Producing finished feed from ingredients is a production activity.
          // The formula behind it is a recipe you maintain, so it lives in
          // Setup > Production with Products.
          { id: "feed-production", title: "Feed Production", icon: Factory, href: "/poultry-feed-production", visible: featureAccess.canViewFeedProduction },
        ],
      },
      // Group ORDER is load-bearing in the 2x2 grid: each row is as tall as its
      // tallest group, so pairing the two long groups (Production 5, Inventory
      // 7) in row 1 and the two short ones (Delivery 2, Farm 1) in row 2 keeps
      // the panel clear of max-h-[70vh] without scrolling. Reordering these will
      // bring the scrollbar back.
      {
        key: "inventory-health",
        label: "Inventory & Health",
        items: [
          { id: "inventory",      title: "Inventory",                 icon: Boxes,         href: "/poultry-inventory" },
          { id: "stock",          title: "Stock movements",           icon: Boxes,         href: "/poultry-stock" },
          { id: "raw-materials",  title: "Raw Materials & Supplies",  icon: Box,           href: "/poultry-raw-materials" },
          // Supplies and Other Inventory are hidden rather than deleted: the
          // pages still exist and still work by URL, and their rows are one
          // uncomment away if the farm wants them back. Both overlapped what
          // Raw Materials & Supplies and Inventory above already cover.
          // { id: "supplies",       title: "Supplies",                  icon: ShoppingCart,  href: "/supplies" },
          { id: "health",         title: "Health Records",            icon: AlertTriangle, href: "/health" },
          // Internal Use moved to Sales, Expenses & Money > Expenses. Stock
          // taken for the farm's own use is a COST, not a stock count -- it is
          // read beside the other outflows, not beside what is on the shelf.
          { id: "loss-records",   title: "Loss & Damage",             icon: AlertTriangle, href: "/poultry-loss-records" },
          // { id: "other-inventory", title: "Other Inventory",          icon: Package,       href: "/inventory" },
        ],
      },
      {
        key: "delivery",
        label: "Delivery",
        items: [
          // Drivers, Vehicles and Routes are records you maintain — they live
          // in Setup > Delivery. What's left here is the daily run and its
          // reconciliation.
          { id: "deliveries",    title: "Deliveries",    icon: Truck,     href: "/poultry-driver-returns" },
          { id: "driver-report", title: "Driver report", icon: BarChart3, href: "/poultry-driver-report" },
        ],
      },
      {
        key: "farm",
        // "Purchase", not "Farm": Houses and Flock Groups moved to Setup > Farm,
        // so all that's left in this group is the purchase transaction itself.
        label: "Purchase",
        items: [
          // Houses and Flock Groups are master data you maintain, not a daily
          // activity — they live in Setup > Farm. What's left here is the
          // purchase transaction that brings birds onto the farm.
          { id: "flock-batch", title: "Flock Purchases (Batches)", icon: Boxes, href: "/flock-batch" },
          // Deep link that opens the Raw Materials purchase dialog straight
          // away (?purchase=1 is handled in app/poultry-raw-materials/page.tsx)
          // — buying feed/packaging/medication is the other purchase people do
          // daily, and it was only reachable from inside that page.
          { id: "record-purchase", title: "Record Purchase", icon: ShoppingCart, href: "/poultry-raw-materials?purchase=1" },
        ],
      },
    ],

    // Three columns split by direction of the money: what comes IN (Sales),
    // what goes OUT (Expenses), and where the cash itself sits (Money).
    salesMoney: [
      {
        key: "sales",
        label: "Sales",
        items: [
          { id: "sales",    title: "Sales",             icon: ShoppingCart, href: "/sales",            visible: money("/sales") },
          { id: "payments", title: "Payments",          icon: Wallet,       href: "/poultry-payments", visible: money("/poultry-payments") },
          // "Who owes us what" — the collections control centre, so it belongs
          // with the money coming in rather than with the cash accounts.
          { id: "customer-balances", title: "Customer Balances", icon: Users, href: "/customer-balances", visible: money("/customer-balances") },
        ],
      },
      {
        key: "expenses",
        label: "Expenses",
        items: [
          { id: "expenses",      title: "Expenses",     icon: DollarSign, href: "/expenses",               visible: money("/expenses") },
          // Moved here from Operations > Inventory & Health. Stock the farm
          // consumes itself is money going out in kind -- it belongs with the
          // outflows it is, rather than with the stock counts it is measured
          // from. Ungated, exactly as it was in its old home, so nobody loses
          // access to a page they can reach today.
          { id: "internal-use",  title: "Internal Use", icon: PackageMinus, href: "/poultry-internal-use" },
          // Payroll is money going out, so it sits with the other outflows
          // rather than with staff master data in Setup > People. It is also the
          // one ungated row here, which keeps this column from ever vanishing.
          { id: "payroll",       title: "Payroll",      icon: Banknote,   href: "/poultry-payroll" },
          // Directly below Payroll, because payroll deduction is how most
          // advances are repaid -- but the page stands on its own: an advance
          // can equally be repaid in cash, and exists whether or not the
          // worker is on any payroll run. Migrations 305/306.
          { id: "employee-loans", title: "Employee Loans & Advances", icon: HandCoins, href: "/poultry-employee-loans", visible: money("/poultry-employee-loans") },
          // The payables mirror of the two Sales rows: what we owe, and what
          // we've paid against it.
          { id: "supplier-payments", title: "Supplier Payments", icon: Receipt, href: "/supplier-payments", visible: money("/supplier-payments") },
          { id: "supplier-balances", title: "Supplier Balances", icon: Truck, href: "/supplier-balances", visible: money("/supplier-balances") },
          // Migration 288. Sits with Expenses because that is what it is about:
          // stock cost that has NOT become an expense yet. It is deliberately
          // not under Inventory -- an owner asking "why is my feed bill low
          // this month" looks here, beside the expenses it explains.
          //
          // "Deferred inventory cost" is now the name everywhere -- the page's
          // own heading and the inventory card people click to get here.
          { id: "deferred-inventory-costs", title: "Deferred inventory cost", icon: Hourglass, href: "/poultry-deferred-costs", visible: money("/poultry-deferred-costs") },
          // Migrations 270-273. Assets sit in the Expenses column because that
          // is where a major purchase is recorded from -- a farm buying a
          // generator looks here, not in a separate "capital" menu -- but they
          // are deliberately NOT expenses, which the page says on every screen.
          // Gated on its OWN href now that financial-nav-access.ts names it;
          // it used to borrow "/expenses", which the sidebar could not copy.
          //
          // "Capital Investments/Assets" carries both names because the page is
          // filed under one and talked about as the other. It is the widest
          // label in this menu, so the Expenses column (and the panel width in
          // top-nav) is sized to it; see the width note on the NavMegaMenu.
          { id: "assets", title: "Capital Investments/Assets", icon: Building2, href: "/poultry-assets", visible: money("/poultry-assets") },
        ],
      },
      {
        key: "money",
        label: "Money",
        items: [
          { id: "cash-flow",     title: "Cash Flow",    icon: Wallet,     href: "/cash-flow",              visible: money("/cash-flow") },
          // Between the two on purpose: it is the bridge between them, and it
          // reads the same functions both of them read.
          { id: "financial-activity", title: "Financial Activity", icon: Activity, href: "/poultry-financial-activity", visible: money("/poultry-financial-activity") },
          // The same STATEMENT as Reports > Profit & Loss, in the Money frame.
          // Surfaced beside Cash Flow because the two answer the pair of
          // questions owners ask together: what did we earn, and where did the
          // money go.
          { id: "profit-loss",   title: "Profit & Loss", icon: TrendingUp, href: "/poultry-profit-loss", visible: money("/poultry-profit-loss") },
          // The pre-cash-account page. HIDDEN from the menu: it counts EVERY
          // sale and expense while Cash Flow counts only what was linked to a
          // cash account, and two rows one above the other showing different
          // totals for "cash" was the question owners kept asking. The route
          // still works for anyone holding a link -- only the menu row is gone.
          // { id: "cash",       title: "Cash",         icon: History,   href: "/cash",                   visible: money("/cash") },
          // Migrations 253-254. Where money comes FROM when it is neither a
          // sale nor an expense: the owner's own funding, then borrowed money.
          { id: "owner-money",    title: "Owner Money",    icon: Banknote,       href: "/poultry-owner-money",    visible: money("/poultry-owner-money") },
          // "(Financing)" because borrowed money is neither income nor an
          // expense -- it is a financing movement. The bracket says so in the
          // menu, where an owner decides what to click, rather than only inside
          // the page once they are already there.
          { id: "loans",          title: "Loans (Financing)", icon: HandCoins,   href: "/poultry-loans",          visible: money("/poultry-loans") },
          // The accounts themselves, and the two things you do TO them, kept
          // together at the foot of the column: where the money sits, moving it
          // between our own accounts (252), and counting it against the system.
          { id: "cash-accounts", title: "Cash Account", icon: Wallet,     href: "/poultry-cash-accounts",  visible: money("/poultry-cash-accounts") },
          { id: "cash-transfers", title: "Cash Transfers", icon: ArrowLeftRight, href: "/poultry-cash-transfers", visible: money("/poultry-cash-transfers") },
          { id: "cash-reconciliation", title: "Reconciliation", icon: Scale, href: "/poultry-cash-reconciliation", visible: money("/poultry-cash-reconciliation") },
        ],
      },
    ],

    analytics: [
      {
        key: "trackers",
        label: "Trackers",
        // Row ORDER is the order the user asked for, not a derived one: what
        // the farm looks at daily comes first (eggs, feed, then feed stock),
        // then the birds and their medication, then the Analytical Report.
        // Ingredients only tracker trails the group -- it is the mill's own view,
        // consulted far less often than the three above it.
        items: [
          { id: "egg-tracker",        title: "Egg tracker",        icon: BarChart3, href: "/egg-tracker" },
          { id: "feed-tracker",       title: "Feed tracker",       icon: Wheat,     href: "/feed-tracker" },
          { id: "feed-inventory-tracker", title: "Feed inventory tracker", icon: History, href: "/feed-inventory-tracker" },
          { id: "birds-left",         title: "Birds tracker",      icon: Bird,      href: "/birds-left-tracker" },
          { id: "medication-tracker", title: "Medication tracker", icon: Pill,      href: "/medication-tracker" },
          { id: "weekly-report",      title: "Analytical Report",  icon: FileText,  href: "/weekly-report" },
          { id: "feed-ingredient-tracker", title: "Ingredients only tracker", icon: Wheat, href: "/feed-ingredient-tracker" },
        ],
      },
    ],

    setup: [
      {
        key: "company",
        label: "Company",
        items: [
          // Points at the real setup page rather than /settings, which is now
          // only a redirect. Matches Water's "Company Setup" row.
          { id: "farm-setup", title: "Farm Setup",    icon: Settings, href: "/poultry-setup",         visible: featureAccess.canViewSettings },
          { id: "settings",   title: "Company Setup", icon: Settings, href: "/poultry-company-setup", visible: featureAccess.canViewSettings },
          // Migrations 261-263. Sits with the other setup rows because it is
          // configuration, but it is a FINANCE decision -- it changes what the
          // owner reads as profit -- so it rides canViewFinancial rather than
          // canViewSettings. Its own IAM keys gate what you can do once inside.
          { id: "financial-settings", title: "Financial Settings", icon: Coins, href: "/poultry-financial-settings", visible: featureAccess.canViewFinancial },
          // Ungated, so this column (and the Setup trigger) always renders.
          { id: "companies",  title: "Companies", icon: Building2, href: "/companies" },
        ],
      },
      // Group ORDER is load-bearing: the panel is a 3-column grid filled row by
      // row, so these six groups read as two rows --
      //   Company | Delivery | Production   (the operating chain)
      //   Finance | Farm     | People
      // Reordering here silently reshuffles the panel; keep the pairs of three
      // together, and keep `columns={3}` on the Setup NavMegaMenu in
      // components/dashboard/top-nav.tsx in step with it.
      {
        key: "delivery-setup",
        label: "Delivery",
        items: [
          { id: "drivers",  title: "Drivers",  icon: Users2, href: "/poultry-drivers" },
          { id: "vehicles", title: "Vehicles", icon: Truck,  href: "/poultry-vehicles" },
          { id: "routes",   title: "Routes",   icon: Truck,  href: "/poultry-routes" },
        ],
      },
      {
        key: "production-setup",
        label: "Production",
        items: [
          // Products is ungated, which keeps this column — and the Setup
          // trigger — from ever disappearing.
          { id: "products",      title: "Products",      icon: Package, href: "/poultry-products" },
          { id: "feed-formulas", title: "Feed Formulas", icon: Wheat,   href: "/poultry-feed-formulas", visible: featureAccess.canViewFeedProduction },
          // A farm-level schedule that production records key off, so it sits
          // with the other production master data rather than under Company.
          { id: "egg-picks",     title: "Egg Pick Times", icon: Clock,  href: "/business-office/egg-pick-settings", visible: isAdmin },
        ],
      },
      {
        // Customers and Suppliers are master data maintained here, not part of
        // the day's selling flow — but they're the two trading parties every
        // receivable and payable hangs off, so they get their own Finance group
        // rather than sitting under Company. Both rows are money()-gated, so
        // this group drops out for a user without financial access; that's safe
        // because Company is ungated.
        key: "finance",
        label: "Finance",
        items: [
          { id: "customers", title: "Customers", icon: Users, href: "/customers", visible: money("/customers") },
          { id: "suppliers", title: "Suppliers", icon: Truck, href: "/suppliers", visible: money("/suppliers") },
        ],
      },
      {
        key: "farm",
        label: "Farm",
        items: [
          { id: "houses", title: "Houses",       icon: Building2, href: "/houses" },
          { id: "flocks", title: "Flock Groups", icon: Bird,      href: "/flocks" },
        ],
      },
      {
        key: "people",
        label: "People",
        items: [
          { id: "staff",     title: "Staff",               icon: Users2,  href: "/poultry-staff", visible: canSeeStaff },
          { id: "employees", title: "Users & Permissions", icon: UserCog, href: "/employees",     visible: canSeeStaff },
        ],
      },
    ],

    system: [
      {
        key: "system",
        label: "Your account",
        items: [
          // Hidden to match the water rail — the header avatar still opens
          // /profile. Flip `visible` to bring the row back.
          { id: "profile",     title: "Account",             icon: User,       href: "/profile", visible: false },
          { id: "alerts",      title: "Alerts",              icon: Bell,       onClick: onOpenAlerts, badge: alertCount },
          // Subscription billing is the account's own, not the company's
          // trading money. Same gate it had in the Money column.
          { id: "billing",     title: "Billing",             icon: CreditCard, href: "/billing", visible: money("/billing") },
          { id: "audit-logs",  title: "Activity Log",        icon: Activity,   href: "/audit-logs", visible: featureAccess.canViewActivityLog },
          { id: "resources",   title: "Resources",           icon: BookOpen,   href: "/resources" },
          { id: "help",        title: "Help Center",         icon: HelpCircle, href: "/help" },
          { id: "terms",       title: "Terms & Conditions",  icon: ListTodo,   href: "/terms" },
        ],
      },
    ],
  }

  // LAST, over the finished config. resolveQuickLinks resolves the stored
  // hrefs against THIS object, whose rows have already been permission-gated,
  // so a pinned page the user may not see is dropped rather than revealed. See
  // lib/nav/quick-links.ts.
  return {
    ...config,
    quickLinks: { ...config.quickLinks, items: resolveQuickLinks(config, quickLinkHrefs) },
  }
}
