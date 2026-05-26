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
  UserCog,
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

function WaterTopNav({ permissions }: { permissions: ReturnType<typeof usePermissions> }) {
  const moreGroup: NavGroup = {
    label: "More",
    items: [
      { href: "/profile", label: "Account", icon: User },
      // /resources and /settings are poultry-only — Water has /water-company-setup
      ...(permissions.featureAccess.canViewActivityLog
        ? [{ href: "/audit-logs", label: "Activity Log", icon: Activity }]
        : []),
      ...(permissions.isAdmin || permissions.featureAccess.canSeeEmployees
        ? [{ href: "/employees", label: "Employees", icon: UserCog }]
        : []),
    ],
  }

  // Operations dropdown houses the daily/weekly workflow pages: production,
  // distribution, daily closing, expenses, staff, payroll, maintenance, setup.
  // Without this they'd be invisible on desktop top-nav, only reachable via
  // the sidebar.
  const opsGroup: NavGroup = {
    label: "Operations",
    items: [
      { href: "/water-production-batches", label: "Production batches", icon: Boxes },
      { href: "/water-machines",           label: "Machines",           icon: Settings },
      { href: "/water-boreholes",          label: "Boreholes",          icon: Droplets },
      { href: "/water-vehicles",           label: "Vehicles",           icon: Truck },
      { href: "/water-routes",             label: "Routes",             icon: Activity },
      { href: "/water-driver-returns",     label: "Driver returns",     icon: Truck },
      { href: "/water-raw-materials",      label: "Raw materials",      icon: Boxes },
      { href: "/water-loss-records",       label: "Damages & loss",     icon: AlertTriangle },
      { href: "/water-daily-closing",      label: "Daily Closing",      icon: FileText },
      { href: "/water-reports",            label: "Reports",            icon: BarChart3 },
      { href: "/water-expenses",           label: "Expenses",           icon: DollarSign },
      { href: "/water-cash-accounts",      label: "Cash & Accounts",    icon: Wallet },
      { href: "/water-staff",              label: "Staff",              icon: Users },
      { href: "/water-payroll",            label: "Payroll",            icon: CreditCard },
      { href: "/water-maintenance",        label: "Maintenance",        icon: Settings },
      { href: "/water-company-setup",      label: "Setup",              icon: Settings },
    ],
  }

  return (
    <div className="hidden lg:block bg-sky-600 border-b border-sky-700">
      <div className="flex items-center gap-1 px-4 py-1.5 nav-rail-scroll">
        <NavLink item={{ href: "/water-dashboard", label: "Dashboard", icon: Droplets }} />
        <div className="h-5 w-px bg-white/30 mx-1" />
        <NavLink item={{ href: "/water-products", label: "Products", icon: ShoppingBag }} />
        <NavLink item={{ href: "/water-stock", label: "Stock", icon: Boxes }} />
        <NavLink item={{ href: "/water-customers", label: "Customers", icon: Users }} />
        <NavLink item={{ href: "/water-sales", label: "Sales", icon: ShoppingCart }} />
        <NavLink item={{ href: "/water-payments", label: "Payments", icon: CreditCard }} />
        <NavDropdown group={opsGroup} />
        <NavDropdown group={moreGroup} />
        <div className="ml-auto flex items-center gap-1">
          <NavLink item={{ href: "/companies", label: "Companies", icon: Building2 }} />
          {/* /help is poultry-specific */}
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
      // /resources and /settings are poultry-only — Generic has /generic-setup
      ...(permissions.featureAccess.canViewActivityLog
        ? [{ href: "/audit-logs", label: "Activity Log", icon: Activity }]
        : []),
      ...(permissions.isAdmin || permissions.featureAccess.canSeeEmployees
        ? [{ href: "/employees", label: "Employees", icon: UserCog }]
        : []),
    ],
  }

  return (
    <div className="hidden lg:block bg-emerald-600 border-b border-emerald-700">
      <div className="flex items-center gap-1 px-4 py-1.5 nav-rail-scroll">
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
      { href: "/sales", label: "Sales", icon: ShoppingCart },
      { href: "/expenses", label: "Expenses", icon: DollarSign },
      { href: "/customers", label: "Customers", icon: Users },
      { href: "/suppliers", label: "Suppliers", icon: Truck },
      { href: "/payments", label: "Payments", icon: CreditCard },
    ].filter((item) =>
      isFinancialNavItemVisible(item.href, permissions.featureAccess, permissions.isAdmin)
    ),
  }

  const moreGroup: NavGroup = {
    label: "More",
    items: [
      { href: "/profile", label: "Account", icon: User },
      { href: "/resources", label: "Resources", icon: BookOpen },
      ...(permissions.featureAccess.canViewActivityLog
        ? [{ href: "/audit-logs", label: "Activity Log", icon: Activity }]
        : []),
      ...(permissions.featureAccess.canViewSettings
        ? [{ href: "/settings", label: "Settings", icon: Settings }]
        : []),
      ...(permissions.isAdmin || permissions.featureAccess.canSeeEmployees
        ? [{ href: "/employees", label: "Employees", icon: UserCog }]
        : []),
    ],
  }

  return (
    <>
      <div className="hidden lg:block bg-orange-500 border-b border-orange-600">
        <div className="flex items-center gap-1 px-4 py-1.5 nav-rail-scroll">
          <NavLink item={{ href: "/dashboard", label: "Dashboard", icon: Home }} />
          <div className="h-5 w-px bg-white/30 mx-1" />
          <NavDropdown group={farmGroup} />
          <NavDropdown group={productionGroup} />
          <NavDropdown group={inventoryGroup} />
          {financialGroup.items.length > 0 && <NavDropdown group={financialGroup} />}
          <div className="h-5 w-px bg-white/30 mx-1" />
          {permissions.featureAccess.canViewReports && <NavLink item={{ href: "/reports", label: "Reports", icon: BarChart3 }} />}
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



