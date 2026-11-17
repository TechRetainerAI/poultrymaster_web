// Generic's money charts on the Home tab (user, 2026-11-13: the Poultry and
// Water P&L, waterfall, cash and who-owes-whom charts, fitted to Generic).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/generic/generic_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/poultry/poultry_money_charts.dart';

import 'support/harness.dart';

final gen = Company(farmId: 'g1', name: 'Fit Gym', type: CompanyType.generic, role: 'Admin');
final now = DateTime(2026, 11, 4, 10);
const base = '/api/generic-company/g1';

/// reports/period-pnl: net profit is sales less expenses (COGS only shapes gross profit).
Map pnl() => {
      'totalIncome': 1000,
      'totalExpenses': 1150,
      'costOfGoodsSold': 400,
      'grossProfit': 600,
      'netProfit': -150,
      'profitMarginPct': -15,
      'totalPurchasesPaid': 300,
      'salesCount': 12,
    };

FakeApi fake() => FakeApi()
  ..gets['$base/sales'] = []
  ..gets['$base/expenses'] = []
  ..gets['$base/reports/sales-by-product'] = []
  ..gets['$base/reports/period-pnl'] = pnl()
  ..gets['$base/reports/expenses-by-category'] = [
    {'categoryName': 'Rent', 'totalAmount': 800, 'expenseCount': 1},
    {'categoryName': 'Electricity', 'totalAmount': 350, 'expenseCount': 3},
    {'categoryName': 'Nothing', 'totalAmount': 0, 'expenseCount': 0},
  ]
  // The fake answers every column alike: 100 in, 40 out per month, 1,000 at hand today.
  ..gets['$base/reports/cash-summary'] = {
    'accounts': [
      {'accountName': 'Till', 'periodCashIn': 70, 'periodCashOut': 40, 'currentBalance': 600, 'isActive': true},
      {'accountName': 'Bank', 'periodCashIn': 30, 'periodCashOut': 0, 'currentBalance': 400, 'isActive': true},
    ],
    'totalCashAtHand': 1000,
  }
  ..gets['$base/balances/customer-balances/summary'] = {'totalBalance': 250, 'partyCount': 2}
  ..gets['$base/balances/supplier-balances/summary'] = {'totalBalance': 400, 'partyCount': 1};

void main() {
  setUp(ChartFolds.reset);

  test('Generic figures: the server totals as they come; costs are the expenses', () {
    final f = PlFigures.generic(pnl());
    expect(f.generic, isTrue);
    expect(f.revenue, 1000);
    expect(f.net, -150);
    expect(f.costs, 1150);
    expect(f.cogs, 400);
    expect(f.gross, 600);
    expect(f.salesCount, 12);
  });

  testWidgets('Generic Home: the seven money cards above the Generic charts, on its own routes', (tester) async {
    final api = fake();
    await open(
      tester,
      Scaffold(body: ListView(children: [GenericDashboardCharts(session: await sessionFor(api), company: gen, now: () => now)])),
      size: const Size(360, 7000),
    );
    await tester.pumpAndSettle();

    for (final t in ['Profit or loss', 'Profit or loss per period', 'From revenue to profit', 'What the costs are', 'Cash in and out',
        'Cash at hand', 'Who owes whom', 'What sells']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(tester.getTopLeft(find.text('Who owes whom').first).dy, lessThan(tester.getTopLeft(find.text('What sells').first).dy));

    // Headline: the server's loss, with cost of goods sold and gross profit beside it.
    expect(find.text('Loss'), findsWidgets);
    expect(find.text('Cost of goods sold'), findsOneWidget);
    expect(find.text('Gross profit'), findsOneWidget);
    expect(find.text('12'), findsOneWidget, reason: 'sales count');
    expect(find.textContaining('Costs were 115% of revenue'), findsOneWidget);

    // Waterfall: Revenue → Expenses → Net profit (the server's own sum).
    expect(find.text('Expenses'), findsWidgets);
    expect(find.text('Net profit'), findsWidgets);
    expect(find.text('Operating profit'), findsNothing);

    // Costs: expenses by category, largest first, empty categories left out.
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Electricity'), findsOneWidget);
    expect(find.text('Nothing'), findsNothing);
    expect(find.text('70%'), findsOneWidget, reason: '800 of 1,150');

    // Cash at hand: 12 months of +60 back from 1,000 today → 280 at the start.
    expect(find.text('At the start'), findsOneWidget);
    expect(find.textContaining('280.00'), findsWidgets);
    expect(find.textContaining('1,000.00'), findsWidgets);

    // Balances.
    expect(find.text('Customers owe you'), findsOneWidget);
    expect(find.textContaining('more than you are owed'), findsOneWidget);

    // Only Generic's routes; one cash summary per month (12).
    // (The shared currency setting, FarmMoney.load, is the one exception, as on every Generic money screen.)
    expect(
      api.requests
          .where((r) => r.url.path.startsWith('/api/Poultry') || r.url.path.startsWith('/api/Water'))
          .map((r) => r.url.path)
          .where((path) => path != '/api/Water/farm-settings')
          .toList(),
      isEmpty,
    );
    expect(api.requests.where((r) => r.url.path == '$base/reports/cash-summary').length, 12);
    expect(api.requests.where((r) => r.url.path == '$base/reports/period-pnl').length, greaterThan(12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed cash column: the cash cards say so; no P&L: the P&L cards say so', (tester) async {
    final api = FakeApi()
      ..gets['$base/sales'] = []
      ..gets['$base/expenses'] = []
      ..gets['$base/reports/sales-by-product'] = [];
    await open(
      tester,
      Scaffold(body: ListView(children: [GenericDashboardCharts(session: await sessionFor(api), company: gen, now: () => now)])),
      size: const Size(360, 7000),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profit & Loss is not available right now'), findsWidgets);
    expect(find.text('Cash Flow is not available right now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
