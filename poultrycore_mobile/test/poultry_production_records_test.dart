// Poultry → Operations → Production → Production Records, at phone width:
// the list and its filters, the Log Production form (picks, losses, birds,
// FIFO feed costing, the checks and the body), edit, and the routes.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/production/production_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/production/production_records_screen.dart';

import 'support/harness.dart';

final rec1 = <String, Object?>{
  'id': 11, 'flockId': 7, 'date': '2026-10-05T00:00:00', 'production9AM': 60, 'production12PM': 31, 'production4PM': 9, 'brokenEggs': 2,
  'totalProduction': 100, 'noOfBirds': 120, 'mortality': 2, 'noOfBirdsLeft': 118, 'feedKg': 12.5, 'medication': 'Vitamins', 'ageInDays': 87,
  'eggGrade': 'p3',
};
final rec2 = <String, Object?>{
  'id': 12, 'flockId': 8, 'date': '2026-09-20T00:00:00', 'production9AM': 30, 'totalProduction': 30, 'noOfBirds': 50, 'mortality': 0,
  'noOfBirdsLeft': 50, 'feedKg': 5, 'medication': 'None',
};

FakeApi api() => FakeApi()
  ..gets['/api/ProductionRecord'] = [rec1, rec2]
  ..gets['/api/Flock'] = [
    {'flockId': 7, 'name': 'Pen 1', 'batchId': 1, 'quantity': 130, 'active': true, 'hasArrived': true, 'startDate': '2026-07-10T00:00:00'},
    {'flockId': 8, 'name': 'Pen 2', 'batchId': 2, 'quantity': 50, 'active': true, 'hasArrived': true, 'startDate': '2026-08-01T00:00:00'},
    {'flockId': 9, 'name': 'Old pen', 'batchId': 1, 'quantity': 40, 'closedDate': '2026-01-01'},
  ]
  ..gets['/api/MainFlockBatch'] = [
    {'batchId': 1, 'batchName': 'Batch A'},
    {'batchId': 2, 'batchCode': 'B-002'},
  ]
  ..gets['/api/FarmProductionSettings'] = {'enableFourthPick': true, 'fourthPickTime': '18:00', 'firstPickTime': '09:00'}
  ..gets['/api/Poultry/raw-material-items'] = [
    {'poultryRawMaterialItemId': 5, 'itemName': 'Layer mash', 'category': 'FinishedFeed', 'unitOfMeasure': 'Kilogram', 'currentQuantity': 40, 'isActive': true,
      'usageMethod': 'FIFO'},
    {'poultryRawMaterialItemId': 6, 'itemName': 'Maize', 'category': 'FeedIngredient', 'currentQuantity': 90, 'isActive': true},
    {'poultryRawMaterialItemId': 7, 'itemName': 'Vitamin mix', 'category': 'Medication', 'currentQuantity': 3, 'isActive': true, 'usageMethod': 'FIFO'},
  ]
  ..gets['/api/Poultry/raw-material-purchases'] = [
    {'poultryRawMaterialPurchaseId': 1, 'poultryRawMaterialItemId': 5, 'purchaseDate': '2026-09-01', 'remainingQuantity': 1, 'unitCost': 250,
      'productionUnitsPerPurchaseUnit': 25},
    {'poultryRawMaterialPurchaseId': 2, 'poultryRawMaterialItemId': 5, 'purchaseDate': '2026-09-10', 'remainingQuantity': 1, 'unitCost': 300,
      'productionUnitsPerPurchaseUnit': 25},
  ];

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 50 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 70 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, 250));
    await tester.pumpAndSettle();
  }
  Scrollable.ensureVisible(tester.element(f.first), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await see(tester, f);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String shown, String option, {Finder? within, int which = 0}) async {
  final label = within == null ? find.text(shown) : find.descendant(of: within, matching: find.text(shown));
  await see(tester, label);
  final sel = find.ancestor(of: label.at(which), matching: find.byWidgetPredicate((w) => w is AppSelect)).first;
  await tester.ensureVisible(sel);
  await tester.pumpAndSettle();
  await tester.tap(sel);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// The text field under a field label.
Future<void> enter(WidgetTester tester, String label, String text, {int which = 0}) async {
  await see(tester, find.text(label));
  final f = find.descendant(of: find.ancestor(of: find.text(label).at(which), matching: find.byType(Column)).first, matching: find.byType(TextField));
  await tester.enterText(f.first, text);
  await tester.pumpAndSettle();
}

void clearToasts(WidgetTester tester) => tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

void main() {
  test('calculations, costing, age, pick labels, routes', () {
    expect(pickTotal(2, 5), 65);
    expect(cratesEquivalent(65), (crates: 2, pieces: 5));
    expect(flockAge('2026-07-10T00:00:00', '2026-10-05'), (weeks: 12, days: 87, years: 0));
    expect(resolveAge(true, (weeks: 1, days: 7), years: '1'), (weeks: 52, days: 365));
    expect(formatProductionAge(rec1), '0 yr 12 wk 3 d (87 days)');
    expect(eggGradeFromApi('p3'), 'Large');
    expect(const PickSettings(fourth: '18:00').labels.fourth, '4th Pick (6:00 PM)');

    // 30 kg across two lots of 25 kg: 25 at 10/kg then 5 at 12/kg.
    final purchases = [
      {'poultryRawMaterialPurchaseId': 1, 'poultryRawMaterialItemId': 5, 'purchaseDate': '2026-09-01', 'remainingQuantity': 1, 'unitCost': 250, 'productionUnitsPerPurchaseUnit': 25},
      {'poultryRawMaterialPurchaseId': 2, 'poultryRawMaterialItemId': 5, 'purchaseDate': '2026-09-10', 'remainingQuantity': 1, 'unitCost': 300, 'productionUnitsPerPurchaseUnit': 25},
    ];
    final item = {'poultryRawMaterialItemId': 5, 'itemName': 'Layer mash', 'usageMethod': 'FIFO', 'currentQuantity': 50};
    final c = computeLines([ConsumptionLine('5', '30')], [item], purchases, {}, LineKeys.feed);
    expect(c.totalCost, 310);
    expect(c.lines.single['feedUnitCost'], closeTo(10.333, .001));
    expect(c.pendingStock[5], 20);
    final short = computeLines([ConsumptionLine('5', '60')], [item], purchases, {}, LineKeys.feed);
    expect(short.firstShortfall?.preview.shortfall, 10);
    final lifo = computeLines([ConsumptionLine('5', '30')], [{...item, 'usageMethod': 'LIFO'}], purchases, {}, LineKeys.feed);
    expect(lifo.totalCost, 350, reason: '25 at 12 then 5 at 10');

    for (final r in ['/production-records']) {
      expect(pageScreens.containsKey(r), isTrue);
    }
  });

  testWidgets('list: tiles, filters, cards, table', (tester) async {
    final a = api();
    await open(tester, ProductionRecordsScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('130'), findsWidgets, reason: 'eggs 100 + 30');
    await see(tester, find.text('Batch: Batch A'));
    expect(find.text('VITAMINS'), findsNothing);
    expect(find.text('Vitamins'), findsOneWidget);

    await tap(tester, find.text('Filters'));
    await choose(tester, 'All Batches', 'B-002', within: find.byType(BottomSheet));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Vitamins'), findsNothing);
    expect(find.text('1'), findsWidgets, reason: 'active filter badge');

    await tap(tester, find.text('Filters'));
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tap(tester, find.text('View table format'));
    expect(find.text('4th Pick'), findsOneWidget, reason: 'the enabled 4th pick column');
    await see(tester, find.text('Totals'));
  });

  testWidgets('log production: the checks, then the body with picks, losses and FIFO feed', (tester) async {
    final a = api();
    await open(tester, ProductionRecordsScreen(session: await sessionFor(a), company: company), size: phone);
    await tester.tap(find.text('Log Production'));
    await tester.pumpAndSettle();
    expect(find.text('Add Production Record'), findsOneWidget);
    expect(find.text('4th Pick (6:00 PM)'), findsOneWidget);
    expect(find.text('Old pen'), findsNothing);

    await tester.tap(find.text('Save Production Record'));
    await tester.pumpAndSettle();
    expect(find.text('Choose which flock this production entry is for.'), findsWidgets);
    clearToasts(tester);

    await choose(tester, 'Select a flock', 'Pen 1');
    expect(find.text('Last recorded birds left for this flock: 118'), findsOneWidget, reason: 'seeded from the latest earlier record');
    await enter(tester, 'Crates', '2');
    await enter(tester, 'Loose eggs', '5');
    expect(find.text('65 eggs'), findsOneWidget);
    await enter(tester, 'Broken eggs', '3');
    await enter(tester, 'Deaths', '1');
    await choose(tester, 'None', 'Layer mash (Kilogram) · 40 in stock · FIFO', within: find.byType(Dialog));
    await enter(tester, 'Consumed', '30');
    expect(find.text('310.00'), findsWidgets);
    await choose(tester, 'None', 'Vitamin mix · 3 in stock · FIFO', which: 1, within: find.byType(Dialog));

    await tester.tap(find.text('Save Production Record'));
    await tester.pumpAndSettle();
    final b = jsonDecode(a.writes.lastWhere((w) => w.url.path == '/api/ProductionRecord').body) as Map;
    expect((b['FlockId'], b['production9AM'], b['totalProduction'], b['brokenEggs']), (7, 65, 65, 3));
    expect((b['noOfBirds'], b['mortality'], b['noOfBirdsLeft'], b['feedKg'], b['medication']), (118, 1, 117, 30, 'None'));
    expect((b['meatyEggs'], b['eggGrade'], b['totalCostOfProduction']), (null, null, 310));
    final feed = (b['feeds'] as List).single as Map;
    expect((feed['specificFeedUsedId'], feed['totalFeedConsumed'], feed['totalFeedCost']), (5, 30, 310));
    expect(b['medications'], isEmpty, reason: 'no quantity on the medication line');
    expect(b['ageInDays'], greaterThan(0));
  });

  testWidgets('edit opens on the saved figures and PUTs', (tester) async {
    final a = api()..gets['/api/ProductionRecord/11'] = rec1;
    await open(tester, ProductionRecordsScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Edit'));
    expect(find.text('Edit Production Record'), findsOneWidget);
    expect(find.text('100 eggs'), findsOneWidget);
    await tester.tap(find.text('Update Production Record'));
    await tester.pumpAndSettle();
    final w = a.writes.last;
    expect((w.method, w.url.path), ('PUT', '/api/ProductionRecord/11'));
    final b = jsonDecode(w.body) as Map;
    expect((b['id'], b['production12PM'], b['eggGrade'], b['medication']), (11, 31, 'Large', 'Vitamins'));
  });

  testWidgets('the full page opens from a link', (tester) async {
    final a = api();
    final s = await sessionFor(a);
    final page = productionScreenForHref('/production-records/new?flockId=8&date=2026-10-06', s, company)!;
    await open(tester, page, size: phone);
    expect(find.text('Record daily egg production data for a flock'), findsOneWidget);
    await see(tester, find.text('Save Production Record'));
    expect(find.text('Cancel'), findsOneWidget);
  });
}
