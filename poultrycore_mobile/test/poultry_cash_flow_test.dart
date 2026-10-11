// Poultry → Money → Cash Flow: the running balance and buckets, then the page
// driven at phone width — every dropdown, every way an adjustment is saved.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/cash_adjustment_dialog.dart';
import 'package:poultrycore_mobile/pages/poultry/money/cash_flow_screen.dart';

import 'support/harness.dart';

final cashFlow = {
  'summary': {
    'moneyIn': 1500, 'moneyOut': 400, 'netCashFlow': 1100, 'openingCash': 200, 'closingCash': 1300,
    'operatingIn': 1000, 'operatingOut': 400, 'financingIn': 500, 'financingOut': 0, 'movementCount': 3,
  },
  'rows': [
    {'id': 1, 'rowSource': 'Sale', 'sourceType': 'CustomerPayment', 'sourceId': 11, 'flowGroup': 'OperatingIn', 'category': 'Sale', 'transactionDate': '2026-10-01T00:00:00', 'createdAt': '2026-10-01T08:00:00', 'description': 'Eggs to Ama', 'amount': 1000},
    {'id': 2, 'rowSource': 'Expense', 'sourceType': 'Expense', 'sourceId': 12, 'flowGroup': 'OperatingOut', 'category': 'Feed', 'transactionDate': '2026-10-02T00:00:00', 'createdAt': '2026-10-02T08:00:00', 'description': 'Layer mash', 'amount': -400},
    {'id': 3, 'rowSource': 'Adjustment', 'sourceType': 'Owner injection', 'sourceId': 31, 'flowGroup': 'FinancingIn', 'category': 'OwnerInjection', 'transactionDate': '2026-10-03T00:00:00', 'createdAt': '2026-10-03T08:00:00', 'description': 'Top up', 'amount': 500},
  ],
};

FakeApi api() => FakeApi()
  ..gets['/api/Poultry/cash-flow'] = cashFlow
  ..gets['/api/Poultry/customer-balances/summary'] = {'totalBalance': 300, 'partyCount': 2}
  ..gets['/api/Poultry/supplier-balances/summary'] = {'totalBalance': 120, 'partyCount': 1}
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 5, 'accountName': 'Main Cash Account', 'isActive': true, 'currentBalance': 900},
    {'poultryCashAccountId': 6, 'accountName': 'Old till', 'isActive': false},
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

Future<void> tapSeen(WidgetTester tester, Finder f) async {
  await see(tester, f);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String shown, String option) async {
  await see(tester, find.text(shown));
  await pick(tester, shown, option);
}

/// Inside the adjustment dialog.
Finder _inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> dialogPick(WidgetTester tester, String shown, String option) async {
  await tester.tap(_inDialog(find.text(shown)).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> dialogAmount(WidgetTester tester, String amount) async {
  await tester.enterText(_inDialog(find.byType(TextFormField)).first, amount);
  await tester.pump();
}

Future<void> openAdd(WidgetTester tester) async {
  await tester.drag(_list, const Offset(0, 3000));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add Adjustment'));
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.widgetWithText(FilledButton, label));
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pumpAndSettle();
}

void main() {
  group('cash flow rules', () {
    test('running cash from opening, oldest first; buckets by category', () {
      final rows = [for (final r in cashFlow['rows'] as List) r as Map];
      final run = withRunningBalance([rows[2], rows[0], rows[1]], 200);
      expect([for (final r in run) r['running']], [1200, 800, 1300]);
      final ins = cashFlowBuckets(rows, true);
      expect([for (final b in ins) (b.label, b.amount, b.percent)], [('Sales', 1000, 66.7), ('Owner injection', 500, 33.3)]);
      expect(previousRange('2026-10-01', '2026-10-10'), (from: '2026-09-21', to: '2026-09-30', days: 10));
      expect(previousRange('', ''), (from: null, to: null, days: 0));
      expect(adjustmentTypeFromLabel('Owner injection'), 'OwnerInjection');
      expect(sourceTypeLabel('CustomerPayment'), 'Sale');
      expect(sourceTypeLabel('SomethingNew'), 'Something New');
    });
  });

  test('on the sidebar route', () => expect(pageScreens.containsKey('/cash-flow'), isTrue));

  testWidgets('tiles, the identity line, filters, the table view, insights', (tester) async {
    final a = api();
    await open(tester, CashFlowScreen(session: await sessionFor(a), company: company), size: phone);
    final q = a.requests.where((r) => r.url.path == '/api/Poultry/cash-flow').map((r) => r.url.queryParameters).toList();
    expect(q.length, 3, reason: 'period, previous period, all time');
    expect(q.last.containsKey('fromDate'), isFalse, reason: 'cash at hand is all time');
    await see(tester, find.text('GHC 1,300.00'));
    expect(find.text('+GHC 1,100.00'), findsOneWidget);
    expect(find.text('+GHC 600.00'), findsOneWidget, reason: 'strictly business');
    expect(find.text('All time · 2 customers owing'), findsOneWidget);
    await see(tester, find.textContaining('of capital in'));

    await choose(tester, 'All categories', 'Operating expense');
    expect(find.text('Layer mash'), findsOneWidget);
    expect(find.text('Eggs to Ama'), findsNothing);
    await choose(tester, 'Operating expense', 'All categories');
    await choose(tester, 'All types', 'Sales');
    expect(find.text('Eggs to Ama'), findsOneWidget);
    expect(find.text('Top up'), findsNothing);
    await choose(tester, 'Sales', 'All types');

    await tapSeen(tester, find.text('View table format'));
    final edits = tester.widgetList<IconButton>(find.widgetWithIcon(IconButton, Icons.edit_outlined)).toList();
    expect(edits.where((b) => b.onPressed != null).length, 1, reason: 'only the adjustment is managed here');

    await tester.drag(_list, const Offset(0, 4000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash Flow Insights'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cash positive'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Money In by Source'), 200,
        scrollable: find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable)).first);
    expect(find.text('Money In by Source'), findsOneWidget);
  });

  testWidgets('a plain adjustment, unlinked then linked to an account', (tester) async {
    final a = api();
    await open(tester, CashFlowScreen(session: await sessionFor(a), company: company), size: phone);
    await openAdd(tester);
    expect(_inDialog(find.text('Old till')), findsNothing);
    await dialogPick(tester, 'What kind of adjustment?', 'Opening Balance');
    await dialogAmount(tester, '250');
    expect(find.textContaining('will be recorded without a cash account'), findsOneWidget);
    await save(tester, 'Save adjustment');
    final body = a.lastBody('/api/Cash/Adjustment');
    expect((body['AdjustmentType'], body['Amount'], body['FarmId'], body['UserId']), ('OpeningBalance', 250, 'farm-1', 'user-1'));
    expect(a.writes.where((w) => w.url.path.endsWith('/adjust')), isEmpty);

    await openAdd(tester);
    await dialogPick(tester, 'What kind of adjustment?', 'Correction');
    await dialogAmount(tester, '40');
    await dialogPick(tester, 'Not linked to an account', 'Main Cash Account');
    await save(tester, 'Save adjustment');
    final adj = a.lastBody('/api/Poultry/cash-accounts/5/adjust');
    expect((adj['amount'], adj['reason']), (40, 'Correction'));
  });

  testWidgets('loan received needs a lender and becomes a loan', (tester) async {
    final a = api();
    await open(tester, CashFlowScreen(session: await sessionFor(a), company: company), size: phone);
    await openAdd(tester);
    await dialogPick(tester, 'What kind of adjustment?', 'Loan received');
    await dialogAmount(tester, '5000');
    expect(find.text('A loan needs a lender before it can be recorded.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Record loan')).onPressed, isNull);
    await tester.enterText(_inDialog(find.byType(TextFormField)).at(1), 'GCB Bank');
    await tester.pump();
    await save(tester, 'Record loan');
    final body = a.lastBody('/api/Poultry/loans');
    expect((body['lenderName'], body['originalPrincipal'], body['amountReceived']), ('GCB Bank', 5000, 5000));
    expect(a.writes.where((w) => w.url.path == '/api/Cash/Adjustment'), isEmpty, reason: 'counted once');
  });

  testWidgets('a withdrawal needs an account and is recorded as an owner draw', (tester) async {
    final a = api();
    await open(tester, CashFlowScreen(session: await sessionFor(a), company: company), size: phone);
    await openAdd(tester);
    await dialogPick(tester, 'What kind of adjustment?', 'Withdrawal');
    await dialogAmount(tester, '300');
    expect(find.textContaining('Say which account the money came out of'), findsOneWidget);
    await dialogPick(tester, 'Not linked to an account', 'Main Cash Account');
    await save(tester, 'Record withdrawal');
    final body = a.lastBody('/api/Poultry/owner-money');
    expect((body['transactionType'], body['amount'], body['poultryCashAccountId'], body['ownerName']), ('Draw', 300, 5, null));
    expect(find.textContaining('taken out of Main Cash Account by the owner'), findsOneWidget);
  });

  testWidgets('edit and delete an adjustment from the table', (tester) async {
    final a = api();
    await open(tester, CashFlowScreen(session: await sessionFor(a), company: company), size: phone);
    await tapSeen(tester, find.text('View table format'));
    final edit = find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Edit this adjustment');
    await see(tester, edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Edit Adjustment'), findsOneWidget);
    expect(_inDialog(find.text('Owner injection')), findsOneWidget, reason: 'type recovered from the label');
    await dialogAmount(tester, '550');
    await save(tester, 'Update adjustment');
    final put = a.lastBody('/api/Cash/Adjustment/31', 'PUT');
    expect((put['Amount'], put['AdjustmentType']), (550, 'OwnerInjection'));

    final del = find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Delete this adjustment');
    await see(tester, del);
    await tester.tap(del);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete adjustment'));
    await tester.pumpAndSettle();
    final d = a.writes.lastWhere((w) => w.method == 'DELETE');
    expect((d.url.path, d.url.queryParameters['farmId']), ('/api/Cash/Adjustment/31', 'farm-1'));
  });

  testWidgets('a period goes to the server; clearing makes it all time', (tester) async {
    final a = api();
    await open(tester, CashFlowScreen(session: await sessionFor(a), company: company), size: phone);
    await choose(tester, 'Last 30 Days', 'This Year');
    expect(a.requests.where((r) => r.url.path == '/api/Poultry/cash-flow').elementAt(3).url.queryParameters['fromDate'],
        '${DateTime.now().year}-01-01');
    await tapSeen(tester, find.textContaining('Clear ('));
    final last = a.requests.lastWhere((r) => r.url.path == '/api/Poultry/cash-flow' && r.url.queryParameters.length == 1);
    expect(last.url.queryParameters, {'farmId': 'farm-1'});
  });
}
