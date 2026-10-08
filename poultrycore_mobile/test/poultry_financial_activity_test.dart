// Poultry → Money → Financial Activity: the filters, the time format, the CSV,
// then the page at phone width — every dropdown, the position detail, export.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/financial_activity_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';

import 'support/harness.dart';

final activity = {
  'summary': {
    'moneyIn': 6000, 'moneyOut': 900, 'netCashFlow': 5100, 'openingCash': 100, 'closingCash': 5200,
    'revenue': 1000, 'expense': 1150, 'netProfit': -150, 'eventCount': 3, 'cashEvents': 2, 'nonCashEvents': 1,
  },
  'rows': [
    {
      'eventKey': 'sale-1', 'occurredAt': '2026-10-01T09:30:00', 'activityType': 'Operating', 'type': 'Sale', 'category': 'Eggs',
      'description': 'Eggs to Ama', 'sourceType': 'Sale', 'sourceId': 1, 'moneyIn': 1000, 'moneyOut': 0, 'revenue': 1000, 'expense': 0,
      'profitImpact': 1000, 'runningCash': 1100, 'isCashActivity': true, 'partyName': 'Ama',
      'positionChanges': [
        {'positionType': 'Cash', 'positionName': 'Main Cash Account', 'increaseAmount': 1000, 'decreaseAmount': 0, 'explanation': 'Paid at the counter'},
      ],
    },
    {
      'eventKey': 'loan-2', 'occurredAt': '2026-10-02T00:00:00', 'createdAt': '2026-10-02T13:05:00Z', 'activityType': 'Financing',
      'type': 'Loan received', 'category': 'Loans', 'description': 'GCB loan', 'sourceType': 'LoanReceived', 'sourceId': 2,
      'moneyIn': 5000, 'moneyOut': 0, 'revenue': 0, 'expense': 0, 'profitImpact': 0, 'runningCash': 6100, 'isCashActivity': true,
      'positionChanges': [],
    },
    {
      'eventKey': 'dep-3', 'occurredAt': '2026-10-03', 'activityType': 'Capital', 'type': 'Depreciation', 'category': 'Assets',
      'description': 'Pen depreciation', 'sourceType': 'AssetDepreciation', 'sourceId': 3, 'moneyIn': 0, 'moneyOut': 0, 'revenue': 0,
      'expense': 1150, 'profitImpact': -1150, 'runningCash': 6100, 'isCashActivity': false, 'isNonCashActivity': true,
      'positionChanges': [
        {'positionType': 'AccumulatedDepreciation', 'positionName': 'Pen 1', 'increaseAmount': 1150, 'decreaseAmount': 0},
      ],
    },
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

Future<void> choose(WidgetTester tester, String shown, String option) async {
  await see(tester, find.text(shown));
  await pick(tester, shown, option);
}

List<Map> get rows => [for (final r in activity['rows'] as List) r as Map];

void main() {
  group('financial activity rules', () {
    test('the time shown: its own, else the entry time on the company clock', () {
      expect(formatActivityMoment('2026-10-01T09:30:00', null, Duration.zero), '10/01/2026 9:30 AM');
      expect(formatActivityMoment('2026-10-02T00:00:00', '2026-10-02T13:05:00Z', Duration.zero), '10/02/2026 1:05 PM');
      expect(formatActivityMoment('2026-10-02T00:00:00', '2026-10-02T13:05:00Z', const Duration(hours: 1)), '10/02/2026 2:05 PM');
      expect(formatActivityMoment('2026-10-03', null, Duration.zero), '10/03/2026');
    });

    test('filters keep cash and profit apart', () {
      expect([for (final r in filterActivity(rows, activity: 'PL')) r['eventKey']], ['sale-1', 'dep-3']);
      expect([for (final r in filterActivity(rows, cash: 'NON')) r['eventKey']], ['dep-3']);
      expect([for (final r in filterActivity(rows, profit: 'NONE')) r['eventKey']], ['loan-2']);
      expect([for (final r in filterActivity(rows, activity: 'Financing')) r['eventKey']], ['loan-2']);
      expect([for (final r in filterActivity(rows, search: 'ama')) r['eventKey']], ['sale-1']);
    });

    test('the CSV: blank for zero, quoted where needed', () {
      final csv = activityCsv(rows.sublist(0, 1), Duration.zero).split('\n');
      expect(csv.first, 'Date,Type,Category,Description,Money In,Money Out,Revenue,Expense,Profit Impact,Running Cash');
      expect(csv[1], '10/01/2026 9:30 AM,Sale,Eggs,Eggs to Ama,1000,,1000,,1000,1100');
      expect(positionLabel('LoanLiability'), 'Loan Liability');
      expect(activitySourceLink(rows[1]), ('/poultry-loans', 'View loan'));
    });
  });

  test('on the sidebar route', () => expect(pageScreens.containsKey('/poultry-financial-activity'), isTrue));

  testWidgets('the seven figures, every filter, the position detail, totals, export', (tester) async {
    final shared = <(String, List<int>)>[];
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add((name, bytes));
    final api = FakeApi()..gets['/api/Poultry/financial-activity'] = activity;
    await open(tester, FinancialActivityScreen(session: await sessionFor(api), company: company), size: phone);
    final q = api.requests.firstWhere((r) => r.url.path == '/api/Poultry/financial-activity').url.queryParameters;
    expect(q['fromDate'], endsWith('-01'), reason: 'this month by default');

    await see(tester, find.text('GHC -150.00'));
    expect(find.text('2 cash · 1 non-cash events'), findsOneWidget);
    expect(find.text('Opening GHC 100.00'), findsOneWidget);

    await see(tester, find.text('Paid at the counter'));
    expect(find.text('Main Cash Account'), findsOneWidget);
    expect(find.text('Party: Ama'), findsOneWidget);
    await see(tester, find.text('This event did not change any tracked financial position.'));

    await choose(tester, 'All activity', 'Capital activity');
    await see(tester, find.text('Pen depreciation'));
    expect(find.text('Eggs to Ama'), findsNothing);
    expect(find.text('Reset filters'), findsOneWidget);
    await choose(tester, 'Capital activity', 'All activity');
    await choose(tester, 'Cash and non-cash', 'Cash movement');
    await choose(tester, 'Any profit impact', 'Positive');
    await see(tester, find.text('Eggs to Ama'));
    expect(find.text('GCB loan'), findsNothing);
    await choose(tester, 'All types', 'Sale');
    await choose(tester, 'All categories', 'Eggs');
    await see(tester, find.text('Reset filters'));
    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();

    await see(tester, find.text('View table format'));
    await tester.tap(find.text('View table format'));
    await tester.pumpAndSettle();
    await see(tester, find.textContaining('Period total'));
    expect(find.text('GHC -150.00'), findsWidgets, reason: 'the profit total');
    await tester.tap(find.text('Loan received'));
    await tester.pumpAndSettle();

    await tester.drag(_list, const Offset(0, 4000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export CSV'));
    await tester.pumpAndSettle();
    expect(shared.single.$1, startsWith('financial-activity-'));
    expect(utf8.decode(shared.single.$2), contains('Pen depreciation'));
  });

  testWidgets('a period goes to the server', (tester) async {
    final api = FakeApi()..gets['/api/Poultry/financial-activity'] = activity;
    await open(tester, FinancialActivityScreen(session: await sessionFor(api), company: company), size: phone);
    await choose(tester, 'This Month', 'Last Month');
    final q = api.requests.lastWhere((r) => r.url.path == '/api/Poultry/financial-activity').url.queryParameters;
    final now = DateTime.now();
    final last = DateTime(now.year, now.month - 1, 1);
    expect(q['fromDate'], '${last.year}-${last.month.toString().padLeft(2, '0')}-01');
  });
}
