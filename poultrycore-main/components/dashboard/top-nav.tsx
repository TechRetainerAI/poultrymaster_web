"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { useState, useRef, useEffect } from "react"
import { createPortal } from "react-dom"
import { cn } from "@/lib/utils"
import { usePermissions } from "@/hooks/use-permissions"
import { isFinancialNavItemVisible } from "@/lib/utils/financial-nav-access"
import { useAuthStore } from "@/lib/store/auth-store"
import { Droplets, ShoppingBag } from "lucide-react"
import { WATER_REPORT_GROUPS, waterReportHref } from "@/lib/reports/water-reports-config"
import { POULTRY_REPORT_MENU_GROUPS } from "@/lib/reports/poultry-reports-config"
import {
  Home,
  Bird,
  Building2,
  FileText,
  Egg,
  Package,
  AlertTriangle,
  ShoppingCart,
  DollarSign,
  Users,
  BookOpen,
  BarChart3,
  User,
  Settings,
  Activity,
  ChevronDown,
  Wallet,
  Boxes,
  CreditCard,
  Wheat,
  Pill,
  Truck,
  Factory,
  Receipt,
  Wrench,
  Cog,
  Route as RouteIcon,
  Users2,
  Banknote,
  Box as BoxIcon,
} from "lucide-react"

interface NavItem {
  href: string
  label: string
  icon: any
}

interface NavGroup {
  label: string
  items: NavItem[]
}

function NavDropdown({ group }: { group: NavGroup }) {
  const pathname = usePathname()
  const [open, setOpen] = useState(false)
  const triggerRef = useRef<HTMLDivElement>(null)
  const dropdownRef = useRef<HTMLDivElement>(null)
  const timeoutRef = useRef<NodeJS.Timeout | null>(null)
  const [position, setPosition] = useState({ top: 0, left: 0 })
  const [mounted, setMounted] = useState(false)

  const isGroupActive = group.items.some((item) => navPathActive(pathname, item.href))

  useEffect(() => { setMounted(true) }, [])

  const updatePosition = () => {
    if (triggerRef.current) {
      const rect = triggerRef.current.getBoundingClientRect()
      setPosition({
        top: rect.bottom + 4,
        left: rect.left,
      })
    }
  }

  const handleMouseEnter = () => {
    if (timeoutRef.current) clearTimeout(timeoutRef.current)
    updatePosition()
    setOpen(true)
  }

  const handleMouseLeave = () => {
    timeoutRef.current = setTimeout(() => setOpen(false), 150)
  }

  // Close on click outside
  useEffect(() => {
    if (!open) return
    const handleClickOutside = (e: MouseEvent) => {
      const target = e.target as Node
      if (
        triggerRef.current && !triggerRef.current.contains(target) &&
        (!dropdownRef.current || !dropdownRef.current.contains(target))
      ) {
        setOpen(false)
      }
    }
    document.addEventListener("mousedown", handleClickOutside)
    return () => document.removeEventListener("mousedown", handleClickOutside)
  }, [open])

  return (
    <div
      ref={triggerRef}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
    >
      <button
        onClick={() => { updatePosition(); setOpen(!open) }}
        className={cn(
          "flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-md transition-colors whitespace-nowrap",
          isGroupActive
            ? "bg-white/25 text-white font-semibold"
            : "text-orange-100 hover:bg-white/15 hover:text-white"
        )}
      >
        {group.label}
        <ChevronDown
          className={cn(
            "h-3.5 w-3.5 transition-transform",
            open ? "rotate-180" : ""
          )}
        />
      </button>

      {open && mounted && createPortal(
        <div
          ref={dropdownRef}
          style={{ position: "fixed", top: position.top, left: position.left }}
          className="w-52 rounded-lg bg-blue-600 py-1 shadow-lg border border-blue-500 z-[9999]"
          onMouseEnter={handleMouseEnter}
          onMouseLeave={handleMouseLeave}
        >
          {group.items.map((item) => {
            const Icon = item.icon
            const isActive = navPathActive(pathname, item.href)
            return (
              <Link
                key={item.href}
                href={item.href}
                prefetch={true}
                onClick={() => setOpen(false)}
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

function navPathActive(pathname: string, href: string) {
  return pathname === href || (href !== "/dashboard" && pathname.startsWith(`${href}/`))
}

function NavLink({ item }: { item: NavItem }) {
  const pathname = usePathname()
  const isActive = navPathActive(pathname, item.href)
  const Icon = item.icon

  return (
    <Link
      href={item.href}
      prefetch={true}
      className={cn(
        "flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-md transition-colors whitespace-nowrap",
        isActive
          ? "bg-white/25 text-white font-semibold"
          : "text-orange-100 hover:bg-white/15 hover:text-white"
      )}
    >
      <Icon className={cn("h-4 w-4", isActive ? "text-white" : "text-orange-200")} />
      {item.label}
    </Link>
  )
}

/**
 * 4-column Reports mega-menu shown in the Water top-nav. Opens on hover (with
 * a small close delay so the user can travel diagonally into it) and on click.
 * Reports come from the shared `WATER_REPORT_GROUPS` catalog so the menu and
 * the /water-reports index can never drift apart.
 *
 * The menu is portalled into <body> so the sky-600 nav bar's overflow doesn't
 * clip it. Width is fixed at 56rem; collapses with horizontal scroll on narrow
 * desktop widths via overflow-auto on the container.
 */
function ReportsMegaMenu() {
  const pathname = usePathname()
  const [open, setOpen] = useState(false)
  const [mounted, setMounted] = useState(false)
  const [position, setPosition] = useState({ top: 0, left: 0 })
  const triggerRef = useRef<HTMLDivElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)
  const timeoutRef = useRef<NodeJS.Timeout | null>(null)

  useEffect(() => { setMounted(true) }, [])

  const updatePosition = () => {
    if (!triggerRef.current) return
    const rect = triggerRef.current.getBoundingClientRect()
    // Keep within viewport: max width 56rem (896px), give 16px right margin.
    const desiredLeft = rect.left
    const maxLeft = Math.max(8, window.innerWidth - 896 - 16)
    setPosition({ top: rect.bottom + 4, left: Math.min(desiredLeft, maxLeft) })
  }

  const handleMouseEnter = () => {
    if (timeoutRef.current) clearTimeout(timeoutRef.current)
    updatePosition()
    setOpen(true)
  }
  const handleMouseLeave = () => {
    timeoutRef.current = setTimeout(() => setOpen(false), 180)
  }

  useEffect(() => {
    if (!open) return
    const handleClickOutside = (e: MouseEvent) => {
      const t = e.target as Node
      if (
        triggerRef.current && !triggerRef.current.contains(t) &&
        (!menuRef.current || !menuRef.current.contains(t))
      ) setOpen(false)
    }
    document.addEventListener("mousedown", handleClickOutside)
    return () => document.removeEventListener("mousedown", handleClickOutside)
  }, [open])

  const isReportsActive = pathname === "/water-reports" || pathname.startsWith("/water-reports/")

  return (
    <div
      ref={triggerRef}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
    >
      <button
        onClick={() => { updatePosition(); setOpen(!open) }}
        className={cn(
          "flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-md transition-colors whitespace-nowrap",
          isReportsActive
            ? "bg-white/25 text-white font-semibold"
            : "text-orange-100 hover:bg-white/15 hover:text-white",
        )}
      >
        <BarChart3 className="h-4 w-4" />
        Reports
        <ChevronDown className={cn("h-3.5 w-3.5 transition-transform", open ? "rotate-180" : "")} />
      </button>

      {open && mounted && createPortal(
        <div
          ref={menuRef}
          style={{ position: "fixed", top: position.top, left: position.left }}
          className="w-[56rem] max-w-[calc(100vw-16px)] rounded-lg bg-white shadow-2xl border border-slate-200 z-[9999] overflow-hidden"
          onMouseEnter={handleMouseEnter}
          onMouseLeave={handleMouseLeave}
        >
          {/* Header strip — gives the menu a clear identity, mirrors the
              recommended visual from the design reference. */}
          <div className="bg-slate-50 px-5 py-3 border-b border-slate-200 flex items-center justify-between">
            <div>
              <div className="font-semibold text-slate-900 text-sm">Reports</div>
              <div className="text-xs text-slate-500">Quickly access Business, Sales, Inventory, Production and Delivery reports.</div>
            </div>
            <Link
              href="/water-reports"
              prefetch
              onClick={() => setOpen(false)}
              className="text-xs font-medium text-sky-700 hover:text-sky-900 hover:underline whitespace-nowrap"
            >
              View all reports →
            </Link>
          </div>

          <div className="grid grid-cols-2 lg:grid-cols-4 gap-x-4 gap-y-3 p-4 max-h-[70vh] overflow-y-auto">
            {WATER_REPORT_GROUPS.map((g) => (
              <div key={g.key} className="min-w-0">
                <div className="flex items-center gap-2 mb-2">
                  <span className={cn("inline-block h-2 w-2 rounded-full", g.color)} />
                  <h3 className="text-[11px] font-semibold uppercase tracking-wider text-slate-600">{g.label}</h3>
                </div>
                <ul className="space-y-0.5">
                  {g.reports.map((r) => {
                    const href = waterReportHref(r.slug)
                    const active = pathname === href
                    const Icon = r.icon
                    return (
                      <li key={r.slug}>
                        <Link
                          href={href}
                          prefetch
                          onClick={() => setOpen(false)}
                          className={cn(
                            "flex items-start gap-2 px-2 py-1.5 rounded-md text-sm transition-colors",
                            active
                              ? "bg-sky-50 text-sky-900 font-medium"
                              : "text-slate-700 hover:bg-slate-100",
                          )}
                        >
                          <Icon className={cn("h-4 w-4 mt-0.5 shrink-0", active ? "text-sky-700" : "text-slate-400")} />
                          <span className="truncate">{r.title}</span>
                        </Link>
                      </li>
                    )
                  })}
                </ul>
              </div>
            ))}
          </div>
        </div>,
        document.body,
      )}
    </div>
  )
}

/**
 * Reports mega-menu for the Poultry top-nav. Same hover-card pattern as the
 * Water ReportsMegaMenu, but sourced from POULTRY_REPORT_GROUPS so the menu and
 * the /poultry/reports catalogue stay in sync. Items link to the individual
 * report pages (/poultry/reports/<slug>); "View all" opens the catalogue.
 */
function PoultryReportsMegaMenu() {
  const pathname = usePathname()
  const [open, setOpen] = useState(false)
  const [mounted, setMounted] = useState(false)
  const [position, setPosition] = useState({ top: 0, left: 0 })
  const triggerRef = useRef<HTMLDivElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)
  const timeoutRef = useRef<NodeJS.Timeout | null>(null)

  useEffect(() => { setMounted(true) }, [])

  const updatePosition = () => {
    if (!triggerRef.current) return
    const rect = triggerRef.current.getBoundingClientRect()
    const desiredLeft = rect.left
    const maxLeft = Math.max(8, window.innerWidth - 896 - 16)
    setPosition({ top: rect.bottom + 4, left: Math.min(desiredLeft, maxLeft) })
  }

  const handleMouseEnter = () => {
    if (timeoutRef.current) clearTimeout(timeoutRef.current)
    updatePosition()
    setOpen(true)
  }
  const handleMouseLeave = () => {
    timeoutRef.current = setTimeout(() => setOpen(false), 180)
  }

  useEffect(() => {
    if (!open) return
    const handleClickOutside = (e: MouseEvent) => {
      const t = e.target as Node
      if (
        triggerRef.current && !triggerRef.current.contains(t) &&
        (!menuRef.current || !menuRef.current.contains(t))
      ) setOpen(false)
    }
    document.addEventListener("mousedown", handleClickOutside)
    return () => document.removeEventListener("mousedown", handleClickOutside)
  }, [open])

  const isReportsActive =
    pathname === "/reports" || pathname === "/poultry/reports" || pathname.startsWith("/poultry/reports/")

  return (
    <div ref={triggerRef} onMouseEnter={handleMouseEnter} onMouseLeave={handleMouseLeave}>
      <button
        onClick={() => { updatePosition(); setOpen(!open) }}
        className={cn(
          "flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-md transition-colors whitespace-nowrap",
          isReportsActive
            ? "bg-white/25 text-white font-semibold"
            : "text-orange-100 hover:bg-white/15 hover:text-white",
        )}
      >
        <BarChart3 className="h-4 w-4" />
        Reports
        <ChevronDown className={cn("h-3.5 w-3.5 transition-transform", open ? "rotate-180" : "")} />
      </button>

      {open && mounted && createPortal(
        <div
          ref={menuRef}
          style={{ position: "fixed", top: position.top, left: position.left }}
          className="w-[56rem] max-w-[calc(100vw-16px)] rounded-lg bg-white shadow-2xl border border-slate-200 z-[9999] overflow-hidden"
          onMouseEnter={handleMouseEnter}
          onMouseLeave={handleMouseLeave}
        >
          <div className="bg-slate-50 px-5 py-3 border-b border-slate-200 flex items-center justify-between">
            <div>
              <div className="font-semibold text-slate-900 text-sm">Reports</div>
              <div className="text-xs text-slate-500">Production, birds &amp; mortality, feed, inventory, sales, expenses, profitability and health.</div>
            </div>
            <Link
              href="/poultry/reports"
              prefetch
              onClick={() => setOpen(false)}
              className="text-xs font-medium text-amber-700 hover:text-amber-900 hover:underline whitespace-nowrap"
            >
              View all reports →
            </Link>
          </div>

          <div className="grid grid-cols-2 lg:grid-cols-4 gap-x-4 gap-y-3 p-4 max-h-[70vh] overflow-y-auto">
            {POULTRY_REPORT_MENU_GROUPS.map((g) => (
              <div key={g.key} className="min-w-0">
                <div className="flex items-center gap-2 mb-2">
                  <span className={cn("inline-block h-2 w-2 rounded-full", g.color)} />
                  <h3 className="text-[11px] font-semibold uppercase tracking-wider text-slate-600">{g.label}</h3>
                </div>
                <ul className="space-y-0.5">
                  {g.items.map((it) => {
                    const active = pathname === it.href
                    const Icon = it.icon
                    return (
                      <li key={it.id}>
                        <Link
                          href={it.href}
                          prefetch
                          onClick={() => setOpen(false)}
                          className={cn(
                            "flex items-start gap-2 px-2 py-1.5 rounded-md text-sm transition-colors",
                            active
                              ? "bg-amber-50 text-amber-900 font-medium"
                              : "text-slate-700 hover:bg-slate-100",
                          )}
                        >
                          <Icon className={cn("h-4 w-4 mt-0.5 shrink-0", active ? "text-amber-700" : "text-slate-400")} />
                          <span className="truncate">{it.title}</span>
                        </Link>
                      </li>
                    )
                  })}
                </ul>
              </div>
            ))}
          </div>
        </div>,
        document.body,
      )}
    </div>
  )
}

function WaterTopNav({ permissions }: { permissions: ReturnType<typeof usePermissions> }) {
  // James (2026-06-02): top nav mirrors the new sidebar layout — Quick Links
  // (shortcuts) / Delivery / Production / Inventory / Sales & Money / People
  // / Reports (mega-menu) / Admin · Setup. Delivery and Production graduated
  // out of Admin/Setup; Quick Links is a fast-access bar for the most-used
  // daily flows (its items also live in their canonical groups).
  // See: components/dashboard/sidebar.tsx waterQuickLinkItems / waterDeliveryItems
  // / waterProductionItems / waterInventoryItems / waterSalesMoneyItems
  // / waterPeopleItems / waterAdminItems.
  const quickLinksGroup: NavGroup = {
    label: "Quick Links",
    items: [
      { href: "/water-daily-closing",      label: "Daily Closing",      icon: FileText },
      { href: "/water-driver-returns",     label: "Deliveries",         icon: Truck },
      { href: "/water-production-batches", label: "Production Batches", icon: Factory },
      { href: "/water-sales",              label: "Sales",              icon: ShoppingCart },
    ],
  }

  const deliveryGroup: NavGroup = {
    label: "Delivery",
    items: [
      { href: "/water-driver-returns", label: "Deliveries", icon: Truck },
      { href: "/water-drivers",        label: "Drivers",    icon: Users2 },
      { href: "/water-vehicles",       label: "Vehicles",   icon: Truck },
      { href: "/water-routes",         label: "Routes",     icon: RouteIcon },
    ],
  }

  const productionGroup: NavGroup = {
    label: "Production",
    items: [
      { href: "/water-production-batches", label: "Production Batches", icon: Factory },
      { href: "/water-products",           label: "Products",           icon: ShoppingBag },
      { href: "/water-machines",           label: "Machines",           icon: Cog },
      { href: "/water-boreholes",          label: "Boreholes",          icon: Droplets },
      { href: "/water-maintenance",        label: "Maintenance",        icon: Wrench },
    ],
  }

  const inventoryGroup: NavGroup = {
    label: "Inventory",
    items: [
      { href: "/water-stock",             label: "Stock",                    icon: Boxes },
      { href: "/water-inventory",         label: "Inventory",                icon: Boxes },
      { href: "/water-raw-materials",     label: "Raw materials & supplies", icon: BoxIcon },
      { href: "/water-loss-records",      label: "Damages & loss",           icon: AlertTriangle },
      { href: "/water-production-losses", label: "Production losses",        icon: AlertTriangle },
    ],
  }

  const salesMoneyGroup: NavGroup = {
    label: "Sales & Money",
    items: [
      { href: "/water-customers",     label: "Customers",       icon: Users },
      { href: "/water-sales",         label: "Sales",           icon: ShoppingCart },
      { href: "/water-payments",      label: "Payments",        icon: CreditCard },
      { href: "/water-expenses",      label: "Expenses",        icon: Receipt },
      { href: "/water-cash-accounts", label: "Cash & Accounts", icon: Wallet },
    ],
  }

  const peopleGroup: NavGroup = {
    label: "People",
    items: [
      { href: "/water-staff",   label: "Staff",   icon: Users2 },
      { href: "/water-payroll", label: "Payroll", icon: Banknote },
    ],
  }

  // Admin / Setup is now the lean rare-touch config bucket. Delivery/Production
  // fleet items have moved into their own groups above. Driver collection
  // report stays here as an admin/operations artifact.
  const adminGroup: NavGroup = {
    label: "Admin · Setup",
    items: [
      { href: "/water-setup",          label: "Setup",                    icon: Settings },
      { href: "/water-company-setup",  label: "Company Setup",            icon: Settings },
      { href: "/water-suppliers",      label: "Suppliers",                icon: Truck },
      { href: "/water-driver-report",  label: "Driver collection report", icon: BarChart3 },
    ],
  }

  return (
    <div className="hidden lg:block bg-sky-600 border-b border-sky-700">
      <div className="flex items-center gap-1 px-4 pt-1.5 pb-2.5 nav-rail-scroll">
        <NavLink item={{ href: "/water-dashboard", label: "Dashboard", icon: Droplets }} />
        <div className="h-5 w-px bg-white/30 mx-1" />
        <NavDropdown group={quickLinksGroup} />
        <NavDropdown group={deliveryGroup} />
        <NavDropdown group={productionGroup} />
        <NavDropdown group={inventoryGroup} />
        <NavDropdown group={salesMoneyGroup} />
        <NavDropdown group={peopleGroup} />
        {/* Reports opens a 4-column mega-menu sourced from
            lib/reports/water-reports-config.ts (single source of truth shared
            with the /water-reports index page). */}
        <ReportsMegaMenu />
        <NavDropdown group={adminGroup} />
        <div className="ml-auto flex items-center gap-1">
          {/* James 2026-06-02 — Employees and Activity Log are still reachable
              from the sidebar; removed from the top nav to keep the right side
              of the bar focused on the user's own context (Account, Companies). */}
          <NavLink item={{ href: "/profile",   label: "Account",   icon: User }} />
          <NavLink item={{ href: "/companies", label: "Companies", icon: Building2 }} />
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
  // Temporary business override while subscription enforcement is paused.
  const TEMP_SHOW_PAYMENTS_LINK = true
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  // Water and Generic companies each get their own nav rail — falling through
  // to the Poultry layout below would show "Flocks / Houses / Egg sorting" on
  // a Generic company sidebar, which is what the user is hitting right now.
  if (activeFarmType === "Water") {
    return <WaterTopNav permissions={permissions} />
  }
  if (activeFarmType === "Generic") {
    return <GenericTopNav permissions={permissions} />
  }

  const farmGroup: NavGroup = {
    label: "Farm",
    items: [
      { href: "/flock-batch", label: "Flock Purchases (Batches)", icon: Boxes },
      { href: "/flocks", label: "Flock Groups (Pens / Flocks)", icon: Bird },
      { href: "/houses", label: "Houses", icon: Building2 },
    ],
  }

  const productionGroup: NavGroup = {
    label: "Production",
    items: [
      { href: "/production-records", label: "Production Records", icon: FileText },
      { href: "/egg-production", label: "Egg sorting", icon: Egg },
      { href: "/feed-usage", label: "Feed Usage", icon: Package },
    ],
  }

  const analyticsGroup: NavGroup = {
    label: "Analytics",
    items: [
      { href: "/egg-tracker", label: "Egg tracker", icon: BarChart3 },
      { href: "/feed-tracker", label: "Feed tracker", icon: Wheat },
      { href: "/medication-tracker", label: "Medication tracker", icon: Pill },
      { href: "/birds-left-tracker", label: "Bird Left Tracker", icon: Bird },
      { href: "/weekly-report", label: "Analytical Report", icon: FileText },
    ],
  }

  const inventoryGroup: NavGroup = {
    label: "Inventory & Health",
    items: [
      { href: "/health", label: "Health Records", icon: AlertTriangle },
      { href: "/inventory", label: "Inventory", icon: Package },
      { href: "/supplies", label: "Supplies", icon: ShoppingCart },
    ],
  }

  const financialGroup: NavGroup = {
    label: "Financial",
    items: [
      { href: "/cash", label: "Cash", icon: Wallet },
      { href: "/poultry-cash-accounts", label: "Cash & Accounts", icon: Wallet },
      { href: "/sales", label: "Sales", icon: ShoppingCart },
      { href: "/expenses", label: "Expenses", icon: DollarSign },
      { href: "/customers", label: "Customers", icon: Users },
      { href: "/suppliers", label: "Suppliers", icon: Truck },
      { href: "/payments", label: "Payments", icon: CreditCard },
    ].filter((item) =>
      isFinancialNavItemVisible(item.href, permissions.featureAccess, permissions.isAdmin)
    ),
  }

  const peopleGroup: NavGroup = {
    label: "People",
    items: [
      ...((permissions.isAdmin || permissions.featureAccess.canSeeEmployees)
        ? [{ href: "/poultry-staff", label: "Staff", icon: Users2 }]
        : []),
      { href: "/poultry-payroll", label: "Payroll", icon: Banknote },
    ],
  }

  const moreGroup: NavGroup = {
    label: "More",
    items: [
      { href: "/profile", label: "Account", icon: User },
      { href: "/resources", label: "Resources", icon: BookOpen },
      // James 2026-06-02 — Employees and Activity Log removed from the top
      // nav (still in the sidebar).
      ...(permissions.featureAccess.canViewSettings
        ? [{ href: "/settings", label: "Settings", icon: Settings }]
        : []),
    ],
  }

  return (
    <>
      <div className="hidden lg:block bg-orange-500 border-b border-orange-600">
        <div className="flex items-center gap-1 px-4 pt-1.5 pb-2.5 nav-rail-scroll">
          <NavLink item={{ href: "/dashboard", label: "Dashboard", icon: Home }} />
          <div className="h-5 w-px bg-white/30 mx-1" />
          <NavDropdown group={farmGroup} />
          <NavDropdown group={productionGroup} />
          <NavDropdown group={inventoryGroup} />
          {financialGroup.items.length > 0 && <NavDropdown group={financialGroup} />}
          {peopleGroup.items.length > 0 && <NavDropdown group={peopleGroup} />}
          <div className="h-5 w-px bg-white/30 mx-1" />
          {/* Reports opens a hover mega-menu of the 20 poultry reports, sourced
              from lib/reports/poultry-reports-config.ts (shared with the
              /poultry/reports catalogue). */}
          {permissions.featureAccess.canViewReports && <PoultryReportsMegaMenu />}
          <NavDropdown group={analyticsGroup} />
          <NavDropdown group={moreGroup} />
          <div className="ml-auto flex items-center gap-1">
            {(TEMP_SHOW_PAYMENTS_LINK || permissions.isAdmin || permissions.featureAccess.canViewFinancial) && (
              <NavLink item={{ href: "/payments", label: "Payments", icon: CreditCard }} />
            )}
            <NavLink item={{ href: "/terms", label: "Terms", icon: FileText }} />
            <NavLink item={{ href: "/help", label: "Help Center", icon: BookOpen }} />
          </div>
        </div>
      </div>

      {/* Mobile: top nav replaced by MobileBottomNav (bottom tab bar) */}
    </>
  )
}



