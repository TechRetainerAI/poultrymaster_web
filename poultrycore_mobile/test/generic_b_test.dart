// Report 36 (B of the 9 Nov web pull): the Generic pages the app did not have,
// checked against the web pages at phone width with a fake API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/generic/generic_credits_screen.dart';
import 'package:poultrycore_mobile/pages/generic/generic_kit.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart' show pageScreens;
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final generic = Company(farmId: 'g1', name: 'Kofi Shop', type: CompanyType.generic, role: 'Admin');
const base = '/api/generic-company/g1';

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-11-12', 'companyLocalDateTime': '2026-11-12T10:00:00', 'utcNow': '2026-11-12T10:00:00Z',
  }
  ..gets['$base/module-settings'] = {for (final k in genericModuleKeys) k: true}
  ..gets['$base/customers'] = [
    {'genericCustomerId': 1, 'customerName': 'Ama', 'isActive': true},
    {'genericCustomerId': 2, 'customerName': 'Gone Ltd', 'isActive': false},
  ]
  ..gets['$base/suppliers'] = [
    {'genericSupplierId': 4, 'supplierName': 'SoapCo', 'isActive': true},
  ]
  ..gets['$base/customer-credits'] = [
    {'genericCustomerCreditId': 1, 'customerName': 'Ama', 'creditType': 'Overpayment', 'amount': 100, 'remainingBalance': 60,
      'creditDate': '2026-11-10T00:00:00', 'notes': 'Paid twice', 'status': 'Active'},
    {'genericCustomerCreditId': 2, 'customerName': 'Ama', 'creditType': 'Advance', 'amount': 50, 'remainingBalance': 0,
      'creditDate': '2026-11-01T00:00:00', 'status': 'Used'},
  ]
  ..gets['$base/supplier-credits'] = [];

void main() {
  test('credit totals follow the web: active rows add what is left, the rest add what was used', () {
    final t = genericCreditTotals([
      {'amount': 100, 'remainingBalance': 60, 'status': 'Active'},
      {'amount': 50, 'remainingBalance': 0, 'status': 'Used'},
      {'amount': 30, 'remainingBalance': 10, 'status': 'Expired'},
    ]);
    expect((t.total, t.active, t.used), (180, 60, 70));
  });

  test('menus: Customer Credits after Payments, Supplier Credits after Supplier balances, both routed', () {
    final groups = webNavGroups['generic']!;
    List<String> hrefs(String g) => [for (final s in groups.firstWhere((x) => x.title == g).subGroups) for (final l in s.links) l.href];
    final sales = hrefs('Sales'), buy = hrefs('Purchasing');
    expect(sales.indexOf('/generic-customer-credits'), sales.indexOf('/generic-customer-payments') + 1);
    expect(buy.indexOf('/generic-supplier-credits'), buy.indexOf('/generic-supplier-balances') + 1);
    expect(pageScreens['/generic-customer-credits'], isNotNull);
    expect(pageScreens['/generic-supplier-credits'], isNotNull);
  });

  testWidgets('Customer Credits: cards, rows and the Record dialog post the web body', (tester) async {
    final a = api();
    await open(tester, GenericCreditsScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.text('Customer Credits'), findsWidgets);
    expect(find.text('Advances, overpayments and credit notes held for customers.'), findsOneWidget);
    expect(find.text('TOTAL CREDITS'), findsOneWidget);
    expect(find.text('Ama'), findsNWidgets(2));
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Used'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('credit-new')));
    await tester.pumpAndSettle();
    expect(find.text('Record customer credit'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('credit-save')));
    await tester.pumpAndSettle();
    expect(find.text('Select a customer'), findsOneWidget);
    expect(a.writes, isEmpty);

    await tester.tap(find.byKey(const ValueKey('credit-party')));
    await tester.pumpAndSettle();
    expect(find.text('Gone Ltd'), findsNothing, reason: 'only active customers');
    await tester.tap(find.text('Ama').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('credit-save')));
    await tester.pumpAndSettle();
    expect(find.text('Amount must be > 0'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('credit-amount')), '25');
    await tester.tap(find.byKey(const ValueKey('credit-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CreditNote').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('credit-save')));
    await tester.pumpAndSettle();
    expect(a.writes, hasLength(1));
    final b = a.lastBody('$base/customer-credits');
    expect(b, containsPair('genericCustomerId', 1));
    expect(b, containsPair('creditType', 'CreditNote'));
    expect(b, containsPair('amount', 25));
    expect(b, containsPair('farmId', 'g1'));
  });

  testWidgets('Supplier Credits: its own words, Advance first, empty list', (tester) async {
    final a = api();
    await open(tester, GenericCreditsScreen(session: await sessionFor(a), company: generic, supplier: true), size: phone);
    expect(find.text('Credit held with suppliers, advance payments and credit notes.'), findsOneWidget);
    expect(find.text('No credits.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('credit-new')));
    await tester.pumpAndSettle();
    expect(find.text('Record supplier credit'), findsOneWidget);
    expect(find.text('Advance'), findsOneWidget, reason: 'the supplier page starts on Advance');
  });
}
