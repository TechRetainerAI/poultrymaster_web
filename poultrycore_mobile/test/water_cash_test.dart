// Water → Money → Cash accounts, Cash Transfers and Reconciliation: what the
// web's Water pages do differently from Poultry's. The shared flows themselves
// are covered by the generated water_cash_accounts / water_cash_transfers /
// water_reconciliation tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/cash_accounts_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/money/cash_transfers_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';
import 'package:poultrycore_mobile/pages/poultry/money/reconciliation_screen.dart';
import 'package:poultrycore_mobile/pages/water/reports/water_money_reports.dart' show waterMoneyRail;

import 'support/harness.dart';

final water = Company(farmId: 'farm-1', name: 'Win Water', type: CompanyType.water);

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z'}
  ..gets['/api/Water/cash-accounts'] = [
    {'waterCashAccountId': 5, 'accountName': 'Factory Box', 'accountType': 'FactoryCashBox', 'openingBalance': 0, 'currentBalance': 900, 'isActive': true},
  ]
  ..gets['/api/Water/cash-accounts/5'] = {'waterCashAccountId': 5, 'accountName': 'Factory Box', 'accountType': 'FactoryCashBox', 'currentBalance': 900, 'isActive': true}
  ..gets['/api/Water/cash-accounts/transactions'] = <Map>[]
  ..gets['/api/Water/cash-transfers'] = [
    {'waterCashTransferId': 31, 'fromAccountName': 'Factory Box', 'toAccountName': 'Bank', 'transferDate': '2026-10-02T00:00:00', 'amount': 300, 'status': 'Approved'},
  ]
  ..gets['/api/Water/cash-reconciliations/account-status'] = [
    {'waterCashAccountId': 5, 'ledgerBalance': 900, 'cacheDrift': 0, 'lastReconciledAt': '2026-10-01', 'daysSinceReconciled': 5},
  ]
  ..gets['/api/Water/cash-reconciliations/account/5'] = [
    {'waterCashReconciliationId': 8, 'referenceNo': 'CC-8', 'reconciliationDate': '2026-10-01T00:00:00', 'systemBalance': 900, 'actualBalance': 900, 'difference': 0, 'status': 'Posted'},
  ];

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, 200));
    await tester.pumpAndSettle();
  }
  Scrollable.ensureVisible(tester.element(f.first), alignment: .5);
  await tester.pumpAndSettle();
}

Finder inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

void main() {
  test('the three pages and their deep links are native for Water', () async {
    for (final r in ['/water-cash-accounts', '/water-cash-transfers', '/water-cash-reconciliation']) {
      expect(pageScreens.containsKey(r), isTrue, reason: r);
    }
    final s = await sessionFor(FakeApi());
    final detail = moneyScreenForHref('/water-cash-accounts/5', s, water);
    expect(detail, isA<CashAccountDetailScreen>());
    expect((detail as CashAccountDetailScreen).rail, waterMoneyRail);
    final rec = moneyScreenForHref('/water-cash-reconciliation?accountId=5', s, water);
    expect((rec as ReconciliationScreen).rail, waterMoneyRail);
    expect(rec.accountId, 5);
  });

  testWidgets('Cash accounts: title, plain figures, no cash-flow link, amount on a transfer, Water types', (tester) async {
    await open(tester, CashAccountsScreen(session: await sessionFor(api()), company: water, rail: waterMoneyRail), size: phone);
    expect(find.text('Cash accounts'), findsWidgets);
    expect(find.text('Total cash at hand'), findsOneWidget, reason: 'plain card, not the upper-case stat tile');
    expect(find.text("See the whole company's cash flow →"), findsNothing);
    await see(tester, find.text('Factory Box → Bank'));
    expect(find.text('AMOUNT'), findsOneWidget, reason: 'the transfer amount is a highlight');

    await see(tester, find.text('New account'));
    await tester.tap(find.text('New account'));
    await tester.pumpAndSettle();
    expect(inDialog(find.text('FactoryCashBox')), findsOneWidget, reason: 'default type');
    await tester.tap(find.ancestor(of: inDialog(find.text('FactoryCashBox')), matching: find.byType(AppSelect<String>)));
    await tester.pumpAndSettle();
    expect(find.text('DriverCash'), findsOneWidget);
    expect(find.text('FarmCashBox'), findsNothing);
  });

  testWidgets('account page: Water back label; Adjust "Other" has its own field; delete text', (tester) async {
    final a = api();
    await open(tester, CashAccountDetailScreen(session: await sessionFor(a), company: water, rail: waterMoneyRail, accountId: 5), size: phone);
    expect(find.text('Back to Cash & Accounts'), findsOneWidget);
    await tester.tap(find.text('Adjust balance'));
    await tester.pumpAndSettle();
    await tester.tap(find.ancestor(of: inDialog(find.text('Why is the balance changing?')), matching: find.byType(AppSelect<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();
    expect(inDialog(find.text('Say what happened *')), findsOneWidget);
    expect(inDialog(find.text('e.g. Till float returned from the depot')), findsOneWidget);
    await tester.tap(inDialog(find.text('Cancel')));
    await tester.pumpAndSettle();

    await see(tester, find.text('Delete'));
    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('If this account has no transactions it is permanently deleted.'), findsOneWidget);
  });

  testWidgets('transfers say "company"; reconciliation cards say Actual balance', (tester) async {
    await open(tester, CashTransfersScreen(session: await sessionFor(api()), company: water, rail: waterMoneyRail), size: phone);
    expect(find.textContaining("Move money between the company's own cash accounts."), findsOneWidget);

    await open(tester, ReconciliationScreen(session: await sessionFor(api()), company: water, rail: waterMoneyRail), size: phone);
    await see(tester, find.text('CC-8'));
    expect(find.text('ACTUAL BALANCE'), findsOneWidget);
    expect(find.text('COUNTED'), findsNothing);
    expect(find.text('Balanced'), findsWidgets);
  });
}
