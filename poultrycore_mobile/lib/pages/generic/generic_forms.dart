import 'package:flutter/widgets.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../custom_form.dart';
import '../poultry/sales/balances_logic.dart' show BalanceRail, BalanceSide;
import '../poultry/sales/customer_balances_screen.dart';
import '../water/water_internal_use_screen.dart';
import 'generic_customer_payments_screen.dart';
import 'generic_customers_screen.dart';
import 'generic_expenses_screen.dart';
import 'generic_inventory_screen.dart';
import 'generic_money_screens.dart';
import 'generic_products_screen.dart';
import 'generic_purchases_screen.dart';
import 'generic_reports_screen.dart';
import 'generic_sales_screen.dart';
import 'generic_suppliers_screen.dart';
import 'generic_stock_adjustments_screen.dart';
import 'generic_settings_screen.dart';
import 'generic_setup_screen.dart';
import 'generic_setup_wizard_screen.dart';
import 'reports/generic_report_screens.dart';

/// Generic routes that open a screen of their own.
const Map<String, PageScreenBuilder> genericPageScreens = {
  // Catalog.
  '/generic-products': _products,
  '/generic-inventory': _onHand,
  '/generic-stock-adjustments': _adjustments,
  '/generic-internal-use': _internalUse,
  // Sales.
  '/generic-sales': _sales,
  '/generic-sales/new': _newSale,
  '/generic-customers': _customers,
  '/generic-customer-payments': _customerPayments,
  // Purchasing (Recurring expenses is the shared /recurring-expenses screen).
  '/generic-suppliers': _suppliers,
  '/generic-purchases': _purchases,
  '/generic-purchases/new': _newPurchase,
  '/generic-supplier-payments': _supplierPayments,
  '/generic-supplier-balances': _supplierBalances,
  '/generic-expenses': _expenseList,
  '/generic-expenses/new': _newExpense,
  // Money.
  '/generic-cash': _cashAccounts,
  '/generic-cash-transfers': _cashTransfers,
  '/generic-daily-closings': _dailyClosings,
  '/generic-owner-money': _ownerMoney,
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

Widget _products(Session s, Company c) => GenericProductsScreen(session: s, company: c);
Widget _onHand(Session s, Company c) => GenericInventoryScreen(session: s, company: c);
Widget _adjustments(Session s, Company c) => GenericStockAdjustmentsScreen(session: s, company: c);
Widget _internalUse(Session s, Company c) => WaterInternalUseScreen(session: s, company: c, generic: true);
Widget _sales(Session s, Company c) => GenericSalesScreen(session: s, company: c);
Widget _newSale(Session s, Company c) => GenericNewSaleScreen(session: s, company: c);
Widget _customers(Session s, Company c) => GenericCustomersScreen(session: s, company: c);
Widget _customerPayments(Session s, Company c) => GenericCustomerPaymentsScreen(session: s, company: c);
Widget _suppliers(Session s, Company c) => GenericSuppliersScreen(session: s, company: c);
Widget _purchases(Session s, Company c) => GenericPurchasesScreen(session: s, company: c);
Widget _newPurchase(Session s, Company c) => GenericNewPurchaseScreen(session: s, company: c);
Widget _supplierPayments(Session s, Company c) => GenericCustomerPaymentsScreen(session: s, company: c, supplier: true);
Widget _supplierBalances(Session s, Company c) =>
    CustomerBalancesScreen(session: s, company: c, side: BalanceSide.supplier, rail: BalanceRail.generic(c.farmId));
Widget _expenseList(Session s, Company c) => GenericExpensesScreen(session: s, company: c);
Widget _newExpense(Session s, Company c) => GenericNewExpenseScreen(session: s, company: c);
Widget _cashAccounts(Session s, Company c) => GenericCashScreen(session: s, company: c);
Widget _cashTransfers(Session s, Company c) => GenericCashTransfersScreen(session: s, company: c);
Widget _dailyClosings(Session s, Company c) => GenericDailyClosingsScreen(session: s, company: c);
Widget _ownerMoney(Session s, Company c) => GenericOwnerMoneyScreen(session: s, company: c);
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
