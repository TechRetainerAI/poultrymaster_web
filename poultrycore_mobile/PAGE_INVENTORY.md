# PoultryCore / VisibilityCore — page inventory

Every web page, what it does, the REST endpoint behind it, and whether the
Flutter app has it yet. Generated from the source, not written by hand:
page markup for titles and buttons, `lib/api/*.ts` for the endpoint each
page calls, and the API controllers for the verbs that endpoint supports.

| Field | Meaning |
|---|---|
| **Add / Edit / Del** | what the web page offers |
| **Verbs** | what the API supports for that endpoint |
| **Form** | `<FormSection>` fields extracted from the page |
| **Mobile** | ✅ live · ○ listed but unmapped · — not in mobile nav |

## Summary

- **268** web pages catalogued
- **214** live in the mobile app, **6** listed but not mapped
- **143** have a create button
- **80** have row edit, **90** row delete
- **656** form fields across **63** pages

## business-office (4 pages)

| Page | Route | Endpoint | Verbs | Add | Edit | Del | Form | Mobile |
|---|---|---|---|---|---|---|---|---|
| Business Office | `/business-office` | `/api/Announcements` | DELETE,GET,POST | Create company |  | 🗑 |  | ✅ |
| Egg Pick Time Settings | `/business-office/egg-pick-settings` | `—` | — | — |  |  |  | ✅ |
| Help Center | `/business-office/help` | `—` | — | — |  |  |  | — |
| Administration | `/business-office/setup` | `—` | — | — |  |  |  | ○ |

## generic (27 pages)

| Page | Route | Endpoint | Verbs | Add | Edit | Del | Form | Mobile |
|---|---|---|---|---|---|---|---|---|
| Generic Cash Transfers | `/generic-cash-transfers` | `—` | — | New transfer |  |  | 5f/3s | ✅ |
| Generic Customer Payments | `/generic-customer-payments` | `—` | — | Record payment |  |  | 5f/2s | ✅ |
| Generic Customers | `/generic-customers` | `—` | — | — | ✎ | 🗑 | 9f/4s | ✅ |
| Generic Dashboard | `/generic-dashboard` | `—` | — | New sale |  |  |  | ✅ |
| Generic Expenses | `/generic-expenses` | `—` | — | New expense |  |  |  | ✅ |
| Generic Expenses/New | `/generic-expenses/new` | `—` | — | New expense |  |  |  | — |
| Generic Internal Use | `/generic-internal-use` | `/api/generic-company/internal-usage/suggested-cost` | GET | Record internal use | ✎ | 🗑 | 9f/3s | ✅ |
| Inventory | `/generic-inventory` | `—` | — | — |  |  |  | ✅ |
| Generic Owner Money | `/generic-owner-money` | `—` | — | — |  |  | 8f/3s | ✅ |
| Generic Payroll | `/generic-payroll` | `—` | — | New payroll run |  |  | 5f/3s | ✅ |
| Generic Payroll/[Id] | `/generic-payroll/[id]` | `—` | — | Add line |  | 🗑 |  | — |
| Generic Products | `/generic-products` | `—` | — | New product | ✎ | 🗑 | 13f/4s | ✅ |
| Generic Purchases | `/generic-purchases` | `—` | — | New purchase |  |  |  | ✅ |
| Generic Purchases/New | `/generic-purchases/new` | `—` | — | New purchase |  |  |  | — |
| Generic Recurring Expenses | `/generic-recurring-expenses` | `—` | — | New recurring expense |  |  | 11f/4s | ✅ |
| Generic Sales | `/generic-sales` | `—` | — | New sale |  |  |  | ✅ |
| Generic Sales/[Id] | `/generic-sales/[id]` | `—` | — | — |  | 🗑 |  | — |
| Generic Sales/New | `/generic-sales/new` | `—` | — | New sale |  |  |  | — |
| Generic Service Plans | `/generic-service-plans` | `—` | — | — | ✎ |  | 5f/3s | ✅ |
| Generic Setup/Wizard | `/generic-setup/wizard` | `—` | — | Add your |  |  |  | ✅ |
| Generic Staff | `/generic-staff` | `—` | — | Add staff | ✎ | 🗑 | 10f/3s | ✅ |
| Generic Staff Payments | `/generic-staff-payments` | `—` | — | Record payment |  |  | 9f/4s | ✅ |
| Generic Staff/[Id] | `/generic-staff/[id]` | `—` | — | — |  | 🗑 |  | — |
| Generic Stock Adjustments | `/generic-stock-adjustments` | `—` | — | New adjustment |  |  | 6f/3s | ✅ |
| Generic Subscriptions | `/generic-subscriptions` | `—` | — | — |  |  | 8f/3s | ✅ |
| Generic Supplier Payments | `/generic-supplier-payments` | `—` | — | Record payment |  |  | 6f/3s | ✅ |
| Generic Suppliers | `/generic-suppliers` | `—` | — | New supplier | ✎ | 🗑 | 9f/4s | ✅ |

## hotel (45 pages)

| Page | Route | Endpoint | Verbs | Add | Edit | Del | Form | Mobile |
|---|---|---|---|---|---|---|---|---|
| Hotel Availability | `/hotel-availability` | `/api/Hotel/setup/room-types` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Hotel Billing | `/hotel-billing` | `/api/Hotel/billing/charges` | GET,POST | Add Charge |  |  |  | ✅ |
| Hotel Bookings | `/hotel-bookings` | `/api/Hotel/guests` | DELETE,GET,POST,PUT | New Booking | ✎ |  |  | ✅ |
| Hotel Cash Accounts | `/hotel-cash-accounts` | `—` | — | Add Account |  | 🗑 |  | ✅ |
| Hotel Check In | `/hotel-check-in` | `/api/Hotel/billing/charges` | GET,POST | — |  |  |  | ✅ |
| Hotel Check Out | `/hotel-check-out` | `/api/Hotel/billing/charges` | GET,POST | — |  |  |  | ✅ |
| Hotel Communications | `/hotel-communications` | `/api/Hotel/staff` | DELETE,GET,POST,PUT | Log Entry |  |  |  | ✅ |
| Hotel Company Setup | `/hotel-company-setup` | `/api/Hotel/setup/profile` | GET,POST | — |  |  |  | ✅ |
| Hotel Daily Closing | `/hotel-daily-closing` | `/api/Hotel/reports/daily-closings` | GET,POST | — |  |  |  | ✅ |
| Hotel Dashboard | `/hotel-dashboard` | `/api/Hotel/staff` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Hotel Expenses | `/hotel-expenses` | `/api/Hotel/finance/expense-categories` | GET,POST | Record Expense |  |  | 8f/3s | ✅ |
| Hotel Guest Requests | `/hotel-guest-requests` | `/api/Hotel/setup/request-types` | GET | New Request |  |  |  | ✅ |
| Hotel Guests | `/hotel-guests` | `/api/Hotel/guests` | DELETE,GET,POST,PUT | Add Guest | ✎ | 🗑 |  | ✅ |
| Hotel Housekeeping Schedule | `/hotel-housekeeping-schedule` | `/api/Hotel/staff` | DELETE,GET,POST,PUT | Add Schedule Entry |  |  |  | ✅ |
| Hotel Inventory | `/hotel-inventory` | `/api/Hotel/setup/supply-items` | GET | Add Item |  |  |  | ✅ |
| Hotel Lost Found | `/hotel-lost-found` | `—` | — | Log Item |  |  |  | ✅ |
| Hotel Maintenance | `/hotel-maintenance` | `/api/Hotel/setup/maintenance-assets` | GET | New Request |  |  |  | ✅ |
| Hotel Menu | `/hotel-menu` | `/api/Hotel/restaurant/tables` | GET,POST | Add Item | ✎ | 🗑 |  | ✅ |
| Hotel Night Audit | `/hotel-night-audit` | `/api/Hotel/night-audit` | GET,POST | — |  |  |  | ✅ |
| Hotel Payments | `/hotel-payments` | `/api/Hotel/finance/expenses` | GET,POST | Record Payment |  |  |  | ✅ |
| Hotel Payroll | `/hotel-payroll` | `/api/Hotel/payroll-runs` | DELETE,GET,POST | New payroll run |  | 🗑 | 12f/4s | ✅ |
| Reports are restricted | `/hotel-reports/[slug]` | `/api/Hotel/setup/profile` | GET,POST | — |  |  |  | — |
| Hotel Reports/Billing Report | `/hotel-reports/billing-report` | `/api/Hotel/setup/profile` | GET,POST | — |  |  |  | ✅ |
| Hotel Reports/Bookings Report | `/hotel-reports/bookings-report` | `/api/Hotel/setup/profile` | GET,POST | — |  |  |  | ✅ |
| Hotel Reports/Cash Flow Report | `/hotel-reports/cash-flow-report` | `/api/Hotel/setup/profile` | GET,POST | — |  |  |  | ✅ |
| Hotel Reports/Daily Report | `/hotel-reports/daily-report` | `/api/Hotel/reports/daily-closings` | GET,POST | — |  |  |  | ✅ |
| Hotel Reports/Expense Report | `/hotel-reports/expense-report` | `/api/Hotel/setup/profile` | GET,POST | — |  |  |  | ✅ |
| Hotel Reports/Guest Report | `/hotel-reports/guest-report` | `/api/Hotel/guests` | DELETE,GET,POST,PUT | New Guests |  |  |  | ✅ |
| Hotel Reports/Housekeeping Report | `/hotel-reports/housekeeping-report` | `/api/Hotel/setup/profile` | GET,POST | — |  |  |  | ✅ |
| Hotel Reports/Inventory Report | `/hotel-reports/inventory-report` | `/api/Hotel/setup/profile` | GET,POST | — |  |  |  | ✅ |
| Hotel Reports/Maintenance Report | `/hotel-reports/maintenance-report` | `/api/Hotel/setup/profile` | GET,POST | — |  |  |  | ✅ |
| Hotel Reports/Menu Performance | `/hotel-reports/menu-performance` | `/api/Hotel/setup/profile` | GET,POST | — |  |  |  | ✅ |
| Hotel Reports/Monthly Report | `/hotel-reports/monthly-report` | `/api/Hotel/reports/daily-closings` | GET,POST | — |  |  |  | ✅ |
| Hotel Reports/Occupancy Report | `/hotel-reports/occupancy-report` | `/api/Hotel/reports/daily-closings` | GET,POST | — |  |  |  | ✅ |
| Hotel Reports/Payroll Report | `/hotel-reports/payroll-report` | `/api/Hotel/payroll-runs` | DELETE,GET,POST | — |  |  |  | ✅ |
| Hotel Reports/Restaurant Sales | `/hotel-reports/restaurant-sales` | `/api/Hotel/setup/profile` | GET,POST | — |  |  |  | ✅ |
| Hotel Reports/Revenue Summary | `/hotel-reports/revenue-summary` | `/api/Hotel/reports/daily-closings` | GET,POST | — |  |  |  | ✅ |
| Hotel Reports/Weekly Report | `/hotel-reports/weekly-report` | `/api/Hotel/reports/daily-closings` | GET,POST | — |  |  |  | ✅ |
| Hotel Restaurant | `/hotel-restaurant` | `/api/Hotel/staff` | DELETE,GET,POST,PUT | — |  | 🗑 |  | ✅ |
| Hotel Restaurant Tables | `/hotel-restaurant-tables` | `/api/Hotel/setup/table-locations` | GET | Add Table |  |  |  | ✅ |
| Hotel Rooms | `/hotel-rooms` | `/api/Hotel/setup/room-types` | DELETE,GET,POST,PUT | Add Room |  |  |  | ✅ |
| Hotel Setup | `/hotel-setup` | `/api/Hotel/setup/amenities` | DELETE,GET,POST,PUT | Add Room | ✎ | 🗑 |  | ✅ |
| Hotel Shift Handover | `/hotel-shift-handover` | `/api/Hotel/staff` | DELETE,GET,POST,PUT | New Handover |  |  | 9f/3s | ✅ |
| Hotel Staff | `/hotel-staff` | `/api/Hotel/staff` | DELETE,GET,POST,PUT | Add Staff | ✎ | 🗑 | 9f/3s | ✅ |
| Hotel Stay History | `/hotel-stay-history` | `/api/Hotel/checkin-history` | GET | — |  |  |  | ✅ |

## poultry / shared (103 pages)

| Page | Route | Endpoint | Verbs | Add | Edit | Del | Form | Mobile |
|---|---|---|---|---|---|---|---|---|
| Audit Logs | `/audit-logs` | `—` | — | — |  |  |  | ✅ |
| Batch Production Records | `/batch-production-records` | `—` | — | Log Batch Production |  |  |  | ✅ |
| Batch Production Records/[Id] | `/batch-production-records/[id]` | `—` | — | — |  | 🗑 |  | — |
| Allocate Batch Production | `/batch-production-records/[id]/allocate` | `—` | — | Post Allocation |  |  |  | — |
| Edit Batch Production Record | `/batch-production-records/[id]/edit` | `—` | — | — |  |  |  | — |
| Add New Batch Production Record | `/batch-production-records/new` | `—` | — | Add New Batch Production Record |  |  |  | — |
| Cash | `/cash` | `—` | — | Add Adjustment | ✎ | 🗑 |  | ✅ |
| Cash Flow | `/cash-flow` | `/api/Poultry/cash-accounts` | DELETE,GET,POST,PUT | Add Adjustment | ✎ | 🗑 |  | ✅ |
| Companies | `/companies` | `—` | — | New company |  |  |  | ✅ |
| Customer Balances | `/customer-balances` | `/api/Poultry/cash-accounts` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Customers | `/customers` | `/api/Customer` | — | Add Customer | ✎ | 🗑 |  | ✅ |
| Edit Customer | `/customers/[id]` | `—` | — | — | ✎ |  |  | — |
| Add New Customer | `/customers/new` | `—` | — | Add New Customer |  |  |  | — |
| Egg Sorting | `/egg-production` | `—` | — | Add Egg Sorting record | ✎ | 🗑 |  | ✅ |
| Edit Production Record | `/egg-production/[id]` | `—` | — | — |  |  |  | — |
| Add New Egg Sorting Record | `/egg-production/new` | `/api/Poultry/raw-material-purchases` | DELETE,GET,POST,PUT | Add New Egg Sorting Record |  |  |  | — |
| Egg tracker | `/egg-tracker` | `/api/Poultry/products` | DELETE,GET,POST,PUT | Add adjustment | ✎ | 🗑 |  | ✅ |
| Employees | `/employees` | `—` | — | Add Employee | ✎ | 🗑 |  | ✅ |
| Edit Employee | `/employees/[id]` | `—` | — | — |  |  |  | — |
| Add New Employee | `/employees/new` | `—` | — | Add New Employee |  |  |  | — |
| Expenses | `/expenses` | `/api/Expense` | — | Add Expense | ✎ | 🗑 |  | ✅ ★ |
| Edit Expense | `/expenses/[id]` | `/api/Poultry/cash-accounts` | DELETE,GET,POST,PUT | — |  |  |  | — |
| Add Expense | `/expenses/new` | `/api/Poultry/cash-accounts` | DELETE,GET,POST,PUT | Add Expense |  |  |  | — |
| Feed inventory tracker | `/feed-inventory-tracker` | `/api/Poultry/raw-material-purchases` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Feed Usage | `/feed-usage` | `—` | — | Add Usage | ✎ | 🗑 |  | ✅ |
| Edit Feed Usage | `/feed-usage/[id]` | `—` | — | — |  |  |  | — |
| Add Feed Usage | `/feed-usage/new` | `—` | — | Add Feed Usage |  |  |  | — |
| Flock Purchases (Batches) | `/flock-batch` | `—` | — | Add Flock Batch | ✎ | 🗑 |  | ✅ |
| Edit Flock Batch | `/flock-batch/[id]` | `—` | — | — |  |  |  | — |
| Add New Flock Batch | `/flock-batch/new` | `—` | — | Add New Flock Batch |  |  |  | — |
| Flock Groups (Pens / Flocks) | `/flocks` | `/api/MainFlockBatch` | — | Add Flock | ✎ | 🗑 |  | ✅ ★ |
| Edit Flock | `/flocks/[id]` | `—` | — | — |  |  |  | — |
| Add New Flock | `/flocks/new` | `—` | — | Add New Flock |  |  |  | — |
| Poultry Core | `/forgot-password` | `—` | — | — |  |  |  | — |
| Health Records | `/health` | `/api/Health` | — | Add Health Record | ✎ | 🗑 |  | ✅ |
| Help Center | `/help` | `—` | — | — |  |  |  | ○ |
| Houses | `/houses` | `/api/House` | — | Add House | ✎ | 🗑 |  | ✅ |
| Other Inventory | `/inventory` | `—` | — | Add Item | ✎ | 🗑 |  | ✅ |
| VisibilityCore | `/login` | `—` | — | Create an account |  |  |  | — |
| Medication Tracker | `/medication-tracker` | `/api/Poultry/raw-material-purchases` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Capital Investments/Assets | `/poultry-assets` | `/api/Poultry/assets` | GET,POST,PUT | New investment | ✎ |  | 41f/8s | ✅ ★ |
| Poultry Assets/[Id] | `/poultry-assets/[id]` | `/api/Poultry/assets` | GET,POST,PUT | — |  |  |  | — ★ |
| Poultry Cash Accounts | `/poultry-cash-accounts` | `/api/Poultry/cash-accounts` | DELETE,GET,POST,PUT | Record Cash Adjustment | ✎ | 🗑 | 11f/5s | ✅ |
| Poultry Cash Accounts/[Id] | `/poultry-cash-accounts/[id]` | `/api/Poultry/cash-accounts` | DELETE,GET,POST,PUT | — |  | 🗑 | 3f/1s | — |
| Poultry Cash Reconciliation | `/poultry-cash-reconciliation` | `—` | — | Post it | ✎ | 🗑 |  | ✅ |
| Poultry Cash Transfers | `/poultry-cash-transfers` | `/api/Poultry/cash-accounts` | DELETE,GET,POST,PUT | Record transfer |  |  | 7f/3s | ✅ |
| Closing by Category | `/poultry-closing-report` | `—` | — | — |  |  |  | ✅ |
| Poultry Closing Report Daily | `/poultry-closing-report-daily` | `/api/Poultry/daily-closings` | DELETE,GET,POST | — |  |  |  | ✅ |
| Poultry Company Setup | `/poultry-company-setup` | `/api/Poultry/company` | GET,PUT | — |  |  |  | ✅ |
| Daily Closing | `/poultry-daily-closing` | `/api/Poultry/daily-closings` | DELETE,GET,POST | New closing | ✎ | 🗑 |  | ✅ |
| Poultry Daily Summary | `/poultry-daily-summary` | `/api/Poultry/daily-closings` | DELETE,GET,POST | — |  |  |  | ✅ |
| Deferred inventory cost | `/poultry-deferred-costs` | `/api/Poultry/deferred-inventory-costs` | GET | — |  |  |  | ✅ |
| Poultry Deliveries | `/poultry-deliveries` | `/api/Poultry/deliveries` | GET | New load |  |  | 17f/3s | ✅ |
| Poultry Driver Report | `/poultry-driver-report` | `/api/Poultry/drivers` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Poultry Driver Returns | `/poultry-driver-returns` | `/api/Poultry/driver-returns` | DELETE,GET,POST | Add product | ✎ | 🗑 | 6f/3s | ✅ |
| Poultry Driver Returns/[Id] | `/poultry-driver-returns/[id]` | `/api/Poultry/driver-returns` | DELETE,GET,POST | — |  |  |  | — |
| Poultry Drivers | `/poultry-drivers` | `/api/Poultry/drivers` | DELETE,GET,POST,PUT | New employee | ✎ | 🗑 | 19f/5s | ✅ |
| Poultry Employee Loans | `/poultry-employee-loans` | `/api/Poultry/employee-loans` | DELETE,GET,POST,PUT | New loan / advance |  |  |  | ✅ ★ |
| Feed Formulas | `/poultry-feed-formulas` | `/api/Poultry/feed-formulas` | DELETE,GET,POST | New Formula | ✎ | 🗑 | 5f/1s | ✅ |
| Feed Production | `/poultry-feed-production` | `/api/Poultry/feed-production` | DELETE,GET,POST | New Batch | ✎ | 🗑 |  | ✅ |
| Poultry Feed Production/[Id] | `/poultry-feed-production/[id]` | `/api/Poultry/feed-production` | DELETE,GET,POST | — | ✎ | 🗑 |  | — |
| Poultry Feed Production/Reports | `/poultry-feed-production/reports` | `/api/Poultry/feed-production` | DELETE,GET,POST | — |  |  |  | ✅ |
| Financial Activity | `/poultry-financial-activity` | `—` | — | — |  |  |  | ✅ |
| Poultry Financial Settings | `/poultry-financial-settings` | `/api/Poultry/financial-settings/cost-recognition` | GET,PUT | — |  |  |  | ✅ |
| Poultry Internal Use | `/poultry-internal-use` | `/api/Poultry/internal-usage/suggested-cost` | GET | Record internal use | ✎ | 🗑 | 10f/3s | ✅ |
| Poultry inventory | `/poultry-inventory` | `/api/Poultry/products` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Poultry Loans | `/poultry-loans` | `/api/Poultry/loans` | GET,POST,PUT | Record loan |  |  | 14f/5s | ✅ ★ |
| Loss & Damage Records | `/poultry-loss-records` | `/api/Poultry/loss-records` | DELETE,GET,POST,PUT | New record | ✎ | 🗑 | 6f/1s | ✅ |
| Poultry Owner Money | `/poultry-owner-money` | `/api/Poultry/owner-money` | GET,POST,PUT | Record contribution |  |  | 8f/3s | ✅ ★ |
| Poultry Payroll | `/poultry-payroll` | `/api/Poultry/payroll-deductions` | DELETE,GET,POST | New payroll run | ✎ | 🗑 | 15f/3s | ✅ |
| Poultry Payroll/[Id] | `/poultry-payroll/[id]` | `/api/Poultry/payroll-runs` | DELETE,GET,POST | — |  |  |  | — |
| Products | `/poultry-products` | `/api/Poultry/products` | DELETE,GET,POST,PUT | New product | ✎ | 🗑 | 12f/3s | ✅ |
| Raw Materials &amp; Supplies | `/poultry-raw-materials` | `/api/Poultry/raw-material-items` | DELETE,GET,POST,PUT | New Item | ✎ | 🗑 | 11f/3s | ✅ ★ |
| Reports | `/poultry-reports` | `—` | — | — |  |  |  | — |
| Poultry Reports/Closing Report | `/poultry-reports/closing-report` | `/api/Poultry/daily-closings` | DELETE,GET,POST | — |  |  |  | ✅ |
| Poultry Reports/Daily Summary | `/poultry-reports/daily-summary` | `/api/Poultry/daily-closings` | DELETE,GET,POST | — |  |  |  | ✅ |
| Poultry Reports/Delivery Run Report | `/poultry-reports/delivery-run-report` | `/api/Poultry/driver-returns` | DELETE,GET,POST | — |  |  |  | ✅ |
| Poultry Reports/Driver Accountability | `/poultry-reports/driver-accountability` | `/api/Poultry/reports/driver-reconciliation` | GET | — |  |  |  | ✅ |
| Poultry Reports/Driver Collection | `/poultry-reports/driver-collection` | `/api/Poultry/reports/driver-collection` | GET | — |  |  |  | ✅ |
| Poultry Routes | `/poultry-routes` | `/api/Poultry/vehicles` | DELETE,GET,POST,PUT | New route | ✎ | 🗑 | 6f/3s | ✅ |
| Poultry farm setup | `/poultry-setup` | `—` | — | — | ✎ | 🗑 |  | ✅ |
| Poultry Staff | `/poultry-staff` | `/api/Poultry/staff` | DELETE,GET,POST,PUT | New staff | ✎ | 🗑 | 14f/4s | ✅ |
| Stock Movements | `/poultry-stock` | `/api/Poultry/products/reconcile-stock` | GET | New movement |  |  | 5f/1s | ✅ |
| Poultry Vehicles | `/poultry-vehicles` | `/api/Poultry/vehicles` | DELETE,GET,POST,PUT | New vehicle | ✎ | 🗑 | 7f/3s | ✅ |
| Batch Production Summary | `/poultry/reports/batch-production-summary` | `—` | — | — |  |  |  | ✅ |
| Poultry/Reports/Cash Accounts | `/poultry/reports/cash-accounts` | `/api/Poultry/cash-accounts` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Poultry Changes Report | `/poultry/reports/changes` | `—` | — | Record details |  |  |  | ✅ |
| Poultry/Reports/Money | `/poultry/reports/money` | `/api/Poultry/owner-money` | GET,POST,PUT | — |  |  |  | ✅ ★ |
| Production Records | `/production-records` | `—` | — | Log Production | ✎ | 🗑 |  | ✅ ★ |
| Edit Egg Production Record | `/production-records/[id]` | `—` | — | — |  |  |  | — |
| Add Production Record | `/production-records/new` | `—` | — | Add Production Record |  |  |  | — |
| Profile | `/profile` | `—` | — | — | ✎ |  |  | ○ |
| VisibilityCore | `/register` | `—` | — | Create your account |  |  |  | — |
| Reports | `/reports` | `—` | — | New Report |  |  |  | ○ |
| Reset Password | `/reset-password` | `—` | — | New Password |  |  |  | — |
| Resources & Information Center | `/resources` | `—` | — | Add Schedule | ✎ | 🗑 |  | ○ |
| Sales | `/sales` | `/api/Sale` | — | Add Sale | ✎ | 🗑 |  | ✅ ★ |
| Supplier Balances | `/supplier-balances` | `/api/Poultry/cash-accounts` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Supplier Payments | `/supplier-payments` | `/api/Poultry/cash-accounts` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Suppliers | `/suppliers` | `/api/Supplier` | — | Add supplier | ✎ | 🗑 |  | ✅ |
| Supplies | `/supplies` | `—` | — | Add Supply | ✎ | 🗑 |  | ✅ |
| System farms | `/system-farms` | `—` | — | — |  |  |  | ✅ |
| Terms & Conditions | `/terms` | `—` | — | — |  |  |  | ○ |

## restaurant (23 pages)

| Page | Route | Endpoint | Verbs | Add | Edit | Del | Form | Mobile |
|---|---|---|---|---|---|---|---|---|
| Customer Relationships | `/restaurant-crm` | `/api/Restaurant/crm/feedback` | GET,POST | Add Customer | ✎ | 🗑 |  | ✅ |
| Restaurant Dashboard | `/restaurant-dashboard` | `/api/Restaurant/orders` | GET,POST | — |  |  |  | ✅ ★ |
| Delivery Management | `/restaurant-delivery` | `/api/Restaurant/delivery/zones` | DELETE,GET,POST,PUT | Add Driver | ✎ | 🗑 |  | ✅ |
| Restaurant Events | `/restaurant-events` | `/api/Restaurant/events` | DELETE,GET,POST,PUT | New Event |  | 🗑 |  | ✅ |
| Restaurant Expenses | `/restaurant-expenses` | `/api/Restaurant/expenses` | DELETE,GET,POST,PUT | Record Expense |  | 🗑 |  | ✅ |
| Restaurant Floor Plan | `/restaurant-floor-plan` | `/api/Restaurant/floor/floors` | DELETE,GET,POST,PUT | Add Area | ✎ | 🗑 |  | ✅ |
| Restaurant Gift Cards | `/restaurant-gift-cards` | `/api/Restaurant/gift-cards` | DELETE,GET,POST,PUT | Issue Card |  |  |  | ✅ |
| Restaurant Inventory | `/restaurant-inventory` | `/api/Restaurant/inventory/ingredients` | DELETE,GET,POST,PUT | Add Ingredient | ✎ | 🗑 |  | ✅ |
| Restaurant Kds | `/restaurant-kds` | `/api/Restaurant/kds/stations` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Restaurant Loyalty | `/restaurant-loyalty` | `/api/Restaurant/loyalty/accounts` | GET,POST | Add Points |  |  |  | ✅ |
| Restaurant Menu | `/restaurant-menu` | `/api/Restaurant/menu/item-names` | GET,POST | Add Menu Item | ✎ | 🗑 |  | ✅ |
| Restaurant Notifications | `/restaurant-notifications` | `/api/Restaurant/notifications` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Online Ordering | `/restaurant-online-orders` | `/api/Restaurant/online/qr-codes` | DELETE,GET,POST | Create it | ✎ | 🗑 |  | ✅ |
| Restaurant not found | `/restaurant-order-online` | `—` | — | — |  | 🗑 |  | ✅ |
| Restaurant Orders | `/restaurant-orders` | `/api/Restaurant/orders` | GET,POST | New Guest Orders |  |  |  | ✅ ★ |
| Income & Expenses | `/restaurant-payments` | `/api/Restaurant/orders` | GET,POST | — |  |  |  | ✅ ★ |
| Restaurant Pending Orders | `/restaurant-pending-orders` | `/api/Restaurant/online/pending-orders` | GET | — |  |  |  | ✅ |
| Restaurant Pos | `/restaurant-pos` | `/api/Restaurant/orders` | GET,POST | New Order |  |  |  | ✅ ★ |
| Restaurant Qr Print | `/restaurant-qr-print` | `/api/Restaurant/online/qr-codes` | DELETE,GET,POST | — |  |  |  | ✅ |
| Reports are restricted | `/restaurant-reports/[slug]` | `/api/Restaurant/setup/profile` | GET,POST | — |  |  |  | — |
| Reservations & Waitlist | `/restaurant-reservations` | `/api/Restaurant/reservations` | DELETE,GET,POST,PUT | New Reservation | ✎ | 🗑 |  | ✅ |
| Restaurant Setup | `/restaurant-setup` | `/api/Restaurant/setup/profile` | GET,POST | Add Schedule | ✎ | 🗑 |  | ✅ |
| Restaurant Staff | `/restaurant-staff` | `—` | — | Add Staff | ✎ | 🗑 |  | ✅ |

## water (66 pages)

| Page | Route | Endpoint | Verbs | Add | Edit | Del | Form | Mobile |
|---|---|---|---|---|---|---|---|---|
| Assets | `/water-assets` | `/api/Water/assets` | GET,POST,PUT | New asset | ✎ |  | 40f/8s | ✅ |
| Water Assets/[Id] | `/water-assets/[id]` | `/api/Water/assets` | GET,POST,PUT | — |  |  |  | — |
| Water Boreholes | `/water-boreholes` | `/api/Water/boreholes` | DELETE,GET,POST,PUT | New borehole | ✎ | 🗑 | 14f/5s | ✅ |
| Water Cash Accounts | `/water-cash-accounts` | `/api/Water/cash-reconciliations/account-status` | GET | Record Cash Adjustment | ✎ | 🗑 | 11f/5s | ✅ |
| Water Cash Accounts/[Id] | `/water-cash-accounts/[id]` | `/api/Water/cash-accounts` | DELETE,GET,POST,PUT | — |  | 🗑 | 4f/1s | — ★ |
| Water Cash Flow | `/water-cash-flow` | `—` | — | Add Adjustment | ✎ | 🗑 |  | ✅ |
| Water Cash Reconciliation | `/water-cash-reconciliation` | `—` | — | Post it | ✎ | 🗑 |  | ✅ |
| Water Cash Transfers | `/water-cash-transfers` | `/api/Water/cash-transfers` | DELETE,GET,POST,PUT | Record transfer |  |  | 7f/3s | ✅ |
| Water Company Setup | `/water-company-setup` | `/api/Water/company` | GET,PUT | — |  |  |  | ✅ |
| Water Customers | `/water-customers` | `—` | — | New customer | ✎ | 🗑 | 6f/3s | ✅ |
| Water Daily Closing | `/water-daily-closing` | `/api/Water/daily-closings` | DELETE,GET,POST | Create draft | ✎ | 🗑 |  | ✅ |
| Batch production | `/water-daily-production` | `/api/Water/daily-productions` | DELETE,GET,POST,PUT | Log batch production | ✎ | 🗑 |  | ✅ |
| Water Daily Production/[Id] | `/water-daily-production/[id]` | `/api/Water/daily-productions` | DELETE,GET,POST,PUT | — | ✎ |  |  | — |
| Water Daily Production/[Id]/Allocate | `/water-daily-production/[id]/allocate` | `/api/Water/daily-productions` | DELETE,GET,POST,PUT | Post allocation |  |  |  | — |
| Water Daily Production/[Id]/Edit | `/water-daily-production/[id]/edit` | `/api/Water/daily-productions` | DELETE,GET,POST,PUT | — |  |  |  | — |
| Water Dashboard | `/water-dashboard` | `/api/Water/expenses` | DELETE,GET,POST,PUT | — |  |  |  | ✅ ★ |
| Deferred inventory cost | `/water-deferred-costs` | `/api/Water/deferred-inventory-costs` | GET | — |  |  |  | ✅ |
| Water Driver Report | `/water-driver-report` | `/api/Water/reports/driver-collection` | GET | — |  |  |  | ✅ |
| Water Driver Returns | `/water-driver-returns` | `/api/Water/driver-returns` | DELETE,GET,POST | Add product | ✎ | 🗑 | 12f/5s | ✅ |
| Water Driver Returns/[Id] | `/water-driver-returns/[id]` | `/api/Water/driver-returns` | DELETE,GET,POST | — |  |  |  | — |
| Water Drivers | `/water-drivers` | `/api/Water/drivers/list-for-farm` | GET | New employee | ✎ | 🗑 | 17f/5s | ✅ |
| Water Expenses | `/water-expenses` | `/api/Water/expenses` | DELETE,GET,POST,PUT | Record expense |  |  | 10f/3s | ✅ ★ |
| Water Financial Settings | `/water-financial-settings` | `/api/Water/financial-settings/items` | GET | — |  |  |  | ✅ |
| Water Internal Use | `/water-internal-use` | `/api/Water/internal-usage/suggested-cost` | GET | Record internal use | ✎ | 🗑 | 10f/3s | ✅ |
| Water inventory | `/water-inventory` | `/api/Water/products` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Inventory tracker | `/water-inventory-tracker` | `/api/Water/reports/inventory-tracker` | GET | — |  |  |  | ✅ |
| Water Loans | `/water-loans` | `/api/Water/loans` | GET,POST,PUT | Record loan |  |  | 14f/5s | ✅ |
| Water Loss Records | `/water-loss-records` | `/api/Water/loss-records` | DELETE,GET,POST,PUT | Record loss | ✎ |  | 7f/3s | ✅ |
| Water Machines | `/water-machines` | `—` | — | New machine | ✎ | 🗑 | 11f/4s | ✅ |
| Water Maintenance | `/water-maintenance` | `/api/Water/maintenance-logs` | DELETE,GET,POST,PUT | Log issue |  | 🗑 | 8f/4s | ✅ ★ |
| Water Owner Money | `/water-owner-money` | `/api/Water/owner-money` | GET,POST,PUT | Record contribution |  |  | 8f/3s | ✅ |
| Water Payroll | `/water-payroll` | `/api/Water/payroll-runs` | DELETE,GET,POST | New run |  | 🗑 | 4f/3s | ✅ |
| Water Payroll/[Id] | `/water-payroll/[id]` | `/api/Water/payroll-runs` | DELETE,GET,POST | — |  | 🗑 |  | — |
| Production | `/water-production-batches` | `/api/Water/production-batches` | DELETE,GET,POST,PUT | Record production | ✎ | 🗑 | 14f/4s | ✅ |
| {batch?.batchNumber ?? `Production #${ | `/water-production-batches/[id]` | `/api/Water/production-batches` | DELETE,GET,POST,PUT | — |  |  |  | — |
| Production losses | `/water-production-losses` | `/api/Water/production-losses` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Water Products | `/water-products` | `/api/Water/products` | DELETE,GET,POST,PUT | New product | ✎ | 🗑 | 12f/4s | ✅ |
| Water Products/[Id] | `/water-products/[id]` | `/api/Water/products` | DELETE,GET,POST,PUT | Add material |  | 🗑 |  | — |
| Water Raw Materials | `/water-raw-materials` | `/api/Water/raw-material-purchases` | DELETE,GET,POST,PUT | New item | ✎ | 🗑 | 26f/8s | ✅ |
| Water Reports/Cash Accounts | `/water-reports/cash-accounts` | `/api/Water/cash-reconciliations/account-status` | GET | — |  |  |  | ✅ |
| Water Reports/Closing Report | `/water-reports/closing-report` | `/api/Water/daily-closings` | DELETE,GET,POST | — |  |  |  | ✅ |
| Water Reports/Daily Summary | `/water-reports/daily-summary` | `/api/Water/daily-closings` | DELETE,GET,POST | — |  |  |  | ✅ |
| Water Reports/Delivery Run Report | `/water-reports/delivery-run-report` | `/api/Water/driver-returns` | DELETE,GET,POST | — |  |  |  | ✅ |
| Water Reports/Driver Accountability | `/water-reports/driver-accountability` | `/api/Water/reports/driver-reconciliation` | GET | — |  |  |  | ✅ |
| Water Reports/Driver Collection | `/water-reports/driver-collection` | `/api/Water/reports/driver-collection` | GET | — |  |  |  | ✅ |
| Water Reports/Expense Report | `/water-reports/expense-report` | `/api/Water/expenses` | DELETE,GET,POST,PUT | — |  |  |  | ✅ ★ |
| Water Reports/Inventory Report | `/water-reports/inventory-report` | `/api/Water/products` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Water Reports/Loss Report | `/water-reports/loss-report` | `/api/Water/loss-records` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Water Reports/Money Movement | `/water-reports/money-movement` | `/api/Water/owner-money` | GET,POST,PUT | — |  |  |  | ✅ |
| Water Reports/Operational | `/water-reports/operational` | `/api/Water/reports/driver-reconciliation` | GET | — |  |  |  | ✅ |
| Water Reports/Product Performance | `/water-reports/product-performance` | `/api/Water/products` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Water Reports/Production Report | `/water-reports/production-report` | `/api/Water/production-batches` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Water Reports/Profit Loss | `/water-reports/profit-loss` | `/api/Water/reports/period-pnl` | GET | — |  |  |  | ✅ |
| Water Reports/Raw Material Purchase | `/water-reports/raw-material-purchase` | `/api/Water/raw-material-purchases` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Water Reports/Raw Material Usage | `/water-reports/raw-material-usage` | `/api/Water/raw-material-usage/history` | GET,POST | — |  |  |  | ✅ |
| Water Reports/Route Performance | `/water-reports/route-performance` | `/api/Water/reports/route-profitability` | GET | — |  |  |  | ✅ |
| Water Reports/Supplier Activity | `/water-reports/supplier-activity` | `/api/Water/reports/supplier-activity` | GET | — |  |  |  | ✅ |
| Water Reports/Top Customers | `/water-reports/top-customers` | `/api/Water/reports/top-customers` | GET | — |  |  |  | ✅ |
| Water Reports/Vehicle Usage | `/water-reports/vehicle-usage` | `/api/Water/vehicles` | DELETE,GET,POST,PUT | — |  |  |  | ✅ |
| Water Routes | `/water-routes` | `/api/Water/vehicles` | DELETE,GET,POST,PUT | New route | ✎ | 🗑 | 6f/3s | ✅ |
| Water Sales | `/water-sales` | `/api/Water/sales` | DELETE,GET,POST | New sale |  | 🗑 |  | ✅ ★ |
| Water company setup | `/water-setup` | `/api/Water/vehicles` | DELETE,GET,POST,PUT | — | ✎ | 🗑 | 12f/5s | ✅ |
| Water Staff | `/water-staff` | `/api/Water/staff` | DELETE,GET,POST,PUT | New staff | ✎ | 🗑 | 11f/4s | ✅ ★ |
| Water Stock | `/water-stock` | `/api/Water/products/reconcile-stock` | GET | New entry |  |  | 4f/1s | ✅ |
| Water Suppliers | `/water-suppliers` | `/api/Water/suppliers` | DELETE,GET,POST,PUT | New supplier | ✎ | 🗑 | 8f/3s | ✅ |
| Water Vehicles | `/water-vehicles` | `/api/Water/vehicles` | DELETE,GET,POST,PUT | New vehicle | ✎ | 🗑 | 7f/3s | ✅ |

---

★ = hand-tuned spec in the mobile app (proper field labels
and summaries); the rest render from whatever the endpoint returns.
