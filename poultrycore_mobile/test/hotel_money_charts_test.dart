// Hotel's money charts on the Home tab (user, 2026-11-13: the Poultry, Water
// and Generic P&L, waterfall, cash and who-owes-whom charts, fitted to Hotel).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/poultry/poultry_money_charts.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'h1', name: 'Lake Inn', type: CompanyType.hotel, role: 'Admin');
const today = '2026-11-04';

/// /api/Hotel/profit-loss: lines only carry the bands; supplies used are direct costs.
Map hotelPl() => {
      'roomRevenue': 800,
      'restaurantRevenue': 200,
      'depositsNet': 300,
      'totalRevenue': 1000,
      'totalExpenses': 900,
      'totalOtherCosts': 100,
      'netProfit': 0,
      'lines': [
        {'section': 'Revenue', 'lineKey': 'Rooms', 'lineLabel': 'Room revenue', 'amount': 800},
        {'section': 'Revenue', 'lineKey': 'Restaurant', 'lineLabel': 'Restaurant revenue', 'amount': 200},
        {'section': 'OperatingExpense', 'lineKey': 'SuppliesUsed', 'lineLabel': 'Supplies used', 'amount': 300},
        {'section': 'OperatingExpense', 'lineKey': 'StaffWages', 'lineLabel': 'Staff wages', 'amount': 600},
        {'section': 'OtherCost', 'lineKey': 'Depreciation', 'lineLabel': 'Depreciation', 'amount': 100},
        {'section': 'Financing', 'lineKey': 'Deposits', 'lineLabel': 'Deposits held', 'amount': 300, 'isInformational': true},
      ],
    };

FakeApi fake() => FakeApi()
  ..gets['/api/Hotel/profit-loss'] = hotelPl()
  ..gets['/api/Hotel/cash-flow'] = {
    'summary': {'openingCash': 500},
    'rows': [
      {'transactionDate': '2026-10-03T09:00:00', 'amount': 300},
      {'transactionDate': '2026-10-20', 'amount': -900},
    ],
  }
  ..gets['/api/Hotel/balances/customer-balances/summary'] = {'totalBalance': 700, 'partyCount': 3}
  ..gets['/api/Hotel/balances/supplier-balances/summary'] = {'totalBalance': 200, 'partyCount': 1};

void main() {
  setUp(ChartFolds.reset);

  test('Hotel figures: bands as the Hotel P&L page puts them; deposits apart from revenue', () {
    final f = PlFigures.hotel(hotelPl());
    expect(f.hotel, isTrue);
    expect(f.revenue, 1000);
    expect(f.direct, 300, reason: 'supplies used');
    expect(f.operating, 600);
    expect(f.other, 100);
    expect(f.gross, 700);
    expect(f.operatingProfit, 100);
    expect(f.net, 0, reason: "the server's net profit");
    expect(f.deposits, 300);
    expect([for (final l in f.costLines) l.label], ['Staff wages', 'Supplies used', 'Depreciation']);
  });

  testWidgets('Hotel Home: the seven money cards first, on /api/Hotel', (tester) async {
    final api = fake();
    await open(
      tester,
      Scaffold(
        body: ListView(children: [
          HotelDashboardCharts(
            statusSummary: const [],
            bookings: const [],
            payments: const [],
            expenses: const [],
            today: today,
            session: await sessionFor(api),
            company: hotel,
          ),
        ]),
      ),
      size: const Size(360, 7000),
    );
    await tester.pumpAndSettle();

    for (final t in ['Profit or loss', 'Profit or loss per period', 'From revenue to profit', 'What the costs are', 'Cash in and out',
        'Cash at hand', 'Who owes whom', 'Room mix']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(tester.getTopLeft(find.text('Who owes whom').first).dy, lessThan(tester.getTopLeft(find.text('Room mix').first).dy));

    // Headline: break-even counts as a profit of 0; Hotel's own figures.
    expect(find.text('Rooms'), findsOneWidget);
    expect(find.text('Restaurant'), findsOneWidget);
    expect(find.text('Deposits held'), findsOneWidget);
    expect(find.textContaining('not counted as revenue'), findsOneWidget);

    // Waterfall with Hotel's steps; the deposit line is never a cost.
    for (final t in ['Supplies used', 'Gross profit', 'Operating expenses', 'Operating profit', 'Depreciation & financing']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('Staff wages'), findsOneWidget);
    expect(find.text('Customers owe you'), findsOneWidget);
    expect(find.textContaining('more than you owe'), findsOneWidget);

    // Every money request on Hotel's routes, with the company's id.
    final paths = {for (final r in api.requests) r.url.path};
    expect(paths.where((p) => p.startsWith('/api/Poultry') || p.startsWith('/api/generic')), isEmpty);
    expect(api.requests.where((r) => r.url.path == '/api/Hotel/profit-loss').every((r) => r.url.queryParameters['farmId'] == 'h1'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a session (older callers) the charts draw without the money cards', (tester) async {
    await open(
      tester,
      Scaffold(
        body: ListView(children: [
          HotelDashboardCharts(statusSummary: const [], bookings: const [], payments: const [], expenses: const [], today: today),
        ]),
      ),
      size: const Size(360, 3000),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profit or loss'), findsNothing);
    expect(find.text('Room mix'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
