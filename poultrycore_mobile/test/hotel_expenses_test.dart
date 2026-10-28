// Hotel → Sales, Expenses & Money → Expenses: Expenses, Supplier Payments and
// Supplier Balances, at phone width against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_expenses_screen.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/supplier_payments_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/balances_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/customer_balances_screen.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const tall = Size(360, 3600);
final today = DateTime.now().toIso8601String().substring(0, 10);

FakeApi expensesApi() => FakeApi()
  ..gets['/api/Hotel/finance/expenses'] = [
    {'hotelexpenseid': 1, 'expensedate': '${today}T00:00:00', 'category': 'Utilities', 'description': 'Power bill', 'amount': 300,
      'paymentmethod': 'Cash', 'hotelcashaccountid': 5, 'paidto': 'ECG', 'status': 'Approved'},
    {'hotelexpenseid': 2, 'expensedate': '2025-01-05', 'category': 'Laundry', 'description': 'Detergent', 'amount': 80,
      'paymentmethod': 'Credit', 'hotelsupplierid': 4, 'status': 'Draft'},
    {'hotelexpenseid': 3, 'expensedate': today, 'category': 'Utilities', 'description': 'Old cancelled', 'amount': 999, 'status': 'Cancelled'},
  ]
  ..gets['/api/Hotel/finance/expense-categories'] = [
    {'hotelexpensecategoryid': 10, 'name': 'Utilities', 'isactive': true},
    {'hotelexpensecategoryid': 11, 'name': 'Laundry', 'isactive': true},
    {'hotelexpensecategoryid': 12, 'name': 'Retired', 'isactive': false},
  ]
  ..gets['/api/Hotel/finance/cash-accounts'] = [
    {'hotelcashaccountid': 5, 'accountname': 'Front desk till', 'currentbalance': 1200, 'isactive': true, 'purpose': 'FrontDesk'},
  ]
  ..gets['/api/Hotel/suppliers'] = [
    {'hotelSupplierId': 4, 'supplierName': 'CleanCo', 'isActive': true},
  ];

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

Finder inDialog(String text) => find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

void main() {
  test('the three rows open native screens; payable links open Hotel pages', () {
    for (final h in ['/hotel-expenses', '/hotel-supplier-payments', '/hotel-supplier-balances']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    expect(BalanceRail.hotel.supplierDocumentHref({'documentType': 'Expense', 'documentId': 2}), '/hotel-expenses?expenseId=2');
  });

  test('filters: cancelled rows hidden; category, dates and search', () {
    final rows = [
      for (final e in (expensesApi().gets['/api/Hotel/finance/expenses'] as List).cast<Map>())
        {...e, 'hotelExpenseId': e['hotelexpenseid'], 'expenseDate': e['expensedate'], 'paidTo': e['paidto']},
    ];
    expect(filterHotelExpenses(rows).length, 2);
    expect(filterHotelExpenses(rows, category: 'Laundry').single['hotelExpenseId'], 2);
    expect(filterHotelExpenses(rows, from: '2025-06-01').single['hotelExpenseId'], 1);
    expect(filterHotelExpenses(rows, search: 'ecg').single['hotelExpenseId'], 1);
    expect(filterHotelExpenses(rows, focusId: 2).single['hotelExpenseId'], 2);
  });

  testWidgets('the list: cards, totals, and what a row shows', (tester) async {
    await open(tester, HotelExpensesScreen(session: await sessionFor(expensesApi()), company: hotel), size: tall);
    expect(find.text('Track operational costs and financial records'), findsOneWidget);
    expect(find.text('This Month'), findsOneWidget);
    expect(find.text('Total (Filtered)'), findsOneWidget);
    expect(find.text('Power bill'), findsOneWidget);
    expect(find.text('Old cancelled'), findsNothing);
    expect(find.text('Not posted (Edit to post)'), findsOneWidget, reason: 'the Draft row');
    expect(find.text('Front desk till'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add Expense: checks, then posts with postNow', (tester) async {
    final api = expensesApi();
    await open(tester, HotelExpensesScreen(session: await sessionFor(api), company: hotel), size: tall);
    await tapText(tester, 'Add Expense');
    expect(find.text('The money leaves the chosen account when you save.'), findsOneWidget);
    expect(inDialog('Utilities'), findsOneWidget, reason: 'the first active category is picked');
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).at(0), 'Generator fuel');
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).at(1), '150');
    await tapText(tester, 'Save Expense');
    expect(find.text('Select a cash account'), findsOneWidget);
    await tester.ensureVisible(inDialog('Pick account to debit'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog('Pick account to debit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Front desk till [Front Desk] — Bal: 1200.00').last);
    await tester.pumpAndSettle();
    await tapText(tester, 'Save Expense');
    final w = api.writes.lastWhere((w) => w.url.path == '/api/Hotel/finance/expenses');
    final body = jsonDecode(w.body) as Map;
    expect(w.method, 'POST');
    expect(body['postNow'], true);
    expect(body['hotelCashAccountId'], 5);
    expect(body['hotelExpenseCategoryId'], 10);
    expect(body['category'], 'Utilities');
    expect(body['amount'], 150);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Credit needs a supplier; Edit puts; Delete cancels', (tester) async {
    final api = expensesApi();
    await open(tester, HotelExpensesScreen(session: await sessionFor(api), company: hotel), size: tall);
    // The Credit row (Detergent) is the second card.
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Edit').at(1));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Supplier *'), findsOneWidget);
    expect(find.text('This bill appears on Supplier Balances.'), findsOneWidget);
    await tapText(tester, 'Save changes');
    final put = api.writes.lastWhere((w) => w.method == 'PUT');
    expect(put.url.path, '/api/Hotel/finance/expenses/2');
    expect((jsonDecode(put.body) as Map)['hotelSupplierId'], 4);

    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Delete').first);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('If it was paid, the money goes back to its account.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    final cancel = api.writes.lastWhere((w) => w.url.path.endsWith('/cancel'));
    expect(cancel.url.path, '/api/Hotel/finance/expenses/1/cancel');
    expect(jsonDecode(cancel.body), {'farmId': 'h1', 'reason': 'Deleted'});
  });

  testWidgets('Categories: lists them and adds one', (tester) async {
    final api = expensesApi();
    await open(tester, HotelExpensesScreen(session: await sessionFor(api), company: hotel), size: tall);
    await tapText(tester, 'Categories');
    expect(find.text('Manage categories for hotel expenses'), findsOneWidget);
    expect(find.text('inactive'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Repairs');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    final w = api.writes.lastWhere((w) => w.url.path == '/api/Hotel/finance/expense-categories');
    expect(jsonDecode(w.body), {'name': 'Repairs', 'farmId': 'h1'});
    expect(find.text('Category added'), findsOneWidget);
  });

  testWidgets('?expenseId= narrows the list to one bill', (tester) async {
    final api = expensesApi();
    final screen = moneyScreenForHref('/hotel-expenses?expenseId=2', await sessionFor(api), hotel);
    expect(screen, isA<HotelExpensesScreen>());
    await open(tester, screen!, size: tall);
    expect(find.text('Showing expense #2 only.'), findsOneWidget);
    expect(find.text('Power bill'), findsNothing);
    await tapText(tester, 'Show all expenses');
    expect(find.text('Power bill'), findsOneWidget);
  });

  testWidgets('Supplier Payments and Balances read the Hotel routes and accounts', (tester) async {
    final api = expensesApi()
      ..gets['/api/Hotel/balances/supplier-payments'] = [
        {'paymentId': 'SP-1', 'partyName': 'CleanCo', 'amount': 40, 'paymentDate': today, 'status': 'Posted', 'cashAccountId': 5,
          'allocations': [{'documentType': 'Expense', 'documentId': 2, 'amount': 40}]},
      ]
      ..gets['/api/Hotel/balances/supplier-balances'] = [
        {'partyId': 4, 'partyName': 'CleanCo', 'totalBalance': 40, 'openDocumentCount': 1},
      ]
      ..gets['/api/Hotel/balances/supplier-balances/summary'] = {'totalBalance': 40, 'partyCount': 1};
    await open(tester, SupplierPaymentsScreen(session: await sessionFor(api), company: hotel, rail: BalanceRail.hotel), size: tall);
    expect(api.requests.any((r) => r.url.path == '/api/Hotel/balances/supplier-payments'), isTrue);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
    expect(find.textContaining('CleanCo'), findsWidgets);
    expect(find.textContaining('Front desk till'), findsWidgets, reason: 'lowercase account fields are read');

    await open(tester, CustomerBalancesScreen(session: await sessionFor(api), company: hotel, side: BalanceSide.supplier, rail: BalanceRail.hotel),
        size: tall);
    expect(api.requests.any((r) => r.url.path == '/api/Hotel/balances/supplier-balances'), isTrue);
    expect(api.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
    expect(find.textContaining('CleanCo'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
