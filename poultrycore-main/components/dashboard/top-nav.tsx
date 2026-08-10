"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { useMemo } from "react"
import { createPortal } from "react-dom"
import { cn } from "@/lib/utils"
import { usePermissions } from "@/hooks/use-permissions"
import { useAuthStore } from "@/lib/store/auth-store"
import { useAlertsStore } from "@/lib/store/alerts-store"
import { Droplets, ShoppingBag } from "lucide-react"
import { navPathActive, type NavGroup, type NavItem } from "@/lib/nav/nav-model"
import { WATER_REPORT_NAV_GROUPS, POULTRY_REPORT_NAV_GROUPS } from "@/lib/nav/report-nav-adapters"
import { buildWaterNavConfig } from "@/lib/nav/water-nav-config"
import { buildPoultryNavConfig } from "@/lib/nav/poultry-nav-config"
import { NavMegaMenu } from "./nav/nav-mega-menu"
import {
  useNavPopover, NAV_TRIGGER_CLASS, NAV_TRIGGER_ACTIVE, NAV_TRIGGER_IDLE,
} from "./nav/use-nav-popover"
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
} from "lucide-react"

function NavDropdown({ group }: { group: NavGroup }) {
  const pathname = usePathname()
  // Width passed so a dropdown opened near the right edge can't run off-screen
  // (the pre-extraction copy had no clamp at all).
  const pop = useNavPopover({ closeDelayMs: 150, menuWidthPx: 208 })

  const isGroupActive = group.items.some((item) => navPathActive(pathname, item.href))

  return (
    <div
      ref={pop.triggerRef}
      onMouseEnter={pop.handleMouseEnter}
      onMouseLeave={pop.handleMouseLeave}
    >
      <button
        onClick={pop.toggle}
        className={cn(NAV_TRIGGER_CLASS, isGroupActive ? NAV_TRIGGER_ACTIVE : NAV_TRIGGER_IDLE)}
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
          className="w-52 rounded-lg bg-blue-600 py-1 shadow-lg border border-blue-500 z-[9999]"
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
                  isActive
                    ? "bg-blue-700 text-white font-medium"
                    : "text-blue-50 hover:bg-blue-700 hover:text-white"
                )}
              >
                <Icon className={cn("h-4 w-4", isActive ? "text-white" : "text-blue-100")} />
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

function NavLink({ item }: { item: NavItem }) {
  const pathname = usePathname()
  const isActive = navPathActive(pathname, item.href)
  const Icon = item.icon

  return (
    <Link
      href={item.href}
      prefetch={true}
      className={cn(NAV_TRIGGER_CLASS, isActive ? NAV_TRIGGER_ACTIVE : NAV_TRIGGER_IDLE)}
    >
      <Icon className={cn("h-4 w-4", isActive ? "text-white" : "text-orange-200")} />
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

        <NavMegaMenu
          label="Operations" icon={Factory}
          title="Operations"
          blurb="Delivery runs, production and stock — everything that moves water."
          groups={nav.operations}
          columns={3} widthRem={46} layout="grid"
        />

        <NavMegaMenu
          label="Sales & Money" icon={Wallet}
          title="Sales & Money"
          blurb="Orders, collections, expenses and cash."
          groups={nav.salesMoney}
          columns={2} widthRem={34} layout="grid"
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
          columns={4} widthRem={56}
        />

        <NavMegaMenu
          label="Setup" icon={Settings}
          title="Setup"
          blurb="Company configuration, products, customers and your team."
          groups={nav.setup}
          columns={3} widthRem={46} layout="grid"
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
            columns={1} widthRem={20} layout="grid"
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
        <NavLink item={{ href: "/generic-dashboard",          label: "Dashboard",         icon: Home }} />
        <div className="h-5 w-px bg-white/30 mx-1" />
        <NavLink item={{ href: "/generic-products",           label: "Products",          icon: ShoppingBag }} />
        <NavLink item={{ href: "/generic-stock-adjustments",  label: "Stock adjustments", icon: Boxes }} />
        <NavLink item={{ href: "/generic-sales",              label: "Sales",             icon: ShoppingCart }} />
        <NavLink item={{ href: "/generic-customers",          label: "Customers",         icon: Users }} />
        <NavLink item={{ href: "/generic-suppliers",          label: "Suppliers",         icon: Truck }} />
        <NavLink item={{ href: "/generic-purchases",          label: "Purchases",         icon: Package }} />
        <NavLink item={{ href: "/generic-expenses",           label: "Expenses",          icon: DollarSign }} />
        <NavDropdown group={moreGroup} />
        <div className="ml-auto flex items-center gap-1">
          <NavLink item={{ href: "/companies", label: "Companies", icon: Building2 }} />
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
          <NavLink item={{ href: "/dashboard", label: "Dashboard", icon: Home }} />
          <div className="h-5 w-px bg-white/30 mx-1" />

          <NavDropdown group={nav.quickLinks} />

          <NavMegaMenu
            label="Operations" icon={Factory}
            title="Operations"
            blurb="Production, flocks, deliveries, stock and health."
            groups={nav.operations}
            columns={4} widthRem={58} layout="grid" accent="amber"
          />

          <NavMegaMenu
            label="Sales & Money" icon={Wallet}
            title="Sales & Money"
            blurb="Orders, collections, expenses, cash and payroll."
            groups={nav.salesMoney}
            columns={2} widthRem={34} layout="grid" accent="amber"
          />

          <NavMegaMenu
            label="Analytics" icon={BarChart3}
            title="Analytics"
            blurb="Day-to-day trackers for eggs, feed, medication and birds."
            groups={nav.analytics}
            columns={1} widthRem={22} layout="grid" accent="amber"
          />

          {/* Sourced from lib/reports/poultry-reports-config.ts — the single
              source of truth shared with the /poultry/reports catalogue. Keeps
              the "columns" layout so it renders exactly as it always has. */}
          {permissions.featureAccess.canViewReports && (
            <NavMegaMenu
              label="Reports" icon={BarChart3}
              title="Reports"
              blurb="Production, birds & mortality, feed, inventory, sales and profitability."
              viewAll={{ href: "/poultry/reports", label: "View all reports →" }}
              triggerActiveHrefs={["/reports", "/poultry/reports"]}
              groups={POULTRY_REPORT_NAV_GROUPS}
              columns={4} widthRem={56} accent="amber"
            />
          )}

          <NavMegaMenu
            label="Setup" icon={Settings}
            title="Setup"
            blurb="Farm settings, products, customers, suppliers and your team."
            groups={nav.setup}
            columns={3} widthRem={46} layout="grid" accent="amber"
          />

          <div className="ml-auto flex items-center gap-1">
            {/* Billing, Terms and Help Center used to be pinned here; they now
                live in Sales & Money and System respectively. */}
            <NavMegaMenu
              label="System" icon={User}
              title="System"
              blurb="Alerts, activity, help and terms."
              groups={nav.system}
              columns={1} widthRem={22} layout="grid" accent="amber"
            />
          </div>
        </div>
      </div>

      {/* Mobile: top nav replaced by MobileBottomNav (bottom tab bar) */}
    </>
  )
}



