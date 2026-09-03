"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { useEffect, useState } from "react"
import { cn } from "@/lib/utils"
import { usePermissions } from "@/hooks/use-permissions"
import { isFinancialNavItemVisible } from "@/lib/utils/financial-nav-access"
import { filterWaterNavItems } from "@/lib/utils/water-nav-access"
import { useAuthStore } from "@/lib/store/auth-store"
import { useAlertsStore } from "@/lib/store/alerts-store"
import { buildPoultryNavConfig } from "@/lib/nav/poultry-nav-config"
import { POULTRY_REPORT_NAV_GROUPS } from "@/lib/nav/report-nav-adapters"
import type { MegaMenuGroup } from "@/lib/nav/nav-model"
import {
  Home,
  Bird,
  FileText,
  ShoppingCart,
  MoreHorizontal,
  Package,
  PackageMinus,
  BookOpen,
  AlertTriangle,
  Wallet,
  DollarSign,
  Users,
  Egg,
  BarChart3,
  User,
  Settings,
  Activity,
  UserCog,
  CreditCard,
  LucideIcon,
  Wheat,
  Pill,
  Truck,
  Droplets,
  ShoppingBag,
  Boxes,
  Factory,
  Box,
  Cog,
  Users2,
  Wrench,
  Banknote,
  Receipt,
  CalendarDays,
  Building2,
  History,
  Scale,
  Clock,
  Search,
  ChevronDown,
} from "lucide-react"
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet"

interface NavItem {
  href: string
  label: string
  icon: LucideIcon
}

/**
 * "More" is a whole navigation tree, not an overflow bin. Forty-odd links in
 * one flat grid meant reading every label to find anything.
 *
 * It now mirrors the DESKTOP TOP NAV: the same sections in the same order
 * (Quick Links, Operations, Sales & Money, Analytics, Reports, Setup, System),
 * each holding the same column groups. For Poultry the contents are read
 * straight out of lib/nav/poultry-nav-config.ts — the very config the top nav
 * renders — so the two cannot drift apart.
 *
 * On a phone the sections are an accordion rather than seven mega-menus: one
 * section open at a time, exactly like tapping one dropdown on the rail.
 */
interface NavGroup {
  /** Column heading inside a section. Empty string renders no sub-heading. */
  title: string
  items: NavItem[]
}

interface NavSection {
  title: string
  groups: NavGroup[]
}

// Groups (and sections) that gate away to nothing must not leave a heading.
const compactGroups = (groups: NavGroup[]): NavGroup[] => groups.filter((g) => g.items.length > 0)
const compactSections = (sections: NavSection[]): NavSection[] =>
  sections
    .map((sec) => ({ ...sec, groups: compactGroups(sec.groups) }))
    .filter((sec) => sec.groups.length > 0)

/** A flat list of groups becomes one section per group (water / generic / hotel). */
const asSections = (groups: NavGroup[]): NavSection[] =>
  compactSections(groups.map((g) => ({ title: g.title, groups: [{ title: "", items: g.items }] })))

/**
 * The top nav's mega-menu rows carry `visible` gates, action rows with no href,
 * and `title` where the mobile rail uses `label`. Normalise to plain links.
 */
const fromMegaMenu = (groups: MegaMenuGroup[]): NavGroup[] =>
  compactGroups(groups.map((g) => ({
    title: g.label,
    items: g.items
      .filter((i) => i.visible !== false && !!i.href)
      .map((i) => ({ href: i.href as string, label: i.title, icon: i.icon })),
  })))

function TabLink({
  item, isActive, palette,
}: {
  item: NavItem
  isActive: boolean
  palette: { inactive: string; activeText: string }
}) {
  const Icon = item.icon
  return (
    <Link
      href={item.href}
      prefetch={true}
      className={cn(
        "flex flex-col items-center justify-center gap-1 min-h-[44px] min-w-[44px] flex-1 py-1.5 px-1 transition-colors",
        isActive ? palette.activeText : palette.inactive,
      )}
      aria-label={item.label}
      aria-current={isActive ? "page" : undefined}
    >
      {/* Material-style active pill behind the icon for a clearer, more premium
          active state than colour-only. */}
      <span
        className={cn(
          "flex items-center justify-center h-7 w-12 rounded-full transition-colors",
          isActive ? "bg-white/20" : "bg-transparent",
        )}
      >
        <Icon className="h-[22px] w-[22px] shrink-0" strokeWidth={isActive ? 2.5 : 2} />
      </span>
      <span className="text-[10px] font-medium truncate max-w-full leading-none">{item.label}</span>
    </Link>
  )
}

export function MobileBottomNav() {
  const pathname = usePathname()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  // buildPoultryNavConfig wants these for its Alerts action row. That row has
  // no href so it is filtered out of the sheet, but the config still asks.
  const openAlerts = useAlertsStore((st) => st.open)
  const alertCount = useAlertsStore((st) => st.alerts.length)
  const [sheetOpen, setSheetOpen] = useState(false)
  // Forty-odd destinations is more than anyone scans. Typing filters across
  // every group at once; clearing it restores the grouped view.
  const [moreQuery, setMoreQuery] = useState("")
  // Which accordion sections the user has toggled. Anything not in here falls
  // back to "open if it holds the current page".
  const [openSections, setOpenSections] = useState<Record<string, boolean>>({})
  // The tabs are built from the persisted (localStorage) auth store, which is
  // empty during SSR and populated on the client — rendering before mount makes
  // the tree (and Radix useId ids) differ, causing a hydration mismatch. Render
  // only after mount so SSR and the first client paint agree.
  const [mounted, setMounted] = useState(false)
  useEffect(() => setMounted(true), [])

  // Per-company-type bar config. The 4 main tabs are the most-used daily flow
  // pages for each company; everything else goes into "More". Colours match
  // the desktop top-nav so the company-type identity is consistent.
  const config = (() => {
    if (activeFarmType === "Water") {
      // Staff Page Access gate, same route -> flag map the sidebar and top nav
      // use (lib/utils/water-nav-access) so all three surfaces agree.
      const gateWater = (items: NavItem[]) =>
        filterWaterNavItems(items, permissions.featureAccess, permissions.isAdmin)

      return {
        bg: "bg-sky-600",
        borderTop: "border-sky-700",
        palette: { inactive: "text-sky-100/90 hover:text-white", activeText: "text-white" },
        activeBg: "bg-sky-100 text-sky-800",
        mainTabs: gateWater([
          { href: "/water-dashboard",          label: "Home",       icon: Droplets },
          { href: "/water-production-batches", label: "Production", icon: Factory },
          { href: "/water-driver-returns",     label: "Deliveries", icon: Truck },
          { href: "/water-sales",              label: "Sales",      icon: ShoppingCart },
        ] as NavItem[]),
        // Same groups, same order as the desktop water sidebar.
        moreGroups: asSections([
          { title: "Quick Links", items: gateWater([
            { href: "/water-daily-closing",  label: "Daily Closing",  icon: FileText },
            { href: "/water-driver-returns", label: "Deliveries",     icon: Truck },
          ] as NavItem[]) },
          { title: "Delivery", items: gateWater([
            { href: "/water-drivers",       label: "Drivers",       icon: Users2 },
            { href: "/water-vehicles",      label: "Vehicles",      icon: Truck },
            { href: "/water-routes",        label: "Routes",        icon: Activity },
            { href: "/water-driver-report", label: "Driver report", icon: BarChart3 },
          ] as NavItem[]) },
          { title: "Production", items: gateWater([
            { href: "/water-daily-production", label: "Batch Production", icon: CalendarDays },
            { href: "/water-products",         label: "Products",         icon: ShoppingBag },
            { href: "/water-machines",         label: "Machines",         icon: Cog },
            { href: "/water-boreholes",        label: "Boreholes",        icon: Droplets },
            { href: "/water-maintenance",      label: "Maintenance",      icon: Wrench },
          ] as NavItem[]) },
          { title: "Inventory", items: gateWater([
            { href: "/water-stock",             label: "Stock movement",           icon: Boxes },
            { href: "/water-inventory",         label: "Inventory",                icon: Boxes },
            { href: "/water-raw-materials",     label: "Raw materials & supplies", icon: Box },
            { href: "/water-internal-use",      label: "Internal Use",             icon: PackageMinus },
            { href: "/water-loss-records",      label: "Damages & loss",           icon: AlertTriangle },
            { href: "/water-production-losses", label: "Production losses",        icon: AlertTriangle },
          ] as NavItem[]) },
          { title: "Sales & Money", items: gateWater([
            { href: "/water-payments",            label: "Payments",          icon: CreditCard },
            { href: "/water-customer-balances",   label: "Customer Balances", icon: Users },
            { href: "/water-supplier-balances",   label: "Supplier Balances", icon: Truck },
            { href: "/water-expenses",            label: "Expenses",          icon: Receipt },
            { href: "/water-cash-flow",           label: "Cash Flow",         icon: Wallet },
            { href: "/water-cash-accounts",       label: "Cash accounts",     icon: Wallet },
            { href: "/water-cash-reconciliation", label: "Reconcile cash",    icon: Scale },
          ] as NavItem[]) },
          { title: "Finance", items: gateWater([
            { href: "/water-customers", label: "Customers", icon: Users },
            { href: "/water-suppliers", label: "Suppliers", icon: Truck },
          ] as NavItem[]) },
          { title: "People", items: gateWater([
            { href: "/water-staff",   label: "Staff",   icon: Users2 },
            { href: "/water-payroll", label: "Payroll", icon: Banknote },
          ] as NavItem[]) },
          { title: "Analytics & Reports", items: gateWater([
            { href: "/water-inventory-tracker", label: "Inventory tracker", icon: History },
            { href: "/water-reports",           label: "Reports",           icon: BarChart3 },
          ] as NavItem[]) },
          { title: "System", items: [
            ...gateWater([
              { href: "/water-setup",         label: "Setup",         icon: Settings },
              { href: "/water-company-setup", label: "Company Setup", icon: Settings },
            ] as NavItem[]),
            ...(permissions.isAdmin || permissions.featureAccess.canSeeEmployees
              ? [{ href: "/employees", label: "Users & Permissions", icon: UserCog }] : []),
            { href: "/profile",   label: "Account",   icon: User },
            { href: "/companies", label: "Companies", icon: Building2 },
            ...(permissions.featureAccess.canViewActivityLog
              ? [{ href: "/audit-logs", label: "Activity Log", icon: Activity }] : []),
            { href: "/terms", label: "Terms & Conditions", icon: FileText },
          ] as NavItem[] },
        ]),
      }
    }

    if (activeFarmType === "Generic") {
      return {
        bg: "bg-emerald-600",
        borderTop: "border-emerald-700",
        palette: { inactive: "text-emerald-100/90 hover:text-white", activeText: "text-white" },
        activeBg: "bg-emerald-100 text-emerald-800",
        mainTabs: [
          { href: "/generic-dashboard", label: "Home",      icon: Home },
          { href: "/generic-products",  label: "Products",  icon: ShoppingBag },
          { href: "/generic-sales",     label: "Sales",     icon: ShoppingCart },
          { href: "/generic-purchases", label: "Purchases", icon: Package },
        ] as NavItem[],
        moreGroups: asSections([
          { title: "Inventory", items: [
            { href: "/generic-inventory",         label: "Inventory",         icon: Boxes },
            { href: "/generic-stock-adjustments", label: "Stock adjustments", icon: Boxes },
            { href: "/generic-internal-use",      label: "Internal Use",      icon: PackageMinus },
          ] as NavItem[] },
          { title: "Sales & Money", items: [
            { href: "/generic-customer-payments", label: "Customer payments", icon: CreditCard },
            { href: "/generic-supplier-payments", label: "Supplier payments", icon: CreditCard },
            { href: "/generic-expenses",          label: "Expenses",          icon: DollarSign },
            { href: "/generic-cash",              label: "Cash & Accounts",   icon: Wallet },
            { href: "/generic-cash-transfers",    label: "Cash transfers",    icon: Activity },
            { href: "/generic-daily-closings",    label: "Daily Closing",     icon: FileText },
          ] as NavItem[] },
          { title: "Finance", items: [
            { href: "/generic-customers", label: "Customers", icon: Users },
            { href: "/generic-suppliers", label: "Suppliers", icon: Truck },
          ] as NavItem[] },
          { title: "People", items: [
            { href: "/generic-staff",      label: "Staff",      icon: Users2 },
            { href: "/generic-attendance", label: "Attendance", icon: Activity },
            { href: "/generic-payroll",    label: "Payroll",    icon: Banknote },
          ] as NavItem[] },
          { title: "Reports", items: [
            { href: "/generic-reports", label: "Reports", icon: BarChart3 },
          ] as NavItem[] },
          { title: "System", items: [
            { href: "/generic-setup", label: "Setup",   icon: Settings },
            ...(permissions.isAdmin || permissions.featureAccess.canSeeEmployees
              ? [{ href: "/employees", label: "Users & Permissions", icon: UserCog }] : []),
            { href: "/profile",   label: "Account",   icon: User },
            { href: "/companies", label: "Companies", icon: Building2 },
            ...(permissions.featureAccess.canViewActivityLog
              ? [{ href: "/audit-logs", label: "Activity Log", icon: Activity }] : []),
            { href: "/terms", label: "Terms & Conditions", icon: FileText },
          ] as NavItem[] },
        ]),
      }
    }

    if (activeFarmType === "Hotel") {
      return {
        bg: "bg-violet-600",
        borderTop: "border-violet-700",
        palette: { inactive: "text-violet-100/90 hover:text-white", activeText: "text-white" },
        activeBg: "bg-violet-100 text-violet-800",
        mainTabs: [
          { href: "/hotel-dashboard", label: "Home",     icon: Home },
          { href: "/hotel-bookings",  label: "Bookings", icon: FileText },
          { href: "/hotel-rooms",     label: "Rooms",    icon: Building2 },
          { href: "/hotel-guests",    label: "Guests",   icon: Users },
        ] as NavItem[],
        moreGroups: asSections([
          { title: "Front Desk", items: [
            { href: "/hotel-check-in",     label: "Check-in",     icon: Activity },
            { href: "/hotel-check-out",    label: "Check-out",    icon: Activity },
            { href: "/hotel-availability", label: "Availability", icon: Activity },
            { href: "/hotel-guest-folio",  label: "Guest Folio",  icon: FileText },
            { href: "/hotel-stay-history", label: "Stay History", icon: FileText },
            { href: "/hotel-night-audit",  label: "Night Audit",  icon: FileText },
          ] as NavItem[] },
          { title: "Guest Services", items: [
            { href: "/hotel-communications", label: "Guest Log",    icon: FileText },
            { href: "/hotel-guest-requests", label: "Requests",     icon: Activity },
            { href: "/hotel-lost-found",     label: "Lost & Found", icon: Boxes },
          ] as NavItem[] },
          { title: "Rooms & Service", items: [
            { href: "/hotel-housekeeping", label: "Housekeeping", icon: Factory },
            { href: "/hotel-room-service", label: "Room Service", icon: ShoppingCart },
            { href: "/hotel-restaurant",   label: "Restaurant",   icon: ShoppingCart },
            { href: "/hotel-menu",         label: "Menu Items",   icon: ShoppingBag },
            { href: "/hotel-housekeeping-schedule", label: "HK Schedule", icon: Activity },
            { href: "/hotel-restaurant-tables",     label: "Tables",      icon: Boxes },
            { href: "/hotel-kitchen",               label: "Kitchen",     icon: Activity },
          ] as NavItem[] },
          { title: "Billing & Money", items: [
            { href: "/hotel-billing",       label: "Billing",       icon: DollarSign },
            { href: "/hotel-invoices",      label: "Invoices",      icon: FileText },
            { href: "/hotel-payments",      label: "Payments",      icon: CreditCard },
            { href: "/hotel-expenses",      label: "Expenses",      icon: DollarSign },
            { href: "/hotel-cash-accounts", label: "Cash Accounts", icon: Wallet },
            { href: "/hotel-daily-closing", label: "Daily Closing", icon: FileText },
          ] as NavItem[] },
          { title: "People", items: [
            { href: "/hotel-staff",   label: "Staff",   icon: Users2 },
            { href: "/hotel-payroll", label: "Payroll", icon: Banknote },
          ] as NavItem[] },
          { title: "Inventory & Reports", items: [
            { href: "/hotel-inventory",   label: "Supplies",    icon: Boxes },
            { href: "/hotel-maintenance", label: "Maintenance", icon: Wrench },
            { href: "/hotel-reports",     label: "Reports",     icon: BarChart3 },
            { href: "/hotel-shift-handover", label: "Shift Handover", icon: FileText },
          ] as NavItem[] },
          { title: "System", items: [
            { href: "/hotel-setup", label: "Setup",     icon: Settings },
            { href: "/profile",     label: "Account",   icon: User },
            { href: "/companies",   label: "Companies", icon: Building2 },
          ] as NavItem[] },
        ]),
      }
    }

    // Default: Poultry (also used when activeFarmType is null/undefined during
    // hydration, since the dashboard route is /dashboard either way).
    const poultryMain: NavItem[] = [
      { href: "/dashboard",          label: "Home",       icon: Home },
      { href: "/flocks",             label: "Flocks",     icon: Bird },
      { href: "/production-records", label: "Production", icon: FileText },
      { href: "/sales",              label: "Sales",      icon: ShoppingCart },
    ]
    const visiblePoultryMain = poultryMain.filter((item) => {
      if (item.href === "/sales") return permissions.featureAccess.canEnterSales
      return true
    })
    // Read the DESKTOP TOP NAV's own config rather than keeping a third copy of
    // the poultry nav. Same sections, same order, same permission gates as the
    // rail: Quick Links | Operations | Sales & Money | Analytics | Reports |
    // Setup, then System.
    const nav = buildPoultryNavConfig({ permissions, onOpenAlerts: openAlerts, alertCount })
    const filteredPoultryMore = compactSections([
      { title: "Quick Links", groups: [{ title: "", items: nav.quickLinks.items }] },
      { title: "Operations",    groups: fromMegaMenu(nav.operations) },
      { title: "Sales & Money", groups: fromMegaMenu(nav.salesMoney) },
      { title: "Analytics",     groups: fromMegaMenu(nav.analytics) },
      // The rail hides the whole Reports menu behind canViewReports.
      ...(permissions.featureAccess.canViewReports
        ? [{ title: "Reports", groups: [
            // The rail reaches these two through its trigger and its
            // "View all reports" link, neither of which survives as a row.
            { title: "Overview", items: [
              { href: "/reports",         label: "Reports Dashboard", icon: BarChart3 },
              { href: "/poultry/reports", label: "All reports",       icon: BookOpen },
            ] },
            ...fromMegaMenu(POULTRY_REPORT_NAV_GROUPS),
          ] }]
        : []),
      { title: "Setup",  groups: fromMegaMenu(nav.setup) },
      { title: "System", groups: fromMegaMenu(nav.system) },
    ])
    return {
      bg: "bg-orange-500",
      borderTop: "border-orange-600",
      palette: { inactive: "text-orange-100/90 hover:text-white", activeText: "text-white" },
      activeBg: "bg-orange-100 text-orange-800",
      mainTabs: visiblePoultryMain,
      moreGroups: filteredPoultryMore,
    }
  })()

  if (!mounted) return null

  const itemActive = (href: string) =>
    pathname === href || (href !== "/dashboard" && pathname.startsWith(`${href}/`))

  // The top nav lists Production Records and Sales inside their sections AND as
  // Quick Links, and both are main tabs down here. Excluding the main tabs from
  // this test stops the bar lighting up two tabs at once on those routes.
  const mainHrefs = new Set(config.mainTabs.map((t) => t.href))
  const moreActive = config.moreGroups.some((sec) =>
    sec.groups.some((g) => g.items.some((i) => !mainHrefs.has(i.href) && itemActive(i.href))),
  )

  const q = moreQuery.trim().toLowerCase()
  const visibleMoreSections = q
    ? config.moreGroups
        .map((sec) => ({
          ...sec,
          groups: sec.groups
            .map((g) => ({ ...g, items: g.items.filter((i) => i.label.toLowerCase().includes(q)) }))
            .filter((g) => g.items.length > 0),
        }))
        .filter((sec) => sec.groups.length > 0)
    : config.moreGroups

  // The section holding the current page opens by default, so the sheet lands
  // you where you already are rather than on a wall of closed headings.
  const activeSectionTitle = config.moreGroups.find((sec) =>
    sec.groups.some((g) => g.items.some((i) => !mainHrefs.has(i.href) && itemActive(i.href))),
  )?.title
  // A search matches across every section, so they all open while typing.
  const sectionIsOpen = (title: string) =>
    q ? true : (openSections[title] ?? title === activeSectionTitle)
  const toggleSection = (title: string) =>
    setOpenSections((prev) => ({ ...prev, [title]: !sectionIsOpen(title) }))

  const isProductionActive =
    pathname === "/production-records" ||
    pathname.startsWith("/production-records/") ||
    pathname === "/egg-production" ||
    pathname.startsWith("/egg-production/")

  return (
    <nav
      className={cn(
        "lg:hidden fixed bottom-0 left-0 right-0 z-40 border-t pb-[env(safe-area-inset-bottom)] shadow-[0_-2px_10px_rgba(0,0,0,0.15)]",
        config.bg, config.borderTop,
      )}
      role="navigation"
      aria-label="Main navigation"
    >
      <div className="flex items-stretch justify-around px-2 py-2">
        {config.mainTabs.map((item) => {
          const isActive =
            item.href === "/production-records"
              ? isProductionActive
              : pathname === item.href || pathname.startsWith(`${item.href}/`)
          return <TabLink key={item.href} item={item} isActive={isActive} palette={config.palette} />
        })}

        <Sheet
          open={sheetOpen}
          onOpenChange={(o) => { setSheetOpen(o); if (!o) { setMoreQuery(""); setOpenSections({}) } }}
        >
          <SheetTrigger asChild>
            <button
              className={cn(
                "flex flex-col items-center justify-center gap-1 min-h-[44px] min-w-[44px] flex-1 py-1.5 px-1 transition-colors",
                moreActive ? config.palette.activeText : config.palette.inactive,
              )}
              aria-label="More"
            >
              <span className={cn("flex items-center justify-center h-7 w-12 rounded-full transition-colors", moreActive ? "bg-white/20" : "bg-transparent")}>
                <MoreHorizontal className="h-[22px] w-[22px] shrink-0" />
              </span>
              <span className="text-[10px] font-medium leading-none">More</span>
            </button>
          </SheetTrigger>
          {/* Taller than before (85vh): the grouped list is longer, and a short
              sheet meant scrolling a scroll. p-0 so the search bar can stick to
              the top edge while the list scrolls under it. */}
          <SheetContent
            side="bottom"
            className="flex max-h-[85vh] flex-col gap-0 rounded-t-2xl p-0 pb-[env(safe-area-inset-bottom)]"
          >
            <SheetHeader className="shrink-0 px-4 pt-4 pb-2 text-left">
              <SheetTitle>All pages</SheetTitle>
              {/* Radix warns when a dialog has no description; it is only for
                  screen readers, so it is visually hidden. */}
              <SheetDescription className="sr-only">
                Every page available for this company, grouped as on the desktop menu.
              </SheetDescription>
            </SheetHeader>

            <div className="shrink-0 px-4 pb-3">
              <div className="relative">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                <input
                  type="search"
                  value={moreQuery}
                  onChange={(e) => setMoreQuery(e.target.value)}
                  placeholder="Search pages…"
                  aria-label="Search pages"
                  className="h-11 w-full rounded-xl border border-slate-200 bg-slate-50 pl-9 pr-3 text-sm outline-none placeholder:text-slate-400 focus:border-slate-400 focus:bg-white"
                />
              </div>
            </div>

            <div className="min-h-0 flex-1 divide-y divide-slate-100 overflow-y-auto px-4 pb-6">
              {visibleMoreSections.length === 0 ? (
                <p className="py-8 text-center text-sm text-slate-500">
                  No page matches “{moreQuery}”.
                </p>
              ) : visibleMoreSections.map((section) => {
                const expanded = sectionIsOpen(section.title)
                const count = section.groups.reduce((n, g) => n + g.items.length, 0)
                return (
                  <div key={section.title} className="py-1">
                    {/* One tap per section, like opening one menu on the rail. */}
                    <button
                      type="button"
                      onClick={() => toggleSection(section.title)}
                      aria-expanded={expanded}
                      className="flex min-h-[44px] w-full items-center justify-between gap-2 py-2 text-left"
                    >
                      <span className="text-sm font-semibold text-slate-900">{section.title}</span>
                      <span className="flex items-center gap-2">
                        <span className="text-xs tabular-nums text-slate-400">{count}</span>
                        <ChevronDown
                          className={cn(
                            "h-4 w-4 shrink-0 text-slate-400 transition-transform",
                            expanded && "rotate-180",
                          )}
                        />
                      </span>
                    </button>

                    {expanded && (
                      <div className="space-y-3 pb-3">
                        {section.groups.map((group, gi) => (
                          <div key={group.title || `g${gi}`}>
                            {group.title && (
                              <h4 className="mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-slate-400">
                                {group.title}
                              </h4>
                            )}
                            <div className="grid grid-cols-2 gap-2">
                              {group.items.map((item) => {
                                const Icon = item.icon
                                const isActive = itemActive(item.href)
                                return (
                                  <Link
                                    key={`${group.title}:${item.href}`}
                                    href={item.href}
                                    onClick={() => setSheetOpen(false)}
                                    className={cn(
                                      "flex min-h-[44px] items-center gap-2.5 rounded-xl p-3 transition-colors",
                                      isActive
                                        ? `${config.activeBg} font-medium`
                                        : "bg-slate-100 text-slate-700 hover:bg-slate-200",
                                    )}
                                  >
                                    <Icon className="h-5 w-5 shrink-0" />
                                    <span className="truncate text-sm">{item.label}</span>
                                  </Link>
                                )
                              })}
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                )
              })}
            </div>
          </SheetContent>
        </Sheet>
      </div>
    </nav>
  )
}
