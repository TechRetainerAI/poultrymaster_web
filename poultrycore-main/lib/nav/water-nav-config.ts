/**
 * Water desktop top-nav contents.
 *
 * The rail is deliberately short — Dashboard, Quick Links, and four grouped
 * panels — because nine near-identical narrow dropdowns made users hunt for
 * items. Related things now sit side by side inside one wide panel, the way the
 * Reports menu already worked.
 *
 * A builder taking deps (rather than a bare const) so the sidebar can adopt it
 * later: the signature spells out exactly what a consumer has to supply.
 *
 * NOTE: components/dashboard/sidebar.tsx and mobile-bottom-nav.tsx still carry
 * their own copies of the water nav. Changing an item here does NOT change them.
 */

import {
  Activity, AlertTriangle, Banknote, BarChart3, Bell, Boxes, Box, Building2,
  CalendarDays, Cog, CreditCard, Droplets, FileText, Factory, ListTodo, Receipt,
  Route as RouteIcon, Settings, ShoppingBag, ShoppingCart, Truck, User, UserCog,
  Users, Users2, Wallet, Wrench,
} from "lucide-react"
import type { UserPermissions } from "@/hooks/use-permissions"
import type { MegaMenuGroup, NavGroup } from "./nav-model"

export interface WaterNavDeps {
  permissions: UserPermissions
  /** Opens the alerts drawer (useAlertsStore.open). */
  onOpenAlerts: () => void
  /** Badge count on the Alerts row. Currently always 0 — nothing in the app
   *  calls useAlertsStore.setAlerts yet, and only the poultry dashboard mounts
   *  the dialog, so on water pages this row opens nothing for the moment. */
  alertCount?: number
}

export interface WaterNavConfig {
  /** Stays a narrow single-column dropdown — it's a 4-item shortcut bar. */
  quickLinks: NavGroup
  operations: MegaMenuGroup[]
  salesMoney: MegaMenuGroup[]
  setup: MegaMenuGroup[]
  /** Right-hand panel. Mirrors the sidebar's bottom "System" block. */
  system: MegaMenuGroup[]
}

export function buildWaterNavConfig({ permissions, onOpenAlerts, alertCount }: WaterNavDeps): WaterNavConfig {
  // Same predicates the sidebar uses, so the two surfaces can't disagree about
  // who sees what. The top nav previously applied no gating at all.
  const canSeeStaff = permissions.isAdmin || permissions.featureAccess.canSeeEmployees
  const canSeeActivityLog = permissions.featureAccess.canViewActivityLog

  return {
    quickLinks: {
      label: "Quick Links",
      items: [
        { href: "/water-daily-closing",      label: "Daily Closing", icon: FileText },
        { href: "/water-driver-returns",     label: "Deliveries",    icon: Truck },
        // Same label as Operations > Production > Water Production — one page,
        // one name, so the two menus can't look like two destinations.
        { href: "/water-production-batches", label: "Water Production", icon: Factory },
        { href: "/water-sales",              label: "Sales",         icon: ShoppingCart },
      ],
    },

    operations: [
      // Production leads — it's the core of the business, and the panel reads
      // make-it -> move-it -> count-it left to right.
      {
        key: "production",
        label: "Production",
        color: "bg-indigo-600",
        items: [
          // "Water Production", not "Production": a row called Production
          // inside a column called Production tells the user nothing.
          { id: "production",       title: "Water Production", icon: Factory,      href: "/water-production-batches" },
          { id: "batch-production", title: "Batch Production", icon: CalendarDays, href: "/water-daily-production" },
          // Products, Machines and Boreholes are NOT here — they're records you
          // maintain, not things you run. All three live in Setup > Production.
          { id: "maintenance",      title: "Maintenance",      icon: Wrench,       href: "/water-maintenance" },
        ],
      },
      {
        key: "delivery",
        label: "Delivery",
        color: "bg-rose-600",
        items: [
          { id: "deliveries",    title: "Deliveries",              icon: Truck,      href: "/water-driver-returns" },
          { id: "drivers",       title: "Drivers",                 icon: Users2,     href: "/water-drivers" },
          { id: "vehicles",      title: "Vehicles",                icon: Truck,      href: "/water-vehicles" },
          { id: "routes",        title: "Routes",                  icon: RouteIcon,  href: "/water-routes" },
          // Was filed under Admin/Setup, which is not where anyone looks for a
          // delivery artifact. Poultry already files its equivalent here.
          { id: "driver-report", title: "Driver collection report", icon: BarChart3, href: "/water-driver-report" },
        ],
      },
      {
        key: "inventory",
        label: "Inventory",
        color: "bg-amber-600",
        items: [
          { id: "stock",             title: "Stock movement",            icon: Boxes,         href: "/water-stock" },
          { id: "inventory",         title: "Inventory",                 icon: Boxes,         href: "/water-inventory" },
          { id: "raw-materials",     title: "Raw materials & supplies",  icon: Box,           href: "/water-raw-materials" },
          { id: "loss-records",      title: "Damages & loss",            icon: AlertTriangle, href: "/water-loss-records" },
          { id: "production-losses", title: "Production losses",         icon: AlertTriangle, href: "/water-production-losses" },
        ],
      },
    ],

    salesMoney: [
      {
        key: "sales",
        label: "Sales",
        color: "bg-sky-600",
        items: [
          { id: "sales",    title: "Sales",    icon: ShoppingCart, href: "/water-sales" },
          { id: "payments", title: "Payments", icon: CreditCard,   href: "/water-payments" },
        ],
      },
      {
        key: "money",
        label: "Money",
        color: "bg-emerald-600",
        items: [
          { id: "expenses",      title: "Expenses",        icon: Receipt,  href: "/water-expenses" },
          { id: "cash-accounts", title: "Cash accounts",   icon: Wallet,   href: "/water-cash-accounts" },
          // Payroll is money going out, so it sits with the other outflows
          // rather than with the staff master data in Setup > People.
          { id: "payroll",       title: "Payroll",         icon: Banknote, href: "/water-payroll" },
        ],
      },
    ],

    setup: [
      {
        key: "company",
        label: "Company",
        color: "bg-slate-600",
        items: [
          { id: "setup",         title: "Setup",         icon: Settings,  href: "/water-setup" },
          { id: "company-setup", title: "Company Setup", icon: Settings,  href: "/water-company-setup" },
          // Customers sits beside Suppliers: both are master data maintained
          // here, not part of the day's selling flow.
          { id: "customers",     title: "Customers",     icon: Users,     href: "/water-customers" },
          { id: "suppliers",     title: "Suppliers",     icon: Truck,     href: "/water-suppliers" },
          { id: "companies",     title: "Companies",     icon: Building2, href: "/companies" },
        ],
      },
      {
        key: "production-setup",
        label: "Production",
        color: "bg-indigo-600",
        items: [
          { id: "products",  title: "Products",  icon: ShoppingBag, href: "/water-products" },
          { id: "machines",  title: "Machines",  icon: Cog,         href: "/water-machines" },
          { id: "boreholes", title: "Boreholes", icon: Droplets,    href: "/water-boreholes" },
        ],
      },
      {
        key: "people",
        label: "People",
        color: "bg-violet-600",
        // Both rows share one gate now that Payroll has moved to Sales & Money,
        // so for a staff user without canSeeEmployees the whole column drops
        // out. That's safe — Company and Production are ungated, so the Setup
        // trigger itself can never disappear and the rail can't reflow.
        items: [
          { id: "staff",     title: "Staff",               icon: UserCog, href: "/water-staff", visible: canSeeStaff },
          { id: "employees", title: "Users & Permissions", icon: UserCog, href: "/employees",   visible: canSeeStaff },
        ],
      },
    ],

    // The sidebar's bottom "System" block: the user's own context, kept on the
    // right of the rail. These rows live ONLY here — Setup is company
    // configuration, System is you. Companies belongs to Setup > Company, not
    // here, because it is a company-level thing.
    system: [
      {
        key: "system",
        label: "Your account",
        color: "bg-slate-500",
        items: [
          // Hidden for now (2026-08-07) — flip `visible` back to restore it,
          // and put "account" back in the System blurb in top-nav.tsx.
          { id: "profile",    title: "Account",            icon: User,     href: "/profile", visible: false },
          { id: "alerts",     title: "Alerts",             icon: Bell,     onClick: onOpenAlerts, badge: alertCount },
          { id: "audit-logs", title: "Activity Log",       icon: Activity, href: "/audit-logs", visible: canSeeActivityLog },
          { id: "terms",      title: "Terms & Conditions", icon: ListTodo, href: "/terms" },
        ],
      },
    ],
  }
}
