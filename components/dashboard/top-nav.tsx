"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { useState, useRef, useEffect } from "react"
import { createPortal } from "react-dom"
import { cn } from "@/lib/utils"
import { usePermissions } from "@/hooks/use-permissions"
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

  const isGroupActive = group.items.some((item) => pathname === item.href)

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
          className="w-52 bg-white rounded-lg shadow-lg border border-slate-200 py-1 z-[9999]"
          onMouseEnter={handleMouseEnter}
          onMouseLeave={handleMouseLeave}
        >
          {group.items.map((item) => {
            const Icon = item.icon
            const isActive = pathname === item.href
            return (
              <Link
                key={item.href}
                href={item.href}
                prefetch={true}
                onClick={() => setOpen(false)}
                className={cn(
                  "flex items-center gap-2.5 px-3 py-2 text-sm transition-colors",
                  isActive
                    ? "bg-orange-50 text-orange-700 font-medium"
                    : "text-slate-600 hover:bg-orange-50 hover:text-orange-700"
                )}
              >
                <Icon className={cn("h-4 w-4", isActive ? "text-orange-600" : "text-slate-400")} />
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
  const isActive = pathname === item.href
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

export function TopNavigation() {
  // Temporary business override while subscription enforcement is paused.
  const TEMP_SHOW_PAYMENTS_LINK = true
  const permissions = usePermissions()

  const farmGroup: NavGroup = {
    label: "Farm",
    items: [
      { href: "/flock-batch", label: "Flock Batch", icon: Boxes },
      { href: "/flocks", label: "Flocks", icon: Bird },
      { href: "/houses", label: "Houses", icon: Building2 },
    ],
  }

  const productionGroup: NavGroup = {
    label: "Production",
    items: [
      { href: "/production-records", label: "Production Records", icon: FileText },
      { href: "/egg-production", label: "Egg Production", icon: Egg },
      { href: "/feed-usage", label: "Feed Usage", icon: Package },
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
      { href: "/payments", label: "Payments", icon: CreditCard },
    ].filter((item) => {
      if (!permissions.featureAccess.canViewFinancial) return false
      if (item.href === "/sales") return permissions.featureAccess.canEnterSales
      if (item.href === "/expenses") return permissions.featureAccess.canEnterExpenses
      if (item.href === "/cash") return permissions.featureAccess.canViewCashLedger
      return true
    }),
  }

  const moreGroup: NavGroup = {
    label: "More",
    items: [
      { href: "/profile", label: "Account", icon: User },
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
        <div className="flex items-center gap-1 px-4 py-1.5 overflow-x-auto scrollbar-hide">
          <NavLink item={{ href: "/dashboard", label: "Dashboard", icon: Home }} />
          <div className="h-5 w-px bg-white/30 mx-1" />
          <NavDropdown group={farmGroup} />
          <NavDropdown group={productionGroup} />
          <NavDropdown group={inventoryGroup} />
          {financialGroup.items.length > 0 && <NavDropdown group={financialGroup} />}
          <div className="h-5 w-px bg-white/30 mx-1" />
          <NavLink item={{ href: "/resources", label: "Resources", icon: BookOpen }} />
          {permissions.featureAccess.canViewReports && <NavLink item={{ href: "/reports", label: "Reports", icon: BarChart3 }} />}
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



