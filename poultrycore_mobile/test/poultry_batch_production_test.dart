// Poultry → Operations → Production → Batch Production, at phone width: the
// allocation maths, the list (filters, status-gated actions, confirms), the
// Log Batch Production form and its body, the view and the allocation page.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/production/batch_production_allocate_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/production/batch_production_form.dart';
import 'package:poultrycore_mobile/pages/poultry/production/batch_production_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/production/batch_production_records_screen.dart';

import 'support/harness.dart';

final pending = <String, Object?>{
  'id': 21, 'batchSelectionType': 'SpecificBatch', 'selectedBirdBatchId': 1, 'batchName': null, 'productionDate': '2026-10-05T00:00:00',
  'ageInWeeks': 12, 'ageInDays': 87, 'ageDisplay': '12w 3d', 'firstPickTotal': 60, 'secondPickTotal': 30, 'thirdPickTotal': 10, 'fourthPickTotal': 0,
  'fifthPickTotal': 0, 'sixthPickTotal': 0, 'brokenEggs': 2, 'totalEggs': 100, 'feedKg': 10, 'deaths': 3, 'birdsLeft': 200, 'status': 'PendingAllocation',
  'totalFeedCost': 100, 'totalMedicationCost': 0, 'totalCostOfProduction': 100,
  'includedFlocks': [
    {'flockId': 7, 'flockName': 'Pen 1', 'birdBatchId': 1},
    {'flockId': 8, 'flockName': 'Pen 2', 'birdBatchId': 1},
  ],
  'feeds': [
    {'id': 1, 'itemId': 5, 'itemName': 'Layer mash', 'qty': 10, 'unitCost': 10, 'totalCost': 100},
  ],
  'medications': [],
  'allocations': [],
};
final posted = <String, Object?>{
  ...pending, 'id': 22, 'batchSelectionType': 'AllBatches', 'selectedBirdBatchId': null, 'productionDate': '2026-09-20T00:00:00', 'status': 'Posted',
  'totalEggs': 50, 'firstPickTotal': 50, 'secondPickTotal': 0, 'thirdPickTotal': 0, 'medications': [{'itemId': 7, 'qty': 1}],
  'allocations': [
    {'id': 1, 'flockId': 7, 'flockName': 'Pen 1', 'firstPickEggs': 50, 'secondPickEggs': 0, 'thirdPickEggs': 0, 'fourthPickEggs': 0, 'totalEggs': 50, 'deaths': 3,
      'eggPercentage': 41.67},
  ],
};

FakeApi api() => FakeApi()
  ..gets['/api/ProductionBatchRecord'] = [pending, posted]
  ..gets['/api/ProductionBatchRecord/21'] = pending
  ..gets['/api/ProductionBatchRecord/22'] = posted
  ..gets['/api/ProductionRecord'] = [
    {'id': 1, 'flockId': 7, 'date': '2026-10-01', 'noOfBirds': 120, 'mortality': 0, 'noOfBirdsLeft': 120, 'totalProduction': 90},
    {'id': 2, 'flockId': 8, 'date': '2026-10-01', 'noOfBirds': 80, 'mortality': 0, 'noOfBirdsLeft': 80, 'totalProduction': 10},
  ]
  ..gets['/api/Flock'] = [
    {'flockId': 7, 'name': 'Pen 1', 'batchId': 1, 'quantity': 130, 'active': true, 'startDate': '2026-07-10T00:00:00'},
    {'flockId': 8, 'name': 'Pen 2', 'batchId': 1, 'quantity': 80, 'active': true, 'startDate': '2026-07-10T00:00:00'},
    {'flockId': 9, 'name': 'Pen 3', 'batchId': 2, 'quantity': 40, 'active': true},
    {'flockId': 10, 'name': 'Old pen', 'batchId': 2, 'quantity': 40, 'active': false},
  ]
  ..gets['/api/MainFlockBatch'] = [
    {'batchId': 1, 'batchName': 'Batch A', 'startDate': '2026-07-10T00:00:00'},
    {'batchId': 2, 'batchCode': 'B-002'},
  ]
  ..gets['/api/FarmProductionSettings'] = {'enableFourthPick': false}
  ..gets['/api/Poultry/raw-material-items'] = [
    {'poultryRawMaterialItemId': 5, 'itemName': 'Layer mash', 'category': 'FinishedFeed', 'unitOfMeasure': 'Kilogram', 'currentQuantity': 40, 'isActive': true,
      'usageMethod': 'FIFO'},
  ]
  ..gets['/api/Poultry/raw-material-purchases'] = [
    {'poultryRawMaterialPurchaseId': 1, 'poultryRawMaterialItemId': 5, 'purchaseDate': '2026-09-01', 'remainingQuantity': 2, 'unitCost': 250,
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

Future<void> choose(WidgetTester tester, String shown, String option, {Finder? within}) async {
  final label = within == null ? find.text(shown) : find.descendant(of: within, matching: find.text(shown));
  await see(tester, label);
  final sel = find.ancestor(of: label.first, matching: find.byWidgetPredicate((w) => w is AppSelect)).first;
  await tester.ensureVisible(sel);
  await tester.pumpAndSettle();
  await tester.tap(sel);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String label, String text, {int which = 0}) async {
  await see(tester, find.text(label));
  final f = find.descendant(of: find.ancestor(of: find.text(label).at(which), matching: find.byType(Column)).first, matching: find.byType(TextField));
  await tester.enterText(f.first, text);
  await tester.pumpAndSettle();
}

void main() {
  test('distribution, reconciliation, labels, prefill, routes', () {
    expect(distributeInteger(10, [1, 1, 1]), [4, 3, 3]);
    expect(distributeInteger(100, [120, 80]), [60, 40]);
    expect(distributeDecimal(10, [1, 2]), [3.333, 6.667]);
    expect(batchNameLabel({'batchSelectionType': 'AllBatches'}), 'All Batches');
    expect(batchScopeLabel({'batchSelectionType': 'CustomBatch', 'includedFlocks': [for (var i = 1; i <= 6; i++) {'flockId': i}]}),
        'Flock 1, Flock 2, Flock 3, Flock 4 +2 more');
    expect(batchFilterKey(pending), 'b:1');
    expect(batchFormatAge(posted), 'N/A');
    expect(batchEggPercent(pending), '50.0%');
    expect(batchMedsLabel(posted), '1 item');

    final rows = buildBlankRows(pending, {
      7: {'flockId': 7, 'quantity': 130},
      8: {'flockId': 8, 'quantity': 80},
    }, [
      {'flockId': 7, 'date': '2026-10-01', 'noOfBirds': 120, 'mortality': 0, 'noOfBirdsLeft': 120},
      {'flockId': 8, 'date': '2026-10-01', 'noOfBirds': 80, 'mortality': 0, 'noOfBirdsLeft': 80},
    ]);
    expect([for (final r in rows) r.birdsBefore], [120, 80]);
    final split = applyMethod('ByBirdCount', rows, pending, []);
    expect([for (final r in split) (r.p1, r.p2, r.deaths, r.feedQty[5])], [(36, 18, 2, 6), (24, 12, 1, 4)]);
    expect(buildReconciliation(split, pending).balanced, isTrue);
    split.first.p1 += 1;
    final off = buildReconciliation(split, pending);
    expect(off.balanced, isFalse);
    expect([for (final l in off.lines) if (!l.balanced) l.key], ['p1', 'total']);

    expect(parseMissingProductionPrefill({'date': '2026-10-04', 'flockIds': '7,x,7,8'})?.flockIds, [7, 8]);
    expect(parseMissingProductionPrefill({'flockIds': '7'}), isNull);
    expect(safeReturnPath('//evil'), isNull);
    expect(pageScreens.containsKey('/batch-production-records'), isTrue);
  });

  testWidgets('list: tiles, filters, status actions, cancel confirm', (tester) async {
    final a = api();
    await open(tester, BatchProductionRecordsScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('150'), findsWidgets, reason: 'total eggs');
    expect(find.text('Pending Allocation'), findsWidgets);
    expect(find.text('Pen 1, Pen 2'), findsOneWidget);
    expect(find.text('All active flocks'), findsOneWidget);
    expect(find.text('Allocation'), findsOneWidget);
    expect(find.text('Reverse'), findsOneWidget);

    await tap(tester, find.text('Filters'));
    await choose(tester, 'All Statuses', 'Posted', within: find.byType(BottomSheet));
    await choose(tester, 'All Batches', 'All Batches', within: find.byType(BottomSheet));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Pen 1, Pen 2'), findsNothing);
    await tap(tester, find.text('Filters'));
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();

    await tap(tester, find.text('Cancel').first);
    expect(find.text('Cancel Batch'), findsOneWidget);
    await tester.tap(find.text('Cancel batch'));
    await tester.pumpAndSettle();
    final w = a.writes.last;
    expect((w.url.path, w.url.queryParameters['farmId']), ('/api/ProductionBatchRecord/21/status', company.farmId));
    expect((jsonDecode(w.body) as Map)['status'], 'Cancelled');
    expect(find.text('Done — Status set to Cancelled'), findsOneWidget);

    await tap(tester, find.text('View table format'));
    expect(find.text('4th Pick'), findsNothing, reason: '4th pick is off');
    await see(tester, find.text('Delete Allocation'));
  });

  testWidgets('log batch production: custom scope check, then the body', (tester) async {
    final a = api();
    await open(tester, BatchProductionRecordsScreen(session: await sessionFor(a), company: company), size: phone);
    await tester.tap(find.text('Log Batch Production'));
    await tester.pumpAndSettle();
    expect(find.text('Add Batch Production Record'), findsOneWidget);

    await choose(tester, 'All batches', 'Custom selection', within: find.byType(Dialog));
    expect(find.text('Old pen'), findsNothing, reason: 'only active flocks');
    await tap(tester, find.text('Log Batch Production').last);
    expect(find.text('Select at least one flock for the custom batch.'), findsOneWidget);

    await tap(tester, find.text('Pen 3'));
    await enter(tester, 'Crates', '3');
    expect(find.text('90 eggs'), findsOneWidget);
    await enter(tester, 'Deaths', '2');
    await enter(tester, 'Birds left', '50');
    expect(find.textContaining('more than one egg per bird'), findsOneWidget);
    await choose(tester, 'None', 'Layer mash (Kilogram) · 40 in stock · FIFO', within: find.byType(Dialog));
    await enter(tester, 'Consumed', '5');
    await choose(tester, 'None', 'Layer Feed', within: find.byType(Dialog));
    await tester.tap(find.text('Log Batch Production').last);
    await tester.pumpAndSettle();

    final b = jsonDecode(a.writes.lastWhere((w) => w.url.path == '/api/ProductionBatchRecord').body) as Map;
    expect((b['batchSelectionType'], b['selectedBirdBatchId'], b['ageDisplay'], b['status']), ('CustomBatch', null, 'Mixed', 'PendingAllocation'));
    expect((b['firstPickTotal'], b['totalEggs'], b['deaths'], b['birdsLeft'], b['feedKg'], b['feedType']), (90, 90, 2, 50, 5, 'Layer Feed'));
    expect(b['includedFlocks'], [
      {'flockId': 9, 'flockName': 'Pen 3', 'birdBatchId': 2},
    ]);
    final feed = (b['feeds'] as List).single as Map;
    expect((feed['itemId'], feed['qty'], feed['unitCost'], feed['totalCost'], feed['method']), (5, 5, 10, 50, 'FIFO'));
    expect(b['totalCostOfProduction'], 50);
    expect(find.textContaining('Check the egg count'), findsOneWidget, reason: 'the warning toast shows last');
  });

  testWidgets('allocate: method dialog, by bird count, reconciled, post', (tester) async {
    final a = api();
    await open(tester, BatchAllocateScreen(session: await sessionFor(a), company: company, batchId: 21), size: phone);
    expect(find.text('Choose an allocation method'), findsOneWidget, reason: 'opens on a fresh pending batch');
    await tester.tap(find.text('By Bird Count'));
    await tester.pumpAndSettle();
    expect(find.text('Method: ByBirdCount'), findsOneWidget);
    expect(find.text('✓ Reconciled'), findsOneWidget);

    await tester.tap(find.text('View reconciliation details'));
    await tester.pumpAndSettle();
    expect(find.text('Layer mash (feed)'), findsOneWidget);
    expect(find.text('Info only'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Post Allocation'));
    await tester.pumpAndSettle();
    final save = a.writes.firstWhere((w) => w.url.path == '/api/ProductionBatchRecord/21/allocation');
    final allocs = (jsonDecode(save.body) as Map)['allocations'] as List;
    expect([for (final x in allocs) ((x as Map)['flockId'], x['firstPickEggs'], x['deaths'], x['allocationMethod'])],
        [(7, 36, 2, 'ByBirdCount'), (8, 24, 1, 'ByBirdCount')]);
    expect(((allocs.first as Map)['feeds'] as List).single, containsPair('qty', 6));
    expect(a.writes.last.url.path, '/api/ProductionBatchRecord/21/post');
  });

  testWidgets('view: totals, lines, allocation, delete allocation', (tester) async {
    final a = api();
    await open(tester, BatchProductionDetailScreen(session: await sessionFor(a), company: company, batchId: 22), size: phone);
    expect(find.text('Batch totals'), findsOneWidget);
    expect(find.text('Reverse'), findsOneWidget);
    await see(tester, find.text('Allocation (1 flocks)'));
    await tap(tester, find.text('Delete Allocation'));
    expect(find.text('Delete Posted Allocation?'), findsOneWidget);
    await tester.tap(find.text('Delete and Reverse Allocation'));
    await tester.pumpAndSettle();
    expect((a.writes.last.method, a.writes.last.url.path), ('DELETE', '/api/ProductionBatchRecord/22/allocation'));
    expect(find.textContaining('Allocation deleted'), findsOneWidget);
  });

  testWidgets('links: new with the missing-production prefill', (tester) async {
    final a = api();
    final s = await sessionFor(a);
    final page = batchProductionScreenForHref('/batch-production-records/new?date=2026-10-04&flockIds=7%2C10&source=missing-production', s, company)!;
    await open(tester, page, size: phone);
    expect(find.textContaining('Completing missing production for'), findsOneWidget);
    expect(find.textContaining('1 flagged flock is no longer active'), findsOneWidget);
    expect(find.text('missing'), findsOneWidget);
    expect(batchProductionScreenForHref('/batch-production-records/abc/edit', s, company), isA<BatchProductionRecordPage>());
    expect(batchProductionScreenForHref('/batch-production-records/21/allocate?returnTo=%2Fpoultry-farm-completeness', s, company), isA<BatchAllocateScreen>());
  });
}
