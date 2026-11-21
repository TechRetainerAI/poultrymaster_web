/**
 * Livestock nav contents (ducks, guinea fowl, rabbits, goats, sheep, pigs,
 * cattle...).
 *
 * Livestock is the Poultry module tree cloned for other animals, so the config
 * has exactly the PoultryNavConfig shape: the sidebar, top nav and mobile nav
 * render it with the same layout as Poultry, only tinted amber.
 *
 * Rows are added here as each /livestock-* page lands. A row is never listed
 * before its page exists.
 *
 * Species gating: the egg, milk and breeding pages only mean something when the
 * company keeps a species with that output. Same rule as Poultry's broiler-only
 * egg hiding: hidden from the menus, but the route still opens.
 */

import { Building2 as CompanyIcon, BarChart3, CalendarDays, Pill as PillIcon, ShoppingBag as SalesIcon, Skull, Wheat, CalendarCheck, CalendarX, Route as RouteIcon, Activity, ArrowLeftRight, Banknote, Building2, Calculator, Landmark, PiggyBank, TrendingUp, Users2, Waves, Baby, Bell, Boxes, ShoppingBag, Users, Receipt, Scale as BalanceIcon, Layers as LayersIcon, ListChecks, PackageMinus, ShoppingCart, Wallet, Scale as ScaleIcon, ClipboardList, CreditCard, Factory, FlaskConical, HeartPulse, HelpCircle, Hourglass, Layers, ListTodo, Package, PawPrint, Pill, Scale, Syringe, Tag, Truck, User, Warehouse } from "lucide-react"
import type { UserPermissions } from "@/hooks/use-permissions"
import { isFinancialNavItemVisible } from "@/lib/utils/financial-nav-access"
import type { MegaMenuGroup } from "./nav-model"
import type { PoultryNavConfig } from "./poultry-nav-config"
import { resolveQuickLinks } from "./quick-links"
import { isSetupAdminRoute } from "@/lib/nav/setup-admin-routes"

export interface LivestockNavDeps {
  permissions: UserPermissions
  onOpenAlerts: () => void
  alertCount?: number
  /** The user's own Quick Links; see PoultryNavDeps.quickLinkHrefs. */
  quickLinkHrefs?: string[] | null
  /** False when no enabled species lays eggs. Undefined = true. */
  showEggFeatures?: boolean
  /** False when no enabled species is milked. Undefined = true. */
  showMilkFeatures?: boolean
  /** False when no enabled species is bred on the farm (births/litters). Undefined = true. */
  showBreedingFeatures?: boolean
}

/** Same shape as Poultry so every nav surface can render either. */
export type LivestockNavConfig = PoultryNavConfig

/** Pages that only mean something when an egg-laying species is kept. */
export const LIVESTOCK_EGG_ONLY_HREFS: ReadonlySet<string> = new Set<string>([])
/** Pages that only mean something when a dairy species is kept. */
export const LIVESTOCK_MILK_ONLY_HREFS: ReadonlySet<string> = new Set<string>([])
/** Pages that only mean something when animals are bred on the farm. */
export const LIVESTOCK_BREEDING_ONLY_HREFS: ReadonlySet<string> = new Set<string>(["/livestock-breeding", "/livestock/reports/breeding"])

export function buildLivestockNavConfig({
  permissions, onOpenAlerts, alertCount, quickLinkHrefs,
  showEggFeatures = true, showMilkFeatures = true, showBreedingFeatures = true,
}: LivestockNavDeps): LivestockNavConfig {
  const { featureAccess, isAdmin } = permissions
  const money = (href: string) =>
    isFinancialNavItemVisible(href, featureAccess, isAdmin, { tempShowPayments: true })

  const config: LivestockNavConfig = {
    quickLinks: {
      label: "Quick Links",
      // Pages a livestock farm opens most days. Grows with each module.
      items: [
        { href: "/livestock-production-records", label: "Daily records", icon: ClipboardList },
        { href: "/livestock-sales",   label: "Sales",           icon: ShoppingBag },
        { href: "/livestock-customer-balances", label: "Customer balances", icon: BalanceIcon },
        { href: "/livestock-daily-closing", label: "Daily closing", icon: CalendarCheck },
        { href: "/livestock-groups",  label: "Animal groups",   icon: Layers },
        { href: "/livestock-animals", label: "Animal register", icon: Tag },
      ],
    },
    // Same four groups as Poultry's Operations panel: the day's work only.
    // Things you maintain (pens, groups, the register, formulas) are in Setup,
    // and the many-group jobs (feed many groups, head count, campaigns,
    // alerts) are in Tools -- as on the poultry side.
    //
    // Group ORDER is load-bearing in the 2x2 grid: the two long groups
    // (Production, Inventory & Health) share row 1 and the two short ones
    // (Delivery, Purchase) row 2, so the panel stays short.
    operations: [
      {
        key: "production",
        label: "Production",
        items: [
          { id: "records",  title: "Daily records",      icon: ClipboardList, href: "/livestock-production-records" },
          { id: "breeding", title: "Breeding & births",  icon: Baby,          href: "/livestock-breeding" },
          { id: "weighins", title: "Weigh-ins & growth", icon: Scale,         href: "/livestock-weigh-ins" },
          // Making feed from ingredients is production, as Poultry's Feed Production.
          { id: "mixing",   title: "Feed mixing",        icon: Factory,       href: "/livestock-feed-production" },
        ],
      },
      {
        key: "inventory-health",
        label: "Inventory & Health",
        items: [
          { id: "items",        title: "Feed & stock",             icon: Boxes,        href: "/livestock-items" },
          // Poultry's Stock movements: opening + in - out = closing per group.
          { id: "animalstock",  title: "Animal stock",             icon: LayersIcon,   href: "/livestock-animal-stock" },
          { id: "health",       title: "Health records",           icon: HeartPulse,   href: "/livestock-health" },
          { id: "vaccinations", title: "Vaccinations & deworming", icon: Syringe,      href: "/livestock-vaccinations" },
          { id: "losses",       title: "Loss & damage",            icon: PackageMinus, href: "/livestock-losses" },
        ],
      },
      {
        key: "delivery",
        label: "Delivery",
        items: [
          { id: "deliveries", title: "Deliveries", icon: Truck, href: "/livestock-deliveries" },
        ],
      },
      {
        key: "purchase",
        label: "Purchase",
        items: [
          // Poultry's "Flock Purchases (Batches)". Also in Setup > Farm, beside
          // the groups they are divided into.
          { id: "batches",         title: "Animal purchases", icon: Package,      href: "/livestock-batches" },
          // Opens the Record purchase dialog on Feed & stock straight away
          // (?purchase=1, handled in app/livestock-items/page.tsx).
          { id: "record-purchase", title: "Record purchase",            icon: ShoppingCart, href: "/livestock-items?purchase=1" },
        ],
      },
    ],
    // Keys MUST be sales / expenses / money: the sidebar builds its Sales,
    // Expenses and Money menus by these keys (renderSalesMoneyMenus) and drops
    // any other group -- the same three groups Poultry uses.
    salesMoney: [
      {
        key: "sales",
        label: "Sales",
        items: [
          { id: "sales",             title: "Sales",             icon: ShoppingBag, href: "/livestock-sales" },
          { id: "customers",         title: "Customers",         icon: Users,       href: "/livestock-customers" },
          { id: "customer-balances", title: "Customer balances", icon: BalanceIcon, href: "/livestock-customer-balances" },
        ],
      },
      {
        key: "expenses",
        label: "Expenses & buying",
        items: [
          { id: "expenses",          title: "Expenses",          icon: Receipt,      href: "/livestock-expenses" },
          { id: "purchases",         title: "Purchases",         icon: ShoppingCart, href: "/livestock-purchases" },
          { id: "suppliers",         title: "Suppliers",         icon: Truck,        href: "/livestock-suppliers" },
          { id: "supplier-balances", title: "Supplier balances", icon: ScaleIcon,    href: "/livestock-supplier-balances" },
          { id: "staff",             title: "Staff",             icon: Users2,       href: "/livestock-staff" },
          { id: "payroll",           title: "Payroll",           icon: Banknote,     href: "/livestock-payroll" },
        ],
      },
      {
        key: "money",
        label: "Money",
        items: [
          { id: "daily-closing", title: "Daily closing",   icon: CalendarCheck,  href: "/livestock-daily-closing" },
          { id: "cash-accounts", title: "Cash accounts",   icon: Wallet,         href: "/livestock-cash-accounts" },
          { id: "transfers",     title: "Move money",      icon: ArrowLeftRight, href: "/livestock-cash-transfers" },
          { id: "count",         title: "Count the money", icon: Calculator,     href: "/livestock-cash-reconciliation" },
          { id: "owner",         title: "Owner money",     icon: PiggyBank,      href: "/livestock-owner-money" },
          { id: "loans",         title: "Loans",           icon: Landmark,       href: "/livestock-loans" },
          { id: "assets",        title: "Assets",          icon: Building2,      href: "/livestock-assets" },
          { id: "profit-loss",   title: "Profit & loss",   icon: TrendingUp,     href: "/livestock-profit-loss" },
          { id: "cash-flow",     title: "Cash flow",       icon: Waves,          href: "/livestock-cash-flow" },
        ],
      },
    ],
    analytics: [
      {
        key: "reports",
        label: "Reports",
        items: [
          { id: "all-reports", title: "All reports",      icon: BarChart3,    href: "/livestock/reports" },
          { id: "trackers",    title: "Monthly trackers", icon: CalendarDays, href: "/livestock-trackers" },
          { id: "production-report", title: "Production", icon: ClipboardList, href: "/livestock/reports/production" },
          { id: "mortality-report",  title: "Deaths & culls", icon: Skull,    href: "/livestock/reports/mortality" },
          { id: "breeding-report",   title: "Births & litters", icon: Baby,   href: "/livestock/reports/breeding" },
          { id: "herd-report",       title: "Herd make-up", icon: PawPrint,   href: "/livestock/reports/herd" },
          { id: "group-summary",     title: "Group summary", icon: Layers,    href: "/livestock/reports/group-summary" },
        ],
      },
      {
        key: "usage",
        label: "Feed, health & sales",
        items: [
          { id: "feed-report",     title: "Feed used",     icon: Wheat,      href: "/livestock/reports/feed" },
          { id: "medicine-report", title: "Medicine used", icon: PillIcon,   href: "/livestock/reports/medicine" },
          { id: "sales-report",    title: "Sales",         icon: SalesIcon,  href: "/livestock/reports/sales" },
        ],
      },
    ],
    // Group ORDER is load-bearing: a 2-column grid filled row by row, with
    // Farm taking two rows --
    //   Farm     | Production
    //   (Farm)   | Company
    //   Delivery |
    // Keep columns={2} on the livestock Setup menu in top-nav.tsx and
    // sidebar.tsx in step with it.
    setup: [
      {
        // Poultry's Setup > Farm (Houses, Flock Groups, Batches).
        key: "farm",
        label: "Farm",
        // Takes two rows, so Company sits right under Production.
        rowSpan: 2,
        items: [
          { id: "pens",          title: "Pens",                       icon: Warehouse, href: "/livestock-pens" },
          { id: "groups",        title: "Animal groups",              icon: Layers,    href: "/livestock-groups" },
          { id: "animals",       title: "Animal register",            icon: Tag,       href: "/livestock-animals" },
          { id: "batches-setup", title: "Animal purchases", icon: Package,   href: "/livestock-batches" },
        ],
      },
      {
        key: "production-setup",
        label: "Production",
        items: [
          { id: "formulas", title: "Feed formulas", icon: FlaskConical, href: "/livestock-feed-formulas" },
        ],
      },
      {
        key: "company",
        label: "Company",
        items: [
          { id: "company-settings", title: "Company settings", icon: CompanyIcon, href: "/livestock-company-settings" },
          { id: "species",          title: "Animals kept",     icon: PawPrint,    href: "/livestock-animals-kept" },
        ],
      },
      {
        key: "delivery-setup",
        label: "Delivery",
        items: [
          { id: "delivery-setup", title: "Delivery setup", icon: RouteIcon, href: "/livestock-delivery-setup" },
        ],
      },
    ],
    // Poultry's Tools: jobs across many groups at once, and the farm checks.
    tools: [
      {
        key: "tools",
        label: "Tools",
        items: [
          { id: "missing",      title: "Missing records",     icon: CalendarX,  href: "/livestock-missing-records" },
          { id: "distribution", title: "Feed many groups",    icon: Wheat,      href: "/livestock-feed-distribution" },
          { id: "headcount",    title: "Head count",          icon: ListChecks, href: "/livestock-head-count" },
          { id: "treatments",   title: "Treatment campaigns", icon: Pill,       href: "/livestock-treatments" },
          { id: "supply",       title: "Days of supply",      icon: Hourglass,  href: "/livestock-feed-supply" },
          { id: "alerts",       title: "Farm alerts",         icon: Bell,       href: "/livestock-alerts" },
        ],
      },
    ],
    system: [
      {
        key: "system",
        label: "Your account",
        items: [
          { id: "profile",    title: "Account",            icon: User,       href: "/profile", visible: false },
          { id: "alerts",     title: "Alerts",             icon: Bell,       onClick: onOpenAlerts, badge: alertCount },
          { id: "billing",    title: "Billing",            icon: CreditCard, href: "/business-office/billing", visible: money("/billing") },
          { id: "audit-logs", title: "Activity Log",       icon: Activity,   href: "/audit-logs", visible: featureAccess.canViewActivityLog },
          { id: "help",       title: "Help",               icon: HelpCircle, href: "/livestock-help" },
          { id: "terms",      title: "Terms & Conditions", icon: ListTodo,   href: "/terms" },
        ],
      },
    ],
  }

  const hide = (pred: (href: string) => boolean) => {
    for (const section of Object.values(config)) {
      if (!Array.isArray(section)) continue
      for (const group of section as MegaMenuGroup[]) {
        group.items = group.items.map((i) => (i.href && pred(i.href) ? { ...i, visible: false } : i))
      }
    }
  }

  // Setup pages are admin-only whatever the toggles say (setup-admin-routes.ts).
  if (!isAdmin) hide(isSetupAdminRoute)
  if (!showEggFeatures) hide((h) => LIVESTOCK_EGG_ONLY_HREFS.has(h))
  if (!showMilkFeatures) hide((h) => LIVESTOCK_MILK_ONLY_HREFS.has(h))
  if (!showBreedingFeatures) hide((h) => LIVESTOCK_BREEDING_ONLY_HREFS.has(h))

  // LAST, over the gated config (see poultry-nav-config.ts).
  return {
    ...config,
    quickLinks: { ...config.quickLinks, items: resolveQuickLinks(config, quickLinkHrefs) },
  }
}

/** True when a section has at least one row a user can see. */
export function navSectionHasRows(groups: MegaMenuGroup[]): boolean {
  return groups.some((g) => g.items.some((i) => i.visible !== false))
}
