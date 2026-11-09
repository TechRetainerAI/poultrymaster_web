// The Days / Weeks / Months / Years picker over the dashboard charts (2 Nov).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/generic/generic_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/poultry/poultry_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_dashboard_charts.dart';
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

  // ------------------------------------------------ Range (user, 9 Nov 2026)

  test('a range: grouping follows its length; first and last columns are cut to the range', () {
    final d = ChartWindow.range(DateTime(2026, 10, 20), DateTime(2026, 11, 4));
    final db = d.buckets(now);
    expect((d.period, db.length, db.first.from, db.last.short), (ChartPeriod.days, 16, '2026-10-20', 'Today'));
    expect((d.window, d.inWindow), ('20 Oct – 4 Nov 2026', 'between 20 Oct and 4 Nov 2026'));

    // Wed 1 Oct to Fri 31 Oct 2025 is 31 days, still by day; one more day goes by week.
    expect(ChartWindow.range(DateTime(2025, 10, 1), DateTime(2025, 10, 31)).period, ChartPeriod.days);
    final w = ChartWindow.range(DateTime(2025, 10, 1), DateTime(2025, 11, 1));
    final wb = w.buckets(now);
    expect(w.period, ChartPeriod.weeks);
    expect((wb.first.from, wb.first.to, wb.first.long), ('2025-10-01', '2025-10-05', '1 Oct – 5 Oct 2025'), reason: 'a Wednesday start: the first week is cut');
    expect((wb[1].from, wb.last.from, wb.last.to), ('2025-10-06', '2025-10-27', '2025-11-01'));
    expect(bucketHolding(wb, '2026-11-04'), isNull, reason: 'a past range has no "today" column');

    final m = ChartWindow.range(DateTime(2024, 3, 15), DateTime(2025, 2, 10));
    final mb = m.buckets(now);
    expect((m.period, mb.length, mb.first.from, mb.first.to, mb.last.to), (ChartPeriod.months, 12, '2024-03-15', '2024-03-31', '2025-02-10'));
    expect(m.window, '15 Mar 2024 – 10 Feb 2025');

    final y = ChartWindow.range(DateTime(2019, 6, 1), DateTime(2026, 11, 4));
    expect((y.period, y.buckets(now).length, y.buckets(now).first.from), (ChartPeriod.years, 8, '2019-06-01'));

    expect(ChartWindow.range(DateTime(2026, 5, 9), DateTime(2026, 5, 1)).from, DateTime(2026, 5, 1), reason: 'dates given backwards are put in order');
    expect(ChartWindow.range(DateTime(2026, 5, 1), DateTime(2026, 5, 1)).inWindow, 'on 1 May 2026');
  });

  testWidgets('Poultry: Range opens a calendar; the charts then cover only those dates; the cross goes back to Months', (tester) async {
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
    await tester.tap(find.text('Range'));
    await tester.pumpAndSettle();
    expect(find.text('Show the charts for'), findsOneWidget);
    // Type the dates instead of scrolling the calendar back to 2025.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '03/01/2025');
    await tester.enterText(fields.at(1), '03/31/2025');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Old hens'), findsOneWidget);
    expect(find.text('700.00'), findsWidgets, reason: 'only the March 2025 sale: the November 2026 one is outside the range');
    expect(find.text('750.00'), findsNothing);
    expect(find.text('1 Mar – 31 Mar 2025'), findsOneWidget, reason: 'the range is read back under the picker');
    expect(find.textContaining('day by day, 1 Mar – 31 Mar 2025'), findsWidgets);

    await tester.tap(find.byTooltip('Back to Months'));
    await tester.pumpAndSettle();
    expect(find.text('Old hens'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Restaurant: a range older than the 5 years loaded asks for the expenses again from its first day', (tester) async {
    final api = FakeApi();
    final rest = Company(farmId: 'r1', name: 'Bistro', type: CompanyType.restaurant, role: 'Admin');
    await open(
      tester,
      Scaffold(body: ListView(children: [RestaurantDashboardCharts(session: await sessionFor(api), company: rest, orders: const [], now: () => now)])),
      size: const Size(360, 3200),
    );
    await tester.tap(find.text('Range'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '01/01/2019');
    await tester.enterText(find.byType(TextField).at(1), '12/31/2019');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final froms = [
      for (final r in api.requests)
        if (r.url.path.endsWith('/api/Restaurant/expenses')) r.url.queryParameters['from'],
    ];
    expect(froms, ['2022-01-01', '2019-01-01']);
    expect(tester.takeException(), isNull);
  });
}
