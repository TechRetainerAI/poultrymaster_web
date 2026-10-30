// Restaurant → Expenses (2026-10-20): Expenses, Supplier Payments and Supplier
// Balances as the web pages, against a fake API at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/supplier_payments_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/balances_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/customer_balances_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_expenses_screen.dart';

import 'support/harness.dart' hide enter;

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(390, 4000);

Finder filled(String t) => find.widgetWithText(FilledButton, t);

/// The box under [label] in the open dialog; a required label carries " *".
Future<void> enter(WidgetTester tester, String label, String text) async {
  final l = find.textContaining(RegExp('^${RegExp.escape(label)}' r'( \*)?$'), findRichText: true);
  final box = find.descendant(of: find.ancestor(of: l.last, matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.enterText(box.first, text);
  await tester.pump();
}

void main() {
  test('routes, the Restaurant rail, short dates and the list filters', () {
    for (final h in ['/restaurant-expenses', '/restaurant-supplier-payments', '/restaurant-supplier-balances']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    const r = BalanceRail.restaurant;
    expect((r.supplierPaymentsHref, r.suppliersHref, r.cashAccountIdKey, r.cashAccountsPath, r.isPoultry),
        ('/restaurant-supplier-payments', '/restaurant-suppliers', 'cashAccountId', '/api/Restaurant/finance/accounts', false));
    expect(r.supplierDocumentHref({'documentType': 'Purchase', 'documentId': 4}), '/restaurant-inventory?tab=purchases&purchaseId=4');
    expect(r.supplierBalanceDocHref({'documentType': 'Expense', 'documentId': 9}), '/restaurant-expenses?expenseId=9');
    expect(r.supplierDocumentHref({'documentType': 'AssetCost', 'documentId': 1}), '/restaurant-assets');
    expect(fmtShortDate('2026-09-28T00:00:00'), 'Sep 28, 26');
    final rows = [
      {'expenseId': 1, 'expenseDate': '2026-10-02', 'categoryName': 'Produce', 'description': 'Tomatoes', 'amount': 50},
      {'expenseId': 2, 'expenseDate': '2026-10-09', 'categoryName': null, 'description': 'Gas', 'amount': 30},
    ];
    expect(filterRestaurantExpenses(rows, {}, category: 'Uncategorized').map((e) => e['expenseId']), [2]);
    expect(filterRestaurantExpenses(rows, {1: {'supplierName': 'Farm Fresh'}}, search: 'fresh').map((e) => e['expenseId']), [1]);
    expect(filterRestaurantExpenses(rows, {}, from: '2026-10-05').map((e) => e['expenseId']), [2]);
    expect(filterRestaurantExpenses(rows, {}, focusId: 1).map((e) => e['expenseId']), [1]);
  });

  testWidgets('Expenses: list, filters, record a part-paid supplier bill, edit, delete, categories', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/expenses'] = [
        {'expenseId': 1, 'expenseDate': '2026-10-02', 'categoryId': 3, 'categoryName': 'Produce', 'description': 'Tomatoes', 'amount': 50,
          'paymentMethod': 'Cash', 'receiptRef': 'R-1'},
      ]
      ..gets['/api/Restaurant/expenses/categories'] = [
        {'expenseCategoryId': 3, 'name': 'Produce', 'isActive': true},
        {'expenseCategoryId': 4, 'name': 'Utilities', 'isActive': false},
      ]
      ..gets['/api/Restaurant/finance/accounts'] = [
        {'cashAccountId': 5, 'name': 'Bank', 'currentBalance': 4000, 'isActive': true},
      ]
      ..gets['/api/Restaurant/expenses/payments'] = [
        {'expenseId': 1, 'supplierId': 8, 'supplierName': 'Farm Fresh', 'amountPaid': 20, 'balance': 30, 'paymentStatus': 'PartiallyPaid',
          'paidAtEntry': 20, 'cashAccountId': 5},
      ]
      ..gets['/api/Restaurant/setup/suppliers'] = [
        {'restaurantsupplierid': 8, 'name': 'Farm Fresh', 'isactive': true},
        {'restaurantsupplierid': 9, 'name': 'Old Supplier', 'isactive': false},
      ];
    await open(tester, RestaurantExpensesScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('Oct 2, 26'), findsOneWidget);
    expect(find.text('Farm Fresh'), findsOneWidget, reason: 'paid to comes from the payments read');
    expect(find.text('Partially paid'), findsOneWidget);
    expect(find.text('Total (Filtered)'), findsOneWidget);

    // Filters sheet: a category with no match, then Clear all.
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await pick(tester, 'All categories', 'Produce');
    await tester.tap(filled('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsWidgets, reason: 'the filter count badge');
    await tester.enterText(find.widgetWithText(TextFormField, 'Search expenses...'), 'zzz');
    await tester.pump();
    expect(find.text('No expenses found'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Search expenses...'), '');
    await tester.pump();

    // Record a part-paid bill owed to a supplier.
    await tester.tap(filled('Add Expense'));
    await tester.pumpAndSettle();
    await enter(tester, 'Description', 'Weekly produce');
    await enter(tester, 'Amount', '100');
    await pick(tester, 'Not linked to a supplier', 'Farm Fresh');
    expect(find.text('Old Supplier'), findsNothing, reason: 'inactive suppliers are left out');
    await pick(tester, 'Paid', 'Partially paid');
    await tester.tap(filled('Record Expense'));
    await tester.pumpAndSettle();
    expect(find.textContaining('must have something paid'), findsOneWidget);
    await enter(tester, 'Amount Paid', '40');
    await tester.tap(filled('Record Expense'));
    await tester.pumpAndSettle();
    final b = api.lastBody('/api/Restaurant/expenses');
    expect((b['description'], b['amount'], b['supplierId'], b['supplierName'], b['amountPaid'], b['cashAccountId'], b['paymentMethod'], b['farmId']),
        ('Weekly produce', 100, 8, 'Farm Fresh', 40, null, 'Cash', 'farm-1'));

    // Edit pre-fills the part payment and the account it was paid from.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit Expense'), findsOneWidget);
    expect(find.text('Bank — 4000.00'), findsOneWidget);
    await tester.tap(filled('Save Changes'));
    await tester.pumpAndSettle();
    final u = api.lastBody('/api/Restaurant/expenses/1', 'PUT');
    expect((u['amount'], u['amountPaid'], u['cashAccountId'], u['supplierId'], u['categoryId']), (50, 20, 5, 8, 3));

    // Delete asks first.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(filled('OK'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/Restaurant/expenses/1'), isTrue);

    // Categories tab.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Categories'));
    await tester.pumpAndSettle();
    expect(find.text('Inactive'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'New category name'), 'Gas');
    await tester.pump();
    await tester.tap(filled('Add Category'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/expenses/categories'), {'name': 'Gas'});
    await tester.tap(find.byTooltip('Delete category').first);
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/Restaurant/expenses/categories/3'), isTrue);
  });

  testWidgets('Supplier Payments and Supplier Balances read the Restaurant routes and accounts', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/supplier-payments'] = [
        {'paymentId': 'SP-1', 'partyName': 'Farm Fresh', 'amount': 30, 'paymentDate': '2026-10-10', 'status': 'Posted', 'cashAccountId': 5},
      ]
      ..gets['/api/Restaurant/finance/accounts'] = [
        {'cashAccountId': 5, 'name': 'Bank', 'currentBalance': 4000, 'isActive': true, 'allowNegative': false},
      ]
      ..gets['/api/Restaurant/supplier-balances'] = [
        {'partyId': 8, 'partyName': 'Farm Fresh', 'totalBalance': 30, 'openDocuments': 1},
      ]
      ..gets['/api/Restaurant/supplier-balances/summary'] = {'totalBalance': 30, 'partyCount': 1};
    await open(tester, SupplierPaymentsScreen(session: await sessionFor(api), company: rest, rail: BalanceRail.restaurant), size: tall);
    expect(api.requests.any((r) => r.url.path == '/api/Restaurant/supplier-payments'), isTrue);
    expect(api.requests.any((r) => r.url.path == '/api/Restaurant/finance/accounts'), isTrue);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
    expect(find.textContaining('Farm Fresh'), findsWidgets);

    await open(tester,
        CustomerBalancesScreen(session: await sessionFor(api), company: rest, side: BalanceSide.supplier, rail: BalanceRail.restaurant),
        size: tall);
    expect(api.requests.any((r) => r.url.path == '/api/Restaurant/supplier-balances'), isTrue);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
    expect(find.textContaining('Farm Fresh'), findsWidgets);
  });
}
