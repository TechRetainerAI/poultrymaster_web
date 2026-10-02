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
        NavLink('Production Records', '/production-records', 'production-records'),
        NavLink('Egg sorting', '/egg-production', 'eggproduction'),
        NavLink('Raw Materials', '/poultry-raw-materials', 'raw-materials'),
        NavLink('Sales', '/sales', 'sales'),
        NavLink('Payments received', '/poultry-payments', 'poultry-payments'),
        NavLink('Customer Balances', '/customer-balances', 'poultry-customer-balances'),
        NavLink('Expenses', '/expenses', 'expenses'),
        NavLink('Cash Flow', '/cash-flow', 'poultry-cash-flow'),
        NavLink('Profit & Loss', '/poultry-profit-loss', null),
        NavLink('Daily Closing', '/poultry-daily-closing', 'poultry-daily-closings'),
      ]),
    ]),
    NavGroup('Operations', [
      NavSubGroup('Production', [
        NavLink('Production Records', '/production-records', 'production-records'),
        NavLink('Batch Production', '/batch-production-records', 'productionbatchrecord'),
        NavLink('Egg sorting', '/egg-production', 'eggproduction'),
        NavLink('Feed Usage', '/feed-usage', 'feedusage'),
        NavLink('Feed Production', '/poultry-feed-production', 'poultry-feed-production'),
      ]),
      NavSubGroup('Inventory & Health', [
        NavLink('Inventory', '/poultry-inventory', 'poultry-products'),
        NavLink('Stock movements', '/poultry-stock', 'poultry-stock-transactions'),
        NavLink('Raw Materials & Supplies', '/poultry-raw-materials', 'raw-materials'),
        NavLink('Health Records', '/health', 'health'),
        NavLink('Loss & Damage', '/poultry-loss-records', 'poultry-loss-records'),
      ]),
      NavSubGroup('Delivery', [
        NavLink('Deliveries', '/poultry-driver-returns', 'poultry-driver-returns'),
        NavLink('Driver report', '/poultry-driver-report', 'poultry-reports-driver-collection'),
      ]),
      NavSubGroup('Purchase', [
        NavLink('Flock Purchases (Batches)', '/flock-batch', 'flock'),
        NavLink('Record Purchase', '/poultry-raw-materials?purchase=1', 'raw-materials'),
      ]),
    ]),
    NavGroup('Sales, Expenses & Money', [
      NavSubGroup('Sales', [
        NavLink('Sales', '/sales', 'sales'),
        NavLink('Payments', '/poultry-payments', 'poultry-payments'),
        NavLink('Customer Balances', '/customer-balances', 'poultry-customer-balances'),
      ]),
      NavSubGroup('Expenses', [
        NavLink('Expenses', '/expenses', 'expenses'),
        NavLink('Internal Use', '/poultry-internal-use', 'poultry-internal-usage'),
        NavLink('Payroll', '/poultry-payroll', 'poultry-payroll-runs'),
        NavLink('Employee Loans & Advances', '/poultry-employee-loans', 'employee-loans'),
        NavLink('Supplier Payments', '/supplier-payments', 'poultry-cash-accounts'),
        NavLink('Supplier Balances', '/supplier-balances', 'poultry-supplier-balances'),
        NavLink('Deferred inventory cost', '/poultry-deferred-costs', 'poultry-deferred-inventory-costs'),
        NavLink('Capital Investments/Assets', '/poultry-assets', 'assets'),
      ]),
      NavSubGroup('Money', [
        NavLink('Cash Flow', '/cash-flow', 'poultry-cash-flow'),
        NavLink('Financial Activity', '/poultry-financial-activity', 'poultry-financial-activity'),
        NavLink('Profit & Loss', '/poultry-profit-loss', null),
        NavLink('Owner Money', '/poultry-owner-money', 'owner-money'),
        NavLink('Loans (Financing)', '/poultry-loans', 'loans'),
        NavLink('Cash Account', '/poultry-cash-accounts', 'poultry-cash-accounts'),
        NavLink('Cash Transfers', '/poultry-cash-transfers', 'poultry-cash-transfers'),
        NavLink('Reconciliation', '/poultry-cash-reconciliation', 'poultry-cash-reconciliations'),
      ]),
    ]),
    NavGroup('Trackers', [
      NavSubGroup('Trackers', [
        NavLink('Egg tracker', '/egg-tracker', 'egginventoryadjustment'),
        NavLink('Feed tracker', '/feed-tracker', null),
        NavLink('Feed inventory tracker', '/feed-inventory-tracker', 'poultry-raw-material-purchases'),
        NavLink('Birds tracker', '/birds-left-tracker', 'flock'),
        NavLink('Medication tracker', '/medication-tracker', 'poultry-raw-material-items'),
        NavLink('Analytical Report', '/weekly-report', 'production-records'),
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
        NavLink('Account', '/profile', 'authentication-get-current-user'),
        NavLink('Billing', '/billing', 'payments-subscription-tiers'),
        NavLink('Activity Log', '/audit-logs', 'auditlogs'),
        NavLink('Resources', '/resources', null),
        NavLink('Help Center', '/help', null),
        NavLink('Terms & Conditions', '/terms', null),
      ]),
    ]),
  ],
  'water': [
    NavGroup('Quick Links', [
      NavSubGroup('', [
        NavLink('Daily Closing', '/water-daily-closing', 'water-daily-closings'),
        NavLink('Deliveries', '/water-driver-returns', 'water-driver-returns'),
      ]),
    ]),
    NavGroup('Delivery', [
      NavSubGroup('', [
        NavLink('Drivers', '/water-drivers', 'water-drivers-list-for-farm'),
        NavLink('Vehicles', '/water-vehicles', 'water-vehicles'),
        NavLink('Routes', '/water-routes', 'water-routes'),
        NavLink('Driver report', '/water-driver-report', 'water-reports-driver-collection'),
      ]),
    ]),
    NavGroup('Production', [
      NavSubGroup('', [
        NavLink('Production Batches', '/water-production-batches', 'water-production-batches'),
        NavLink('Batch Production', '/water-daily-production', 'water-daily-productions'),
        NavLink('Products', '/water-products', 'water-products'),
        NavLink('Machines', '/water-machines', 'water-machines'),
        NavLink('Boreholes', '/water-boreholes', 'water-boreholes'),
        NavLink('Maintenance', '/water-maintenance', 'water-maintenance'),
      ]),
    ]),
    NavGroup('Inventory', [
      NavSubGroup('', [
        NavLink('Stock movement', '/water-stock', 'water-stock-transactions'),
        NavLink('Inventory', '/water-inventory', 'water-products'),
        NavLink('Raw materials & supplies', '/water-raw-materials', 'water-raw-material-purchases'),
        NavLink('Internal Use', '/water-internal-use', 'water-internal-usage'),
        NavLink('Damages & loss', '/water-loss-records', 'water-loss-records'),
        NavLink('Production losses', '/water-production-losses', 'water-production-losses'),
      ]),
    ]),
    NavGroup('Sales', [
      NavSubGroup('', [
        NavLink('Sales', '/water-sales', 'water-sales'),
        NavLink('Payments', '/water-payments', 'water-payments'),
        NavLink('Customer Balances', '/water-customer-balances', 'water-customer-balances'),
      ]),
    ]),
    NavGroup('Expenses', [
      NavSubGroup('', [
        NavLink('Expenses', '/water-expenses', 'water-expenses'),
        NavLink('Payroll', '/water-payroll', 'water-payroll-runs'),
        NavLink('Supplier Payments', '/water-supplier-payments', 'water-supplier-payments'),
        NavLink('Supplier Balances', '/water-supplier-balances', 'water-supplier-balances'),
        NavLink('Deferred inventory cost', '/water-deferred-costs', 'water-deferred-inventory-costs'),
        NavLink('Capital Investments/Assets', '/water-assets', 'water-assets'),
      ]),
    ]),
    NavGroup('Money', [
      NavSubGroup('', [
        NavLink('Financial Settings', '/water-financial-settings', 'water-financial-settings-items'),
        NavLink('Cash Flow', '/water-cash-flow', 'water-cash-flow'),
        NavLink('Profit & Loss', '/water-reports/profit-loss', 'water-reports-period-pnl'),
        NavLink('Owner Money', '/water-owner-money', 'water-owner-money'),
        NavLink('Loans', '/water-loans', 'water-loans'),
        NavLink('Cash accounts', '/water-cash-accounts', 'water-cash-accounts'),
        NavLink('Cash Transfers', '/water-cash-transfers', 'water-cash-transfers'),
        NavLink('Reconciliation', '/water-cash-reconciliation', 'water-cash-reconciliations'),
      ]),
    ]),
    NavGroup('Finance', [
      NavSubGroup('', [
        NavLink('Customers', '/water-customers', 'water-customers'),
        NavLink('Suppliers', '/water-suppliers', 'water-suppliers'),
      ]),
    ]),
    NavGroup('People', [
      NavSubGroup('', [
        NavLink('Staff', '/water-staff', 'water-staff'),
      ]),
    ]),
    NavGroup('Analytics & Reports', [
      NavSubGroup('', [
        NavLink('Inventory tracker', '/water-inventory-tracker', 'water-reports-inventory-tracker'),
        NavLink('Reports', '/water-reports', null),
      ]),
    ]),
    NavGroup('Reports', [
      NavSubGroup('', [
        NavLink('Water Reports/Vehicle Usage', '/water-reports/vehicle-usage', 'water-vehicle-loadings'),
        NavLink('Water Reports/Route Performance', '/water-reports/route-performance', 'water-reports-route-profitability'),
        NavLink('Water Reports/Product Performance', '/water-reports/product-performance', 'water-production-batches'),
        NavLink('Water Reports/Operational', '/water-reports/operational', 'water-reports-driver-reconciliation'),
        NavLink('Water Reports/Money Movement', '/water-reports/money-movement', 'water-owner-money'),
        NavLink('Water Reports/Loss Report', '/water-reports/loss-report', 'water-loss-records'),
        NavLink('Water Reports/Inventory Report', '/water-reports/inventory-report', 'water-products'),
        NavLink('Water Reports/Driver Accountability', '/water-reports/driver-accountability', 'water-reports-driver-reconciliation'),
        NavLink('Water Reports/Delivery Run Report', '/water-reports/delivery-run-report', 'water-driver-returns'),
        NavLink('Water Reports/Daily Summary', '/water-reports/daily-summary', 'water-daily-closings'),
        NavLink('Water Reports/Cash Accounts', '/water-reports/cash-accounts', 'water-cash-accounts'),
        NavLink('Raw Material Usage', '/water-reports/raw-material-usage', 'water-raw-material-usage-history'),
        NavLink('Raw Material Purchases', '/water-reports/raw-material-purchase', 'water-raw-material-purchases'),
        NavLink('Production Report', '/water-reports/production-report', 'water-production-batches'),
        NavLink('Expense Report', '/water-reports/expense-report', 'water-expenses'),
        NavLink('Closing Report', '/water-reports/closing-report', 'water-daily-closings'),
        NavLink('Driver Collection', '/water-reports/driver-collection', 'water-reports-driver-collection'),
        NavLink('Supplier Activity', '/water-reports/supplier-activity', 'water-reports-supplier-activity'),
        NavLink('Top Customers', '/water-reports/top-customers', 'water-reports-top-customers'),
      ]),
    ]),
    NavGroup('System', [
      NavSubGroup('', [
        NavLink('Water Dashboard', '/water-dashboard', 'water-dashboard-summary'),
        NavLink('Setup', '/water-setup', null),
        NavLink('Company Setup', '/water-company-setup', 'water-company'),
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
  'hotel': [
    NavGroup('People', [
      NavSubGroup('', [
        NavLink('Staff', '/hotel-staff', 'hotel-staff'),
        NavLink('Payroll', '/hotel-payroll', 'hotel-payroll-runs'),
      ]),
    ]),
    NavGroup('System', [
      NavSubGroup('', [
        NavLink('Hotel Reports/Weekly Report', '/hotel-reports/weekly-report', 'hotel-reports-daily-closings'),
        NavLink('Hotel Reports/Monthly Report', '/hotel-reports/monthly-report', 'hotel-reports-daily-closings'),
        NavLink('Hotel Reports/Menu Performance', '/hotel-reports/menu-performance', 'restaurant-menu-items'),
        NavLink('Hotel Reports/Guest Report', '/hotel-reports/guest-report', 'hotel-bookings'),
        NavLink('Hotel Reports/Daily Report', '/hotel-reports/daily-report', 'hotel-reports-daily-closings'),
        NavLink('Hotel Reports/Cash Flow Report', '/hotel-reports/cash-flow-report', 'hotel-finance-cash-accounts'),
        NavLink('Hotel Reports/Billing Report', '/hotel-reports/billing-report', 'hotel-billing-payments'),
        NavLink('Hotel Dashboard', '/hotel-dashboard', 'hotel-bookings'),
        NavLink('Company Setup', '/hotel-company-setup', 'hotel-setup-profile'),
        NavLink('Setup', '/hotel-setup', 'hotel-setup-amenities'),
      ]),
    ]),
    NavGroup('Front Desk', [
      NavSubGroup('', [
        NavLink('Guests', '/hotel-guests', 'hotel-guests'),
        NavLink('Bookings', '/hotel-bookings', 'hotel-bookings'),
        NavLink('Check-in', '/hotel-check-in', 'hotel-bookings'),
        NavLink('Check-out', '/hotel-check-out', 'hotel-bookings'),
        NavLink('Availability', '/hotel-availability', 'hotel-setup-room-types'),
        NavLink('Guest Folio', '/hotel-guest-folio', 'hotel-bookings'),
        NavLink('Stay History', '/hotel-stay-history', 'hotel-checkin-history'),
        NavLink('Night Audit', '/hotel-night-audit', 'hotel-night-audit'),
      ]),
    ]),
    NavGroup('Guest Services', [
      NavSubGroup('', [
        NavLink('Guest Log', '/hotel-communications', 'hotel-communications'),
        NavLink('Requests', '/hotel-guest-requests', 'hotel-guest-requests'),
        NavLink('Lost & Found', '/hotel-lost-found', 'hotel-lost-and-found'),
      ]),
    ]),
    NavGroup('Rooms & Service', [
      NavSubGroup('', [
        NavLink('Rooms', '/hotel-rooms', 'hotel-rooms'),
        NavLink('Housekeeping', '/hotel-housekeeping', 'hotel-housekeeping'),
        NavLink('Room Service', '/hotel-room-service', 'hotel-restaurant-orders'),
        NavLink('Restaurant', '/hotel-restaurant', 'hotel-restaurant-orders'),
        NavLink('Menu Items', '/hotel-menu', 'hotel-restaurant-tables'),
        NavLink('HK Schedule', '/hotel-housekeeping-schedule', 'hotel-housekeeping-schedule'),
        NavLink('Tables', '/hotel-restaurant-tables', 'hotel-restaurant-tables'),
        NavLink('Kitchen', '/hotel-kitchen', 'hotel-restaurant-orders'),
      ]),
    ]),
    NavGroup('Billing & Money', [
      NavSubGroup('', [
        NavLink('Billing', '/hotel-billing', 'hotel-billing-charges'),
        NavLink('Invoices', '/hotel-invoices', 'hotel-billing-invoices'),
        NavLink('Payments', '/hotel-payments', 'hotel-finance-expenses'),
        NavLink('Expenses', '/hotel-expenses', 'hotel-finance-expense-categories'),
        NavLink('Cash Accounts', '/hotel-cash-accounts', 'hotel-finance-cash-accounts'),
        NavLink('Daily Closing', '/hotel-daily-closing', 'hotel-reports-daily-closings'),
      ]),
    ]),
    NavGroup('Inventory & Reports', [
      NavSubGroup('', [
        NavLink('Revenue Summary', '/hotel-reports/revenue-summary', 'hotel-reports-daily-closings'),
        NavLink('Restaurant Sales', '/hotel-reports/restaurant-sales', 'hotel-restaurant-orders'),
        NavLink('Payroll Report', '/hotel-reports/payroll-report', 'hotel-payroll-runs'),
        NavLink('Occupancy Report', '/hotel-reports/occupancy-report', 'hotel-reports-daily-closings'),
        NavLink('Maintenance Report', '/hotel-reports/maintenance-report', 'hotel-maintenance'),
        NavLink('Inventory Report', '/hotel-reports/inventory-report', 'hotel-inventory'),
        NavLink('Housekeeping Report', '/hotel-reports/housekeeping-report', 'hotel-housekeeping'),
        NavLink('Expense Report', '/hotel-reports/expense-report', 'hotel-finance-expenses'),
        NavLink('Bookings Report', '/hotel-reports/bookings-report', 'hotel-bookings'),
        NavLink('Supplies', '/hotel-inventory', 'hotel-inventory'),
        NavLink('Maintenance', '/hotel-maintenance', 'hotel-maintenance'),
        NavLink('Reports', '/hotel-reports', null),
        NavLink('Shift Handover', '/hotel-shift-handover', 'hotel-shift-handovers'),
      ]),
    ]),
  ],
  // Restaurant had no entry here at all, so a restaurant company opened the
  // app to an empty menu. Mirrors lib/nav/restaurant-nav-config.ts: same
  // sections, same order, same labels as the site.
  'restaurant': [
    NavGroup('Orders', [
      NavSubGroup('Orders', [
        NavLink('POS / New Order', '/restaurant-pos', 'restaurant-orders'),
        NavLink('New Guest Orders', '/restaurant-pending-orders', 'restaurant-online-pending-orders'),
        NavLink('All Orders', '/restaurant-orders', 'restaurant-orders'),
      ]),
      NavSubGroup('Kitchen', [
        NavLink('Kitchen Display', '/restaurant-kds', 'restaurant-kds-stations'),
      ]),
    ]),
    NavGroup('Floor & Tables', [
      NavSubGroup('Floor & Tables', [
        NavLink('Restaurant Areas', '/restaurant-floor-plan', 'restaurant-floor-floors'),
        NavLink('Reservations & Waitlist', '/restaurant-reservations', 'restaurant-reservations'),
      ]),
    ]),
    NavGroup('Online Ordering', [
      NavSubGroup('Online Ordering', [
        NavLink('QR Codes', '/restaurant-qr-print', 'restaurant-online-qr-codes'),
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
        NavLink('Expenses', '/restaurant-expenses', 'restaurant-expenses'),
      ]),
    ]),
    NavGroup('Customers', [
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
    NavGroup('Setup', [
      NavSubGroup('Menu & Staff', [
        NavLink('Menu Items', '/restaurant-menu', 'restaurant-menu-items'),
        NavLink('Staff & Roles', '/restaurant-staff', 'restaurant-staff'),
        NavLink('Restaurant Setup', '/restaurant-setup', 'restaurant-setup-profile'),
      ]),
    ]),
    NavGroup('System', [
      NavSubGroup('Account', [
        NavLink('Income & Expenses', '/restaurant-payments', 'restaurant-expenses'),
        NavLink('Restaurant Dashboard', '/restaurant-dashboard', 'restaurant-menu-items'),
        NavLink('My Account', '/profile', 'authentication-get-current-user'),
        NavLink('Companies', '/companies', 'companies-mine'),
        NavLink('Billing', '/billing', 'payments-subscription-tiers'),
      ]),
    ]),
  ],
};
