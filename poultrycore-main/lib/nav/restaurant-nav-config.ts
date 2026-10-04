/**
 * Restaurant desktop top-nav contents.
 *
 * Rail: Dashboard | POS | Quick Links | Orders & Kitchen | Dining |
 *       Delivery & Online | Inventory | Sales, Expenses & Money | Reports |
 *       Growth | Setup                                           -> System
 *
 * "Sales, Expenses & Money" is the Poultry menu of the same name, copied word
 * for word (lib/nav/poultry-nav-config.ts salesMoney): three columns split by
 * the direction of the money -- what comes IN, what goes OUT, and where the
 * cash itself sits. Same labels, same order, same icons. Rows whose Restaurant
 * page does not exist yet are left out rather than pointed somewhere else;
 * they are added as each page is built, in the reference position.
 *
 * Tills & Shifts and Daily Closing have no row in the reference menu -- Poultry
 * keeps Daily Closing in Quick Links -- so both sit in Quick Links here.
 */

import {
  Activity, ArrowLeftRight, Banknote, Boxes, Building2, Calculator, CalendarCheck, CalendarDays, ClipboardList,
  CreditCard, Crown, DollarSign, Gift, Globe, HandCoins, Heart, Hourglass, Inbox, MapPin, PackageMinus,
  PartyPopper, QrCode, Receipt, Scale, Settings, ShoppingCart, TrendingUp, Truck, User, UserCog, Users,
  UtensilsCrossed, Wallet, Bell,
} from "lucide-react"
import type { UserPermissions } from "@/hooks/use-permissions"
import { isRestaurantNavItemVisible } from "@/lib/utils/restaurant-nav-access"
import type { MegaMenuGroup, NavGroup, NavItem } from "./nav-model"

export interface RestaurantNavConfig {
  /** Stays a narrow single-column dropdown — a shortcut bar, not a menu. */
  quickLinks: NavGroup
  ordersKitchen: MegaMenuGroup[]
  dining: MegaMenuGroup[]
  deliveryOnline: MegaMenuGroup[]
  /** Inventory only. The name is kept because the top nav and mobile nav read it. */
  inventoryReports: MegaMenuGroup[]
  /** Three groups, keys sales / expenses / money, exactly as Poultry's. */
  salesMoney: MegaMenuGroup[]
  growth: MegaMenuGroup[]
  setup: MegaMenuGroup[]
  system: MegaMenuGroup[]
}

export interface RestaurantNavBadges {
  /** Online orders nobody has had on screen yet. See lib/utils/online-order-alerts.ts. */
  unseenOnlineOrders?: number
  /** Online orders still waiting to be accepted or rejected. */
  pendingGuestOrders?: number
}

export function buildRestaurantNavConfig(
  badges: RestaurantNavBadges = {},
  permissions?: UserPermissions,
): RestaurantNavConfig {
  // Every row is gated on its own href, through the same route -> flag map the
  // sidebar uses (lib/utils/restaurant-nav-access.ts). Before this the builder
  // took no permissions and hard-coded `visible: true`, so the desktop rail and
  // the mobile sheet showed every Money page to every staff member -- only the
  // sidebar filtered. With no permissions passed (a caller that has none) the
  // rows stay visible, which is what every caller got before.
  const vis = (href: string) =>
    permissions ? isRestaurantNavItemVisible(href, permissions.featureAccess, permissions.isAdmin) : true

  return {
    quickLinks: {
      label: "Quick Links",
      // Same rule as Poultry's Quick Links: a page the restaurant opens most
      // days, in the order the day happens -- take orders, open the till, record
      // what was spent, see where the money stands, then close the day.
      items: ([
        { href: "/restaurant-sales",         label: "Sales",          icon: ShoppingCart },
        { href: "/restaurant-tills",         label: "Tills & Shifts", icon: Calculator },
        { href: "/restaurant-expenses",      label: "Expenses",       icon: DollarSign },
        { href: "/restaurant-cash-flow",     label: "Cash Flow",      icon: Wallet },
        { href: "/restaurant-profit-loss",   label: "Profit & Loss",  icon: TrendingUp },
        { href: "/restaurant-daily-closing", label: "Daily Closing",  icon: CalendarCheck },
      ] as NavItem[]).filter((i) => vis(i.href)),
    },

    ordersKitchen: [
      {
        key: "orders",
        label: "Orders",
        items: [
          { id: "pos",    title: "POS / New Order", icon: ShoppingCart,  href: "/restaurant-pos",    visible: vis("/restaurant-pos") },
          // Guest QR orders wait here for staff to accept them before the kitchen sees them.
          { id: "pending", title: "New Guest Orders", icon: Inbox,        href: "/restaurant-pending-orders", visible: vis("/restaurant-pending-orders"),
            badge: badges.pendingGuestOrders },
          { id: "orders", title: "All Orders",      icon: ClipboardList, href: "/restaurant-orders", visible: vis("/restaurant-orders"),
            badge: badges.unseenOnlineOrders },
        ],
      },
      {
        key: "kitchen",
        label: "Kitchen",
        items: [
          { id: "kds", title: "Kitchen Display", icon: Activity, href: "/restaurant-kds", visible: vis("/restaurant-kds") },
        ],
      },
    ],

    dining: [
      {
        key: "floor",
        label: "Floor & Tables",
        items: [
          { id: "floor-plan",   title: "Restaurant Areas",    icon: MapPin,       href: "/restaurant-floor-plan",   visible: vis("/restaurant-floor-plan") },
          { id: "reservations", title: "Reservations & Waitlist", icon: CalendarDays, href: "/restaurant-reservations", visible: vis("/restaurant-reservations") },
        ],
      },
    ],

    deliveryOnline: [
      {
        key: "online",
        label: "Online Ordering",
        items: [
          { id: "online-settings", title: "Online Settings",     icon: Globe,  href: "/restaurant-online-orders", visible: vis("/restaurant-online-orders") },
          { id: "qr-ordering",     title: "QR / Customer Order", icon: QrCode, href: "/restaurant-order-online",  visible: vis("/restaurant-order-online") },
        ],
      },
      {
        key: "delivery",
        label: "Delivery",
        items: [
          { id: "delivery", title: "Drivers & Dispatch", icon: Truck, href: "/restaurant-delivery", visible: vis("/restaurant-delivery") },
        ],
      },
    ],

    inventoryReports: [
      {
        key: "inventory",
        label: "Inventory",
        items: [
          { id: "ingredients", title: "Ingredients & Stock", icon: Boxes,     href: "/restaurant-inventory", visible: vis("/restaurant-inventory") },
          // Migration 329: Poultry's "Record Purchase" row -- the same deep
          // link idea (?purchase=1 opens the dialog on the stock page).
          { id: "record-purchase", title: "Record Purchase", icon: ShoppingCart, href: "/restaurant-inventory?purchase=1", visible: vis("/restaurant-inventory") },
        ],
      },
    ],

    // Poultry's salesMoney, row for row. Labels and icons are copied exactly;
    // only the hrefs are the Restaurant pages. A reference row with no
    // Restaurant page yet is omitted and noted in place, so the order is kept
    // when it is added.
    salesMoney: [
      {
        key: "sales",
        label: "Sales",
        items: [
          // An order IS the restaurant's sale -- All Orders is where every one of
          // them is listed with what was paid.
          { id: "sales",    title: "Sales",             icon: ShoppingCart, href: "/restaurant-sales",  visible: vis("/restaurant-sales") },
          // Migration 333: Poultry's rows, titles, icons and gates.
          { id: "payments", title: "Payments",          icon: Wallet,       href: "/restaurant-payments", visible: vis("/restaurant-payments") },
          { id: "customer-balances", title: "Customer Balances", icon: Users, href: "/restaurant-customer-balances", visible: vis("/restaurant-customer-balances") },
        ],
      },
      {
        key: "expenses",
        label: "Expenses",
        items: [
          { id: "expenses",       title: "Expenses",     icon: DollarSign, href: "/restaurant-expenses", visible: vis("/restaurant-expenses") },
          // Migration 330. Poultry's row, title and icon.
          { id: "internal-use",   title: "Internal Use", icon: PackageMinus, href: "/restaurant-internal-use", visible: vis("/restaurant-internal-use") },
          { id: "payroll",        title: "Payroll",      icon: Banknote,   href: "/restaurant-payroll",  visible: vis("/restaurant-payroll") },
          // Migration 326. Money LENT TO staff; "Loans (Financing)" below is
          // money the restaurant borrowed.
          { id: "employee-loans", title: "Employee Loans & Advances", icon: HandCoins, href: "/restaurant-staff-loans", visible: vis("/restaurant-staff-loans") },
          // Migration 329: Poultry's three rows, same titles, icons and gates.
          { id: "supplier-payments", title: "Supplier Payments", icon: Receipt, href: "/restaurant-supplier-payments", visible: vis("/restaurant-supplier-payments") },
          { id: "supplier-balances", title: "Supplier Balances", icon: Truck, href: "/restaurant-supplier-balances", visible: vis("/restaurant-supplier-balances") },
          { id: "deferred-inventory-costs", title: "Deferred inventory cost", icon: Hourglass, href: "/restaurant-deferred-costs", visible: vis("/restaurant-deferred-costs") },
          // Migration 328. Poultry's last Expenses row, same title and icon.
          { id: "assets", title: "Capital Investments/Assets", icon: Building2, href: "/restaurant-assets", visible: vis("/restaurant-assets") },
        ],
      },
      {
        key: "money",
        label: "Money",
        items: [
          { id: "cash-flow",      title: "Cash Flow",      icon: Wallet,     href: "/restaurant-cash-flow",   visible: vis("/restaurant-cash-flow") },
          // Migration 335: Poultry's row, title, icon and gate.
          { id: "financial-activity", title: "Financial Activity", icon: Activity, href: "/restaurant-financial-activity", visible: vis("/restaurant-financial-activity") },
          { id: "profit-loss",    title: "Profit & Loss",  icon: TrendingUp, href: "/restaurant-profit-loss", visible: vis("/restaurant-profit-loss") },
          { id: "owner-money",    title: "Owner Money",    icon: Banknote,   href: "/restaurant-owner-money", visible: vis("/restaurant-owner-money") },
          { id: "loans",          title: "Loans (Financing)", icon: HandCoins, href: "/restaurant-loans",     visible: vis("/restaurant-loans") },
          { id: "cash-accounts",  title: "Cash Account",   icon: Wallet,     href: "/restaurant-cash-accounts", visible: vis("/restaurant-cash-accounts") },
          { id: "cash-transfers", title: "Cash Transfers", icon: ArrowLeftRight, href: "/restaurant-cash-transfers", visible: vis("/restaurant-cash-transfers") },
          { id: "cash-reconciliation", title: "Reconciliation", icon: Scale, href: "/restaurant-cash-reconciliation", visible: vis("/restaurant-cash-reconciliation") },
        ],
      },
    ],

    growth: [
      {
        key: "customers",
        label: "Customers",
        items: [
          { id: "crm",     title: "Customers & CRM",   icon: Heart, href: "/restaurant-crm",     visible: vis("/restaurant-crm") },
          { id: "loyalty",  title: "Loyalty & Rewards", icon: Crown, href: "/restaurant-loyalty",  visible: vis("/restaurant-loyalty") },
        ],
      },
      {
        key: "more",
        label: "More",
        items: [
          { id: "events",    title: "Events & Catering", icon: PartyPopper, href: "/restaurant-events",      visible: vis("/restaurant-events") },
          { id: "giftcards", title: "Gift Cards",        icon: Gift,        href: "/restaurant-gift-cards",   visible: vis("/restaurant-gift-cards") },
          { id: "notifs",    title: "Notifications",     icon: Bell,        href: "/restaurant-notifications", visible: vis("/restaurant-notifications") },
        ],
      },
    ],

    setup: [
      {
        key: "menu",
        label: "Menu & Staff",
        items: [
          { id: "menu-items", title: "Menu Items",       icon: UtensilsCrossed, href: "/restaurant-menu",   visible: vis("/restaurant-menu") },
          // "Staff", as in Poultry's Setup > People.
          { id: "staff",      title: "Staff",            icon: UserCog,         href: "/restaurant-staff",  visible: vis("/restaurant-staff") },
          { id: "setup",      title: "Restaurant Setup",  icon: Settings,        href: "/restaurant-setup",  visible: vis("/restaurant-setup") },
        ],
      },
      {
        // Poultry's Setup > Finance group (migration 329): suppliers are master
        // data every purchase, expense payable and supplier payment hangs off.
        key: "finance",
        label: "Finance",
        items: [
          { id: "suppliers", title: "Suppliers", icon: Truck, href: "/restaurant-suppliers", visible: vis("/restaurant-suppliers") },
        ],
      },
    ],

    system: [
      {
        key: "account",
        label: "Account",
        items: [
          { id: "profile",   title: "My Account", icon: User,      href: "/profile",   visible: true },
          { id: "companies", title: "Companies",  icon: Building2,  href: "/companies", visible: true },
          // The account's own subscription.
          { id: "billing",   title: "Billing",    icon: CreditCard, href: "/business-office/billing",   visible: true },
        ],
      },
    ],
  }
}
