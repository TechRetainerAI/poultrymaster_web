/**
 * Hotel desktop top-nav contents.
 *
 * Same treatment as poultry-nav-config.ts: flat links + a single "More"
 * dropdown collapse into grouped mega-menu panels.
 *
 * Rail: Dashboard | Quick Links | Operations | Sales, Expenses & Money |
 *       Restaurant | Reports | Setup                             -> System
 *
 * "Sales, Expenses & Money" is the Poultry menu of the same name, copied word
 * for word (lib/nav/poultry-nav-config.ts salesMoney): same three columns, same
 * labels, same order, same icons. Rows whose Hotel page does not exist yet are
 * left out rather than pointed somewhere else, and are added in the reference
 * position as each page is built. Customers and Suppliers are master records,
 * so -- as in Poultry -- they sit in Setup > Finance.
 */

import {
  Activity, ArrowLeftRight, Banknote, Bell, Boxes, Building2, CalendarSearch, ClipboardCheck, CreditCard,
  DollarSign, FileText, HandCoins, Hourglass, MessageSquare, Package, PackageMinus, Receipt, ScrollText, Search, Settings, Shield, ShoppingCart,
  Scale, TrendingUp, Truck, User, UserCog, Users, Users2, UtensilsCrossed, Wallet, Wrench,
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
          // The folio desk (add charges, take a payment, generate the invoice).
          // It was the "Sales" row until 332 gave Sales its own list.
          { id: "billing",   title: "Billing",      icon: Receipt,    href: "/hotel-billing",     visible: vis("/hotel-billing") },
          // Moved here from the old Billing group: an invoice is issued from a
          // stay, beside the folio it is built from. The reference Sales column
          // has no Invoices row.
          { id: "invoices",  title: "Invoices",     icon: FileText,   href: "/hotel-invoices",    visible: vis("/hotel-invoices") },
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

    // Poultry's salesMoney, row for row. Labels and icons are copied exactly;
    // only the hrefs are the Hotel pages. A reference row with no Hotel page
    // yet is omitted and noted in place, so the order is kept when it is added.
    // Each row is gated on its OWN href now that hotel-nav-access.ts names
    // them; several used to borrow another page's rule, which the sidebar
    // could not copy.
    salesMoney: [
      {
        key: "sales",
        label: "Sales",
        items: [
          // What the hotel sold: stays (room nights + folio charges) and walk-in
          // restaurant orders, with Total / Paid / Balance (migration 332).
          { id: "sales",    title: "Sales",    icon: ShoppingCart, href: "/hotel-sales",    visible: vis("/hotel-sales") },
          { id: "payments", title: "Payments", icon: Wallet,       href: "/hotel-payments", visible: vis("/hotel-payments") },
          { id: "customer-balances", title: "Customer Balances", icon: Users, href: "/hotel-customer-balances", visible: vis("/hotel-customer-balances") },
        ],
      },
      {
        key: "expenses",
        label: "Expenses",
        items: [
          { id: "expenses",       title: "Expenses", icon: DollarSign, href: "/hotel-expenses", visible: vis("/hotel-expenses") },
          { id: "internal-use",   title: "Internal Use", icon: PackageMinus, href: "/hotel-internal-use", visible: vis("/hotel-internal-use") },
          { id: "payroll",        title: "Payroll",  icon: Banknote,   href: "/hotel-payroll",  visible: vis("/hotel-payroll") },
          // Moved here from Setup > People, to where Poultry has it: directly
          // below Payroll, because payroll deduction is how most advances are
          // repaid.
          { id: "employee-loans", title: "Employee Loans & Advances", icon: HandCoins, href: "/hotel-employee-loans", visible: vis("/hotel-employee-loans") },
          { id: "supplier-payments", title: "Supplier Payments", icon: Receipt, href: "/hotel-supplier-payments", visible: vis("/hotel-supplier-payments") },
          { id: "supplier-balances", title: "Supplier Balances", icon: Truck, href: "/hotel-supplier-balances", visible: vis("/hotel-supplier-balances") },
          { id: "deferred-costs", title: "Deferred inventory cost", icon: Hourglass, href: "/hotel-deferred-costs", visible: vis("/hotel-deferred-costs") },
          { id: "assets", title: "Capital Investments/Assets", icon: Building2, href: "/hotel-assets", visible: vis("/hotel-assets") },
        ],
      },
      {
        key: "money",
        label: "Money",
        items: [
          { id: "cash-flow",     title: "Cash Flow",     icon: Wallet,     href: "/hotel-cash-flow",     visible: vis("/hotel-cash-flow") },
          { id: "financial-activity", title: "Financial Activity", icon: Activity, href: "/hotel-financial-activity", visible: vis("/hotel-financial-activity") },
          { id: "profit-loss",   title: "Profit & Loss", icon: TrendingUp, href: "/hotel-profit-loss",   visible: vis("/hotel-profit-loss") },
          { id: "owner-money",   title: "Owner Money",   icon: Banknote,   href: "/hotel-owner-money",   visible: vis("/hotel-owner-money") },
          { id: "loans",         title: "Loans (Financing)", icon: HandCoins, href: "/hotel-loans",     visible: vis("/hotel-loans") },
          { id: "cash-accounts", title: "Cash Account",  icon: Wallet,     href: "/hotel-cash-accounts", visible: vis("/hotel-cash-accounts") },
          { id: "cash-transfers", title: "Cash Transfers", icon: ArrowLeftRight, href: "/hotel-cash-transfers", visible: vis("/hotel-cash-transfers") },
          { id: "cash-reconciliation", title: "Reconciliation", icon: Scale, href: "/hotel-cash-reconciliation", visible: vis("/hotel-cash-reconciliation") },
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
          { id: "company-setup", title: "Company Setup", icon: Building2, href: "/hotel-company-setup", visible: vis("/hotel-company-setup") },
          { id: "setup", title: "Hotel Setup", icon: Settings, href: "/hotel-setup", visible: vis("/hotel-setup") },
        ],
      },
      {
        key: "people",
        label: "People",
        items: [
          { id: "staff",          title: "Staff",               icon: Users2,  href: "/hotel-staff",          visible: vis("/hotel-staff") },
          { id: "employees",      title: "Users & Permissions", icon: UserCog, href: "/employees",            visible: isAdmin || featureAccess.canSeeEmployees },
        ],
      },
      {
        // As Poultry's Setup > Finance: the customers and suppliers that the
        // money pages are recorded against. Customer Payments is the corporate
        // (on-account) customers' payments page; it stays beside Customers
        // until Customer Balances is built.
        key: "finance",
        label: "Finance",
        items: [
          { id: "customers",         title: "Customers",         icon: Users,   href: "/hotel-customers",         visible: vis("/hotel-customers") },
          // Customer Payments (the Draft -> Approve page) left the menu in 332:
          // Payments and Customer Balances replace it. The route still works.
          { id: "suppliers",         title: "Suppliers",         icon: Truck,   href: "/hotel-suppliers",         visible: vis("/hotel-suppliers") },
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
          // The account's own subscription, not a guest's folio -- that is
          // /hotel-billing, which stays in the Billing group.
          { id: "billing",   title: "Billing",   icon: CreditCard, href: "/billing" },
        ],
      },
    ],
  }
}
