// Recommended module defaults per business template.
//
// These mirror the logic in spgenericbusinesstemplate_apply (migration 242,
// lines 264-268): a subscription business hides stock by default and shows
// billing; a retail or general business shows stock and hides billing.
//
// Used by:
//   - Business Features page (recommended indicators)
//   - Restore Recommended Features (preview and apply)
//
// If the SP logic changes, update this map to match.

import type { GenericModuleSettings } from "@/lib/api/generic-subscriptions"
import type { BusinessTemplate } from "./template-labels"

export type ModuleKey = keyof Omit<GenericModuleSettings, "farmId">

/** The full set of module defaults a template applies. */
export type RecommendedModules = Record<ModuleKey, boolean>

const SUBSCRIPTION_DEFAULTS: RecommendedModules = {
  enableProducts: false,
  enableInventory: false,
  enableStockAdjustments: false,
  enableInternalUse: false,
  enablePurchases: false,
  enableSubscriptions: true,
  enableInvoices: true,
  enableCustomerBalances: true,
  enableStaffPayments: true,
  enableCashAccounts: true,
  enableRecurringExpenses: true,
  enableSupplierBalances: true,
}

const RETAIL_DEFAULTS: RecommendedModules = {
  enableProducts: true,
  enableInventory: true,
  enableStockAdjustments: true,
  enableInternalUse: true,
  enablePurchases: true,
  enableSubscriptions: false,
  enableInvoices: false,
  enableCustomerBalances: false,
  enableStaffPayments: true,
  enableCashAccounts: true,
  enableRecurringExpenses: true,
  enableSupplierBalances: true,
}

// GeneralBusiness uses the same defaults as Retail — stock on, billing off.
const GENERAL_DEFAULTS: RecommendedModules = { ...RETAIL_DEFAULTS }

const DEFAULTS_BY_TEMPLATE: Record<BusinessTemplate, RecommendedModules> = {
  SubscriptionServiceBusiness: SUBSCRIPTION_DEFAULTS,
  RetailBusiness: RETAIL_DEFAULTS,
  GeneralBusiness: GENERAL_DEFAULTS,
}

/**
 * Returns the recommended module settings for a business template.
 * Returns null for an unknown or missing template (pre-template companies).
 */
export function getRecommendedModules(
  template?: string | null,
): RecommendedModules | null {
  if (!template) return null
  return DEFAULTS_BY_TEMPLATE[template as BusinessTemplate] ?? null
}

/** All module keys in display order. */
export const ALL_MODULE_KEYS: ModuleKey[] = [
  "enableSubscriptions",
  "enableInvoices",
  "enableCustomerBalances",
  "enableProducts",
  "enableInventory",
  "enableStockAdjustments",
  "enableInternalUse",
  "enablePurchases",
  "enableStaffPayments",
  "enableCashAccounts",
  "enableRecurringExpenses",
  "enableSupplierBalances",
]

/** Human-readable feature metadata for the Business Features page. */
export interface FeatureInfo {
  key: ModuleKey
  label: string
  description: string
  group: string
}

export const FEATURE_CATALOG: FeatureInfo[] = [
  // Sales & Billing
  { key: "enableSubscriptions",    label: "Subscriptions",      description: "Plans, subscriptions and billing runs",                    group: "Sales & Billing" },
  { key: "enableInvoices",         label: "Invoices",           description: "Raise bills and track what is owed",                       group: "Sales & Billing" },
  { key: "enableCustomerBalances", label: "Customer balances",  description: "See who owes money, with aged balances and statements",    group: "Sales & Billing" },

  // Inventory & Products
  { key: "enableProducts",         label: "Products",           description: "A catalogue of things you sell",                           group: "Inventory & Products" },
  { key: "enableInventory",        label: "Inventory",          description: "Stock levels, movements and valuation",                    group: "Inventory & Products" },
  { key: "enableStockAdjustments", label: "Stock adjustments",  description: "Corrections to stock on hand",                             group: "Inventory & Products" },
  { key: "enableInternalUse",      label: "Internal use",       description: "Stock consumed by the business itself",                    group: "Inventory & Products" },
  { key: "enablePurchases",        label: "Purchases",          description: "What you buy from suppliers",                              group: "Inventory & Products" },

  // Expenses & Finance
  { key: "enableRecurringExpenses",label: "Recurring expenses", description: "Templates that raise a bill when it falls due",            group: "Expenses & Finance" },
  { key: "enableSupplierBalances", label: "Supplier balances",  description: "What you owe vendors — from expenses as well as purchases",group: "Expenses & Finance" },
  { key: "enableCashAccounts",     label: "Cash accounts",      description: "Tills, bank accounts and mobile money",                    group: "Expenses & Finance" },

  // Employees & Payroll
  { key: "enableStaffPayments",    label: "Staff payments",     description: "Pay staff, contractors and commission-based workers",       group: "Employees & Payroll" },
]

/** Group the feature catalog by group name, preserving order. */
export function groupedFeatures(): { group: string; features: FeatureInfo[] }[] {
  const groups: { group: string; features: FeatureInfo[] }[] = []
  const seen = new Map<string, FeatureInfo[]>()
  for (const f of FEATURE_CATALOG) {
    const existing = seen.get(f.group)
    if (existing) {
      existing.push(f)
    } else {
      const arr = [f]
      seen.set(f.group, arr)
      groups.push({ group: f.group, features: arr })
    }
  }
  return groups
}
