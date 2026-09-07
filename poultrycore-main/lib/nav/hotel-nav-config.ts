/**
 * Hotel desktop top-nav contents.
 *
 * Same treatment as poultry-nav-config.ts: flat links + a single "More"
 * dropdown collapse into grouped mega-menu panels.
 *
 * Rail: Dashboard | Quick Links | Operations | Sales & Money | Restaurant |
 *       Reports | Setup                                          -> System
 */

import {
  Activity, BarChart3, Bed, Bell, Boxes, Building2, CalendarSearch, ClipboardCheck, CreditCard,
  DollarSign, FileText, Home, MessageSquare, Package, ScrollText, Search, Settings, Shield, ShoppingCart, Truck,
  User, UserCog, Users, Users2, UtensilsCrossed, Wallet, Wrench,
} from "lucide-react"
import type { UserPermissions } from "@/hooks/use-permissions"
import { isHotelNavItemVisible } from "@/lib/utils/hotel-nav-access"
import type { MegaMenuGroup, NavGroup } from "./nav-model"

export interface HotelNavDeps {
  permissions: UserPermissions
}

export interface HotelNavConfig {
  quickLinks: NavGroup
  operations: MegaMenuGroup[]
  salesMoney: MegaMenuGroup[]
  restaurant: MegaMenuGroup[]
  reports: MegaMenuGroup[]
  setup: MegaMenuGroup[]
  system: MegaMenuGroup[]
}

export function buildHotelNavConfig({ permissions }: HotelNavDeps): HotelNavConfig {
  const { featureAccess, isAdmin } = permissions
  const vis = (href: string) => isHotelNavItemVisible(href, featureAccess, isAdmin)

  return {
    quickLinks: {
      label: "Quick Links",
      items: [
        { href: "/hotel-daily-closing",  label: "Daily Closing",  icon: FileText },
        { href: "/hotel-night-audit",    label: "Night Audit",    icon: Shield },
        { href: "/hotel-shift-handover", label: "Shift Handover", icon: ScrollText },
        { href: "/hotel-bookings",       label: "Bookings",       icon: FileText },
      ],
    },

    operations: [
      {
        key: "front-desk",
        label: "Front Desk",
        items: [
          { id: "bookings",  title: "Bookings",  icon: FileText,       href: "/hotel-bookings",  visible: vis("/hotel-bookings") },
          { id: "guests",    title: "Guests",     icon: Users,          href: "/hotel-guests",    visible: vis("/hotel-guests") },
          { id: "check-in",  title: "Check-in",   icon: Activity,       href: "/hotel-check-in",  visible: vis("/hotel-check-in") },
          { id: "check-out", title: "Check-out",  icon: ClipboardCheck, href: "/hotel-check-out", visible: vis("/hotel-check-out") },
          { id: "availability", title: "Availability", icon: Search, href: "/hotel-availability", visible: vis("/hotel-bookings") },
          { id: "folio",     title: "Guest Folio",  icon: ScrollText, href: "/hotel-guest-folio", visible: vis("/hotel-billing") },
          { id: "history",   title: "Stay History", icon: FileText,   href: "/hotel-stay-history", visible: vis("/hotel-check-in") },
        ],
      },
      {
        key: "guest-services",
        label: "Guest Services",
        items: [
          { id: "communications", title: "Guest Log",    icon: MessageSquare, href: "/hotel-communications", visible: vis("/hotel-guests") },
          { id: "requests",       title: "Requests",     icon: Bell,          href: "/hotel-guest-requests", visible: vis("/hotel-guests") },
          { id: "lost-found",     title: "Lost & Found", icon: Package,       href: "/hotel-lost-found",     visible: vis("/hotel-guests") },
        ],
      },
      {
        key: "rooms",
        label: "Rooms & Housekeeping",
        items: [
          { id: "rooms",        title: "Rooms",         icon: Building2,      href: "/hotel-rooms",        visible: vis("/hotel-rooms") },
          { id: "housekeeping", title: "Housekeeping",   icon: ClipboardCheck, href: "/hotel-housekeeping", visible: vis("/hotel-housekeeping") },
          { id: "hk-schedule",  title: "HK Schedule",    icon: CalendarSearch, href: "/hotel-housekeeping-schedule", visible: vis("/hotel-housekeeping") },
          { id: "room-service", title: "Room Service",   icon: Truck,         href: "/hotel-room-service", visible: vis("/hotel-room-service") },
        ],
      },
    ],

    salesMoney: [
      {
        key: "billing",
        label: "Billing",
        items: [
          { id: "billing",  title: "Billing",  icon: DollarSign, href: "/hotel-billing",  visible: vis("/hotel-billing") },
          { id: "invoices", title: "Invoices", icon: FileText,   href: "/hotel-invoices", visible: vis("/hotel-invoices") },
          { id: "payments", title: "Payments", icon: CreditCard, href: "/hotel-payments", visible: vis("/hotel-payments") },
        ],
      },
      {
        key: "money",
        label: "Money",
        items: [
          { id: "expenses",      title: "Expenses",      icon: DollarSign, href: "/hotel-expenses",      visible: vis("/hotel-expenses") },
          { id: "cash-accounts", title: "Cash Accounts", icon: Wallet,     href: "/hotel-cash-accounts", visible: vis("/hotel-cash-accounts") },
          { id: "payroll",       title: "Payroll",       icon: Wallet,     href: "/hotel-payroll",       visible: vis("/hotel-payroll") },
        ],
      },
    ],

    restaurant: [
      {
        key: "restaurant",
        label: "Restaurant & Bar",
        items: [
          { id: "restaurant",       title: "Orders",           icon: ShoppingCart,      href: "/hotel-restaurant",       visible: vis("/hotel-restaurant") },
          { id: "menu",             title: "Menu",             icon: UtensilsCrossed,   href: "/hotel-menu",             visible: vis("/hotel-menu") },
          { id: "kitchen",          title: "Kitchen",          icon: UtensilsCrossed,   href: "/hotel-kitchen",          visible: vis("/hotel-kitchen") },
          { id: "restaurant-tables", title: "Tables",          icon: Building2,         href: "/hotel-restaurant-tables", visible: vis("/hotel-restaurant-tables") },
        ],
      },
    ],

    reports: [],

    setup: [
      {
        key: "hotel-config",
        label: "Hotel",
        items: [
          { id: "setup", title: "Hotel Setup", icon: Settings, href: "/hotel-setup", visible: vis("/hotel-setup") },
        ],
      },
      {
        key: "people",
        label: "People",
        items: [
          { id: "staff",     title: "Staff",               icon: Users2,  href: "/hotel-staff", visible: vis("/hotel-staff") },
          { id: "employees", title: "Users & Permissions", icon: UserCog, href: "/employees",   visible: isAdmin || featureAccess.canSeeEmployees },
        ],
      },
      {
        key: "facilities",
        label: "Facilities",
        items: [
          { id: "inventory",   title: "Supplies",    icon: Boxes,  href: "/hotel-inventory",   visible: vis("/hotel-inventory") },
          { id: "maintenance", title: "Maintenance", icon: Wrench, href: "/hotel-maintenance", visible: vis("/hotel-maintenance") },
        ],
      },
    ],

    system: [
      {
        key: "system",
        label: "Your account",
        items: [
          { id: "profile",   title: "Account",   icon: User,     href: "/profile", visible: false },
          { id: "companies", title: "Companies", icon: Building2, href: "/companies" },
        ],
      },
    ],
  }
}
