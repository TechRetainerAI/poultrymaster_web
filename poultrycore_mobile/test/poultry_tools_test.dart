// Poultry → Tools, driven against a fake API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/poultry/days_of_supply_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/farm_completeness_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/feed_distribution_screen.dart';

import 'support/harness.dart';

Map<String, dynamic> supplyRow(int id, String name, String status, int rank, {num? days, num stock = 100}) => {
      'poultryRawMaterialItemId': id, 'itemName': name, 'category': 'FeedIngredient', 'unitOfMeasure': 'kg',
      'purchaseUnitOfMeasure': 'Bag', 'unitsPerPurchaseUnit': 50, 'currentQuantity': stock,
      'belowReorder': status == 'Critical', 'businessDate': '2026-10-02', 'windowFrom': '2026-09-25',
      'windowTo': '2026-10-01', 'lookbackDays': 7, 'windowDays': 7, 'consumedQty': 70, 'usageDays': 7,
      'avgDailyUsage': 10, 'daysOfSupply': days, 'estimatedStockout': '2026-10-05', 'status': status,
      'severityRank': rank, 'criticalDays': 3, 'warningDays': 7, 'expectedDailyUsage': null,
    };

void main() {
  setUp(LookupLoader.clear);

  group('Days of Supply', () {
    testWidgets('worst first, the web wording, idle items hidden until asked for', (tester) async {
      final api = FakeApi()
        ..gets['/api/Poultry/stock-supply'] = [
          supplyRow(2, 'Maize', 'Healthy', 5, days: 20),
          supplyRow(1, 'Soya', 'Critical', 1, days: 2.5, stock: 25),
          {...supplyRow(3, 'Salt', 'NoRecentUsage', 7), 'consumedQty': 0},
        ];
      await open(tester, DaysOfSupplyScreen(session: await sessionFor(api), company: company));

      expect(find.text('1 needs attention · 3 items'), findsOneWidget);
      final soya = tester.getTopLeft(find.text('Soya'));
      final maize = tester.getTopLeft(find.text('Maize'));
      expect(soya.dy < maize.dy, isTrue, reason: 'sorted by severity');
      expect(find.text('2.5 days remaining'), findsOneWidget);
      expect(find.text('Estimated stock-out: Oct 5'), findsWidgets);
      expect(find.text('≈ 0.5 Bag'), findsOneWidget, reason: '25 kg at 50 kg a bag');
      expect(find.text('At or below reorder level'), findsOneWidget);
      expect(find.text('Salt'), findsNothing);

      await tester.tap(find.text('Show 1 item with no recent usage'));
      await tester.pumpAndSettle();
      expect(find.text('Salt'), findsOneWidget);
      expect(find.text('Nothing used from Sep 25 to Oct 1.'), findsOneWidget);
    });

    testWidgets('average over 14 days refetches; warning levels save', (tester) async {
      final api = FakeApi()
        ..gets['/api/Poultry/stock-supply'] = [supplyRow(1, 'Soya', 'Warning', 3, days: 5)]
        ..gets['/api/Poultry/stock-supply/settings'] = {
          'lookbackDays': 7, 'criticalDays': 3, 'warningDays': 7, 'minHistoryDays': 3,
        };
      await open(tester, DaysOfSupplyScreen(session: await sessionFor(api), company: company));

      await tester.tap(find.text('14 days'));
      await tester.pumpAndSettle();
      expect(api.requests.last.url.queryParameters['lookbackDays'], '14');

      await tester.tap(find.text('Warning levels'));
      await tester.pumpAndSettle();
      expect(find.text('Stock warning levels'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(1), '10');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/stock-supply/settings', 'PUT');
      expect(body['warningDays'], 10);
      expect(body['criticalDays'], 3);
      expect(find.text('Stock warning levels saved'), findsOneWidget);
    });
  });

  group('Farm Completeness', () {
    Map<String, dynamic> report(String date, {int missing = 1, int backlog = 0}) => {
          'businessDate': '${date}T00:00:00', 'companyToday': '2026-10-02T00:00:00',
          'checks': [
            {
              'key': 'poultry.production.daily', 'status': 'Incomplete', 'severity': missing > 0 ? 'Warning' : null,
              'expectedCount': 4, 'completedCount': 4 - missing, 'outstandingCount': missing,
              'counters': {'backlogDates': backlog, 'backlogFlockDays': backlog * 2, 'awaitingPosting': 0},
              'items': [
                if (missing > 0)
                  {
                    'subjectType': 'flock', 'subjectId': 7, 'label': 'Flock A', 'groupLabel': 'B-001',
                    'locationLabel': 'Pen 1', 'state': 'Missing', 'severity': 'Warning',
                    'lastCompletedDate': '2026-09-30T00:00:00', 'daysOutstanding': 2,
                  },
              ],
            },
          ],
        };

    testWidgets('today: headline, missing flock, its missing days, by-date view', (tester) async {
      final api = FakeApi()
        ..gets['/api/ActivityChecks'] = report('2026-10-02')
        ..gets['/api/ActivityChecks/production/missing-dates'] = {
          'businessDate': '2026-10-02', 'windowDays': 30,
          'dates': [{'date': '2026-10-01T00:00:00', 'pendingBatchRecordId': null}],
        }
        ..gets['/api/ActivityChecks/production/missing-by-date'] = {
          'businessDate': '2026-10-02', 'windowDays': 30,
          'entries': [
            {'date': '2026-10-01T00:00:00', 'flockId': 7, 'flockName': 'Flock A', 'batchName': 'B-001', 'houseName': 'Pen 1'},
          ],
        };
      await open(tester, FarmCompletenessScreen(session: await sessionFor(api), company: company));

      expect(find.text("TODAY'S FARM COMPLETENESS"), findsOneWidget);
      expect(find.textContaining('3 / 4 recorded', findRichText: true), findsOneWidget);
      expect(find.text('Record 2 days'), findsOneWidget);
      expect(find.text('Next day'), findsNothing);

      await tester.tap(find.text('Flock A'));
      await tester.pumpAndSettle();
      expect(find.text('↳ Thu, Oct 1'), findsOneWidget);
      expect(find.text('1 missing day in the last 30 days.'), findsOneWidget);

      await tester.tap(find.text('By date'));
      await tester.pumpAndSettle();
      expect(find.text('Record batch (1)'), findsOneWidget);
    });

    testWidgets('the previous day is asked for by date; today is left to the server', (tester) async {
      final api = FakeApi()..gets['/api/ActivityChecks'] = report('2026-10-02', missing: 0);
      await open(tester, FarmCompletenessScreen(session: await sessionFor(api), company: company));
      expect(api.requests.last.url.queryParameters.containsKey('businessDate'), isFalse);
      expect(find.text('✓ All expected flock production has been recorded.'), findsOneWidget);

      api.gets['/api/ActivityChecks'] = report('2026-10-01', missing: 0);
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      expect(api.requests.last.url.queryParameters['businessDate'], '2026-10-01');
      expect(find.text('FARM COMPLETENESS — OCT 1'), findsOneWidget);
      expect(find.text('Today'), findsWidgets);
    });
  });

  group('Distribute Feed', () {
    FakeApi feedApi() => FakeApi()
      ..gets['/api/CompanyTime/context'] = {'businessDate': '2026-10-02'}
      ..gets['/api/Poultry/raw-material-items'] = [
        {'poultryRawMaterialItemId': 5, 'itemName': 'Layer Mash', 'category': 'FinishedFeed', 'isActive': true},
        {'poultryRawMaterialItemId': 6, 'itemName': 'Maize', 'category': 'FeedIngredient', 'isActive': true},
        {'poultryRawMaterialItemId': 7, 'itemName': 'Old Mash', 'category': 'FinishedFeed', 'isActive': false},
      ]
      ..gets['/api/Poultry/feed-distributions/availability'] = {
        'itemId': 5, 'itemName': 'Layer Mash', 'availableKg': 100, 'lotCount': 2, 'usageMethod': 'FIFO',
        'gramsPerBirdPerDay': 112.5, 'rateUnit': 'g_bird', 'costRecognitionMethod': 'EXPENSE_WHEN_CONSUMED',
      }
      ..gets['/api/Poultry/feed-distributions/candidates'] = [
        {'flockId': 1, 'flockName': 'Flock A', 'houseName': 'Pen 1', 'birds': 400, 'recordCount': 1,
          'thisItemKg': 0, 'manualFeedKg': 0, 'recentAvgKg': 40, 'recentAvgDays': 7},
        {'flockId': 2, 'flockName': 'Flock B', 'houseName': 'Pen 2', 'birds': 200, 'recordCount': 0},
        {'flockId': 3, 'flockName': 'Flock C', 'houseName': 'Pen 3', 'birds': 100, 'recordCount': 2},
      ];

    testWidgets('only active finished feed is offered; rate converts by unit; fill and post', (tester) async {
      final api = feedApi();
      await open(tester, FeedDistributionScreen(session: await sessionFor(api), company: company));

      await tester.tap(find.text('Choose feed'));
      await tester.pumpAndSettle();
      expect(find.text('Maize'), findsNothing, reason: 'an ingredient, not finished feed');
      expect(find.text('Old Mash'), findsNothing, reason: 'inactive');
      await tester.tap(find.text('Layer Mash').last);
      await tester.pumpAndSettle();

      final cands = api.requests.lastWhere((r) => r.url.path.endsWith('/candidates'));
      expect(cands.url.queryParameters['businessDate'], '2026-10-02');
      expect(find.text('2 stock lots · FIFO'), findsOneWidget);
      expect(find.text('Suggested feed: 45 kg'), findsOneWidget, reason: '400 birds × 112.5 g');
      expect(find.text('record it first'), findsOneWidget);
      expect(find.text('fix the duplicate'), findsOneWidget);

      await pick(tester, 'g per bird per day', 'kg per 100 birds per day');
      expect(find.widgetWithText(TextFormField, '11.25'), findsOneWidget);
      expect(find.text('Suggested feed: 45 kg'), findsOneWidget, reason: 'same physical rate');

      await tester.tap(find.text('Recent average (7 days)'));
      await tester.pumpAndSettle();
      expect(find.text('Suggested feed: 40 kg (avg of 7 days)'), findsOneWidget);

      await tester.tap(find.text('Fill Actual from suggestions'));
      await tester.pumpAndSettle();
      expect(find.text('40 kg to 1 of 1 flocks · 60 kg left'), findsOneWidget);

      await tester.tap(find.text('Post Feed Distribution'));
      await tester.pumpAndSettle();
      expect(find.text('Post feed distribution?'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'e.g. Morning feeding'), 'Morning');
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();

      final body = api.lastBody('/api/Poultry/feed-distributions');
      expect(body['itemId'], 5);
      expect(body['businessDate'], '2026-10-02');
      expect(body['basis'], 'RecentAverage');
      expect(body['gramsPerBirdPerDay'], isNull);
      expect(body['notes'], 'Morning');
      expect(body['lines'], [
        {'flockId': 1, 'actualKg': 40, 'suggestedKg': 40, 'birds': 400, 'notes': null},
      ]);
      expect(find.textContaining('Posted: 40 kg of Layer Mash to 1 flock'), findsOneWidget);
    });

    testWidgets('over-stock and bad numbers block posting; manual amounts post as Manual', (tester) async {
      final api = feedApi();
      await open(tester, FeedDistributionScreen(session: await sessionFor(api), company: company));
      await pick(tester, 'Choose feed', 'Layer Mash');

      // Flock A's Actual box (the rate box above it shares the '0' hint).
      final actual = find.byKey(const ValueKey('actual-1'));
      await tester.enterText(actual, '150');
      await tester.pump();
      expect(find.text('Not enough feed: 50 kg more than is in stock. Stock cannot go negative.'), findsOneWidget);
      final post = find.widgetWithText(FilledButton, 'Post Feed Distribution');
      expect(tester.widget<FilledButton>(post).onPressed, isNull);

      await tester.enterText(actual, '30');
      await tester.pump();
      expect(tester.widget<FilledButton>(post).onPressed, isNotNull);
    });

    testWidgets('a 409 says not enough feed; history reverses with a reason', (tester) async {
      final api = feedApi()
        ..writeStatuses['/api/Poultry/feed-distributions'] = 409
        ..gets['/api/Poultry/feed-distributions'] = [
          {'poultryFeedDistributionId': 9, 'businessDate': '2026-10-01T00:00:00', 'itemName': 'Layer Mash',
            'flockCount': 2, 'totalActualKg': 80, 'totalCost': 120, 'status': 'Posted', 'basis': 'Rate',
            'gramsPerBirdPerDay': 112.5, 'rateUnit': 'g_bird', 'postedBy': 'ama'},
        ]
        ..gets['/api/Poultry/feed-distributions/9/lines'] = [
          {'flockName': 'Flock A', 'actualKg': 45, 'suggestedKg': 45},
        ];
      await open(tester, FeedDistributionScreen(session: await sessionFor(api), company: company));
      await pick(tester, 'Choose feed', 'Layer Mash');
      await tester.tap(find.text('Fill Actual from suggestions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post Feed Distribution'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Not enough feed.'), findsOneWidget);

      await tester.tap(find.text('Posted distributions'));
      await tester.pumpAndSettle();
      expect(find.text('October 1, 2026'), findsOneWidget);
      await tester.tap(find.text('October 1, 2026'));
      await tester.pumpAndSettle();
      expect(find.textContaining('suggested by rate 112.5 g per bird per day'), findsOneWidget);
      expect(find.text('Flock A — 45 kg (suggested 45 kg)'), findsOneWidget);

      await tester.tap(find.text('Reverse'));
      await tester.pumpAndSettle();
      expect(find.text('Reverse this feed distribution?'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, 'Reverse');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull, reason: 'a reason is required');
      await tester.enterText(find.byType(TextField).last, 'Wrong pen');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(api.lastBody('/api/Poultry/feed-distributions/9/reversal'), {'farmId': 'farm-1', 'reason': 'Wrong pen'});
    });
  });

  // The reported overflow (days_of_supply_screen.dart:192) only shows on a
  // phone: every Tools screen is laid out at 360 px wide too. An overflow
  // fails the test.
  group('on a phone', () {
    testWidgets('Days of Supply', (tester) async {
      final api = FakeApi()
        ..gets['/api/Poultry/stock-supply'] = [
          {...supplyRow(1, 'Soya bean meal (high protein)', 'Critical', 1, days: 2.5), 'expectedDailyUsage': 9},
        ];
      await open(tester, DaysOfSupplyScreen(session: await sessionFor(api), company: company), size: phone);
      expect(find.text('Warning levels'), findsOneWidget);
      expect(find.text('Expected (feed rate)'), findsOneWidget);
    });

    testWidgets('Farm Completeness', (tester) async {
      final api = FakeApi()
        ..gets['/api/ActivityChecks'] = {
          'businessDate': '2026-10-01T00:00:00', 'companyToday': '2026-10-02T00:00:00', 'checks': [],
        };
      await open(tester, FarmCompletenessScreen(session: await sessionFor(api), company: company, initialDate: '2026-10-01'),
          size: phone);
      expect(find.byTooltip('Next day'), findsOneWidget);
    });

    testWidgets('Distribute Feed', (tester) async {
      final api = FakeApi()
        ..gets['/api/CompanyTime/context'] = {'businessDate': '2026-10-02'}
        ..gets['/api/Poultry/raw-material-items'] = [
          {'poultryRawMaterialItemId': 5, 'itemName': 'Layer Mash', 'category': 'FinishedFeed', 'isActive': true},
        ]
        ..gets['/api/Poultry/feed-distributions/availability'] = {
          'itemId': 5, 'itemName': 'Layer Mash', 'availableKg': 100, 'lotCount': 1, 'usageMethod': 'FIFO',
          'gramsPerBirdPerDay': null, 'rateUnit': null,
        }
        ..gets['/api/Poultry/feed-distributions/candidates'] = [
          {'flockId': 1, 'flockName': 'Flock A', 'houseName': 'Pen 1', 'birds': 400, 'recordCount': 1,
            'manualFeedKg': 12, 'thisItemKg': 3},
          {'flockId': 2, 'flockName': 'Flock B', 'houseName': 'Pen 2', 'birds': 200, 'recordCount': 2},
        ];
      await open(tester, FeedDistributionScreen(session: await sessionFor(api), company: company), size: phone);
      await pick(tester, 'Choose feed', 'Layer Mash');
      final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
      await tester.scrollUntilVisible(find.byKey(const ValueKey('actual-1')), 200, scrollable: list);
      await tester.enterText(find.byKey(const ValueKey('actual-1')), '20');
      await tester.pump();
      expect(find.textContaining('typed without stock'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('fix the duplicate'), 200, scrollable: list);
    });

    testWidgets('Distribute Feed opens on ?date=', (tester) async {
      final api = FakeApi()..gets['/api/CompanyTime/context'] = {'businessDate': '2026-10-02'};
      await open(tester, FeedDistributionScreen(session: await sessionFor(api), company: company, initialDate: '2026-09-28'));
      expect(find.text('September 28, 2026'), findsOneWidget);
    });
  });
}
