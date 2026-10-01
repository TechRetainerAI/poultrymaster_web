// GENERATED from the web pages' own source — do not edit by hand.
//
// Each entry is what ONE web page says about itself: the <h1> it shows, the
// line under it, and the columns of its table. The list renderer prefers this
// over anything it can infer, so a page reads the same on a phone as it does
// in a browser — without a hand-written screen per page.
//
// Regenerate when the web pages change.

import 'page_headers.dart';
import 'page_spec.dart';

class PageDesign {
  const PageDesign({this.title = '', this.description = '', this.columns = const []});

  /// The page's own heading, not the API action name behind it.
  final String title;

  /// The muted line under the heading.
  final String description;

  /// Column headings in the web's order. Matched to row keys by squashing both
  /// to letters only, so "Customer Name" finds customerName / CustomerName.
  final List<String> columns;
}

const Map<String, PageDesign> webPageDesigns = {
  '/audit-logs': PageDesign(title: 'Audit Logs', description: 'Track all user activities and system events', columns: ['Details', 'Data']),
  '/batch-production-records': PageDesign(title: 'Batch Production Records', description: 'Log batch-level production and allocate totals across flocks'),
  '/birds-left-tracker': PageDesign(title: 'Birds left tracker', description: 'One IN per flock (birds placed at purchase). Only mortality (production records) and bird sales create OUT rows and reduce the count.', columns: ['Flock', 'Placed (IN)', 'Deaths OUT', 'Sales OUT', 'Birds left', 'From last log', 'Type', 'Category', 'Description']),
  '/cash': PageDesign(title: 'Financial → Cash', description: 'Cash at hand and transaction history'),
  '/cash-flow': PageDesign(title: 'Cash Flow'),
  '/companies': PageDesign(title: 'My companies', columns: ['Name', 'Type', 'Role', 'Created']),
  '/customers': PageDesign(title: 'Customers', description: 'Manage your customer database'),
  '/egg-production': PageDesign(title: 'Egg Sorting', description: 'Daily collection by flock (9am / 12pm / 4pm) for the filters below.'),
  '/egg-tracker': PageDesign(title: 'Egg tracker', description: 'Ledger from egg sorting production, egg sales, and optional manual adjustments (like Cash at hand).'),
  '/employees': PageDesign(title: 'Employees', description: 'Manage your staff members and their access'),
  '/expenses': PageDesign(title: 'Expenses', description: 'Track operational costs and financial records'),
  '/feed-inventory-tracker': PageDesign(title: 'Feed inventory tracker', description: 'Ledger from purchases, feed production, flock consumption and adjustments — every movement behind one ingredient&apos;s or finished feed&apos;s stock figure.', columns: ['Unit', 'Items', 'Opening', 'In', 'Out', 'Closing', 'In stock now']),
  '/feed-usage': PageDesign(title: 'Feed Usage', description: 'Monitor feed consumption and costs'),
  '/flock-batch': PageDesign(title: 'Flock Purchases (Batches)', description: 'Manage your bird flock batches', columns: ['Balance', 'Name', 'Breed', 'Quantity', 'Start Date', 'Status']),
  '/flocks': PageDesign(title: 'Flock Groups (Pens / Flocks)', description: 'Manage your bird flocks', columns: ['Status', 'House', 'Batch', 'Age', 'Reason for Inactivation', 'Notes']),
  '/forgot-password': PageDesign(title: 'Poultry Core', description: 'Farm Management System'),
  '/generic-attendance': PageDesign(title: 'Attendance', columns: ['Staff', 'Role', 'Status', 'Set status']),
  '/generic-billing-runs': PageDesign(title: 'Billing runs', columns: ['Period', 'Due', 'Amount', 'Run', 'As of', 'Checked', 'Raised', 'Skipped', 'By']),
  '/generic-cash': PageDesign(title: 'Cash & accounts', columns: ['Account', 'Type', 'Opening', 'Current', 'Allows negative', 'Status']),
  '/generic-cash-transfers': PageDesign(title: 'Cash transfers', columns: ['Date', 'From', 'To', 'Amount', 'Status']),
  '/generic-customer-payments': PageDesign(columns: ['Date', 'Customer', 'Method', 'Amount', 'Status']),
  '/generic-customers': PageDesign(columns: ['Name', 'Type', 'Phone', 'Location', 'Credit limit', 'Owes us', 'Status']),
  '/generic-daily-closings': PageDesign(title: 'Daily closings', columns: ['Date', 'Sales', 'Expenses', 'Expected cash', 'Actual cash', 'Difference', 'Status']),
  '/generic-dashboard': PageDesign(title: 'dashboard'),
  '/generic-expenses': PageDesign(title: 'Expenses', columns: ['Date', 'Category', 'Description', 'Supplier', 'Paid via', 'Amount', 'Status']),
  '/generic-internal-use': PageDesign(title: 'Internal Use', columns: ['Date', 'Reason', 'Product', 'Quantity', 'Cost', 'Status']),
  '/generic-inventory': PageDesign(title: 'Inventory', description: 'Stock-on-hand for every tracked product. Adjustments via Stock Adjustments page.', columns: ['Product', 'SKU', 'Category', 'Unit', 'Cost', 'Selling', 'Stock', 'Min alert', 'Status']),
  '/generic-invoices': PageDesign(columns: ['Number', 'Date', 'Period', 'Due', 'Total', 'Balance', 'Status']),
  '/generic-owner-money': PageDesign(title: 'Owner money', columns: ['Date', 'Type', 'Owner', 'Account', 'Reference', 'Amount']),
  '/generic-payroll': PageDesign(title: 'Payroll', columns: ['Period', 'Pay date', 'Cash account', 'Gross', 'Deductions', 'Net', 'Status']),
  '/generic-products': PageDesign(title: 'Products', columns: ['Name', 'SKU', 'Category', 'Cost', 'Selling', 'Stock', 'Status']),
  '/generic-purchases': PageDesign(title: 'Purchases', columns: ['Date', 'Supplier', 'Invoice', 'Total', 'Paid', 'Balance', 'Status']),
  '/generic-recurring-expenses': PageDesign(title: 'Recurring expenses', columns: ['Expense', 'Category', 'Period', 'Amount', 'Supplier', 'Repeats', 'Next due', 'Raised', 'Status']),
  '/generic-reports': PageDesign(title: 'Reports'),
  '/generic-sales': PageDesign(title: 'Sales', columns: ['Date', 'Customer', 'Type', 'Total', 'Paid', 'Balance', 'Status']),
  '/generic-service-plans': PageDesign(columns: ['Category', 'Price', 'Billing', 'Active', 'Per period']),
  '/generic-settings': PageDesign(title: 'Settings'),
  '/generic-staff': PageDesign(title: 'Staff', columns: ['Name', 'Role', 'Salary type', 'Base pay', 'Commission', 'Phone', 'Status']),
  '/generic-staff-payments': PageDesign(title: 'Staff payments', columns: ['Person', 'Type', 'Paid on', 'Period', 'Account', 'Amount', 'Status']),
  '/generic-stock-adjustments': PageDesign(title: 'Stock adjustments', columns: ['Date', 'Product', 'Type', 'Qty', 'Reason', 'Status']),
  '/generic-subscriptions': PageDesign(columns: ['Number', 'Billing', 'Per period', 'Next bill', 'Open', 'Status']),
  '/generic-supplier-payments': PageDesign(title: 'Supplier payments', columns: ['Date', 'Supplier', 'Method', 'Amount', 'Status']),
  '/generic-suppliers': PageDesign(title: 'Suppliers', columns: ['Name', 'Type', 'Phone', 'Location', 'Terms', 'We owe them', 'Status']),
  '/health': PageDesign(title: 'Health Records', description: 'Track vaccinations, medications, and water consumption', columns: ['Vaccination', 'Medication', 'Water (L)', 'Notes']),
  '/help': PageDesign(title: 'Help Center', description: 'Find answers to common questions, learn how to use VisibilityCore features, and get support.'),
  '/hotel-assets': PageDesign(title: 'Capital Assets'),
  '/hotel-availability': PageDesign(title: 'Room Availability'),
  '/hotel-billing': PageDesign(title: 'Billing'),
  '/hotel-bookings': PageDesign(title: 'Bookings'),
  '/hotel-cash-accounts': PageDesign(title: 'Cash Accounts'),
  '/hotel-cash-flow': PageDesign(title: 'Cash Flow'),
  '/hotel-check-in': PageDesign(title: 'Front Desk'),
  '/hotel-check-out': PageDesign(title: 'Check-out'),
  '/hotel-communications': PageDesign(title: 'Guest Communication Log'),
  '/hotel-company-setup': PageDesign(title: 'Hotel Company Setup', description: 'Your hotel&apos;s identity, contact details, service hours and charges'),
  '/hotel-customer-payments': PageDesign(title: 'Customer Payments'),
  '/hotel-customers': PageDesign(title: 'Customers', description: 'Total Customers'),
  '/hotel-daily-closing': PageDesign(title: 'Daily Closing'),
  '/hotel-dashboard': PageDesign(title: 'Hotel Dashboard'),
  '/hotel-employee-loans': PageDesign(title: 'Staff Loans & Advances'),
  '/hotel-expenses': PageDesign(title: 'Expenses'),
  '/hotel-guest-requests': PageDesign(title: 'Guest Requests'),
  '/hotel-guests': PageDesign(title: 'Guests'),
  '/hotel-housekeeping': PageDesign(title: 'Housekeeping'),
  '/hotel-housekeeping-schedule': PageDesign(title: 'Housekeeping Schedule'),
  '/hotel-inventory': PageDesign(title: 'Supplies & Inventory'),
  '/hotel-invoices': PageDesign(title: 'Invoices'),
  '/hotel-kitchen': PageDesign(title: 'Kitchen Display'),
  '/hotel-lost-found': PageDesign(title: 'Lost & Found'),
  '/hotel-maintenance': PageDesign(title: 'Maintenance'),
  '/hotel-menu': PageDesign(title: 'Menu Items'),
  '/hotel-night-audit': PageDesign(title: 'Night Audit'),
  '/hotel-payments': PageDesign(title: 'Payments'),
  '/hotel-payroll': PageDesign(title: 'Payroll'),
  '/hotel-profit-loss': PageDesign(title: 'Profit & Loss', columns: ['Line', 'Amount', 'Date', 'Type', 'Description', 'Method', 'Category', 'Vendor']),
  '/hotel-reports': PageDesign(title: 'Reports'),
  '/hotel-restaurant': PageDesign(title: 'Restaurant & Bar'),
  '/hotel-restaurant-tables': PageDesign(title: 'Restaurant Tables'),
  '/hotel-room-service': PageDesign(title: 'Room Service Orders'),
  '/hotel-rooms': PageDesign(title: 'Room Inventory'),
  '/hotel-setup': PageDesign(title: 'Hotel Setup', description: 'Work left to right — each step feeds the next'),
  '/hotel-shift-handover': PageDesign(title: 'Shift Handover'),
  '/hotel-staff': PageDesign(title: 'Hotel Staff'),
  '/hotel-stay-history': PageDesign(title: 'Stay History'),
  '/hotel-supplier-payments': PageDesign(title: 'Supplier Payments'),
  '/hotel-suppliers': PageDesign(title: 'Suppliers', description: 'Total Suppliers'),
  '/houses': PageDesign(title: 'Houses', description: 'Manage poultry houses'),
  '/inventory': PageDesign(title: 'Other Inventory', description: 'Manage your farm inventory and supplies', columns: ['Quantity', 'Unit Price', 'Total Value', 'Entry Date', 'Supplier', 'Location']),
  '/login': PageDesign(title: 'VisibilityCore', description: 'Farm Management System'),
  '/medication-tracker': PageDesign(title: 'Medication Tracker'),
  '/poultry-assets': PageDesign(title: 'Capital Investments/Assets', columns: ['Investment', 'From', 'Months', 'Amount']),
  '/poultry-cash-accounts': PageDesign(title: 'Cash Account', columns: ['Name', 'Type', 'Opening', 'Current', 'Calculated', 'Reconciled', 'Status', 'Date', 'From', 'To', 'Amount', 'Source', 'Description']),
  '/poultry-cash-reconciliation': PageDesign(title: 'Reconciliation', columns: ['Reference', 'Date', 'System', 'Actual Balance', 'Difference', 'Reason', 'Status']),
  '/poultry-cash-transfers': PageDesign(title: 'Cash Transfers', columns: ['Date', 'Transfer #', 'From', 'To', 'Amount', 'Reference', 'Recorded by', 'Status']),
  '/poultry-closing-report': PageDesign(title: 'Closing by Category'),
  '/poultry-closing-report-daily': PageDesign(columns: ['Date', 'Produced', 'Sold', 'Income', 'Expenses', 'Cash at hand', 'Counted', 'Difference', 'Status', 'Notes']),
  '/poultry-company-setup': PageDesign(title: 'Poultry Company Setup'),
  '/poultry-daily-closing': PageDesign(title: 'Daily Closing', columns: ['Date', 'Produced', 'Sold', 'Income', 'Expenses', 'Cash at hand', 'Closing stock', 'Status']),
  '/poultry-daily-summary': PageDesign(title: 'Daily Business Summary', columns: ['Category', 'Amount']),
  '/poultry-deferred-costs': PageDesign(title: 'Deferred inventory cost', columns: ['Purchase', 'Item', 'Supplier', 'Purchased', 'Remaining', 'Original cost', 'Expensed', 'Deferred inventory cost', 'Status', 'Date', 'Source', 'Qty drawn', 'Unit cost', 'Stock used', 'Outcome']),
  '/poultry-deliveries': PageDesign(title: 'Egg Deliveries', columns: ['Date', 'Driver / Vehicle', 'Loaded', 'Sold', 'Ret', 'Brk', 'Short', 'Sales', 'Status']),
  '/poultry-driver-report': PageDesign(title: 'Driver collection report', columns: ['Driver', 'Runs', 'Loaded', 'Sold', 'Returned', 'Lost', 'Expected', 'Collected', 'Shortage', 'Date', 'Product', 'Loaded (crates)', 'Sold (crates)', 'Returned (crates)', 'Damaged (crates)']),
  '/poultry-driver-returns': PageDesign(title: 'Deliveries', columns: ['Delivery #', 'Date', 'Vehicle', 'Driver', 'Status', 'Sold (crates)', 'Returned (crates)', 'Damaged (crates)', 'Cash', 'MoMo', 'Credit', 'Shortage', 'Product', 'Quantity (crates)', 'Unit price', 'Expected', 'Qty (crates)', 'Price', 'Total', 'Category', 'Amount', 'Description', 'Approved', 'Route', 'Loaded (crates)']),
  '/poultry-drivers': PageDesign(title: 'Drivers', columns: ['Name', 'Phone', 'License', 'Default vehicle', 'Status']),
  '/poultry-employee-loans': PageDesign(title: 'Employee Loans & Advances', columns: ['Date', 'How', 'Reference', 'Amount', 'Balance before', 'Balance after', 'Status', 'Loan #', 'Employee', 'Type', 'Issued', 'Advanced', 'Repayable', 'Repaid', 'Outstanding', 'Repayment']),
  '/poultry-farm-setup': PageDesign(title: 'Initial Farm Setup', description: 'Your opening farm position — what was true when tracking began.'),
  '/poultry-feed-formulas': PageDesign(title: 'Feed Formulas', columns: ['Formula', 'Finished Feed', 'Ingredients', '% Total', 'Status']),
  '/poultry-feed-production': PageDesign(title: 'Feed Production', columns: ['Batch #', 'Date', 'Finished Feed', 'Qty', 'Ingredient Cost', 'Add. Cost', 'Total Cost', 'Cost/Unit', 'Status']),
  '/poultry-financial-activity': PageDesign(title: 'Financial Activity', description: 'See how business activity affects cash, revenue, expenses, profit and financial position.', columns: ['Position', 'Increase', 'Decrease', 'Explanation']),
  '/poultry-financial-settings': PageDesign(title: 'Cost Recognition'),
  '/poultry-internal-use': PageDesign(title: 'Internal Use', columns: ['Date', 'Reason', 'Product', 'Quantity', 'Cost', 'Status']),
  '/poultry-inventory': PageDesign(title: 'Poultry inventory', description: 'Finished products and raw materials in one place.', columns: ['Item', 'Type', 'SKU', 'Size', 'Unit', 'Unit price', 'In stock', 'Status', 'Details', 'Category', 'Min alert']),
  '/poultry-loans': PageDesign(title: 'Loans (Financing)', columns: ['Date', 'Payment #', 'Principal', 'Interest', 'Fees', 'Total paid', 'Account', 'Status', 'Loan #', 'Lender', 'Borrowed', 'Received', 'Repaid', 'Still owed', 'Next payment']),
  '/poultry-loss-records': PageDesign(title: 'Loss & Damage Records', columns: ['Date', 'Type', 'Product', 'Qty', 'Value', 'Status']),
  '/poultry-owner-money': PageDesign(title: 'Owner Money', columns: ['Date', 'Number', 'Owner', 'Type', 'Amount', 'Cash account', 'Method', 'Reference', 'Status']),
  '/poultry-payroll': PageDesign(title: 'Payroll', columns: ['Period', 'Gross', 'Deductions', 'Net', 'Cash account', 'Status', 'Staff', 'Basic', 'Daily', 'Comm.', 'Bonus', 'Deduct']),
  '/poultry-products': PageDesign(title: 'Products', columns: ['Product', 'Type', 'Unit', 'Price', 'In stock', 'Status']),
  '/poultry-raw-materials': PageDesign(title: 'Raw Materials & Supplies', columns: ['Stock value', 'Cost treatment']),
  '/poultry-reports': PageDesign(title: 'Reports'),
  '/poultry-routes': PageDesign(title: 'Routes', columns: ['Name', 'Area', 'Default vehicle', 'Expected customers', 'Expected crates']),
  '/poultry-setup': PageDesign(title: 'Poultry farm setup', columns: ['{tab.columns.map((c) =>']),
  '/poultry-staff': PageDesign(title: 'Staff', columns: ['Name', 'Role', 'Salary type', 'Base pay', 'Phone', 'Status']),
  '/poultry-stock': PageDesign(title: 'Stock Movements'),
  '/poultry-vehicles': PageDesign(title: 'Vehicles', columns: ['Name', 'Type', 'Reg #', 'Capacity (crates)', 'Fuel', 'Status']),
  '/production-records': PageDesign(title: 'Production Records', description: 'Track daily egg production and performance metrics'),
  '/register': PageDesign(title: 'VisibilityCore', description: 'Run all your businesses from one place.'),
  '/reports': PageDesign(title: 'Reports', description: 'Comprehensive farm analytics and insights'),
  '/resources': PageDesign(title: 'Resources & Information Center', description: 'Access vaccination schedules, medication guides, and feed formulations', columns: ['Notes', 'Ingredients']),
  '/restaurant-cash-flow': PageDesign(title: 'Cash Flow', columns: ['Account', 'Money in', 'Money out', 'Net']),
  '/restaurant-crm': PageDesign(title: 'Customer Relationships', description: 'Profiles, feedback, and campaigns'),
  '/restaurant-dashboard': PageDesign(title: 'Welcome back', description: '— {new Date().toLocaleDateString("en-US", )}'),
  '/restaurant-delivery': PageDesign(title: 'Delivery Management', description: 'Drivers, zones, dispatch and third-party platforms'),
  '/restaurant-floor-plan': PageDesign(title: 'Restaurant Areas', description: 'Manage your dining areas and table layout. tables across areas.'),
  '/restaurant-gift-cards': PageDesign(title: 'You\'ve Received a Gift Card!'),
  '/restaurant-inventory': PageDesign(title: 'Inventory & Recipes', description: 'ingredients tracked'),
  '/restaurant-kds': PageDesign(title: 'Kitchen Display'),
  '/restaurant-menu': PageDesign(title: 'Menu Management', description: 'items across categories'),
  '/restaurant-online-orders': PageDesign(title: 'Online Ordering', description: 'QR codes, promo codes and delivery settings'),
  '/restaurant-orders': PageDesign(title: 'Orders', description: 'orders shown {filterSource !== "all" && ` · \$ only`}'),
  '/restaurant-payments': PageDesign(title: 'Income & Expenses', description: 'Financial overview — where money comes in and goes out'),
  '/restaurant-pending-orders': PageDesign(title: 'New Orders {orders.length > 0 && ( )}', description: 'Orders guests sent from their phones. They do not reach the kitchen until you accept them.'),
  '/restaurant-profit-loss': PageDesign(title: 'Profit & Loss'),
  '/restaurant-reports': PageDesign(title: 'Reports', description: 'Your account does not have permission to view restaurant reports. An administrator can grant this under Users & Permissions.'),
  '/restaurant-reservations': PageDesign(title: 'Reservations & Waitlist', description: 'Manage bookings and walk-in guests'),
  '/restaurant-setup': PageDesign(title: 'Restaurant Setup', description: 'Configure your restaurant profile, menu schedules and modifiers'),
  '/restaurant-staff': PageDesign(title: 'Staff & Permissions', description: 'team members across roles'),
  '/sales': PageDesign(title: 'Sales', description: 'Manage your farm sales and transactions'),
  '/suppliers': PageDesign(title: 'Suppliers', description: 'Manage vendors you buy feed and supplies from'),
  '/supplies': PageDesign(title: 'Supplies', description: 'Track and manage farm supplies', columns: ['Quantity', 'Cost', 'Supplier', 'Purchase Date']),
  '/system-farms': PageDesign(title: 'System farms', description: 'Registered farms, subscription status (paid flag on any farm user), and headcounts.'),
  '/terms': PageDesign(title: 'Terms & Conditions', description: 'Please read these terms before using VisibilityCore.'),
  '/water-assets': PageDesign(title: 'Assets', columns: ['Asset', 'From', 'Months', 'Amount']),
  '/water-boreholes': PageDesign(title: 'Boreholes', columns: ['Name', 'Location', 'Treatment', 'Next maint.', 'Quality test due', 'Status']),
  '/water-cash-accounts': PageDesign(title: 'Cash accounts', columns: ['Name', 'Type', 'Opening', 'Current', 'Calculated', 'Reconciled', 'Status', 'Date', 'From', 'To', 'Amount', 'Source', 'Description']),
  '/water-cash-flow': PageDesign(title: 'Cash Flow'),
  '/water-cash-reconciliation': PageDesign(title: 'Reconciliation', columns: ['Reference', 'Date', 'System', 'Actual Balance', 'Difference', 'Reason', 'Status']),
  '/water-cash-transfers': PageDesign(title: 'Cash Transfers', columns: ['Date', 'Transfer #', 'From', 'To', 'Amount', 'Reference', 'Recorded by', 'Status']),
  '/water-company-setup': PageDesign(title: 'Water Company Setup'),
  '/water-customers': PageDesign(title: 'Water customers', columns: ['Name', 'Phone', 'Email', 'City', 'Outstanding']),
  '/water-daily-closing': PageDesign(title: 'Daily closing', columns: ['Date', 'Bags produced', 'Bags sold', 'Income', 'Expenses', 'Cash at hand', 'Status']),
  '/water-daily-production': PageDesign(title: 'Batch production', columns: ['Date', 'Document', 'Product', 'Machines', 'Bags', 'Good', 'Rejected', 'All-in cost', 'Cost/bag', 'Status']),
  '/water-dashboard': PageDesign(title: 'dashboard'),
  '/water-deferred-costs': PageDesign(title: 'Deferred inventory cost', columns: ['Purchase', 'Item', 'Supplier', 'Purchased', 'Remaining', 'Original cost', 'Expensed', 'Deferred inventory cost', 'Status', 'Date', 'Production batch', 'Qty drawn', 'Unit cost', 'Stock used', 'Outcome']),
  '/water-driver-report': PageDesign(title: 'Driver collection report', columns: ['Driver', 'Runs', 'Reconciled', 'Cash', 'MoMo', 'Bank', 'Credit', 'Shortage', 'Overage', 'Product', 'Loaded (bags)', 'Sold (bags)', 'Returned (bags)', 'Damaged (bags)', 'Expected', 'Sales']),
  '/water-driver-returns': PageDesign(title: 'Deliveries', columns: ['Delivery #', 'Date', 'Vehicle', 'Driver', 'Status', 'Sold (bags)', 'Returned (bags)', 'Damaged (bags)', 'Cash', 'MoMo', 'Credit', 'Shortage', 'Product', 'Quantity (bags)', 'Unit price', 'Expected', 'Qty (bags)', 'Price', 'Total', 'Category', 'Amount', 'Description', 'Approved', 'Route', 'Loaded (bags)']),
  '/water-drivers': PageDesign(title: 'Drivers', columns: ['Name', 'Phone', 'License', 'Assigned vehicle', 'Status']),
  '/water-employee-loans': PageDesign(title: 'Employee Loans & Advances', columns: ['Date', 'How', 'Reference', 'Amount', 'Balance before', 'Balance after', 'Status', 'Loan #', 'Employee', 'Type', 'Issued', 'Advanced', 'Repayable', 'Repaid', 'Outstanding', 'Repayment']),
  '/water-expenses': PageDesign(title: 'Water expenses', columns: ['Date', 'Category', 'Description', 'Supplier / Paid to', 'Total', 'Paid', 'Balance', 'Payment', 'Method', 'Due', 'Source', 'Status']),
  '/water-financial-settings': PageDesign(title: 'Cost Recognition', columns: ['Item', 'Category', 'Treated as', 'Override']),
  '/water-internal-use': PageDesign(title: 'Internal Use', columns: ['Date', 'Reason', 'Product', 'Quantity', 'Cost', 'Status']),
  '/water-inventory': PageDesign(title: 'Water inventory', description: 'Finished products and raw materials in one place.', columns: ['Name', 'SKU', 'Size', 'Unit', 'Unit price', 'Stock (Bags)', 'Stock (Sachets)', 'Status', 'Track', 'Item', 'Category', 'Stock', 'Min alert']),
  '/water-inventory-tracker': PageDesign(title: 'Inventory tracker', description: 'Ledger from production, sales, vehicle loadings, internal use and adjustments — every movement behind a product&apos;s stock figure.', columns: ['Balance']),
  '/water-loans': PageDesign(title: 'Loans', columns: ['Loan #', 'Lender', 'Borrowed', 'Received', 'Repaid', 'Still owed', 'Interest', 'Fees', 'Next payment', 'Status', 'Date', 'Payment #', 'Loan', 'Principal', 'Total paid', 'Account']),
  '/water-loss-records': PageDesign(title: 'Loss records', columns: ['Date', 'Type', 'Bags', 'Sachets', 'Value', 'Reason', 'Status']),
  '/water-machines': PageDesign(title: 'Machines', columns: ['Name', 'Number', 'Type', 'Capacity/hr', 'Next maint.', 'Status']),
  '/water-maintenance': PageDesign(title: 'Maintenance', columns: ['Date', 'Asset', 'Issue', 'Technician', 'Cost', 'Status']),
  '/water-owner-money': PageDesign(title: 'Owner Money', columns: ['Date', 'Number', 'Owner', 'Type', 'Amount', 'Cash account', 'Method', 'Reference', 'Status']),
  '/water-payroll': PageDesign(title: 'Payroll', columns: ['Period', 'Gross', 'Net', 'Cash account', 'Status', 'Staff', 'Basic', 'Daily', 'Comm.', 'Bonus', 'Deduct']),
  '/water-production-batches': PageDesign(title: 'Production', columns: ['Date', 'Shift', 'Machine', 'Produced', 'Good', 'Damaged', 'Total cost', 'Cost/bag', 'Status', 'Material', 'Expected', 'Actual', 'Unit', 'Unit cost', 'Stock', 'Cost']),
  '/water-production-losses': PageDesign(title: 'Production losses', columns: ['Date', 'Batch', 'Product', 'Type', 'Bags', 'Sachets', 'Total value', 'Status']),
  '/water-products': PageDesign(title: 'Water products', columns: ['Name', 'Type', 'SKU', 'Size', 'Unit', 'Price', 'Stock', 'Status']),
  '/water-raw-materials': PageDesign(title: 'Raw materials'),
  '/water-reports': PageDesign(title: 'Reports'),
  '/water-routes': PageDesign(title: 'Routes', columns: ['Name', 'Area', 'Default vehicle', 'Expected customers', 'Expected bags']),
  '/water-sales': PageDesign(title: 'Water sales', columns: ['Date', 'Customer', 'Total', 'Paid', 'Balance', 'Method', 'Status', 'Product', 'Selling Unit', 'Qty', 'Unit Price', 'Line Total']),
  '/water-setup': PageDesign(title: 'Water company setup', columns: ['{tab.columns.map((c) =>']),
  '/water-staff': PageDesign(title: 'Employees', columns: ['Name', 'Role', 'Salary type', 'Base pay', 'Phone', 'Status']),
  '/water-stock': PageDesign(title: 'Stock movement'),
  '/water-suppliers': PageDesign(title: 'Suppliers', columns: ['Name', 'Type', 'Contact', 'Phone', 'Email', 'Status']),
  '/water-vehicles': PageDesign(title: 'Vehicles', columns: ['Name', 'Type', 'Reg #', 'Capacity', 'Fuel', 'Status']),
  '/weekly-report': PageDesign(title: 'Analytical Report', description: 'Showing . All totals update automatically based on the selected period.', columns: ['Room / Flock', 'Total', 'Crates', 'Room', 'Eggs Collected', 'Crates (+ loose)', 'Losses', 'Saleable', 'Sold', 'Unsold', 'Date', 'Item', 'Category', 'Price', 'Customer', 'Amount Owed', 'Size', 'Eggs', 'Avg Price / Crate']),
};

/// Overlays this page's own words on the generated header. Only a non-empty
/// value wins, so a page with no <h1> keeps whatever the header map had.
extension PageHeaderWeb on PageHeaderDef {
  PageHeaderDef withWeb(PageDesign? d) {
    if (d == null) return this;
    return PageHeaderDef(
      title: d.title.isNotEmpty ? d.title : title,
      description: d.description.isNotEmpty ? d.description : description,
      color: color,
      action: action,
    );
  }
}

/// Whether a numeric field is money rather than a count. Mirrors the rule in
/// page_spec.dart, which is private to that file; counts are checked first so
/// "birds" and "eggs" are never formatted as currency.
bool _moneyish(String k) {
  const money = [
    'amount', 'price', 'cost', 'total', 'balance', 'revenue', 'paid',
    'value', 'fee', 'rate', 'principal', 'outstanding',
  ];
  const counts = ['count', 'quantity', 'qty', 'number', 'birds', 'eggs'];
  if (counts.any(k.contains)) return false;
  return money.any(k.contains);
}

/// Letters and digits only, so "Customer Name" / "customerName" /
/// "Customer_Name" all reduce to the same thing.
String _squash(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// The web's columns, resolved against a real row.
///
/// A column whose name matches no field is dropped rather than rendered
/// blank: the web table may show a computed or joined value this endpoint
/// does not return, and an empty label under every row is worse than one
/// fewer field. Capped at three, which is what fits a phone row.
List<FieldSpec> webColumnFields(
  List<String> columns,
  Map<String, dynamic> row,
  String titleKey,
) {
  if (columns.isEmpty || row.isEmpty) return const [];

  final byKey = <String, String>{};
  for (final k in row.keys) {
    byKey.putIfAbsent(_squash(k), () => k);
  }

  final out = <FieldSpec>[];
  for (final label in columns) {
    final key = byKey[_squash(label)];
    if (key == null || key == titleKey) continue;
    final v = row[key];
    if (v == null || v is Map || v is List) continue;

    final lower = key.toLowerCase();
    final kind = v is bool
        ? FieldKind.boolean
        : v is num
            ? (_moneyish(lower) ? FieldKind.money : FieldKind.number)
            : (lower.contains('date') || DateTime.tryParse('$v') != null
                ? FieldKind.date
                : FieldKind.text);

    // Keep the WEB's wording for the label, not the field name's.
    out.add(FieldSpec(key, label, kind: kind));
    if (out.length == 3) break;
  }
  return out;
}
