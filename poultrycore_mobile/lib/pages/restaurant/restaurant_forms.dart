import 'package:flutter/widgets.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../custom_form.dart';
import '../form_spec.dart';
import '../poultry/money/financial_activity_screen.dart';
import '../poultry/expenses/supplier_payments_screen.dart';
import '../poultry/sales/balances_logic.dart' show BalanceRail, BalanceSide;
import '../poultry/sales/customer_balances_screen.dart';
import 'restaurant_cash_accounts_screen.dart';
import 'restaurant_cash_flow_screen.dart';
import 'restaurant_expenses_screen.dart';
import 'restaurant_inventory_screen.dart';
import 'restaurant_sales_screen.dart';
import '../poultry/sales/payments_received_screen.dart';
import 'restaurant_staff_loans_screen.dart';
import '../poultry/expenses/assets_screen.dart';
import '../poultry/expenses/asset_logic.dart' show AssetRail;
import '../poultry/expenses/deferred_costs_screen.dart';
import 'restaurant_internal_use_screen.dart';
import 'restaurant_payroll_screen.dart';
import '../poultry/expenses/recurring_expenses_screen.dart';
import 'restaurant_cash_reconciliation_screen.dart';
import 'restaurant_cash_transfers_screen.dart';
import 'restaurant_loans_screen.dart';
import 'restaurant_owner_money_screen.dart';
import 'restaurant_profit_loss_screen.dart';
import 'restaurant_staff_form_screen.dart';
import 'restaurant_crm_screen.dart';
import 'restaurant_events_screen.dart';
import 'restaurant_gift_cards_screen.dart';
import 'restaurant_loyalty_screen.dart';
import 'restaurant_menu_screen.dart';
import 'restaurant_notifications_screen.dart';
import 'restaurant_setup_screen.dart';
import 'restaurant_staff_screen.dart';
import 'restaurant_supplier_form_screen.dart';

/// Restaurant's forms, copied from the Restaurant web pages — never from
/// Poultry's or Water's.
const Map<String, FormDef> restaurantForms = {
  // app/restaurant-crm/page.tsx — Customers tab, "Add Customer". Segment
  // defaults to New, as the web's `custForm.segment || "New"`.
  'restaurant-crm-customers': FormDef(
    route: '/restaurant-crm',
    specKey: 'restaurant-crm-customers',
    sections: [
      FormSectionDef(title: 'Customer', color: 'rose', columns: 2,
          description: 'Track guest preferences and visit history', fields: [
        FormFieldDef(label: 'Name', kind: FormFieldKind.text, required: true, name: 'name'),
        FormFieldDef(label: 'Phone', kind: FormFieldKind.text, name: 'phone'),
        FormFieldDef(label: 'Email', kind: FormFieldKind.text, name: 'email'),
        FormFieldDef(label: 'Segment', kind: FormFieldKind.select, name: 'segment', initial: 'New'),
        FormFieldDef(label: 'Birthday', kind: FormFieldKind.date, name: 'dateOfBirth'),
        FormFieldDef(label: 'Anniversary', kind: FormFieldKind.date, name: 'anniversary'),
      ]),
      FormSectionDef(title: 'Preferences', color: 'rose', columns: 1, fields: [
        FormFieldDef(label: 'Dietary Preferences', kind: FormFieldKind.text, placeholder: 'e.g. Vegetarian, No spicy', name: 'dietaryPreferences'),
        FormFieldDef(label: 'Allergies', kind: FormFieldKind.text, placeholder: 'e.g. Nuts, Shellfish, Dairy', name: 'allergies'),
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),
};

/// Restaurant pages with a screen of their own.
const Map<String, CustomFormBuilder> restaurantCustomForms = {
  'restaurant-staff': _staff,
  'restaurant-setup-suppliers': _supplier,
};

Widget _staff(Session s, Company c, Map<String, dynamic>? e) =>
    RestaurantStaffFormScreen(session: s, company: c, existing: e);

Widget _supplier(Session s, Company c, Map<String, dynamic>? e) =>
    RestaurantSupplierFormScreen(session: s, company: c, existing: e);

/// Restaurant routes that are screens of their own, keyed by web href.
const Map<String, PageScreenBuilder> restaurantPageScreens = {
  '/restaurant-staff': _staffPage,
  '/restaurant-menu': _menuPage,
  '/restaurant-setup': _setupPage,
  '/restaurant-crm': _crmPage,
  '/restaurant-loyalty': _loyaltyPage,
  '/restaurant-events': _eventsPage,
  '/restaurant-gift-cards': _giftCardsPage,
  '/restaurant-notifications': _notificationsPage,
  '/restaurant-cash-flow': _cashFlowPage,
  '/restaurant-financial-activity': _financialActivityPage,
  '/restaurant-profit-loss': _profitLossPage,
  '/restaurant-owner-money': _ownerMoneyPage,
  '/restaurant-loans': _loansPage,
  '/restaurant-cash-accounts': _cashAccountsPage,
  '/restaurant-cash-transfers': _cashTransfersPage,
  '/restaurant-cash-reconciliation': _reconciliationPage,
  '/restaurant-supplier-payments': _supplierPaymentsPage,
  '/restaurant-supplier-balances': _supplierBalancesPage,
  '/restaurant-expenses': _expensesPage,
  '/restaurant-recurring-expenses': _recurringPage,
  '/restaurant-internal-use': _internalUsePage,
  '/restaurant-payroll': _payrollPage,
  '/restaurant-staff-loans': _staffLoansPage,
  '/restaurant-deferred-costs': _deferredPage,
  '/restaurant-assets': _assetsPage,
  '/restaurant-sales': _salesPage,
  '/restaurant-payments': _paymentsPage,
  '/restaurant-customer-balances': _customerBalancesPage,
  '/restaurant-inventory': _inventoryPage,
  // The Inventory menu's Record Purchase row: the stock page with the dialog open.
  '/restaurant-inventory?purchase=1': _recordPurchasePage,
};

Widget _staffPage(Session s, Company c) => RestaurantStaffScreen(session: s, company: c);
Widget _menuPage(Session s, Company c) => RestaurantMenuScreen(session: s, company: c);
Widget _setupPage(Session s, Company c) => RestaurantSetupScreen(session: s, company: c);
Widget _crmPage(Session s, Company c) => RestaurantCrmScreen(session: s, company: c);
Widget _loyaltyPage(Session s, Company c) => RestaurantLoyaltyScreen(session: s, company: c);
Widget _eventsPage(Session s, Company c) => RestaurantEventsScreen(session: s, company: c);
Widget _giftCardsPage(Session s, Company c) => RestaurantGiftCardsScreen(session: s, company: c);
Widget _notificationsPage(Session s, Company c) => RestaurantNotificationsScreen(session: s, company: c);
Widget _cashFlowPage(Session s, Company c) => RestaurantCashFlowScreen(session: s, company: c);
Widget _financialActivityPage(Session s, Company c) => FinancialActivityScreen(session: s, company: c, restaurant: true);
Widget _profitLossPage(Session s, Company c) => RestaurantProfitLossScreen(session: s, company: c);
Widget _ownerMoneyPage(Session s, Company c) => RestaurantOwnerMoneyScreen(session: s, company: c);
Widget _loansPage(Session s, Company c) => RestaurantLoansScreen(session: s, company: c);
Widget _cashAccountsPage(Session s, Company c) => RestaurantCashAccountsScreen(session: s, company: c);
Widget _cashTransfersPage(Session s, Company c) => RestaurantCashTransfersScreen(session: s, company: c);
Widget _reconciliationPage(Session s, Company c) => RestaurantCashReconciliationScreen(session: s, company: c);
Widget _supplierPaymentsPage(Session s, Company c) => SupplierPaymentsScreen(session: s, company: c, rail: BalanceRail.restaurant);
Widget _supplierBalancesPage(Session s, Company c) =>
    CustomerBalancesScreen(session: s, company: c, side: BalanceSide.supplier, rail: BalanceRail.restaurant);
Widget _expensesPage(Session s, Company c) => RestaurantExpensesScreen(session: s, company: c);

/// `/restaurant-expenses?expenseId=` (from Supplier Balances / Payments) and
/// `?tab=categories` open the Expenses page narrowed.
Widget? restaurantExpensesScreenForHref(String href, Session s, Company c) {
  final uri = Uri.tryParse(href);
  if (uri == null || uri.path != '/restaurant-expenses' || uri.query.isEmpty) return null;
  final id = int.tryParse(uri.queryParameters['expenseId'] ?? '');
  return RestaurantExpensesScreen(
    session: s,
    company: c,
    focusExpenseId: id != null && id > 0 ? id : null,
    categoriesTab: uri.queryParameters['tab'] == 'categories',
  );
}
Widget _recurringPage(Session s, Company c) => RecurringExpensesScreen(session: s, company: c);
Widget _internalUsePage(Session s, Company c) => RestaurantInternalUseScreen(session: s, company: c);
Widget _payrollPage(Session s, Company c) => RestaurantPayrollScreen(session: s, company: c);
Widget _staffLoansPage(Session s, Company c) => RestaurantStaffLoansScreen(session: s, company: c);
Widget _deferredPage(Session s, Company c) => DeferredCostsScreen(session: s, company: c, restaurant: true);
Widget _assetsPage(Session s, Company c) => AssetsScreen(session: s, company: c, rail: AssetRail.restaurant);
Widget _salesPage(Session s, Company c) => RestaurantSalesScreen(session: s, company: c);
Widget _paymentsPage(Session s, Company c) => PaymentsReceivedScreen(session: s, company: c, rail: BalanceRail.restaurant);
Widget _customerBalancesPage(Session s, Company c) => CustomerBalancesScreen(session: s, company: c, rail: BalanceRail.restaurant);
Widget _inventoryPage(Session s, Company c) => RestaurantInventoryScreen(session: s, company: c);
Widget _recordPurchasePage(Session s, Company c) => RestaurantInventoryScreen(session: s, company: c, openPurchase: true);
