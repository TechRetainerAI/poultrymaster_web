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
  CreditCard
} from "lucide-react"
import { InventoryLogo } from "@/components/auth/logo"
import { useAlertsStore, type AlertItem } from "@/lib/store/alerts-store"
import { useSidebarStore } from "@/lib/store/sidebar-store"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"

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
  const { isCollapsed, toggle, isMobileOpen, toggleMobile, setMobileOpen, setCollapsed } = useSidebarStore()
  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>({
    farm: true,
    production: true,
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
    { href: "/flock-batch", label: "Flock Batch", icon: Boxes },
    { href: "/flocks", label: "Flocks", icon: Bird },
    { href: "/houses", label: "Houses", icon: Building2 },
  ]

  const productionItems = [
    { href: "/production-records", label: "Production Records", icon: FileText },
    { href: "/egg-production", label: "Egg Production", icon: Egg },
    { href: "/feed-usage", label: "Feed Usage", icon: Package },
  ]

  const inventoryItems = [
    { href: "/health", label: "Health Records", icon: AlertTriangle },
    { href: "/inventory", label: "Inventory", icon: Package },
    { href: "/supplies", label: "Supplies", icon: ShoppingCart },
  ]

  const financialItems = [
    { href: "/cash", label: "Cash", icon: Wallet },
    { href: "/sales", label: "Sales", icon: ShoppingCart },
    { href: "/expenses", label: "Expenses", icon: DollarSign },
    { href: "/customers", label: "Customers", icon: Users },
    { href: "/payments", label: "Payments", icon: CreditCard },
  ].filter((item) => {
    if (!permissions.featureAccess.canViewFinancial) return false
    if (item.href === "/sales") return permissions.featureAccess.canEnterSales
    if (item.href === "/expenses") return permissions.featureAccess.canEnterExpenses
    if (item.href === "/cash") return permissions.featureAccess.canViewCashLedger
    return true
  })

  // Single items (no group)
  const renderNavItem = (
    item: { href: string; label: string; icon: any },
    isButton = false,
    onClick?: () => void,
    badge?: number
  ) => {
    const isActive = pathname === item.href
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
    <div className="flex flex-col h-full">
      {/* Logo Header */}
      <div className="flex h-16 shrink-0 items-center px-3 gap-1 border-b border-slate-800">
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
      <nav className="flex-1 overflow-y-auto overscroll-contain py-3 px-2 space-y-4 scrollbar-hide">
        {/* Dashboard */}
        <div>
          {renderNavItem({ href: "/dashboard", label: "Dashboard", icon: Home })}
        </div>

        {/* Divider */}
        <div className="border-t border-slate-800 mx-2" />

        {/* Farm Management */}
        {renderGroup("Farm", farmItems, "farm")}

        {/* Divider */}
        <div className="border-t border-slate-800 mx-2" />

        {/* Production */}
        {renderGroup("Production", productionItems, "production")}

        {/* Divider */}
        <div className="border-t border-slate-800 mx-2" />

        {/* Inventory & Health */}
        {renderGroup("Inventory & Health", inventoryItems, "inventory")}

        {/* Divider */}
        <div className="border-t border-slate-800 mx-2" />

        {/* Financial */}
        {financialItems.length > 0 && renderGroup("Financial", financialItems, "financial")}

        {/* Divider */}
        <div className="border-t border-slate-800 mx-2" />

        {/* Resources */}
        <div>
          {renderNavItem({ href: "/resources", label: "Resources", icon: BookOpen })}
        </div>

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
          {renderNavItem(
            { href: "#", label: "Alerts", icon: Bell },
            true,
            openAlerts,
            alerts.length
          )}
          {permissions.featureAccess.canViewActivityLog && renderNavItem({ href: "/audit-logs", label: "Activity Log", icon: Activity })}
          {permissions.featureAccess.canViewSettings && renderNavItem({ href: "/settings", label: "Settings", icon: Settings })}
          {renderNavItem({ href: "/help", label: "Help Center", icon: HelpCircle })}
          {renderNavItem({ href: "/terms", label: "Terms & Conditions", icon: ListTodo })}
        </div>
      </nav>

      {/* Logout */}
      <div className="border-t border-slate-800 p-3">
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
            "fixed top-0 left-0 h-full w-[85vw] max-w-[320px] bg-slate-900 shadow-xl transition-transform duration-300 ease-in-out",
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

      {/* Desktop sidebar */}
      <div className={cn(
        "hidden lg:sticky lg:top-0 lg:h-screen lg:self-start lg:flex flex-col bg-slate-900 transition-all duration-300",
        isCollapsed ? "w-16" : "w-60"
      )}>
        {sidebarContent}
      </div>
    </>
  )
}
