// Poultry → Reports: the standalone report pages (closings, money, batch,
// feed production, changes), driven against a fake API at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/closing_reports.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/money_reports.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/other_reports.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_format.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_routes.dart';
import 'package:poultrycore_mobile/pages/shared/business_dates.dart';

import 'support/harness.dart';

final _list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

Future<void> _see(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 250, scrollable: _list);
  await tester.pumpAndSettle();
}

final _today = isoDay(DateTime.now());
final _todayT = '${_today}T00:00:00';

void main() {
  setUp(() {
    LookupLoader.clear();
    FarmMoney.clearCache();
  });

  test('every standalone report page has a native route', () {
    for (final href in [
      '/poultry-daily-summary', '/poultry-closing-report-daily', '/poultry-closing-report', '/poultry/reports/cash-accounts',
      '/poultry/reports/money', '/poultry/reports/batch-production-summary', '/poultry-feed-production/reports', '/poultry/reports/changes',
    ]) {
      expect(poultryReportScreens.containsKey(href), isTrue, reason: href);
    }
  });

  test('cash accounts split the ledger at From and share by closing cash', () {
    final rows = cashAccountsForPeriod(
      [
        {'poultryCashAccountId': 1, 'accountName': 'Farm box', 'openingBalance': 100},
        {'poultryCashAccountId': 2, 'accountName': 'Bank', 'openingBalance': 0},
      ],
      [
        {'poultryCashAccountId': 1, 'ledgerBalance': 250, 'lastReconciledAt': '2026-09-30', 'daysSinceReconciled': 2},
      ],
      [
        {'poultryCashAccountId': 1, 'amount': 50, 'transactionDate': '2026-08-31'},
        {'poultryCashAccountId': 1, 'amount': 200, 'transactionDate': '2026-09-05'},
        {'poultryCashAccountId': 1, 'amount': -100, 'transactionDate': '2026-09-06'},
        {'poultryCashAccountId': 2, 'amount': 750, 'transactionDate': '2026-09-07'},
      ],
      '2026-09-01',
      '2026-09-30',
    );
    expect(rows.map((r) => r.accountName), ['Bank', 'Farm box']);
    final farm = rows.last;
    expect((farm.openingBalance, farm.periodIn, farm.periodOut, farm.closingBalance), (150, 200, 100, 250));
    expect(rows.first.sharePercent, 75);
    expect(rows.first.attentionReason, 'Never reconciled');
    expect(farm.needsAttention, isFalse);
  });

  test('changes: action kinds, friendly names, readable fields', () {
    expect([for (final a in ['POST', 'put', 'Delete', 'GET', 'LOGIN']) actionKind(a)], ['Created', 'Updated', 'Deleted', 'Viewed', 'Other']);
    expect(friendlyResource('PoultryCashAccount'), 'Cash Account');
    expect(friendlyResource(null), 'Record');
    final fields = buildFields(
        '{"request":{"sale":{"saleId":0,"farmId":"9f1c2a3b-0000-4000-8000-000000000001","customerName":"Ama","isPaid":true,'
        '"note":"","quantity":5,"createdBy":"x","deletedAt":"0001-01-01T00:00:00"}}}');
    expect(fields, [('Customer Name', 'Ama'), ('Is Paid', 'Yes'), ('Quantity', '5')]);
    expect(buildFields('not json'), isEmpty);
  });

  testWidgets('daily summary: closing figures, expense breakdown, PDF', (tester) async {
    final shared = <String>[];
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add(name);
    final api = FakeApi()
      ..gets['/api/Poultry/daily-closings'] = [
        {'closingDate': _todayT, 'totalIncome': 900, 'cashCollected': 500, 'moMoCollected': 400, 'quantityProduced': 1200,
          'quantityDamaged': 7, 'status': 'Submitted', 'cashDifference': -20, 'mortality': 2},
      ]
      ..gets['/api/Expense'] = [
        {'expenseDate': _todayT, 'category': 'Feed', 'amount': 300},
        {'expenseDate': _todayT, 'category': 'Labour', 'amount': 50},
        {'expenseDate': '2020-01-01T00:00:00', 'category': 'Old', 'amount': 999},
      ]
      ..gets['/api/Poultry/loss-records'] = [
        {'status': 'Approved', 'estimatedValue': 40},
        {'status': 'Pending', 'estimatedValue': 1000},
      ];
    await open(tester, DailyBusinessSummaryScreen(session: await sessionFor(api), company: company), size: phone);
    expect(find.text('GHC 900.00'), findsWidgets, reason: 'total income from the closing');
    await _see(tester, find.text('1,200'));
    expect(find.text('Submitted'), findsOneWidget);
    await _see(tester, find.text('GHC 350.00'));
    expect(find.text('GHC 40.00'), findsOneWidget, reason: 'only the approved loss counts');
    expect(find.text('GHC -20.00'), findsOneWidget);
    expect(find.textContaining('Old'), findsNothing);
    await tester.drag(_list, const Offset(0, 4000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export PDF').first);
    await tester.pumpAndSettle();
    expect(shared.single, endsWith('.pdf'));
  });

  testWidgets('closing report: approved closings in the tiles, every closing in the cards', (tester) async {
    final api = FakeApi()
      ..gets['/api/Poultry/daily-closings'] = [
        {'closingDate': _todayT, 'status': 'Approved', 'totalIncome': 500, 'totalExpenses': 100, 'cashAtHand': 400, 'cashDifference': -5},
        {'closingDate': _todayT, 'status': 'Rejected', 'totalIncome': 9000, 'rejectionReason': 'Count again'},
      ];
    await open(tester, ClosingReportScreen(session: await sessionFor(api), company: company), size: phone);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('CASH DIFFERENCE (1 DAY)'), findsOneWidget);
    expect(find.text('GHC 500.00'), findsWidgets);
    await _see(tester, find.text('Rejected: Count again'));
  });

  testWidgets('closing by category: the four sections read the PascalCase totals', (tester) async {
    final api = FakeApi()
      ..gets['/api/Poultry/closing-report'] = {'TotalSales': 1500, 'NetProfitLoss': -25.5, 'TotalEggsProduced': 4321};
    await open(tester, ClosingByCategoryScreen(session: await sessionFor(api), company: company), size: phone);
    expect(find.text('Financial Summary'), findsOneWidget);
    expect(find.text('GHC 1,500.00'), findsOneWidget);
    expect(find.text('GHC -25.50'), findsOneWidget);
    await _see(tester, find.text('4,321'));
    expect(find.text('—'), findsWidgets, reason: 'a total the API left out');
  });

  testWidgets('cash accounts: balances for the period', (tester) async {
    final api = FakeApi()
      ..gets['/api/Poultry/cash-accounts'] = [
        {'poultryCashAccountId': 1, 'accountName': 'Farm cash box', 'accountType': 'FarmCashBox', 'openingBalance': 100},
      ]
      ..gets['/api/Poultry/cash-accounts/transactions'] = [
        {'poultryCashAccountId': 1, 'amount': 250, 'transactionDate': _todayT, 'description': 'Egg sales'},
      ];
    await open(tester, CashAccountReportScreen(session: await sessionFor(api), company: company), size: phone);
    expect(find.text('Farm cash box'), findsWidgets);
    expect(find.text('GHC 350.00'), findsWidgets, reason: '100 opening + 250 in');
  });

  testWidgets('money movement: live rows count, reversed rows are struck', (tester) async {
    final api = FakeApi()
      ..gets['/api/Poultry/owner-money'] = [
        {'transactionDate': _todayT, 'transactionType': 'Contribution', 'amount': 1000, 'status': 'Posted'},
        {'transactionDate': _todayT, 'transactionType': 'Draw', 'amount': 300, 'status': 'Posted'},
        {'transactionDate': _todayT, 'transactionType': 'Draw', 'amount': 5000, 'status': 'Reversed'},
      ];
    await open(tester, MoneyMovementScreen(session: await sessionFor(api), company: company), size: phone);
    await _see(tester, find.text('Owner money'));
    expect(find.text('GHC 1,000.00'), findsWidgets, reason: 'contributions');
    expect(find.text('GHC 300.00'), findsWidgets, reason: 'draws; the reversed draw is left out');
    expect(find.text('GHC 700.00'), findsOneWidget, reason: 'net funding');
    await _see(tester, find.text('−GHC 5,000.00'));
    final struck = tester.widget<Text>(find.text('−GHC 5,000.00').first);
    expect(struck.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('batch production summary: per-batch roll-up, cards, search, CSV', (tester) async {
    final shared = <String>[];
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add(name);
    final api = FakeApi()
      ..gets['/api/MainFlockBatch'] = [
        {'batchId': 1, 'batchName': 'Batch A', 'batchCode': 'BA', 'breed': 'Lohmann', 'numberOfBirds': 500},
        {'batchId': 2, 'batchName': 'Batch B', 'batchCode': 'BB', 'breed': 'Isa', 'numberOfBirds': 300},
      ]
      ..gets['/api/Flock'] = [
        {'flockId': 10, 'batchId': 1},
        {'flockId': 11, 'batchId': 1},
      ]
      ..gets['/api/ProductionRecord'] = [
        {'flockId': 10, 'date': '2026-09-01T00:00:00', 'totalProduction': 40, 'noOfBirds': 50, 'brokenEggs': 1, 'feedKg': 2.5, 'mortality': 1, 'noOfBirdsLeft': 49},
        {'flockId': 11, 'date': '2026-09-01T00:00:00', 'totalProduction': 25, 'noOfBirds': 50, 'feedKg': 1.25, 'noOfBirdsLeft': 50},
        {'flockId': 10, 'date': '2026-09-02T00:00:00', 'totalProduction': 35, 'noOfBirds': 49, 'feedKg': 2, 'noOfBirdsLeft': 48},
      ];
    await open(tester, BatchProductionSummaryScreen(session: await sessionFor(api), company: company), size: phone);
    expect(find.text('of 2 with production'), findsOneWidget);
    expect(find.text('3c + 10p'), findsOneWidget, reason: '100 eggs');
    expect(find.text('800'), findsWidgets, reason: 'birds placed');
    expect(find.text('5.75'), findsWidgets, reason: 'feed, two decimals');
    await _see(tester, find.text('Batch A'));
    expect(find.text('65'), findsOneWidget, reason: 'peak day = 40 + 25 on 1 Sep');
    expect(find.text('98'), findsNWidgets(2), reason: 'row and totals; current birds: latest per flock, 48 + 50');

    await tester.drag(_list, const Offset(0, 4000));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Search batch, code, breed…'), 'isa');
    await tester.pumpAndSettle();
    expect(find.text('Batch A'), findsNothing);
    expect(find.text('of 1 with production'), findsOneWidget);
    await tester.tap(find.text('CSV').first);
    await tester.pumpAndSettle();
    expect(shared.single, 'poultry-batch-production-summary-all_all.csv');
  });

  testWidgets('feed production: posted batches, costs, then ingredient usage', (tester) async {
    final api = FakeApi()
      ..gets['/api/Poultry/feed-production'] = [
        {'poultryFeedProductionBatchId': 7, 'batchNumber': 'FP-007', 'productionDate': '2026-09-03T00:00:00', 'finishedFeedItemName': 'Layer mash',
          'quantityProduced': 1000, 'outputUnit': 'kg', 'totalIngredientCost': 4000, 'totalAdditionalCost': 500, 'totalProductionCost': 4500,
          'costPerOutputUnit': 4.5},
      ]
      ..gets['/api/Poultry/feed-production/reports/ingredient-usage'] = [
        {'ingredientName': 'Maize', 'totalQuantityUsed': 600, 'unitOfMeasure': 'kg', 'fromInventoryQuantity': 400, 'purchasedQuantity': 200,
          'totalCost': 2400, 'batchCount': 1},
      ];
    await open(tester, FeedProductionReportsScreen(session: await sessionFor(api), company: company), size: phone);
    expect(find.text('GHC 4,500.00'), findsWidgets);
    await _see(tester, find.text('FP-007'));
    expect(find.text('1,000 kg'), findsOneWidget);
    expect(find.text('3 Sep 2026'), findsOneWidget);
    final status = api.requests.firstWhere((r) => r.url.path == '/api/Poultry/feed-production').url.queryParameters['status'];
    expect(status, 'Posted');

    await tester.drag(_list, const Offset(0, 4000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ingredient Usage'));
    await tester.pumpAndSettle();
    expect(find.text('Maize'), findsOneWidget);
    expect(find.text('600 kg'), findsOneWidget);
    expect(find.text('GHC 2,400.00'), findsWidgets);
  });

  testWidgets('changes: views hidden by default, action filter, paging, view dialog, CSV', (tester) async {
    final shared = <String>[];
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add(name);
    final api = FakeApi()
      ..gets['/api/AuditLogs'] = [
        for (var i = 0; i < 16; i++)
          {'id': i, 'action': 'PUT', 'resource': 'PoultryFlock', 'resourceId': '$i', 'userName': 'Kofi',
            'timestamp': '2026-09-${(10 + i).toString().padLeft(2, '0')}T10:00:00Z', 'status': 'Success'},
        {'id': 90, 'action': 'POST', 'resource': 'PoultryCashAccount', 'resourceId': '3', 'userName': 'Ama', 'timestamp': '2026-09-30T08:00:00Z',
          'status': 'Success', 'data': '{"request":{"accountName":"Farm box","isActive":true}}'},
        {'id': 91, 'action': 'GET', 'resource': 'PoultryFlock', 'userName': 'Ama', 'timestamp': '2026-09-30T09:00:00Z', 'status': 'Success'},
      ];
    await open(tester, ChangesReportScreen(session: await sessionFor(api), company: company), size: phone);
    expect(api.requests.firstWhere((r) => r.url.path == '/api/AuditLogs').url.queryParameters['pageSize'], '500');
    await _see(tester, find.text('1–15 of 17'));
    expect(find.text('Viewed'), findsNothing);

    await tester.drag(_list, const Offset(0, 6000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Created').last);
    await tester.pumpAndSettle();
    await _see(tester, find.text('Cash Account #3', findRichText: true));
    expect(find.text('1–1 of 1'), findsOneWidget);
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('Created · Cash Account #3'), findsOneWidget);
    expect(find.text('Account Name'), findsOneWidget);
    expect(find.text('Farm box'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.drag(_list, const Offset(0, 6000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export CSV'));
    await tester.pumpAndSettle();
    expect(shared.single, startsWith('poultry-changes-report-'));
  });
}
