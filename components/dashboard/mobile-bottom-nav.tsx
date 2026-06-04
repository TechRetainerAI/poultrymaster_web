"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { useState } from "react"
import { cn } from "@/lib/utils"
import { usePermissions } from "@/hooks/use-permissions"
import { isFinancialNavItemVisible } from "@/lib/utils/financial-nav-access"
import { useAuthStore } from "@/lib/store/auth-store"
import {
  Home,
  Bird,
  FileText,
  ShoppingCart,
  MoreHorizontal,
  Package,
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
        "flex flex-col items-center justify-center gap-0.5 min-h-[44px] min-w-[44px] flex-1 py-2 px-1 rounded-lg transition-colors active:bg-white/10",
        isActive ? palette.activeText : palette.inactive,
      )}
      aria-label={item.label}
      aria-current={isActive ? "page" : undefined}
    >
      <Icon className="h-6 w-6 shrink-0" strokeWidth={isActive ? 2.5 : 2} />
      <span className="text-[10px] font-medium truncate max-w-full">{item.label}</span>
    </Link>
  )
}

export function MobileBottomNav() {
  const pathname = usePathname()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [sheetOpen, setSheetOpen] = useState(false)

  // Per-company-type bar config. The 4 main tabs are the most-used daily flow
  // pages for each company; everything else goes into "More". Colours match
  // the desktop top-nav so the company-type identity is consistent.
  const config = (() => {
    if (activeFarmType === "Water") {
      return {
        bg: "bg-sky-600",
        borderTop: "border-sky-700",
        palette: { inactive: "text-sky-100/90 hover:text-white", activeText: "text-white" },
        activeBg: "bg-sky-100 text-sky-800",
        mainTabs: [
          { href: "/water-dashboard",          label: "Home",       icon: Droplets },
          { href: "/water-production-batches", label: "Production", icon: Factory },
          { href: "/water-driver-returns",     label: "Deliveries", icon: Truck },
          { href: "/water-sales",              label: "Sales",      icon: ShoppingCart },
        ] as NavItem[],
        // Order mirrors the sidebar reorg (Quick Links → Delivery → Production
        // → Inventory → Sales & Money → People → Reports → Admin/Setup) so the
        // mental model is the same between desktop and mobile.
        moreItems: [
          // Quick Links shortcuts (the most-used daily flows)
          { href: "/water-daily-closing", label: "Daily Closing",     icon: FileText },
          { href: "/water-driver-returns", label: "Deliveries",       icon: Truck },
          // Delivery group — Issue 1 (test-report): Drivers folded into People > Staff (role=Driver).
          { href: "/water-vehicles",      label: "Vehicles",          icon: Truck },
          { href: "/water-routes",        label: "Routes",            icon: Activity },
          // Production group
          { href: "/water-products",      label: "Products",          icon: ShoppingBag },
          { href: "/water-machines",      label: "Machines",          icon: Cog },
          { href: "/water-boreholes",     label: "Boreholes",         icon: Droplets },
          { href: "/water-maintenance",   label: "Maintenance",       icon: Wrench },
          // Inventory group
          { href: "/water-stock",         label: "Stock",             icon: Boxes },
          { href: "/water-inventory",     label: "Inventory",         icon: Boxes },
          { href: "/water-raw-materials", label: "Raw materials & supplies", icon: Box },
          { href: "/water-loss-records",  label: "Damages & loss",    icon: AlertTriangle },
          // Sales & Money
          { href: "/water-customers",     label: "Customers",         icon: Users },
          { href: "/water-payments",      label: "Payments",          icon: CreditCard },
          { href: "/water-expenses",      label: "Expenses",          icon: Receipt },
          { href: "/water-cash-accounts", label: "Cash & Accounts",   icon: Wallet },
          // People
          { href: "/water-staff",         label: "Staff",             icon: Users2 },
          { href: "/water-payroll",       label: "Payroll",           icon: Banknote },
          // Reports + Admin
          { href: "/water-reports",       label: "Reports",           icon: BarChart3 },
          { href: "/water-driver-report", label: "Driver report",     icon: BarChart3 },
          { href: "/water-suppliers",     label: "Suppliers",         icon: Truck },
          { href: "/water-company-setup", label: "Setup",             icon: Settings },
          { href: "/profile",             label: "Account",           icon: User },
          ...(permissions.featureAccess.canViewActivityLog
            ? [{ href: "/audit-logs", label: "Activity Log", icon: Activity }] : []),
          ...(permissions.isAdmin || permissions.featureAccess.canSeeEmployees
            ? [{ href: "/employees", label: "Employees", icon: UserCog }] : []),
        ] as NavItem[],
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
    const poultryMore: NavItem[] = [
      { href: "/inventory",          label: "Inventory",          icon: Package },
      { href: "/help",               label: "Help Center",        icon: BookOpen },
      { href: "/egg-production",     label: "Egg sorting",        icon: Egg },
      { href: "/egg-tracker",        label: "Egg tracker",        icon: BarChart3 },
      { href: "/feed-tracker",       label: "Feed at hand",       icon: Wheat },
      { href: "/medication-tracker", label: "Medication at hand", icon: Pill },
      { href: "/health",             label: "Health Records",     icon: AlertTriangle },
      { href: "/cash",               label: "Cash",               icon: Wallet },
      { href: "/expenses",           label: "Expenses",           icon: DollarSign },
      { href: "/customers",          label: "Customers",          icon: Users },
      { href: "/suppliers",          label: "Suppliers",          icon: Truck },
      { href: "/payments",           label: "Payments",           icon: CreditCard },
      { href: "/feed-usage",         label: "Feed Usage",         icon: Package },
      { href: "/resources",          label: "Resources",          icon: BookOpen },
      { href: "/reports",            label: "Reports",            icon: BarChart3 },
      { href: "/profile",            label: "Account",            icon: User },
      { href: "/audit-logs",         label: "Activity Log",       icon: Activity },
      { href: "/settings",           label: "Settings",           icon: Settings },
      { href: "/terms",              label: "Terms",              icon: FileText },
      ...(permissions.isAdmin || permissions.featureAccess.canSeeEmployees
        ? [{ href: "/employees", label: "Employees", icon: UserCog }] : []),
    ]
    const filteredPoultryMore = poultryMore.filter((item) => {
      if (["/sales", "/expenses", "/cash", "/customers", "/suppliers", "/payments"].includes(item.href)) {
        return isFinancialNavItemVisible(item.href, permissions.featureAccess, permissions.isAdmin, {
          tempShowPayments: TEMP_SHOW_PAYMENTS_LINK,
        })
      }
      if (item.href === "/reports") return permissions.featureAccess.canViewReports
      if (item.href === "/audit-logs") return permissions.featureAccess.canViewActivityLog
      if (item.href === "/settings") return permissions.featureAccess.canViewSettings
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

  const isProductionActive =
    pathname === "/production-records" ||
    pathname.startsWith("/production-records/") ||
    pathname === "/egg-production" ||
    pathname.startsWith("/egg-production/")

  return (
    <nav
      className={cn(
        "lg:hidden fixed bottom-0 left-0 right-0 z-40 border-t pb-[env(safe-area-inset-bottom)]",
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
                "flex flex-col items-center justify-center gap-0.5 min-h-[44px] min-w-[44px] flex-1 py-2 px-1 rounded-lg transition-colors active:bg-white/10",
                config.moreItems.some(
                  (i) => pathname === i.href || pathname.startsWith(`${i.href}/`)
                )
                  ? config.palette.activeText
                  : config.palette.inactive,
              )}
              aria-label="More"
            >
              <MoreHorizontal className="h-6 w-6 shrink-0" />
              <span className="text-[10px] font-medium">More</span>
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
