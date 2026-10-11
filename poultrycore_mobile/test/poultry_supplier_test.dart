// Poultry → Expenses → Supplier Balances and Supplier Payments, at phone width:
// the supplier side of the balances page (its endpoints, wording, the required
// cash account and the overdraw check), and the payments ledger.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/supplier_payments_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/balances_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/sales/customer_balances_screen.dart';

import 'support/harness.dart';

FakeApi balancesApi() => FakeApi()
  ..gets['/api/Poultry/supplier-balances'] = [
    {'partyId': 3, 'partyName': 'Agro Ltd', 'totalBalance': 900, 'overdueBalance': 400, 'openDocumentCount': 2, 'oldestDocumentDate': '2026-08-01'},
  ]
  ..gets['/api/Poultry/supplier-balances/summary'] = {
    'totalBalance': 900, 'partyCount': 1, 'overdueBalance': 400, 'paymentsToday': 0, 'largestBalance': 900, 'largestPartyName': 'Agro Ltd',
  }
  ..gets['/api/Poultry/supplier-payments'] = <Map>[]
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 5, 'accountName': 'Main Cash', 'currentBalance': 300, 'isActive': true, 'allowNegativeBalance': false},
    {'poultryCashAccountId': 6, 'accountName': 'Bank', 'currentBalance': 5000, 'isActive': true, 'allowNegativeBalance': false},
  ]
  ..gets['/api/Poultry/supplier-balances/3/open-purchases'] = [
    {'documentType': 'RawMaterialPurchase', 'documentId': 41, 'reference': 'PUR-41', 'documentDate': '2026-08-01', 'totalAmount': 500,
      'amountPaid': 0, 'balance': 500, 'label': 'Maize', 'isOverdue': true, 'ageDays': 66, 'status': 'Unpaid'},
    {'documentType': 'FlockBatch', 'documentId': 7, 'reference': 'FB-7', 'documentDate': '2026-09-01', 'totalAmount': 400,
      'amountPaid': 0, 'balance': 400, 'label': 'Layers', 'status': 'Unpaid'},
  ];

FakeApi paymentsApi() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 5, 'accountName': 'Main Cash', 'isActive': true},
  ]
  ..gets['/api/Poultry/supplier-payments'] = [
    {'paymentId': '17', 'paymentDate': '2026-10-02T00:00:00', 'partyId': 3, 'partyName': 'Agro Ltd', 'totalAmount': 500,
      'allocationCount': 1, 'paymentMethod': 'MoMo', 'cashAccountId': 5, 'reference': 'MM-1', 'sourceType': 'SupplierBalances',
      'createdBy': 'Ama', 'status': 'Posted'},
    {'paymentId': '18', 'paymentDate': '2026-10-03T00:00:00', 'partyId': 4, 'partyName': 'Soy Co', 'totalAmount': 800,
      'allocationCount': 2, 'paymentMethod': 'Cash', 'cashAccountId': 5, 'sourceType': 'ExpenseEntry', 'status': 'Posted'},
    {'paymentId': '19', 'paymentDate': '2026-09-20T00:00:00', 'partyId': 3, 'partyName': 'Agro Ltd', 'totalAmount': 70,
      'allocationCount': 1, 'paymentMethod': 'Cash', 'sourceType': 'PurchaseEntry', 'status': 'Reversed', 'reversalReason': 'Duplicate'},
  ]
  ..gets['/api/Poultry/supplier-payments/17'] = {
    'payment': {},
    'allocations': [
      {'allocationId': 1, 'documentType': 'RawMaterialPurchase', 'documentId': 41, 'reference': 'PUR-41', 'label': 'Maize',
        'documentTotal': 500, 'balanceBefore': 500, 'amountApplied': 500, 'balanceAfter': 0, 'status': 'Posted'},
    ],
  }
  ..gets['/api/Poultry/supplier-payments/18'] = {
    'payment': {},
    'allocations': [
      {'allocationId': 2, 'documentType': 'Expense', 'documentId': 9, 'reference': 'EXP-9', 'documentTotal': 300, 'balanceBefore': 300,
        'amountApplied': 300, 'balanceAfter': 0, 'status': 'Posted'},
      {'allocationId': 3, 'documentType': 'FlockBatch', 'documentId': 7, 'reference': 'FB-7', 'documentTotal': 500, 'balanceBefore': 500,
        'amountApplied': 500, 'balanceAfter': 0, 'status': 'Posted'},
    ],
  }
  ..gets['/api/Poultry/supplier-payments/19'] = {
    'payment': {},
    'allocations': [
      {'allocationId': 4, 'documentType': 'RawMaterialPurchase', 'documentId': 40, 'reference': 'PUR-40', 'documentTotal': 70,
        'balanceBefore': 70, 'amountApplied': 70, 'balanceAfter': 0, 'status': 'Reversed'},
    ],
  };

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

Future<void> pickOn(WidgetTester tester, String shown, String option) async {
  await see(tester, find.text(shown));
  await tester.tap(find.ancestor(of: find.text(shown), matching: find.byType(AppSelect<String>)).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  group('supplier rules', () {
    test('the side decides endpoints, wording and the payment query', () {
      const s = BalanceSide.supplier;
      expect((s.balancesPath, s.paymentsPath, s.openLeaf, s.statementLeaf), ('supplier-balances', 'supplier-payments', 'open-purchases', 'suppliers'));
      expect(s.payTitle(single: false), 'Record bulk payment');
      expect(s.paymentQuery(partyId: 3, documentType: 'FlockBatch', documentId: 7), {'supplierId': '3', 'documentType': 'FlockBatch', 'documentId': '7'});
      expect(BalanceSide.customer.paymentQuery(partyId: 3, documentType: 'Sale', documentId: 7), {'customerId': '3', 'saleId': '7'});
      expect(paymentOverdraws(s, {'currentBalance': 300, 'allowNegativeBalance': false}, 400), isTrue);
      expect(paymentOverdraws(s, {'currentBalance': 300, 'allowNegativeBalance': true}, 400), isFalse);
      expect(paymentOverdraws(BalanceSide.customer, {'currentBalance': 0}, 400), isFalse);
    });

    test('the ledger: labels, links and every filter', () {
      expect(payableTypeLabel('AssetCost'), 'Capital investment');
      expect(supplierSourceLabel('ExpenseEntry'), 'Expense entry');
      expect(supplierDocumentHref({'documentType': 'Expense', 'documentId': 9}), '/expenses?expenseId=9');
      final rows = [for (final r in paymentsApi().gets['/api/Poultry/supplier-payments'] as List) r as Map];
      List<Object?> ids(SupplierPaymentFilters f, [Map<String, List<Map>> a = const {}]) =>
          [for (final r in filterSupplierPayments(rows, f, a)) r['paymentId']];
      expect(ids(SupplierPaymentFilters()..appliedTo = 'multiple'), ['18']);
      expect(ids(SupplierPaymentFilters()..status = 'Reversed'), ['19']);
      expect(ids(SupplierPaymentFilters()..min = '100'..max = '600'), ['17']);
      expect(ids(SupplierPaymentFilters()..source = 'PurchaseEntry'), ['19']);
      expect(ids(SupplierPaymentFilters()..search = 'fb-7', {'18': [{'reference': 'FB-7', 'documentType': 'FlockBatch'}]}), ['18']);
      expect(ids(SupplierPaymentFilters()..payableType = 'Expense', {'17': [{'documentType': 'RawMaterialPurchase'}]}), ['18', '19'],
          reason: 'a row whose allocation is not loaded yet is kept');
    });
  });

  test('both pages are on the sidebar', () {
    expect(pageScreens.containsKey('/supplier-balances'), isTrue);
    expect(pageScreens.containsKey('/supplier-payments'), isTrue);
  });

  testWidgets('Supplier Balances: wording, open purchases, a bulk payment needs an account and must not overdraw', (tester) async {
    final a = balancesApi();
    await open(tester, CustomerBalancesScreen(session: await sessionFor(a), company: company, side: BalanceSide.supplier), size: phone);

    expect(find.text('Supplier Balances'), findsWidgets);
    expect(find.textContaining('Who we owe, which purchases'), findsOneWidget);
    expect(find.text('Total supplier balance'), findsOneWidget);
    expect(find.text('Suppliers owed'), findsOneWidget);
    expect(find.text('Overdue payables'), findsOneWidget);
    await see(tester, find.text('All payments'));
    await see(tester, find.text('Show 2 open purchases'));
    await tap(tester, find.text('Show 2 open purchases'));
    expect(a.requests.any((r) => r.url.path == '/api/Poultry/supplier-balances/3/open-purchases'), isTrue);
    await see(tester, find.text('PUR-41'));
    expect(find.text('Record payment'), findsWidgets);

    await tap(tester, find.text('Record bulk payment'));
    expect(find.text('Record bulk payment'), findsWidgets);
    expect(find.text('Cash account'), findsOneWidget, reason: 'required on the supplier side');
    await tester.enterText(find.byType(TextFormField).first, '400');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto-allocate oldest first'));
    await tester.pumpAndSettle();
    await see(tester, find.text('Select account'));
    await tester.tap(find.ancestor(of: find.text('Select account'), matching: find.byType(AppSelect<int>)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Cash · GHC 300.00').last);
    await tester.pumpAndSettle();
    await see(tester, find.textContaining('Main Cash holds GHC 300.00 — this payment would overdraw it.', findRichText: true));
    await see(tester, find.text('Main Cash · GHC 300.00'));
    await tester.tap(find.text('Main Cash · GHC 300.00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank · GHC 5,000.00').last);
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(FilledButton, 'Record payment'));

    final w = a.writes.single;
    expect(w.url.path, '/api/Poultry/supplier-payments');
    final b = jsonDecode(w.body) as Map;
    expect((b['partyId'], b['amount'], b['cashAccountId'], b['sourceType']), (3, 400, 6, 'SupplierBalances'));
    expect(b['allocations'], [
      {'saleId': null, 'documentType': 'RawMaterialPurchase', 'documentId': 41, 'amount': 400},
    ]);
    expect(find.textContaining('Payment recorded'), findsOneWidget);
  });

  testWidgets('Supplier Payments: figures, cards, filters, allocation, reverse from the card, CSV', (tester) async {
    final shared = <(String, List<int>)>[];
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add((name, bytes));
    final a = paymentsApi();
    await open(tester, SupplierPaymentsScreen(session: await sessionFor(a), company: company), size: phone);

    expect(find.text('3'), findsOneWidget, reason: 'payments');
    expect(find.text('GHC 1,300.00'), findsOneWidget, reason: 'posted only');
    await see(tester, find.text('SPAY-17'));
    expect(find.text('Agro Ltd · 2 Oct 2026'), findsOneWidget);
    expect(find.text('PUR-41'), findsOneWidget, reason: 'a one-item row fetches what it paid');
    expect(find.text('Supplier Balances'), findsOneWidget, reason: 'entered from');
    await see(tester, find.text('2 items'));

    await tap(tester, find.widgetWithText(OutlinedButton, 'Reverse'));
    await see(tester, find.text('Reverse payment'));
    await tester.tap(find.text('Reverse payment'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A reason is required'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.ancestor(of: find.text('Why is this being reversed?'), matching: find.byType(Column)).first,
        matching: find.byType(TextFormField)), 'Paid the wrong supplier');
    await tester.tap(find.text('Reverse payment'));
    await tester.pumpAndSettle();
    final w = a.writes.single;
    expect(w.url.path, '/api/Poultry/supplier-payments/17/reverse');
    expect(jsonDecode(w.body), {'farmId': 'farm-1', 'reason': 'Paid the wrong supplier', 'reversedBy': 'user-1'});

    await pickOn(tester, 'All statuses', 'Reversed');
    await see(tester, find.text('SPAY-19'));
    expect(find.text('SPAY-17'), findsNothing);
    await tap(tester, find.text('More filters'));
    await pickOn(tester, 'Anywhere', 'Purchase entry');
    await tap(tester, find.text('Reset'));
    await see(tester, find.text('SPAY-17'));

    await pickOn(tester, 'All time', 'Last 30 Days');
    expect(a.requests.lastWhere((r) => r.url.path == '/api/Poultry/supplier-payments').url.queryParameters.containsKey('from'), isTrue);

    await tap(tester, find.text('View table format'));
    await see(tester, find.text('SPAY-18'));
    await tester.ensureVisible(find.byIcon(Icons.keyboard_arrow_right).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_arrow_right).at(1));
    await tester.pumpAndSettle();
    await see(tester, find.text('EXP-9'));
    expect(find.text('Entered from Expense entry'), findsOneWidget);
    await tap(tester, find.text('Cards'));

    await tap(tester, find.text('CSV'));
    expect(shared.single.$1, startsWith('supplier-payments-'));
    final csv = utf8.decode(shared.single.$2.sublist(3)).split('\n');
    expect(csv.first, supplierExportHeaders.join(','));
    expect(csv.length, 4);
  });
}
