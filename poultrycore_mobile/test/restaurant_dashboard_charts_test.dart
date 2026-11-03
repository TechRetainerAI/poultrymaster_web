// Restaurant → dashboard charts (an app addition, 2 Nov, mobile only), at phone width against a fake API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_dashboard_charts.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'r1', name: 'Rose Kitchen', type: CompanyType.restaurant, role: 'Admin');
final now = DateTime(2026, 11, 2, 15);
const today = '2026-11-02';
// Midday UTC, so the local day is the same in any time zone the tests run in.
const noon = '${today}T12:00:00Z';

final orders = <Map>[
  {'orderType': 'DineIn', 'status': 'Completed', 'paymentStatus': 'Paid', 'totalAmount': 120, 'createdAt': noon},
  {'orderType': 'Delivery', 'status': 'Completed', 'paymentStatus': 'Paid', 'totalAmount': 80, 'createdAt': noon},
  {'orderType': 'Takeaway', 'status': 'Placed', 'paymentStatus': 'Unpaid', 'totalAmount': 30, 'createdAt': noon},
  {'orderType': 'Takeaway', 'status': 'Refunded', 'paymentStatus': 'Paid', 'totalAmount': 500, 'createdAt': noon},
];

FakeApi base() => FakeApi()
  ..gets['/api/Restaurant/expenses'] = [
    {'expenseDate': today, 'categoryName': 'Ingredients', 'amount': 50, 'status': 'Posted'},
    {'expenseDate': today, 'categoryName': 'Gas', 'amount': 900, 'status': 'Reversed'},
  ];

void main() {
  test('order type mix: paid orders only, refunded left out', () {
    final s = orderTypeMix(orders, today);
    expect([for (final x in s) '${x.label}:${x.value}'], ['Dine-in:120', 'Delivery:80']);
  });

  testWidgets('the four charts at phone width, a tapped day, the expense window', (tester) async {
    final api = base();
    await open(
      tester,
      Scaffold(body: ListView(children: [
        RestaurantDashboardCharts(session: await sessionFor(api), company: rest, orders: orders, now: () => now),
      ])),
      size: const Size(360, 3000),
    );
    for (final t in ['Money in & out', 'Orders', 'How orders come in', 'Where the money goes']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.byType(MixDonut), findsNWidgets(2), reason: 'both breakdowns are pie charts (2 Nov)');
    expect(find.text('Gas'), findsNothing, reason: 'a reversed expense is left out');
    final req = api.requests.firstWhere((r) => r.url.path == '/api/Restaurant/expenses');
    expect((req.url.queryParameters['from'], req.url.queryParameters['to']), ('2022-01-01', today), reason: 'the widest window (5 years), loaded once');

    final money = find.byType(PairedColumns).first;
    final box = tester.getRect(find.descendant(of: money, matching: find.byType(CustomPaint)).last);
    await tester.tapAt(Offset(box.right - 8, box.center.dy));
    await tester.pumpAndSettle();
    expect(find.textContaining('net +150.00'), findsOneWidget, reason: '200 paid, 50 spent');

    final ord = find.byType(PairedColumns).at(1);
    final ordBox = tester.getRect(find.descendant(of: ord, matching: find.byType(CustomPaint)).last);
    await tester.tapAt(Offset(ordBox.right - 8, ordBox.center.dy));
    await tester.pumpAndSettle();
    expect(find.textContaining('average bill 100.00'), findsOneWidget, reason: '200 over two paid orders');
    expect(tester.takeException(), isNull);
  });

  testWidgets('no orders, no expenses: each chart says so', (tester) async {
    await open(
      tester,
      Scaffold(body: ListView(children: [
        RestaurantDashboardCharts(session: await sessionFor(FakeApi()), company: rest, orders: const [], now: () => now),
      ])),
      size: const Size(360, 3000),
    );
    expect(find.text('No paid orders in the last 12 months'), findsOneWidget);
    expect(find.text('No expenses in the last 12 months'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
