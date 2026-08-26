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
  Briefcase,
  Clock,
  CalendarDays,
  Shield,
} from "lucide-react"
import { InventoryLogo } from "@/components/auth/logo"
import { useAlertsStore, type AlertItem } from "@/lib/store/alerts-store"
import { useSidebarStore } from "@/lib/store/sidebar-store"
import { useAuthStore } from "@/lib/store/auth-store"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { isFinancialNavItemVisible } from "@/lib/utils/financial-nav-access"
import { filterWaterNavItems } from "@/lib/utils/water-nav-access"
import { filterHotelNavItems } from "@/lib/utils/hotel-nav-access"
import { useLogout } from "@/hooks/use-logout"

interface SidebarProps {
  onLogout?: () => void
}

/** A sidebar row. `isButton`/`onClick`/`badge` are for rows that trigger an
 *  action instead of navigating — currently just Alerts. */
type SidebarItem = {
  href: string
  label: string
  icon: any
  isButton?: boolean
  onClick?: () => void
  badge?: number
}

export function DashboardSidebar({ onLogout }: SidebarProps) {
  const pathname = usePathname()
  const router = useRouter()
  // Several pages render <DashboardSidebar /> without an onLogout prop, which
  // left the Logout button dead on those pages. Fall back to the shared hook.
  const fallbackLogout = useLogout()
  const doLogout = onLogout ?? fallbackLogout
  const permissions = usePermissions()
  const isMobile = useIsMobile()
  const [isPending, startTransition] = useTransition()
  const alerts = useAlertsStore((s: { alerts: AlertItem[]; open: () => void }) => s.alerts)
  const openAlerts = useAlertsStore((s: { alerts: AlertItem[]; open: () => void }) => s.open)
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const clearActiveCompany = useAuthStore((s) => s.clearActiveCompany)
  const isWater = activeFarmType === "Water"
  const isGeneric = activeFarmType === "Generic"
  const isHotel = activeFarmType === "Hotel"
  const { isCollapsed, toggle, isMobileOpen, toggleMobile, setMobileOpen } = useSidebarStore()
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

  // Desktop sidebar defaults to EXPANDED for every company type (Poultry, Water,
  // Generic). Users can collapse it and that choice persists (sidebar-store,
  // default isCollapsed:false) — we intentionally do NOT force a state per farm
  // type on load, so the user's preference sticks across pages and sessions.

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
  // Houses and Flock Groups moved to the Setup group below — they're master
  // data you maintain, not a daily activity. Matches the top nav's
  // Setup > Farm column (lib/nav/poultry-nav-config.ts).
  const farmItems = [
    { href: "/flock-batch", label: "Flock Purchases (Batches)", icon: Boxes },
  ]

  // Setup — the farm master data behind the daily flows. Mirrors the top nav's
  // Setup > Farm column.
  const poultrySetupItems = [
    { href: "/houses", label: "Houses", icon: Building2 },
    { href: "/flocks", label: "Flock Groups (Pens / Flocks)", icon: Bird },
  ]

  const productionItems = [
    { href: "/production-records", label: "Production Records", icon: FileText },
    { href: "/batch-production-records", label: "Batch Production", icon: Boxes },
    { href: "/egg-production", label: "Egg sorting", icon: Egg },
    { href: "/feed-usage", label: "Feed Usage", icon: Package },
    // Feed Production is a production activity (producing finished feed from
    // ingredients), so it lives under Production. Gated by canViewFeedProduction.
    ...(permissions.featureAccess.canViewFeedProduction ? [
      { href: "/poultry-feed-production", label: "Feed Production", icon: Factory },
      { href: "/poultry-feed-formulas",   label: "Feed Formulas",  icon: Wheat },
    ] : []),
    { href: "/poultry-products", label: "Products", icon: Package },
    // Egg pick times are a farm-level setup (admin only). The page renders in the
    // standard poultry chrome, so it's fine to link straight to it from here.
    ...(permissions.isAdmin ? [{ href: "/business-office/egg-pick-settings", label: "Egg Pick Times", icon: Clock }] : []),
  ]

  const analyticsItems = [
    { href: "/egg-tracker", label: "Egg tracker", icon: BarChart3 },
    { href: "/feed-tracker", label: "Feed tracker", icon: Wheat },
    { href: "/medication-tracker", label: "Medication tracker", icon: Pill },
    { href: "/birds-left-tracker", label: "Birds left tracker", icon: Bird },
    { href: "/weekly-report", label: "Analytical Report", icon: FileText },
  ]

  // Combined Inventory & Health — merges the former "Inventory & Health" and
  // "Inventory & Production" groups into one, in the order below.
  const poultryInventoryItems = [
    { href: "/poultry-inventory", label: "Inventory", icon: Boxes },
    { href: "/poultry-stock", label: "Stock movements", icon: Boxes },
    { href: "/poultry-raw-materials", label: "Raw Materials & Supplies", icon: Box },
    { href: "/supplies", label: "Supplies", icon: ShoppingCart },
    { href: "/health", label: "Health Records", icon: AlertTriangle },
    { href: "/poultry-loss-records", label: "Loss & Damage", icon: AlertTriangle },
    { href: "/inventory", label: "Other Inventory", icon: Package },
  ]

  // Full driver / distribution suite for Poultry (ported from Water). Coexists
  // with the simple /poultry-deliveries quick-delivery page above.
  const poultryDeliveryItems = [
    { href: "/poultry-driver-returns", label: "Deliveries",    icon: Truck },
    { href: "/poultry-drivers",        label: "Drivers",       icon: Users2 },
    { href: "/poultry-vehicles",       label: "Vehicles",      icon: Truck },
    { href: "/poultry-routes",         label: "Routes",        icon: RouteIcon },
    { href: "/poultry-driver-report",  label: "Driver report", icon: BarChart3 },
  ]

  // Quick Links — fast-access shortcuts (mirrors the Water side, minus
  // Deliveries). Targets also live in their canonical groups below so
  // navigation stays consistent.
  const poultryQuickLinkItems = [
    { href: "/poultry-daily-closing", label: "Daily Closing",     icon: FileText },
    { href: "/production-records",    label: "Production Records", icon: Factory },
    { href: "/sales",                 label: "Sales",             icon: ShoppingCart },
  ]

  const TEMP_SHOW_PAYMENTS_LINK = true
  const financialItems = [
    { href: "/cash", label: "Cash", icon: Wallet },
    { href: "/poultry-cash-accounts", label: "Cash Account", icon: Wallet },
    { href: "/sales", label: "Sales", icon: ShoppingCart },
    { href: "/poultry-payments", label: "Payments received", icon: Wallet },
    { href: "/expenses", label: "Expenses", icon: DollarSign },
    { href: "/billing", label: "Billing", icon: CreditCard },
  ].filter((item) =>
    isFinancialNavItemVisible(item.href, permissions.featureAccess, permissions.isAdmin, {
      tempShowPayments: TEMP_SHOW_PAYMENTS_LINK,
    })
  )

  // Finance — the two trading parties every receivable and payable hangs off.
  // They're master data rather than part of the day's selling flow, so they get
  // their own group instead of sitting among the money pages above. Same gate
  // as before the split, so nobody gains or loses access. Mirrors the top nav's
  // Setup > Finance column.
  const poultryFinanceItems = [
    { href: "/customers", label: "Customers", icon: Users },
    { href: "/suppliers", label: "Suppliers", icon: Truck },
  ].filter((item) =>
    isFinancialNavItemVisible(item.href, permissions.featureAccess, permissions.isAdmin, {
      tempShowPayments: TEMP_SHOW_PAYMENTS_LINK,
    })
  )

  // Poultry People (Staff + Payroll). Staff is admin/employee-gated like Water's.
  const poultryPeopleItems = [
    ...((permissions.isAdmin || permissions.featureAccess.canSeeEmployees)
      ? [{ href: "/poultry-staff", label: "Staff", icon: UserCog }]
      : []),
    { href: "/poultry-payroll", label: "Payroll", icon: Banknote },
  ]

  // Water company nav items (shown when activeFarmType === "Water")
  // James (2026-06-02): regrouped to surface Delivery and Production as
  // first-class sections (previously buried in Admin/Setup). Quick Links is
  // the old "Daily operations" group but renamed and used as a fast-access
  // shortcut bar — the items it points to also live in their canonical group
  // so navigation stays consistent.
  //
  // Every water group below is run through `gateWater`, which drops the items
  // this user's Staff Page Access flags don't cover (lib/utils/water-nav-access).
  // Before this the water rail was entirely ungated — the flags only ever
  // applied to the poultry routes.
  const gateWater = <T extends { href: string }>(items: T[]) =>
    filterWaterNavItems(items, permissions.featureAccess, permissions.isAdmin)

  const waterQuickLinkItems = gateWater([
    { href: "/water-daily-closing",      label: "Daily Closing",      icon: FileText },
    { href: "/water-driver-returns",     label: "Deliveries",         icon: Truck },
    { href: "/water-production-batches", label: "Production",          icon: Factory },
    { href: "/water-sales",              label: "Sales",              icon: ShoppingCart },
  ])
  const waterDeliveryItems = gateWater([
    { href: "/water-driver-returns", label: "Deliveries", icon: Truck },
    { href: "/water-drivers",        label: "Drivers",    icon: Users2 },
    { href: "/water-vehicles",       label: "Vehicles",   icon: Truck },
    { href: "/water-routes",         label: "Routes",     icon: RouteIcon },
    // The sidebar had no route to this page at all — the top nav and mobile
    // sheet both carry it under Delivery.
    { href: "/water-driver-report",  label: "Driver collection report", icon: BarChart3 },
  ])
  const waterProductionItems = gateWater([
    // Mirrors the poultry Production group: "Production" is the per-machine
    // record, "Batch Production" is the day-level entry that allocates across
    // machines (poultry: Production Records / Batch Production).
    { href: "/water-production-batches", label: "Production",         icon: Factory },
    { href: "/water-daily-production",   label: "Batch Production",   icon: CalendarDays },
    { href: "/water-products",           label: "Products",           icon: ShoppingBag },
    { href: "/water-machines",           label: "Machines",           icon: Cog },
    { href: "/water-boreholes",          label: "Boreholes",          icon: Droplets },
    { href: "/water-maintenance",        label: "Maintenance",        icon: Wrench },
  ])
  // Inventory absorbs Raw materials & supplies; Products moved out into the
  // Production group above.
  const waterInventoryItems = gateWater([
    { href: "/water-stock",             label: "Stock movement",           icon: Boxes },
    { href: "/water-inventory",         label: "Inventory",                icon: Boxes },
    { href: "/water-raw-materials",     label: "Raw materials & supplies", icon: Box },
    { href: "/water-loss-records",      label: "Damages & loss",           icon: AlertTriangle },
    { href: "/water-production-losses", label: "Production losses",        icon: AlertTriangle },
  ])
  const waterSalesMoneyItems = gateWater([
    { href: "/water-sales",         label: "Sales",           icon: ShoppingCart },
    { href: "/water-payments",      label: "Payments",        icon: CreditCard },
    { href: "/water-expenses",      label: "Expenses",        icon: Receipt },
    { href: "/water-cash-accounts", label: "Cash accounts",   icon: Wallet },
  ])
  // Finance — Customers (was in Sales & money) and Suppliers (was buried in
  // Admin / Setup) now sit together: both are master data, and they're the two
  // trading parties every receivable and payable hangs off. Mirrors the top
  // nav's Setup > Finance column (lib/nav/water-nav-config.ts).
  const waterFinanceItems = gateWater([
    { href: "/water-customers", label: "Customers", icon: Users },
    { href: "/water-suppliers", label: "Suppliers", icon: Truck },
  ])
  // James: group Employees + Payroll under People and hide the Staff item.
  // "Employees" points at the water staff page (/water-staff) — the global
  // /employees page redirects water users to the dashboard. Admin-gated.
  // The /water-staff gate now lives in the route map alongside every other
  // water route rather than being spelled out here.
  const waterPeopleItems = gateWater([
    { href: "/water-staff", label: "Staff", icon: UserCog },
    { href: "/water-payroll", label: "Payroll", icon: Banknote },
  ])
  const waterReportsItems = gateWater([
    { href: "/water-reports", label: "Reports", icon: BarChart3 },
  ])
  // Admin / Setup now only carries the genuinely rare-touch config — the
  // delivery/production items moved into their own first-class groups, and
  // Suppliers moved to Finance beside Customers.
  const waterAdminItems = gateWater([
    { href: "/water-setup",         label: "Setup",         icon: Settings },
    { href: "/water-company-setup", label: "Company Setup", icon: Settings },
  ])

  // Generic Company nav items (shown when activeFarmType === "Generic")
  // /generic-inventory is the new at-a-glance stock page (products + cards
  // + filters). /generic-stock-adjustments stays for actually changing stock.
  const genericCatalogItems = [
    { href: "/generic-products",          label: "Products",          icon: ShoppingBag },
    { href: "/generic-inventory",         label: "Inventory",         icon: Boxes },
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

  // Hotel company nav items (shown when activeFarmType === "Hotel")
  const gateHotel = <T extends { href: string }>(items: T[]) =>
    filterHotelNavItems(items, permissions.featureAccess, permissions.isAdmin)

  const hotelQuickLinkItems = gateHotel([
    { href: "/hotel-daily-closing", label: "Daily Closing", icon: FileText },
    { href: "/hotel-night-audit",   label: "Night Audit",   icon: Shield },
    { href: "/hotel-bookings",      label: "Bookings",      icon: Boxes },
    { href: "/hotel-check-in",      label: "Check-in",      icon: Activity },
  ])
  const hotelFrontDeskItems = gateHotel([
    { href: "/hotel-bookings",  label: "Bookings",   icon: Boxes },
    { href: "/hotel-check-in",  label: "Check-in",   icon: Activity },
    { href: "/hotel-check-out", label: "Check-out",   icon: Activity },
    { href: "/hotel-guests",    label: "Guests",      icon: Users },
  ])
  const hotelRoomsItems = gateHotel([
    { href: "/hotel-rooms",        label: "Room Inventory",  icon: Building2 },
    { href: "/hotel-housekeeping", label: "Housekeeping",    icon: Activity },
    { href: "/hotel-room-service", label: "Room Service",    icon: ShoppingCart },
  ])
  const hotelRestaurantItems = gateHotel([
    { href: "/hotel-restaurant",        label: "POS / Orders", icon: ShoppingCart },
    { href: "/hotel-restaurant-tables", label: "Tables",       icon: Boxes },
    { href: "/hotel-menu",              label: "Menu",         icon: FileText },
    { href: "/hotel-kitchen",           label: "Kitchen",      icon: Activity },
  ])
  const hotelFinanceItems = gateHotel([
    { href: "/hotel-billing",       label: "Billing",       icon: DollarSign },
    { href: "/hotel-invoices",      label: "Invoices",      icon: FileText },
    { href: "/hotel-payments",      label: "Payments",      icon: CreditCard },
    { href: "/hotel-expenses",      label: "Expenses",      icon: DollarSign },
    { href: "/hotel-cash-accounts", label: "Cash Accounts", icon: Wallet },
  ])
  const hotelPeopleItems = gateHotel([
    { href: "/hotel-staff",   label: "Staff",   icon: UserCog },
    { href: "/hotel-payroll", label: "Payroll", icon: Banknote },
  ])
  const hotelInventoryItems = gateHotel([
    { href: "/hotel-inventory",   label: "Supplies",     icon: Boxes },
    { href: "/hotel-maintenance", label: "Maintenance",  icon: Wrench },
  ])
  const hotelReportsItems = gateHotel([
    { href: "/hotel-reports", label: "Reports", icon: BarChart3 },
  ])
  const hotelAdminItems = gateHotel([
    { href: "/hotel-setup", label: "Setup", icon: Settings },
  ])

  // System — was a flat, unlabelled block at the bottom of the rail; now a real
  // collapsible group so it matches the top nav's System menu. Order and every
  // permission / farm-type guard are carried over unchanged from that block.
  const systemItems: SidebarItem[] = [
    ...((permissions.isAdmin || permissions.featureAccess.canSeeEmployees)
      ? [{ href: "/employees", label: "Users & Permissions", icon: UserCog }] : []),
    // #28: /reports is the poultry report page. Water, Generic, and Hotel have their own.
    ...((permissions.featureAccess.canViewReports && !isWater && !isGeneric && !isHotel)
      ? [{ href: "/reports", label: "Reports", icon: BarChart3 }] : []),
    { href: "/profile", label: "Account", icon: User },
    // Resources is poultry-specific (vaccination / feed / medication schedules).
    ...((!isWater && !isGeneric && !isHotel) ? [{ href: "/resources", label: "Resources", icon: BookOpen }] : []),
    { href: "#", label: "Alerts", icon: Bell, isButton: true, onClick: openAlerts, badge: alerts.length },
    { href: "/companies", label: "Companies", icon: Building2 },
    ...(permissions.featureAccess.canViewActivityLog
      ? [{ href: "/audit-logs", label: "Activity Log", icon: Activity }] : []),
    // /settings is the poultry farm-profile page; Water, Generic, and Hotel have their own setup.
    ...((!isWater && !isGeneric && !isHotel && permissions.featureAccess.canViewSettings)
      ? [{ href: "/settings", label: "Settings", icon: Settings }] : []),
    // /help is poultry-specific.
    ...((!isWater && !isGeneric && !isHotel) ? [{ href: "/help", label: "Help Center", icon: HelpCircle }] : []),
    { href: "/terms", label: "Terms & Conditions", icon: ListTodo },
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

  const renderGroup = (title: string, items: SidebarItem[], groupKey: string) => {
    // A group whose every item was filtered out by permissions renders nothing —
    // otherwise a staff member without, say, Deliveries sees a bare "DELIVERY"
    // heading with an empty body under it.
    if (items.length === 0) return null

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
              <div key={item.href}>{renderNavItem(item, item.isButton, item.onClick, item.badge)}</div>
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
        {/* Business Office — the owner's HQ above all companies (Prompt 2).
            Doc 3 §9: clicking it clears the active company so the HQ is
            company-neutral (the "home" icon behavior). */}
        <div>
          {renderNavItem(
            { href: "/business-office", label: "Business Office", icon: Briefcase },
            true,
            () => { try { clearActiveCompany() } catch {}; handleLinkClick?.(); router.push("/business-office") },
          )}
        </div>

        {/* Dashboard — route depends on active company type */}
        <div>
          {renderNavItem({
            href: isWater ? "/water-dashboard" : isGeneric ? "/generic-dashboard" : isHotel ? "/hotel-dashboard" : "/dashboard",
            label: "Dashboard",
            icon: isWater ? Droplets : isGeneric ? ShoppingBag : isHotel ? Building2 : Home,
          })}
        </div>

        {/* Divider */}
        <div className="border-t border-slate-800 mx-2" />

        {isWater ? (
          <>
            {/* Water — Quick Links (shortcuts) → Delivery → Production →
                Inventory → Sales & Money → Finance → People → Reports →
                Admin/Setup. James 2026-06-02 reorg. */}
            {renderGroup("Quick Links", waterQuickLinkItems, "waterQuickLinks")}

            <div className="border-t border-slate-800 mx-2" />

            {renderGroup("Delivery", waterDeliveryItems, "waterDelivery")}

            <div className="border-t border-slate-800 mx-2" />

            {renderGroup("Production", waterProductionItems, "waterProduction")}

            <div className="border-t border-slate-800 mx-2" />

            {renderGroup("Inventory", waterInventoryItems, "waterInventory")}

            <div className="border-t border-slate-800 mx-2" />

            {renderGroup("Sales & money", waterSalesMoneyItems, "waterSalesMoney")}

            <div className="border-t border-slate-800 mx-2" />

            {renderGroup("Finance", waterFinanceItems, "waterFinance")}

            <div className="border-t border-slate-800 mx-2" />

            {renderGroup("People", waterPeopleItems, "waterPeople")}

            <div className="border-t border-slate-800 mx-2" />

            {renderGroup("Reports", waterReportsItems, "waterReports")}

            <div className="border-t border-slate-800 mx-2" />

            {renderGroup("Admin / Setup", waterAdminItems, "waterAdmin")}
          </>
        ) : isHotel ? (
          <>
            {renderGroup("Quick Links", hotelQuickLinkItems, "hotelQuickLinks")}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("Front Desk", hotelFrontDeskItems, "hotelFrontDesk")}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("Rooms", hotelRoomsItems, "hotelRooms")}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("Restaurant & Bar", hotelRestaurantItems, "hotelRestaurant")}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("Finance", hotelFinanceItems, "hotelFinance")}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("People", hotelPeopleItems, "hotelPeople")}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("Inventory", hotelInventoryItems, "hotelInventory")}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("Reports", hotelReportsItems, "hotelReports")}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("Admin / Setup", hotelAdminItems, "hotelAdmin")}
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
            {/* Quick Links (fast-access shortcuts) */}
            {renderGroup("Quick Links", poultryQuickLinkItems, "poultryQuickLinks")}

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

            {/* Analytics */}
            {renderGroup("Analytics", analyticsItems, "analytics")}

            {/* Divider */}
            <div className="border-t border-slate-800 mx-2" />

            {/* Inventory & Health (merged inventory + health) */}
            {renderGroup("Inventory & Health", poultryInventoryItems, "poultryInventory")}

            {/* Divider */}
            <div className="border-t border-slate-800 mx-2" />

            {/* Feed Production + Feed Formulas now live under the Production group above. */}

            {/* Delivery (driver / vehicle / route suite, ported from Water) */}
            {renderGroup("Delivery", poultryDeliveryItems, "poultryDelivery")}

            {/* Divider */}
            <div className="border-t border-slate-800 mx-2" />

            {/* Financial */}
            {financialItems.length > 0 && renderGroup("Financial", financialItems, "financial")}

            {/* Divider */}
            <div className="border-t border-slate-800 mx-2" />

            {/* Finance — Customers + Suppliers (see poultryFinanceItems) */}
            {poultryFinanceItems.length > 0 && renderGroup("Finance", poultryFinanceItems, "poultryFinance")}

            {/* Divider */}
            <div className="border-t border-slate-800 mx-2" />

            {/* People (Staff + Payroll) */}
            {renderGroup("People", poultryPeopleItems, "poultryPeople")}

            {/* Divider */}
            <div className="border-t border-slate-800 mx-2" />

            {/* Setup — Houses + Flock Groups (see poultrySetupItems) */}
            {renderGroup("Setup", poultrySetupItems, "poultrySetup")}
          </>
        )}

        {/* Divider */}
        <div className="border-t border-slate-800 mx-2" />

        {/* System — Users & Permissions (the /employees page creates employee
            LOGIN accounts; it adapts to Water), account, alerts, companies,
            audit log and legal. Mirrors the top nav's System menu. Contents are
            built in systemItems above, guards and all. */}
        {renderGroup("System", systemItems, "system")}
      </nav>

      {/* Logout */}
      <div className="shrink-0 border-t border-slate-800 p-3">
        {isCollapsed && !isMobile ? (
          <Tooltip>
            <TooltipTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                onClick={doLogout}
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
            onClick={doLogout}
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

      {/* Desktop sidebar — fixed to the viewport so it stays put while the main
          column scrolls. `sticky` breaks here because globals.css sets overflow
          on <body>, making it a scroll container that never actually scrolls.
          The in-flow spacer below reserves the same-width column so the main
          content sits beside the fixed rail instead of under it. */}
      <div
        aria-hidden="true"
        className={cn(
          "hidden lg:block lg:shrink-0 transition-all duration-300",
          isCollapsed ? "w-16" : "w-60"
        )}
      />
      <div className={cn(
        "hidden min-h-0 overflow-hidden lg:fixed lg:top-0 lg:left-0 lg:z-40 lg:h-screen lg:flex lg:flex-col bg-slate-900 transition-all duration-300",
        isCollapsed ? "w-16" : "w-60"
      )}>
        {sidebarContent}
      </div>
    </>
  )
}
