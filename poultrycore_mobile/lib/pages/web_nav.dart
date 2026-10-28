// GENERATED from the web's navigation: top-level sections, their
// sub-groups, order and labels all match the site.
//
// specKey is null unless the endpoint is a confident match for the page.
// A weak match used to send 'Farm Setup' to the farm-summary REPORT,
// which rendered real figures from the wrong page and read as invented
// data. Unmatched links now open an honest 'not built yet' screen.

class NavLink {
  const NavLink(this.label, this.href, this.specKey);
  final String label;
  final String href;
  final String? specKey;
}

class NavSubGroup {
  const NavSubGroup(this.title, this.links);
  final String title;
  final List<NavLink> links;
}

class NavGroup {
  const NavGroup(this.title, this.subGroups);
  final String title;
  final List<NavSubGroup> subGroups;

  int get count => subGroups.fold(0, (n, g) => n + g.links.length);
}

const Map<String, List<NavGroup>> webNavGroups = {
  'poultry': [
    NavGroup('Quick Links', [
      NavSubGroup('', [
        NavLink('Production Records', '/production-records', null),
        // The Egg Sorting Workspace; the legacy /egg-production page is hidden
        // from the menus (its URL still works).
        NavLink('Egg sorting', '/poultry-egg-sorting', null),
        NavLink('Supply Purchases', '/poultry-supply-purchases', null),
        NavLink('Sales', '/sales', 'sales'),
        NavLink('Customer Payments', '/poultry-payments', 'poultry-payments'),
        NavLink('Customer Balances', '/customer-balances', 'poultry-customer-balances'),
        NavLink('Expenses', '/expenses', null),
        NavLink('Cash Flow', '/cash-flow', null),
        NavLink('Profit & Loss', '/poultry-profit-loss', null),
        NavLink('Daily Closing', '/poultry-daily-closing', 'poultry-daily-closings'),
      ]),
    ]),
    NavGroup('Operations', [
      NavSubGroup('Production', [
        NavLink('Production Records', '/production-records', null),
        NavLink('Batch Production', '/batch-production-records', null),
        NavLink('Egg Sorting', '/poultry-egg-sorting', null),
        NavLink('Feed Usage', '/feed-usage', null),
        NavLink('Feed Production', '/poultry-feed-production', null),
      ]),
      NavSubGroup('Inventory & Health', [
        NavLink('Inventory', '/poultry-inventory', null),
        NavLink('Stock movements', '/poultry-stock', null),
        NavLink('Inventory & Supply Purchases', '/poultry-supply-purchases', null),
        NavLink('Health Records', '/health', null),
        NavLink('Loss & Damage', '/poultry-loss-records', null),
      ]),
      NavSubGroup('Delivery', [
        NavLink('Deliveries', '/poultry-driver-returns', null),
        NavLink('Driver report', '/poultry-driver-report', null),
      ]),
      NavSubGroup('Purchase', [
        NavLink('Flock Purchases (Batches)', '/flock-batch', null),
        NavLink('Record Purchase', '/poultry-supply-purchases?purchase=1', null),
      ]),
    ]),
    NavGroup('Sales, Expenses & Money', [
      NavSubGroup('Sales', [
        NavLink('Sales', '/sales', 'sales'),
        NavLink('Customer Payments', '/poultry-payments', 'poultry-payments'),
        NavLink('Customer Balances', '/customer-balances', 'poultry-customer-balances'),
        // Money held FOR customers (351): its own page, beside what they owe.
        NavLink('Customer Credits', '/customer-credits', null),
      ]),
      NavSubGroup('Expenses', [
        NavLink('Expenses', '/expenses', null),
        // Right under Expenses: paying a bill and seeing what is still owed.
        NavLink('Supplier Payments', '/supplier-payments', null),
        NavLink('Supplier Balances', '/supplier-balances', null),
        NavLink('Supplier Credits', '/supplier-credits', null),
        NavLink('Internal Use', '/poultry-internal-use', null),
        NavLink('Payroll', '/poultry-payroll', null),
        NavLink('Employee Loans & Advances', '/poultry-employee-loans', null),
        NavLink('Deferred inventory cost', '/poultry-deferred-costs', null),
        NavLink('Capital Investments/Assets', '/poultry-assets', null),
      ]),
      NavSubGroup('Money', [
        NavLink('Cash Flow', '/cash-flow', null),
        NavLink('Financial Activity', '/poultry-financial-activity', null),
        NavLink('Profit & Loss', '/poultry-profit-loss', null),
        NavLink('Owner Money', '/poultry-owner-money', null),
        NavLink('Loans (Financing)', '/poultry-loans', null),
        NavLink('Cash Account', '/poultry-cash-accounts', null),
        NavLink('Cash Transfers', '/poultry-cash-transfers', null),
        NavLink('Reconciliation', '/poultry-cash-reconciliation', null),
      ]),
    ]),
    NavGroup('Trackers', [
      NavSubGroup('Trackers', [
        NavLink('Egg tracker', '/egg-tracker', null),
        // Byproduct stock: never part of the egg or live-bird figures.
        NavLink('Broken eggs tracker', '/broken-eggs-tracker', null),
        NavLink('Feed tracker', '/feed-tracker', null),
        NavLink('Feed inventory tracker', '/feed-inventory-tracker', null),
        NavLink('Birds tracker', '/birds-left-tracker', null),
        NavLink('Dead birds tracker', '/dead-birds-tracker', null),
        NavLink('Medication tracker', '/medication-tracker', null),
        NavLink('Analytical Report', '/weekly-report', null),
        NavLink('Ingredients only tracker', '/feed-ingredient-tracker', null),
      ]),
    ]),
    NavGroup('Reports', [
      NavSubGroup('Overview', [
        NavLink('Reports Dashboard', '/reports', null),
        NavLink('All reports', '/poultry/reports', null),
      ]),
      NavSubGroup('Sales, Money & Profit', [
        NavLink('Profit & Loss (Company)', '/poultry/reports/profit-loss', 'poultry-reports-profit-loss'),
        NavLink('Daily Business Summary', '/poultry-daily-summary', 'poultry-daily-closings'),
        NavLink('Closing Report', '/poultry-closing-report-daily', 'poultry-daily-closings'),
        NavLink('Closing by Category', '/poultry-closing-report', 'poultry-closing-report'),
        NavLink('Profit & Loss by Flock', '/poultry/reports/profit-loss-by-flock', 'poultry-reports-profit-loss-by-flock'),
        NavLink('Egg Sales', '/poultry/reports/egg-sales', 'poultry-reports-egg-sales'),
        NavLink('Customer Balance', '/poultry/reports/customer-balance', 'poultry-reports-customer-balance'),
        NavLink('Supplier Balance', '/poultry/reports/supplier-balance', 'poultry-reports-supplier-balance'),
        NavLink('Expense Summary', '/poultry/reports/expense-summary', 'poultry-reports-expense-summary'),
        NavLink('Cash Movement', '/poultry/reports/cash-movement', 'poultry-reports-cash-movement'),
        NavLink('Cash Flow Detail', '/poultry/reports/cash-flow-detail', 'poultry-reports-cash-flow-detail'),
        NavLink('Cash Account Report', '/poultry/reports/cash-accounts', 'poultry-cash-accounts'),
        NavLink('Money Movement', '/poultry/reports/money', 'poultry-owner-money'),
        NavLink('Cost Per Egg', '/poultry/reports/cost-per-egg', 'poultry-reports-cost-per-egg'),
      ]),
      NavSubGroup('Production & Eggs', [
        NavLink('Daily Egg Production', '/poultry/reports/daily-egg-production', 'poultry-reports-daily-egg-production'),
        NavLink('Flock Production Summary', '/poultry/reports/flock-production-summary', 'poultry-reports-flock-production-summary'),
        NavLink('Hen-Day Production', '/poultry/reports/hen-day-production', 'poultry-reports-hen-day-production'),
        NavLink('Batch Production Summary', '/poultry/reports/batch-production-summary', 'mainflockbatch'),
        NavLink('Egg Stock Balance', '/poultry/reports/egg-stock-balance', 'poultry-reports-egg-stock-balance'),
        NavLink('Byproduct Inventory & Disposition', '/poultry/reports/byproduct-inventory', null),
        NavLink('Missing Daily Records', '/poultry/reports/missing-daily-records', 'poultry-reports-missing-daily-records'),
      ]),
      NavSubGroup('Feed, Birds & Health', [
        NavLink('Feed Usage', '/poultry/reports/feed-usage', 'poultry-reports-feed-usage'),
        NavLink('Feed Inventory Balance', '/poultry/reports/feed-inventory-balance', 'poultry-reports-feed-inventory-balance'),
        NavLink('Feed Cost Per Egg', '/poultry/reports/feed-cost-per-egg', 'poultry-reports-feed-cost-per-egg'),
        NavLink('Feed Production', '/poultry-feed-production/reports', 'poultry-feed-production'),
        NavLink('Mortality', '/poultry/reports/mortality', 'poultry-reports-mortality'),
        NavLink('Birds on Hand', '/poultry/reports/birds-on-hand', 'poultry-reports-birds-on-hand'),
        NavLink('End-of-Flock', '/poultry/reports/end-of-flock', 'poultry-reports-end-of-flock'),
        NavLink('Vaccination Schedule', '/poultry/reports/vaccination-schedule', 'poultry-reports-vaccination-schedule'),
        NavLink('Medicine Usage', '/poultry/reports/medicine-usage', 'poultry-reports-medicine-usage'),
      ]),
      NavSubGroup('Overview & Dashboards', [
        NavLink('Poultry Farm Summary', '/poultry/reports/farm-summary', null),
        NavLink('Production Dashboard', '/poultry/reports/production', null),
        NavLink('Financial Dashboard', '/poultry/reports/financial', null),
        NavLink('Daily Report', '/poultry/reports/daily', null),
        NavLink('More Reports', '/poultry/reports/more', null),
        NavLink('Changes Report', '/poultry/reports/changes', 'auditlogs'),
      ]),
    ]),
    // Hand-added: the web's Tools menu (poultry-nav-config.ts `tools`) was
    // missing from the generated copy.
    NavGroup('Tools', [
      NavSubGroup('Tools', [
        NavLink('Initial Farm Setup', '/poultry-farm-setup', null),
        NavLink('Flock Closeout', '/flock-closeout', null),
        NavLink('Flock Lifecycle', '/poultry-lifecycle', null),
        NavLink('Farm Completeness', '/poultry-farm-completeness', null),
        NavLink('Daily Closing', '/poultry-daily-closing', 'poultry-daily-closings'),
        NavLink('Distribute Feed', '/poultry-feed-distribution', null),
        NavLink('Treatment Campaigns', '/poultry-treatment-campaigns', null),
        NavLink('Inventory Restock Forecast', '/poultry-restock-forecast', null),
        NavLink('Flock Alerts', '/poultry-flock-alerts', null),
        NavLink('Farm Alerts', '/poultry-alerts', null),
        NavLink('Receive Purchase', '/poultry-purchase-receipts', null),
        // Recurring Expenses (348): moved here from Expenses.
        NavLink('Recurring Expenses', '/recurring-expenses', null),
      ]),
    ]),
    NavGroup('Setup', [
      NavSubGroup('Company', [
        NavLink('Farm Setup', '/poultry-setup', 'poultry-farm-setup-status'),
        NavLink('Company Setup', '/poultry-company-setup', 'poultry-company'),
        NavLink('Financial Settings', '/poultry-financial-settings', 'poultry-financial-settings-cost-recognition'),
        NavLink('Companies', '/companies', 'companies-mine'),
      ]),
      NavSubGroup('Delivery', [
        NavLink('Drivers', '/poultry-drivers', 'poultry-drivers'),
        NavLink('Vehicles', '/poultry-vehicles', 'poultry-vehicles'),
        NavLink('Routes', '/poultry-routes', 'poultry-routes'),
      ]),
      NavSubGroup('Production', [
        NavLink('Products', '/poultry-products', 'poultry-products'),
        NavLink('Feed Formulas', '/poultry-feed-formulas', 'poultry-feed-formulas'),
        NavLink('Egg Pick Times', '/business-office/egg-pick-settings', 'farmproductionsettings'),
        NavLink('Egg Sorting Settings', '/poultry-egg-sorting-settings', null),
      ]),
      NavSubGroup('Finance', [
        NavLink('Customers', '/customers', 'customer'),
        NavLink('Suppliers', '/suppliers', 'supplier'),
      ]),
      NavSubGroup('Farm', [
        NavLink('Houses', '/houses', 'house'),
        NavLink('Flock Groups', '/flocks', 'flocks'),
      ]),
      NavSubGroup('People', [
        NavLink('Staff', '/poultry-staff', 'poultry-staff'),
        NavLink('Users & Permissions', '/employees', 'admin-company-employees'),
      ]),
    ]),
    NavGroup('System', [
      NavSubGroup('Your account', [
        NavLink('Account', '/profile', null),
        // An action, not a page: opens "System Alerts and Notifications".
        NavLink('Alerts', '#alerts', null),
        NavLink('Billing', '/business-office/billing', null),
        NavLink('Activity Log', '/audit-logs', null),
        NavLink('Resources', '/resources', null),
        NavLink('Help Center', '/help', null),
        NavLink('Terms & Conditions', '/terms', null),
      ]),
    ]),
  ],
  // Hand-rebuilt 2026-10-02 from lib/nav/water-nav-config.ts, in the web
  // sidebar's order. The generated copy predated that config and was a flat
  // list of old groups.
  'water': [
    NavGroup('Quick Links', [
      NavSubGroup('', [
        NavLink('Water Production', '/water-production-batches', 'water-production-batches'),
        NavLink('Batch Production', '/water-daily-production', 'water-daily-productions'),
        NavLink('Deliveries', '/water-driver-returns', 'water-driver-returns'),
        NavLink('Sales', '/water-sales', 'water-sales'),
        NavLink('Payments', '/water-payments', 'water-payments'),
        NavLink('Expenses', '/water-expenses', 'water-expenses'),
        NavLink('Daily Closing', '/water-daily-closing', 'water-daily-closings'),
      ]),
    ]),
    NavGroup('Operations', [
      NavSubGroup('Production', [
        NavLink('Water Production', '/water-production-batches', 'water-production-batches'),
        NavLink('Batch Production', '/water-daily-production', 'water-daily-productions'),
        NavLink('Maintenance', '/water-maintenance', 'water-maintenance'),
      ]),
      NavSubGroup('Inventory', [
        NavLink('Stock movement', '/water-stock', 'water-stock-transactions'),
        NavLink('Inventory', '/water-inventory', 'water-products'),
        NavLink('Inventory & supply purchases', '/water-supply-purchases', 'water-raw-material-purchases'),
        NavLink('Damages & loss', '/water-loss-records', 'water-loss-records'),
        NavLink('Production losses', '/water-production-losses', 'water-production-losses'),
      ]),
      NavSubGroup('Delivery', [
        NavLink('Deliveries', '/water-driver-returns', 'water-driver-returns'),
        NavLink('Driver collection report', '/water-driver-report', 'water-reports-driver-collection'),
      ]),
    ]),
    NavGroup('Sales, Expenses & Money', [
      NavSubGroup('Sales', [
        NavLink('Sales', '/water-sales', 'water-sales'),
        NavLink('Payments', '/water-payments', 'water-payments'),
        NavLink('Customer Balances', '/water-customer-balances', 'water-customer-balances'),
      ]),
      NavSubGroup('Expenses', [
        NavLink('Expenses', '/water-expenses', 'water-expenses'),
        NavLink('Recurring Expenses', '/water-recurring-expenses', null),
        NavLink('Internal Use', '/water-internal-use', 'water-internal-usage'),
        NavLink('Payroll', '/water-payroll', 'water-payroll-runs'),
        NavLink('Employee Loans & Advances', '/water-employee-loans', 'water-employee-loans'),
        NavLink('Supplier Payments', '/water-supplier-payments', 'water-supplier-payments'),
        NavLink('Supplier Balances', '/water-supplier-balances', 'water-supplier-balances'),
        NavLink('Deferred inventory cost', '/water-deferred-costs', 'water-deferred-inventory-costs'),
        NavLink('Capital Investments/Assets', '/water-assets', 'water-assets'),
      ]),
      NavSubGroup('Money', [
        NavLink('Cash Flow', '/water-cash-flow', 'water-cash-flow'),
        NavLink('Profit & Loss', '/water-profit-loss', null),
        NavLink('Owner Money', '/water-owner-money', 'water-owner-money'),
        NavLink('Loans', '/water-loans', 'water-loans'),
        NavLink('Cash accounts', '/water-cash-accounts', 'water-cash-accounts'),
        NavLink('Cash Transfers', '/water-cash-transfers', 'water-cash-transfers'),
        NavLink('Reconciliation', '/water-cash-reconciliation', 'water-cash-reconciliations'),
      ]),
    ]),
    NavGroup('Trackers', [
      // The web's analytics column is labelled "Stock" (water-nav-config.ts).
      NavSubGroup('Stock', [
        NavLink('Inventory tracker', '/water-inventory-tracker', 'water-reports-inventory-tracker'),
      ]),
    ]),
    // Rebuilt 2026-10-08 from WATER_REPORT_GROUPS (lib/reports/water-reports-config.ts),
    // the web sidebar's Reports menu. In the drawer the web leads with an
    // "All reports" group (renderMenu's inlineLead); "View all reports →" is
    // the desktop panel's header link. Every report has a native screen.
    NavGroup('Reports', [
      NavSubGroup('All reports', [
        NavLink('Reports', '/water-reports', null),
      ]),
      NavSubGroup('Financial', [
        NavLink('Closing Report', '/water-reports/closing-report', null),
        NavLink('Profit & Loss', '/water-reports/profit-loss', null),
        NavLink('Daily Business Summary', '/water-reports/daily-summary', null),
        NavLink('Cash Movement', '/water-reports/cash-movement', null),
        NavLink('Cash Flow Detail', '/water-reports/cash-flow-detail', null),
        NavLink('Cash Account Report', '/water-reports/cash-accounts', null),
        NavLink('Money Movement', '/water-reports/money-movement', null),
        NavLink('Expense Report', '/water-reports/expense-report', null),
        NavLink('Supplier Activity', '/water-reports/supplier-activity', null),
      ]),
      NavSubGroup('Sales & Customers', [
        NavLink('Sales Report', '/water-reports/sales-report', null),
        NavLink('Payments Received', '/water-reports/payments-received', null),
        NavLink('Customer Balances', '/water-reports/customer-balances', null),
        NavLink('Customer Sales History', '/water-reports/customer-history', null),
        NavLink('Top Customers', '/water-reports/top-customers', null),
      ]),
      NavSubGroup('Production & Inventory', [
        NavLink('Production Report', '/water-reports/production-report', null),
        NavLink('Raw Material Usage', '/water-reports/raw-material-usage', null),
        NavLink('Raw Material Purchases', '/water-reports/raw-material-purchase', null),
        NavLink('Inventory / Stock', '/water-reports/inventory-report', null),
        NavLink('Stock Movement', '/water-reports/stock-movement', null),
        NavLink('Product Performance', '/water-reports/product-performance', null),
      ]),
      NavSubGroup('Delivery & Operations', [
        NavLink('Delivery Run Report', '/water-reports/delivery-run-report', null),
        NavLink('Driver Accountability', '/water-reports/driver-accountability', null),
        NavLink('Route Performance', '/water-reports/route-performance', null),
        NavLink('Driver Collection', '/water-reports/driver-collection', null),
        NavLink('Vehicle Usage', '/water-reports/vehicle-usage', null),
        NavLink('Loss Report', '/water-reports/loss-report', null),
        NavLink('Operational dashboard', '/water-reports/operational', null),
      ]),
    ]),
    NavGroup('Setup', [
      NavSubGroup('Company', [
        NavLink('Setup', '/water-setup', null),
        NavLink('Company Setup', '/water-company-setup', null),
        NavLink('Financial Settings', '/water-financial-settings', null),
        NavLink('Companies', '/companies', 'companies-mine'),
      ]),
      NavSubGroup('Delivery', [
        NavLink('Drivers', '/water-drivers', 'water-drivers'),
        NavLink('Vehicles', '/water-vehicles', 'water-vehicles'),
        NavLink('Routes', '/water-routes', 'water-routes'),
      ]),
      NavSubGroup('Production', [
        NavLink('Products', '/water-products', 'water-products'),
      ]),
      NavSubGroup('Finance', [
        NavLink('Customers', '/water-customers', 'water-customers'),
        NavLink('Suppliers', '/water-suppliers', 'water-suppliers'),
      ]),
      NavSubGroup('Plant', [
        NavLink('Machines', '/water-machines', 'water-machines'),
        NavLink('Boreholes', '/water-boreholes', 'water-boreholes'),
      ]),
      NavSubGroup('People', [
        NavLink('Staff', '/water-staff', 'water-staff'),
        NavLink('Users & Permissions', '/employees', 'admin-company-employees'),
      ]),
    ]),
    NavGroup('System', [
      NavSubGroup('Your account', [
        // No Account row: water-nav-config.ts hides it (visible: false).
        // An action, not a page: opens "System Alerts and Notifications".
        NavLink('Alerts', '#alerts', null),
        NavLink('Billing', '/business-office/billing', null),
        NavLink('Activity Log', '/audit-logs', 'auditlogs'),
        NavLink('Terms & Conditions', '/terms', null),
      ]),
    ]),
  ],
  'generic': [
    NavGroup('Finance', [
      NavSubGroup('', [
        NavLink('Internal Use', '/generic-internal-use', 'generic-internal-usage'),
        NavLink('Recurring Expenses', '/generic-recurring-expenses', 'generic-recurring-expenses'),
        NavLink('Purchases', '/generic-purchases', 'generic-purchases'),
        NavLink('Suppliers', '/generic-suppliers', 'generic-suppliers'),
      ]),
    ]),
    NavGroup('People', [
      NavSubGroup('', [
        NavLink('Staff Payments', '/generic-staff-payments', 'generic-staff-payments'),
        NavLink('Staff', '/generic-staff', 'generic-staff'),
        NavLink('Attendance', '/generic-attendance', 'generic-staff-attendance'),
        NavLink('Payroll', '/generic-payroll', 'generic-payroll-runs'),
      ]),
    ]),
    NavGroup('System', [
      NavSubGroup('', [
        NavLink('Generic Stock Adjustments', '/generic-stock-adjustments', 'generic-inventory-adjustments'),
        NavLink('Generic Setup/Wizard', '/generic-setup/wizard', 'generic-business-template'),
        NavLink('Generic Owner Money', '/generic-owner-money', 'generic-owner-entries'),
        NavLink('Inventory', '/generic-inventory', 'generic-products'),
        NavLink('Generic Dashboard', '/generic-dashboard', 'generic-reports-dashboard'),
        NavLink('Setup', '/generic-setup', 'generic-business-template'),
      ]),
    ]),
    NavGroup('Subscriptions', [
      NavSubGroup('', [
        NavLink('Subscriptions', '/generic-subscriptions', 'generic-subscriptions'),
        NavLink('Service Plans', '/generic-service-plans', 'generic-service-plans'),
        NavLink('Billing runs', '/generic-billing-runs', 'generic-billing-runs'),
      ]),
    ]),
    NavGroup('Sales & Money', [
      NavSubGroup('', [
        NavLink('Products', '/generic-products', 'generic-products'),
        NavLink('Sales', '/generic-sales', 'generic-sales'),
        NavLink('Customer Payments', '/generic-customer-payments', 'generic-customer-payments'),
        NavLink('Customers', '/generic-customers', 'generic-customers'),
        NavLink('Supplier payments', '/generic-supplier-payments', 'generic-supplier-payments'),
        NavLink('Expenses', '/generic-expenses', 'generic-expenses'),
        NavLink('Cash & Accounts', '/generic-cash', 'generic-cash-accounts'),
        NavLink('Cash transfers', '/generic-cash-transfers', 'generic-cash-transfers'),
        NavLink('Daily Closing', '/generic-daily-closings', 'generic-daily-closings'),
      ]),
    ]),
    NavGroup('Reports', [
      NavSubGroup('', [
        NavLink('Reports', '/generic-reports', null),
      ]),
    ]),
  ],
  // Rebuilt 2026-10-21 from the web sidebar's Hotel branch after the emma
  // merge (components/dashboard/sidebar.tsx, isHotel → renderMenu) and
  // lib/nav/hotel-nav-config.ts: menus like Poultry, Water and Restaurant.
  // Reports is HOTEL_REPORT_NAV_GROUPS led by "All reports". No Hotel page is
  // native yet: rows keep the specKeys they had (a generated list), and a row
  // new to the menu (specKey null) opens the real web page in-app.
  'hotel': [
    NavGroup('Quick Links', [
      NavSubGroup('', [
        NavLink('Daily Closing', '/hotel-daily-closing', 'hotel-reports-daily-closings'),
        NavLink('Night Audit', '/hotel-night-audit', 'hotel-night-audit'),
        NavLink('Shift Handover', '/hotel-shift-handover', 'hotel-shift-handovers'),
        NavLink('Bookings', '/hotel-bookings', 'hotel-bookings'),
      ]),
    ]),
    NavGroup('Operations', [
      NavSubGroup('Front Desk', [
        NavLink('Bookings', '/hotel-bookings', 'hotel-bookings'),
        NavLink('Guests', '/hotel-guests', 'hotel-guests'),
        NavLink('Check-in', '/hotel-check-in', 'hotel-bookings'),
        NavLink('Check-out', '/hotel-check-out', 'hotel-bookings'),
        NavLink('Availability', '/hotel-availability', 'hotel-setup-room-types'),
        NavLink('Guest Folio', '/hotel-guest-folio', 'hotel-bookings'),
        NavLink('Billing', '/hotel-billing', 'hotel-billing-charges'),
        NavLink('Invoices', '/hotel-invoices', 'hotel-billing-invoices'),
        NavLink('Stay History', '/hotel-stay-history', 'hotel-checkin-history'),
      ]),
      NavSubGroup('Guest Services', [
        NavLink('Guest Log', '/hotel-communications', 'hotel-communications'),
        NavLink('Requests', '/hotel-guest-requests', 'hotel-guest-requests'),
        NavLink('Lost & Found', '/hotel-lost-found', 'hotel-lost-and-found'),
      ]),
      NavSubGroup('Rooms & Housekeeping', [
        NavLink('Rooms', '/hotel-rooms', 'hotel-rooms'),
        NavLink('Housekeeping', '/hotel-housekeeping', 'hotel-housekeeping'),
        NavLink('HK Schedule', '/hotel-housekeeping-schedule', 'hotel-housekeeping-schedule'),
        NavLink('Room Service', '/hotel-room-service', 'hotel-restaurant-orders'),
      ]),
    ]),
    NavGroup('Restaurant & Bar', [
      NavSubGroup('Restaurant & Bar', [
        NavLink('Orders', '/hotel-restaurant', 'hotel-restaurant-orders'),
        NavLink('Menu', '/hotel-menu', 'hotel-restaurant-tables'),
        NavLink('Kitchen', '/hotel-kitchen', 'hotel-restaurant-orders'),
        NavLink('Tables', '/hotel-restaurant-tables', 'hotel-restaurant-tables'),
      ]),
    ]),
    NavGroup('Sales, Expenses & Money', [
      NavSubGroup('Sales', [
        NavLink('Sales', '/hotel-sales', null),
        NavLink('Payments', '/hotel-payments', 'hotel-finance-expenses'),
        NavLink('Customer Balances', '/hotel-customer-balances', null),
      ]),
      NavSubGroup('Expenses', [
        NavLink('Expenses', '/hotel-expenses', 'hotel-finance-expense-categories'),
        NavLink('Supplier Payments', '/hotel-supplier-payments', null),
        NavLink('Supplier Balances', '/hotel-supplier-balances', null),
        NavLink('Recurring Expenses', '/hotel-recurring-expenses', null),
        NavLink('Internal Use', '/hotel-internal-use', null),
        NavLink('Payroll', '/hotel-payroll', 'hotel-payroll-runs'),
        NavLink('Employee Loans & Advances', '/hotel-employee-loans', null),
        NavLink('Deferred inventory cost', '/hotel-deferred-costs', null),
        NavLink('Capital Investments/Assets', '/hotel-assets', null),
      ]),
      NavSubGroup('Money', [
        NavLink('Cash Flow', '/hotel-cash-flow', null),
        NavLink('Financial Activity', '/hotel-financial-activity', null),
        NavLink('Profit & Loss', '/hotel-profit-loss', null),
        NavLink('Owner Money', '/hotel-owner-money', null),
        NavLink('Loans (Financing)', '/hotel-loans', null),
        NavLink('Cash Account', '/hotel-cash-accounts', 'hotel-finance-cash-accounts'),
        NavLink('Cash Transfers', '/hotel-cash-transfers', null),
        NavLink('Reconciliation', '/hotel-cash-reconciliation', null),
      ]),
    ]),
    NavGroup('Reports', [
      NavSubGroup('All reports', [
        NavLink('All Reports', '/hotel-reports', null),
      ]),
      NavSubGroup('Financial', [
        NavLink('Revenue Summary', '/hotel-reports/revenue-summary', 'hotel-reports-daily-closings'),
        NavLink('Expense Report', '/hotel-reports/expense-report', 'hotel-finance-expenses'),
        NavLink('Billing & Payments', '/hotel-reports/billing-report', 'hotel-billing-payments'),
        NavLink('Payroll Report', '/hotel-reports/payroll-report', 'hotel-payroll-runs'),
        NavLink('Cash Flow Report', '/hotel-reports/cash-flow-report', 'hotel-finance-cash-accounts'),
        NavLink('Guest Ledger', '/hotel-reports/guest-ledger', null),
        NavLink('Ancillary Revenue', '/hotel-reports/ancillary-revenue', null),
        NavLink('Employee Loans & Advances', '/hotel-reports/staff-loans', null),
      ]),
      NavSubGroup('Operations', [
        NavLink('Bookings Report', '/hotel-reports/bookings-report', 'hotel-bookings'),
        NavLink('Guest Report', '/hotel-reports/guest-report', 'hotel-bookings'),
        NavLink('Occupancy & ADR', '/hotel-reports/occupancy-report', 'hotel-reports-daily-closings'),
        NavLink('Maintenance Report', '/hotel-reports/maintenance-report', 'hotel-maintenance'),
        NavLink('Loyalty Programme', '/hotel-reports/loyalty-report', null),
      ]),
      NavSubGroup('Restaurant & Bar', [
        NavLink('Restaurant Sales', '/hotel-reports/restaurant-sales', 'hotel-restaurant-orders'),
        NavLink('Menu Performance', '/hotel-reports/menu-performance', 'restaurant-menu-items'),
      ]),
      NavSubGroup('Periodic Reports', [
        NavLink('Daily Report', '/hotel-reports/daily-report', 'hotel-reports-daily-closings'),
        NavLink('Weekly Report', '/hotel-reports/weekly-report', 'hotel-reports-daily-closings'),
        NavLink('Monthly Report', '/hotel-reports/monthly-report', 'hotel-reports-daily-closings'),
      ]),
      NavSubGroup('Housekeeping & Inventory', [
        NavLink('Housekeeping Report', '/hotel-reports/housekeeping-report', 'hotel-housekeeping'),
        NavLink('Inventory Report', '/hotel-reports/inventory-report', 'hotel-inventory'),
        NavLink('Housekeeping Productivity', '/hotel-reports/housekeeping-productivity', null),
      ]),
      NavSubGroup('Revenue Management', [
        NavLink('Performance & KPIs', '/hotel-reports/performance-kpis', null),
        NavLink('Source of Business', '/hotel-reports/source-of-business', null),
        NavLink('Booking Pace', '/hotel-reports/booking-pace', null),
        NavLink('Room Type Performance', '/hotel-reports/room-type-performance', null),
        NavLink('Length of Stay', '/hotel-reports/length-of-stay', null),
        NavLink('Cancellations', '/hotel-reports/cancellations', null),
      ]),
    ]),
    NavGroup('Setup', [
      NavSubGroup('Hotel', [
        NavLink('Company Setup', '/hotel-company-setup', 'hotel-setup-profile'),
        NavLink('Hotel Setup', '/hotel-setup', 'hotel-setup-amenities'),
      ]),
      NavSubGroup('People', [
        NavLink('Staff', '/hotel-staff', 'hotel-staff'),
        NavLink('Users & Permissions', '/employees', null),
      ]),
      NavSubGroup('Finance', [
        NavLink('Customers', '/hotel-customers', null),
        NavLink('Suppliers', '/hotel-suppliers', null),
      ]),
      NavSubGroup('Facilities', [
        NavLink('Supplies', '/hotel-inventory', 'hotel-inventory'),
        NavLink('Maintenance', '/hotel-maintenance', 'hotel-maintenance'),
      ]),
    ]),
    // sidebar.tsx prepends "Account" to the config's "Your account" column,
    // whose own Account row is hidden (visible: false).
    NavGroup('System', [
      NavSubGroup('Your account', [
        NavLink('Account', '/profile', 'authentication-get-current-user'),
        NavLink('Companies', '/companies', 'companies-mine'),
        NavLink('Billing', '/business-office/billing', null),
      ]),
    ]),
  ],
  // Restaurant had no entry here at all, so a restaurant company opened the
  // app to an empty menu. Mirrors lib/nav/restaurant-nav-config.ts: same
  // sections, same order, same labels as the site.
  // Rebuilt 2026-10-21 from the web sidebar's Restaurant branch after the
  // emma merge (components/dashboard/sidebar.tsx, isRestaurant): it is now
  // menus like Poultry and Water, each a collapsible section in the drawer
  // with its columns (lib/nav/restaurant-nav-config.ts) as sub-headings.
  // Reports is RESTAURANT_REPORT_NAV_GROUPS led by "All reports", as Water's.
  //
  // specKey null = the page has no list endpoint of its own (POS, the money
  // reports, Restaurant Setup's tabs); it opens the real web page in-app.
  'restaurant': [
    NavGroup('Quick Links', [
      NavSubGroup('', [
        NavLink('Sales', '/restaurant-sales', null),
        NavLink('Tills & Shifts', '/restaurant-tills', 'restaurant-finance-shifts'),
        NavLink('Expenses', '/restaurant-expenses', 'restaurant-expenses'),
        NavLink('Cash Flow', '/restaurant-cash-flow', 'restaurant-cash-flow'),
        NavLink('Profit & Loss', '/restaurant-profit-loss', null),
        NavLink('Daily Closing', '/restaurant-daily-closing', 'restaurant-finance-daily-closing'),
      ]),
    ]),
    NavGroup('Orders & Kitchen', [
      NavSubGroup('Orders', [
        NavLink('POS / New Order', '/restaurant-pos', null),
        NavLink('New Guest Orders', '/restaurant-pending-orders', 'restaurant-online-pending-orders'),
        NavLink('All Orders', '/restaurant-orders', 'restaurant-orders'),
      ]),
      NavSubGroup('Kitchen', [
        NavLink('Kitchen Display', '/restaurant-kds', null),
      ]),
    ]),
    NavGroup('Dining', [
      NavSubGroup('Floor & Tables', [
        NavLink('Restaurant Areas', '/restaurant-floor-plan', 'restaurant-floor-floors'),
        NavLink('Reservations & Waitlist', '/restaurant-reservations', 'restaurant-reservations'),
      ]),
    ]),
    NavGroup('Delivery & Online', [
      NavSubGroup('Online Ordering', [
        NavLink('Online Settings', '/restaurant-online-orders', 'restaurant-online-settings'),
        NavLink('QR / Customer Order', '/restaurant-order-online', 'restaurant-public-menu'),
      ]),
      NavSubGroup('Delivery', [
        NavLink('Drivers & Dispatch', '/restaurant-delivery', 'restaurant-delivery-drivers'),
      ]),
    ]),
    NavGroup('Inventory', [
      NavSubGroup('Inventory', [
        NavLink('Ingredients & Stock', '/restaurant-inventory', 'restaurant-inventory-ingredients'),
        NavLink('Record Purchase', '/restaurant-inventory?purchase=1', null),
      ]),
    ]),
    NavGroup('Sales, Expenses & Money', [
      NavSubGroup('Sales', [
        NavLink('Sales', '/restaurant-sales', null),
        NavLink('Payments', '/restaurant-payments', null),
        NavLink('Customer Balances', '/restaurant-customer-balances', null),
      ]),
      NavSubGroup('Expenses', [
        NavLink('Expenses', '/restaurant-expenses', 'restaurant-expenses'),
        NavLink('Supplier Payments', '/restaurant-supplier-payments', null),
        NavLink('Supplier Balances', '/restaurant-supplier-balances', null),
        NavLink('Recurring Expenses', '/restaurant-recurring-expenses', null),
        NavLink('Internal Use', '/restaurant-internal-use', null),
        NavLink('Payroll', '/restaurant-payroll', 'restaurant-payroll-runs'),
        NavLink('Employee Loans & Advances', '/restaurant-staff-loans', 'restaurant-staff-loans'),
        NavLink('Deferred inventory cost', '/restaurant-deferred-costs', null),
        NavLink('Capital Investments/Assets', '/restaurant-assets', null),
      ]),
      NavSubGroup('Money', [
        NavLink('Cash Flow', '/restaurant-cash-flow', 'restaurant-cash-flow'),
        NavLink('Financial Activity', '/restaurant-financial-activity', null),
        NavLink('Profit & Loss', '/restaurant-profit-loss', null),
        NavLink('Owner Money', '/restaurant-owner-money', 'restaurant-finance-owner-money'),
        NavLink('Loans (Financing)', '/restaurant-loans', 'restaurant-finance-loans'),
        NavLink('Cash Account', '/restaurant-cash-accounts', 'restaurant-finance-accounts'),
        NavLink('Cash Transfers', '/restaurant-cash-transfers', 'restaurant-finance-transfers'),
        NavLink('Reconciliation', '/restaurant-cash-reconciliation', null),
      ]),
    ]),
    NavGroup('Growth', [
      NavSubGroup('Customers', [
        NavLink('Customers & CRM', '/restaurant-crm', 'restaurant-crm-customers'),
        NavLink('Loyalty & Rewards', '/restaurant-loyalty', 'restaurant-loyalty-accounts'),
      ]),
      NavSubGroup('More', [
        NavLink('Events & Catering', '/restaurant-events', 'restaurant-events'),
        NavLink('Gift Cards', '/restaurant-gift-cards', 'restaurant-gift-cards'),
        NavLink('Notifications', '/restaurant-notifications', 'restaurant-notifications'),
      ]),
    ]),
    NavGroup('Reports', [
      NavSubGroup('All reports', [
        NavLink('Reports', '/restaurant-reports', null),
      ]),
      NavSubGroup('Money', [
        NavLink('Profit & Loss', '/restaurant-reports/pnl', null),
        NavLink('Sales Summary', '/restaurant-reports/sales-summary', null),
        NavLink('Payment Methods', '/restaurant-reports/payment-methods', null),
        NavLink('Expenses', '/restaurant-reports/expenses', null),
        NavLink('Discounts & Promotions', '/restaurant-reports/discounts', null),
        NavLink('Profit vs Cash', '/restaurant-reports/profit-vs-cash', null),
        NavLink('Payroll', '/restaurant-reports/payroll', null),
        NavLink('Employee Loans & Advances', '/restaurant-reports/staff-loans', null),
      ]),
      NavSubGroup('Cash & Ledger', [
        NavLink('Cash Flow Detail', '/restaurant-reports/cash-flow-detail', null),
        NavLink('Cash Movement', '/restaurant-reports/cash-movement', null),
        NavLink('Cash Account Report', '/restaurant-reports/cash-accounts', null),
        NavLink('Money Movement', '/restaurant-reports/money-movement', null),
        NavLink('Takings by Account', '/restaurant-reports/takings-by-account', null),
        NavLink('Till & Count Variances', '/restaurant-reports/till-variances', null),
        NavLink('Closing Report', '/restaurant-reports/closing-report', null),
      ]),
      NavSubGroup('Sales', [
        NavLink('Daily Sales', '/restaurant-reports/daily-sales', null),
        NavLink('Revenue Trend', '/restaurant-reports/revenue-trend', null),
        NavLink('Top Selling Items', '/restaurant-reports/top-items', null),
        NavLink('Sales by Category', '/restaurant-reports/sales-by-category', null),
        NavLink('Peak Hours', '/restaurant-reports/peak-hours', null),
      ]),
      NavSubGroup('Menu & Food', [
        NavLink('Menu Engineering', '/restaurant-reports/menu-engineering', null),
        NavLink('Food Cost', '/restaurant-reports/food-cost', null),
        NavLink('Waste', '/restaurant-reports/waste', null),
      ]),
      NavSubGroup('Operations', [
        NavLink('Kitchen Performance', '/restaurant-reports/kitchen-performance', null),
        NavLink('Table Turnover', '/restaurant-reports/table-turnover', null),
        NavLink('Waiter Performance', '/restaurant-reports/waiter-performance', null),
        NavLink('Tips', '/restaurant-reports/tips', null),
        NavLink('Voids & Cancellations', '/restaurant-reports/voids', null),
        NavLink('Stock on Hand', '/restaurant-reports/stock-on-hand', null),
      ]),
      NavSubGroup('Guests & Channels', [
        NavLink('Customer Retention', '/restaurant-reports/customer-retention', null),
        NavLink('Guest Feedback', '/restaurant-reports/feedback', null),
        NavLink('Delivery Performance', '/restaurant-reports/delivery-performance', null),
        NavLink('Channel Profitability', '/restaurant-reports/channel', null),
        NavLink('Events & Catering', '/restaurant-reports/events', null),
      ]),
    ]),
    NavGroup('Setup', [
      NavSubGroup('Menu & Staff', [
        NavLink('Menu Items', '/restaurant-menu', 'restaurant-menu-items'),
        NavLink('Staff', '/restaurant-staff', 'restaurant-staff'),
        NavLink('Restaurant Setup', '/restaurant-setup', null),
      ]),
      NavSubGroup('Finance', [
        NavLink('Suppliers', '/restaurant-suppliers', 'restaurant-setup-suppliers'),
      ]),
    ]),
    // The web's Restaurant System menu: "Account" is prepended by
    // sidebar.tsx to the nav config's Account column (My Account, Companies,
    // Billing), so both rows open /profile there too.
    NavGroup('System', [
      NavSubGroup('Account', [
        NavLink('Account', '/profile', 'authentication-get-current-user'),
        NavLink('My Account', '/profile', null),
        NavLink('Companies', '/companies', 'companies-mine'),
        NavLink('Billing', '/business-office/billing', 'payments-subscription-tiers'),
      ]),
    ]),
    // Not on the web's Restaurant sidebar any more (the old flat System block
    // and the QR print page). Kept so the All pages sheet still reaches them.
    NavGroup('More pages', [
      NavSubGroup('', [
        NavLink('Users & Permissions', '/employees', 'admin-company-employees'),
        // An action, not a page: opens "System Alerts and Notifications".
        NavLink('Alerts', '#alerts', null),
        NavLink('Activity Log', '/audit-logs', 'auditlogs'),
        NavLink('Terms & Conditions', '/terms', null),
        NavLink('QR Codes', '/restaurant-qr-print', 'restaurant-online-qr-codes'),
      ]),
    ]),
  ],
};
