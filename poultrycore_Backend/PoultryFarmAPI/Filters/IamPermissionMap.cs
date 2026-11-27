using System.Text.RegularExpressions;

namespace PoultryFarmAPIWeb.Filters
{
    /// <summary>
    /// The whole access map for the Farm API, in one place (IAM phase 3).
    ///
    /// <para>
    /// There are 114 controller classes and roughly 600 endpoints. Annotating
    /// each one individually would scatter 600 unverifiable decisions across the
    /// codebase; putting them here makes the entire map readable top to bottom
    /// and reviewable in a single sitting. A controller that needs something the
    /// convention cannot express still carries an explicit
    /// <see cref="RequirePermissionAttribute"/>, which wins over this table.
    /// </para>
    ///
    /// <para>
    /// A permission key is <c>module.resource.action</c>:
    /// <list type="bullet">
    /// <item>module comes from the route prefix (<c>api/Water/…</c>) or, for the
    /// shared controllers, from the company type of the farm on the request —
    /// written <c>*</c> here and resolved per request.</item>
    /// <item>resource comes from the table below.</item>
    /// <item>action comes from the HTTP verb, overridden when the route segment
    /// names an approval or an export.</item>
    /// </list>
    /// </para>
    /// </summary>
    public static class IamPermissionMap
    {
        /// <summary>
        /// Routes that carry no permission at all: infrastructure, or endpoints
        /// that guard themselves. IAM's own controller is here because it checks
        /// office.access.* internally and must stay reachable to fix a lockout.
        /// </summary>
        private static readonly string[] Exempt =
        {
            "iam", "chat", "email", "test", "weatherforecast", "announcements",
            // Guest QR ordering. These endpoints are deliberately anonymous — the
            // person scanning a table's QR code has no account and never will.
            // Without this the IAM filter treats every one of them as an
            // "anonymous request" and 401s the whole ordering flow the moment
            // Iam:Enforced is switched on. Access is bounded instead by the QR
            // token, the per-table throttle, and the staff confirmation gate.
            "restaurant/public",
            // Missing Activity Detector (332). One report spans checks from
            // several resources (production today; driver returns, cash and
            // approvals later), and this table can name only one. The route
            // still requires authentication ([Authorize]); each check is gated
            // on its OWN permission inside ActivityCheckService, following
            // Iam:Enforced exactly as this filter does.
            "activitychecks",
            // Platform operator consoles (billing admin, CRM, ops, health,
            // analytics). They are not company pages: no company staff
            // permission applies, and they guard themselves on the platform
            // operator check. The webhook is called by the payment provider.
            "platformactivity", "platformanalytics", "platformbilling", "platformbillingadmin",
            "platformbillingwebhook", "platformcrm", "platformfarms", "platformhealth",
            "platformops", "platformrevenue",
        };

        /// <summary>
        /// Route prefix (lowercased, after "api/", route parameters removed) to
        /// permission resource. Longest prefix wins, so "poultry/raw-material-purchases"
        /// is matched before "poultry/raw-material-items" can be confused with it.
        ///
        /// "*" means "whichever module this farm is" — the shared controllers
        /// (Sale, Expense, Customer…) serve all three company types.
        /// </summary>
        private static readonly Dictionary<string, string> Map = new(StringComparer.OrdinalIgnoreCase)
        {
            // ---- Shared controllers: module resolved from the farm ----------
            ["sale"] = "*.sales",
            ["customer"] = "~*.customers",
            ["supplier"] = "~*.suppliers",
            ["expense"] = "*.expenses",
            ["cash"] = "*.cash",
            ["inventoryitem"] = "*.inventory",
            ["inventorytransaction"] = "*.stock",
            ["dashboard"] = "member",
            // 333. "Is this company's day closed?" -- module-neutral so Business
            // Office can ask it of every company; the module's own daily-closing
            // view right answers it.
            ["dailyclosingstatus"] = "*.daily-closing",
            // 362. Links a staff row to an employee login; same right as the
            // module's staff page, which is where the link is made.
            ["staffuserlink"] = "*.staff",

            // ---- Poultry, via the shared/legacy controller names -------------
            ["flock"] = "~poultry.flocks",
            // 338. Its own resource so closing a flock is not simply "can edit
            // flocks". POST = create (close); the /reverse route resolves to
            // approve (reopen) via ApproveSegments with no extra wiring.
            ["flock-closeout"] = "poultry.flock-closeout",
            ["mainflockbatch"] = "~poultry.flock-batches",
            // Migration 319. Initial Farm Setup creates batches, houses AND
            // flocks, and this table can only name one resource. It names
            // flocks because that is what the wizard ultimately produces and
            // because poultry.flocks.* certainly exists in the catalog -- a
            // brand-new "poultry.farm-setup" key would be held by no role and
            // would lock the page out the day enforcement is switched on. The
            // batch and house rights are checked explicitly inside
            // PoultryFarmSetupController, gated on Iam:Enforced.
            ["poultryfarmsetup"] = "poultry.farm-setup",
            ["house"] = "~poultry.houses",
            ["health"] = "poultry.health",
            ["feedusage"] = "poultry.feed-usage",
            ["feedinventoryadjustment"] = "poultry.stock",
            ["eggproduction"] = "poultry.egg-production",
            ["egginventoryadjustment"] = "poultry.egg-production",
            ["productionrecord"] = "poultry.production-records",
            ["productionbatchrecord"] = "poultry.batch-production",
            ["farmobservation"] = "poultry.production-records",
            ["farmproductionsettings"] = "~*.setup",

            // ---- Poultry, explicitly prefixed --------------------------------
            ["poultry/reports"] = "poultry.reports",
            ["poultry/closing-report"] = "poultry.reports-financial",
            // 481. Egg Cost & Profit Analyzer: the same right as Profit & Loss.
            // Its costing-assumption writes are additionally [SetupAdminOnly].
            ["poultry/egg-cost"] = "poultry.egg-cost-analyzer",
            ["poultry/cash-accounts"] = "poultry.cash",
            // 255 gave these three their own resources. They all rode on
            // poultry.cash until then, which meant anyone who could SEE cash
            // could reverse a transfer, record an owner draw and take out a
            // loan. 255 also copies every existing poultry.cash grant onto the
            // new keys, so nobody lost access in the move.
            //
            // KNOWN QUIRK, recorded rather than papered over: ResolveAction
            // treats /reverse as `approve` but NOT /cancel, so
            // POST /loans/{id}/cancel resolves to poultry.loans.CREATE. Widening
            // ApproveSegments would silently re-resolve every other /cancel
            // route in the API, and an explicit [RequirePermission] would make
            // this one of the first HARD-enforced endpoints while enforcement is
            // still in shadow mode. Both are phase-3 calls; .create is seeded.
            ["poultry/cash-transfers"] = "poultry.cash-transfers",
            ["poultry/owner-money"] = "poultry.owner-money",
            ["poultry/loans"] = "poultry.loans",
            ["poultry/loan-payments"] = "poultry.loans",
            // 263. Its own resource rather than an action on office.settings,
            // where farmproductionsettings sits: choosing when inventory costs
            // reach Profit & Loss is a finance decision, and the people who
            // maintain egg-pick times are not necessarily the people who should
            // be making it. Seeded to whoever already holds poultry.reports.
            ["poultry/financial-settings"] = "poultry.financial-settings",
            // Migration 223, mirroring 222 on the Water side. Its own resource
            // rather than an action on poultry.cash: *.cash has no `approve`, and
            // widening a shared resource would hand reconciliation rights to
            // everyone who can merely see cash. The /post and /reverse segments
            // resolve to the `approve` action via ResolveAction with no extra
            // wiring.
            ["poultry/cash-reconciliations"] = "poultry.cash-reconciliation",
            ["poultry/drivers"] = "~poultry.drivers",
            ["poultry/vehicles"] = "~poultry.vehicles",
            ["poultry/routes"] = "~poultry.routes",
            ["poultry/vehicle-loadings"] = "poultry.driver-returns",
            ["poultry/deliveries"] = "poultry.driver-returns",
            ["poultry/driver-returns"] = "poultry.driver-returns",
            ["poultry/driver-shortages"] = "poultry.driver-returns",
            ["poultry/driver-delivery-expenses"] = "poultry.driver-returns",
            ["poultry/feed-formulas"] = "~poultry.feed-formulas",
            ["poultry/feed-production"] = "poultry.feed-production",
            // 335. Distributing feed records feed usage on flocks' production
            // records, so it rides the existing feed-usage keys. Reversal is
            // checked explicitly against .delete in the controller.
            ["poultry/feed-distributions"] = "poultry.feed-distribution",
            // 389. Feed Usage entries: the same feed-usage keys.
            ["poultry/feed-usage-entries"] = "poultry.feed-usage",
            ["poultry/raw-material-items"] = "poultry.raw-materials",
            ["poultry/raw-material-adjustments"] = "poultry.raw-materials",
            ["poultry/raw-material-purchases"] = "poultry.supply-purchases",
            // 345. Its own resource (seeded from the raw-materials grants), so
            // reversing a whole supplier invoice is not simply "can delete a
            // purchase". POST = create; /reverse resolves to approve. Paying on
            // receipt is checked against supplier-payments.create in the controller.
            ["poultry/purchase-receipts"] = "poultry.purchase-receipts",
            // 347. Flock lifecycle plans and their reminders. GET = view, POST = create
            // (plans, assignments), PUT = edit (plans AND completing/skipping a task),
            // DELETE = delete. Seeded from the poultry.flocks grants.
            ["poultry/lifecycle"] = "poultry.lifecycle",
            // 348. Recurring expenses are expenses: ride the module's own expenses
            // resource, so every company type gates them the way it gates its
            // Expenses page. POST .../record (not /post) keeps posting a draft on
            // the create right rather than approve.
            ["recurring-expenses"] = "*.recurring-expenses",
            // 337. How long the stock lasts is part of seeing the stock.
            ["poultry/stock-supply"] = "poultry.restock-forecast",
            // 338. Flock anomaly alerts: a flock dying, laying less or eating
            // differently is flock health. view = see alerts and why; create =
            // acknowledge / note / resolve / rescan; edit = thresholds.
            ["poultry/flock-alerts"] = "poultry.alerts",
            // 339. Treatment campaigns record medication given to flocks:
            // flock health. view = see campaigns and history; create = new
            // campaign / record a day; edit = product dose settings, complete,
            // cancel. Reversal is checked explicitly against .delete in the
            // controller.
            ["poultry/treatment-campaigns"] = "poultry.treatment-campaigns",
            // 400. Weigh-ins are a daily flock record, like production records,
            // and are kept by the same people. GET view, POST create, PUT edit,
            // DELETE delete (soft, with a reason).
            ["poultry/weigh-ins"] = "poultry.weigh-ins",
            // 341-343. Egg Sorting Workspace: its own resource. view = workspace,
            // ledger, reports; create = save / commit a sorting; edit = sizes
            // and settings; delete = discard a draft. Reversal is a POST to
            // {id}/reversal (not "reverse", which would resolve to .approve)
            // and is checked explicitly against .delete in the controller.
            ["poultry/egg-sorting"] = "poultry.egg-sorting",
            // 268. A read-only view of the same stock, valued two ways. It is
            // the raw materials it values, so it rides their resource rather
            // than inventing a permission nobody has been granted.
            ["poultry/inventory-valuation"] = "poultry.raw-materials",
            // 273. Two resources, not one: recording a vehicle and charging the
            // P&L for it are different decisions and belong to different people.
            // The /reverse and /dispose segments resolve to approve and delete
            // through ResolveAction with no extra wiring here.
            ["poultry/assets"] = "poultry.assets",
            ["poultry/asset-depreciation"] = "poultry.assets",
            // The structured P&L and its drilldowns are the reports resource.
            ["poultry/profit-loss"] = "poultry.profit-loss",
            ["poultry/raw-material-usage"] = "poultry.raw-materials",
            ["poultry/payments"] = "poultry.payments",
            ["poultry/products"] = "~poultry.products",
            ["poultry/stock"] = "poultry.stock",
            // 441. Batch Bird Count: setting every flock of a batch to its counted
            // birds is its own right, not simply "can add a stock movement".
            // GET sheet = view, POST = create. Longest prefix wins over poultry/stock.
            ["poultry/stock/bird-count"] = "poultry.bird-count",
            // 413. Reconciling a batch's birds is part of managing the batch.
            ["poultry/bird-reconciliation"] = "poultry.flock-batches",
            ["poultry/production-batches"] = "poultry.batch-production",
            ["poultry/production-losses"] = "poultry.loss-records",
            ["poultry/loss-records"] = "poultry.loss-records",
            ["poultry/internal-usage"] = "poultry.internal-use",
            ["poultry/daily-closings"] = "poultry.daily-closing",
            ["poultry/staff"] = "poultry.staff",
            ["poultry/staff-attendance"] = "poultry.staff",
            ["poultry/payroll-runs"] = "poultry.payroll",

            // Migrations 222-224 and 238: the balance / payment-allocation pages.
            // Previously UNMAPPED, which meant IamEnforcementFilter could not say
            // anything about them at all -- and, with Iam:DenyUnmapped on, would
            // have refused them outright.
            //
            // KNOWN MISMATCH, left as-is deliberately: ResolveAction turns the
            // /reverse segment into the `approve` action, but 222 seeded the key
            // as supplier-payments.REVERSE. So reversal resolves to
            // poultry.supplier-payments.approve, which is not in the catalog.
            // Harmless while enforcement is in shadow mode (the default); before
            // Iam:Enforced is switched on, either seed the .approve keys or put
            // [RequirePermission("poultry.supplier-payments.reverse")] on the two
            // reverse actions. Doing the latter now would make them the first
            // hard-enforced endpoints in the API, which is a phase-3 decision.
            ["poultry/customer-balances"] = "poultry.customer-balances",
            ["poultry/supplier-balances"] = "poultry.supplier-balances",
            ["poultry/customer-payments"] = "poultry.payments",
            ["poultry/supplier-payments"] = "poultry.supplier-payments",
            ["poultry/balances"] = "poultry.supplier-balances",

            // ---- Livestock (458+) ----------------------------------------------
            // Each key mirrors a poultry twin (splivestock_iammirror): pens <-
            // houses, groups/animals <- flocks, batches <- flock-batches.
            ["livestock/species"] = "~livestock.species",
            ["livestock/pens"] = "~livestock.pens",
            ["livestock/company"] = "~livestock.setup",   // 467, as water/company
            ["livestock/batches"] = "~livestock.batches",
            ["livestock/groups"] = "~livestock.groups",
            ["livestock/animals"] = "~livestock.animals",
            ["livestock/overview"] = "~livestock.groups",
            // 459
            ["livestock/items"] = "livestock.items",
            ["livestock/stock"] = "livestock.animal-stock",
            ["livestock/production-records"] = "livestock.production-records",
            ["livestock/breeding"] = "livestock.breeding",
            ["livestock/weigh-ins"] = "livestock.weigh-ins",
            // 460
            ["livestock/health"] = "livestock.health",
            ["livestock/vaccination"] = "livestock.vaccination",
            ["livestock/treatments"] = "livestock.treatments",
            ["livestock/feed-formulas"] = "~livestock.feed-formulas",
            ["livestock/feed-production"] = "livestock.feed-production",
            // Feeding many groups writes their daily records.
            ["livestock/feed-distribution"] = "livestock.feed-distribution",
            ["livestock/feed-supply"] = "livestock.feed-supply",
            ["livestock/alerts"] = "livestock.alerts",
            // 461
            ["livestock/cash-accounts"] = "livestock.cash",
            ["livestock/purchases"] = "livestock.purchases",
            ["livestock/supplier-payments"] = "livestock.supplier-payments",
            ["livestock/supplier-balances"] = "livestock.supplier-balances",
            ["livestock/losses"] = "livestock.losses",
            ["livestock/head-count"] = "livestock.head-count",
            ["livestock/animal-stock"] = "livestock.animal-stock",
            // 462
            ["livestock/sales"] = "livestock.sales",
            ["livestock/customer-payments"] = "livestock.payments",
            ["livestock/customer-balances"] = "livestock.customer-balances",
            ["livestock/expenses"] = "livestock.expenses",
            // 463
            ["livestock/cash-transfers"] = "livestock.cash-transfers",
            ["livestock/cash-reconciliation"] = "livestock.cash-reconciliation",
            ["livestock/staff"] = "livestock.staff",
            ["livestock/payroll"] = "livestock.payroll",
            ["livestock/staff-loans"] = "livestock.payroll",
            ["livestock/owner-money"] = "livestock.owner-money",
            ["livestock/loans"] = "livestock.loans",
            ["livestock/assets"] = "livestock.assets",
            ["livestock/reports"] = "livestock.reports",
            // 464
            ["livestock/daily-closing"] = "livestock.daily-closing",
            ["livestock/missing-records"] = "livestock.missing-records",
            ["livestock/drivers"] = "~livestock.drivers",
            ["livestock/vehicles"] = "~livestock.drivers",
            ["livestock/routes"] = "~livestock.drivers",
            ["livestock/deliveries"] = "livestock.deliveries",
            ["livestock/driver-returns"] = "livestock.deliveries",

            // ---- Water --------------------------------------------------------
            ["water/company"] = "~water.setup",
            ["water/farm-settings"] = "~water.setup",
            ["water/products"] = "~water.products",
            ["water/customers"] = "~water.customers",
            ["water/stock"] = "water.stock",
            ["water/internal-usage"] = "water.internal-use",
            ["water/sales"] = "water.sales",
            ["water/payments"] = "water.payments",
            ["water/suppliers"] = "~water.suppliers",
            ["water/dashboard"] = "member",
            ["water/reports"] = "water.reports",
            ["water/financial-activity"] = "water.financial-activity",   // 461: read-only timeline
            ["water/closing-report"] = "water.reports-financial",   // 463: Closing by Category
            ["water/alerts"] = "water.alerts",   // 465: Alerts
            ["water/drivers"] = "~water.drivers",
            ["water/vehicles"] = "~water.vehicles",
            ["water/routes"] = "~water.routes",
            ["water/vehicle-loadings"] = "water.driver-returns",
            ["water/driver-returns"] = "water.driver-returns",
            ["water/driver-shortages"] = "water.driver-returns",
            ["water/expenses"] = "water.expenses",
            ["water/expense-categories"] = "water.expenses",
            ["water/cash-accounts"] = "water.cash",
            // 260 gave these four their own resources, mirroring what 255 did on
            // the poultry side. Cash Transfers rode on water.cash until then,
            // and Owner Money and Loans would have inherited the same mapping
            // the moment their routes appeared -- which would have meant anyone
            // who could SEE cash could reverse a transfer, record an owner draw
            // and take out a loan. 260 also copies every existing water.cash
            // grant onto the new keys, so nobody lost access in the move.
            //
            // KNOWN QUIRK, recorded rather than papered over: ResolveAction
            // treats /reverse as `approve` but NOT /cancel, so
            // POST /loans/{id}/cancel resolves to water.loans.CREATE. Same
            // trade-off, and same open decision, as the poultry note above.
            ["water/cash-transfers"] = "water.cash-transfers",
            ["water/owner-money"] = "water.owner-money",
            ["water/loans"] = "water.loans",
            ["water/loan-payments"] = "water.loans",
            // 276. Its own resource rather than an action on office.settings,
            // where water/company and water/farm-settings sit: choosing when
            // inventory costs reach Profit & Loss is a finance decision, and the
            // people who maintain machine allocation are not necessarily the
            // people who should be making it.
            ["water/financial-settings"] = "water.financial-settings",
            // 286. Two resources, not one: recording a delivery truck and
            // charging the P&L for it are different decisions and belong to
            // different people. The /reverse and /dispose segments resolve to
            // approve and delete through ResolveAction with no extra wiring here.
            ["water/assets"] = "water.assets",
            ["water/asset-depreciation"] = "water.assets",
            // Migration 222. Its own resource rather than an action on
            // water.cash: *.cash has no `approve`, and widening a shared
            // resource would hand reconciliation rights to everyone who can
            // merely see cash. The /post and /reverse segments resolve to the
            // `approve` action via ResolveAction with no extra wiring.
            ["water/cash-reconciliations"] = "water.cash-reconciliation",
            ["water/daily-closings"] = "water.daily-closing",
            ["water/loss-records"] = "water.loss-records",
            ["water/production-batches"] = "water.production-batches",
            ["water/production-losses"] = "water.production-losses",
            ["water/boreholes"] = "~water.boreholes",
            ["water/machines"] = "~water.machines",
            ["water/maintenance-logs"] = "water.maintenance",
            ["water/quality-tests"] = "water.production-batches",
            ["water/pumping-logs"] = "water.production-batches",
            // Migrations 222/227 -- see the poultry note above, including the
            // reverse/approve mismatch.
            ["water/customer-balances"] = "water.customer-balances",
            ["water/supplier-balances"] = "water.supplier-balances",
            ["water/customer-payments"] = "water.payments",
            ["water/supplier-payments"] = "water.supplier-payments",
            ["water/balances"] = "water.supplier-balances",
            ["water/raw-material-items"] = "water.inventory",
            ["water/raw-material-adjustments"] = "water.inventory",
            ["water/raw-material-purchases"] = "water.supply-purchases",
            ["water/purchase-receipts"] = "water.purchase-receipts",   // 462: Receive Purchase
            ["water/stock-supply"] = "water.restock-forecast",   // 464: Restock Forecast
            ["water/raw-material-usage"] = "water.inventory",
            ["water/staff"] = "water.staff",
            ["water/staff-attendance"] = "water.staff",
            ["water/payroll-runs"] = "water.payroll",

            // ---- Generic company ---------------------------------------------
            // The route carries the farm id ("api/generic-company/{farmId}/sales"),
            // which Normalize strips before matching.
            // bare "generic-company" removed by the page-access upgrade: every sub-route is mapped explicitly.
            ["generic-company/products"] = "~generic.products",
            ["generic-company/service-catalog"] = "~generic.products",
            ["generic-company/inventory"] = "generic.inventory",
            ["generic-company/internal-usage"] = "generic.internal-use",
            ["generic-company/suppliers"] = "~generic.suppliers",
            ["generic-company/purchases"] = "generic.inventory",
            ["generic-company/expenses"] = "generic.expenses",
            ["generic-company/cash"] = "generic.cash",
            ["generic-company/cash-transfers"] = "generic.cash-transfers",
            ["generic-company/daily-closings"] = "generic.daily-closing",
            ["generic-company/reports"] = "generic.reports",
            ["generic-company/customers"] = "~generic.customers",
            ["generic-company/sales"] = "generic.sales",
            ["generic-company/staff"] = "generic.staff",
            ["generic-company/staff-attendance"] = "generic.attendance",
            ["generic-company/payroll-runs"] = "generic.payroll",
            ["generic-company/service-plans"] = "generic.subscription-plans",
            ["generic-company/subscriptions"] = "generic.subscriptions",
            ["generic-company/billing-runs"] = "generic.billing-runs",
            ["generic-company/invoices"] = "generic.invoices",
            ["generic-company/recurring-expenses"] = "generic.recurring-expenses",
            ["generic-company/staff-payments"] = "generic.payroll",
            ["generic-company/owner-entries"] = "generic.owner-money",
            // 482: Projects & Contracts. Longest prefix wins, so the sub-routes
            // below beat the bare register entry.
            ["generic-company/projects"] = "generic.projects",
            ["generic-company/projects/options"] = "generic.project-allocations",
            ["generic-company/projects/financials"] = "generic.project-financials",
            ["generic-company/projects/budget"] = "generic.projects",
            ["generic-company/projects/budget-categories"] = "generic.projects",
            ["generic-company/projects/milestones"] = "generic.projects",
            ["generic-company/projects/reservations"] = "generic.projects",
            ["generic-company/project-reservations"] = "generic.projects",
            ["generic-company/project-allocations"] = "generic.project-allocations",
            ["generic-company/module-settings"] = "~generic.setup",
            ["generic-company/business-settings"] = "~generic.setup",
            ["generic-company/business-template"] = "~generic.setup",
            // The balance endpoints sit one segment down from the older
            // customer-payments document routes, which already exist and mean
            // something else. Both prefixes are mapped so neither lands in the
            // unmapped bucket -- the bare "generic-company" entry above would
            // otherwise catch them and call them office.companies.
            ["generic-company/balances"] = "generic.customer-balances",
            ["generic-company/balances/customer-balances"] = "generic.customer-balances",
            ["generic-company/balances/customer-payments"] = "generic.payments",
            ["generic-company/balances/customers"] = "generic.customer-balances",
            ["generic-company/balances/supplier-balances"] = "generic.supplier-balances",
            ["generic-company/balances/supplier-payments"] = "generic.supplier-payments",
            ["generic-company/balances/suppliers"] = "generic.supplier-balances",
            ["generic-company/customer-payments"] = "generic.payments",
            ["business-categories"] = "member",

            // ---- Business office ----------------------------------------------
            ["businessoffice"] = "office.organization",
            ["auditlogs"] = "office.audit-log",

            // ---- Page access upgrade: every remaining route, keyed to its page ----
            ["companytime"] = "member",
            ["userquicklinks"] = "member",
            ["poultry/cash-flow"] = "poultry.cash-flow",
            ["poultry/financial-activity"] = "poultry.financial-activity",
            ["poultry/company"] = "~poultry.setup",
            ["poultry/customer-debts"] = "poultry.customer-balances",
            ["poultry/customers"] = "~poultry.customers",
            ["poultry/suppliers"] = "~poultry.suppliers",
            ["poultry/deferred-inventory-costs"] = "poultry.deferred-costs",
            ["poultry/employee-credit"] = "poultry.employee-credit",
            ["poultry/employee-loans"] = "poultry.employee-loans",
            ["poultry/payroll-deductions"] = "poultry.payroll",
            ["poultry/payroll-templates"] = "poultry.payroll",
            ["poultry/supplier-credits"] = "poultry.supplier-credits",
            ["poultry/supplier-debts"] = "poultry.supplier-balances",
            ["livestock/cash-flow"] = "livestock.cash-flow",
            ["livestock/profit-loss"] = "livestock.profit-loss",
            ["livestock/customers"] = "~livestock.customers",
            ["livestock/suppliers"] = "~livestock.suppliers",
            ["water/cash-flow"] = "water.cash-flow",
            ["water/profit-loss"] = "water.profit-loss",
            ["water/customer-debts"] = "water.customer-balances",
            ["water/daily-productions"] = "water.daily-production",
            ["water/deferred-inventory-costs"] = "water.deferred-costs",
            ["water/delivery-expenses"] = "water.driver-returns",
            ["water/employee-credit"] = "water.employee-credit",
            ["water/employee-loans"] = "water.employee-loans",
            ["water/payroll-deductions"] = "water.payroll",
            ["water/supplier-credits"] = "water.supplier-credits",
            ["water/supplier-debts"] = "water.supplier-balances",
            ["waterproductionlines"] = "water.production-batches",
            ["generic/asset-depreciation"] = "generic.assets",
            ["generic/assets"] = "generic.assets",
            ["generic/deferred-inventory-costs"] = "generic.deferred-costs",
            ["generic/employee-credit"] = "generic.employee-credit",
            ["generic/employee-loans"] = "generic.employee-loans",
            ["generic/payroll-deductions"] = "generic.payroll",
            ["generic/payroll-runs"] = "generic.payroll",
            ["generic/payroll-templates"] = "generic.payroll",
            ["generic/supplier-credits"] = "generic.supplier-credits",
            ["generic/supplier-debts"] = "generic.supplier-balances",
            ["hotel/asset-depreciation"] = "hotel.assets",
            ["hotel/assets"] = "hotel.assets",
            ["hotel/availability"] = "hotel.availability",
            ["hotel/balances"] = "hotel.customer-balances",
            ["hotel/balances/audit"] = "hotel.customer-balances",
            ["hotel/balances/customer-balances"] = "hotel.customer-balances",
            ["hotel/balances/customer-payments"] = "hotel.payments",
            ["hotel/balances/customers"] = "hotel.customer-balances",
            ["hotel/balances/supplier-balances"] = "hotel.supplier-balances",
            ["hotel/balances/supplier-payments"] = "hotel.supplier-payments",
            ["hotel/balances/suppliers"] = "hotel.supplier-balances",
            ["hotel/billing"] = "hotel.billing",
            ["hotel/bookings"] = "hotel.bookings",
            ["hotel/cash-flow"] = "hotel.cash-flow",
            ["hotel/cash-reconciliations"] = "hotel.cash-reconciliation",
            ["hotel/cash-transfers"] = "hotel.cash-transfers",
            ["hotel/checkin-history"] = "hotel.check-in",
            ["hotel/checkout-history"] = "hotel.check-in",
            ["hotel/communications"] = "hotel.guest-services",
            ["hotel/customer-payments"] = "hotel.payments",
            ["hotel/customers"] = "~hotel.customers",
            ["hotel/custom-options"] = "member",
            ["hotel/dashboard"] = "member",
            ["hotel/deferred-inventory-costs"] = "hotel.deferred-costs",
            ["hotel/deposits"] = "hotel.billing",
            ["hotel/employee-loan-repayments"] = "hotel.employee-loans",
            ["hotel/employee-loans"] = "hotel.employee-loans",
            ["hotel/finance/cash-accounts"] = "hotel.cash",
            ["hotel/finance/cash-adjustments"] = "hotel.cash",
            ["hotel/finance/cash-transactions"] = "hotel.cash",
            ["hotel/finance/expense-categories"] = "hotel.expenses",
            ["hotel/finance/expenses"] = "hotel.expenses",
            ["hotel/financial-activity"] = "hotel.financial-activity",
            ["hotel/folio"] = "hotel.guest-folio",
            ["hotel/front-desk"] = "hotel.check-in",
            ["hotel/guest-requests"] = "hotel.guest-services",
            ["hotel/guests"] = "hotel.guests",
            ["hotel/housekeeping"] = "hotel.housekeeping",
            ["hotel/housekeeping-schedule"] = "hotel.housekeeping-schedule",
            ["hotel/internal-usage"] = "hotel.internal-use",
            ["hotel/inventory"] = "hotel.inventory",
            ["hotel/loan-payments"] = "hotel.loans",
            ["hotel/loans"] = "hotel.loans",
            ["hotel/lost-and-found"] = "hotel.guest-services",
            ["hotel/loyalty"] = "hotel.guests",
            ["hotel/maintenance"] = "hotel.maintenance",
            ["hotel/night-audit"] = "hotel.night-audit",
            ["hotel/owner-money"] = "hotel.owner-money",
            ["hotel/payroll-diag"] = "hotel.payroll",
            ["hotel/payroll-runs"] = "hotel.payroll",
            ["hotel/profit-loss"] = "hotel.profit-loss",
            ["hotel/reports"] = "hotel.reports",
            ["hotel/reports/daily-closings"] = "hotel.daily-closing",
            ["hotel/restaurant"] = "hotel.restaurant",
            ["hotel/room-rates"] = "~hotel.rooms",
            ["hotel/rooms"] = "~hotel.rooms",
            ["hotel/sales"] = "hotel.sales",
            ["hotel/setup"] = "~hotel.setup",
            ["hotel/shift-handovers"] = "hotel.availability",
            ["hotel/staff"] = "hotel.staff",
            ["hotel/stay-history"] = "hotel.stay-history",
            ["hotel/supplier-payments"] = "hotel.supplier-payments",
            ["hotel/suppliers"] = "~hotel.suppliers",
            ["hotel/supplies"] = "hotel.inventory",
            ["restaurant/asset-depreciation"] = "restaurant.assets",
            ["restaurant/assets"] = "restaurant.assets",
            ["restaurant/balances"] = "restaurant.customer-balances",
            ["restaurant/cash-flow"] = "restaurant.cash-flow",
            ["restaurant/crm"] = "restaurant.crm",
            ["restaurant/customer-balances"] = "restaurant.customer-balances",
            ["restaurant/customer-payments"] = "restaurant.payments",
            ["restaurant/customers"] = "~restaurant.crm",
            ["restaurant/custom-options"] = "member",
            ["restaurant/deferred-inventory-costs"] = "restaurant.deferred-costs",
            ["restaurant/delivery"] = "restaurant.delivery",
            ["restaurant/events"] = "restaurant.extras",
            ["restaurant/expenses"] = "restaurant.expenses",
            ["restaurant/finance/accounts"] = "restaurant.cash",
            ["restaurant/finance/counts"] = "restaurant.cash-reconciliation",
            ["restaurant/finance/daily-closing"] = "restaurant.daily-closing",
            ["restaurant/finance/ledger"] = "restaurant.financial-activity",
            ["restaurant/finance/loans"] = "restaurant.loans",
            ["restaurant/finance/owner-money"] = "restaurant.owner-money",
            ["restaurant/finance/pnl-lines"] = "restaurant.profit-loss",
            ["restaurant/finance/reports"] = "restaurant.reports",
            ["restaurant/finance/shifts"] = "restaurant.tills",
            ["restaurant/finance/transfers"] = "restaurant.cash-transfers",
            ["restaurant/financial-activity"] = "restaurant.financial-activity",
            ["restaurant/floor"] = "~restaurant.floor-plan",
            ["restaurant/gift-cards"] = "restaurant.extras",
            ["restaurant/internal-usage"] = "restaurant.internal-use",
            ["restaurant/inventory"] = "restaurant.inventory",
            ["restaurant/kds"] = "restaurant.kitchen",
            ["restaurant/loyalty"] = "restaurant.crm",
            ["restaurant/menu"] = "~restaurant.menu",
            ["restaurant/notifications"] = "restaurant.extras",
            ["restaurant/online"] = "restaurant.online-orders",
            ["restaurant/orders"] = "restaurant.pos",
            ["restaurant/payroll"] = "restaurant.payroll",
            ["restaurant/purchases"] = "restaurant.inventory",
            ["restaurant/reports"] = "restaurant.reports",
            ["restaurant/reservations"] = "restaurant.reservations",
            ["restaurant/setup"] = "~restaurant.setup",
            ["restaurant/staff"] = "restaurant.staff",
            ["restaurant/staff-loans"] = "restaurant.employee-loans",
            ["restaurant/supplier-balances"] = "restaurant.supplier-balances",
            ["restaurant/supplier-payments"] = "restaurant.supplier-payments",
            ["restaurant/suppliers"] = "~restaurant.suppliers",
            ["generic-company"] = "~generic.setup",
            ["generic-company/setup"] = "~generic.setup",
            ["generic-company/academic-terms"] = "~generic.school",
            ["generic-company/classes"] = "~generic.school",
            ["generic-company/customer-attendance"] = "generic.school",
            ["generic-company/assets"] = "generic.assets",
            ["generic-company/bulk-payments"] = "generic.payments",
            ["generic-company/cash-accounts"] = "~generic.cash",
            ["generic-company/cash-flow"] = "generic.cash-flow",
            ["generic-company/financial-activity"] = "generic.financial-activity",
            ["generic-company/coupons"] = "~generic.coupons",
            ["generic-company/credit-applications"] = "generic.customer-credits",
            ["generic-company/credit-refunds"] = "generic.customer-credits",
            ["generic-company/customer-credits"] = "generic.customer-credits",
            ["generic-company/supplier-credits"] = "generic.supplier-credits",
            ["generic-company/supplier-payments"] = "generic.supplier-payments",
            ["generic-company/deferred-costs"] = "generic.deferred-costs",
            ["generic-company/deliveries"] = "generic.deliveries",
            ["generic-company/drivers"] = "~generic.drivers",
            ["generic-company/routes"] = "~generic.drivers",
            ["generic-company/invoice-documents"] = "generic.invoices",
            ["generic-company/late-fees"] = "generic.invoices",
            ["generic-company/loans"] = "generic.loans",
            ["generic-company/customer-types"] = "member",
            ["generic-company/supplier-types"] = "member",
            ["generic-company/payment-methods"] = "member",
            ["generic-company/expense-categories"] = "~generic.expenses",
            ["generic-company/product-categories"] = "~generic.products",
            ["generic-company/service-categories"] = "~generic.products",
            ["generic-company/services"] = "~generic.products",
            ["generic-company/units"] = "~generic.products",
            ["generic-company/uom-conversions"] = "~generic.products",
            ["generic-company/production-records"] = "generic.products",
        };

        /// <summary>Route segments that mean "approve", whatever the HTTP verb.</summary>
        private static readonly string[] ApproveSegments =
        {
            "approve", "unapprove", "post", "unpost", "confirm", "authorize", "release",
        };

        /// <summary>
        /// Route segments that undo a posted record. Their own action since the
        /// page-access upgrade, so "may approve" and "may reverse" can differ;
        /// a page without a .reverse key falls back to .approve (see
        /// <see cref="FallbackActions"/>).
        /// </summary>
        private static readonly string[] ReverseSegments = { "reverse", "void", "unwind" };

        /// <summary>
        /// When the catalog has no key for the resolved action, the next action
        /// that must be held instead — always an equal-or-stronger one, never a
        /// weaker one, so a missing key can never turn "approve" into "view".
        /// </summary>
        public static readonly IReadOnlyDictionary<string, string[]> FallbackActions = new Dictionary<string, string[]>
        {
            ["view"] = Array.Empty<string>(),
            ["create"] = new[] { "edit" },
            ["edit"] = Array.Empty<string>(),
            ["delete"] = new[] { "edit" },
            ["approve"] = new[] { "edit" },
            ["reverse"] = new[] { "approve", "delete", "edit" },
            ["export"] = new[] { "view" },
        };

        /// <summary>
        /// Writes every member makes as a side effect of using the app, whatever
        /// pages they hold: the browser recording an activity-log entry.
        /// </summary>
        private static readonly HashSet<string> MemberWrites = new(StringComparer.OrdinalIgnoreCase) { "POST auditlogs" };

        private static readonly HashSet<string> ExactOnly = new(StringComparer.OrdinalIgnoreCase) { "generic-company" };

        /// <summary>The resource value for routes any active member may call (dashboards, settings lookups).</summary>
        public const string MemberResource = "member";

        /// <summary>
        /// Prefix on a resource meaning "reads are member-level": reference lists
        /// (customers, products, routes, room types…) that operational pages
        /// need even when the person cannot open the list's own page. Changes
        /// still need the resource's create/edit/delete key.
        /// </summary>
        public const string MemberReadPrefix = "~";

        private static readonly Regex RouteParam = new(@"\{[^}]*\}", RegexOptions.Compiled);

        /// <summary>
        /// Strip "api/", route parameters and empty segments so a template like
        /// "api/generic-company/{farmId}/sales/{id:int}" matches the table entry
        /// "generic-company/sales".
        /// </summary>
        public static string Normalize(string? routeTemplate)
        {
            if (string.IsNullOrWhiteSpace(routeTemplate)) return string.Empty;

            var withoutParams = RouteParam.Replace(routeTemplate, string.Empty);
            var segments = withoutParams
                .Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Where(s => !string.Equals(s, "api", StringComparison.OrdinalIgnoreCase))
                .ToList();

            return string.Join('/', segments).ToLowerInvariant();
        }

        /// <summary>
        /// Matches a whole route segment prefix, not just the first segment.
        ///
        /// This used to compare only <c>route.Split('/')[0]</c>, which meant a
        /// multi-segment entry such as "restaurant/public" could never match
        /// anything — it silently did nothing, so exempting one branch of a
        /// controller family was impossible. Comparing on segment boundaries
        /// keeps that from becoming an accidental wildcard: "restaurant/public"
        /// exempts "restaurant/public/menu" but never "restaurant/publicity".
        /// </summary>
        public static bool IsExempt(string normalizedRoute)
        {
            if (string.IsNullOrEmpty(normalizedRoute)) return true;
            return Exempt.Any(e =>
                normalizedRoute.Equals(e, StringComparison.OrdinalIgnoreCase) ||
                normalizedRoute.StartsWith(e + "/", StringComparison.OrdinalIgnoreCase));
        }

        /// <summary>
        /// The resource for a route, or null when nothing matches. Longest prefix
        /// wins so more specific entries beat their parents.
        /// </summary>
        public static string? ResolveResource(string normalizedRoute)
        {
            if (string.IsNullOrEmpty(normalizedRoute)) return null;

            if (Map.TryGetValue(normalizedRoute, out var exact)) return exact;

            string? best = null;
            var bestLength = -1;
            foreach (var (prefix, resource) in Map)
            {
                if (prefix.Length <= bestLength) continue;
                // Bare controller roots match only themselves, never as a
                // catch-all prefix — an unmapped sub-route must surface in the
                // route-map test instead of silently inheriting the root's key.
                if (ExactOnly.Contains(prefix) && !normalizedRoute.Equals(prefix, StringComparison.OrdinalIgnoreCase)) continue;
                if (!normalizedRoute.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) continue;
                // Only match on a segment boundary, so "water/stock" cannot be
                // matched by a route like "water/stocktake".
                if (normalizedRoute.Length > prefix.Length && normalizedRoute[prefix.Length] != '/') continue;
                best = resource;
                bestLength = prefix.Length;
            }

            if (best is not null) return best;

            // Generic company routes carry the farm id as the second segment, so
            // "generic-company/sales" only appears after Normalize strips it. If a
            // literal id slipped through, retry without that segment.
            var parts = normalizedRoute.Split('/');
            if (parts.Length >= 3 && string.Equals(parts[0], "generic-company", StringComparison.OrdinalIgnoreCase))
            {
                var collapsed = string.Join('/', new[] { parts[0] }.Concat(parts.Skip(2)));
                if (Map.TryGetValue(collapsed, out var viaCollapse)) return viaCollapse;
            }

            return null;
        }

        /// <summary>
        /// Action for a request. The HTTP verb decides, except where the route
        /// names an approval or an export — those are separate permissions
        /// precisely because "can post a payroll run" is not "can edit one".
        /// </summary>
        public static string ResolveAction(string httpMethod, string normalizedRoute)
        {
            var segments = normalizedRoute.Split('/', StringSplitOptions.RemoveEmptyEntries);

            if (segments.Any(s => s.Contains("export", StringComparison.OrdinalIgnoreCase)))
                return "export";

            if (segments.Any(s => ReverseSegments.Contains(s, StringComparer.OrdinalIgnoreCase)))
                return "reverse";

            if (segments.Any(s => ApproveSegments.Contains(s, StringComparer.OrdinalIgnoreCase)))
                return "approve";

            return httpMethod.ToUpperInvariant() switch
            {
                "GET" or "HEAD" or "OPTIONS" => "view",
                "POST" => "create",
                "PUT" or "PATCH" => "edit",
                "DELETE" => "delete",
                _ => "view",
            };
        }

        /// <summary>
        /// Build the key for a request, substituting the module for a "*" resource.
        /// Returns null when the route is unmapped or the module is unknown.
        /// </summary>
        /// <summary>
        /// What a request needs: nothing beyond membership (<c>MemberOnly</c>),
        /// a permission key, or nothing resolvable (<c>Key</c> null).
        /// </summary>
        public sealed record Requirement(bool MemberOnly, string? Key);

        public static Requirement? Resolve(string normalizedRoute, string httpMethod, string? moduleForFarm)
        {
            var resource = ResolveResource(normalizedRoute);
            if (resource is null) return null;
            if (resource == MemberResource) return new Requirement(true, null);

            var action = ResolveAction(httpMethod, normalizedRoute);
            if (MemberWrites.Contains($"{httpMethod.ToUpperInvariant()} {normalizedRoute}")) return new Requirement(true, null);
            if (resource.StartsWith(MemberReadPrefix, StringComparison.Ordinal))
            {
                if (action == "view") return new Requirement(true, null);
                resource = resource[MemberReadPrefix.Length..];
            }

            if (resource.StartsWith("*.", StringComparison.Ordinal))
            {
                if (string.IsNullOrWhiteSpace(moduleForFarm)) return new Requirement(false, null);
                resource = string.Concat(moduleForFarm, resource.AsSpan(1));
            }

            return new Requirement(false, $"{resource}.{action}");
        }

        /// <summary>Strip the member-read marker, for callers that only want the resource.</summary>
        public static string? ResourceOf(string normalizedRoute)
        {
            var r = ResolveResource(normalizedRoute);
            return r is not null && r.StartsWith(MemberReadPrefix, StringComparison.Ordinal) ? r[MemberReadPrefix.Length..] : r;
        }

        public static string? BuildKey(string normalizedRoute, string httpMethod, string? moduleForFarm)
        {
            var resource = ResourceOf(normalizedRoute);
            if (resource is null || resource == MemberResource) return null;

            if (resource.StartsWith("*.", StringComparison.Ordinal))
            {
                if (string.IsNullOrWhiteSpace(moduleForFarm)) return null;
                resource = string.Concat(moduleForFarm, resource.AsSpan(1));
            }

            return $"{resource}.{ResolveAction(httpMethod, normalizedRoute)}";
        }
    }
}
