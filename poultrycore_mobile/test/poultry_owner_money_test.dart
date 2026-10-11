// Poultry → Money → Owner Money: the filters, the date-time text, then the page
// at phone width — figures, every filter button, both dialogs, reversal.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/owner_money_screen.dart';
import 'package:poultrycore_mobile/pages/shared/business_dates.dart';

import 'support/harness.dart';

final rows = <Map>[
  {
    'poultryOwnerMoneyId': 1, 'transactionNumber': 'OWN-2026-0001', 'transactionDate': '2026-10-01T00:00:00',
    'createdAt': '2026-10-01T09:15:00Z', 'transactionType': 'Contribution', 'amount': 1000, 'poultryCashAccountId': 5,
    'accountName': 'Main Cash', 'paymentMethod': 'MoMo', 'ownerName': 'Kofi', 'referenceNumber': 'MM-77',
    'notes': 'Start-up', 'status': 'Posted', 'source': 'OwnerMoney', 'sourceId': 1,
  },
  {
    'poultryOwnerMoneyId': 2, 'transactionNumber': 'OWD-2026-0001', 'transactionDate': '2026-10-03T00:00:00',
    'transactionType': 'Draw', 'amount': 200, 'poultryCashAccountId': 5, 'accountName': 'Main Cash',
    'paymentMethod': 'Cash', 'ownerName': 'Kofi', 'status': 'Posted', 'source': 'OwnerMoney', 'sourceId': 2,
  },
  {
    'poultryOwnerMoneyId': 0, 'transactionNumber': null, 'transactionDate': '2026-09-20T00:00:00',
    'transactionType': 'Contribution', 'amount': 50, 'poultryCashAccountId': null, 'status': 'Posted',
    'source': 'CashAdjustment', 'sourceId': 7,
  },
  {
    'poultryOwnerMoneyId': 3, 'transactionNumber': 'OWD-2026-0002', 'transactionDate': '2026-10-04T00:00:00',
    'transactionType': 'Draw', 'amount': 80, 'accountName': 'Main Cash', 'status': 'Reversed',
    'reversalReason': 'Typed twice', 'source': 'OwnerMoney', 'sourceId': 3,
  },
];

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-05', 'companyLocalDateTime': '2026-10-05T10:00:00', 'utcNow': '2026-10-05T10:00:00Z',
  }
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 5, 'accountName': 'Main Cash', 'currentBalance': 300, 'isActive': true, 'allowNegativeBalance': false},
    {'poultryCashAccountId': 6, 'accountName': 'Old Till', 'currentBalance': 0, 'isActive': false},
  ]
  ..gets['/api/Poultry/owner-money'] = rows
  ..gets['/api/Poultry/owner-money/summary'] = {
    'totalContributions': 1050, 'totalDraws': 200, 'netFunding': 850, 'periodContributions': 1050, 'periodDraws': 200,
    'contributionCount': 2, 'drawCount': 1,
  };

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

void clearToasts(WidgetTester tester) =>
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

void main() {
  group('owner money rules', () {
    test('type, status, calendar days and the five search keys', () {
      List<Object?> ids(List<Map> l) => [for (final r in l) r['sourceId']];
      expect(ids(filterOwnerMoney(rows, type: 'Draw')), [2, 3]);
      expect(ids(filterOwnerMoney(rows, status: 'Reversed')), [3]);
      expect(ids(filterOwnerMoney(rows, from: '2026-10-01', to: '2026-10-03')), [1, 2]);
      expect(ids(filterOwnerMoney(rows, search: 'mm-77')), [1]);
      expect(ids(filterOwnerMoney(rows, search: 'start')), [1], reason: 'notes are searched');
      expect(ownerNumber(rows[2]), '#7');
    });

    test('date with the entry time, else the date alone', () {
      expect(fmtDateTime('2026-10-01T00:00:00', rows[0], Duration.zero), '1 Oct 2026, 09:15');
      expect(fmtDateTime('2026-10-01T00:00:00', rows[0], const Duration(hours: 1)), '1 Oct 2026, 10:15');
      expect(fmtDateTime('2026-10-03T00:00:00', rows[1], Duration.zero), '3 Oct 2026');
      expect(fmtDateTime('2026-10-03T14:30:00', null, Duration.zero), '3 Oct 2026, 14:30');
    });
  });

  test('on the sidebar route', () => expect(pageScreens.containsKey('/poultry-owner-money'), isTrue));

  testWidgets('figures, cards, filter buttons, Cash-page rows, table', (tester) async {
    final a = api();
    await open(tester, OwnerMoneyScreen(session: await sessionFor(a), company: company), size: phone);

    expect(find.text('GHC 1,050.00'), findsNWidgets(2), reason: 'total and in range');
    expect(find.text('2 record(s)'), findsOneWidget);
    expect(find.text('GHC 850.00'), findsOneWidget);
    await see(tester, find.text('OWN-2026-0001'));
    expect(find.text('1 Oct 2026, 09:15 · Main Cash'), findsOneWidget);
    await see(tester, find.text('Recorded on the Cash page — edit it there.'));
    expect(find.text('#7'), findsOneWidget);
    await see(tester, find.text('Typed twice'));
    expect(find.text('Reverse'), findsNWidgets(2), reason: 'only posted rows recorded here');

    await tap(tester, find.widgetWithText(OutlinedButton, 'Draw'));
    expect(find.text('OWN-2026-0001'), findsNothing);
    expect(find.text('OWD-2026-0001'), findsOneWidget);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Reversed'));
    expect(find.text('OWD-2026-0001'), findsNothing);
    expect(find.text('OWD-2026-0002'), findsOneWidget);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Contribution'));
    expect(find.text('Nothing matches these filters.'), findsOneWidget);
    await tap(tester, find.widgetWithText(OutlinedButton, 'All').first);
    await tap(tester, find.widgetWithText(OutlinedButton, 'All'));
    await see(tester, find.text('#7'));

    await tap(tester, find.text('View table format'));
    await see(tester, find.text('From the Cash page'));
    expect(find.text('Cash page'), findsOneWidget);
    expect(find.text('−GHC 200.00'), findsOneWidget);
    expect(find.text('+GHC 1,000.00'), findsOneWidget);
  });

  testWidgets('record a draw: active accounts only, overdraw blocks, the body sent', (tester) async {
    final a = api();
    await open(tester, OwnerMoneyScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Record draw'));
    expect(find.text('Record Owner Draw'), findsOneWidget);

    await tester.tap(inDialog(find.text('Record Draw')));
    await tester.pumpAndSettle();
    expect(find.text('Pick a cash account'), findsOneWidget);
    clearToasts(tester);

    await tester.ensureVisible(inDialog(find.text('Which account does it leave?')));
    await tester.pumpAndSettle();
    await tester.tap(find.ancestor(of: inDialog(find.text('Which account does it leave?')), matching: find.byType(AppSelect<String>)));
    await tester.pumpAndSettle();
    expect(find.text('Old Till — GHC 0.00'), findsNothing, reason: 'inactive accounts are not offered');
    await tester.tap(find.text('Main Cash — GHC 300.00').last);
    await tester.pumpAndSettle();
    await enter(tester, 'Amount *', '500');
    await tester.pumpAndSettle();
    expect(find.textContaining('The draw will be rejected.'), findsOneWidget);
    expect(find.textContaining('GHC 300.00 → GHC -200.00', findRichText: true), findsOneWidget);
    expect(tester.widget<FilledButton>(inDialog(find.widgetWithText(FilledButton, 'Record Draw'))).onPressed, isNull);

    await enter(tester, 'Amount *', '120');
    await tester.pumpAndSettle();
    expect(find.textContaining('The draw will be rejected.'), findsNothing);
    await pick(tester, 'Cash', 'MoMo');
    await enter(tester, 'Owner', ' Kofi ');
    await enter(tester, 'Reference', 'MM-90');
    final save = inDialog(find.text('Record Draw'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final b = a.lastBody('/api/Poultry/owner-money');
    expect(b['transactionType'], 'Draw');
    expect(b['amount'], 120);
    expect(b['poultryCashAccountId'], 5);
    expect(b['paymentMethod'], 'MoMo');
    expect(b['ownerName'], 'Kofi');
    expect(b['referenceNumber'], 'MM-90');
    expect(b['notes'], isNull);
    expect(b['farmId'], 'farm-1');
    expect(b['createdBy'], 'user-1');
    expect(find.textContaining('Draw recorded'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a contribution says it arrives; reverse needs a reason', (tester) async {
    final a = api();
    await open(tester, OwnerMoneyScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Record contribution'));
    expect(find.text('Record Owner Contribution'), findsOneWidget);
    await tester.ensureVisible(inDialog(find.text('Which account does it arrive in?')));
    await tester.pumpAndSettle();
    await tester.tap(find.ancestor(of: inDialog(find.text('Which account does it arrive in?')), matching: find.byType(AppSelect<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Cash — GHC 300.00').last);
    await tester.pumpAndSettle();
    await enter(tester, 'Amount *', '100');
    await tester.pumpAndSettle();
    expect(find.textContaining('→ GHC 400.00', findRichText: true), findsOneWidget, reason: 'balance after');
    await tester.tap(inDialog(find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(a.writes, isEmpty);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Reverse'));
    expect(find.text('Reverse Owner Money'), findsOneWidget);
    expect(find.text('OWN-2026-0001 · Contribution'), findsOneWidget);
    expect(find.text('GHC 1,000.00 on 1 Oct 2026, 09:15 · Main Cash'), findsOneWidget);
    await enter(tester, 'Reason *', 'no');
    final go = inDialog(find.widgetWithText(FilledButton, 'Reverse'));
    await tester.tap(go);
    await tester.pumpAndSettle();
    expect(find.textContaining('Say why'), findsOneWidget);
    expect(a.writes, isEmpty);
    clearToasts(tester);
    await enter(tester, 'Reason *', 'Was a loan');
    await tester.tap(go);
    await tester.pumpAndSettle();
    final w = a.writes.single;
    expect(w.url.path, '/api/Poultry/owner-money/1/reverse');
    expect(w.url.queryParameters, {'farmId': 'farm-1', 'reversedBy': 'user-1'});
    expect(a.lastBody('/api/Poultry/owner-money/1/reverse'), {'reason': 'Was a loan'});
    expect(find.text('Reversed'), findsWidgets);
    expect(find.textContaining('GHC 1,000.00 put back.'), findsOneWidget);
  });
}
