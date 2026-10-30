import 'package:flutter/widgets.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../custom_form.dart';
import '../form_spec.dart';
import '../form_screen.dart';
import '../registry.dart';
import '../poultry/expenses/recurring_expenses_screen.dart';
import '../poultry/sales/balances_logic.dart' show BalanceRail, BalanceSide;
import '../poultry/expenses/supplier_payments_screen.dart';
import '../poultry/sales/customer_balances_screen.dart';
import '../poultry/sales/payments_received_screen.dart';
import 'water_sales_screen.dart';
import 'water_internal_use_screen.dart';
import 'water_payroll_screen.dart';
import 'water_expenses_screen.dart';
import 'water_deferred_costs_screen.dart';
import 'water_production_screen.dart';
import 'water_batch_production_screen.dart';
import 'water_maintenance_screen.dart';
import 'water_stock_screen.dart';
import 'water_raw_materials_screen.dart';
import 'water_losses_screen.dart';
import 'water_deliveries_screen.dart';
import '../poultry/expenses/assets_screen.dart' show AssetsScreen;
import '../poultry/expenses/asset_logic.dart' show AssetRail;
import '../poultry/expenses/employee_loans_screen.dart';
import '../poultry/money/cash_accounts_screen.dart';
import '../poultry/money/cash_flow_screen.dart';
import '../poultry/money/cash_transfers_screen.dart';
import '../poultry/money/reconciliation_screen.dart';
import '../poultry/money/loans_screen.dart';
import '../poultry/money/owner_money_screen.dart';
import 'reports/water_money_reports.dart' show waterMoneyRail, WaterProfitLossScreen;
import 'water_company_setup_screen.dart';
import 'water_driver_employee_screen.dart';
import 'water_financial_settings_screen.dart';
import 'water_labels.dart';
import 'water_product_screens.dart';
import 'water_setup_screen.dart';
import 'water_staff_form_screen.dart';

/// Water's forms, copied from the Water web pages' own dialogs — never from
/// Poultry's. Same sections, colours, labels, placeholders, required marks,
/// defaults (each page's EMPTY) and the body each `lib/api/water.ts` call
/// sends, including the record id on update.
const Map<String, FormDef> waterForms = {
  // app/water-customers/page.tsx
  'water-customers': FormDef(
    route: '/water-customers',
    specKey: 'water-customers',
    idKey: 'waterCustomerId',
    sections: [
      FormSectionDef(title: 'Identity', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'Name', kind: FormFieldKind.text, required: true, full: true, name: 'name'),
        FormFieldDef(label: 'Phone', kind: FormFieldKind.text, name: 'contactPhone'),
        FormFieldDef(label: 'Email', kind: FormFieldKind.text, name: 'contactEmail'),
      ]),
      FormSectionDef(title: 'Address', color: 'green', columns: 2, fields: [
        FormFieldDef(label: 'Address', kind: FormFieldKind.text, full: true, name: 'address'),
        FormFieldDef(label: 'City', kind: FormFieldKind.text, name: 'city'),
      ]),
      FormSectionDef(title: 'Notes', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),

  // app/water-suppliers/page.tsx — Active is a yes/no select over a boolean.
  'water-suppliers': FormDef(
    route: '/water-suppliers',
    specKey: 'water-suppliers',
    idKey: 'waterSupplierId',
    createdByKey: 'createdBy',
    updatedByKey: 'updatedBy',
    sections: [
      FormSectionDef(title: 'Identity', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'Supplier name', kind: FormFieldKind.text, required: true, full: true, name: 'supplierName'),
        FormFieldDef(label: 'Supplier type', kind: FormFieldKind.select, name: 'supplierType', initial: 'Other'),
        FormFieldDef(label: 'Active', kind: FormFieldKind.select, name: 'isActive', yesNo: true, initial: 'yes'),
      ]),
      FormSectionDef(title: 'Contact', color: 'green', columns: 2, fields: [
        FormFieldDef(label: 'Contact person', kind: FormFieldKind.text, name: 'contactPerson'),
        FormFieldDef(label: 'Phone', kind: FormFieldKind.text, name: 'phone'),
        FormFieldDef(label: 'Email', kind: FormFieldKind.text, name: 'email'),
        FormFieldDef(label: 'Address', kind: FormFieldKind.text, full: true, name: 'address'),
      ]),
      FormSectionDef(title: 'Notes', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),

  // app/water-machines/page.tsx — Setup → Plant.
  'water-machines': FormDef(
    route: '/water-machines',
    specKey: 'water-machines',
    idKey: 'waterMachineId',
    sections: [
      FormSectionDef(title: 'Identity', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'Machine name', kind: FormFieldKind.text, required: true, full: true, name: 'machineName'),
        FormFieldDef(label: 'Machine number', kind: FormFieldKind.text, name: 'machineNumber'),
        FormFieldDef(label: 'Type', kind: FormFieldKind.text, placeholder: 'e.g. Sachet filling, Bottling', name: 'machineType'),
        FormFieldDef(label: 'Manufacturer', kind: FormFieldKind.text, name: 'manufacturer'),
      ]),
      FormSectionDef(title: 'Details', color: 'blue', columns: 2, fields: [
        FormFieldDef(label: 'Capacity / hour (bags)', kind: FormFieldKind.number, name: 'capacityPerHour'),
        FormFieldDef(label: 'Purchase date', kind: FormFieldKind.date, name: 'purchaseDate', dateBound: DateBound.past),
        FormFieldDef(label: 'Status', kind: FormFieldKind.select, full: true, name: 'status', initial: 'Active'),
      ]),
      FormSectionDef(title: 'Maintenance', color: 'amber', columns: 2, fields: [
        FormFieldDef(label: 'Maintenance frequency (days)', kind: FormFieldKind.number, full: true, name: 'maintenanceFrequencyDays'),
        FormFieldDef(label: 'Last maintenance', kind: FormFieldKind.date, name: 'lastMaintenanceDate', dateBound: DateBound.past),
        FormFieldDef(label: 'Next maintenance', kind: FormFieldKind.date, name: 'nextMaintenanceDate', dateBound: DateBound.future),
      ]),
      FormSectionDef(title: 'Notes', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),

  // app/water-boreholes/page.tsx — Setup → Plant.
  'water-boreholes': FormDef(
    route: '/water-boreholes',
    specKey: 'water-boreholes',
    idKey: 'waterBoreholeId',
    sections: [
      FormSectionDef(title: 'Identity', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'Borehole name', kind: FormFieldKind.text, required: true, full: true, name: 'boreholeName'),
        FormFieldDef(label: 'Location', kind: FormFieldKind.text, full: true, name: 'location'),
      ]),
      FormSectionDef(title: 'Pump & Tank', color: 'blue', columns: 2, fields: [
        FormFieldDef(label: 'Pump type', kind: FormFieldKind.text, name: 'pumpType'),
        FormFieldDef(label: 'Pump capacity', kind: FormFieldKind.text, placeholder: 'e.g. 5000 L/hr', name: 'pumpCapacity'),
        FormFieldDef(label: 'Tank capacity', kind: FormFieldKind.text, full: true, placeholder: 'e.g. 10000 L', name: 'tankCapacity'),
      ]),
      FormSectionDef(title: 'Treatment', color: 'sky', columns: 2, fields: [
        FormFieldDef(label: 'Treatment method', kind: FormFieldKind.text, name: 'waterTreatmentMethod'),
        FormFieldDef(label: 'Filtration', kind: FormFieldKind.text, name: 'filtrationSystem'),
        FormFieldDef(label: 'UV sterilization', kind: FormFieldKind.bool, full: true, name: 'uvSterilizationAvailable', placeholder: 'Available', initial: 'false'),
        FormFieldDef(label: 'Status', kind: FormFieldKind.select, full: true, name: 'status', initial: 'Active'),
      ]),
      FormSectionDef(title: 'Maintenance', color: 'amber', columns: 2, fields: [
        FormFieldDef(label: 'Maint. frequency (days)', kind: FormFieldKind.number, full: true, name: 'maintenanceFrequencyDays'),
        FormFieldDef(label: 'Last maintenance', kind: FormFieldKind.date, name: 'lastMaintenanceDate', dateBound: DateBound.past),
        FormFieldDef(label: 'Next maintenance', kind: FormFieldKind.date, name: 'nextMaintenanceDate', dateBound: DateBound.future),
        FormFieldDef(label: 'Water quality test due date', kind: FormFieldKind.date, full: true, name: 'waterQualityTestDueDate', dateBound: DateBound.future),
      ]),
      FormSectionDef(title: 'Notes', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),

  // app/water-vehicles/page.tsx — Setup → Delivery. The dialog has no driver
  // field, but the web sends the record's defaultDriverStaffId back on update.
  'water-vehicles': FormDef(
    route: '/water-vehicles',
    specKey: 'water-vehicles',
    idKey: 'waterVehicleId',
    carry: ['defaultDriverStaffId'],
    sections: [
      FormSectionDef(title: 'Identity', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'Vehicle name', kind: FormFieldKind.text, required: true, full: true, placeholder: 'e.g. Truck 1', name: 'vehicleName'),
        FormFieldDef(label: 'Type', kind: FormFieldKind.select, name: 'vehicleType', initial: 'Truck'),
        FormFieldDef(label: 'Registration #', kind: FormFieldKind.text, name: 'registrationNumber'),
      ]),
      FormSectionDef(title: 'Details', color: 'blue', columns: 2, fields: [
        FormFieldDef(label: 'Capacity (bags)', kind: FormFieldKind.number, name: 'capacityBags'),
        FormFieldDef(label: 'Fuel type', kind: FormFieldKind.text, placeholder: 'Petrol / Diesel', name: 'fuelType'),
        FormFieldDef(label: 'Status', kind: FormFieldKind.select, full: true, name: 'status', initial: 'Active'),
      ]),
      FormSectionDef(title: 'Notes', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),

  // app/water-routes/page.tsx — Setup → Delivery.
  'water-routes': FormDef(
    route: '/water-routes',
    specKey: 'water-routes',
    idKey: 'waterRouteId',
    carry: ['defaultDriverStaffId'],
    sections: [
      FormSectionDef(title: 'Basics', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'Route name', kind: FormFieldKind.text, required: true, full: true, placeholder: 'e.g. Kumasi East', name: 'routeName'),
        FormFieldDef(label: 'Area covered', kind: FormFieldKind.text, full: true, name: 'areaCovered'),
      ]),
      FormSectionDef(title: 'Assignment', color: 'blue', columns: 2, fields: [
        FormFieldDef(label: 'Default vehicle', kind: FormFieldKind.select, full: true, placeholder: '(none)', name: 'defaultVehicleId',
            optionLabel: waterVehicleOptionLabel, emptyHint: 'No vehicles. Add one on the Vehicles page first.'),
        FormFieldDef(label: 'Expected customers', kind: FormFieldKind.number, name: 'expectedCustomers'),
        FormFieldDef(label: 'Expected bags/day', kind: FormFieldKind.number, name: 'expectedBagsSold'),
      ]),
      FormSectionDef(title: 'Notes', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),

  // app/water-drivers/page.tsx — the Edit driver dialog. New drivers come
  // through an employee (WaterDriverEmployeeScreen). Water's dialog has only
  // the assigned vehicle — no route, base pay or commission.
  'water-drivers': FormDef(
    route: '/water-drivers',
    specKey: 'water-drivers',
    idKey: 'waterDriverId',
    sections: [
      FormSectionDef(title: 'Driver details', color: 'indigo', columns: 2,
          description: "Enter the driver's details and assign a vehicle.", fields: [
        FormFieldDef(label: 'Driver name', kind: FormFieldKind.text, required: true, full: true, name: 'driverName'),
        FormFieldDef(label: 'Phone', kind: FormFieldKind.text, name: 'phoneNumber'),
        FormFieldDef(label: 'License number', kind: FormFieldKind.text, name: 'licenseNumber'),
        FormFieldDef(label: 'Assigned vehicle', kind: FormFieldKind.select, full: true, placeholder: '(none)', name: 'assignedWaterVehicleId',
            optionLabel: waterVehicleOptionLabel, emptyHint: 'No vehicles. Add one on the Vehicles page first.'),
        FormFieldDef(label: 'Active', kind: FormFieldKind.bool, full: true, placeholder: 'Active', name: 'isActive', initial: 'true'),
      ]),
      FormSectionDef(title: 'Notes', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),
};

/// Water pages with a screen of their own.
const Map<String, CustomFormBuilder> waterCustomForms = {
  'water-staff': _staff,
  'water-drivers': _driver,
  'water-products': _product,
};

/// Water routes that open a screen of their own (see PageScreenBuilder).
const Map<String, PageScreenBuilder> waterPageScreens = {
  '/water-setup': _setup,
  '/water-company-setup': _companySetup,
  '/water-financial-settings': _financialSettings,
  // Sales, Expenses & Money → Sales. Payments and Customer Balances are the
  // shared pages given the Water rail, as the web's thin page files do.
  '/water-sales': _sales,
  '/water-payments': _payments,
  '/water-customer-balances': _customerBalances,
  // Sales, Expenses & Money → Money. Cash Flow, Owner Money and Loans are the
  // Poultry screens on the Water rail (the web's Water pages differ from the
  // Poultry ones only in what the rail carries, plus the few layout points
  // each screen keys on it). P&L is the Water statement in its page frame.
  '/water-cash-flow': _cashFlow,
  '/water-profit-loss': _profitLoss,
  '/water-owner-money': _ownerMoney,
  '/water-loans': _loans,
  '/water-cash-accounts': _cashAccounts,
  '/water-cash-transfers': _cashTransfers,
  '/water-cash-reconciliation': _reconciliation,
  // Sales, Expenses & Money → Expenses.
  '/water-internal-use': _internalUse,
  '/water-employee-loans': _employeeLoans,
  '/water-payroll': _payroll,
  '/water-expenses': _expenses,
  // 348: the shared recurring-expense page, under Water's own route.
  '/water-recurring-expenses': _recurringExpenses,
  // Supplier Payments and Balances: the shared pages on the Water rail, as
  // the web's thin page files do.
  '/water-supplier-payments': _supplierPayments,
  '/water-supplier-balances': _supplierBalances,
  '/water-deferred-costs': _deferredCosts,
  // Assets: the Poultry register on the Water rail (the web's water-assets
  // page is its twin apart from the word, the supplier picker, the payment
  // method and the table-only list, which the screens key on the rail).
  '/water-assets': _assets,
  // Operations → Production.
  '/water-production-batches': _production,
  '/water-daily-production': _batchProduction,
  '/water-maintenance': _maintenance,
  // Operations → Inventory.
  '/water-stock': _stock,
  '/water-inventory': _inventory,
  // Inventory & supply purchases. The old address still opens it, as the
  // web redirects /water-raw-materials there.
  '/water-supply-purchases': _rawMaterials,
  '/water-raw-materials': _rawMaterials,
  '/water-loss-records': _lossRecords,
  '/water-production-losses': _productionLosses,
  // Operations → Delivery.
  '/water-driver-returns': _deliveries,
  '/water-driver-report': _driverReport,
};

Widget _deliveries(Session s, Company c) => WaterDeliveriesScreen(session: s, company: c);

Widget _driverReport(Session s, Company c) => WaterDriverReportScreen(session: s, company: c);

Widget _lossRecords(Session s, Company c) => WaterLossRecordsScreen(session: s, company: c);

Widget _productionLosses(Session s, Company c) => WaterProductionLossesScreen(session: s, company: c);

Widget _rawMaterials(Session s, Company c) => WaterRawMaterialsScreen(session: s, company: c);

Widget _stock(Session s, Company c) => WaterStockMovementScreen(session: s, company: c);

Widget _inventory(Session s, Company c) => WaterInventoryScreen(session: s, company: c);

Widget _maintenance(Session s, Company c) => WaterMaintenanceScreen(session: s, company: c);

Widget _batchProduction(Session s, Company c) => WaterBatchProductionScreen(session: s, company: c);

Widget _production(Session s, Company c) => WaterProductionScreen(session: s, company: c);

Widget _assets(Session s, Company c) => AssetsScreen(session: s, company: c, rail: AssetRail.water);

Widget _deferredCosts(Session s, Company c) => WaterDeferredCostsScreen(session: s, company: c);

Widget _supplierPayments(Session s, Company c) => SupplierPaymentsScreen(session: s, company: c, rail: BalanceRail.water);

Widget _supplierBalances(Session s, Company c) =>
    CustomerBalancesScreen(session: s, company: c, side: BalanceSide.supplier, rail: BalanceRail.water);

Widget _expenses(Session s, Company c) => WaterExpensesScreen(session: s, company: c);
Widget _recurringExpenses(Session s, Company c) => RecurringExpensesScreen(session: s, company: c);

Widget _payroll(Session s, Company c) => WaterPayrollScreen(session: s, company: c);

Widget _internalUse(Session s, Company c) => WaterInternalUseScreen(session: s, company: c);

Widget _employeeLoans(Session s, Company c) => EmployeeLoansScreen(session: s, company: c, rail: waterMoneyRail);

Widget _cashAccounts(Session s, Company c) => CashAccountsScreen(session: s, company: c, rail: waterMoneyRail);

Widget _cashTransfers(Session s, Company c) => CashTransfersScreen(session: s, company: c, rail: waterMoneyRail);

Widget _reconciliation(Session s, Company c) => ReconciliationScreen(session: s, company: c, rail: waterMoneyRail);

Widget _cashFlow(Session s, Company c) => CashFlowScreen(session: s, company: c, rail: waterMoneyRail);

Widget _profitLoss(Session s, Company c) => WaterProfitLossScreen(session: s, company: c, page: true);

Widget _ownerMoney(Session s, Company c) => OwnerMoneyScreen(session: s, company: c, rail: waterMoneyRail);

Widget _loans(Session s, Company c) => LoansScreen(session: s, company: c, rail: waterMoneyRail);

Widget _sales(Session s, Company c) => WaterSalesScreen(session: s, company: c);

Widget _payments(Session s, Company c) => PaymentsReceivedScreen(session: s, company: c, rail: BalanceRail.water);

Widget _customerBalances(Session s, Company c) => CustomerBalancesScreen(session: s, company: c, rail: BalanceRail.water);

Widget _setup(Session s, Company c) => WaterSetupScreen(session: s, company: c);

Widget _companySetup(Session s, Company c) => WaterCompanySetupScreen(session: s, company: c);

Widget _financialSettings(Session s, Company c) => WaterFinancialSettingsScreen(session: s, company: c);

Widget _product(Session s, Company c, Map<String, dynamic>? e) =>
    WaterProductFormScreen(session: s, company: c, existing: e);

/// Drivers: the main button is "New employee & driver"; Edit is the plain
/// driver form above.
Widget _driver(Session s, Company c, Map<String, dynamic>? e) {
  final spec = PageRegistry.of('water-drivers');
  if (e == null || spec == null) {
    return WaterDriverEmployeeScreen(session: s, company: c, mode: WaterDriverMode.created);
  }
  return FormScreen(
    def: waterForms['water-drivers']!,
    title: 'Edit driver',
    company: c,
    session: s,
    spec: spec,
    existing: e,
  );
}

Widget _staff(Session s, Company c, Map<String, dynamic>? e) =>
    WaterStaffFormScreen(session: s, company: c, existing: e);
