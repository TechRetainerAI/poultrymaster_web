// Poultry → Home tab charts (an app addition, 2 Nov), at phone width against a fake API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/poultry/poultry_dashboard_charts.dart';

import 'support/harness.dart';

final now = DateTime(2026, 11, 2, 10);
const today = '2026-11-02';

FakeApi base() => FakeApi()
  ..gets['/api/ProductionRecord'] = [
    {'date': '${today}T00:00:00', 'totalProduction': 420, 'brokenEggs': 12, 'mortality': 3, 'feedKg': 50},
    {'date': '2026-11-01T00:00:00', 'totalProduction': 400, 'brokenEggs': 8, 'mortality': 1, 'feedKg': 48},
  ]
  ..gets['/api/Sale'] = [
    {'saleDate': '${today}T09:00:00', 'product': 'Eggs', 'totalAmount': 300},
    {'saleDate': today, 'product': 'Live birds', 'totalAmount': 100},
    {'saleDate': today, 'product': 'Eggs', 'totalAmount': 999, 'status': 'Reversed'},
  ]
  ..gets['/api/Expense'] = [
    {'expenseDate': today, 'category': 'Feed', 'amount': 150},
    {'expenseDate': '2026-10-20', 'category': 'Vet', 'amount': 40},
    {'expenseDate': today, 'category': 'Equipment', 'amount': 5000, 'plSection': 'Excluded'},
  ];

void main() {
  test('top groups: the three biggest, the rest as Other, only the last 30 days', () {
    final rows = [
      for (final (c, a) in [('A', 50), ('B', 40), ('C', 30), ('D', 20), ('E', 10)]) {'d': today, 'c': c, 'v': a},
      {'d': '2026-09-01', 'c': 'Old', 'v': 1000},
    ];
    final s = topGroups(rows, today, dateKey: 'd', key: 'c', amountKey: 'v');
    expect([for (final x in s) '${x.label}:${x.value}'], ['A:50', 'B:40', 'C:30', 'Other:30']);
  });

  testWidgets('the four charts at phone width; reversed sales and excluded costs left out; a tapped day', (tester) async {
    final api = base();
    await open(
      tester,
      Scaffold(body: ListView(children: [PoultryDashboardCharts(session: await sessionFor(api), company: company, now: () => now)])),
      size: const Size(360, 3000),
    );
    for (final t in ['Egg collection', 'Money in & out', 'Where the money goes', 'What sells']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('400.00'), findsWidgets, reason: 'sales: 300 + 100, the reversed 999 left out');
    expect(find.text('190.00'), findsWidgets, reason: 'expenses: 150 + 40, the excluded 5000 left out');
    expect(find.text('5190.00'), findsNothing);
    expect(find.text('1399.00'), findsNothing);
    expect(find.text('Feed'), findsOneWidget);
    expect(find.byType(MixDonut), findsNWidgets(2), reason: 'both breakdowns are pie charts (2 Nov)');
    // Tapping a key row singles out its slice; the middle then reads it.
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    expect(find.text('Feed'), findsNWidgets(2), reason: 'the key row and the middle of the pie');
    expect(find.text('79% of the total'), findsOneWidget, reason: 'Feed 150 of 190');
    await tester.tap(find.text('Feed').last);
    await tester.pumpAndSettle();
    expect(find.text('Live birds'), findsOneWidget);

    final money = find.byType(PairedColumns).at(1);
    final box = tester.getRect(find.descendant(of: money, matching: find.byType(CustomPaint)).last);
    await tester.tapAt(Offset(box.right - 8, box.center.dy));
    await tester.pumpAndSettle();
    expect(find.textContaining('net +250.00'), findsOneWidget, reason: 'today: 400 in, 150 out');

    final eggs = find.byType(PairedColumns).first;
    final eggBox = tester.getRect(find.descendant(of: eggs, matching: find.byType(CustomPaint)).last);
    await tester.tapAt(Offset(eggBox.right - 8, eggBox.center.dy));
    await tester.pumpAndSettle();
    expect(find.textContaining('November 2026 · deaths 4 · feed 98.0 kg'), findsOneWidget, reason: 'by month: both November days together');
    expect(tester.takeException(), isNull);
  });

  testWidgets('no records: each chart says so instead of breaking', (tester) async {
    final api = FakeApi();
    await open(
      tester,
      Scaffold(body: ListView(children: [PoultryDashboardCharts(session: await sessionFor(api), company: company, now: () => now)])),
      size: const Size(360, 3000),
    );
    expect(find.text('No expenses in the last 12 months'), findsOneWidget);
    expect(find.text('No sales in the last 12 months'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
