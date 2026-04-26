"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { useState } from "react"
import { cn } from "@/lib/utils"
import { usePermissions } from "@/hooks/use-permissions"
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

const mainTabs: NavItem[] = [
  { href: "/dashboard", label: "Home", icon: Home },
  { href: "/flocks", label: "Flocks", icon: Bird },
  { href: "/production-records", label: "Production", icon: FileText },
  { href: "/sales", label: "Sales", icon: ShoppingCart },
]

function TabLink({ item, isActive }: { item: NavItem; isActive: boolean }) {
  const Icon = item.icon
  return (
    <Link
      href={item.href}
      prefetch={true}
      className={cn(
        "flex flex-col items-center justify-center gap-0.5 min-h-[44px] min-w-[44px] flex-1 py-2 px-1 rounded-lg transition-colors active:bg-white/10",
        isActive
          ? "text-white"
          : "text-orange-100/90 hover:text-white"
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
  // Temporary business override while subscription enforcement is paused.
  const TEMP_SHOW_PAYMENTS_LINK = true
  const pathname = usePathname()
  const permissions = usePermissions()
  const [sheetOpen, setSheetOpen] = useState(false)

  const visibleMainTabs = mainTabs.filter((item) => {
    if (item.href === "/sales")
      return permissions.featureAccess.canViewFinancial && permissions.featureAccess.canEnterSales
    return true
  })

  const isProductionActive =
    pathname === "/production-records" ||
    pathname.startsWith("/production-records/") ||
    pathname === "/egg-production" ||
    pathname.startsWith("/egg-production/")

  const moreItems: NavItem[] = [
    { href: "/inventory", label: "Inventory", icon: Package },
    { href: "/help", label: "Help Center", icon: BookOpen },
    { href: "/health", label: "Health Records", icon: AlertTriangle },
    { href: "/cash", label: "Cash", icon: Wallet },
    { href: "/expenses", label: "Expenses", icon: DollarSign },
    { href: "/customers", label: "Customers", icon: Users },
    { href: "/payments", label: "Payments", icon: CreditCard },
    { href: "/feed-usage", label: "Feed Usage", icon: Package },
    { href: "/egg-production", label: "Egg Production", icon: Egg },
    { href: "/resources", label: "Resources", icon: BookOpen },
    { href: "/reports", label: "Reports", icon: BarChart3 },
    { href: "/profile", label: "Account", icon: User },
    { href: "/audit-logs", label: "Activity Log", icon: Activity },
    { href: "/settings", label: "Settings", icon: Settings },
    { href: "/terms", label: "Terms", icon: FileText },
    ...(permissions.isAdmin || permissions.featureAccess.canSeeEmployees
      ? [{ href: "/employees", label: "Employees", icon: UserCog }]
      : []),
  ].filter((item) => {
    if (item.href === "/payments") return TEMP_SHOW_PAYMENTS_LINK || permissions.featureAccess.canViewFinancial
    if (
      !permissions.featureAccess.canViewFinancial &&
      ["/sales", "/expenses", "/cash", "/customers", "/payments"].includes(item.href)
    )
      return false
    if (item.href === "/sales") return permissions.featureAccess.canEnterSales
    if (item.href === "/expenses") return permissions.featureAccess.canEnterExpenses
    if (item.href === "/cash") return permissions.featureAccess.canViewCashLedger
    if (item.href === "/reports") return permissions.featureAccess.canViewReports
    if (item.href === "/audit-logs") return permissions.featureAccess.canViewActivityLog
    if (item.href === "/settings") return permissions.featureAccess.canViewSettings
    return true
  })

  return (
    <nav
      className="lg:hidden fixed bottom-0 left-0 right-0 z-40 bg-orange-500 border-t border-orange-600 pb-[env(safe-area-inset-bottom)]"
      role="navigation"
      aria-label="Main navigation"
    >
      <div className="flex items-stretch justify-around px-2 py-2">
        {visibleMainTabs.map((item) => {
          const isActive =
            item.href === "/production-records"
              ? isProductionActive
              : pathname === item.href || pathname.startsWith(`${item.href}/`)
          return <TabLink key={item.href} item={item} isActive={isActive} />
        })}

        <Sheet open={sheetOpen} onOpenChange={setSheetOpen}>
          <SheetTrigger asChild>
            <button
              className={cn(
                "flex flex-col items-center justify-center gap-0.5 min-h-[44px] min-w-[44px] flex-1 py-2 px-1 rounded-lg transition-colors active:bg-white/10",
                moreItems.some(
                  (i) => pathname === i.href || pathname.startsWith(`${i.href}/`)
                )
                  ? "text-white"
                  : "text-orange-100/90 hover:text-white"
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
              {moreItems.map((item) => {
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
                        ? "bg-orange-100 text-orange-800 font-medium"
                        : "bg-slate-100 text-slate-700 hover:bg-orange-50 hover:text-orange-700"
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
