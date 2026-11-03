import 'package:flutter/widgets.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../custom_form.dart';
import 'generic_reports_screen.dart';
import 'generic_settings_screen.dart';
import 'generic_setup_screen.dart';
import 'generic_setup_wizard_screen.dart';
import 'reports/generic_report_screens.dart';

/// Generic routes that open a screen of their own.
const Map<String, PageScreenBuilder> genericPageScreens = {
  // Admin.
  '/generic-reports': _reports,
  '/generic-setup': _setup,
  '/generic-setup/wizard': _wizard,
  '/generic-settings': _settings,
  // The reports the hub links to (the two balance pages are Sales & Money's).
  '/generic-reports/period-pnl': _pnl,
  '/generic-reports/cash-summary': _cash,
  '/generic-reports/expenses-by-category': _expenses,
  '/generic-reports/staff-cost': _staffCost,
  '/generic-reports/subscription-revenue': _subRevenue,
  '/generic-reports/mrr': _mrr,
  '/generic-reports/customer-payments': _payments,
  '/generic-reports/unpaid-customers': _unpaid,
  '/generic-reports/hosting-cost': _hosting,
  '/generic-reports/break-even': _breakEven,
  '/generic-reports/sales-by-product': _byProduct,
  '/generic-reports/sales-by-customer': _byCustomer,
  '/generic-reports/inventory-value': _inventory,
};

Widget _reports(Session s, Company c) => GenericReportsScreen(session: s, company: c);
Widget _setup(Session s, Company c) => GenericSetupScreen(session: s, company: c);
Widget _wizard(Session s, Company c) => GenericSetupWizardScreen(session: s, company: c);
Widget _settings(Session s, Company c) => GenericSettingsScreen(session: s, company: c);
Widget _pnl(Session s, Company c) => GenericPeriodPnlScreen(session: s, company: c);
Widget _cash(Session s, Company c) => GenericCashSummaryScreen(session: s, company: c);
Widget _expenses(Session s, Company c) => GenericExpenseReportScreen(session: s, company: c);
Widget _staffCost(Session s, Company c) => GenericStaffCostScreen(session: s, company: c);
Widget _subRevenue(Session s, Company c) => GenericSubscriptionRevenueScreen(session: s, company: c);
Widget _mrr(Session s, Company c) => GenericMrrScreen(session: s, company: c);
Widget _payments(Session s, Company c) => GenericCustomerPaymentsReportScreen(session: s, company: c);
Widget _unpaid(Session s, Company c) => GenericUnpaidCustomersScreen(session: s, company: c);
Widget _hosting(Session s, Company c) => GenericHostingCostScreen(session: s, company: c);
Widget _breakEven(Session s, Company c) => GenericBreakEvenScreen(session: s, company: c);
Widget _byProduct(Session s, Company c) => GenericSalesByProductScreen(session: s, company: c);
Widget _byCustomer(Session s, Company c) => GenericSalesByCustomerScreen(session: s, company: c);
Widget _inventory(Session s, Company c) => GenericInventoryValueScreen(session: s, company: c);
