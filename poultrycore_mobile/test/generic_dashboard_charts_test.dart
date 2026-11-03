// Generic → Home tab charts (an app addition, 2 Nov, mobile only), at phone width against a fake API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/generic/generic_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_dashboard_charts.dart';

import 'support/harness.dart';

final gen = Company(farmId: 'g1', name: 'Fit Gym', type: CompanyType.generic, role: 'Admin');
final now = DateTime(2026, 11, 2, 10);
const today = '2026-11-02';
const base = '/api/generic-company/g1';

FakeApi fake() => FakeApi()
  ..gets['$base/sales'] = [
    {'saleDate': '${today}T09:00:00', 'totalAmount': 300, 'amountPaid': 200, 'balance': 100, 'status': 'Approved'},
    {'saleDate': today, 'totalAmount': 999, 'amountPaid': 999, 'balance': 0, 'status': 'Refunded'},
  ]
  ..gets['$base/expenses'] = [
    {'expenseDate': today, 'categoryName': 'Rent', 'amount': 120, 'status': 'Approved'},
    {'expenseDate': today, 'categoryName': 'Travel', 'amount': 4000, 'status': 'Draft'},
  ]
  ..gets['$base/reports/sales-by-product'] = [
    {'productName': 'Monthly pass', 'totalRevenue': 500},
    {'productName': 'Protein bar', 'totalRevenue': 60},
    {'productName': 'Towel', 'totalRevenue': 0},
  ];

void main() {
  test('product mix: three best, the rest as Other, zero revenue left out', () {
    final s = productMix([
      for (final (n, v) in [('A', 40), ('B', 30), ('C', 20), ('D', 10), ('E', 0)]) {'productName': n, 'totalRevenue': v},
    ]);
    expect([for (final x in s) '${x.label}:${x.value}'], ['A:40', 'B:30', 'C:20', 'Other:10']);
  });

  testWidgets('the four charts at phone width; only Approved counts; a tapped day; the queries', (tester) async {
    final api = fake();
    await open(
      tester,
      Scaffold(body: ListView(children: [GenericDashboardCharts(session: await sessionFor(api), company: gen, now: () => now)])),
      size: const Size(360, 3000),
    );
    for (final t in ['Money in & out', 'Paid & still owed', 'What sells', 'Where the money goes']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Rent'), findsOneWidget);
    expect(find.byType(MixDonut), findsNWidgets(2), reason: 'both breakdowns are pie charts (2 Nov)');
    expect(find.text('Travel'), findsNothing, reason: 'a draft expense is left out');
    expect(find.text('Monthly pass'), findsOneWidget);
    expect(find.text('Towel'), findsNothing);
    Map<String, String> q(String path) => api.requests.firstWhere((r) => r.url.path == '$base$path').url.queryParameters;
    expect(q('/sales')['status'], 'Approved');
    expect(q('/expenses')['status'], 'Approved');
    expect((q('/reports/sales-by-product')['fromDate'], q('/reports/sales-by-product')['toDate']), ('2025-12-01', today), reason: 'the picker opens on Months');

    final money = find.byType(PairedColumns).first;
    final box = tester.getRect(find.descendant(of: money, matching: find.byType(CustomPaint)).last);
    await tester.tapAt(Offset(box.right - 8, box.center.dy));
    await tester.pumpAndSettle();
    expect(find.textContaining('net +180.00'), findsOneWidget, reason: '300 sold, 120 spent; the refunded sale left out');

    final owed = find.byType(PairedColumns).at(1);
    final owedBox = tester.getRect(find.descendant(of: owed, matching: find.byType(CustomPaint)).last);
    await tester.tapAt(Offset(owedBox.right - 8, owedBox.center.dy));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 sale(s)'), findsOneWidget);
    expect(find.text('100.00'), findsWidgets, reason: 'still owed today');
    expect(tester.takeException(), isNull);
  });

  testWidgets('no records: each chart says so instead of breaking', (tester) async {
    await open(
      tester,
      Scaffold(body: ListView(children: [GenericDashboardCharts(session: await sessionFor(FakeApi()), company: gen, now: () => now)])),
      size: const Size(360, 3000),
    );
    expect(find.text('No product sales in the last 12 months'), findsOneWidget);
    expect(find.text('No approved expenses in the last 12 months'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
