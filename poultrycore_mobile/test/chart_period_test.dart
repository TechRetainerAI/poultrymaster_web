// The Days / Weeks / Months / Years picker over the dashboard charts (2 Nov).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/generic/generic_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/poultry/poultry_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/shared/chart_period.dart';

import 'support/harness.dart';

final now = DateTime(2026, 11, 4, 10); // a Wednesday

void main() {
  test('the buckets of each period, oldest first, the last holding today', () {
    final d = ChartPeriod.days.buckets(now);
    expect((d.length, d.first.from, d.last.from, d.last.short), (14, '2026-10-22', '2026-11-04', 'Today'));

    final w = ChartPeriod.weeks.buckets(now);
    expect((w.length, w.last.from, w.last.to, w.last.short), (12, '2026-11-02', '2026-11-08', 'Now'), reason: 'weeks start on Monday');
    expect((w.first.from, w.first.long), ('2026-08-17', 'Week of 17 Aug'));

    final m = ChartPeriod.months.buckets(now);
    expect((m.length, m.first.from, m.first.short, m.last.to, m.last.long), (12, '2025-12-01', 'Dec', '2026-11-30', 'November 2026'));
    expect(m[2].to, '2026-02-28', reason: 'month ends are real month ends');

    final y = ChartPeriod.years.buckets(now);
    expect([for (final b in y) b.short], ['2022', '2023', '2024', '2025', '2026']);
  });

  test('bucket sums: each row in its bucket, rows outside the window ignored', () {
    final b = ChartPeriod.months.buckets(now);
    final rows = [
      {'d': '2026-11-01T08:00:00', 'v': 5},
      {'d': '2026-11-30', 'v': 1},
      {'d': '2026-01-15', 'v': 7},
      {'d': '2024-05-01', 'v': 100},
      {'d': '', 'v': 9},
    ];
    final s = bucketSums(b, rows, (r) => '${r['d']}'.length >= 10 ? '${r['d']}'.substring(0, 10) : '${r['d']}', (r) => r['v'] as num);
    expect((s.last, s[1], s.reduce((a, x) => a + x)), (6, 7, 13));
  });

  testWidgets('Poultry: switching to Years brings in last year\'s sale; the window words follow', (tester) async {
    final api = FakeApi()
      ..gets['/api/Sale'] = [
        {'saleDate': '2025-03-10', 'product': 'Old hens', 'totalAmount': 700},
        {'saleDate': '2026-11-03', 'product': 'Eggs', 'totalAmount': 50},
      ];
    await open(
      tester,
      Scaffold(body: ListView(children: [PoultryDashboardCharts(session: await sessionFor(api), company: company, now: () => now)])),
      size: const Size(360, 3200),
    );
    expect(find.text('Old hens'), findsNothing, reason: 'it opens on Months: March 2025 is outside the last 12 months');
    expect(find.textContaining('month by month, last 12 months'), findsWidgets);

    await tester.tap(find.text('Years'));
    await tester.pumpAndSettle();
    expect(find.text('Old hens'), findsOneWidget);
    expect(find.text('750.00'), findsWidgets, reason: 'both sales in the 5-year pie');
    expect(find.textContaining('year by year, last 5 years'), findsWidgets);
    expect(find.text('2025'), findsNothing, reason: 'column labels are painted, not widgets');

    await tester.tap(find.text('Months'));
    await tester.pumpAndSettle();
    expect(find.text('Old hens'), findsNothing, reason: 'March 2025 is outside the last 12 months');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Generic: a new period asks the Sales by product report for its own window', (tester) async {
    final gen = Company(farmId: 'g1', name: 'Fit Gym', type: CompanyType.generic, role: 'Admin');
    final api = FakeApi();
    await open(
      tester,
      Scaffold(body: ListView(children: [GenericDashboardCharts(session: await sessionFor(api), company: gen, now: () => now)])),
      size: const Size(360, 3200),
    );
    await tester.tap(find.text('Weeks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Months'));
    await tester.pumpAndSettle();
    final froms = [
      for (final r in api.requests)
        if (r.url.path.endsWith('/reports/sales-by-product')) r.url.queryParameters['fromDate'],
    ];
    expect(froms, ['2025-12-01', '2026-08-17'], reason: 'Months (the opening view), then Weeks; Months again comes from memory');
    expect(tester.takeException(), isNull);
  });
}
