// =============================================================================
// THE PAGE CATALOG — the one list of every access-controlled page.
//
// Every page a staff member can open, in every company type, is listed here
// once: its permission key, the menu label owners see in Staff Page Access,
// the menu section it lives in, the routes it covers, and whether it is
// sensitive (unticked by default for a new employee).
//
// Everything else is derived from this file:
//   - the page guard (lib/iam/page-registry.ts) maps a URL to its key,
//   - the menus ask the same registry whether to show a row,
//   - migration 506 (scripts/iam/gen-page-catalog-sql.mjs) seeds these rows
//     into the IAM catalog the server enforces,
//   - the tests prove every app page and every menu row is covered.
//
// ADDING A PAGE: add one entry here (or the page is denied to every staff
// member and the registry test fails), then run
// `node scripts/iam/gen-page-catalog-sql.mjs NNN` for the catalog migration.
//
// This file must stay import-free and use only erasable TypeScript, because
// the SQL generator loads it with plain Node.
// =============================================================================

export type PageAction = "view" | "create" | "edit" | "delete" | "approve" | "reverse" | "export"

/** Top-level groups in the Staff Page Access editor, in display order. */
export const NAV_SECTIONS = [
  "Dashboard", "Operations", "Sales", "Expenses", "Money", "Reports",
  "Tools", "Employees", "Setup", "Administration",
] as const
export type NavSection = (typeof NAV_SECTIONS)[number]

export type PageModule = "poultry" | "water" | "generic" | "hotel" | "restaurant" | "livestock" | "office"

/**
 * The 12 legacy Staff Page Access flags that actually reached the browser
 * before this upgrade (lib/api/auth.ts extractFromFeatureRecord kept only
 * these). Water flags were "grandfathered" to on for every staff member and
 * the hotel/restaurant flags were always off, so they are not legacy inputs.
 */
export type LegacyFlag =
  | "canEnterSales" | "canEnterExpenses" | "canViewCashLedger" | "canSeeEmployees"
  | "canViewReports" | "canViewFinancial" | "canViewCustomers" | "canViewActivityLog"
  | "canViewSettings" | "canViewFeedProduction" | "canManageFeedProduction" | "canViewFeedProductionCost"

export const LEGACY_FLAGS: readonly LegacyFlag[] = [
  "canEnterSales", "canEnterExpenses", "canViewCashLedger", "canSeeEmployees",
  "canViewReports", "canViewFinancial", "canViewCustomers", "canViewActivityLog",
  "canViewSettings", "canViewFeedProduction", "canManageFeedProduction", "canViewFeedProductionCost",
]

/**
 * How a plain (non-admin) staff member's access to this page was decided
 * before this upgrade — used once, by migration 507, so nobody gains or loses
 * a page on deploy.
 *   "always" — the menu showed it to every staff member
 *   "admin"  — only admins/owners saw it
 *   flags    — shown when ANY of these flags was ticked
 *   "iam"    — the menu already asked IAM `can(<view key>)`, so whoever held
 *              that key (legacy-flag mapping or an IAM grant) keeps it
 */
export type LegacyRule = "always" | "admin" | "iam" | readonly LegacyFlag[]

export interface PageDef {
  module: PageModule
  resource: string
  label: string
  section: NavSection
  /** Sub-heading inside the section (also IAM permissiongroup). */
  group: string
  /** First is the page's main address; detail pages under each inherit. */
  routes: readonly string[]
  /** Actions beyond view that this page offers. View is implicit. */
  actions?: readonly PageAction[]
  /** Unticked by default for a new employee; bulk "select all" asks first. */
  sensitive?: boolean
  /** Page key whose view must also be held (e.g. a report category needs Reports). */
  dependsOn?: string
  legacy: LegacyRule
  /**
   * Existing catalog key whose role holders receive this new page key when
   * migration 506 seeds it (the "Carried over from …" pattern), so built-in
   * roles like Accountant keep reaching what they reached before.
   */
  carry?: string
  description?: string
}

export const pageKey = (p: Pick<PageDef, "module" | "resource">) => `${p.module}.${p.resource}`
export const viewKey = (p: Pick<PageDef, "module" | "resource">) => `${p.module}.${p.resource}.view`

// ---- builders -----------------------------------------------------------------

type Opts = Omit<PageDef, "module" | "resource" | "label" | "section" | "group" | "routes" | "legacy">
const pg = (
  module: PageModule, resource: string, label: string, section: NavSection, group: string,
  routes: readonly string[], legacy: LegacyRule, opts: Opts = {},
): PageDef => ({ module, resource, label, section, group, routes, legacy, ...opts })

const S: LegacyFlag = "canEnterSales"
const E: LegacyFlag = "canEnterExpenses"
const C: LegacyFlag = "canViewCashLedger"
const M: LegacyFlag = "canSeeEmployees"
const R: LegacyFlag = "canViewReports"
const F: LegacyFlag = "canViewFinancial"
const U: LegacyFlag = "canViewCustomers"
const A: LegacyFlag = "canViewActivityLog"
const T: LegacyFlag = "canViewSettings"
const FP: LegacyFlag = "canViewFeedProduction"

const CRUD: readonly PageAction[] = ["create", "edit", "delete"]
const CRUDX: readonly PageAction[] = ["create", "edit", "delete", "export"]
const MONEY_ACTS: readonly PageAction[] = ["create", "edit", "approve"]

/**
 * Report categories, shared by every family. A category key is what decides
 * whether a report page opens; `<module>.reports.view` opens the Reports menu.
 */
const REPORT_CATEGORIES: ReadonlyArray<{ resource: string; label: string; sensitive?: boolean; carry: string }> = [
  { resource: "reports-sales",      label: "Sales Reports",            carry: "reports.view" },
  { resource: "reports-customers",  label: "Customer Reports",         carry: "reports.view" },
  { resource: "reports-suppliers",  label: "Supplier Reports",         carry: "reports.view" },
  { resource: "reports-expenses",   label: "Expense Reports",          carry: "reports.view" },
  { resource: "reports-financial",  label: "Financial Reports (P&L, cash)", sensitive: true, carry: "reports.view" },
  { resource: "reports-payroll",    label: "Payroll Reports",          sensitive: true, carry: "payroll.view" },
  { resource: "reports-production", label: "Production Reports",       carry: "reports.view" },
  { resource: "reports-inventory",  label: "Inventory Reports",        carry: "reports.view" },
  { resource: "reports-operations", label: "Operations & Delivery Reports", carry: "reports.view" },
]

function reportCategories(module: PageModule, routesByCategory: Partial<Record<string, readonly string[]>>, legacy: LegacyRule = [R]): PageDef[] {
  const out: PageDef[] = []
  for (const c of REPORT_CATEGORIES) {
    const routes = routesByCategory[c.resource]
    if (!routes || routes.length === 0) continue
    out.push(pg(module, c.resource, c.label, "Reports", "Report categories", routes,
      legacy,
      { actions: ["export"], sensitive: c.sensitive, dependsOn: `${module}.reports`, carry: `${module}.${c.carry}` }))
  }
  return out
}

/**
 * The Sales / Expenses / Money pages every family shares in shape. `r` gives
 * each page's route (omit a page the family does not have) and `legacy`
 * overrides the default legacy rule where that family's nav-access file
 * differed.
 */
type FinKey =
  | "sales" | "payments" | "customer-balances" | "customer-credits"
  | "expenses" | "recurring-expenses" | "supplier-payments" | "supplier-balances" | "supplier-credits"
  | "internal-use" | "payroll" | "employee-loans" | "employee-credit" | "deferred-costs" | "assets"
  | "cash-flow" | "financial-activity" | "profit-loss" | "owner-money" | "loans" | "cash"
  | "cash-transfers" | "cash-reconciliation" | "daily-closing" | "customers" | "suppliers"

interface FinSpec {
  label: string
  section: NavSection
  group: string
  sensitive?: boolean
  actions: readonly PageAction[]
  legacy: LegacyRule
  carry?: (m: PageModule) => string
}

const FIN: Record<FinKey, FinSpec> = {
  "sales":               { label: "Sales",                       section: "Sales",    group: "Sales", actions: ["create", "edit", "delete", "approve", "reverse", "export"], legacy: [S] },
  "payments":            { label: "Customer Payments",           section: "Sales",    group: "Sales", actions: ["create", "edit", "approve", "reverse"], legacy: [F, S] },
  "customer-balances":   { label: "Customer Balances",           section: "Sales",    group: "Sales", actions: ["create", "reverse"], legacy: [F, S, U] },
  "customer-credits":    { label: "Customer Credits",            section: "Sales",    group: "Sales", actions: ["create", "reverse"], legacy: [F, S, U], carry: (m) => `${m}.customer-balances.view` },
  "expenses":            { label: "Expenses",                    section: "Expenses", group: "Expenses", actions: ["create", "edit", "delete", "approve", "reverse", "export"], legacy: [E] },
  "recurring-expenses":  { label: "Recurring Expenses",          section: "Expenses", group: "Expenses", actions: ["create", "edit", "reverse"], legacy: [E], carry: (m) => `${m}.expenses.view` },
  "supplier-payments":   { label: "Supplier Payments",           section: "Expenses", group: "Expenses", actions: ["create", "approve", "reverse"], legacy: [F, E, U], carry: (m) => `${m}.supplier-balances.view` },
  "supplier-balances":   { label: "Supplier Balances",           section: "Expenses", group: "Expenses", actions: ["create", "reverse"], legacy: [F, E, U] },
  "supplier-credits":    { label: "Supplier Credits & Advances", section: "Expenses", group: "Expenses", actions: ["create", "reverse"], legacy: [F, E, U], carry: (m) => `${m}.supplier-balances.view` },
  "internal-use":        { label: "Internal Use",                section: "Expenses", group: "Expenses", actions: CRUD, legacy: "always" },
  "payroll":             { label: "Payroll",                     section: "Expenses", group: "People & pay", sensitive: true, actions: ["create", "edit", "delete", "approve", "export"], legacy: "always" },
  "employee-loans":      { label: "Employee Loans & Advances",   section: "Expenses", group: "People & pay", sensitive: true, actions: ["create", "edit", "approve", "reverse"], legacy: [C], carry: (m) => `${m}.cash.view` },
  "employee-credit":     { label: "Employee Credit",             section: "Expenses", group: "People & pay", sensitive: true, actions: ["create", "reverse"], legacy: [C], carry: (m) => `${m}.cash.view` },
  "deferred-costs":      { label: "Deferred Inventory Cost",     section: "Expenses", group: "Costing", sensitive: true, actions: ["create", "reverse"], legacy: [E, F], carry: (m) => `${m}.expenses.view` },
  "assets":              { label: "Capital Investments/Assets",  section: "Expenses", group: "Costing", sensitive: true, actions: CRUD, legacy: [E, F] },
  "cash-flow":           { label: "Cash Flow",                   section: "Money", group: "Money", sensitive: true, actions: ["export"], legacy: [C], carry: (m) => `${m}.cash.view` },
  "financial-activity":  { label: "Financial Activity",          section: "Money", group: "Money", sensitive: true, actions: ["export"], legacy: [C], carry: (m) => `${m}.cash.view` },
  "profit-loss":         { label: "Profit & Loss",               section: "Money", group: "Money", sensitive: true, actions: ["export"], legacy: [F, R], carry: (m) => `${m}.reports.view` },
  "owner-money":         { label: "Owner Money",                 section: "Money", group: "Money", sensitive: true, actions: MONEY_ACTS, legacy: [C] },
  "loans":               { label: "Loans (Financing)",           section: "Money", group: "Money", sensitive: true, actions: MONEY_ACTS, legacy: [C] },
  "cash":                { label: "Cash Account",                section: "Money", group: "Money", sensitive: true, actions: ["create", "edit", "delete", "export"], legacy: [C] },
  "cash-transfers":      { label: "Cash Transfers",              section: "Money", group: "Money", sensitive: true, actions: MONEY_ACTS, legacy: [C] },
  "cash-reconciliation": { label: "Reconciliation",              section: "Money", group: "Money", sensitive: true, actions: CRUD, legacy: [C] },
  "daily-closing":       { label: "Daily Closing",               section: "Money", group: "Closing", actions: ["create", "edit", "approve"], legacy: [F, C] },
  "customers":           { label: "Customers",                   section: "Setup", group: "Finance", actions: CRUDX, legacy: "admin" },
  "suppliers":           { label: "Suppliers",                   section: "Setup", group: "Finance", actions: CRUD, legacy: "admin" },
}

function finance(
  module: PageModule,
  r: Partial<Record<FinKey, string | readonly string[]>>,
  legacy: Partial<Record<FinKey, LegacyRule>> = {},
  labels: Partial<Record<FinKey, string>> = {},
): PageDef[] {
  const out: PageDef[] = []
  for (const k of Object.keys(r) as FinKey[]) {
    const spec = FIN[k]
    const routes = r[k]!
    out.push(pg(module, k, labels[k] ?? spec.label, spec.section, spec.group,
      typeof routes === "string" ? [routes] : routes, legacy[k] ?? spec.legacy,
      { actions: spec.actions, sensitive: spec.sensitive, carry: spec.carry?.(module) }))
  }
  return out
}

const dashFinancials = (module: PageModule): PageDef =>
  pg(module, "dashboard-financials", "Dashboard money figures (sales, profit, cash)", "Dashboard", "Dashboard",
    [], "always", { sensitive: true, carry: `${module}.reports.view`,
      description: "Revenue, expense, profit and cash cards and charts on the dashboard. Operational cards always show." })

// =============================================================================
// POULTRY
// =============================================================================
const POULTRY: PageDef[] = [
  dashFinancials("poultry"),
  // --- Operations: Production
  pg("poultry", "production-records", "Production Records", "Operations", "Production", ["/production-records"], "always", { actions: CRUDX }),
  pg("poultry", "batch-production", "Batch Production", "Operations", "Production", ["/batch-production-records"], "always", { actions: CRUD, carry: "poultry.production-records.view" }),
  pg("poultry", "weigh-ins", "Weigh-ins", "Operations", "Production", ["/poultry-weigh-ins"], "always", { actions: CRUD, carry: "poultry.production-records.view" }),
  pg("poultry", "egg-sorting", "Egg Sorting", "Operations", "Production", ["/poultry-egg-sorting", "/egg-sorting"], "always", { actions: CRUD }),
  pg("poultry", "egg-production", "Egg Production (legacy page)", "Operations", "Production", ["/egg-production"], "always", { actions: CRUDX }),
  pg("poultry", "feed-usage", "Feed Usage", "Operations", "Production", ["/feed-usage"], "always", { actions: CRUD }),
  pg("poultry", "feed-production", "Feed Production", "Operations", "Production", ["/poultry-feed-production"], [FP], { actions: ["create", "edit", "delete", "approve"] }),
  pg("poultry", "feed-production-cost", "Feed Production Costs", "Operations", "Production", [], ["canViewFeedProductionCost"], { sensitive: true,
    description: "The cost columns inside Feed Production." }),
  // --- Operations: Inventory & Health
  pg("poultry", "inventory", "Inventory", "Operations", "Inventory & Health", ["/poultry-inventory", "/inventory", "/supplies"], "always", { actions: CRUD }),
  pg("poultry", "stock", "Stock Movements", "Operations", "Inventory & Health", ["/poultry-stock"], "always", { actions: ["edit", "export"] }),
  pg("poultry", "supply-purchases", "Inventory & Supply Purchases", "Operations", "Inventory & Health", ["/poultry-supply-purchases"], "always", { actions: ["create", "edit", "approve", "reverse"], carry: "poultry.inventory.view" }),
  pg("poultry", "raw-materials", "Raw Materials", "Operations", "Inventory & Health", ["/poultry-raw-materials"], "always", { actions: CRUD }),
  pg("poultry", "health", "Health Records", "Operations", "Inventory & Health", ["/health"], "always", { actions: CRUD }),
  pg("poultry", "medication", "Medications & Vaccinations", "Operations", "Inventory & Health", [], "always", { actions: CRUD,
    description: "Medication and vaccination entries inside Health and production records." }),
  pg("poultry", "loss-records", "Loss & Damage", "Operations", "Inventory & Health", ["/poultry-loss-records"], "always", { actions: CRUD }),
  // --- Operations: Delivery
  pg("poultry", "driver-returns", "Deliveries", "Operations", "Delivery", ["/poultry-driver-returns", "/poultry-deliveries"], "always", { actions: ["create", "edit", "delete", "approve"] }),
  pg("poultry", "driver-report", "Driver Report", "Operations", "Delivery", ["/poultry-driver-report"], "always", { carry: "poultry.driver-returns.view" }),
  // --- Operations: Purchase
  pg("poultry", "flock-batches", "Flock Purchases (Batches)", "Operations", "Purchase", ["/flock-batch"], "always", { actions: CRUD }),
  // --- Sales / Expenses / Money
  ...finance("poultry", {
    "sales": "/sales", "payments": "/poultry-payments", "customer-balances": "/customer-balances", "customer-credits": "/customer-credits",
    "expenses": "/expenses", "recurring-expenses": "/recurring-expenses", "supplier-payments": "/supplier-payments",
    "supplier-balances": "/supplier-balances", "supplier-credits": "/supplier-credits",
    "internal-use": "/poultry-internal-use", "payroll": "/poultry-payroll", "employee-loans": "/poultry-employee-loans",
    "employee-credit": "/poultry-employee-credit", "deferred-costs": "/poultry-deferred-costs", "assets": "/poultry-assets",
    "cash-flow": "/cash-flow", "financial-activity": ["/poultry-financial-activity", "/cash"], "profit-loss": ["/poultry-profit-loss", "/poultry/reports/profit-loss"],
    "owner-money": "/poultry-owner-money", "loans": "/poultry-loans", "cash": "/poultry-cash-accounts",
    "cash-transfers": "/poultry-cash-transfers", "cash-reconciliation": "/poultry-cash-reconciliation",
    "daily-closing": "/poultry-daily-closing", "customers": "/customers", "suppliers": "/suppliers",
  }, { "daily-closing": "always" }),
  // --- Analytics (trackers)
  pg("poultry", "trackers", "Trackers (egg, feed, birds, medication)", "Reports", "Analytics",
    ["/egg-tracker", "/broken-eggs-tracker", "/feed-tracker", "/feed-inventory-tracker", "/birds-left-tracker",
     "/dead-birds-tracker", "/medication-tracker", "/feed-ingredient-tracker", "/poultry-broiler-performance", "/weekly-report"],
    "always", { carry: "poultry.production-records.view" }),
  // --- Reports
  pg("poultry", "reports", "Reports menu", "Reports", "Reports", ["/poultry/reports", "/poultry-reports", "/reports"], [R], { actions: ["export"] }),
  ...reportCategories("poultry", {
    "reports-production": ["/poultry/reports/daily-egg-production", "/poultry/reports/flock-production-summary", "/poultry/reports/hen-day-production",
      "/poultry/reports/missing-daily-records", "/poultry/reports/mortality", "/poultry/reports/birds-on-hand", "/poultry/reports/end-of-flock",
      "/poultry/reports/feed-usage", "/poultry/reports/feed-cost-per-egg", "/poultry/reports/vaccination-schedule", "/poultry/reports/medicine-usage",
      "/poultry/reports/batch-production-summary", "/poultry/reports/batch-bird-reconciliation", "/poultry/reports/production",
      "/poultry-feed-production/reports", "/poultry/reports/daily", "/poultry/reports/changes", "/poultry/reports/more"],
    "reports-inventory": ["/poultry/reports/feed-inventory-balance", "/poultry/reports/egg-stock-balance", "/poultry/reports/byproduct-inventory"],
    "reports-sales": ["/poultry/reports/egg-sales"],
    "reports-customers": ["/poultry/reports/customer-balance"],
    "reports-suppliers": ["/poultry/reports/supplier-balance"],
    "reports-expenses": ["/poultry/reports/expense-summary"],
    "reports-financial": ["/poultry/reports/cash-movement", "/poultry/reports/cash-flow-detail",
      "/poultry/reports/profit-loss-by-flock", "/poultry/reports/cost-per-egg", "/poultry/reports/cash-accounts", "/poultry/reports/money",
      "/poultry/reports/financial", "/poultry-daily-summary", "/poultry-closing-report-daily", "/poultry-closing-report",
      "/poultry-reports/closing-report", "/poultry-reports/daily-summary"],
    "reports-operations": ["/poultry-reports/delivery-run-report", "/poultry-reports/driver-accountability", "/poultry-reports/driver-collection"],
  }),
  // --- Tools
  pg("poultry", "farm-setup", "Initial Farm Setup", "Tools", "Tools", ["/poultry-farm-setup"], "admin", { actions: ["create", "edit", "delete"], sensitive: true, carry: "poultry.flocks.edit" }),
  pg("poultry", "flock-closeout", "Flock Closeout", "Tools", "Tools", ["/flock-closeout"], "iam", { actions: ["create", "approve"] }),
  pg("poultry", "lifecycle", "Flock Lifecycle & Vaccination Planner", "Tools", "Tools", ["/poultry-lifecycle"], "iam", { actions: CRUD }),
  pg("poultry", "farm-completeness", "Farm Completeness", "Tools", "Tools", ["/poultry-farm-completeness"], "always", { carry: "poultry.production-records.view" }),
  pg("poultry", "feed-distribution", "Distribute Feed", "Tools", "Tools", ["/poultry-feed-distribution"], "always", { actions: ["create", "edit"], carry: "poultry.feed-usage.view" }),
  pg("poultry", "bird-count", "Batch Bird Count", "Tools", "Tools", ["/poultry-batch-bird-count"], "iam", { actions: ["create"] }),
  pg("poultry", "treatment-campaigns", "Treatment Campaigns", "Tools", "Tools", ["/poultry-treatment-campaigns"], "always", { actions: CRUD, carry: "poultry.health.view" }),
  pg("poultry", "restock-forecast", "Inventory Restock Forecast", "Tools", "Tools", ["/poultry-restock-forecast", "/poultry-days-of-supply"], "always", { actions: ["edit"], carry: "poultry.inventory.view" }),
  pg("poultry", "alerts", "Flock & Farm Alerts", "Tools", "Tools", ["/poultry-flock-alerts", "/poultry-alerts"], "always", { actions: ["edit"], carry: "poultry.flocks.view" }),
  pg("poultry", "purchase-receipts", "Receive Purchase", "Tools", "Tools", ["/poultry-purchase-receipts"], "iam", { actions: ["create", "approve"] }),
  pg("poultry", "egg-cost-analyzer", "Egg Cost & Profit Analyzer", "Tools", "Tools", ["/egg-cost-analyzer"], [F, R], { actions: ["create", "edit", "delete", "reverse"], sensitive: true, carry: "poultry.reports.view" }),
  pg("poultry", "advanced-costing", "Advanced Flock Costing", "Tools", "Tools", [], "admin", { actions: ["create", "edit", "approve"], sensitive: true }),
  // --- Employees
  pg("poultry", "staff", "Staff", "Employees", "People", ["/poultry-staff"], [M], { actions: CRUD }),
  // --- Setup
  pg("poultry", "houses", "Houses", "Setup", "Farm", ["/houses"], "admin", { actions: CRUD }),
  pg("poultry", "flocks", "Flock Groups", "Setup", "Farm", ["/flocks"], "always", { actions: CRUD }),
  pg("poultry", "financial-settings", "Financial Settings", "Setup", "Finance", ["/poultry-financial-settings"], "admin", { actions: ["edit"], sensitive: true }),
  pg("poultry", "products", "Products", "Setup", "Production", ["/poultry-products"], "admin", { actions: CRUD }),
  pg("poultry", "feed-formulas", "Feed Formulas", "Setup", "Production", ["/poultry-feed-formulas"], "admin", { actions: CRUD }),
  pg("poultry", "egg-settings", "Egg Settings", "Setup", "Production", ["/business-office/egg-pick-settings", "/poultry-egg-sorting-settings"], "admin", { actions: ["edit"], sensitive: true, carry: "poultry.egg-sorting.edit" }),
  pg("poultry", "setup", "Production & Business Setup", "Setup", "Company", ["/poultry-setup", "/poultry-company-setup", "/settings"], "admin", { actions: ["edit"], sensitive: true, carry: "poultry.financial-settings.view" }),
  pg("poultry", "drivers", "Drivers", "Setup", "Delivery", ["/poultry-drivers"], "admin", { actions: CRUD }),
  pg("poultry", "vehicles", "Vehicles", "Setup", "Delivery", ["/poultry-vehicles"], "admin", { actions: CRUD }),
  pg("poultry", "routes", "Routes", "Setup", "Delivery", ["/poultry-routes"], "admin", { actions: CRUD }),
]

// =============================================================================
// WATER
// =============================================================================
const WATER: PageDef[] = [
  dashFinancials("water"),
  pg("water", "production-batches", "Water Production", "Operations", "Production", ["/water-production-batches", "/water-production-lines"], "always", { actions: ["create", "edit", "delete", "approve"] }),
  pg("water", "daily-production", "Batch Production", "Operations", "Production", ["/water-daily-production"], "always", { actions: CRUDX }),
  pg("water", "maintenance", "Maintenance", "Operations", "Production", ["/water-maintenance"], "always", { actions: ["create", "edit", "delete", "approve"] }),
  pg("water", "stock", "Stock Movements", "Operations", "Inventory", ["/water-stock"], "always", { actions: ["edit", "export"] }),
  pg("water", "inventory", "Inventory", "Operations", "Inventory", ["/water-inventory", "/water-raw-materials"], "always", { actions: CRUD }),
  pg("water", "supply-purchases", "Inventory & Supply Purchases", "Operations", "Inventory", ["/water-supply-purchases"], "always", { actions: ["create", "edit", "approve", "reverse"], carry: "water.inventory.view" }),
  pg("water", "purchase-receipts", "Receive Purchase", "Operations", "Inventory", ["/water-purchase-receipts"], "always", { actions: ["create", "approve"], carry: "water.inventory.view" }),
  pg("water", "restock-forecast", "Inventory Restock Forecast", "Operations", "Inventory", ["/water-restock-forecast"], "always", { actions: ["edit"], carry: "water.inventory.view" }),
  pg("water", "loss-records", "Damages & Loss", "Operations", "Inventory", ["/water-loss-records"], "always", { actions: CRUD, carry: "water.inventory.view" }),
  pg("water", "production-losses", "Production Losses", "Operations", "Inventory", ["/water-production-losses"], "always", { actions: CRUD }),
  pg("water", "driver-returns", "Deliveries", "Operations", "Delivery", ["/water-driver-returns"], "always", { actions: ["create", "edit", "delete", "approve"] }),
  pg("water", "driver-report", "Driver Collection Report", "Operations", "Delivery", ["/water-driver-report"], "always", { carry: "water.driver-returns.view" }),
  pg("water", "trackers", "Inventory Tracker", "Reports", "Analytics", ["/water-inventory-tracker"], "always", { carry: "water.inventory.view" }),
  pg("water", "alerts", "Alerts", "Tools", "Tools", ["/water-alerts"], "always", { carry: "water.inventory.view" }),
  ...finance("water", {
    "sales": "/water-sales", "payments": "/water-payments", "customer-balances": "/water-customer-balances", "customer-credits": "/water-customer-credits",
    "expenses": "/water-expenses", "recurring-expenses": "/water-recurring-expenses", "supplier-payments": "/water-supplier-payments",
    "supplier-balances": "/water-supplier-balances", "supplier-credits": "/water-supplier-credits", "internal-use": "/water-internal-use",
    "payroll": "/water-payroll", "employee-loans": "/water-employee-loans", "employee-credit": "/water-employee-credit",
    "deferred-costs": "/water-deferred-costs", "assets": "/water-assets", "cash-flow": "/water-cash-flow",
    "financial-activity": "/water-financial-activity", "profit-loss": ["/water-profit-loss", "/water-reports/profit-loss"], "owner-money": "/water-owner-money",
    "loans": "/water-loans", "cash": "/water-cash-accounts", "cash-transfers": "/water-cash-transfers",
    "cash-reconciliation": "/water-cash-reconciliation", "daily-closing": "/water-daily-closing",
    "customers": "/water-customers", "suppliers": "/water-suppliers",
  }, { "recurring-expenses": "always", "assets": [F, E], "deferred-costs": [F, E] }),
  pg("water", "reports", "Reports menu", "Reports", "Reports", ["/water-reports"], [R], { actions: ["export"] }),
  ...reportCategories("water", {
    "reports-financial": ["/water-reports/closing-report", "/water-reports/closing-by-category", "/water-reports/daily-summary",
      "/water-reports/cash-movement", "/water-reports/cash-flow-detail", "/water-reports/cash-accounts", "/water-reports/money-movement"],
    "reports-expenses": ["/water-reports/expense-report"],
    "reports-suppliers": ["/water-reports/supplier-activity"],
    "reports-sales": ["/water-reports/sales-report", "/water-reports/payments-received"],
    "reports-customers": ["/water-reports/customer-balances", "/water-reports/customer-history", "/water-reports/top-customers"],
    "reports-production": ["/water-reports/production-report", "/water-reports/raw-material-usage", "/water-reports/product-performance"],
    "reports-inventory": ["/water-reports/raw-material-purchase", "/water-reports/inventory-report", "/water-reports/stock-movement"],
    "reports-operations": ["/water-reports/delivery-run-report", "/water-reports/driver-accountability", "/water-reports/route-performance",
      "/water-reports/driver-collection", "/water-reports/vehicle-usage", "/water-reports/loss-report", "/water-reports/operational"],
  }, "always"),
  pg("water", "staff", "Staff", "Employees", "People", ["/water-staff"], [M], { actions: CRUD }),
  pg("water", "setup", "Setup & Company Setup", "Setup", "Company", ["/water-setup", "/water-company-setup"], "admin", { actions: ["edit"], sensitive: true, carry: "water.financial-settings.view" }),
  pg("water", "financial-settings", "Financial Settings", "Setup", "Company", ["/water-financial-settings"], "admin", { actions: ["edit"], sensitive: true }),
  pg("water", "drivers", "Drivers", "Setup", "Delivery", ["/water-drivers"], "admin", { actions: CRUD }),
  pg("water", "vehicles", "Vehicles", "Setup", "Delivery", ["/water-vehicles"], "admin", { actions: CRUD }),
  pg("water", "routes", "Routes", "Setup", "Delivery", ["/water-routes"], "admin", { actions: CRUD }),
  pg("water", "products", "Products", "Setup", "Production", ["/water-products"], "admin", { actions: CRUD }),
  pg("water", "machines", "Machines", "Setup", "Plant", ["/water-machines"], "admin", { actions: CRUD }),
  pg("water", "boreholes", "Boreholes", "Setup", "Plant", ["/water-boreholes"], "admin", { actions: CRUD }),
]

// =============================================================================
// GENERIC (Services & Subscriptions, Retail/Wholesale, General, School…)
// =============================================================================
const GENERIC: PageDef[] = [
  dashFinancials("generic"),
  pg("generic", "subscription-plans", "Service Plans", "Sales", "Billing & Subscriptions", ["/generic-service-plans"], "always", { actions: CRUD }),
  pg("generic", "subscriptions", "Subscriptions", "Sales", "Billing & Subscriptions", ["/generic-subscriptions"], "always", { actions: CRUD }),
  pg("generic", "billing-runs", "Billing Runs", "Sales", "Billing & Subscriptions", ["/generic-billing-runs"], "always", { actions: CRUD }),
  pg("generic", "coupons", "Coupons", "Sales", "Billing & Subscriptions", ["/generic-coupons"], [S], { actions: CRUD, carry: "generic.sales.view" }),
  pg("generic", "invoices", "Invoices", "Sales", "Sales", ["/generic-invoices", "/generic-invoice-documents"], [F, S, U], { actions: CRUD }),
  pg("generic", "pos", "Point of Sale", "Sales", "Sales", ["/generic-pos", "/generic-pharmacy-pos", "/generic-prescriptions"], [S], { actions: ["create"], carry: "generic.sales.create" }),
  pg("generic", "products", "Products & Services", "Operations", "Catalog & Stock", ["/generic-products", "/generic-production", "/generic-medicines"], "always", { actions: CRUD }),
  pg("generic", "inventory", "Inventory & Supply Purchases", "Operations", "Catalog & Stock", ["/generic-inventory", "/generic-purchases", "/generic-batches", "/generic-pharmacy-reports"], "always", { actions: CRUD }),
  pg("generic", "stock-adjustments", "Stock Adjustments", "Operations", "Catalog & Stock", ["/generic-stock-adjustments"], "always", { actions: ["create", "edit", "delete", "approve"] }),
  pg("generic", "stock", "Stock Movements", "Operations", "Catalog & Stock", ["/generic-stock-movements"], "always", { actions: ["create"], carry: "generic.inventory.view" }),
  pg("generic", "trackers", "Product Tracker", "Reports", "Analytics", ["/generic-product-tracker"], "always", { carry: "generic.inventory.view" }),
  pg("generic", "loss-records", "Loss & Damage", "Operations", "Catalog & Stock", ["/generic-loss-records"], "always", { actions: CRUD, carry: "generic.inventory.view" }),
  pg("generic", "deliveries", "Deliveries", "Operations", "Logistics", ["/generic-deliveries"], "always", { actions: CRUD, carry: "generic.sales.view" }),
  pg("generic", "drivers", "Drivers & Routes", "Setup", "Delivery", ["/generic-drivers", "/generic-routes"], "always", { actions: CRUD, carry: "generic.sales.view" }),
  pg("generic", "projects", "Projects & Contracts", "Operations", "Projects", ["/generic-projects", "/generic-projects/compare"], [F, R], { actions: CRUD }),
  pg("generic", "project-financials", "Project Details & Reporting", "Operations", "Projects", [], [F, R], { actions: ["export"], sensitive: true }),
  pg("generic", "project-allocations", "Link Older Transactions to Projects", "Operations", "Projects", ["/generic-projects/link"], [F], { actions: ["create", "edit"] }),
  ...finance("generic", {
    "sales": "/generic-sales", "payments": "/generic-customer-payments", "customer-balances": "/generic-customer-balances",
    "customer-credits": "/generic-customer-credits", "expenses": "/generic-expenses",
    "recurring-expenses": ["/generic-recurring-expenses", "/recurring-expenses"], "supplier-payments": "/generic-supplier-payments",
    "supplier-balances": "/generic-supplier-balances", "supplier-credits": "/generic-supplier-credits",
    "internal-use": "/generic-internal-use", "payroll": ["/generic-payroll", "/generic-staff-payments"],
    "employee-loans": "/generic-employee-loans", "employee-credit": "/generic-employee-credit",
    "deferred-costs": "/generic-deferred-costs", "assets": "/generic-assets", "cash-flow": "/generic-cash-flow",
    "financial-activity": "/generic-financial-activity", "profit-loss": "/generic-profit-loss",
    "owner-money": "/generic-owner-money", "loans": "/generic-loans", "cash": "/generic-cash",
    "cash-transfers": "/generic-cash-transfers", "cash-reconciliation": "/generic-cash-reconciliation",
    "daily-closing": "/generic-daily-closings", "customers": "/generic-customers", "suppliers": "/generic-suppliers",
  }, {
    "payments": [U, F, S], "payroll": [C], "deferred-costs": [F], "assets": [F], "daily-closing": [C],
    "customers": [U, F], "suppliers": [F, E, U],
  }),
  pg("generic", "staff", "Staff", "Employees", "People", ["/generic-staff"], "always", { actions: CRUD }),
  pg("generic", "attendance", "Attendance", "Employees", "People", ["/generic-attendance"], "always", { actions: CRUD }),
  pg("generic", "school", "Classes, Terms & Student Attendance", "Operations", "School", ["/generic-classes", "/generic-terms", "/generic-student-attendance"], "always", { actions: CRUD, carry: "generic.customers.view" }),
  pg("generic", "reports", "Reports menu", "Reports", "Reports", ["/generic-reports"], [R], { actions: ["export"] }),
  ...reportCategories("generic", {
    "reports-financial": ["/generic-reports/period-pnl", "/generic-reports/daily-summary", "/generic-reports/cash-summary",
      "/generic-reports/cash-accounts", "/generic-reports/cash-movement", "/generic-reports/money-movement",
      "/generic-reports/closing-report", "/generic-reports/closing-by-category", "/generic-reports/break-even", "/generic-reports/hosting-cost"],
    "reports-expenses": ["/generic-reports/expenses-by-category"],
    "reports-customers": ["/generic-reports/customer-balance", "/generic-reports/unpaid-customers", "/generic-reports/customer-payments",
      "/generic-reports/invoice-aging", "/generic-reports/collections"],
    "reports-suppliers": ["/generic-reports/supplier-balance"],
    "reports-payroll": ["/generic-reports/staff-cost"],
    "reports-sales": ["/generic-reports/sales-by-product", "/generic-reports/sales-by-customer", "/generic-reports/subscription-revenue", "/generic-reports/mrr"],
    "reports-inventory": ["/generic-reports/inventory-value", "/generic-reports/inventory-balance", "/generic-reports/internal-consumption",
      "/generic-reports/restock-forecast", "/generic-reports/inventory-reconciliation"],
    "reports-operations": ["/generic-reports/delivery-report"],
  }),
  pg("generic", "setup", "Business Profile, Features & Settings", "Setup", "Company",
    ["/generic-setup", "/generic-business-features", "/generic-settings"], "admin", { actions: ["edit"], sensitive: true, carry: "office.settings.view" }),
]

// =============================================================================
// HOTEL
// =============================================================================
const HOTEL: PageDef[] = [
  dashFinancials("hotel"),
  pg("hotel", "bookings", "Bookings & Availability", "Operations", "Front Desk", ["/hotel-bookings"], "admin", { actions: CRUD, carry: "poultry.sales.view" }),
  pg("hotel", "guests", "Guests & Stay History", "Operations", "Front Desk", ["/hotel-guests"], "admin", { actions: CRUD, carry: "poultry.customers.view" }),
  pg("hotel", "check-in", "Check-in & Check-out", "Operations", "Front Desk", ["/hotel-check-in", "/hotel-check-out"], "admin", { actions: ["create"], carry: "poultry.sales.create" }),
  pg("hotel", "billing", "Guest Folio, Billing & Invoices", "Operations", "Front Desk", ["/hotel-billing", "/hotel-invoices"], "admin", { actions: CRUD, carry: "poultry.sales.view" }),
  pg("hotel", "availability", "Availability & Shift Handover", "Operations", "Front Desk", ["/hotel-availability", "/hotel-shift-handover"], "always", { actions: ["create"], carry: "poultry.sales.view" }),
  pg("hotel", "stay-history", "Stay History", "Operations", "Front Desk", ["/hotel-stay-history"], "always", { carry: "poultry.customers.view" }),
  pg("hotel", "guest-folio", "Guest Folio", "Operations", "Front Desk", ["/hotel-guest-folio"], "always", { actions: ["create", "edit"], carry: "poultry.sales.view" }),
  pg("hotel", "housekeeping-schedule", "Housekeeping Schedule", "Operations", "Rooms & Housekeeping", ["/hotel-housekeeping-schedule"], "always", { actions: CRUD, carry: "poultry.inventory.view" }),
  pg("hotel", "guest-services", "Guest Log, Requests, Lost & Found", "Operations", "Guest Services", ["/hotel-communications", "/hotel-guest-requests", "/hotel-lost-found"], "always", { actions: CRUD, carry: "poultry.customers.view" }),
  pg("hotel", "rooms", "Rooms & Room Service", "Operations", "Rooms & Housekeeping", ["/hotel-rooms", "/hotel-room-service"], "admin", { actions: CRUD, carry: "poultry.inventory.view" }),
  pg("hotel", "housekeeping", "Housekeeping & Schedule", "Operations", "Rooms & Housekeeping", ["/hotel-housekeeping"], "admin", { actions: CRUD, carry: "poultry.inventory.view" }),
  pg("hotel", "restaurant", "Restaurant & Bar (orders, menu, kitchen, tables)", "Operations", "Restaurant & Bar",
    ["/hotel-restaurant", "/hotel-menu", "/hotel-kitchen", "/hotel-restaurant-tables"], "admin", { actions: CRUD, carry: "poultry.sales.view" }),
  pg("hotel", "inventory", "Supplies", "Operations", "Facilities", ["/hotel-inventory"], "admin", { actions: CRUD, carry: "poultry.inventory.view" }),
  pg("hotel", "maintenance", "Maintenance", "Operations", "Facilities", ["/hotel-maintenance"], "admin", { actions: CRUD, carry: "poultry.inventory.view" }),
  pg("hotel", "night-audit", "Night Audit", "Money", "Closing", ["/hotel-night-audit"], [F, C], { actions: ["create", "approve"], carry: "poultry.daily-closing.view" }),
  ...finance("hotel", {
    "sales": "/hotel-sales", "payments": ["/hotel-payments", "/hotel-customer-payments"], "customer-balances": "/hotel-customer-balances",
    "expenses": "/hotel-expenses", "recurring-expenses": "/hotel-recurring-expenses", "supplier-payments": "/hotel-supplier-payments",
    "supplier-balances": "/hotel-supplier-balances", "internal-use": "/hotel-internal-use", "payroll": "/hotel-payroll",
    "employee-loans": "/hotel-employee-loans", "deferred-costs": "/hotel-deferred-costs", "assets": "/hotel-assets",
    "cash-flow": "/hotel-cash-flow", "financial-activity": "/hotel-financial-activity", "profit-loss": "/hotel-profit-loss",
    "owner-money": "/hotel-owner-money", "loans": "/hotel-loans", "cash": "/hotel-cash-accounts",
    "cash-transfers": "/hotel-cash-transfers", "cash-reconciliation": "/hotel-cash-reconciliation",
    "daily-closing": "/hotel-daily-closing", "customers": "/hotel-customers", "suppliers": "/hotel-suppliers",
  }, {
    "sales": [S], "payments": [F, S], "customer-balances": [F, S, U], "internal-use": "admin", "payroll": "admin",
    "employee-loans": "admin", "profit-loss": [E], "assets": [E], "recurring-expenses": "always",
  }),
  pg("hotel", "reports", "Reports menu", "Reports", "Reports", ["/hotel-reports"], [R], { actions: ["export"], carry: "poultry.reports.view" }),
  ...reportCategories("hotel", {
    "reports-financial": ["/hotel-reports/revenue-summary", "/hotel-reports/billing-report", "/hotel-reports/cash-flow-report",
      "/hotel-reports/guest-ledger", "/hotel-reports/ancillary-revenue", "/hotel-reports/daily-report", "/hotel-reports/weekly-report",
      "/hotel-reports/monthly-report", "/hotel-reports/performance-kpis", "/hotel-reports/source-of-business", "/hotel-reports/booking-pace",
      "/hotel-reports/room-type-performance"],
    "reports-expenses": ["/hotel-reports/expense-report"],
    "reports-payroll": ["/hotel-reports/payroll-report", "/hotel-reports/staff-loans"],
    "reports-sales": ["/hotel-reports/restaurant-sales", "/hotel-reports/menu-performance"],
    "reports-customers": ["/hotel-reports/guest-report", "/hotel-reports/loyalty-report", "/hotel-reports/length-of-stay", "/hotel-reports/cancellations"],
    "reports-operations": ["/hotel-reports/bookings-report", "/hotel-reports/occupancy-report", "/hotel-reports/maintenance-report",
      "/hotel-reports/housekeeping-report", "/hotel-reports/housekeeping-productivity"],
    "reports-inventory": ["/hotel-reports/inventory-report"],
  }, "always"),
  pg("hotel", "staff", "Staff", "Employees", "People", ["/hotel-staff"], [M], { actions: CRUD, carry: "poultry.staff.view" }),
  pg("hotel", "setup", "Company & Hotel Setup", "Setup", "Company", ["/hotel-company-setup", "/hotel-setup"], "admin", { actions: ["edit"], sensitive: true, carry: "poultry.financial-settings.view" }),
]

// =============================================================================
// RESTAURANT
// =============================================================================
const RESTAURANT: PageDef[] = [
  dashFinancials("restaurant"),
  pg("restaurant", "pos", "POS & Orders", "Operations", "Orders", ["/restaurant-pos", "/restaurant-pending-orders", "/restaurant-orders"], "admin", { actions: ["create", "edit", "reverse"], carry: "poultry.sales.create" }),
  pg("restaurant", "tills", "Tills", "Money", "Closing", ["/restaurant-tills"], [C], { actions: ["create", "edit", "approve"], carry: "poultry.cash.view" }),
  pg("restaurant", "kitchen", "Kitchen Display", "Operations", "Kitchen", ["/restaurant-kds"], "admin", { actions: ["edit"], carry: "poultry.sales.view" }),
  pg("restaurant", "floor-plan", "Restaurant Areas & Tables", "Operations", "Floor & Tables", ["/restaurant-floor-plan"], "admin", { actions: CRUD, carry: "poultry.sales.view" }),
  pg("restaurant", "reservations", "Reservations & Waitlist", "Operations", "Floor & Tables", ["/restaurant-reservations"], "admin", { actions: CRUD, carry: "poultry.sales.view" }),
  pg("restaurant", "online-orders", "Online Ordering & QR", "Operations", "Online Ordering", ["/restaurant-online-orders", "/restaurant-qr-print"], "admin", { actions: ["edit"], carry: "poultry.sales.view" }),
  pg("restaurant", "delivery", "Drivers & Dispatch", "Operations", "Delivery", ["/restaurant-delivery"], "admin", { actions: CRUD, carry: "poultry.driver-returns.view" }),
  pg("restaurant", "inventory", "Ingredients & Stock", "Operations", "Inventory", ["/restaurant-inventory"], "always", { actions: CRUD, carry: "poultry.inventory.view" }),
  pg("restaurant", "crm", "Customers & CRM, Loyalty", "Operations", "Customers", ["/restaurant-crm", "/restaurant-loyalty"], "always", { actions: CRUD, carry: "poultry.customers.view" }),
  pg("restaurant", "extras", "Events, Gift Cards & Notifications", "Operations", "More", ["/restaurant-events", "/restaurant-gift-cards", "/restaurant-notifications"], "always", { actions: CRUD, carry: "poultry.sales.view" }),
  pg("restaurant", "income-expenses", "Income & Expenses (legacy)", "Money", "Money", ["/restaurant-income-expenses"], [C], { sensitive: true, carry: "poultry.cash.view" }),
  ...finance("restaurant", {
    "sales": "/restaurant-sales", "payments": "/restaurant-payments", "customer-balances": "/restaurant-customer-balances",
    "expenses": "/restaurant-expenses", "recurring-expenses": "/restaurant-recurring-expenses", "supplier-payments": "/restaurant-supplier-payments",
    "supplier-balances": "/restaurant-supplier-balances", "internal-use": "/restaurant-internal-use", "payroll": "/restaurant-payroll",
    "employee-loans": "/restaurant-staff-loans", "deferred-costs": "/restaurant-deferred-costs", "assets": "/restaurant-assets",
    "cash-flow": "/restaurant-cash-flow", "financial-activity": "/restaurant-financial-activity", "profit-loss": "/restaurant-profit-loss",
    "owner-money": "/restaurant-owner-money", "loans": "/restaurant-loans", "cash": "/restaurant-cash-accounts",
    "cash-transfers": "/restaurant-cash-transfers", "cash-reconciliation": "/restaurant-cash-reconciliation",
    "daily-closing": "/restaurant-daily-closing", "suppliers": "/restaurant-suppliers",
  }, {
    "sales": [F, S], "payments": [F, S], "internal-use": "always", "payroll": "admin", "employee-loans": "admin",
    "profit-loss": [C], "daily-closing": [C], "recurring-expenses": [E], "expenses": "always",
  }),
  pg("restaurant", "reports", "Reports", "Reports", "Reports", ["/restaurant-reports"], [R], { actions: ["create", "delete", "export"], carry: "poultry.reports.view",
    description: "Opens the restaurant report catalogue." }),
  pg("restaurant", "staff", "Staff", "Employees", "People", ["/restaurant-staff"], "admin", { actions: CRUD, carry: "poultry.staff.view" }),
  pg("restaurant", "menu", "Menu Items", "Setup", "Menu & Staff", ["/restaurant-menu"], "admin", { actions: CRUD, carry: "poultry.products.view" }),
  pg("restaurant", "setup", "Restaurant Setup", "Setup", "Company", ["/restaurant-setup"], "admin", { actions: ["edit"], sensitive: true, carry: "poultry.financial-settings.view" }),
]

// =============================================================================
// LIVESTOCK (its menu never filtered pages for staff except Setup)
// =============================================================================
const LIVESTOCK: PageDef[] = [
  dashFinancials("livestock"),
  pg("livestock", "production-records", "Daily Records", "Operations", "Production", ["/livestock-production-records"], "always", { actions: CRUDX }),
  pg("livestock", "breeding", "Breeding & Births", "Operations", "Production", ["/livestock-breeding"], "always", { actions: CRUD }),
  pg("livestock", "weigh-ins", "Weigh-ins & Growth", "Operations", "Production", ["/livestock-weigh-ins"], "always", { actions: CRUDX }),
  pg("livestock", "feed-production", "Feed Mixing", "Operations", "Production", ["/livestock-feed-production"], "always", { actions: ["create", "edit", "delete", "approve"] }),
  pg("livestock", "items", "Feed & Stock", "Operations", "Inventory & Health", ["/livestock-items"], "always", { actions: CRUD }),
  pg("livestock", "animal-stock", "Animal Stock", "Operations", "Inventory & Health", ["/livestock-animal-stock"], "always", { actions: ["edit", "export"] }),
  pg("livestock", "health", "Health Records", "Operations", "Inventory & Health", ["/livestock-health"], "always", { actions: CRUD }),
  pg("livestock", "vaccination", "Vaccinations & Deworming", "Operations", "Inventory & Health", ["/livestock-vaccinations"], "always", { actions: CRUD }),
  pg("livestock", "losses", "Loss & Damage", "Operations", "Inventory & Health", ["/livestock-losses"], "always", { actions: CRUD }),
  pg("livestock", "deliveries", "Deliveries", "Operations", "Delivery", ["/livestock-deliveries"], "always", { actions: CRUD }),
  pg("livestock", "batches", "Animal Purchases", "Operations", "Purchase", ["/livestock-batches"], "always", { actions: CRUD }),
  pg("livestock", "purchases", "Purchases", "Expenses", "Expenses", ["/livestock-purchases"], "always", { actions: ["create", "approve"] }),
  ...finance("livestock", {
    "sales": "/livestock-sales", "payments": "/livestock-customer-payments", "customer-balances": "/livestock-customer-balances",
    "expenses": "/livestock-expenses", "supplier-payments": "/livestock-supplier-payments", "supplier-balances": "/livestock-supplier-balances",
    "payroll": "/livestock-payroll", "assets": "/livestock-assets", "cash-flow": "/livestock-cash-flow", "profit-loss": "/livestock-profit-loss",
    "owner-money": "/livestock-owner-money", "loans": "/livestock-loans", "cash": "/livestock-cash-accounts",
    "cash-transfers": "/livestock-cash-transfers", "cash-reconciliation": "/livestock-cash-reconciliation",
    "daily-closing": "/livestock-daily-closing", "customers": "/livestock-customers", "suppliers": "/livestock-suppliers",
  }, {
    "sales": "always", "payments": "always", "customer-balances": "always", "expenses": "always", "supplier-payments": "always",
    "supplier-balances": "always", "payroll": "always", "assets": "always", "cash-flow": "always", "profit-loss": "always",
    "owner-money": "always", "loans": "always", "cash": "always", "cash-transfers": "always", "cash-reconciliation": "always",
    "daily-closing": "always",
  }),
  pg("livestock", "reports", "Reports menu", "Reports", "Reports", ["/livestock/reports"], "always", { actions: ["export"] }),
  ...reportCategories("livestock", {
    "reports-production": ["/livestock/reports/production", "/livestock/reports/mortality", "/livestock/reports/breeding",
      "/livestock/reports/herd", "/livestock/reports/group-summary", "/livestock/reports/feed", "/livestock/reports/medicine"],
    "reports-sales": ["/livestock/reports/sales"],
  }, "always"),
  pg("livestock", "trackers", "Monthly Trackers", "Reports", "Analytics", ["/livestock-trackers"], "always", { carry: "livestock.reports.view" }),
  pg("livestock", "missing-records", "Missing Records", "Tools", "Tools", ["/livestock-missing-records"], "always", { carry: "livestock.production-records.view" }),
  pg("livestock", "feed-distribution", "Feed Many Groups", "Tools", "Tools", ["/livestock-feed-distribution"], "always", { actions: ["create"], carry: "livestock.production-records.create" }),
  pg("livestock", "head-count", "Head Count", "Tools", "Tools", ["/livestock-head-count"], "always", { actions: ["create"] }),
  pg("livestock", "treatments", "Treatment Campaigns", "Tools", "Tools", ["/livestock-treatments"], "always", { actions: CRUD }),
  pg("livestock", "feed-supply", "Days of Supply", "Tools", "Tools", ["/livestock-feed-supply"], "always", { carry: "livestock.items.view" }),
  pg("livestock", "alerts", "Farm Alerts", "Tools", "Tools", ["/livestock-alerts"], "always", { actions: CRUD }),
  pg("livestock", "staff", "Staff", "Employees", "People", ["/livestock-staff"], "always", { actions: CRUD }),
  pg("livestock", "pens", "Pens", "Setup", "Farm", ["/livestock-pens"], "admin", { actions: CRUD }),
  pg("livestock", "groups", "Animal Groups", "Setup", "Farm", ["/livestock-groups"], "always", { actions: CRUD }),
  pg("livestock", "animals", "Animal Register", "Setup", "Farm", ["/livestock-animals"], "always", { actions: CRUD }),
  pg("livestock", "feed-formulas", "Feed Formulas", "Setup", "Production", ["/livestock-feed-formulas"], "always", { actions: CRUD }),
  pg("livestock", "species", "Animals Kept", "Setup", "Company", ["/livestock-animals-kept"], "admin", { actions: CRUD }),
  pg("livestock", "setup", "Company Settings", "Setup", "Company", ["/livestock-company-settings", "/livestock-setup"], "admin", { actions: ["edit"], sensitive: true, carry: "livestock.species.edit" }),
  pg("livestock", "drivers", "Delivery Setup", "Setup", "Delivery", ["/livestock-delivery-setup"], "admin", { actions: CRUD }),
]

// =============================================================================
// SHARED / ADMINISTRATION (every company type)
// =============================================================================
const OFFICE: PageDef[] = [
  pg("office", "employees", "View Employees (Users & Permissions)", "Employees", "Employees",
    ["/employees", "/business-office/employees", "/business-office/users"], [M], { actions: ["create", "edit", "delete"], sensitive: true }),
  pg("office", "employee-access", "Manage Employee Access", "Employees", "Employees", [], "admin", { actions: ["edit"], sensitive: true, dependsOn: "office.employees",
    carry: "office.access.edit", description: "Tick and untick other employees' page access." }),
  pg("office", "access", "Manage Roles & Permissions", "Employees", "Employees", ["/business-office/setup"], "admin", { actions: ["create", "edit", "delete"], sensitive: true }),
  pg("office", "employee-password", "Admin-Assisted Password Recovery", "Employees", "Employees", [], "admin", { actions: ["edit"], sensitive: true, dependsOn: "office.employees", carry: "office.employees.edit" }),
  pg("office", "employee-status", "Suspend or Terminate Employee", "Employees", "Employees", [], "admin", { actions: ["edit"], sensitive: true, dependsOn: "office.employees", carry: "office.employees.delete" }),
  pg("office", "employee-security", "View Employee Security History", "Employees", "Employees", [], "admin", { sensitive: true, dependsOn: "office.employees", carry: "office.access.view" }),
  pg("office", "audit-log", "Activity Log", "Administration", "Administration", ["/audit-logs"], [A], { actions: ["export"], sensitive: true }),
  pg("office", "companies", "Companies", "Administration", "Administration", ["/companies", "/business-office/companies"], "always", { actions: ["create", "edit", "delete"] }),
  pg("office", "billing", "Billing & Subscription", "Administration", "Administration", ["/business-office/billing", "/billing"], "always", { actions: ["edit"], sensitive: true }),
  pg("office", "organization", "Organization Profile", "Administration", "Administration", ["/business-office/organization-profile"], "admin", { actions: ["edit"], sensitive: true }),
]

export const PAGE_CATALOG: readonly PageDef[] = [
  ...POULTRY, ...WATER, ...GENERIC, ...HOTEL, ...RESTAURANT, ...LIVESTOCK, ...OFFICE,
]

/**
 * Pages every signed-in member of the company may open, whatever is ticked:
 * landing dashboards, your own account, help. Not grantable, not deniable.
 */
export const MEMBER_ROUTES: readonly string[] = [
  "/", "/dashboard", "/water-dashboard", "/generic-dashboard", "/hotel-dashboard", "/restaurant-dashboard", "/livestock-dashboard",
  "/business-office", "/business-office/help", "/profile", "/help", "/resources", "/support", "/terms", "/chat",
  "/poultry-setup-guide", "/poultry-videos", "/livestock-help", "/generic-setup/wizard",
]

/** Pages reachable without signing in (auth flow, marketing, public ordering). */
export const PUBLIC_ROUTES: readonly string[] = [
  "/login", "/login-2fa", "/register", "/forgot-password", "/reset-password", "/verify-account",
  "/test-email-confirmation", "/pricing", "/restaurant-order-online",
]

/** Platform operator pages: never grantable to company staff. */
export const PLATFORM_ROUTES: readonly string[] = ["/system-farms", "/platform-billing-admin"]

/** Which module a company type uses. Retail/Services profiles are Generic. */
export function moduleForCompanyType(type: string | null | undefined): PageModule | null {
  switch ((type ?? "").trim().toLowerCase()) {
    case "poultry": return "poultry"
    case "water": return "water"
    case "generic": return "generic"
    case "hotel": return "hotel"
    case "restaurant": return "restaurant"
    case "livestock": return "livestock"
    default: return null
  }
}

/** The pages an owner configures for one company: its own module plus the shared ones. */
export function pagesForCompanyType(type: string | null | undefined): PageDef[] {
  const module = moduleForCompanyType(type)
  return PAGE_CATALOG.filter((p) => p.module === "office" || p.module === module)
}

/** Every key (view + actions) a page defines. */
export function keysForPage(p: PageDef): string[] {
  return ["view", ...(p.actions ?? [])].map((a) => `${p.module}.${p.resource}.${a}`)
}

/**
 * Keys ticked by default for a brand-new employee: view and ordinary actions
 * on every non-sensitive page. Approve/reverse/delete are never defaulted —
 * a ticked page is not permission to perform privileged operations.
 */
export function defaultKeysFor(pages: readonly PageDef[]): string[] {
  const out: string[] = []
  for (const p of pages) {
    if (p.sensitive) continue
    if (p.module === "office" && p.resource !== "companies") continue
    out.push(viewKey(p))
    for (const a of p.actions ?? []) {
      if (a === "create" || a === "edit") out.push(`${p.module}.${p.resource}.${a}`)
    }
  }
  return out
}
