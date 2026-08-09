/**
 * Poultry desktop top-nav contents.
 *
 * Same treatment as lib/nav/water-nav-config.ts: nine narrow dropdowns collapse
 * into a handful of wide grouped panels, so related things sit side by side
 * instead of being spread across menus that all look alike.
 *
 * Rail: Dashboard | Quick Links | Operations | Sales & Money | Analytics |
 *       Reports | Setup                                        -> System
 *
 * NOTE: components/dashboard/sidebar.tsx and mobile-bottom-nav.tsx still carry
 * their own copies of the poultry nav. Changing an item here does NOT change
 * them.
 */

import {
  Activity, AlertTriangle, Banknote, BarChart3, Bell, Bird, BookOpen, Box, Boxes,
  Building2, Clock, CreditCard, DollarSign, Egg, Factory, FileText, HelpCircle,
  ListTodo, Package, Pill, Settings, ShoppingCart, Truck, User, UserCog, Users,
  Users2, Wallet, Wheat,
} from "lucide-react"
import type { UserPermissions } from "@/hooks/use-permissions"
import { isFinancialNavItemVisible } from "@/lib/utils/financial-nav-access"
import type { MegaMenuGroup, NavGroup } from "./nav-model"

export interface PoultryNavDeps {
  permissions: UserPermissions
  /** Opens the alerts drawer (useAlertsStore.open). */
  onOpenAlerts: () => void
  alertCount?: number
}

export interface PoultryNavConfig {
  /** Stays a narrow single-column dropdown — it's a 3-item shortcut bar. */
  quickLinks: NavGroup
  operations: MegaMenuGroup[]
  salesMoney: MegaMenuGroup[]
  analytics: MegaMenuGroup[]
  setup: MegaMenuGroup[]
  /** Right-hand panel. Mirrors the sidebar's bottom "System" group. */
  system: MegaMenuGroup[]
}

export function buildPoultryNavConfig(
  { permissions, onOpenAlerts, alertCount }: PoultryNavDeps,
): PoultryNavConfig {
  const { featureAccess, isAdmin } = permissions
  const canSeeStaff = isAdmin || featureAccess.canSeeEmployees

  // The financial allow-list is default-deny and keyed on href, so it has to
  // follow each row wherever it lands. tempShowPayments matches what the
  // sidebar passes — the old top nav omitted it, which hid /billing here while
  // showing it in the sidebar for the same user.
  const money = (href: string) =>
    isFinancialNavItemVisible(href, featureAccess, isAdmin, { tempShowPayments: true })

  return {
    quickLinks: {
      label: "Quick Links",
      items: [
        { href: "/poultry-daily-closing", label: "Daily Closing",      icon: FileText },
        { href: "/production-records",    label: "Production Records", icon: Factory },
        { href: "/sales",                 label: "Sales",              icon: ShoppingCart },
      ],
    },

    operations: [
      {
        key: "production",
        label: "Production",
        items: [
          { id: "production-records", title: "Production Records", icon: FileText, href: "/production-records" },
          { id: "batch-production",   title: "Batch Production",   icon: Boxes,    href: "/batch-production-records" },
          { id: "egg-sorting",        title: "Egg sorting",        icon: Egg,      href: "/egg-production" },
          { id: "feed-usage",         title: "Feed Usage",         icon: Package,  href: "/feed-usage" },
          // Producing finished feed from ingredients is a production activity.
          // The formula behind it is a recipe you maintain, so it lives in
          // Setup > Production with Products.
          { id: "feed-production", title: "Feed Production", icon: Factory, href: "/poultry-feed-production", visible: featureAccess.canViewFeedProduction },
        ],
      },
      // Group ORDER is load-bearing in the 2x2 grid: each row is as tall as its
      // tallest group, so pairing the two long groups (Production 5, Inventory
      // 7) in row 1 and the two short ones (Farm 3, Delivery 2) in row 2 makes
      // the panel 10 rows instead of 12 — enough to clear max-h-[70vh] without
      // scrolling. Reordering these will bring the scrollbar back.
      {
        key: "inventory-health",
        label: "Inventory & Health",
        items: [
          { id: "inventory",      title: "Inventory",                 icon: Boxes,         href: "/poultry-inventory" },
          { id: "stock",          title: "Stock movements",           icon: Boxes,         href: "/poultry-stock" },
          { id: "raw-materials",  title: "Raw Materials & Supplies",  icon: Box,           href: "/poultry-raw-materials" },
          { id: "supplies",       title: "Supplies",                  icon: ShoppingCart,  href: "/supplies" },
          { id: "health",         title: "Health Records",            icon: AlertTriangle, href: "/health" },
          { id: "loss-records",   title: "Loss & Damage",             icon: AlertTriangle, href: "/poultry-loss-records" },
          { id: "other-inventory", title: "Other Inventory",          icon: Package,       href: "/inventory" },
        ],
      },
      {
        key: "farm",
        label: "Farm",
        items: [
          { id: "flock-batch", title: "Flock Purchases (Batches)",   icon: Boxes,     href: "/flock-batch" },
          { id: "flocks",      title: "Flock Groups (Pens / Flocks)", icon: Bird,      href: "/flocks" },
          { id: "houses",      title: "Houses",                       icon: Building2, href: "/houses" },
        ],
      },
      {
        key: "delivery",
        label: "Delivery",
        items: [
          // Drivers, Vehicles and Routes are fleet records you maintain — they
          // live in Setup > Fleet. What's left here is the daily run and its
          // reconciliation.
          { id: "deliveries",    title: "Deliveries",    icon: Truck,     href: "/poultry-driver-returns" },
          { id: "driver-report", title: "Driver report", icon: BarChart3, href: "/poultry-driver-report" },
        ],
      },
    ],

    salesMoney: [
      {
        key: "sales",
        label: "Sales",
        items: [
          { id: "sales",    title: "Sales",             icon: ShoppingCart, href: "/sales",            visible: money("/sales") },
          { id: "payments", title: "Payments received", icon: Wallet,       href: "/poultry-payments", visible: money("/poultry-payments") },
          { id: "billing",  title: "Billing",           icon: CreditCard,   href: "/billing",          visible: money("/billing") },
        ],
      },
      {
        key: "money",
        label: "Money",
        items: [
          { id: "cash",          title: "Cash",         icon: Wallet,     href: "/cash",                   visible: money("/cash") },
          { id: "cash-accounts", title: "Cash Account", icon: Wallet,     href: "/poultry-cash-accounts",  visible: money("/poultry-cash-accounts") },
          { id: "expenses",      title: "Expenses",     icon: DollarSign, href: "/expenses",               visible: money("/expenses") },
          // Payroll is money going out, so it sits with the other outflows
          // rather than with staff master data in Setup > People. It is also the
          // one ungated row here, which keeps this column from ever vanishing.
          { id: "payroll",       title: "Payroll",      icon: Banknote,   href: "/poultry-payroll" },
        ],
      },
    ],

    analytics: [
      {
        key: "trackers",
        label: "Trackers",
        items: [
          { id: "egg-tracker",        title: "Egg tracker",        icon: BarChart3, href: "/egg-tracker" },
          { id: "feed-tracker",       title: "Feed tracker",       icon: Wheat,     href: "/feed-tracker" },
          { id: "medication-tracker", title: "Medication tracker", icon: Pill,      href: "/medication-tracker" },
          { id: "birds-left",         title: "Birds left tracker", icon: Bird,      href: "/birds-left-tracker" },
          { id: "weekly-report",      title: "Analytical Report",  icon: FileText,  href: "/weekly-report" },
        ],
      },
    ],

    setup: [
      {
        key: "company",
        label: "Company",
        items: [
          { id: "settings",   title: "Settings",  icon: Settings,  href: "/settings",  visible: featureAccess.canViewSettings },
          // Customers and Suppliers are master data maintained here, not part of
          // the day's selling flow — same call as the water rail.
          { id: "customers",  title: "Customers", icon: Users,     href: "/customers", visible: money("/customers") },
          { id: "suppliers",  title: "Suppliers", icon: Truck,     href: "/suppliers", visible: money("/suppliers") },
          // Ungated, so this column (and the Setup trigger) always renders.
          { id: "companies",  title: "Companies", icon: Building2, href: "/companies" },
        ],
      },
      {
        key: "production-setup",
        label: "Production",
        items: [
          // Products is ungated, which keeps this column — and the Setup
          // trigger — from ever disappearing.
          { id: "products",      title: "Products",      icon: Package, href: "/poultry-products" },
          { id: "feed-formulas", title: "Feed Formulas", icon: Wheat,   href: "/poultry-feed-formulas", visible: featureAccess.canViewFeedProduction },
          // A farm-level schedule that production records key off, so it sits
          // with the other production master data rather than under Company.
          { id: "egg-picks",     title: "Egg Pick Times", icon: Clock,  href: "/business-office/egg-pick-settings", visible: isAdmin },
        ],
      },
      {
        key: "fleet",
        label: "Fleet",
        items: [
          { id: "drivers",  title: "Drivers",  icon: Users2, href: "/poultry-drivers" },
          { id: "vehicles", title: "Vehicles", icon: Truck,  href: "/poultry-vehicles" },
          { id: "routes",   title: "Routes",   icon: Truck,  href: "/poultry-routes" },
        ],
      },
      {
        key: "people",
        label: "People",
        items: [
          { id: "staff",     title: "Staff",               icon: Users2,  href: "/poultry-staff", visible: canSeeStaff },
          { id: "employees", title: "Users & Permissions", icon: UserCog, href: "/employees",     visible: canSeeStaff },
        ],
      },
    ],

    system: [
      {
        key: "system",
        label: "Your account",
        items: [
          // Hidden to match the water rail — the header avatar still opens
          // /profile. Flip `visible` to bring the row back.
          { id: "profile",     title: "Account",             icon: User,       href: "/profile", visible: false },
          { id: "alerts",      title: "Alerts",              icon: Bell,       onClick: onOpenAlerts, badge: alertCount },
          { id: "audit-logs",  title: "Activity Log",        icon: Activity,   href: "/audit-logs", visible: featureAccess.canViewActivityLog },
          { id: "resources",   title: "Resources",           icon: BookOpen,   href: "/resources" },
          { id: "help",        title: "Help Center",         icon: HelpCircle, href: "/help" },
          { id: "terms",       title: "Terms & Conditions",  icon: ListTodo,   href: "/terms" },
        ],
      },
    ],
  }
}
