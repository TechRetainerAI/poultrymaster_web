// Generic → Purchasing at phone width (lib/nav/generic-nav-config.ts
// "Purchasing"): Suppliers (+ ledger), Purchases (+ New purchase), Supplier
// payments, Supplier balances, Expenses (+ New expense) and Recurring expenses,
// each against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/generic/generic_customer_payments_screen.dart';
import 'package:poultrycore_mobile/pages/generic/generic_expenses_screen.dart';
import 'package:poultrycore_mobile/pages/generic/generic_kit.dart';
import 'package:poultrycore_mobile/pages/generic/generic_purchases_screen.dart';
import 'package:poultrycore_mobile/pages/generic/generic_suppliers_screen.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart' show pageScreens;
import 'package:poultrycore_mobile/pages/poultry/expenses/recurring_expenses_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/balances_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/customer_balances_screen.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final generic = Company(farmId: 'g1', name: 'Kofi Shop', type: CompanyType.generic, role: 'Admin');
const base = '/api/generic-company/g1';

String ghs(String n) => 'GHS $n';

final landlord = <String, Object?>{
  'genericSupplierId': 1, 'supplierName': 'Mr Boateng', 'supplierType': 'Landlord', 'phoneNumber': '0207000000', 'location': 'Osu',
  'paymentTermsDays': 30, 'openingBalance': 0, 'currentBalance': 500, 'isActive': true,
};
final soapCo = <String, Object?>{
  'genericSupplierId': 2, 'supplierName': 'SoapCo', 'supplierType': 'ProductSupplier', 'paymentTermsDays': 0, 'openingBalance': 0,
  'currentBalance': 0, 'isActive': true,
};

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-11-04', 'companyLocalDateTime': '2026-11-04T10:00:00', 'utcNow': '2026-11-04T10:00:00Z',
  }
  ..gets['$base/module-settings'] = {for (final k in genericModuleKeys) k: true}
  ..gets['$base/suppliers'] = [landlord, soapCo]
  ..gets['$base/suppliers/1'] = landlord
  ..gets['$base/suppliers/1/ledger'] = [
    {'genericSupplierLedgerId': 1, 'transactionDate': '2026-11-01T00:00:00', 'transactionType': 'ExpenseCredit', 'description': 'Rent',
      'expenseId': 8, 'debitAmount': 0, 'creditAmount': 500, 'balanceAfterTransaction': 500},
  ]
  ..gets['$base/products'] = [
    {'genericProductId': 1, 'productName': 'Bar soap', 'sku': 'SP-1', 'costPrice': 4},
  ]
  ..gets['$base/cash-accounts'] = [
    {'genericCashAccountId': 6, 'accountName': 'Till', 'accountType': 'Cash', 'isActive': true, 'currentBalance': 900, 'allowNegativeBalance': false},
  ]
  ..gets['$base/expense-categories'] = [
    {'genericExpenseCategoryId': 3, 'name': 'Rent', 'isActive': true},
    {'genericExpenseCategoryId': 4, 'name': 'Old', 'isActive': false},
  ]
  ..gets['$base/purchases'] = [
    {'genericPurchaseId': 5, 'purchaseDate': '2026-11-02T00:00:00', 'supplierName': 'SoapCo', 'invoiceNumber': 'INV-7', 'totalAmount': 80,
      'amountPaid': 50, 'balance': 30, 'status': 'Draft'},
  ]
  ..gets['$base/supplier-payments'] = [
    {'genericSupplierPaymentId': 9, 'genericSupplierId': 1, 'supplierName': 'Mr Boateng', 'paymentDate': '2026-11-03T00:00:00',
      'paymentMethod': 'Bank', 'amount': 200, 'status': 'Draft'},
  ]
  ..gets['$base/expenses'] = [
    {'genericExpenseId': 8, 'expenseDate': '2026-11-01T00:00:00', 'categoryName': 'Rent', 'description': 'November rent',
      'supplierName': 'Mr Boateng', 'paymentMethod': 'Credit', 'amount': 500, 'status': 'Submitted'},
    {'genericExpenseId': 7, 'expenseDate': '2026-10-01T00:00:00', 'paymentMethod': 'Cash', 'amount': 20, 'status': 'Approved'},
  ];

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 80 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, 200));
    await tester.pumpAndSettle();
  }
  Scrollable.ensureVisible(tester.element(f.first), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await see(tester, f);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Finder inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> tapIn(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Finder selectShowing(String shown) => find.ancestor(of: find.text(shown), matching: find.byType(AppSelect<String>)).first;

Future<void> choose(WidgetTester tester, Finder select, String option) async {
  await tapIn(tester, select);
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> enterIn(WidgetTester tester, String label, String text, {bool dialog = true}) async {
  final l = find.text(label);
  final field = find.descendant(
      of: find.ancestor(of: dialog ? inDialog(l) : l, matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.ensureVisible(field.first);
  await tester.enterText(field.first, text);
  await tester.pump();
}

void clearToasts(WidgetTester tester) => tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

void main() {
  tearDown(invalidateGenericModules);

  testWidgets('the Purchasing menu: web order, native screens, module switches', (tester) async {
    final groups = webNavGroups['generic']!;
    final p = groups.firstWhere((g) => g.title == 'Purchasing');
    const hrefs = [
      '/generic-suppliers', '/generic-purchases', '/generic-supplier-payments', '/generic-supplier-balances',
      '/generic-supplier-credits', '/generic-expenses', '/recurring-expenses',
    ];
    expect([for (final l in p.subGroups.single.links) l.href], hrefs);
    expect(groups.indexOf(p), groups.indexWhere((g) => g.title == 'Sales') + 1);
    expect(groups.where((g) => g.title == 'Finance'), isEmpty, reason: 'its rows all moved to Purchasing');
    final elsewhere = [for (final g in groups) if (g != p) for (final s in g.subGroups) for (final l in s.links) l.href];
    for (final h in hrefs) {
      expect(elsewhere, isNot(contains(h)));
      expect(pageScreens[h], isNotNull, reason: h);
    }
    expect(pageScreens['/generic-purchases/new'], isNotNull);
    expect(pageScreens['/generic-expenses/new'], isNotNull);

    final a = FakeApi()
      ..gets['$base/module-settings'] = {
        for (final k in genericModuleKeys) k: true,
        'enablePurchases': false,
        'enableSupplierBalances': false,
        'enableRecurringExpenses': null,
      };
    await tester.runAsync(() async => loadGenericModules(await sessionFor(a), generic));
    final gated = gateGenericCatalog(groups, generic).firstWhere((g) => g.title == 'Purchasing').subGroups.single.links.map((l) => l.href);
    expect(gated, ['/generic-suppliers', '/generic-supplier-payments', '/generic-supplier-credits', '/generic-expenses', '/recurring-expenses']);
  });

  test('filters, badges, ledger refs and the balances rail', () {
    expect([for (final s in filterGenericSuppliers([landlord, soapCo], 'osu')) s['genericSupplierId']], [1]);
    expect(genericSupplierLedgerRef({'purchaseId': 3}), 'Pur #3');
    expect(genericSupplierLedgerRef({'expenseId': 8}), 'Exp #8');
    final ex = [for (final r in api().gets['$base/expenses']! as List) r as Map];
    expect([for (final e in filterGenericExpenses(ex, search: 'november')) e['genericExpenseId']], [8]);
    final rail = BalanceRail.generic('g1');
    expect((rail.isGeneric, rail.cashAccountsPath, rail.cashAccountIdKey, rail.supplierPaymentsHref),
        (true, '$base/cash-accounts', 'genericCashAccountId', '/generic-supplier-payments'));
    expect(rail.supplierDocumentHref({'documentType': 'Expense', 'documentId': 8}), '/generic-expenses?expenseId=8');
    expect(rail.supplierDocumentHref({'documentType': 'Purchase', 'documentId': 5}), '/generic-purchases?purchaseId=5');
  });

  testWidgets('Suppliers: badges, create, delete warning, ledger', (tester) async {
    final a = api()..writeAnswers['$base/suppliers'] = {'genericSupplierId': 9, 'supplierName': 'ECG'};
    await open(tester, GenericSuppliersScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.text('2 supplier(s)'), findsOneWidget);
    expect(find.text('Owed'), findsOneWidget);
    expect(find.text('30d'), findsOneWidget);

    await tap(tester, find.text('New supplier'));
    await enterIn(tester, 'Supplier name *', 'ECG');
    await choose(tester, inDialog(selectShowing('ProductSupplier')), 'UtilityProvider');
    await enterIn(tester, 'Payment terms (days)', '14');
    await tapIn(tester, find.widgetWithText(FilledButton, 'Create'));
    final b = a.lastBody('$base/suppliers');
    expect((b['supplierName'], b['supplierType'], b['paymentTermsDays'], b['openingBalance'], b['farmId']), ('ECG', 'UtilityProvider', 14, 0, 'g1'));
    expect(b.containsKey('creditLimit'), isFalse);
    expect(find.textContaining('Supplier "ECG" created.'), findsOneWidget);
    clearToasts(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Delete'));
    expect(find.textContaining('Balance owed to "Mr Boateng": ${ghs('500.00')}.'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    await tap(tester, find.text('Mr Boateng'));
    expect(find.text('WE OWE THEM'), findsOneWidget);
    expect(find.text('Terms: 30 days'), findsOneWidget);
    expect(find.text('Exp #8'), findsOneWidget);
  });

  testWidgets('Purchases: approve with its confirm; New purchase lands on Draft', (tester) async {
    final a = api()..writeAnswers['$base/purchases'] = {'genericPurchaseId': 6};
    await open(tester, GenericPurchasesScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.text('#5 · SoapCo'), findsOneWidget);
    await see(tester, find.text(ghs('30.00')));
    await tap(tester, find.widgetWithText(OutlinedButton, 'Approve'));
    expect(find.text('Approve purchase #5?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(a.writes.last.url.path, '$base/purchases/5/approve');
    clearToasts(tester);

    await tap(tester, find.text('New purchase'));
    await see(tester, find.text('— select product —'));
    await choose(tester, selectShowing('— select product —'), 'Bar soap (SP-1)');
    await enterIn(tester, 'Qty', '10', dialog: false);
    await see(tester, find.text('Balance owed to supplier'));
    expect(find.text(ghs('40.00')), findsWidgets, reason: '10 × the cost price 4');
    await tap(tester, find.text('Create as Draft'));
    expect(find.textContaining('Credit purchase requires a supplier'), findsOneWidget, reason: 'nothing paid, no supplier');
    clearToasts(tester);
    await see(tester, find.text('— none —'));
    await choose(tester, selectShowing('— none —'), 'SoapCo');
    await tap(tester, find.text('Create as Draft'));
    final b = a.lastBody('$base/purchases');
    expect((b['genericSupplierId'], b['amountPaid'], b['genericCashAccountId'], b['farmId']), (2, 0, 6, 'g1'));
    expect(b['items'], [
      {'genericProductId': 1, 'description': 'Bar soap', 'quantity': 10, 'unitCost': 4, 'discountAmount': 0},
    ]);
    expect(find.textContaining('Purchase #6 created as Draft'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Draft'), findsOneWidget, reason: 'back on the list, Draft chosen');
  });

  testWidgets('Supplier payments: the supplier words, body, approve', (tester) async {
    final a = api()..writeAnswers['$base/supplier-payments'] = {'genericSupplierPaymentId': 10};
    await open(tester, GenericCustomerPaymentsScreen(session: await sessionFor(a), company: generic, supplier: true), size: phone);
    expect(find.text('1 payment(s) – money going out to suppliers.'), findsOneWidget);
    expect(find.text('#9 · Mr Boateng'), findsOneWidget);

    await tap(tester, find.text('Record payment'));
    expect(find.text('New supplier payment'), findsOneWidget);
    expect(find.text('Cash account (paid from)'), findsOneWidget);
    await choose(tester, inDialog(selectShowing('Pick supplier...')), 'Mr Boateng – owed ${ghs('500.00')}');
    await enterIn(tester, 'Amount *', '100');
    await tapIn(tester, find.widgetWithText(FilledButton, 'Create'));
    final b = a.lastBody('$base/supplier-payments');
    expect((b['genericSupplierId'], b['amount'], b['genericCashAccountId']), (1, 100, 6));
    expect(find.textContaining('Supplier payment created as Draft. Approve to debit supplier + cash.'), findsOneWidget);
    clearToasts(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Approve'));
    expect(a.writes.last.url.path, '$base/supplier-payments/9/approve');
  });

  testWidgets('Supplier balances: the shared page on the Generic routes', (tester) async {
    final a = api()
      ..gets['$base/balances/supplier-balances'] = [
        {'partyId': 1, 'partyName': 'Mr Boateng', 'totalBalance': 500, 'openDocumentCount': 1},
      ]
      ..gets['$base/balances/supplier-balances/summary'] = {'totalBalance': 500, 'partyCount': 1}
      ..gets['$base/balances/supplier-payments'] = [];
    await open(tester, CustomerBalancesScreen(session: await sessionFor(a), company: generic, side: BalanceSide.supplier, rail: BalanceRail.generic('g1')),
        size: phone);
    expect(a.requests.any((r) => r.url.path == '$base/balances/supplier-balances'), isTrue);
    expect(a.requests.any((r) => r.url.path == '$base/cash-accounts'), isTrue);
    expect(a.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
    await see(tester, find.text('Mr Boateng'));
    expect(find.text('Mr Boateng'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Expenses: approve a submitted one; New expense: credit needs a supplier', (tester) async {
    final a = api()..writeAnswers['$base/expenses'] = {'genericExpenseId': 11};
    await open(tester, GenericExpensesScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.text('#8 · Rent'), findsOneWidget);
    expect(find.text('#7 · Expense'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Approve'), findsOneWidget, reason: 'Submitted only; Approved has none');
    await tap(tester, find.widgetWithText(OutlinedButton, 'Approve'));
    expect(a.writes.last.url.path, '$base/expenses/8/approve');
    clearToasts(tester);

    await tap(tester, find.text('New expense'));
    expect(find.text('Till (Cash)'), findsOneWidget, reason: 'the first active account is chosen');
    await choose(tester, selectShowing('Choose category…'), 'Rent');
    expect(find.text('Old'), findsNothing);
    await enterIn(tester, 'Amount *', '250', dialog: false);
    await choose(tester, selectShowing('Cash'), 'Credit');
    expect(find.text('Supplier (credit) *'), findsOneWidget);
    final create = find.widgetWithText(FilledButton, 'Create as Draft');
    await see(tester, create);
    expect(tester.widget<FilledButton>(create).onPressed, isNull, reason: 'a credit expense needs a supplier');
    await choose(tester, selectShowing('Pick supplier…'), 'Mr Boateng');
    await tap(tester, create);
    final b = a.lastBody('$base/expenses');
    expect((b['genericExpenseCategoryId'], b['amount'], b['paymentMethod'], b['genericSupplierId'], b['genericCashAccountId']),
        (3, 250, 'Credit', 1, null));
    expect(find.textContaining('Expense #11 created as Draft'), findsOneWidget);
  });

  testWidgets('Recurring expenses: the Generic lists, and the approval note', (tester) async {
    final a = api()
      ..writeAnswers['/api/recurring-expenses/generate'] = {'generated': 0, 'autoPosted': 0, 'autoPostFailures': []}
      ..gets['/api/recurring-expenses/templates'] = []
      ..gets['/api/recurring-expenses/occurrences'] = []
      ..gets['/api/recurring-expenses/upcoming'] = [];
    await open(tester, RecurringExpensesScreen(session: await sessionFor(a), company: generic), size: phone);
    for (final p in ['expense-categories', 'suppliers', 'cash-accounts']) {
      expect(a.requests.any((r) => r.url.path == '$base/$p'), isTrue, reason: p);
    }
    expect(a.requests.any((r) => r.url.path.startsWith('/api/Poultry')), isFalse);
    expect(jsonEncode(a.requests.map((r) => r.url.path).toList()), isNot(contains('/api/Supplier')));
    expect(tester.takeException(), isNull);
  });
}
