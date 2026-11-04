// Generic → Money at phone width (lib/nav/generic-nav-config.ts "money"):
// Cash & accounts, Cash transfers, Daily closing and Owner money, each against
// a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/generic/generic_kit.dart';
import 'package:poultrycore_mobile/pages/generic/generic_money_screens.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart' show pageScreens;
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final generic = Company(farmId: 'g1', name: 'Kofi Shop', type: CompanyType.generic, role: 'Admin');
const base = '/api/generic-company/g1';

String ghs(String n) => 'GHS $n';

final accounts = [
  {'genericCashAccountId': 1, 'accountName': 'Cash Box', 'accountType': 'Cash', 'openingBalance': 100, 'currentBalance': 300,
    'allowNegativeBalance': false, 'isActive': true},
  {'genericCashAccountId': 2, 'accountName': 'MoMo', 'accountType': 'MobileMoney', 'openingBalance': 0, 'currentBalance': -20,
    'allowNegativeBalance': true, 'isActive': true},
  {'genericCashAccountId': 3, 'accountName': 'Old bank', 'accountType': 'Bank', 'openingBalance': 0, 'currentBalance': 999,
    'allowNegativeBalance': false, 'isActive': false},
];

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-11-04', 'companyLocalDateTime': '2026-11-04T10:00:00', 'utcNow': '2026-11-04T10:00:00Z',
  }
  ..gets['$base/cash-accounts'] = accounts
  ..gets['$base/cash-transfers'] = [
    {'genericCashTransferId': 4, 'fromGenericCashAccountId': 1, 'fromAccountName': 'Cash Box', 'toGenericCashAccountId': 2,
      'transferDate': '2026-11-03T00:00:00', 'amount': 50, 'status': 'Draft', 'notes': 'float'},
  ]
  ..gets['$base/daily-closings'] = [
    {'genericDailyClosingId': 6, 'closingDate': '2026-11-03T00:00:00', 'totalSales': 400, 'totalExpenses': 50, 'expectedCash': 350,
      'actualCashCounted': 340, 'cashDifference': -10, 'status': 'Submitted', 'managerNotes': 'short'},
    {'genericDailyClosingId': 5, 'closingDate': '2026-11-02T00:00:00', 'totalSales': 0, 'totalExpenses': 0, 'expectedCash': 0,
      'actualCashCounted': 0, 'cashDifference': 0, 'status': 'Draft'},
  ]
  ..gets['$base/owner-entries'] = [
    {'genericOwnerEntryId': 1, 'entryType': 'Contribution', 'amount': 1000, 'entryDate': '2026-11-01T00:00:00', 'status': 'Posted',
      'ownerName': 'Kofi', 'cashAccountName': 'Cash Box', 'paymentMethod': 'Bank', 'referenceNo': 'OM-1'},
    {'genericOwnerEntryId': 2, 'entryType': 'Draw', 'amount': 200, 'entryDate': '2026-11-02T00:00:00', 'status': 'Posted'},
    {'genericOwnerEntryId': 3, 'entryType': 'Draw', 'amount': 500, 'entryDate': '2026-11-02T00:00:00', 'status': 'Reversed'},
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

Future<void> enterIn(WidgetTester tester, String label, String text) async {
  final field = find.descendant(of: find.ancestor(of: inDialog(find.text(label)), matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.ensureVisible(field.first);
  await tester.enterText(field.first, text);
  await tester.pump();
}

void clearToasts(WidgetTester tester) => tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

void main() {
  tearDown(invalidateGenericModules);

  testWidgets('the Money menu: web order, native screens, the cash-accounts switch', (tester) async {
    final groups = webNavGroups['generic']!;
    final m = groups.firstWhere((g) => g.title == 'Money');
    const hrefs = ['/generic-cash', '/generic-cash-transfers', '/generic-daily-closings', '/generic-owner-money'];
    expect([for (final l in m.subGroups.single.links) l.href], hrefs);
    expect(groups.indexOf(m), groups.indexWhere((g) => g.title == 'Purchasing') + 1);
    expect(groups.where((g) => g.title == 'Sales & Money'), isEmpty, reason: 'its rows all moved to Money');
    final elsewhere = [for (final g in groups) if (g != m) for (final s in g.subGroups) for (final l in s.links) l.href];
    for (final h in hrefs) {
      expect(elsewhere, isNot(contains(h)));
      expect(pageScreens[h], isNotNull, reason: h);
    }
    final a = FakeApi()..gets['$base/module-settings'] = {for (final k in genericModuleKeys) k: true, 'enableCashAccounts': false};
    await tester.runAsync(() async => loadGenericModules(await sessionFor(a), generic));
    final gated = gateGenericCatalog(groups, generic).firstWhere((g) => g.title == 'Money').subGroups.single.links.map((l) => l.href);
    expect(gated, ['/generic-daily-closings', '/generic-owner-money']);
  });

  test('owner totals leave reversed entries out; filters', () {
    final rows = [for (final r in api().gets['$base/owner-entries']! as List) r as Map];
    final t = genericOwnerTotals(rows);
    expect((t.inSum, t.outSum, t.net), (1000, 200, 800));
    expect([for (final r in genericListFilter(rows, const ['ownerName', 'referenceNo', 'notes', 'cashAccountName'], search: 'om-1')) r['genericOwnerEntryId']], [1]);
  });

  testWidgets('Cash & accounts: the active total, badges, negative balance', (tester) async {
    await open(tester, GenericCashScreen(session: await sessionFor(api()), company: generic), size: phone);
    expect(find.text(ghs('280.00')), findsOneWidget, reason: '300 + (−20); the inactive account is left out');
    expect(find.text('across 2 active account(s)'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    await see(tester, find.text('-${ghs('20.00')}'));
    expect(find.text('Yes'), findsOneWidget);
  });

  testWidgets('Cash transfers: checks, the body, approve and cancel', (tester) async {
    final a = api()..writeAnswers['$base/cash-transfers'] = {'genericCashTransferId': 7};
    await open(tester, GenericCashTransfersScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.text('#4 · Cash Box → #2'), findsOneWidget, reason: 'a missing name falls back to the id');

    await tap(tester, find.text('New transfer'));
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pick both accounts'), findsOneWidget);
    clearToasts(tester);
    await choose(tester, inDialog(selectShowing('Source...')), 'Cash Box – ${ghs('300.00')}');
    await tapIn(tester, inDialog(selectShowing('Destination...')));
    expect(find.text('Old bank'), findsNothing, reason: 'inactive accounts are not offered');
    await tester.tap(find.text('MoMo').last);
    await tester.pumpAndSettle();
    await tapIn(tester, find.widgetWithText(FilledButton, 'Create'));
    expect(find.textContaining('Amount must be greater than zero'), findsOneWidget);
    clearToasts(tester);
    await enterIn(tester, 'Amount *', '75');
    await tapIn(tester, find.widgetWithText(FilledButton, 'Create'));
    final b = a.lastBody('$base/cash-transfers');
    expect((b['fromGenericCashAccountId'], b['toGenericCashAccountId'], b['amount'], b['notes'], b['farmId']), (1, 2, 75, null, 'g1'));
    expect(find.textContaining('Transfer created as Draft. Approve to move the cash.'), findsOneWidget);
    clearToasts(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Approve'));
    expect(a.writes.last.url.path, '$base/cash-transfers/4/approve');
    clearToasts(tester);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Cancel'));
    expect(a.writes.last.url.path, '$base/cash-transfers/4/cancel');
  });

  testWidgets('Daily closing: create & submit, approve with its confirm, refresh, submit a draft', (tester) async {
    final a = api()..writeAnswers['$base/daily-closings'] = {'genericDailyClosingId': 8};
    await open(tester, GenericDailyClosingsScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.text('2 closing(s) — totals are auto-aggregated; you just count cash.'), findsOneWidget);
    expect(find.text('Sales ${ghs('400.00')} · Exp ${ghs('50.00')}'), findsOneWidget);

    await tap(tester, find.text('Close today'));
    await enterIn(tester, 'Actual cash counted *', '340');
    await choose(tester, inDialog(selectShowing('Select a reason')), 'Miscount');
    await tapIn(tester, find.text('Create & submit'));
    final b = a.lastBody('$base/daily-closings');
    expect((b['openingCash'], b['actualCashCounted'], b['differenceReason'], b['managerNotes'], b['farmId']), (null, 340, 'Miscount', null, 'g1'));
    expect(a.writes.last.url.path, '$base/daily-closings/8/submit');
    expect(find.textContaining('Closing #8 created and submitted.'), findsOneWidget);
    clearToasts(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Approve'));
    expect(find.text('Approve and lock?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(a.writes.last.url.path, '$base/daily-closings/6/approve');
    clearToasts(tester);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Refresh'));
    expect(a.writes.last.url.path, '$base/daily-closings/6/submit');
    clearToasts(tester);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Submit'));
    expect(a.writes.last.url.path, '$base/daily-closings/5/submit');
  });

  testWidgets('Owner money: totals, the type filter, record, reverse with a reason', (tester) async {
    final a = api()..writeAnswers['$base/owner-entries'] = {'entryId': 9};
    await open(tester, GenericOwnerMoneyScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.textContaining('put in ·'), findsOneWidget);
    expect(find.text('Money in'), findsOneWidget);
    expect(find.text('Reversed'), findsOneWidget);
    await choose(tester, selectShowing('All'), 'Contribution');
    expect(find.text('Money out'), findsNothing);
    await choose(tester, selectShowing('Contribution'), 'All');

    await tap(tester, find.text('Record'));
    await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Record')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pick a cash account'), findsOneWidget);
    clearToasts(tester);
    await choose(tester, inDialog(selectShowing('Contribution — the owner put money in')), 'Draw — the owner took money out');
    await enterIn(tester, 'Amount *', '150');
    await choose(tester, inDialog(selectShowing('Pick one')), 'Cash Box');
    expect(find.text('Old bank'), findsNothing);
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Record')));
    final b = a.lastBody('$base/owner-entries');
    expect((b['entryType'], b['amount'], b['cashAccountId'], b['paymentMethod'], b['entryDate'], b['ownerName']),
        ('Draw', 150, 1, 'Bank', '2026-11-04T00:00:00Z', null));
    expect(find.textContaining('Draw recorded.'), findsOneWidget);
    clearToasts(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Reverse'));
    expect(find.textContaining('put in. The cash movement is undone'), findsOneWidget);
    await tester.tap(find.text('Reverse it'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A reason is required to reverse'), findsOneWidget);
    clearToasts(tester);
    await choose(tester, inDialog(selectShowing('Select a reason')), 'Wrong amount');
    await tester.tap(find.text('Reverse it'));
    await tester.pumpAndSettle();
    expect(a.writes.last.url.path, '$base/owner-entries/1/reverse');
    expect(jsonDecode(a.writes.last.body), {'reason': 'Wrong amount', 'farmId': 'g1'});
  });
}
