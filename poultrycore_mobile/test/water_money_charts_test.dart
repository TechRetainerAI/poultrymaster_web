// Water's money charts on the Home tab (user, 2026-11-13: Poultry's P&L,
// waterfall, cash and who-owes-whom charts, fitted to Water).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/poultry/poultry_money_charts.dart';
import 'package:poultrycore_mobile/pages/water/water_dashboard_charts.dart';

import 'support/harness.dart';

final water = Company(farmId: 'w1', name: 'Clear Water', type: CompanyType.water, role: 'Admin');
final now = DateTime(2026, 11, 4, 10);

/// Water's /profit-loss: totals under `summary`, a Loss band, informational lines.
Map waterPl() => {
      'summary': {
        'storefrontSales': 600,
        'deliveryCollections': 400,
        'totalRevenue': 1000,
        'totalDirectCosts': 500,
        'grossProfit': 500,
        'totalOperatingExpenses': 300,
        'totalOtherCosts': 100,
        'operatingProfit': 100,
        'totalLosses': 250,
        'netProfit': -150,
        'bagsSold': 200,
        'avgProfitPerBag': -0.75,
      },
      'lines': [
        {'section': 'Revenue', 'lineLabel': 'Storefront sales', 'amount': 600},
        {'section': 'Revenue', 'lineLabel': 'Delivery collections', 'amount': 400},
        {'section': 'DirectCost', 'lineLabel': 'Raw materials', 'amount': 500},
        {'section': 'OperatingExpense', 'lineLabel': 'Fuel', 'amount': 300},
        {'section': 'OtherCost', 'lineLabel': 'Depreciation', 'amount': 100},
        {'section': 'Loss', 'lineLabel': 'Driver shortages', 'amount': 250},
        {'section': 'Financing', 'lineLabel': 'Owner contributions', 'amount': 5000, 'isInformational': true},
        {'section': 'CapitalInvestment', 'lineLabel': 'Sachet machine', 'amount': 9000, 'isInformational': true},
      ],
    };

void main() {
  setUp(ChartFolds.reset);

  test('Water figures: summary totals, losses are costs, informational lines left out', () {
    final f = PlFigures.water(waterPl());
    expect(f.revenue, 1000);
    expect(f.costs, 1150, reason: '500 direct + 300 operating + 100 other + 250 losses');
    expect(f.net, -150);
    expect([for (final l in f.costLines) l.label], ['Raw materials', 'Fuel', 'Driver shortages', 'Depreciation']);
    expect(f.costLines.map((l) => l.label), isNot(contains('Sachet machine')));
    // Poultry reading the same map sees nothing at the top level, and never counts a Loss line.
    expect(PlFigures(waterPl()).revenue, 0);
    expect(PlFigures(waterPl()).costLines.map((l) => l.label), isNot(contains('Driver shortages')));
  });

  testWidgets('Water Home: the seven money cards above the Water charts, on /api/Water', (tester) async {
    final api = FakeApi()
      ..gets['/api/Water/daily-productions'] = []
      ..gets['/api/Water/sales'] = []
      ..gets['/api/Water/expenses'] = []
      ..gets['/api/Water/profit-loss'] = waterPl()
      ..gets['/api/Water/cash-flow'] = {
        'summary': {'openingCash': 500},
        'rows': [
          {'transactionDate': '2026-10-03T09:00:00', 'amount': 300},
          {'transactionDate': '2026-10-20', 'amount': -900},
          {'transactionDate': '2026-11-02', 'amount': 150},
        ],
      }
      ..gets['/api/Water/customer-balances/summary'] = {'totalBalance': 250, 'partyCount': 2}
      ..gets['/api/Water/supplier-balances/summary'] = {'totalBalance': 400, 'partyCount': 1};
    await open(
      tester,
      Scaffold(body: ListView(children: [WaterDashboardCharts(session: await sessionFor(api), company: water, now: () => now)])),
      size: const Size(360, 7000),
    );
    await tester.pumpAndSettle();

    final titles = ['Profit or loss', 'Profit or loss per period', 'From revenue to profit', 'What the costs are', 'Cash in and out',
        'Cash at hand', 'Who owes whom', 'Bags produced'];
    for (final t in titles) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    // Money first, then the Water charts.
    expect(tester.getTopLeft(find.text('Who owes whom').first).dy, lessThan(tester.getTopLeft(find.text('Bags produced')).dy));

    // Headline: a loss of 150 after losses; Water's own figures.
    expect(find.text('Loss'), findsWidgets);
    expect(find.text('Storefront sales'), findsOneWidget);
    expect(find.text('Delivery collections'), findsOneWidget);
    expect(find.text('Profit per bag'), findsOneWidget);
    expect(find.text('200 bags sold'), findsOneWidget);
    expect(find.textContaining('Costs were 115% of revenue'), findsOneWidget);

    // Waterfall with Water's steps.
    for (final t in ['Raw materials & production', 'Expenses, depreciation & interest', 'Losses & driver shortages', 'Net profit']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // Costs ranked include the loss line, never the capital or owner lines.
    expect(find.text('Driver shortages'), findsOneWidget);
    expect(find.text('Sachet machine'), findsNothing);
    expect(find.text('Owner contributions'), findsNothing);

    // Cash and balances.
    expect(find.text('At the start'), findsOneWidget);
    expect(find.text('Customers owe you'), findsOneWidget);
    expect(find.textContaining('more than you are owed'), findsOneWidget);

    // Every request went to Water's rail.
    expect(api.requests.where((r) => r.url.path.startsWith('/api/Poultry')), isEmpty);
    expect(api.requests.where((r) => r.url.path == '/api/Water/profit-loss').length, greaterThan(12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no P&L answer: the cards say so instead of breaking', (tester) async {
    final api = FakeApi()
      ..gets['/api/Water/daily-productions'] = []
      ..gets['/api/Water/sales'] = []
      ..gets['/api/Water/expenses'] = [];
    await open(
      tester,
      Scaffold(body: ListView(children: [WaterDashboardCharts(session: await sessionFor(api), company: water, now: () => now)])),
      size: const Size(360, 7000),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profit & Loss is not available right now'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
