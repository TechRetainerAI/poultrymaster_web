"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { useMemo } from "react"
import { createPortal } from "react-dom"
import { cn } from "@/lib/utils"
import { usePermissions } from "@/hooks/use-permissions"
import { useAuthStore } from "@/lib/store/auth-store"
import { useAlertsStore } from "@/lib/store/alerts-store"
import { Droplets, ShoppingBag, PackageMinus,
} from "lucide-react"
import { navPathActive, type NavAccent, type NavGroup, type NavItem } from "@/lib/nav/nav-model"
import { NAV_SURFACE } from "./nav/nav-surface"
import { WATER_REPORT_NAV_GROUPS, POULTRY_REPORT_NAV_GROUPS } from "@/lib/nav/report-nav-adapters"
import { buildWaterNavConfig } from "@/lib/nav/water-nav-config"
import { buildPoultryNavConfig } from "@/lib/nav/poultry-nav-config"
import { NavMegaMenu } from "./nav/nav-mega-menu"
import { useNavPopover, NAV_TRIGGER_CLASS, NAV_TRIGGER_ACTIVE } from "./nav/use-nav-popover"
import {
  Home,
  Building2,
  FileText,
  Package,
  ShoppingCart,
  DollarSign,
  Users,
  BarChart3,
  User,
  Settings,
  Activity,
  ChevronDown,
  Wallet,
  Boxes,
  CreditCard,
  Truck,
  Factory,
  LineChart,
} from "lucide-react"

function NavDropdown({ group, accent = "sky" }: { group: NavGroup; accent?: NavAccent }) {
  const pathname = usePathname()
  // Width passed so a dropdown opened near the right edge can't run off-screen
  // (the pre-extraction copy had no clamp at all).
  const pop = useNavPopover({ closeDelayMs: 150, menuWidthPx: 208 })
  // Same tinted surface as NavMegaMenu. This used to be a hardcoded bg-blue-600
  // that matched none of the three nav bars.
  const a = NAV_SURFACE[accent]

  const isGroupActive = group.items.some((item) => navPathActive(pathname, item.href))

  // After the hooks — bailing earlier would break the hook order. A group whose
  // rows were all permission-filtered would otherwise show as a trigger that
  // opens an empty panel.
  if (group.items.length === 0) return null

  return (
    <div
      ref={pop.triggerRef}
      onMouseEnter={pop.handleMouseEnter}
      onMouseLeave={pop.handleMouseLeave}
    >
      <button
        onClick={pop.toggle}
        className={cn(NAV_TRIGGER_CLASS, isGroupActive ? NAV_TRIGGER_ACTIVE : a.triggerIdle)}
      >
        {group.label}
        <ChevronDown
          className={cn(
            "h-3.5 w-3.5 transition-transform",
            pop.open ? "rotate-180" : ""
          )}
        />
      </button>

      {pop.open && pop.mounted && createPortal(
        <div
          ref={pop.menuRef}
          style={{ position: "fixed", top: pop.position.top, left: pop.position.left }}
          className={cn("w-52 rounded-lg py-1 shadow-lg border z-[9999]", a.panel)}
          onMouseEnter={pop.handleMouseEnter}
          onMouseLeave={pop.handleMouseLeave}
        >
          {group.items.map((item) => {
            const Icon = item.icon
            const isActive = navPathActive(pathname, item.href)
            return (
              <Link
                key={item.href}
                href={item.href}
                prefetch={true}
                onClick={pop.close}
                className={cn(
                  "flex items-center gap-2.5 px-3 py-2 text-sm transition-colors",
                  isActive ? cn(a.rowActive, "font-medium") : a.rowIdle,
                )}
              >
                <Icon className={cn("h-4 w-4", isActive ? a.iconActive : a.iconIdle)} />
                {item.label}
              </Link>
            )
          })}
        </div>,
        document.body
      )}
    </div>
  )
}

function NavLink({ item, accent = "sky" }: { item: NavItem; accent?: NavAccent }) {
  const pathname = usePathname()
  const isActive = navPathActive(pathname, item.href)
  const Icon = item.icon
  const a = NAV_SURFACE[accent]

  return (
    <Link
      href={item.href}
      prefetch={true}
      className={cn(NAV_TRIGGER_CLASS, isActive ? NAV_TRIGGER_ACTIVE : a.triggerIdle)}
    >
      <Icon className={cn("h-4 w-4", isActive ? "text-white" : a.triggerIcon)} />
      {item.label}
    </Link>
  )
}

function WaterTopNav({ permissions }: { permissions: ReturnType<typeof usePermissions> }) {
  // 2026-08-06: the rail used to carry nine near-identical narrow dropdowns
  // (Quick Links / Delivery / Production / Inventory / Sales & Money / People /
  // Reports / Admin · Setup), which made users hunt for items. Related groups
  // now share one wide panel each — the pattern Reports already used — so the
  // rail is Dashboard | Quick Links | Operations | Sales & Money | Reports |
  // Setup. Contents live in lib/nav/water-nav-config.ts.
  //
  // The sidebar and mobile nav keep their own copies of the water nav and were
  // deliberately left alone in this pass.
  // Business Office is not in here — it's an icon in the header bar above,
  // beside the search box, since it leaves the current company entirely.
  const openAlerts = useAlertsStore((s) => s.open)
  const alertCount = useAlertsStore((s) => s.alerts.length)

  const nav = useMemo(
    () => buildWaterNavConfig({ permissions, onOpenAlerts: openAlerts, alertCount }),
    [permissions, openAlerts, alertCount],
  )

  return (
    <div className="hidden lg:block bg-sky-600 border-b border-sky-700">
      <div className="flex items-center gap-1 px-4 pt-1.5 pb-2.5 nav-rail-scroll">
        <NavLink item={{ href: "/water-dashboard", label: "Dashboard", icon: Droplets }} />
        <div className="h-5 w-px bg-white/30 mx-1" />

        <NavDropdown group={nav.quickLinks} />

        {/* Panel widths below are sized to the longest label each one carries,
            not picked by eye. NavMegaMenu's padding is shared with the poultry
            rail, so an oversized widthRem is the whole reason water's groups sat
            in dead space instead of filling the panel.

            32px panel padding (p-4)
          + 32px scrollbar gutter  <-- [scrollbar-gutter:stable_both-edges]
          + 16px per grid gap
          + per column: 16px px-2 + 16px icon + 8px gap + ~7.6px per character

            THE GUTTER TERM IS NOT OPTIONAL. `stable` reserves the space whether
            or not the panel actually scrolls, and `both-edges` reserves it
            twice. It was added in the same pass that first tightened these
            widths and left out of the arithmetic, which cost every panel 2rem
            and truncated the longest label in most of them. If you ever drop
            `both-edges`, drop 16px here; if you drop scrollbar-gutter entirely,
            drop all 32px -- and re-derive, do not eyeball.

            Rows use `truncate`, so being short does not reflow anything: it
            silently eats letters. Err wide. */}
        <NavMegaMenu
          label="Operations" icon={Factory}
          title="Operations"
          blurb="Delivery runs, production and stock — everything that moves water."
          groups={nav.operations}
          /* 3 columns, longest label "Raw materials & supplies" / "Driver
             collection report" (24 chars ~= 182px): 64 + 3x(40+182) + 2x16 =
             762px. */
          columns={3} widthRem={48.5} layout="grid"
        />

        <NavMegaMenu
          label="Sales & Money" icon={Wallet}
          title="Sales & Money"
          blurb="Orders, collections, expenses and cash."
          groups={nav.salesMoney}
          /* Longest label "Reconcile cash" (14 chars ~= 106px):
             64 + 2x(40+106) + 16 = 372px. */
          columns={2} widthRem={24} layout="grid"
        />

        {/* Analytics is a menu, not a destination — there is no landing page,
            so no viewAll. A report prints a period; an analytic is explored. */}
        <NavMegaMenu
          label="Analytics" icon={LineChart}
          title="Analytics"
          blurb="Explore where your stock actually moved."
          groups={nav.analytics}
          /* Longest label "Inventory tracker" (17 chars ~= 129px):
             64 + (40+129) = 233px. */
          columns={1} widthRem={15.5} layout="grid"
        />

        {/* Sourced from lib/reports/water-reports-config.ts — the single source
            of truth shared with the /water-reports index page. Keeps the
            "columns" layout so it renders exactly as it always has. */}
        <NavMegaMenu
          label="Reports" icon={BarChart3}
          title="Reports"
          blurb="Quickly access Business, Sales, Inventory, Production and Delivery reports."
          viewAll={{ href: "/water-reports", label: "View all reports →" }}
          triggerActiveHrefs={["/water-reports"]}
          groups={WATER_REPORT_NAV_GROUPS}
          columns={4} widthRem={58}
        />

        <NavMegaMenu
          label="Setup" icon={Settings}
          title="Setup"
          blurb="Company configuration, products, delivery, customers and your team."
          groups={nav.setup}
          /* 5 groups over 2 columns = a 3x2 block with the last cell empty.
             Denser than one wide row. Longest label "Terms & Conditions"
             (18 chars ~= 137px): 64 + 2x(40+137) + 16 = 434px. */
          columns={2} widthRem={28.5} layout="grid"
        />

        <div className="ml-auto flex items-center gap-1">
          {/* Same panel treatment as the other menus, just one column wide —
              it only carries the user's own context. Companies is not here; it
              lives in Setup > Company. */}
          <NavMegaMenu
            label="System" icon={User}
            title="System"
            blurb="Alerts, activity and terms."
            groups={nav.system}
            /* Longest label "Terms & Conditions" (18 chars ~= 137px):
               64 + (40+137) = 241px. */
            columns={1} widthRem={15.5} layout="grid"
          />
        </div>
      </div>
    </div>
  )
}

// Generic Company top-nav: same compact pattern as WaterTopNav, but with the
// emerald color to make the company-type switch visually obvious. Mirrors the
// Generic sidebar groups (Catalog / Sales / Purchasing / Money / Admin); less
// important items live in a More dropdown so the rail stays one line wide.
function GenericTopNav({ permissions }: { permissions: ReturnType<typeof usePermissions> }) {
  const moreGroup: NavGroup = {
    label: "More",
    items: [
      // Generic has no Operations mega-menu, so Internal Use rides here beside
      // the other stock pages rather than getting a menu of its own.
      { href: "/generic-internal-use",       label: "Internal Use",       icon: PackageMinus },
      { href: "/generic-customer-payments",  label: "Customer payments",  icon: CreditCard },
      { href: "/generic-supplier-payments",  label: "Supplier payments",  icon: CreditCard },
      { href: "/generic-cash",               label: "Cash & Accounts",    icon: Wallet },
      { href: "/generic-cash-transfers",     label: "Cash transfers",     icon: Activity },
      { href: "/generic-daily-closings",     label: "Daily Closing",      icon: FileText },
      { href: "/generic-reports",            label: "Reports",            icon: BarChart3 },
      { href: "/generic-setup",              label: "Setup",              icon: Settings },
      { href: "/profile",                    label: "Account",            icon: User },
      // James 2026-06-02 — Employees and Activity Log removed from the top
      // nav (still in the sidebar). /resources and /settings are poultry-only;
      // Generic has /generic-setup.
    ],
  }

  return (
    <div className="hidden lg:block bg-emerald-600 border-b border-emerald-700">
      <div className="flex items-center gap-1 px-4 pt-1.5 pb-2.5 nav-rail-scroll">
        <NavLink item={{ href: "/generic-dashboard",          label: "Dashboard",         icon: Home }} accent="emerald" />
        <div className="h-5 w-px bg-white/30 mx-1" />
        <NavLink item={{ href: "/generic-products",           label: "Products",          icon: ShoppingBag }} accent="emerald" />
        <NavLink item={{ href: "/generic-stock-adjustments",  label: "Stock adjustments", icon: Boxes }} accent="emerald" />
        <NavLink item={{ href: "/generic-sales",              label: "Sales",             icon: ShoppingCart }} accent="emerald" />
        <NavLink item={{ href: "/generic-customers",          label: "Customers",         icon: Users }} accent="emerald" />
        <NavLink item={{ href: "/generic-suppliers",          label: "Suppliers",         icon: Truck }} accent="emerald" />
        <NavLink item={{ href: "/generic-purchases",          label: "Purchases",         icon: Package }} accent="emerald" />
        <NavLink item={{ href: "/generic-expenses",           label: "Expenses",          icon: DollarSign }} accent="emerald" />
        <NavDropdown group={moreGroup} accent="emerald" />
        <div className="ml-auto flex items-center gap-1">
          <NavLink item={{ href: "/companies", label: "Companies", icon: Building2 }} accent="emerald" />
          {/* /help is poultry-specific */}
        </div>
      </div>
    </div>
  )
}

export function TopNavigation() {
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  // Must be read before the farm-type early returns below, or the hook order
  // changes when the user switches company type.
  const openAlerts = useAlertsStore((s) => s.open)
  const alertCount = useAlertsStore((s) => s.alerts.length)

  // Water and Generic companies each get their own nav rail — falling through
  // to the Poultry layout below would show "Flocks / Houses / Egg sorting" on
  // a Generic company sidebar, which is what the user is hitting right now.
  if (activeFarmType === "Water") {
    return <WaterTopNav permissions={permissions} />
  }
  if (activeFarmType === "Generic") {
    return <GenericTopNav permissions={permissions} />
  }

  // 2026-08-07: same treatment as the water rail — nine near-identical narrow
  // dropdowns collapse into grouped panels. Contents live in
  // lib/nav/poultry-nav-config.ts. The sidebar and mobile nav keep their own
  // copies and were left alone.
  const nav = buildPoultryNavConfig({ permissions, onOpenAlerts: openAlerts, alertCount })

  return (
    <>
      <div className="hidden lg:block bg-orange-500 border-b border-orange-600">
        <div className="flex items-center gap-1 px-4 pt-1.5 pb-2.5 nav-rail-scroll">
          <NavLink item={{ href: "/dashboard", label: "Dashboard", icon: Home }} accent="orange" />
          <div className="h-5 w-px bg-white/30 mx-1" />

          <NavDropdown group={nav.quickLinks} accent="orange" />

          <NavMegaMenu
            label="Operations" icon={Factory}
            title="Operations"
            blurb="Production, flock purchases, deliveries, stock and health."
            groups={nav.operations}
            /* 4 groups over 2 columns = a 2x2 block, and it's those two long
               labels that set the floor: "Flock Purchases (Batches)" is 184px in
               Geist-Medium (the active row's weight) and "Raw Materials &
               Supplies" 177px, so a column needs 224px:
               64 + 2x224 + 16 = 528px. Shorten both and this drops to ~27.5rem. */
            columns={2} widthRem={34} layout="grid" accent="orange"
          />

          <NavMegaMenu
            label="Sales & Money" icon={Wallet}
            title="Sales & Money"
            blurb="Orders, collections, expenses, cash and payroll."
            groups={nav.salesMoney}
            /* Two columns sized to their OWN content (fitColumns), not to an equal
               share: Sales' longest label is "Customer Balances" and Money's is
               "Reconcile cash", and equal columns would widen BOTH to the former
               and hang the difference off the right edge as dead space.
               Measured in Geist-Medium (the active row's weight): Customer
               Balances 132px, Reconcile cash 102px. Each column needs ~40px more
               for the icon, gap and row padding, so the two are ~180px and
               ~148px. 24rem = 384px covers 180 + 148 + the 16px grid gap + 32px
               of panel padding, with slack for font rendering. */
            columns={2} widthRem={24} layout="grid" fitColumns accent="orange"
          />

          <NavMegaMenu
            label="Analytics" icon={BarChart3}
            title="Analytics"
            blurb="Day-to-day tracker"
            groups={nav.analytics}
            /* "Medication tracker" is the longest label and sets the floor:
               137px in Geist-Medium (the active row's weight) plus 40px of icon,
               gap and row padding, plus the panel's 64px = 241px. */
            columns={1} widthRem={15.5} layout="grid" accent="orange"
          />

          {/* Sourced from lib/reports/poultry-reports-config.ts — the single
              source of truth shared with the /poultry/reports catalogue. Keeps
              the "columns" layout so it renders exactly as it always has. */}
          {permissions.featureAccess.canViewReports && (
            <NavMegaMenu
              label="Reports" icon={BarChart3}
              title="Reports"
              blurb="Money, production, feed, birds, health and dashboards."
              viewAll={{ href: "/poultry/reports", label: "View all reports →" }}
              triggerActiveHrefs={["/reports", "/poultry/reports"]}
              groups={POULTRY_REPORT_NAV_GROUPS}
              /* Four groups of 8/6/9/6 over four columns — one group per
                 column, with Overview & Dashboards last. */
              columns={4} widthRem={58} accent="orange"
            />
          )}

          <NavMegaMenu
            label="Setup" icon={Settings}
            title="Setup"
            blurb="Houses, flocks, products, delivery, customers and your team."
            groups={nav.setup}
            /* 6 groups over 2 columns = a 3x2 block. "Users & Permissions" is
               the longest label at 145px in Geist-Medium (the active row's
               weight), so a column needs 185px:
               64 + 2x185 + 16 = 450px. */
            columns={2} widthRem={28.5} layout="grid" accent="orange"
          />

          <div className="ml-auto flex items-center gap-1">
            {/* Billing, Terms and Help Center used to be pinned here; they now
                live in Sales & Money and System respectively. */}
            <NavMegaMenu
              label="System" icon={User}
              title="System"
              blurb="Alerts, activity, help, terms."
              groups={nav.system}
              /* "Terms & Conditions" is the longest label at 137px in
                 Geist-Medium (the active row's weight) plus 40px of icon, gap and
                 row padding, plus the panel's 64px = 241px. The Alerts row also
                 carries a count badge, but at 44px of text it stays well clear. */
              columns={1} widthRem={15.5} layout="grid" accent="orange"
            />
          </div>
        </div>
      </div>

      {/* Mobile: top nav replaced by MobileBottomNav (bottom tab bar) */}
    </>
  )
}



