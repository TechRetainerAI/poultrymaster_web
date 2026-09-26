"use client"

import { useState, useTransition, useEffect, Fragment } from "react"
import Link from "next/link"
import { usePathname, useRouter } from "next/navigation"
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { usePermissions } from "@/hooks/use-permissions"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { useIsMobile } from "@/hooks/use-mobile"
import {
  BarChart3,
  Users,
  Building2,
  User,
  Settings,
  ChevronDown,
  Home,
  FileText,
  Package,
  PackageMinus,
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
  Tag,
  Calculator,
  Landmark,
  ArrowLeftRight,
  PiggyBank,
  CalendarCheck,
  Boxes,
  CreditCard,
  Truck,
  Droplets,
  ShoppingBag,
  Receipt,
  Users2,
  Banknote,
  Wrench,
  Cog,
  Briefcase,
  CalendarDays,
  Shield,
  UtensilsCrossed,
  History,
  Scale,
  Coins,
  Repeat,
  CalendarClock,
  Inbox,
} from "lucide-react"
import { InventoryLogo } from "@/components/auth/logo"
import { useAlertsStore, type AlertItem } from "@/lib/store/alerts-store"
import { useSidebarStore } from "@/lib/store/sidebar-store"
import { useAuthStore } from "@/lib/store/auth-store"
import { useOnlineOrderCounts } from "@/lib/utils/online-order-alerts"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { isFinancialNavItemVisible } from "@/lib/utils/financial-nav-access"
import { filterWaterNavItems } from "@/lib/utils/water-nav-access"
import { filterHotelNavItems } from "@/lib/utils/hotel-nav-access"
import { filterRestaurantNavItems } from "@/lib/utils/restaurant-nav-access"
import { useLogout } from "@/hooks/use-logout"
import { buildPoultryNavConfig } from "@/lib/nav/poultry-nav-config"
import { buildWaterNavConfig } from "@/lib/nav/water-nav-config"
import { useQuickLinkHrefs } from "@/lib/store/quick-links-store"
import { QuickLinksDialog } from "@/components/dashboard/quick-links-dialog"
import type { MegaMenuGroup, NavGroup } from "@/lib/nav/nav-model"

/** A titled, collapsible block of sidebar rows. */
type SidebarGroup = { key: string; title: string; items: SidebarItem[] }

/**
 * Top-nav mega-menu groups -> sidebar groups.
 *
 * The Poultry and Water rails are built from lib/nav/*-nav-config.ts, and this
 * rail now reads the SAME configs instead of keeping its own hand-written copy
 * of every row. That copy is what let the two surfaces drift: rows the rail had
 * and the sidebar did not, labels that said "Birds left tracker" in one place
 * and "Birds tracker" in the other. There is one list now, and it is the rail's.
 *
 * What the conversion has to handle:
 *   * `title` here is `label` there,
 *   * `visible: false` rows are permission-gated out and must be dropped before
 *     the empty-group check, not after,
 *   * action rows (Alerts) carry an onClick and no href, which this rail
 *     already supports via isButton — unlike the mobile sheet's version of this
 *     adapter, which drops them.
 *
 * `titlePrefix` exists for Setup. Its columns include Delivery and Production,
 * which collide with the Operations columns of the same name; in the rail they
 * sit in different menus and cannot be confused, but this is one flat list.
 */
const fromMegaMenu = (
  groups: MegaMenuGroup[],
  keyPrefix: string,
  titlePrefix = "",
): SidebarGroup[] =>
  groups
    .map((g) => ({
      key: `${keyPrefix}:${g.key}`,
      title: `${titlePrefix}${g.label}`,
      items: g.items
        .filter((i) => i.visible !== false)
        .map((i): SidebarItem => ({
          // Action rows have no href. "#" is never navigated to — isButton
          // renders a <button> — but it is what keys the row in renderGroup.
          href: i.href ?? `#${i.id}`,
          label: i.title,
          icon: i.icon,
          ...(i.onClick ? { isButton: true, onClick: i.onClick } : {}),
          ...(i.badge !== undefined ? { badge: i.badge } : {}),
        })),
    }))
    .filter((g) => g.items.length > 0)

/** The rail's Quick Links is a plain NavGroup, not a mega-menu. */
const fromNavGroup = (group: NavGroup): SidebarItem[] =>
  group.items.map((i) => ({ href: i.href, label: i.label, icon: i.icon }))

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
  /**
   * Tint the whole row, not just the count pill, while the badge is above zero.
   * A red dot on the right of a dark row is easy to miss on a rail this long;
   * a row that has changed colour is not. Opt-in, because a badge that is
   * merely informational (Alerts) should not repaint the sidebar.
   */
  alertOnBadge?: boolean
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
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const clearActiveCompany = useAuthStore((s) => s.clearActiveCompany)
  const isWater = activeFarmType === "Water"
  const isGeneric = activeFarmType === "Generic"
  const isHotel = activeFarmType === "Hotel"
  const isRestaurant = activeFarmType === "Restaurant"
  // Online orders arrive without anyone touching a till. All Orders carries a
  // count of the ones nobody has looked at yet; New Guest Orders carries the
  // ones still waiting to be accepted. Returns zeroes for every other company
  // type, so it is safe to call here rather than behind a branch.
  const { unseen: unseenOnline, pending: pendingOnline } = useOnlineOrderCounts(activeFarmId, isRestaurant)
  const { isCollapsed, toggle, isMobileOpen, toggleMobile, setMobileOpen } = useSidebarStore()
  // 318. null = never customised = the config's defaults, which is also what
  // renders while it loads.
  const quickLinkHrefs = useQuickLinkHrefs()
  const [customiseOpen, setCustomiseOpen] = useState(false)

  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>({
    farm: true,
    production: true,
    analytics: true,
    inventory: true,
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

  // Navigation items.
  //
  // Poultry and Water no longer spell their rows out here. Both rails are
  // generated from the same lib/nav/*-nav-config.ts the top nav is built from,
  // and rendered in the top nav's own order, so the two surfaces cannot say
  // different things about the same farm. See fromMegaMenu above.
  //
  // The other company types still carry their lists below; their configs are
  // either built inline in top-nav.tsx (Generic) or not yet adopted here.

  const TEMP_SHOW_PAYMENTS_LINK = true
  // The financial allow-list is default-deny and keyed on href, so it has to
  // follow each row into whichever of the three groups below it lands in.
  const gateFinancial = (items: SidebarItem[]) =>
    items.filter((item) =>
      isFinancialNavItemVisible(item.href, permissions.featureAccess, permissions.isAdmin, {
        tempShowPayments: TEMP_SHOW_PAYMENTS_LINK,
      })
    )

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

  // Only the Reports row is still written out here. Everything else on the
  // water rail comes from buildWaterNavConfig below. The rail reaches its
  // report catalogue through the Reports menu's own trigger and "View all
  // reports" link, neither of which survives as a config row, so the sidebar
  // needs this one link of its own.
  const waterReportsItems = gateWater([
    { href: "/water-reports", label: "Reports", icon: BarChart3 },
  ])

  // Generic Company nav items (shown when activeFarmType === "Generic")
  // Module settings and the industry vocabulary, shared with the top nav and
  // the mobile bar through one cached hook.
  const genericModules = useGenericModules()

  // /generic-inventory is the new at-a-glance stock page (products + cards
  // + filters). /generic-stock-adjustments stays for actually changing stock.
  //
  // Every item here is one of the OPTIONAL modules in section 5 of the spec:
  // a SaaS company, a gym and a school do not sell stock, and a template that
  // turns them off must actually take them off the menu. showExisting rather
  // than showNew, so a failed settings request leaves the menu as it was
  // instead of emptying it.
  const genericCatalogItems = [
    ...(genericModules.showExisting("enableProducts")
      ? [{ href: "/generic-products", label: "Products", icon: ShoppingBag }] : []),
    ...(genericModules.showExisting("enableInventory")
      ? [{ href: "/generic-inventory", label: "Inventory", icon: Boxes }] : []),
    ...(genericModules.showExisting("enableStockAdjustments")
      ? [{ href: "/generic-stock-adjustments", label: "Stock adjustments", icon: Boxes }] : []),
    ...(genericModules.showExisting("enableInternalUse")
      ? [{ href: "/generic-internal-use", label: "Internal Use", icon: PackageMinus }] : []),
  ]
  // Only the NEW items are gated on module settings. Every item that existed
  // before templates stays ungated -- retro-fitting a gate would take away
  // access people have today.
  const genericSubscriptionItems = [
    ...(genericModules.showNew("enableSubscriptions")
      ? [
          { href: "/generic-service-plans",  label: genericModules.labels.planPlural,         icon: Repeat },
          { href: "/generic-subscriptions",  label: genericModules.labels.subscriptionPlural, icon: CalendarClock },
          { href: "/generic-billing-runs",   label: "Billing runs",                           icon: Receipt },
        ]
      : []),
  ]
  const genericSalesItems = [
    { href: "/generic-sales",              label: "Sales",             icon: ShoppingCart },
    ...(genericModules.showNew("enableInvoices")
      ? [{ href: "/generic-invoices", label: genericModules.labels.invoicePlural, icon: FileText }]
      : []),
    { href: "/generic-customers",          label: genericModules.labels.customerPlural, icon: Users },
    { href: "/generic-customer-payments",  label: genericModules.labels.paymentPlural, icon: CreditCard },
    ...(genericModules.showNew("enableCustomerBalances")
      ? [{ href: "/generic-customer-balances", label: genericModules.labels.customerBalance, icon: Scale }]
      : []),
  ]
  const genericPurchasingItems = [
    { href: "/generic-suppliers",          label: "Suppliers",         icon: Truck },
    // Buying stock is optional too (section 5). A service business owes its
    // vendors through expenses, and Supplier Balances below covers that.
    ...(genericModules.showExisting("enablePurchases")
      ? [{ href: "/generic-purchases", label: "Purchases", icon: Package }] : []),
    { href: "/generic-supplier-payments",  label: "Supplier payments", icon: CreditCard },
    // 251 gave both of these a toggle of their own. Supplier balances no longer
    // rides on Purchases: a service business owes vendors through expenses,
    // which is exactly what 248's payables arm reads, so gating it on stock
    // buying hid it from the companies that needed it most.
    ...(genericModules.showExisting("enableSupplierBalances")
      ? [{ href: "/generic-supplier-balances", label: "Supplier balances", icon: Scale }]
      : []),
    { href: "/generic-expenses",           label: "Expenses",          icon: DollarSign },
    ...(genericModules.showExisting("enableRecurringExpenses")
      ? [{ href: "/generic-recurring-expenses", label: "Recurring expenses", icon: Repeat }]
      : []),
  ]
  const genericMoneyItems = [
    ...(genericModules.showExisting("enableCashAccounts")
      ? [
          { href: "/generic-cash",           label: "Cash & Accounts", icon: Wallet },
          { href: "/generic-cash-transfers", label: "Cash transfers",  icon: Activity },
        ]
      : []),
    { href: "/generic-daily-closings", label: "Daily Closing",   icon: FileText },
    { href: "/generic-owner-money",    label: "Owner money",     icon: Wallet },
  ]
  // Generic — People (Phase 6: staff + attendance + payroll, migrations 055/056)
  const genericPeopleItems = [
    { href: "/generic-staff",       label: "Staff",      icon: Users2 },
    { href: "/generic-attendance",  label: "Attendance", icon: Activity },
    { href: "/generic-payroll",     label: "Payroll",    icon: Banknote },
    { href: "/generic-staff-payments", label: "Staff payments", icon: Banknote },
  ]
  const genericAdminItems = [
    { href: "/generic-reports",  label: "Reports",  icon: BarChart3 },
    { href: "/generic-setup",    label: "Setup",    icon: Settings },
    // Setup is the company PROFILE; Settings is how the company works --
    // which modules it has and what they default to (251).
    { href: "/generic-settings", label: "Settings", icon: Cog },
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
    { href: "/hotel-bookings",     label: "Bookings",      icon: Boxes },
    { href: "/hotel-availability", label: "Availability",  icon: Activity },
    { href: "/hotel-check-in",     label: "Check-in",      icon: Activity },
    { href: "/hotel-check-out",    label: "Check-out",     icon: Activity },
    { href: "/hotel-guests",       label: "Guests",        icon: Users },
    { href: "/hotel-guest-folio",  label: "Guest Folio",   icon: FileText },
    { href: "/hotel-stay-history", label: "Stay History",  icon: FileText },
  ])
  const hotelGuestServicesItems = gateHotel([
    { href: "/hotel-communications",  label: "Guest Log",    icon: FileText },
    { href: "/hotel-guest-requests",  label: "Requests",     icon: Activity },
    { href: "/hotel-lost-found",      label: "Lost & Found", icon: Boxes },
  ])
  const hotelRoomsItems = gateHotel([
    { href: "/hotel-rooms",                  label: "Room Inventory",  icon: Building2 },
    { href: "/hotel-housekeeping",           label: "Housekeeping",    icon: Activity },
    { href: "/hotel-housekeeping-schedule",  label: "HK Schedule",     icon: Activity },
    { href: "/hotel-room-service",           label: "Room Service",    icon: ShoppingCart },
  ])
  const hotelRestaurantItems = gateHotel([
    { href: "/hotel-restaurant",        label: "POS / Orders", icon: ShoppingCart },
    { href: "/hotel-restaurant-tables", label: "Tables",       icon: Boxes },
    { href: "/hotel-menu",              label: "Menu",         icon: FileText },
    { href: "/hotel-kitchen",           label: "Kitchen",      icon: Activity },
  ])
  const hotelFinanceItems = gateHotel([
    { href: "/hotel-billing",           label: "Billing",           icon: DollarSign },
    { href: "/hotel-invoices",          label: "Invoices",          icon: FileText },
    { href: "/hotel-payments",          label: "Payments",          icon: CreditCard },
    { href: "/hotel-expenses",          label: "Expenses",          icon: DollarSign },
    { href: "/hotel-customers",         label: "Customers",         icon: Users },
    { href: "/hotel-customer-payments", label: "Customer Payments", icon: Receipt },
    { href: "/hotel-suppliers",         label: "Suppliers",         icon: Truck },
    { href: "/hotel-supplier-payments", label: "Supplier Payments", icon: Banknote },
    { href: "/hotel-assets",            label: "Capital Assets",    icon: Briefcase },
    { href: "/hotel-cash-accounts",     label: "Cash Accounts",     icon: Wallet },
    { href: "/hotel-cash-flow",         label: "Cash Flow",         icon: Activity },
    { href: "/hotel-profit-loss",       label: "Profit & Loss",     icon: BarChart3 },
  ])
  const hotelPeopleItems = gateHotel([
    { href: "/hotel-staff",           label: "Staff",            icon: UserCog },
    { href: "/hotel-payroll",         label: "Payroll",          icon: Banknote },
    { href: "/hotel-employee-loans",  label: "Loans & Advances", icon: Coins },
  ])
  const hotelInventoryItems = gateHotel([
    { href: "/hotel-inventory",   label: "Supplies",     icon: Boxes },
    { href: "/hotel-maintenance", label: "Maintenance",  icon: Wrench },
    // Shift Handover moved here from Reports: it is a shift-operations record,
    // not a report, and Reports should list reports and nothing else.
    { href: "/hotel-shift-handover", label: "Shift Handover", icon: FileText },
  ])
  const hotelReportsItems = gateHotel([
    { href: "/hotel-reports",        label: "All Reports",    icon: BarChart3 },
  ])
  const hotelAdminItems = gateHotel([
    { href: "/hotel-company-setup", label: "Company Setup", icon: Building2 },
    // "Hotel Setup", not "Setup": inside a group now titled Setup, a row also
    // called Setup read as a loop. Matches lib/nav/hotel-nav-config.ts.
    { href: "/hotel-setup", label: "Hotel Setup", icon: Settings },
  ])

  // Restaurant company nav items (shown when activeFarmType === "Restaurant")
  // Restaurant — grouped to match the top-nav mega menus
  const gateRestaurant = <T extends { href: string }>(items: T[]) =>
    filterRestaurantNavItems(items, permissions.featureAccess, permissions.isAdmin)

  const restaurantOrdersItems = gateRestaurant([
    { href: "/restaurant-pos",    label: "POS / New Order", icon: ShoppingCart },
    // Guest QR orders wait here for staff to accept them before the kitchen sees
    // them. The top-nav menu has always listed this; the sidebar did not, which
    // left the rail with no route at all to the screen where online orders are
    // accepted.
    // A workload count, not a notification: it stays until the orders are
    // actually accepted or rejected, and is deliberately NOT cleared by opening
    // the screen the way the All Orders count is.
    { href: "/restaurant-pending-orders", label: "New Guest Orders", icon: Inbox,
      badge: pendingOnline || undefined, alertOnBadge: true },
    // `|| undefined` rather than passing 0: the sidebar guards its pill with
    // `{badge && badge > 0 && ...}`, and a leading `0 &&` short-circuits to the
    // NUMBER 0 — which React happily renders as a visible "0". Handing it
    // undefined instead means nothing is drawn when there is nothing to report.
    // The same latent bug affects the shared Alerts row; see the note in
    // plan/plan.md rather than a change here, which would touch four other modules.
    { href: "/restaurant-orders", label: "All Orders",      icon: FileText,
      badge: unseenOnline || undefined, alertOnBadge: true },
  ])
  const restaurantKitchenItems = gateRestaurant([
    { href: "/restaurant-kds",    label: "Kitchen Display", icon: Activity },
  ])
  const restaurantDiningItems = gateRestaurant([
    { href: "/restaurant-floor-plan",   label: "Restaurant Areas",      icon: Building2 },
    { href: "/restaurant-reservations", label: "Reservations & Waitlist", icon: CalendarDays },
  ])
  const restaurantDeliveryOnlineItems = gateRestaurant([
    { href: "/restaurant-online-orders", label: "Online Settings",     icon: ShoppingBag },
    { href: "/restaurant-delivery",      label: "Drivers & Dispatch",  icon: Truck },
  ])
  // Reports used to sit in this list, between Ingredients and Customers. That
  // put the profit-and-loss screen inside a group headed "Inventory", while the
  // top nav gave Reports a menu of its own -- the two navigations disagreed
  // about where reporting lives. It now has its own group below, matching the
  // top nav, and is gated on canViewReports in restaurant-nav-access.ts.
  // Inventory, Money, Expenses and Growth are separate groups, in the same
  // order and with the same items as the top nav (lib/nav/restaurant-nav-config.ts):
  // Money is where cash sits and moves; Expenses is what the restaurant spends on.
  const restaurantInventoryItems = gateRestaurant([
    { href: "/restaurant-inventory", label: "Ingredients & Stock", icon: Boxes },
  ])
  const restaurantMoneyItems = gateRestaurant([
    { href: "/restaurant-tills",               label: "Tills & Shifts",     icon: Calculator },
    { href: "/restaurant-cash-accounts",       label: "Cash Accounts",      icon: Wallet },
    { href: "/restaurant-cash-transfers",      label: "Cash Transfers",     icon: ArrowLeftRight },
    { href: "/restaurant-cash-reconciliation", label: "Reconciliation",     icon: Scale },
    { href: "/restaurant-daily-closing",       label: "Daily Closing",      icon: CalendarCheck },
    { href: "/restaurant-owner-money",         label: "Owner Money",        icon: PiggyBank },
    { href: "/restaurant-loans",               label: "Loans",              icon: Landmark },
    { href: "/restaurant-payroll",             label: "Payroll",            icon: Banknote },
    { href: "/restaurant-staff-loans",         label: "Staff Loans & Advances", icon: Coins },
    { href: "/restaurant-cash-flow",           label: "Cash Flow",          icon: Activity },
    { href: "/restaurant-profit-loss",         label: "Profit & Loss",      icon: BarChart3 },
    { href: "/restaurant-payments",            label: "Income & Expenses",  icon: DollarSign },
  ])
  const restaurantExpenseItems = gateRestaurant([
    { href: "/restaurant-expenses",                label: "Record Expenses",    icon: Receipt },
    { href: "/restaurant-expenses?tab=categories", label: "Expense Categories", icon: Tag },
    { href: "/restaurant-reports/expenses",        label: "Expense Report",     icon: BarChart3 },
  ])
  const restaurantGrowthItems = gateRestaurant([
    { href: "/restaurant-crm",           label: "Customers & CRM",    icon: Users },
    { href: "/restaurant-loyalty",       label: "Loyalty & Rewards",  icon: CreditCard },
    { href: "/restaurant-events",        label: "Events & Catering",  icon: CalendarDays },
    { href: "/restaurant-gift-cards",    label: "Gift Cards",         icon: CreditCard },
    { href: "/restaurant-notifications", label: "Notifications",      icon: Bell },
  ])
  // Its own group, mirroring the top nav's Reports mega-menu. The rail links to
  // the catalog; the 24 individual reports live under it.
  const restaurantReportsItems = gateRestaurant([
    { href: "/restaurant-reports", label: "Reports", icon: BarChart3 },
  ])
  const restaurantMenuSetupItems = gateRestaurant([
    { href: "/restaurant-menu",   label: "Menu Items",      icon: UtensilsCrossed },
    { href: "/restaurant-staff",  label: "Staff & Roles",   icon: UserCog },
    { href: "/restaurant-setup",  label: "Restaurant Setup", icon: Settings },
  ])

  // System — was a flat, unlabelled block at the bottom of the rail; now a real
  // collapsible group so it matches the top nav's System menu. Order and every
  // permission / farm-type guard are carried over unchanged from that block.
  // ------------------------------------------------------------------ nav
  // The rail's own config, for the two company types that have adopted it.
  // Plain function calls, not hooks, so building one only for the active type
  // cannot change hook order.
  const poultryNav = (!isWater && !isGeneric && !isHotel && !isRestaurant)
    ? buildPoultryNavConfig({ permissions, onOpenAlerts: openAlerts, alertCount: alerts.length, quickLinkHrefs })
    : null
  const waterNav = isWater
    ? buildWaterNavConfig({ permissions, onOpenAlerts: openAlerts, alertCount: alerts.length, quickLinkHrefs })
    : null

  /**
   * Quick Links, plus the row that opens the picker (318).
   *
   * An action row rather than a control bolted onto the group heading: the
   * heading is the collapse toggle, and the rail already renders action rows
   * (Alerts), so this needs nothing renderGroup does not already do -- it works
   * collapsed, in the mobile drawer and with a keyboard for free.
   *
   * The pseudo-href is a key, never a destination; isButton is what decides
   * this renders as a <button>.
   */
  const quickLinkItems = (nav: { quickLinks: NavGroup }): SidebarItem[] => [
    ...fromNavGroup(nav.quickLinks),
    {
      href: "#customise-quick-links",
      label: "Customise…",
      icon: Settings,
      isButton: true,
      onClick: () => setCustomiseOpen(true),
    },
  ]

  // Reports is a menu on the rail, not a config section: its contents come from
  // lib/reports/*-reports-config.ts and run to dozens of rows, which would bury
  // everything else in a vertical rail. Both surfaces get the same two ways in
  // that the mobile sheet already uses — the dashboard and the catalogue.
  const poultryReportsItems: SidebarItem[] = permissions.featureAccess.canViewReports
    ? [
        { href: "/reports",         label: "Reports Dashboard", icon: BarChart3 },
        { href: "/poultry/reports", label: "All reports",       icon: BookOpen },
      ]
    : []

  const systemItems: SidebarItem[] = [
    ...((permissions.isAdmin || permissions.featureAccess.canSeeEmployees)
      ? [{ href: "/employees", label: "Users & Permissions", icon: UserCog }] : []),
    // #28: /reports is the poultry report page. Water, Generic, and Hotel have their own.
    ...((permissions.featureAccess.canViewReports && !isWater && !isGeneric && !isHotel && !isRestaurant)
      ? [{ href: "/reports", label: "Reports", icon: BarChart3 }] : []),
    { href: "/profile", label: "Account", icon: User },
    // Resources is poultry-specific (vaccination / feed / medication schedules).
    ...((!isWater && !isGeneric && !isHotel && !isRestaurant) ? [{ href: "/resources", label: "Resources", icon: BookOpen }] : []),
    { href: "#", label: "Alerts", icon: Bell, isButton: true, onClick: openAlerts, badge: alerts.length },
    { href: "/companies", label: "Companies", icon: Building2 },
    // Subscription billing is the ACCOUNT's own, not the company's trading
    // money, so it sits beside Companies and Account rather than among Cash
    // Flow and Loans. Same gate it had in the money group, carried across with
    // it -- and because systemItems is shared, every company type now has a
    // link to its own subscription instead of only Poultry.
    ...gateFinancial([{ href: "/billing", label: "Billing", icon: CreditCard }]),
    ...(permissions.featureAccess.canViewActivityLog
      ? [{ href: "/audit-logs", label: "Activity Log", icon: Activity }] : []),
    // The poultry farm profile. Water, Generic and Hotel have their own setup links
    // in their groups above; this is the equivalent row for Poultry, pointing at the
    // database-backed pages rather than /settings (now only a redirect).
    ...((!isWater && !isGeneric && !isHotel && !isRestaurant && permissions.featureAccess.canViewSettings)
      ? [{ href: "/poultry-setup", label: "Farm Setup", icon: Settings },
         { href: "/poultry-company-setup", label: "Company Setup", icon: Settings }] : []),
    // Configuration, but a finance decision: it changes what the owner reads as
    // profit, so it follows the financial flag rather than the settings one.
    ...((!isWater && !isGeneric && !isHotel && !isRestaurant && permissions.featureAccess.canViewFinancial)
      ? [{ href: "/poultry-financial-settings", label: "Financial Settings", icon: Coins }] : []),
    // /help is poultry-specific (flocks, eggs, vaccinations).
    ...((!isWater && !isGeneric && !isHotel && !isRestaurant) ? [{ href: "/help", label: "Help Center", icon: HelpCircle }] : []),
    { href: "/terms", label: "Terms & Conditions", icon: ListTodo },
  ]

  // Single items (no group)
  const renderNavItem = (
    item: { href: string; label: string; icon: any },
    isButton = false,
    onClick?: () => void,
    badge?: number,
    alertOnBadge = false
  ) => {
    const isActive =
      pathname === item.href || (item.href !== "/dashboard" && pathname.startsWith(`${item.href}/`))
    const Icon = item.icon
    // Something has arrived that nobody has looked at. Only ever applied to a
    // row that asked for it, and never to the row you are already standing on —
    // the active state is the stronger signal and they would fight each other.
    const alerting = alertOnBadge && !!badge && badge > 0 && !isActive

    const content = (
      <div
        className={cn(
          "flex items-center gap-3 px-4 py-2.5 text-sm font-medium rounded-md transition-colors relative",
          isActive
            ? "bg-slate-700 text-white border-l-[3px] border-blue-400 pl-[13px]"
            : alerting
              ? "bg-rose-950/50 text-rose-50 hover:bg-rose-900/50 border-l-[3px] border-rose-400 pl-[13px]"
              : "text-slate-300 hover:bg-slate-800 hover:text-white border-l-[3px] border-transparent pl-[13px]",
          isCollapsed && !isMobile ? "justify-center px-2 pl-2" : ""
        )}
      >
        <Icon className={cn("h-5 w-5 shrink-0",
          isActive ? "text-blue-400" : alerting ? "text-rose-300" : "text-slate-400")} />
        {(!isCollapsed || isMobile) && (
          <span className="truncate">{item.label}</span>
        )}
        {badge && badge > 0 && (!isCollapsed || isMobile) && (
          <span className="ml-auto inline-flex items-center justify-center min-w-[20px] h-5 rounded-full bg-red-500 text-white text-[10px] font-bold px-1.5">
            {badge > 99 ? '99+' : badge}
          </span>
        )}
        {/* Collapsed rail: no room for the pill, and the tooltip needs a hover to
            find. A dot on the icon is the only thing that still reads at 56px.
            Gated on alertOnBadge rather than on badge alone, so this stays off
            every other company type's rail — Alerts is badged on Poultry, Water,
            Generic and Hotel, and none of them asked for a dot. */}
        {alerting && isCollapsed && !isMobile && (
          <span className="absolute right-1.5 top-1.5 h-2 w-2 rounded-full bg-red-500 ring-2 ring-slate-900" />
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
            // The badge was dropped here while the rail was collapsed, even though
            // the collapsed tooltip below already renders one. Passed on only for
            // rows that opted in, so the collapsed rail is unchanged for every
            // other company type.
            <div key={item.href}>{renderNavItem(
              item, item.isButton, item.onClick,
              item.alertOnBadge ? item.badge : undefined, item.alertOnBadge)}</div>
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
              <div key={item.href}>{renderNavItem(item, item.isButton, item.onClick, item.badge, item.alertOnBadge)}</div>
            ))}
          </div>
        )}
      </div>
    )
  }

  /** renderGroup over a list of them. Fragment, not a wrapper div: the nav is a
   *  flow of groups and dividers, and an extra element here would break the
   *  spacing between them. */
  const renderGroups = (groups: SidebarGroup[]) =>
    groups.map((g) => <Fragment key={g.key}>{renderGroup(g.title, g.items, g.key)}</Fragment>)

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
            href: isWater ? "/water-dashboard" : isGeneric ? "/generic-dashboard" : isHotel ? "/hotel-dashboard" : isRestaurant ? "/restaurant-dashboard" : "/dashboard",
            label: "Dashboard",
            icon: isWater ? Droplets : isGeneric ? ShoppingBag : isHotel ? Building2 : isRestaurant ? UtensilsCrossed : Home,
          })}
        </div>

        {/* Divider */}
        <div className="border-t border-slate-800 mx-2" />

        {isWater ? (
          <>
            {/* Generated from buildWaterNavConfig, in the rail's own order:
                Quick Links | Operations | Sales, Expenses & Money | Trackers |
                Reports | Setup. Dividers fall where the rail has a separate
                menu, so a cluster here is a menu up there. */}
            {renderGroup("Quick Links", quickLinkItems(waterNav!), "waterQuickLinks")}

            <div className="border-t border-slate-800 mx-2" />

            {renderGroups(fromMegaMenu(waterNav!.operations, "waterOps"))}

            <div className="border-t border-slate-800 mx-2" />

            {/* Three adjacent groups with no divider between them, so they
                still read as the one "Sales, Expenses & Money" menu. */}
            {renderGroups(fromMegaMenu(waterNav!.salesMoney, "waterMoney"))}

            <div className="border-t border-slate-800 mx-2" />

            {/* The rail's Trackers menu holds a single column labelled
                "Stock", which says nothing on its own in a flat list — so the
                MENU name is used here instead. Same for System at the foot. */}
            {renderGroups(fromMegaMenu(waterNav!.analytics, "waterAnalytics").map(
              (g) => ({ ...g, title: "Trackers" })
            ))}
            {renderGroup("Reports", waterReportsItems, "waterReports")}

            <div className="border-t border-slate-800 mx-2" />

            {renderGroups(fromMegaMenu(waterNav!.setup, "waterSetup", "Setup · "))}
          </>
        ) : isHotel ? (
          <>
            {renderGroup("Quick Links", hotelQuickLinkItems, "hotelQuickLinks")}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("Front Desk", hotelFrontDeskItems, "hotelFrontDesk")}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("Guest Services", hotelGuestServicesItems, "hotelGuestServices")}
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
            {renderGroup("Setup", hotelAdminItems, "hotelAdmin")}
          </>
        ) : isRestaurant ? (
          <>
            {renderGroup("Orders", restaurantOrdersItems, "restaurantOrders")}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("Kitchen", restaurantKitchenItems, "restaurantKitchen")}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("Dining", restaurantDiningItems, "restaurantDining")}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("Delivery & Online", restaurantDeliveryOnlineItems, "restaurantDeliveryOnline")}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("Inventory", restaurantInventoryItems, "restaurantInventory")}
            {restaurantMoneyItems.length > 0 && (
              <>
                <div className="border-t border-slate-800 mx-2" />
                {renderGroup("Money", restaurantMoneyItems, "restaurantMoney")}
              </>
            )}
            {restaurantExpenseItems.length > 0 && (
              <>
                <div className="border-t border-slate-800 mx-2" />
                {renderGroup("Expenses", restaurantExpenseItems, "restaurantExpenses")}
              </>
            )}
            {restaurantGrowthItems.length > 0 && (
              <>
                <div className="border-t border-slate-800 mx-2" />
                {renderGroup("Growth", restaurantGrowthItems, "restaurantGrowth")}
              </>
            )}
            {restaurantReportsItems.length > 0 && (
              <>
                <div className="border-t border-slate-800 mx-2" />
                {renderGroup("Reports", restaurantReportsItems, "restaurantReports")}
              </>
            )}
            <div className="border-t border-slate-800 mx-2" />
            {renderGroup("Menu & Setup", restaurantMenuSetupItems, "restaurantMenuSetup")}
          </>
        ) : isGeneric ? (
          <>
            {/* Generic Company — Catalog. Gone entirely for a company with no
                stock modules on, rather than an empty heading. */}
            {genericCatalogItems.length > 0 && (
              <>
                {renderGroup("Catalog", genericCatalogItems, "genericCatalog")}

                <div className="border-t border-slate-800 mx-2" />
              </>
            )}

            {genericSubscriptionItems.length > 0 && (
              <>
                {/* Generic Company — Subscriptions (migrations 242-243) */}
                {renderGroup("Subscriptions", genericSubscriptionItems, "genericSubscriptions")}

                <div className="border-t border-slate-800 mx-2" />
              </>
            )}

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
            {/* Generated from buildPoultryNavConfig, in the rail's own order:
                Quick Links | Operations | Sales, Expenses & Money | Trackers |
                Reports | Setup. Dividers fall where the rail has a separate
                menu, so a cluster here is a menu up there.

                What moved, versus the hand-written lists this replaced:
                Trackers dropped from third place to sit beside Reports where
                the rail has it, Farm's lone row joined Operations > Purchase,
                and Setup grew from two rows to the rail's six columns. */}
            {renderGroup("Quick Links", quickLinkItems(poultryNav!), "poultryQuickLinks")}

            <div className="border-t border-slate-800 mx-2" />

            {renderGroups(fromMegaMenu(poultryNav!.operations, "poultryOps"))}

            <div className="border-t border-slate-800 mx-2" />

            {/* Three adjacent groups with no divider between them, so they
                still read as the one "Sales, Expenses & Money" menu. */}
            {renderGroups(fromMegaMenu(poultryNav!.salesMoney, "poultryMoney"))}

            <div className="border-t border-slate-800 mx-2" />

            {/* The rail's Trackers menu holds one column, itself labelled
                "Trackers" — so the MENU name used here happens to be the same
                word. Same treatment as System at the foot. */}
            {renderGroups(fromMegaMenu(poultryNav!.analytics, "poultryAnalytics").map(
              (g) => ({ ...g, title: "Trackers" })
            ))}
            {renderGroup("Reports", poultryReportsItems, "poultryReports")}

            <div className="border-t border-slate-800 mx-2" />

            {renderGroups(fromMegaMenu(poultryNav!.setup, "poultrySetup", "Setup · "))}
            {/* Tools follows Setup here for the same reason it does in the top
                bar: one-off jobs after the things you configure and revisit.
                Titled from the MENU, exactly as Trackers above is: a
                single-group panel whose group repeats the menu name. */}
            {renderGroups(fromMegaMenu(poultryNav!.tools, "poultryTools").map(
              (g) => ({ ...g, title: "Tools" })
            ))}
          </>
        )}

        {/* Divider */}
        <div className="border-t border-slate-800 mx-2" />

        {/* System — alerts, activity, billing, terms and the rest of the
            user's own context.

            Poultry and Water take it from the rail's System menu like every
            other group, which is what keeps Setup from being listed twice:
            systemItems carries Farm Setup / Company Setup / Financial Settings
            / Companies, and those same rows are in the rail's Setup > Company
            column, now rendered above. The other company types keep
            systemItems, guards and all. */}
        {poultryNav || waterNav
          ? renderGroups(fromMegaMenu((poultryNav ?? waterNav)!.system, "system").map(
              (g, i) => ({
                ...g,
                title: "System",
                // Account is `visible: false` in both configs, because the RAIL
                // reaches /profile through the header avatar a few pixels away
                // and a menu row there would have said the same thing twice.
                // The sidebar is the opposite side of the screen from that
                // avatar, so it gets the row back — added HERE rather than by
                // unhiding it in the config, which would put it on the rail
                // too. First row, which is where it sat in systemItems and
                // where the config lists it. Only the first group: these two
                // configs each have exactly one System column, and if a second
                // is ever added, Account should not repeat in it.
                items: i === 0
                  ? [{ href: "/profile", label: "Account", icon: User }, ...g.items]
                  : g.items,
              })
            ))
          : renderGroup("System", systemItems, "system")}
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

      {/* ONE dialog for the rail. sidebarContent is rendered twice -- the
          mobile drawer and the desktop rail -- so a dialog inside it would be
          mounted twice over one piece of open state. */}
      {(poultryNav || waterNav) && (
        <QuickLinksDialog
          open={customiseOpen}
          onOpenChange={setCustomiseOpen}
          nav={(poultryNav ?? waterNav)!}
        />
      )}
    </>
  )
}
