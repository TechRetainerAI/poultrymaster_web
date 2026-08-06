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
  Activity, AlertTriangle, Banknote, BarChart3, Boxes, Box, Briefcase, Building2,
  CalendarDays, Cog, CreditCard, Droplets, FileText, Factory, ListTodo, Receipt,
  Route as RouteIcon, Settings, ShoppingBag, ShoppingCart, Truck, User, UserCog,
  Users, Users2, Wallet, Wrench,
} from "lucide-react"
import type { UserPermissions } from "@/hooks/use-permissions"
import type { MegaMenuGroup, NavGroup } from "./nav-model"

export interface WaterNavDeps {
  permissions: UserPermissions
  /** Mirrors sidebar.tsx: clear the active company (the HQ is company-neutral),
   *  then navigate to /business-office. */
  onBusinessOffice: () => void
}

export interface WaterNavConfig {
  /** Stays a narrow single-column dropdown — it's a 4-item shortcut bar. */
  quickLinks: NavGroup
  operations: MegaMenuGroup[]
  salesMoney: MegaMenuGroup[]
  setup: MegaMenuGroup[]
}

export function buildWaterNavConfig({ permissions, onBusinessOffice }: WaterNavDeps): WaterNavConfig {
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
        { href: "/water-production-batches", label: "Production",    icon: Factory },
        { href: "/water-sales",              label: "Sales",         icon: ShoppingCart },
      ],
    },

    operations: [
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
        key: "production",
        label: "Production",
        color: "bg-indigo-600",
        items: [
          { id: "production",       title: "Production",       icon: Factory,      href: "/water-production-batches" },
          { id: "batch-production", title: "Batch Production", icon: CalendarDays, href: "/water-daily-production" },
          { id: "products",         title: "Products",         icon: ShoppingBag,  href: "/water-products" },
          { id: "machines",         title: "Machines",         icon: Cog,          href: "/water-machines" },
          { id: "boreholes",        title: "Boreholes",        icon: Droplets,     href: "/water-boreholes" },
          { id: "maintenance",      title: "Maintenance",      icon: Wrench,       href: "/water-maintenance" },
        ],
      },
      {
        key: "inventory",
        label: "Inventory",
        color: "bg-amber-600",
        items: [
          { id: "stock",             title: "Stock",                     icon: Boxes,         href: "/water-stock" },
          { id: "inventory",         title: "Inventory",                 icon: Boxes,         href: "/water-inventory" },
          { id: "raw-materials",     title: "Raw materials & supplies",  icon: Box,           href: "/water-raw-materials" },
          { id: "loss-records",      title: "Damages & loss",            icon: AlertTriangle, href: "/water-loss-records" },
          { id: "production-losses", title: "Production losses",         icon: AlertTriangle, href: "/water-production-losses" },
        ],
      },
    ],

    salesMoney: [
      {
        key: "sales-customers",
        label: "Sales & Customers",
        color: "bg-sky-600",
        items: [
          { id: "customers", title: "Customers", icon: Users,        href: "/water-customers" },
          { id: "sales",     title: "Sales",     icon: ShoppingCart, href: "/water-sales" },
          { id: "payments",  title: "Payments",  icon: CreditCard,   href: "/water-payments" },
        ],
      },
      {
        key: "money",
        label: "Money",
        color: "bg-emerald-600",
        items: [
          { id: "expenses",      title: "Expenses",       icon: Receipt, href: "/water-expenses" },
          { id: "cash-accounts", title: "Cash & Accounts", icon: Wallet, href: "/water-cash-accounts" },
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
          { id: "suppliers",     title: "Suppliers",     icon: Truck,     href: "/water-suppliers" },
          { id: "companies",     title: "Companies",     icon: Building2, href: "/companies" },
          // Action, not a link: the HQ is company-neutral, so the active company
          // has to be cleared first.
          { id: "business-office", title: "Business Office", icon: Briefcase, onClick: onBusinessOffice },
        ],
      },
      {
        key: "people",
        label: "People",
        color: "bg-violet-600",
        items: [
          { id: "staff",    title: "Staff",   icon: UserCog,  href: "/water-staff",  visible: canSeeStaff },
          // Keep Payroll ungated — it's what guarantees this column always
          // renders, so the rail can't reflow when permissions settle.
          { id: "payroll",  title: "Payroll", icon: Banknote, href: "/water-payroll" },
          { id: "employees", title: "Users & Permissions", icon: UserCog, href: "/employees", visible: canSeeStaff },
        ],
      },
      {
        key: "account",
        label: "Your account",
        color: "bg-slate-500",
        items: [
          { id: "profile",      title: "Account",             icon: User,     href: "/profile" },
          { id: "audit-logs",   title: "Activity Log",        icon: Activity, href: "/audit-logs", visible: canSeeActivityLog },
          { id: "terms",        title: "Terms & Conditions",  icon: ListTodo, href: "/terms" },
        ],
      },
    ],
  }
}
