// Restaurant's money charts on the dashboard (user, 2026-11-13: the P&L,
// waterfall, cash and who-owes-whom charts the other modules have, fitted to Restaurant).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/poultry/poultry_money_charts.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_dashboard_charts.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'r1', name: 'Rose Kitchen', type: CompanyType.restaurant, role: 'Admin');
final now = DateTime(2026, 11, 4, 15);

/// reports/pnl: the totals.
Map summary() => {
      'revenue': 1000,
      'cogs': 350,
      'grossProfit': 650,
      'expensesTotal': 500,
      'netProfit': 100,
      'netMarginPct': 10,
      'foodCostPct': 35,
      'tipsTotal': 45,
      'orderCount': 80,
    };

/// finance/pnl-lines: profit-signed lines (costs negative).
List<Map> lines() => [
      {'section': 'Revenue', 'label': 'Food sales', 'amount': 1000},
      {'section': 'CostOfSales', 'label': 'Ingredients used', 'amount': -350},
      {'section': 'Expenses', 'label': 'Wages', 'amount': -400},
      {'section': 'Other', 'label': 'Depreciation', 'amount': -50},
    ];

FakeApi fake() => FakeApi()
  ..gets['/api/Restaurant/expenses'] = []
  ..gets['/api/Restaurant/reports/pnl'] = summary()
  ..gets['/api/Restaurant/finance/pnl-lines'] = lines()
  ..gets['/api/Restaurant/cash-flow'] = {
    'summary': {'openingCash': 500},
    'rows': [
      {'transactionDate': '2026-10-03T09:00:00', 'amount': 300},
      {'transactionDate': '2026-10-20', 'amount': -100},
    ],
  }
  ..gets['/api/Restaurant/customer-balances/summary'] = {'totalBalance': 120, 'partyCount': 1}
  ..gets['/api/Restaurant/supplier-balances/summary'] = {'totalBalance': 400, 'partyCount': 2};

void main() {
  setUp(ChartFolds.reset);

  test('Restaurant figures: totalled as the Restaurant P&L page does; net is the server\'s', () {
    final f = PlFigures.restaurant(summary(), lines());
    expect(f.isRestaurant, isTrue);
    expect(f.revenue, 1000);
    expect(f.direct, 350);
    expect(f.operating, 400);
    expect(f.other, 50);
    expect(f.gross, 650);
    expect(f.operatingProfit, 250);
    expect(f.net, 100);
    expect([for (final l in f.costLines) '${l.label}:${l.amount}'], ['Wages:400', 'Ingredients used:350', 'Depreciation:50']);
    // Lines failed: the totals still stand.
    expect(PlFigures.restaurant(summary(), const []).net, 100);
  });

  testWidgets('Restaurant dashboard: the seven money cards first, on /api/Restaurant', (tester) async {
    final api = fake();
    await open(
      tester,
      Scaffold(body: ListView(children: [RestaurantDashboardCharts(session: await sessionFor(api), company: rest, orders: const [], now: () => now)])),
      size: const Size(360, 7000),
    );
    await tester.pumpAndSettle();

    for (final t in ['Profit or loss', 'Profit or loss per period', 'From revenue to profit', 'What the costs are', 'Cash in and out',
        'Cash at hand', 'Who owes whom', 'How orders come in']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(tester.getTopLeft(find.text('Who owes whom').first).dy, lessThan(tester.getTopLeft(find.text('How orders come in').first).dy));

    expect(find.text('Profit'), findsWidgets);
    expect(find.text('Food cost'), findsOneWidget);
    expect(find.text('35.0%'), findsOneWidget);
    expect(find.text('Completed orders'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(find.text('Tips collected'), findsOneWidget);
    expect(find.text('Cost of sales (food & drink)'), findsOneWidget);
    expect(find.text('Ingredients used'), findsOneWidget);
    expect(find.text('Wages'), findsOneWidget);
    expect(find.text('Customers owe you'), findsOneWidget);
    expect(find.textContaining('more than you are owed'), findsOneWidget);

    final reqs = api.requests.map((r) => r.url).toList();
    expect(reqs.where((u) => u.path.startsWith('/api/Poultry') || u.path.startsWith('/api/Hotel')), isEmpty);
    final pnl = reqs.where((u) => u.path == '/api/Restaurant/reports/pnl').toList();
    expect(pnl, isNotEmpty);
    expect(pnl.every((u) => u.queryParameters['farmId'] == 'r1' && u.queryParameters.containsKey('from') && u.queryParameters.containsKey('to')), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no P&L answer: the P&L cards say so', (tester) async {
    final api = FakeApi()..gets['/api/Restaurant/expenses'] = [];
    await open(
      tester,
      Scaffold(body: ListView(children: [RestaurantDashboardCharts(session: await sessionFor(api), company: rest, orders: const [], now: () => now)])),
      size: const Size(360, 7000),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profit & Loss is not available right now'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
