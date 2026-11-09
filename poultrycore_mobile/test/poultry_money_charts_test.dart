// Poultry's money charts on the Home tab (user, 2026-11-09).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/poultry/poultry_dashboard_charts.dart';

import 'support/harness.dart';

final now = DateTime(2026, 11, 4, 10);

Map pl({num revenue = 1000, num direct = 700, num operating = 400, num other = 100}) => {
      'totalRevenue': revenue,
      'totalDirectCosts': direct,
      'grossProfit': revenue - direct,
      'totalOperatingExpenses': operating,
      'operatingProfit': revenue - direct - operating,
      'totalOtherCosts': other,
      'netProfit': revenue - direct - operating - other,
      'lines': [
        {'section': 'Revenue', 'lineLabel': 'Egg sales', 'amount': revenue},
        {'section': 'DirectCost', 'lineLabel': 'Feed', 'amount': direct},
        {'section': 'OperatingExpense', 'lineLabel': 'Wages', 'amount': operating},
        {'section': 'OtherCost', 'lineLabel': 'Depreciation', 'amount': other},
        {'section': 'Financing', 'lineLabel': 'Owner contributions', 'amount': 5000},
      ],
    };

void main() {
  setUp(ChartFolds.reset);

  testWidgets('a loss: headline, per-period columns, waterfall, costs ranked, cash, who owes whom', (tester) async {
    final api = FakeApi()
      ..gets['/api/Poultry/profit-loss'] = pl()
      ..gets['/api/Poultry/cash-flow'] = {
        'summary': {'openingCash': 500},
        'rows': [
          {'transactionDate': '2026-10-03T09:00:00', 'amount': 300},
          {'transactionDate': '2026-10-20', 'amount': -900},
          {'transactionDate': '2026-11-02', 'amount': 150},
        ],
      }
      ..gets['/api/Poultry/customer-balances/summary'] = {'totalBalance': 250, 'partyCount': 2}
      ..gets['/api/Poultry/supplier-balances/summary'] = {'totalBalance': 400, 'partyCount': 1};
    await open(
      tester,
      Scaffold(body: ListView(children: [PoultryDashboardCharts(session: await sessionFor(api), company: company, now: () => now)])),
      size: const Size(390, 6000),
    );
    await tester.pumpAndSettle();

    // 1. The headline: a loss of 200, margin −20%, costs over revenue.
    expect(find.text('Loss'), findsWidgets);
    expect(find.textContaining('200.00'), findsWidgets);
    expect(find.text('-20.0%'), findsOneWidget);
    expect(find.textContaining('Costs were 120% of revenue'), findsOneWidget);
    expect(find.textContaining('Same as the period before'), findsOneWidget, reason: 'the fake answers every window alike');

    // 2. One P&L request per month (12), plus the whole window and the one before it.
    final starts = {
      for (final r in api.requests)
        if (r.url.path == '/api/Poultry/profit-loss') '${r.url.queryParameters['startDate']}|${r.url.queryParameters['endDate']}',
    };
    expect(starts, containsAll(['2025-12-01|2026-11-04', '2026-11-01|2026-11-04', '2025-12-01|2025-12-31']));
    expect(starts.length, 14, reason: '12 months + the previous window (the whole window shares no key with a month)');

    // 3. The waterfall steps and the excluded financing line left out of costs.
    for (final t in ['Gross profit', 'Operating profit', 'Net profit', 'Direct production costs']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Owner contributions'), findsNothing);

    // 4. Costs ranked: Feed first, shares of 1,200.
    expect(find.text('Feed'), findsOneWidget);
    expect(find.text('58%'), findsOneWidget);
    expect(find.textContaining('Total costs'), findsOneWidget);

    // 5 & 6. Cash: in 450, out 900; cash at hand 500 → 50.
    expect(find.textContaining('450.00'), findsWidgets);
    expect(find.textContaining('900.00'), findsWidgets);
    expect(find.text('At the start'), findsOneWidget);
    expect(find.text('Fell by'), findsOneWidget);

    // 7. Who owes whom.
    expect(find.text('Customers owe you'), findsOneWidget);
    expect(find.textContaining('You owe'), findsWidgets);
    expect(find.textContaining('more than you are owed'), findsOneWidget);

    // A tapped month reads its own figures.
    await tester.tapAt(tester.getBottomRight(find.byType(CustomPaint).at(1)) - const Offset(8, 40));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a folded money card asks for nothing', (tester) async {
    final api = FakeApi()..gets['/api/Poultry/profit-loss'] = pl(revenue: 5000);
    final session = await sessionFor(api);
    await open(tester, Scaffold(body: ListView(children: [PoultryDashboardCharts(session: session, company: company, now: () => now)])),
        size: const Size(390, 6000));
    await tester.pumpAndSettle();
    expect(find.text('Profit'), findsWidgets);
    for (final t in ['Profit or loss', 'Profit or loss per period', 'From revenue to profit', 'What the costs are']) {
      await tester.tap(find.text(t));
      await tester.pumpAndSettle();
    }
    // Reopen the dashboard: the folded P&L cards make no P&L requests.
    api.requests.clear();
    await open(tester, Scaffold(body: ListView(children: [PoultryDashboardCharts(key: UniqueKey(), session: session, company: company, now: () => now)])),
        size: const Size(390, 6000));
    await tester.pumpAndSettle();
    expect(api.requests.where((r) => r.url.path == '/api/Poultry/profit-loss'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
