// Water → Home tab charts (an app addition, 2 Nov, mobile only), at phone width against a fake API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_dashboard_charts.dart';
import 'package:poultrycore_mobile/pages/water/water_dashboard_charts.dart';

import 'support/harness.dart';

final water = Company(farmId: 'w1', name: 'Clear Water', type: CompanyType.water, role: 'Admin');
final now = DateTime(2026, 11, 2, 10);
const today = '2026-11-02';

FakeApi base() => FakeApi()
  ..gets['/api/Water/daily-productions'] = [
    {'productionDate': '${today}T00:00:00', 'bagsProduced': 200, 'damagedBags': 5, 'rejectedSachets': 30, 'status': 'Posted'},
    {'productionDate': today, 'bagsProduced': 900, 'damagedBags': 0, 'rejectedSachets': 0, 'status': 'Reversed'},
  ]
  ..gets['/api/Water/sales'] = [
    {'saleDate': '${today}T08:00:00', 'totalAmount': 300, 'status': 'Paid', 'items': [
      {'productName': 'Sachet bag', 'quantity': 50, 'unitPrice': 5, 'lineTotal': 250},
      {'productName': 'Bottle 1.5L', 'quantity': 10, 'unitPrice': 5},
    ]},
    {'saleDate': today, 'totalAmount': 777, 'status': 'Cancelled', 'items': [
      {'productName': 'Dispenser', 'quantity': 1, 'unitPrice': 777},
    ]},
  ]
  ..gets['/api/Water/expenses'] = [
    {'expenseDate': today, 'categoryName': 'Fuel', 'amount': 120, 'status': 'Approved'},
    {'expenseDate': today, 'categoryName': 'Repairs', 'amount': 4000, 'status': 'Submitted'},
  ];

void main() {
  test('sale lines: one row per line, lineTotal or quantity × price', () {
    final rows = saleLines([
      {'saleDate': today, 'items': [
        {'productName': 'A', 'lineTotal': 20, 'quantity': 1, 'unitPrice': 1},
        {'productName': 'B', 'quantity': 3, 'unitPrice': 4},
      ]},
    ]);
    expect([for (final r in rows) '${r['productName']}:${r['amount']}'], ['A:20', 'B:12']);
  });

  testWidgets('the four charts at phone width; cancelled, unapproved and reversed rows left out; a tapped day', (tester) async {
    final api = base();
    await open(
      tester,
      Scaffold(body: ListView(children: [WaterDashboardCharts(session: await sessionFor(api), company: water, now: () => now)])),
      size: const Size(360, 3000),
    );
    for (final t in ['Bags produced', 'Money in & out', 'Where the money goes', 'What sells']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Fuel'), findsOneWidget);
    expect(find.byType(MixDonut), findsNWidgets(2), reason: 'both breakdowns are pie charts (2 Nov)');
    expect(find.text('Repairs'), findsNothing, reason: 'only Approved expenses count');
    expect(find.text('Sachet bag'), findsOneWidget);
    expect(find.text('Bottle 1.5L'), findsOneWidget);
    expect(find.text('Dispenser'), findsNothing, reason: 'a cancelled sale is left out');

    final money = find.byType(PairedColumns).at(1);
    final box = tester.getRect(find.descendant(of: money, matching: find.byType(CustomPaint)).last);
    await tester.tapAt(Offset(box.right - 8, box.center.dy));
    await tester.pumpAndSettle();
    expect(find.textContaining('net +180.00'), findsOneWidget, reason: 'today: 300 in, 120 out');

    final bags = find.byType(PairedColumns).first;
    final bagBox = tester.getRect(find.descendant(of: bags, matching: find.byType(CustomPaint)).last);
    await tester.tapAt(Offset(bagBox.right - 8, bagBox.center.dy));
    await tester.pumpAndSettle();
    expect(find.textContaining('rejected sachets 30'), findsOneWidget, reason: 'the reversed record is left out');
    expect(find.text('195'), findsWidgets, reason: '200 bags less 5 damaged');
    expect(tester.takeException(), isNull);
  });

  testWidgets('no records: each chart says so instead of breaking', (tester) async {
    await open(
      tester,
      Scaffold(body: ListView(children: [WaterDashboardCharts(session: await sessionFor(FakeApi()), company: water, now: () => now)])),
      size: const Size(360, 3000),
    );
    expect(find.text('No approved expenses in the last 12 months'), findsOneWidget);
    expect(find.text('No sales in the last 12 months'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
