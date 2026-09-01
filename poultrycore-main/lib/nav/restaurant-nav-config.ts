/**
 * Restaurant desktop top-nav contents.
 *
 * Rail: Dashboard | POS | Orders & Kitchen | Dining | Delivery & Online |
 *       Inventory & Reports | Growth | Setup -> System
 */

import {
  Activity, BarChart3, Bell, Boxes, Building2, CalendarDays, ClipboardList,
  CreditCard, Crown, DollarSign, FileText, Gift, Globe, Heart, MapPin,
  Megaphone, Package, PartyPopper, QrCode, Receipt, Settings, ShoppingBag,
  ShoppingCart, Star, Tag, Truck, User, UserCog, Users, UtensilsCrossed,
} from "lucide-react"
import type { MegaMenuGroup, NavGroup } from "./nav-model"

export interface RestaurantNavConfig {
  ordersKitchen: MegaMenuGroup[]
  dining: MegaMenuGroup[]
  deliveryOnline: MegaMenuGroup[]
  inventoryReports: MegaMenuGroup[]
  growth: MegaMenuGroup[]
  setup: MegaMenuGroup[]
  system: MegaMenuGroup[]
}

export function buildRestaurantNavConfig(): RestaurantNavConfig {
  return {
    ordersKitchen: [
      {
        key: "orders",
        label: "Orders",
        items: [
          { id: "pos",    title: "POS / New Order", icon: ShoppingCart,  href: "/restaurant-pos",    visible: true },
          { id: "orders", title: "All Orders",      icon: ClipboardList, href: "/restaurant-orders", visible: true },
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
          { id: "floor-plan",   title: "Floor Plan & Tables", icon: MapPin,       href: "/restaurant-floor-plan",   visible: true },
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
          { id: "reports",     title: "Reports & Analytics", icon: BarChart3, href: "/restaurant-reports",   visible: true },
          { id: "expenses",    title: "Expenses",            icon: Receipt,   href: "/restaurant-expenses",  visible: true },
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
        ],
      },
    ],
  }
}
