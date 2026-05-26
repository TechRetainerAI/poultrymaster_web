"use client"

import { useState, useTransition, useEffect } from "react"
import Link from "next/link"
import { usePathname, useRouter } from "next/navigation"
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { usePermissions } from "@/hooks/use-permissions"
import { useIsMobile } from "@/hooks/use-mobile"
import { 
  BarChart3, 
  Users, 
  Building2, 
  User, 
  Settings, 	
  AlertTriangle,
  ChevronDown,
  Home,
  FileText,
  Egg,
  Package,
  Bird,
  DollarSign,
  LogOut,
  ShoppingCart,
  UserCog,
  Bell,
  ListTodo,
  BookOpen,
  Menu,
  X,
  HelpCircle,
  Activity,
  Wallet,
  Boxes,
  CreditCard,
  Wheat,
  Pill,
  Truck,
  Droplets,
  ShoppingBag,
  Receipt,
  Users2,
  Banknote,
  Wrench,
  Factory,
  Cog,
  Box,
  Route as RouteIcon,
} from "lucide-react"
import { InventoryLogo } from "@/components/auth/logo"
import { useAlertsStore, type AlertItem } from "@/lib/store/alerts-store"
import { useSidebarStore } from "@/lib/store/sidebar-store"
import { useAuthStore } from "@/lib/store/auth-store"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { isFinancialNavItemVisible } from "@/lib/utils/financial-nav-access"

interface SidebarProps {
  onLogout: () => void
}

export function DashboardSidebar({ onLogout }: SidebarProps) {
  const pathname = usePathname()
  const router = useRouter()
  const permissions = usePermissions()
  const isMobile = useIsMobile()
  const [isPending, startTransition] = useTransition()
  const alerts = useAlertsStore((s: { alerts: AlertItem[]; open: () => void }) => s.alerts)
  const openAlerts = useAlertsStore((s: { alerts: AlertItem[]; open: () => void }) => s.open)
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const isWater = activeFarmType === "Water"
  const isGeneric = activeFarmType === "Generic"
  const { isCollapsed, toggle, isMobileOpen, toggleMobile, setMobileOpen, setCollapsed } = useSidebarStore()
  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>({
    farm: true,
    production: true,
    analytics: true,
    inventory: true,
    financial: true,
  })

  // Close mobile sidebar when route changes
  useEffect(() => {
    if (isMobile) {
      setMobileOpen(false)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pathname, isMobile])

  // Keep default desktop sidebar in icon mode on initial load.
  useEffect(() => {
    if (!isMobile) {
      setCollapsed(true)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isMobile])

  // Close mobile sidebar on escape key and prevent body scroll when open
  useEffect(() => {
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isMobile && isMobileOpen) {
        setMobileOpen(false)
      }
    }
    
    if (isMobile && isMobileOpen) {
      document.body.style.overflow = 'hidden'
    } else {
      document.body.style.overflow = ''
    }
    
    window.addEventListener('keydown', handleEscape)
    return () => {
      window.removeEventListener('keydown', handleEscape)
      document.body.style.overflow = ''
    }
  }, [isMobile, isMobileOpen, setMobileOpen])

  const toggleGroup = (groupName: string) => {
    setOpenGroups((prev) => ({ ...prev, [groupName]: !prev[groupName] }))
  }

  const handleLinkClick = () => {
    if (isMobile) {
      setMobileOpen(false)
    }
  }

  // Navigation items
  const farmItems = [
    { href: "/flock-batch", label: "Flock Purchases (Batches)", icon: Boxes },
    { href: "/flocks", label: "Flock Groups (Pens / Flocks)", icon: Bird },
    { href: "/houses", label: "Houses", icon: Building2 },
  ]

  const productionItems = [
    { href: "/production-records", label: "Production Records", icon: FileText },
    { href: "/egg-production", label: "Egg sorting", icon: Egg },
    { href: "/feed-usage", label: "Feed Usage", icon: Package },
  ]

  const analyticsItems = [
    { href: "/egg-tracker", label: "Egg tracker", icon: BarChart3 },
    { href: "/feed-tracker", label: "Feed tracker", icon: Wheat },
    { href: "/medication-tracker", label: "Medication tracker", icon: Pill },
    { href: "/birds-left-tracker", label: "Birds left tracker", icon: Bird },
    { href: "/weekly-report", label: "Analytical Report", icon: FileText },
  ]

  const inventoryItems = [
    { href: "/health", label: "Health Records", icon: AlertTriangle },
    { href: "/inventory", label: "Inventory", icon: Package },
    { href: "/supplies", label: "Supplies", icon: ShoppingCart },
  ]

  const TEMP_SHOW_PAYMENTS_LINK = true
  const financialItems = [
    { href: "/cash", label: "Cash", icon: Wallet },
    { href: "/sales", label: "Sales", icon: ShoppingCart },
    { href: "/expenses", label: "Expenses", icon: DollarSign },
    { href: "/customers", label: "Customers", icon: Users },
    { href: "/suppliers", label: "Suppliers", icon: Truck },
    { href: "/payments", label: "Payments", icon: CreditCard },
  ].filter((item) =>
    isFinancialNavItemVisible(item.href, permissions.featureAccess, permissions.isAdmin, {
      tempShowPayments: TEMP_SHOW_PAYMENTS_LINK,
    })
  )

  // Water company nav items (shown when activeFarmType === "Water")
  const waterCatalogItems = [
    { href: "/water-products", label: "Products", icon: ShoppingBag },
    { href: "/water-stock",    label: "Stock",    icon: Boxes },
  ]
  const waterSalesItems = [
    { href: "/water-customers", label: "Customers", icon: Users },
    { href: "/water-sales",     label: "Sales",     icon: ShoppingCart },
    { href: "/water-payments",  label: "Payments",  icon: CreditCard },
  ]
  // Water — Production (W1)
  const waterProductionItems = [
    { href: "/water-production-batches", label: "Production batches", icon: Factory },
    { href: "/water-machines",           label: "Machines",            icon: Cog },
    { href: "/water-boreholes",          label: "Boreholes",           icon: Droplets },
  ]
  // Water — Distribution (W2)
  const waterDistributionItems = [
    { href: "/water-drivers",        label: "Drivers",        icon: Users2 },
    { href: "/water-driver-returns", label: "Driver returns", icon: Truck },
    { href: "/water-vehicles",       label: "Vehicles",       icon: Truck },
    { href: "/water-routes",         label: "Routes",         icon: RouteIcon },
  ]
  // Water — Inventory (W3 raw materials + loss tracking)
  const waterInventoryItems = [
    { href: "/water-raw-materials", label: "Raw materials", icon: Box },
    { href: "/water-loss-records",  label: "Damages & loss", icon: AlertTriangle },
  ]
  // Water — Reports (W3)
  const waterReportsItems = [
    { href: "/water-reports", label: "Reports", icon: BarChart3 },
  ]
  // Water — Money (W4 finance + W3 daily closing)
  const waterMoneyItems = [
    { href: "/water-expenses",      label: "Expenses",       icon: Receipt },
    { href: "/water-cash-accounts", label: "Cash & Accounts", icon: Wallet },
    { href: "/water-daily-closing", label: "Daily Closing",   icon: FileText },
  ]
  // Water — People (W6)
  const waterPeopleItems = [
    { href: "/water-staff",   label: "Staff",   icon: Users2 },
    { href: "/water-payroll", label: "Payroll", icon: Banknote },
  ]
  // Water — Admin (W7 maintenance + W5 setup)
  const waterAdminItems = [
    { href: "/water-maintenance",   label: "Maintenance", icon: Wrench },
    { href: "/water-company-setup", label: "Setup",       icon: Settings },
  ]

  // Generic Company nav items (shown when activeFarmType === "Generic")
  const genericCatalogItems = [
    { href: "/generic-products",          label: "Products",          icon: ShoppingBag },
    { href: "/generic-stock-adjustments", label: "Stock adjustments", icon: Boxes },
  ]
  const genericSalesItems = [
    { href: "/generic-sales",              label: "Sales",             icon: ShoppingCart },
    { href: "/generic-customers",          label: "Customers",         icon: Users },
    { href: "/generic-customer-payments",  label: "Customer payments", icon: CreditCard },
  ]
  const genericPurchasingItems = [
    { href: "/generic-suppliers",          label: "Suppliers",         icon: Truck },
    { href: "/generic-purchases",          label: "Purchases",         icon: Package },
    { href: "/generic-supplier-payments",  label: "Supplier payments", icon: CreditCard },
    { href: "/generic-expenses",           label: "Expenses",          icon: DollarSign },
  ]
  const genericMoneyItems = [
    { href: "/generic-cash",           label: "Cash & Accounts", icon: Wallet },
    { href: "/generic-cash-transfers", label: "Cash transfers",  icon: Activity },
    { href: "/generic-daily-closings", label: "Daily Closing",   icon: FileText },
  ]
  // Generic — People (Phase 6: staff + attendance + payroll, migrations 055/056)
  const genericPeopleItems = [
    { href: "/generic-staff",       label: "Staff",      icon: Users2 },
    { href: "/generic-attendance",  label: "Attendance", icon: Activity },
    { href: "/generic-payroll",     label: "Payroll",    icon: Banknote },
  ]
  const genericAdminItems = [
    { href: "/generic-reports", label: "Reports", icon: BarChart3 },
    { href: "/generic-setup",   label: "Setup",   icon: Settings },
  ]

  // Single items (no group)
  const renderNavItem = (
    item: { href: string; label: string; icon: any },
    isButton = false,
    onClick?: () => void,
    badge?: number
  ) => {
    const isActive =
      pathname === item.href || (item.href !== "/dashboard" && pathname.startsWith(`${item.href}/`))
    const Icon = item.icon

    const content = (
      <div
        className={cn(
          "flex items-center gap-3 px-4 py-2.5 text-sm font-medium rounded-md transition-colors relative",
          isActive
            ? "bg-slate-700 text-white border-l-[3px] border-blue-400 pl-[13px]"
            : "text-slate-300 hover:bg-slate-800 hover:text-white border-l-[3px] border-transparent pl-[13px]",
          isCollapsed && !isMobile ? "justify-center px-2 pl-2" : ""
        )}
      >
        <Icon className={cn("h-5 w-5 shrink-0", isActive ? "text-blue-400" : "text-slate-400")} />
        {(!isCollapsed || isMobile) && (
          <span className="truncate">{item.label}</span>
        )}
        {badge && badge > 0 && (!isCollapsed || isMobile) && (
          <span className="ml-auto inline-flex items-center justify-center min-w-[20px] h-5 rounded-full bg-red-500 text-white text-[10px] font-bold px-1.5">
            {badge > 99 ? '99+' : badge}
          </span>
        )}
      </div>
    )

    if (isCollapsed && !isMobile) {
      return (
        <Tooltip>
          <TooltipTrigger asChild>
            {isButton ? (
              <button onClick={onClick} className="w-full">
                {content}
              </button>
            ) : (
              <Link href={item.href} prefetch={true} className="block" onClick={handleLinkClick}>
                {content}
              </Link>
            )}
          </TooltipTrigger>
          <TooltipContent side="right" className="bg-slate-800 text-white border-slate-700">
            {item.label}
            {badge && badge > 0 && (
              <span className="ml-2 inline-flex items-center justify-center min-w-[18px] h-[18px] rounded-full bg-red-500 text-white text-[10px] px-1">
                {badge > 99 ? '99+' : badge}
              </span>
            )}
          </TooltipContent>
        </Tooltip>
      )
    }

    return isButton ? (
      <button onClick={onClick} className="w-full text-left">
        {content}
      </button>
    ) : (
      <Link href={item.href} prefetch={true} className="block" onClick={handleLinkClick}>
        {content}
      </Link>
    )
  }

  const renderGroup = (title: string, items: typeof farmItems, groupKey: string) => {
    const isOpen = openGroups[groupKey] !== false

    if (isCollapsed && !isMobile) {
      return (
        <div className="space-y-0.5">
          {items.map((item) => (
            <div key={item.href}>{renderNavItem(item)}</div>
          ))}
        </div>
      )
    }

    return (
      <div>
        <button
          onClick={() => toggleGroup(groupKey)}
          className="w-full flex items-center justify-between px-4 py-1.5 text-xs font-semibold text-slate-500 uppercase tracking-wider hover:text-slate-300 transition-colors"
        >
          <span>{title}</span>
          <ChevronDown
            className={cn(
              "h-3.5 w-3.5 transition-transform",
              isOpen ? "rotate-0" : "-rotate-90"
            )}
          />
        </button>
        {isOpen && (
          <div className="space-y-0.5 mt-0.5">
            {items.map((item) => (
              <div key={item.href}>{renderNavItem(item)}</div>
            ))}
          </div>
        )}
      </div>
    )
  }

  const sidebarContent = (
    <div className="flex h-full min-h-0 w-full flex-col">
      {/* Logo Header */}
      <div className="flex h-16 shrink-0 items-center border-b border-slate-800 px-3 gap-1">
        {(!isCollapsed || isMobile) && (
          <InventoryLogo dark />
        )}
        {isMobile ? (
          <Button
            variant="ghost"
            size="icon"
            onClick={toggleMobile}
            className="ml-auto shrink-0 text-slate-300 hover:bg-slate-800 hover:text-white"
            aria-label="Close sidebar"
          >
            <X className="h-5 w-5" />
          </Button>
        ) : isCollapsed ? (
          <Tooltip>
            <TooltipTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                onClick={toggle}
                className="mx-auto text-slate-300 hover:bg-slate-800 hover:text-white"
                aria-label="Expand sidebar"
              >
                <Menu className="h-5 w-5" />
              </Button>
            </TooltipTrigger>
            <TooltipContent side="right" className="bg-slate-800 text-white border-slate-700">
              Show Sidebar
            </TooltipContent>
          </Tooltip>
        ) : (
          <Button
            variant="ghost"
            size="icon"
            onClick={toggle}
            className="ml-auto shrink-0 text-slate-400 hover:bg-slate-800 hover:text-white"
            aria-label="Collapse sidebar"
          >
            <X className="h-4 w-4" />
          </Button>
        )}
      </div>

      {/* Navigation */}
      <nav
        className="sidebar-nav-scrollable min-h-0 flex-1 overflow-y-auto overscroll-y-contain py-3 px-2 space-y-4"
        aria-label="Main navigation"
      >
        {/* Dashboard — route depends on active company type */}
        <div>
          {renderNavItem({
            href: isWater ? "/water-dashboard" : isGeneric ? "/generic-dashboard" : "/dashboard",
            label: "Dashboard",
            icon: isWater ? Droplets : isGeneric ? ShoppingBag : Home,
          })}
        </div>

        {/* Divider */}
        <div className="border-t border-slate-800 mx-2" />

        {isWater ? (
          <>
            {/* Water — Catalog */}
            {renderGroup("Catalog", waterCatalogItems, "waterCatalog")}

            <div className="border-t border-slate-800 mx-2" />

            {/* Water — Production (W1) */}
            {renderGroup("Production", waterProductionItems, "waterProduction")}

            <div className="border-t border-slate-800 mx-2" />

            {/* Water — Distribution (W2) */}
            {renderGroup("Distribution", waterDistributionItems, "waterDistribution")}

            <div className="border-t border-slate-800 mx-2" />

            {/* Water — Sales */}
            {renderGroup("Sales", waterSalesItems, "waterSales")}

            <div className="border-t border-slate-800 mx-2" />

            {/* Water — Inventory (raw materials + loss) */}
            {renderGroup("Inventory", waterInventoryItems, "waterInventory")}

            <div className="border-t border-slate-800 mx-2" />

            {/* Water — Money (W4 finance + W3 daily closing) */}
            {renderGroup("Money", waterMoneyItems, "waterMoney")}

            <div className="border-t border-slate-800 mx-2" />

            {/* Water — People (W6 staff + payroll) */}
            {renderGroup("People", waterPeopleItems, "waterPeople")}

            <div className="border-t border-slate-800 mx-2" />

            {/* Water — Reports */}
            {renderGroup("Reports", waterReportsItems, "waterReports")}

            <div className="border-t border-slate-800 mx-2" />

            {/* Water — Admin (W7 maintenance + W5 setup) */}
            {renderGroup("Admin", waterAdminItems, "waterAdmin")}
          </>
        ) : isGeneric ? (
          <>
            {/* Generic Company — Catalog */}
            {renderGroup("Catalog", genericCatalogItems, "genericCatalog")}

            <div className="border-t border-slate-800 mx-2" />

            {/* Generic Company — Sales */}
            {renderGroup("Sales", genericSalesItems, "genericSales")}

            <div className="border-t border-slate-800 mx-2" />

            {/* Generic Company — Purchasing */}
            {renderGroup("Purchasing", genericPurchasingItems, "genericPurchasing")}

            <div className="border-t border-slate-800 mx-2" />

            {/* Generic Company — Money */}
            {renderGroup("Money", genericMoneyItems, "genericMoney")}

            <div className="border-t border-slate-800 mx-2" />

            {/* Generic Company — People (Phase 6) */}
            {renderGroup("People", genericPeopleItems, "genericPeople")}

            <div className="border-t border-slate-800 mx-2" />

            {/* Generic Company — Admin */}
            {renderGroup("Admin", genericAdminItems, "genericAdmin")}
          </>
        ) : (
          <>
            {/* Farm Management */}
            {renderGroup("Farm", farmItems, "farm")}

            {/* Divider */}
            <div className="border-t border-slate-800 mx-2" />

            {/* Production */}
            {renderGroup("Production", productionItems, "production")}

            {/* Divider */}
            <div className="border-t border-slate-800 mx-2" />

            {/* Analytics */}
            {renderGroup("Analytics", analyticsItems, "analytics")}

            {/* Divider */}
            <div className="border-t border-slate-800 mx-2" />

            {/* Inventory & Health */}
            {renderGroup("Inventory & Health", inventoryItems, "inventory")}

            {/* Divider */}
            <div className="border-t border-slate-800 mx-2" />

            {/* Financial */}
            {financialItems.length > 0 && renderGroup("Financial", financialItems, "financial")}
          </>
        )}

        {/* Admin */}
        {(permissions.isAdmin || permissions.featureAccess.canSeeEmployees) && (
          <>
            <div className="border-t border-slate-800 mx-2" />
            <div className="space-y-0.5">
              {renderNavItem({ href: "/employees", label: "Employees", icon: UserCog })}
            </div>
          </>
        )}

        {/* Divider */}
        <div className="border-t border-slate-800 mx-2" />

        {/* System */}
        <div className="space-y-0.5">
          {permissions.featureAccess.canViewReports && renderNavItem({ href: "/reports", label: "Reports", icon: BarChart3 })}
          {renderNavItem({ href: "/profile", label: "Account", icon: User })}
          {/* Resources page is poultry-only (vaccination/feed/medication schedules for chickens). */}
          {!isWater && !isGeneric && renderNavItem({ href: "/resources", label: "Resources", icon: BookOpen })}
          {renderNavItem(
            { href: "#", label: "Alerts", icon: Bell },
            true,
            openAlerts,
            alerts.length
          )}
          {renderNavItem({ href: "/companies", label: "Companies", icon: Building2 })}
          {permissions.featureAccess.canViewActivityLog && renderNavItem({ href: "/audit-logs", label: "Activity Log", icon: Activity })}
          {/* /settings is the poultry farm-profile page. Water and Generic have their own
              dedicated setup links inside their respective sidebar groups above. */}
          {!isWater && !isGeneric && permissions.featureAccess.canViewSettings && renderNavItem({ href: "/settings", label: "Settings", icon: Settings })}
          {/* /help is poultry-specific (flocks, eggs, vaccinations). */}
          {!isWater && !isGeneric && renderNavItem({ href: "/help", label: "Help Center", icon: HelpCircle })}
          {renderNavItem({ href: "/terms", label: "Terms & Conditions", icon: ListTodo })}
        </div>
      </nav>

      {/* Logout */}
      <div className="shrink-0 border-t border-slate-800 p-3">
        {isCollapsed && !isMobile ? (
          <Tooltip>
            <TooltipTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                onClick={onLogout}
                className="w-full text-slate-300 hover:bg-slate-800 hover:text-white"
                aria-label="Logout"
              >
                <LogOut className="h-5 w-5" />
              </Button>
            </TooltipTrigger>
            <TooltipContent side="right" className="bg-slate-800 text-white border-slate-700">
              Logout
            </TooltipContent>
          </Tooltip>
        ) : (
          <Button
            variant="ghost"
            onClick={onLogout}
            className="w-full justify-start text-slate-300 hover:bg-red-900/30 hover:text-red-400 gap-3 px-4"
          >
            <LogOut className="h-5 w-5" />
            Logout
          </Button>
        )}
      </div>
    </div>
  )

  return (
    <>
      {/* Mobile sidebar with overlay */}
      <div className="lg:hidden">
        {isMobileOpen && (
          <div
            className="fixed inset-0 bg-black/50 transition-opacity duration-300"
            style={{ zIndex: 9998 }}
            onClick={() => toggleMobile()}
            aria-hidden="true"
          />
        )}
        
        <div
          className={cn(
            "fixed top-0 left-0 flex h-full min-h-0 w-[85vw] max-w-[320px] flex-col overflow-hidden bg-slate-900 shadow-xl transition-transform duration-300 ease-in-out",
            isMobileOpen ? "translate-x-0" : "-translate-x-full"
          )}
          style={{
            zIndex: 9999,
            willChange: 'transform',
          }}
        >
          {sidebarContent}
        </div>
      </div>

      {/* Desktop sidebar — pin to viewport so it stays fixed while the main column scrolls. */}
      <div className={cn(
        "hidden min-h-0 overflow-hidden lg:sticky lg:top-0 lg:h-screen lg:self-start lg:shrink-0 lg:flex lg:flex-col bg-slate-900 transition-all duration-300",
        isCollapsed ? "w-16" : "w-60"
      )}>
        {sidebarContent}
      </div>
    </>
  )
}
