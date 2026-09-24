/**
 * Restaurant desktop top-nav contents.
 *
 * Rail: Dashboard | POS | Orders & Kitchen | Dining | Delivery & Online |
 *       Inventory | Money | Expenses | Reports | Growth | Setup -> System
 *
 * Money and Expenses are separate menus, the way Poultry and Water keep them:
 * Money is where cash sits and moves (tills, accounts, transfers, owner money,
 * loans, closing, cash flow, P&L); Expenses is what the restaurant spends on.
 */

import {
  Activity, ArrowLeftRight, BarChart3, Bell, Boxes, Building2, Calculator, CalendarCheck, CalendarDays, ClipboardList,
  Landmark, PiggyBank, TrendingUp, Wallet, Scale, FileBarChart, Banknote, HandCoins,
  CreditCard, Crown, DollarSign, FileText, Gift, Globe, Heart, Inbox, MapPin,
  Megaphone, Package, PartyPopper, QrCode, Receipt, Settings, ShoppingBag,
  ShoppingCart, Star, Tag, Truck, User, UserCog, Users, UtensilsCrossed,
} from "lucide-react"
import type { MegaMenuGroup, NavGroup } from "./nav-model"

export interface RestaurantNavConfig {
  ordersKitchen: MegaMenuGroup[]
  dining: MegaMenuGroup[]
  deliveryOnline: MegaMenuGroup[]
  /** Inventory only. The name is kept because the top nav and mobile nav read it. */
  inventoryReports: MegaMenuGroup[]
  money: MegaMenuGroup[]
  expenses: MegaMenuGroup[]
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

export function buildRestaurantNavConfig(badges: RestaurantNavBadges = {}): RestaurantNavConfig {
  return {
    ordersKitchen: [
      {
        key: "orders",
        label: "Orders",
        items: [
          { id: "pos",    title: "POS / New Order", icon: ShoppingCart,  href: "/restaurant-pos",    visible: true },
          // Guest QR orders wait here for staff to accept them before the kitchen sees them.
          { id: "pending", title: "New Guest Orders", icon: Inbox,        href: "/restaurant-pending-orders", visible: true,
            badge: badges.pendingGuestOrders },
          { id: "orders", title: "All Orders",      icon: ClipboardList, href: "/restaurant-orders", visible: true,
            badge: badges.unseenOnlineOrders },
        ],
      },
      {
        key: "kitchen",
        label: "Kitchen",
        items: [
          { id: "kds", title: "Kitchen Display", icon: Activity, href: "/restaurant-kds", visible: true },
        ],
      },
    ],

    dining: [
      {
        key: "floor",
        label: "Floor & Tables",
        items: [
          { id: "floor-plan",   title: "Restaurant Areas",    icon: MapPin,       href: "/restaurant-floor-plan",   visible: true },
          { id: "reservations", title: "Reservations & Waitlist", icon: CalendarDays, href: "/restaurant-reservations", visible: true },
        ],
      },
    ],

    deliveryOnline: [
      {
        key: "online",
        label: "Online Ordering",
        items: [
          { id: "online-settings", title: "Online Settings",     icon: Globe,  href: "/restaurant-online-orders", visible: true },
          { id: "qr-ordering",     title: "QR / Customer Order", icon: QrCode, href: "/restaurant-order-online",  visible: true },
        ],
      },
      {
        key: "delivery",
        label: "Delivery",
        items: [
          { id: "delivery", title: "Drivers & Dispatch", icon: Truck, href: "/restaurant-delivery", visible: true },
        ],
      },
    ],

    inventoryReports: [
      {
        key: "inventory",
        label: "Inventory",
        items: [
          { id: "ingredients", title: "Ingredients & Stock", icon: Boxes,     href: "/restaurant-inventory", visible: true },
        ],
      },
    ],

    // Migrations 323 / 324: every screen here reads or posts to the one cash
    // ledger. Tills first — it is the one cashiers use every shift.
    money: [
      {
        key: "cash",
        label: "Tills & Cash",
        items: [
          { id: "tills",          title: "Tills & Shifts",   icon: Calculator,     href: "/restaurant-tills",               visible: true },
          { id: "cash-accounts",  title: "Cash Accounts",    icon: Wallet,         href: "/restaurant-cash-accounts",       visible: true },
          { id: "cash-transfers", title: "Cash Transfers",   icon: ArrowLeftRight, href: "/restaurant-cash-transfers",      visible: true },
          { id: "reconciliation", title: "Reconciliation",   icon: Scale,          href: "/restaurant-cash-reconciliation", visible: true },
          { id: "daily-closing",  title: "Daily Closing",    icon: CalendarCheck,  href: "/restaurant-daily-closing",       visible: true },
        ],
      },
      {
        key: "funding",
        label: "Owner & Loans",
        items: [
          { id: "owner-money",    title: "Owner Money",      icon: PiggyBank,      href: "/restaurant-owner-money",         visible: true },
          { id: "loans",          title: "Loans",            icon: Landmark,       href: "/restaurant-loans",               visible: true },
        ],
      },
      {
        // Migration 326. Staff loans are money LENT TO staff; "Loans" above is
        // money the restaurant borrowed.
        key: "payroll",
        label: "Payroll & Staff",
        items: [
          { id: "payroll",        title: "Payroll",          icon: Banknote,       href: "/restaurant-payroll",             visible: true },
          { id: "staff-loans",    title: "Staff Loans & Advances", icon: HandCoins, href: "/restaurant-staff-loans",        visible: true },
        ],
      },
      {
        key: "statements",
        label: "Statements",
        items: [
          { id: "cash-flow",      title: "Cash Flow",         icon: Activity,     href: "/restaurant-cash-flow",           visible: true },
          { id: "profit-loss",    title: "Profit & Loss",     icon: TrendingUp,   href: "/restaurant-profit-loss",         visible: true },
          { id: "income",         title: "Income & Expenses", icon: DollarSign,   href: "/restaurant-payments",            visible: true },
          { id: "profit-vs-cash", title: "Profit vs Cash",    icon: FileBarChart, href: "/restaurant-reports/profit-vs-cash", visible: true },
        ],
      },
    ],

    // What the restaurant spends on — kept apart from Money, as in Poultry/Water.
    expenses: [
      {
        key: "expenses",
        label: "Expenses",
        items: [
          { id: "expenses",       title: "Record Expenses",     icon: Receipt,      href: "/restaurant-expenses",               visible: true },
          { id: "expense-cats",   title: "Expense Categories",  icon: Tag,          href: "/restaurant-expenses?tab=categories", visible: true },
          { id: "expense-report", title: "Expense Report",      icon: FileBarChart, href: "/restaurant-reports/expenses",       visible: true },
        ],
      },
    ],

    growth: [
      {
        key: "customers",
        label: "Customers",
        items: [
          { id: "crm",     title: "Customers & CRM",   icon: Heart, href: "/restaurant-crm",     visible: true },
          { id: "loyalty",  title: "Loyalty & Rewards", icon: Crown, href: "/restaurant-loyalty",  visible: true },
        ],
      },
      {
        key: "more",
        label: "More",
        items: [
          { id: "events",    title: "Events & Catering", icon: PartyPopper, href: "/restaurant-events",      visible: true },
          { id: "giftcards", title: "Gift Cards",        icon: Gift,        href: "/restaurant-gift-cards",   visible: true },
          { id: "notifs",    title: "Notifications",     icon: Bell,        href: "/restaurant-notifications", visible: true },
        ],
      },
    ],

    setup: [
      {
        key: "menu",
        label: "Menu & Staff",
        items: [
          { id: "menu-items", title: "Menu Items",       icon: UtensilsCrossed, href: "/restaurant-menu",   visible: true },
          { id: "staff",      title: "Staff & Roles",    icon: UserCog,         href: "/restaurant-staff",  visible: true },
          { id: "setup",      title: "Restaurant Setup",  icon: Settings,        href: "/restaurant-setup",  visible: true },
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
          { id: "billing",   title: "Billing",    icon: CreditCard, href: "/billing",   visible: true },
        ],
      },
    ],
  }
}
