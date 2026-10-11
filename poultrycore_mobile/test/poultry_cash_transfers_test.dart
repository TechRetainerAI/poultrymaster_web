// Poultry → Money → Cash Transfers: the filters and figures, then the page at
// phone width — status buttons, table, Record transfer, Reverse.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/cash_transfers_screen.dart';

import 'support/harness.dart';

String _today() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

List<Map> rows() => [
      {
        'poultryCashTransferId': 1, 'transferNumber': 'TRF-0001', 'transferDate': '${_today()}T00:00:00', 'createdAt': '${_today()}T09:05:00Z',
        'fromAccountName': 'Main Cash', 'toAccountName': 'GCB Bank', 'amount': 500, 'referenceNumber': 'DEP-1', 'notes': 'Bank deposit',
        'createdBy': 'Ama', 'status': 'Approved',
      },
      {
        'poultryCashTransferId': 2, 'transferNumber': 'TRF-0002', 'transferDate': '2025-01-10T00:00:00', 'fromAccountName': 'GCB Bank',
        'toAccountName': 'MoMo', 'amount': 200, 'status': 'Approved',
      },
      {
        'poultryCashTransferId': 3, 'transferNumber': null, 'transferDate': '2025-01-11T00:00:00', 'fromAccountName': 'Main Cash',
        'toAccountName': 'MoMo', 'amount': 70, 'status': 'Reversed', 'reversalReason': 'Wrong account',
      },
      {'poultryCashTransferId': 4, 'transferNumber': 'TRF-0004', 'transferDate': '2025-01-12T00:00:00', 'amount': 10, 'status': 'Draft'},
    ];

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': _today(), 'companyLocalDateTime': '${_today()}T10:00:00', 'utcNow': '${_today()}T10:00:00Z',
  }
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 5, 'accountName': 'Main Cash', 'currentBalance': 300, 'isActive': true, 'allowNegativeBalance': false},
    {'poultryCashAccountId': 6, 'accountName': 'GCB Bank', 'currentBalance': 1000, 'isActive': true, 'allowNegativeBalance': false},
    {'poultryCashAccountId': 7, 'accountName': 'Old Box', 'currentBalance': 0, 'isActive': false},
  ]
  ..gets['/api/Poultry/cash-transfers'] = rows()
  ..writeAnswers['/api/Poultry/cash-transfers'] = {'poultryCashTransferId': 9};

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

Future<void> choose(WidgetTester tester, String shown, String option) async {
  await tapIn(tester, find.ancestor(of: inDialog(find.text(shown)), matching: find.byType(AppSelect<String>)));
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> enterIn(WidgetTester tester, String label, String text) async {
  final field = find.descendant(
    of: find.ancestor(of: inDialog(find.text(label)), matching: find.byType(Column)).first,
    matching: find.byType(TextFormField),
  );
  await tester.enterText(field.first, text);
  await tester.pump();
}

void clearToasts(WidgetTester tester) =>
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

void main() {
  group('transfer rules', () {
    test('status, calendar days and the five search keys', () {
      List<Object?> ids(List<Map> l) => [for (final r in l) r['poultryCashTransferId']];
      expect(ids(filterTransfers(rows(), status: 'Approved')), [1, 2]);
      expect(ids(filterTransfers(rows(), from: '2025-01-11', to: '2025-01-12')), [3, 4]);
      expect(ids(filterTransfers(rows(), search: 'dep-1')), [1]);
      expect(ids(filterTransfers(rows(), search: 'momo')), [2, 3]);
      expect(transferNumber(rows()[2]), '#3');
    });

    test('only approved transfers count as moved; busiest accounts by amount', () {
      final s = transferStats(rows());
      expect(s.today, 500);
      expect(s.todayCount, 1);
      expect(s.approved, 2);
      expect(s.topFrom, ('Main Cash', 500));
      expect(s.topTo, ('GCB Bank', 500));
    });
  });

  test('on the sidebar route', () => expect(pageScreens.containsKey('/poultry-cash-transfers'), isTrue));

  testWidgets('figures, cards, status buttons, table', (tester) async {
    await open(tester, CashTransfersScreen(session: await sessionFor(api()), company: company), size: phone);

    expect(find.text('4'), findsOneWidget, reason: 'transfers on record');
    expect(find.text('2 approved'), findsOneWidget);
    expect(find.text('Main Cash'), findsOneWidget, reason: 'most used source');
    await see(tester, find.text('TRF-0001'));
    expect(find.textContaining('09:05 · Main Cash → GCB Bank'), findsOneWidget);
    await see(tester, find.text('Ama'));
    await see(tester, find.text('Wrong account'));
    expect(find.text('Reverse'), findsNWidgets(2), reason: 'approved transfers only');

    await tap(tester, find.widgetWithText(OutlinedButton, 'Reversed'));
    expect(find.text('TRF-0001'), findsNothing);
    await see(tester, find.text('#3'));
    await tap(tester, find.widgetWithText(OutlinedButton, 'Cancelled'));
    expect(find.text('No transfers match these filters.'), findsOneWidget);
    await tap(tester, find.widgetWithText(OutlinedButton, 'All'));

    await tap(tester, find.text('View table format'));
    await see(tester, find.text('Recorded by'));
    expect(find.text('DEP-1'), findsOneWidget);
  });

  testWidgets('Record transfer: checks, To leaves out From, preview, overdraw, body', (tester) async {
    final a = api();
    await open(tester, CashTransfersScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Record transfer'));
    final save = inDialog(find.widgetWithText(FilledButton, 'Record Transfer'));

    await tapIn(tester, save);
    expect(find.textContaining('Pick both accounts'), findsOneWidget);
    clearToasts(tester);
    await choose(tester, 'Pick the account the money leaves', 'Main Cash — GHC 300.00');
    await tapIn(tester, find.ancestor(of: inDialog(find.text('Pick the account the money arrives in')), matching: find.byType(AppSelect<String>)));
    expect(find.text('Main Cash — GHC 300.00'), findsOneWidget, reason: 'the source is not offered as the destination');
    expect(find.text('Old Box — GHC 0.00'), findsNothing, reason: 'inactive accounts are not offered');
    await tester.tap(find.text('GCB Bank — GHC 1,000.00').last);
    await tester.pumpAndSettle();
    await tapIn(tester, save);
    expect(find.textContaining('Enter an amount'), findsOneWidget);
    clearToasts(tester);

    await enterIn(tester, 'Amount *', '400');
    await tester.pumpAndSettle();
    expect(find.textContaining('GHC 300.00 → GHC -100.00', findRichText: true), findsOneWidget);
    expect(find.textContaining('GHC 1,000.00 → GHC 1,400.00', findRichText: true), findsOneWidget);
    expect(find.textContaining('The transfer will be rejected.'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await enterIn(tester, 'Amount *', '250');
    await enterIn(tester, 'Reference', 'DEP-9');
    await tester.pumpAndSettle();
    await tapIn(tester, save);
    final b = a.lastBody('/api/Poultry/cash-transfers');
    expect(b['fromPoultryCashAccountId'], 5);
    expect(b['toPoultryCashAccountId'], 6);
    expect(b['amount'], 250);
    expect(b['referenceNumber'], 'DEP-9');
    expect(b['notes'], isNull);
    expect(b['transferDate'], startsWith(_today()));
    expect(a.writes.last.url.path, '/api/Poultry/cash-transfers/9/approve');
    expect(find.textContaining('Transfer recorded'), findsOneWidget);
  });

  testWidgets('Reverse a transfer needs a reason', (tester) async {
    final a = api();
    await open(tester, CashTransfersScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Reverse'));
    expect(find.text('Reverse Transfer'), findsWidgets);
    expect(find.textContaining('GHC 500.00 comes back out of GCB Bank and returns to Main Cash.'), findsOneWidget);
    final go = inDialog(find.widgetWithText(FilledButton, 'Reverse Transfer'));
    await tapIn(tester, go);
    expect(find.textContaining('Say why'), findsOneWidget);
    clearToasts(tester);
    await enterIn(tester, 'Reason *', 'Typed twice');
    await tapIn(tester, go);
    final w = a.writes.single;
    expect(w.url.path, '/api/Poultry/cash-transfers/1/reverse');
    expect(w.url.queryParameters, {'farmId': 'farm-1', 'reversedBy': 'user-1'});
    expect(a.lastBody('/api/Poultry/cash-transfers/1/reverse'), {'reason': 'Typed twice'});
    expect(find.textContaining('GHC 500.00 put back on Main Cash.'), findsOneWidget);
  });
}
