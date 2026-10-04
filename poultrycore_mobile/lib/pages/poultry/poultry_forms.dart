import 'package:flutter/widgets.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../custom_form.dart';
import '../form_spec.dart';
import '../form_screen.dart';
import '../registry.dart';
import 'company_setup_screen.dart';
import 'daily_closing_screen.dart';
import 'days_of_supply_screen.dart';
import 'driver_employee_screen.dart';
import 'egg_pick_settings_screen.dart';
import 'farm_completeness_screen.dart';
import 'farm_setup_screen.dart';
import 'feed_distribution_screen.dart';
import 'feed_formula_form_screen.dart';
import 'financial_settings_screen.dart';
import 'flock_batch_form_screen.dart';
import 'flock_form_screen.dart';
import 'initial_farm_setup_screen.dart';
import 'poultry_labels.dart';
import 'product_screens.dart';

/// Hand-written forms that replace the extracted ones, keyed by spec key.
///
/// Extraction reads every `<FormSection>` on a page, so a page with a second
/// dialog gets that dialog's fields too (Poultry Staff picked up the
/// attendance dialog's Date / Status / Shift), and inputs bound through local
/// state carry no name at all (Houses sent nothing). These are copied from
/// the web page's own dialog: same sections, colours, labels, placeholders,
/// required marks and defaults.
const Map<String, FormDef> poultryForms = {
  // app/poultry-staff/page.tsx — the Add/Edit staff dialog only.
  'poultry-staff': FormDef(
    route: '/poultry-staff',
    specKey: 'poultry-staff',
    idKey: 'poultryStaffId',
    sections: [
      FormSectionDef(title: 'Person', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'First name', kind: FormFieldKind.text, required: true, name: 'firstName'),
        FormFieldDef(label: 'Last name', kind: FormFieldKind.text, required: true, name: 'lastName'),
        FormFieldDef(label: 'Phone', kind: FormFieldKind.text, name: 'phoneNumber'),
        FormFieldDef(label: 'Email', kind: FormFieldKind.text, name: 'email'),
      ]),
      FormSectionDef(title: 'Pay', color: 'amber', columns: 2, fields: [
        FormFieldDef(label: 'Role', kind: FormFieldKind.select, name: 'role', initial: 'FarmHand'),
        FormFieldDef(label: 'Salary type', kind: FormFieldKind.select, name: 'salaryType', initial: 'Monthly'),
        FormFieldDef(label: 'Base pay', kind: FormFieldKind.number, name: 'basePay', decimal: true, initial: '0'),
        FormFieldDef(label: 'Commission rate', kind: FormFieldKind.number, name: 'commissionRate', decimal: true, initial: '0'),
      ]),
      FormSectionDef(title: 'Other', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Active', kind: FormFieldKind.bool, name: 'isActive', placeholder: 'Active', initial: 'true'),
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),

  // app/houses/page.tsx — "Create New House".
  'house': FormDef(
    route: '/houses',
    specKey: 'house',
    idKey: 'houseId',
    sections: [
      FormSectionDef(title: 'House Details', color: 'blue', columns: 2, fields: [
        FormFieldDef(label: 'House Name', kind: FormFieldKind.text, required: true, placeholder: 'House A', name: 'houseName'),
        FormFieldDef(label: 'Capacity (birds)', kind: FormFieldKind.number, placeholder: '1000', name: 'capacity'),
      ]),
      FormSectionDef(title: 'Additional Information', color: 'indigo', columns: 1, fields: [
        FormFieldDef(label: 'Location', kind: FormFieldKind.text, placeholder: 'North Wing', name: 'location'),
      ]),
    ],
  ),

  // app/customers/page.tsx — "Add New Customer".
  'customer': FormDef(
    route: '/customers',
    specKey: 'customer',
    idKey: 'customerId',
    carry: ['createdDate'],
    sections: [
      FormSectionDef(title: 'Personal Information', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'Full Name', kind: FormFieldKind.text, required: true, placeholder: 'John Doe', name: 'name'),
        FormFieldDef(label: 'Phone Number', kind: FormFieldKind.text, required: true, placeholder: '+1 (555) 123-4567', name: 'contactPhone'),
        FormFieldDef(label: 'Email Address', kind: FormFieldKind.text, placeholder: 'john@example.com (optional)', name: 'contactEmail'),
        FormFieldDef(label: 'City', kind: FormFieldKind.text, required: true, placeholder: 'New York', name: 'city'),
      ]),
      FormSectionDef(title: 'Address', color: 'green', columns: 1, fields: [
        FormFieldDef(label: 'Full Address', kind: FormFieldKind.text, required: true, placeholder: '123 Main Street, Apt 4B', name: 'address'),
      ]),
    ],
  ),

  // app/suppliers/page.tsx — "Add new supplier".
  'supplier': FormDef(
    route: '/suppliers',
    specKey: 'supplier',
    idKey: 'supplierId',
    carry: ['createdDate'],
    sections: [
      FormSectionDef(title: 'Contact', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'Business / name', kind: FormFieldKind.text, required: true, placeholder: 'e.g. Agro Feed Ltd', name: 'name'),
        FormFieldDef(label: 'Phone', kind: FormFieldKind.text, required: true, placeholder: '+233 …', name: 'contactPhone'),
        FormFieldDef(label: 'Email', kind: FormFieldKind.text, placeholder: 'optional', name: 'contactEmail'),
        FormFieldDef(label: 'City', kind: FormFieldKind.text, required: true, placeholder: 'City', name: 'city'),
      ]),
      FormSectionDef(title: 'Address', color: 'green', columns: 1, fields: [
        FormFieldDef(label: 'Full address', kind: FormFieldKind.text, required: true, placeholder: 'Street, region', name: 'address'),
      ]),
    ],
  ),

  // app/poultry-vehicles/page.tsx — Setup → Delivery.
  'poultry-vehicles': FormDef(
    route: '/poultry-vehicles',
    specKey: 'poultry-vehicles',
    idKey: 'poultryVehicleId',
    sections: [
      FormSectionDef(title: 'Identity', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'Vehicle name', kind: FormFieldKind.text, required: true, full: true, placeholder: 'e.g. Truck 1', name: 'vehicleName'),
        FormFieldDef(label: 'Type', kind: FormFieldKind.select, name: 'vehicleType', initial: 'Truck'),
        FormFieldDef(label: 'Registration #', kind: FormFieldKind.text, name: 'registrationNumber'),
      ]),
      FormSectionDef(title: 'Details', color: 'blue', columns: 2, fields: [
        FormFieldDef(label: 'Capacity (crates)', kind: FormFieldKind.number, name: 'capacityCrates'),
        FormFieldDef(label: 'Fuel type', kind: FormFieldKind.text, placeholder: 'Petrol / Diesel', name: 'fuelType'),
        FormFieldDef(label: 'Status', kind: FormFieldKind.select, full: true, name: 'status', initial: 'Active'),
      ]),
      FormSectionDef(title: 'Notes', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),

  // app/poultry-routes/page.tsx — Setup → Delivery.
  'poultry-routes': FormDef(
    route: '/poultry-routes',
    specKey: 'poultry-routes',
    idKey: 'poultryRouteId',
    sections: [
      FormSectionDef(title: 'Basics', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'Route name', kind: FormFieldKind.text, required: true, full: true, placeholder: 'e.g. Kumasi East', name: 'routeName'),
        FormFieldDef(label: 'Area covered', kind: FormFieldKind.text, full: true, name: 'areaCovered'),
      ]),
      FormSectionDef(title: 'Assignment', color: 'blue', columns: 2, fields: [
        FormFieldDef(label: 'Default vehicle', kind: FormFieldKind.select, full: true, placeholder: '(none)', name: 'defaultVehicleId',
            optionLabel: vehicleOptionLabel, emptyHint: 'No vehicles. Add one on the Vehicles page first.'),
        FormFieldDef(label: 'Expected customers', kind: FormFieldKind.number, name: 'expectedCustomers'),
        FormFieldDef(label: 'Expected crates/day', kind: FormFieldKind.number, name: 'expectedCratesSold'),
      ]),
      FormSectionDef(title: 'Notes', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),

  // app/poultry-drivers/page.tsx — the Edit driver dialog. (The page has no
  // plain "new driver": drivers are added through an employee, see
  // DriverEmployeeScreen.)
  'poultry-drivers': FormDef(
    route: '/poultry-drivers',
    specKey: 'poultry-drivers',
    idKey: 'poultryDriverId',
    sections: [
      FormSectionDef(title: 'Driver details', color: 'indigo', columns: 2,
          description: "Enter the driver's details and assign a vehicle.", fields: [
        FormFieldDef(label: 'Driver name', kind: FormFieldKind.text, required: true, full: true, name: 'driverName'),
        FormFieldDef(label: 'Phone', kind: FormFieldKind.text, name: 'phoneNumber'),
        FormFieldDef(label: 'License number', kind: FormFieldKind.text, name: 'licenseNumber'),
        FormFieldDef(label: 'Default vehicle', kind: FormFieldKind.select, placeholder: '(none)', name: 'defaultVehicleId',
            optionLabel: vehicleOptionLabel, emptyHint: 'No vehicles. Add one on the Vehicles page first.'),
        FormFieldDef(label: 'Default route', kind: FormFieldKind.select, placeholder: '(none)', name: 'defaultRouteId',
            emptyHint: 'No routes. Add one on the Routes page first.'),
        FormFieldDef(label: 'Base pay', kind: FormFieldKind.number, decimal: true, name: 'basePay'),
        FormFieldDef(label: 'Commission per crate', kind: FormFieldKind.number, decimal: true, name: 'commissionPerCrate'),
        FormFieldDef(label: 'Active', kind: FormFieldKind.bool, full: true, placeholder: 'Active', name: 'isActive', initial: 'true'),
      ]),
      FormSectionDef(title: 'Notes', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),
};

/// Poultry pages with a screen of their own.
const Map<String, CustomFormBuilder> poultryCustomForms = {
  'flocks': _flock,
  'flock': _flockBatch,
  'poultry-drivers': _driver,
  'poultry-products': _product,
  'poultry-feed-formulas': _feedFormula,
};

Widget _feedFormula(Session s, Company c, Map<String, dynamic>? e) =>
    FeedFormulaFormScreen(session: s, company: c, existing: e);

Widget _product(Session s, Company c, Map<String, dynamic>? e) =>
    ProductFormScreen(session: s, company: c, existing: e);

/// Drivers: the main button is "New employee & driver"; Edit is the plain
/// driver form above.
Widget _driver(Session s, Company c, Map<String, dynamic>? e) {
  final spec = PageRegistry.of('poultry-drivers');
  if (e == null || spec == null) {
    return DriverEmployeeScreen(session: s, company: c, mode: DriverEmployeeMode.created);
  }
  return FormScreen(
    def: poultryForms['poultry-drivers']!,
    title: 'Edit driver',
    company: c,
    session: s,
    spec: spec,
    existing: e,
  );
}

Widget _flock(Session s, Company c, Map<String, dynamic>? e) =>
    FlockFormScreen(session: s, company: c, existing: e);

Widget _flockBatch(Session s, Company c, Map<String, dynamic>? e) =>
    FlockBatchFormScreen(session: s, company: c, existing: e);

/// Poultry routes that open a screen of their own (see PageScreenBuilder).
const Map<String, PageScreenBuilder> poultryPageScreens = {
  '/business-office/egg-pick-settings': _eggPicks,
  '/poultry-company-setup': _companySetup,
  '/poultry-financial-settings': _financialSettings,
  '/poultry-setup': _farmSetup,
  '/poultry-days-of-supply': _daysOfSupply,
  '/poultry-farm-completeness': _farmCompleteness,
  '/poultry-feed-distribution': _feedDistribution,
  '/poultry-daily-closing': _dailyClosing,
  '/poultry-farm-setup': _initialFarmSetup,
};

Widget _initialFarmSetup(Session s, Company c) => InitialFarmSetupScreen(session: s, company: c);

Widget _dailyClosing(Session s, Company c) => DailyClosingScreen(session: s, company: c);

Widget _farmCompleteness(Session s, Company c) => FarmCompletenessScreen(session: s, company: c);
Widget _feedDistribution(Session s, Company c) => FeedDistributionScreen(session: s, company: c);

Widget _daysOfSupply(Session s, Company c) => DaysOfSupplyScreen(session: s, company: c);

Widget _farmSetup(Session s, Company c) => FarmSetupScreen(session: s, company: c);

Widget _financialSettings(Session s, Company c) => FinancialSettingsScreen(session: s, company: c);

Widget _companySetup(Session s, Company c) => PoultryCompanySetupScreen(session: s, company: c);

Widget _eggPicks(Session s, Company c) => EggPickSettingsScreen(session: s, company: c);
