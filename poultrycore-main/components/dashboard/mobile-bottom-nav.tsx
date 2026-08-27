"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { useEffect, useState } from "react"
import { cn } from "@/lib/utils"
import { usePermissions } from "@/hooks/use-permissions"
import { isFinancialNavItemVisible } from "@/lib/utils/financial-nav-access"
import { filterWaterNavItems } from "@/lib/utils/water-nav-access"
import { useAuthStore } from "@/lib/store/auth-store"
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
  History,
} from "lucide-react"
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet"

interface NavItem {
  href: string
  label: string
  icon: LucideIcon
}

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
  const [sheetOpen, setSheetOpen] = useState(false)
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
        // Order mirrors the sidebar reorg (Quick Links → Delivery → Production
        // → Inventory → Sales & Money → Finance → People → Reports →
        // Admin/Setup) so the mental model is the same between desktop and
        // mobile.
        moreItems: gateWater([
          // Quick Links shortcuts (the most-used daily flows)
          { href: "/water-daily-closing", label: "Daily Closing",     icon: FileText },
          { href: "/water-driver-returns", label: "Deliveries",       icon: Truck },
          // Delivery group
          { href: "/water-drivers",       label: "Drivers",           icon: Users2 },
          { href: "/water-vehicles",      label: "Vehicles",          icon: Truck },
          { href: "/water-routes",        label: "Routes",            icon: Activity },
          // Production group
          { href: "/water-daily-production", label: "Batch Production", icon: CalendarDays },
          { href: "/water-products",      label: "Products",          icon: ShoppingBag },
          { href: "/water-machines",      label: "Machines",          icon: Cog },
          { href: "/water-boreholes",     label: "Boreholes",         icon: Droplets },
          { href: "/water-maintenance",   label: "Maintenance",       icon: Wrench },
          // Inventory group
          { href: "/water-stock",         label: "Stock movement",    icon: Boxes },
          { href: "/water-inventory",     label: "Inventory",         icon: Boxes },
          { href: "/water-raw-materials", label: "Raw materials & supplies", icon: Box },
          { href: "/water-internal-use",  label: "Internal Use",      icon: PackageMinus },
          { href: "/water-loss-records",  label: "Damages & loss",    icon: AlertTriangle },
          // Sales & Money
          { href: "/water-payments",      label: "Payments",          icon: CreditCard },
          { href: "/water-customer-balances", label: "Customer Balances", icon: Users },
          { href: "/water-supplier-balances", label: "Supplier Balances", icon: Truck },
          { href: "/water-expenses",      label: "Expenses",          icon: Receipt },
          { href: "/water-cash-accounts", label: "Cash accounts",     icon: Wallet },
          // Finance — Customers and Suppliers sit together here, matching the
          // sidebar's Finance group and the top nav's Setup > Finance column.
          { href: "/water-customers",     label: "Customers",         icon: Users },
          { href: "/water-suppliers",     label: "Suppliers",         icon: Truck },
          // People
          { href: "/water-staff",         label: "Staff",             icon: Users2 },
          { href: "/water-payroll",       label: "Payroll",           icon: Banknote },
          // Analytics + Reports + Admin
          { href: "/water-inventory-tracker", label: "Inventory tracker", icon: History },
          { href: "/water-reports",       label: "Reports",           icon: BarChart3 },
          { href: "/water-driver-report", label: "Driver report",     icon: BarChart3 },
          // Match desktop sidebar (components/dashboard/sidebar.tsx waterAdminItems):
          // "Setup" → /water-setup, "Company Setup" → /water-company-setup. The
          // earlier mobile rail collapsed both into a single "Setup" entry that
          // pointed at /water-company-setup, so tapping it landed users on the
          // wrong page vs. desktop.
          { href: "/water-setup",         label: "Setup",             icon: Settings },
          { href: "/water-company-setup", label: "Company Setup",     icon: Settings },
          { href: "/profile",             label: "Account",           icon: User },
          ...(permissions.featureAccess.canViewActivityLog
            ? [{ href: "/audit-logs", label: "Activity Log", icon: Activity }] : []),
          ...(permissions.isAdmin || permissions.featureAccess.canSeeEmployees
            ? [{ href: "/employees", label: "Employees", icon: UserCog }] : []),
        ] as NavItem[]),
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
        moreItems: [
          { href: "/generic-inventory",          label: "Inventory",         icon: Boxes },
          { href: "/generic-stock-adjustments",  label: "Stock adjustments", icon: Boxes },
          { href: "/generic-internal-use",       label: "Internal Use",      icon: PackageMinus },
          { href: "/generic-customers",          label: "Customers",         icon: Users },
          { href: "/generic-customer-payments",  label: "Customer payments", icon: CreditCard },
          { href: "/generic-suppliers",          label: "Suppliers",         icon: Truck },
          { href: "/generic-supplier-payments",  label: "Supplier payments", icon: CreditCard },
          { href: "/generic-expenses",           label: "Expenses",          icon: DollarSign },
          { href: "/generic-cash",               label: "Cash & Accounts",   icon: Wallet },
          { href: "/generic-cash-transfers",     label: "Cash transfers",    icon: Activity },
          { href: "/generic-daily-closings",     label: "Daily Closing",     icon: FileText },
          { href: "/generic-staff",              label: "Staff",             icon: Users2 },
          { href: "/generic-attendance",         label: "Attendance",        icon: Activity },
          { href: "/generic-payroll",            label: "Payroll",           icon: Banknote },
          { href: "/generic-reports",            label: "Reports",           icon: BarChart3 },
          { href: "/generic-setup",              label: "Setup",             icon: Settings },
          { href: "/profile",                    label: "Account",           icon: User },
          ...(permissions.featureAccess.canViewActivityLog
            ? [{ href: "/audit-logs", label: "Activity Log", icon: Activity }] : []),
          ...(permissions.isAdmin || permissions.featureAccess.canSeeEmployees
            ? [{ href: "/employees", label: "Employees", icon: UserCog }] : []),
        ] as NavItem[],
      }
    }

    // Default: Poultry (also used when activeFarmType is null/undefined during
    // hydration, since the dashboard route is /dashboard either way).
    const TEMP_SHOW_PAYMENTS_LINK = true
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
    // Mirrors the desktop poultry sidebar so mobile has the same, correctly-
    // targeted destinations. Key fix: "Inventory" → the new /poultry-inventory;
    // the legacy page is listed separately as "Other Inventory" → /inventory.
    const poultryMore: NavItem[] = [
      // Farm — Houses and Flock Groups moved to the Setup block at the end.
      { href: "/flock-batch",            label: "Flock Purchases",        icon: Boxes },
      // Production
      { href: "/egg-production",         label: "Egg sorting",            icon: Egg },
      { href: "/feed-usage",             label: "Feed Usage",             icon: Package },
      { href: "/poultry-products",       label: "Products",               icon: ShoppingBag },
      // Analytics
      { href: "/egg-tracker",            label: "Egg tracker",            icon: BarChart3 },
      { href: "/feed-tracker",           label: "Feed at hand",           icon: Wheat },
      { href: "/medication-tracker",     label: "Medication at hand",     icon: Pill },
      { href: "/birds-left-tracker",     label: "Birds left tracker",     icon: Bird },
      { href: "/weekly-report",          label: "Analytical Report",      icon: FileText },
      // Inventory & Health
      { href: "/poultry-inventory",      label: "Inventory",              icon: Boxes },
      { href: "/poultry-stock",          label: "Stock movements",        icon: Boxes },
      { href: "/poultry-raw-materials",  label: "Raw Materials & Supplies", icon: Box },
      { href: "/supplies",               label: "Supplies",               icon: ShoppingCart },
      { href: "/health",                 label: "Health Records",         icon: AlertTriangle },
      { href: "/poultry-internal-use",   label: "Internal Use",           icon: PackageMinus },
      { href: "/poultry-loss-records",   label: "Loss & Damage",          icon: AlertTriangle },
      { href: "/inventory",              label: "Other Inventory",        icon: Package },
      // Delivery
      { href: "/poultry-driver-returns", label: "Deliveries",             icon: Truck },
      { href: "/poultry-drivers",        label: "Drivers",                icon: Users2 },
      { href: "/poultry-vehicles",       label: "Vehicles",               icon: Truck },
      { href: "/poultry-routes",         label: "Routes",                 icon: Activity },
      { href: "/poultry-driver-report",  label: "Driver report",          icon: BarChart3 },
      // Financial
      { href: "/poultry-daily-closing",  label: "Daily Closing",          icon: FileText },
      { href: "/cash",                   label: "Cash",                   icon: Wallet },
      { href: "/poultry-cash-accounts",  label: "Cash Account",           icon: Wallet },
      { href: "/poultry-payments",       label: "Payments received",      icon: CreditCard },
      { href: "/customer-balances",      label: "Customer Balances",      icon: Users },
      { href: "/supplier-balances",      label: "Supplier Balances",      icon: Truck },
      { href: "/expenses",               label: "Expenses",               icon: DollarSign },
      { href: "/billing",                label: "Billing",                icon: CreditCard },
      // Finance — Customers and Suppliers sit together here, matching the
      // sidebar's Finance group and the top nav's Setup > Finance column.
      { href: "/customers",              label: "Customers",              icon: Users },
      { href: "/suppliers",              label: "Suppliers",              icon: Truck },
      // Setup — the farm master data behind the daily flows (top nav:
      // Setup > Farm). Flock Groups is NOT repeated here: it's a main tab, and
      // anything listed in moreItems also lights up the "More" button, so the
      // bar would show two active tabs on /flocks.
      { href: "/houses",                 label: "Houses",                 icon: Home },
      // Reports / Help / Account
      { href: "/reports",                label: "Reports",                icon: BarChart3 },
      { href: "/resources",              label: "Resources",              icon: BookOpen },
      { href: "/help",                   label: "Help Center",            icon: BookOpen },
      { href: "/profile",                label: "Account",                icon: User },
      { href: "/audit-logs",             label: "Activity Log",           icon: Activity },
      { href: "/poultry-setup",          label: "Farm Setup",             icon: Settings },
      { href: "/poultry-company-setup",  label: "Company Setup",          icon: Settings },
      { href: "/terms",                  label: "Terms",                  icon: FileText },
      ...(permissions.isAdmin || permissions.featureAccess.canSeeEmployees
        ? [{ href: "/employees", label: "Employees", icon: UserCog }] : []),
    ]
    const filteredPoultryMore = poultryMore.filter((item) => {
      if (["/sales", "/expenses", "/cash", "/customers", "/suppliers", "/billing", "/poultry-cash-accounts", "/poultry-payments", "/customer-balances", "/supplier-balances"].includes(item.href)) {
        return isFinancialNavItemVisible(item.href, permissions.featureAccess, permissions.isAdmin, {
          tempShowPayments: TEMP_SHOW_PAYMENTS_LINK,
        })
      }
      if (item.href === "/reports") return permissions.featureAccess.canViewReports
      if (item.href === "/audit-logs") return permissions.featureAccess.canViewActivityLog
      if (item.href === "/poultry-company-setup" || item.href === "/poultry-setup") return permissions.featureAccess.canViewSettings
      return true
    })
    return {
      bg: "bg-orange-500",
      borderTop: "border-orange-600",
      palette: { inactive: "text-orange-100/90 hover:text-white", activeText: "text-white" },
      activeBg: "bg-orange-100 text-orange-800",
      mainTabs: visiblePoultryMain,
      moreItems: filteredPoultryMore,
    }
  })()

  if (!mounted) return null

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

        <Sheet open={sheetOpen} onOpenChange={setSheetOpen}>
          <SheetTrigger asChild>
            <button
              className={cn(
                "flex flex-col items-center justify-center gap-1 min-h-[44px] min-w-[44px] flex-1 py-1.5 px-1 transition-colors",
                config.moreItems.some(
                  (i) => pathname === i.href || pathname.startsWith(`${i.href}/`)
                )
                  ? config.palette.activeText
                  : config.palette.inactive,
              )}
              aria-label="More"
            >
              {(() => {
                const moreActive = config.moreItems.some((i) => pathname === i.href || pathname.startsWith(`${i.href}/`))
                return (
                  <span className={cn("flex items-center justify-center h-7 w-12 rounded-full transition-colors", moreActive ? "bg-white/20" : "bg-transparent")}>
                    <MoreHorizontal className="h-[22px] w-[22px] shrink-0" />
                  </span>
                )
              })()}
              <span className="text-[10px] font-medium leading-none">More</span>
            </button>
          </SheetTrigger>
          <SheetContent side="bottom" className="rounded-t-2xl max-h-[75vh] pb-[env(safe-area-inset-bottom)]">
            <SheetHeader>
              <SheetTitle>More</SheetTitle>
            </SheetHeader>
            <div className="grid grid-cols-2 gap-2 overflow-y-auto -mx-4 px-4 pb-4">
              {config.moreItems.map((item) => {
                const Icon = item.icon
                const isActive =
                  pathname === item.href || pathname.startsWith(`${item.href}/`)
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    onClick={() => setSheetOpen(false)}
                    className={cn(
                      "flex items-center gap-3 p-3 rounded-xl transition-colors min-h-[44px]",
                      isActive
                        ? `${config.activeBg} font-medium`
                        : "bg-slate-100 text-slate-700 hover:bg-slate-200",
                    )}
                  >
                    <Icon className="h-5 w-5 shrink-0" />
                    <span className="text-sm truncate">{item.label}</span>
                  </Link>
                )
              })}
            </div>
          </SheetContent>
        </Sheet>
      </div>
    </nav>
  )
}
