// Water → Operations → Production → Batch Production (app/water-daily-production):
// the allocation maths, then the list, the Log / Edit form, the record page
// and the allocation workspace at phone width — every dropdown and each body.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';
import 'package:poultrycore_mobile/pages/water/water_batch_production_screen.dart';

import 'support/harness.dart';

final machines = [
  {'waterMachineId': 4, 'machineName': 'Line A', 'capacityPerHour': 300},
  {'waterMachineId': 5, 'machineName': 'Line B', 'capacityPerHour': 100},
];

final pending = <String, Object?>{
  'waterDailyProductionId': 1, 'productionNumber': 'DP-1', 'productionDate': '2026-10-05T00:00:00', 'shift': 'FullDay',
  'machineSelectionType': 'AllMachines', 'waterProductId': 7, 'productName': 'Sachet 500ml', 'status': 'PendingAllocation',
  'bagsProduced': 101, 'sachetsPerBag': 30, 'looseSachetsProduced': 0, 'rejectedSachets': 10, 'damagedBags': 1,
  'packagingRollsUsed': 4, 'electricityCost': 100.01, 'fuelCost': 0, 'laborCost': 0, 'otherProductionCost': 0,
  'rawMaterialCost': 80, 'goodBags': 100, 'allInCost': 180.01, 'costPerBag': 1.8, 'postingVersion': 0,
  'machines': machines,
  'materials': [
    {'waterDailyProductionMaterialId': 21, 'waterRawMaterialItemId': 11, 'itemName': 'Sachet film', 'unitOfMeasure': 'kg',
      'quantityUsed': 4, 'expectedQuantityUsed': 5.05, 'unitCost': 20, 'totalCost': 80},
  ],
  'allocations': <Map>[],
  'postings': <Map>[],
};
final posted = <String, Object?>{
  'waterDailyProductionId': 2, 'productionNumber': 'DP-2', 'productionDate': '2026-10-04T00:00:00', 'productName': 'Sachet 500ml',
  'machineSelectionType': 'CustomMachines', 'machines': machines, 'status': 'Posted', 'bagsProduced': 50, 'goodBags': 50,
  'allInCost': 100, 'costPerBag': 2, 'postingVersion': 1, 'notes': 'smooth day',
  'allocations': [
    {'waterDailyProductionAllocationId': 1, 'waterMachineId': 4, 'machineName': 'Line A', 'bagsProduced': 50, 'rejectedSachets': 0,
      'damagedBags': 0, 'totalProductionCost': 100, 'rawMaterialCost': 0, 'generatedWaterProductionBatchId': 88, 'generatedBatchNumber': 'DP-2-A'},
  ],
  'postings': [
    {'waterDailyProductionPostingId': 1, 'postingVersion': 1, 'batchNumber': 'DP-2-A', 'postedAt': '2026-10-04T10:00:00'},
  ],
};
final draft = <String, Object?>{
  'waterDailyProductionId': 3, 'productionDate': '2026-10-01T00:00:00', 'status': 'Draft', 'machineSelectionType': 'AllMachines',
  'bagsProduced': 10, 'goodBags': 10,
};

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Water/daily-productions'] = [pending, posted, draft]
  ..gets['/api/Water/daily-productions/1'] = pending
  ..gets['/api/Water/daily-productions/2'] = posted
  ..gets['/api/Water/production-batches'] = [
    {'waterMachineId': 4, 'status': 'Approved', 'bagsProduced': 10},
    {'waterMachineId': 5, 'status': 'Approved', 'bagsProduced': 30},
  ]
  ..gets['/api/Water/machines'] = [
    {'waterMachineId': 4, 'machineName': 'Line A', 'status': 'Active', 'capacityPerHour': 300},
    {'waterMachineId': 5, 'machineName': 'Line B', 'status': 'UnderMaintenance', 'capacityPerHour': 100},
  ]
  ..gets['/api/Water/products'] = [
    {'waterProductId': 7, 'name': 'Sachet 500ml'},
  ]
  ..gets['/api/Water/boreholes'] = [
    {'waterBoreholeId': 2, 'boreholeName': 'North borehole'},
  ]
  ..gets['/api/Water/raw-material-items'] = [
    {'waterRawMaterialItemId': 11, 'itemName': 'Sachet film', 'unitOfMeasure': 'kg', 'currentQuantity': 50},
  ]
  ..gets['/api/Water/products/7/recipe'] = {
    'items': [
      {'waterRawMaterialItemId': 11, 'quantityPerOutputUnit': 0.05, 'wasteAllowancePercent': 0, 'latestUnitCost': 20,
        'rawMaterialUnit': 'kg', 'rawMaterialName': 'Sachet film'},
    ],
  }
  ..writeAnswers['/api/Water/daily-productions'] = {'waterDailyProductionId': 1};

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 80 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, 200));
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

Future<void> pick<T>(WidgetTester tester, String shown, String option) async {
  await see(tester, find.text(shown));
  await tester.tap(find.ancestor(of: find.text(shown), matching: find.byType(AppSelect<T>)).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String label, String text) async {
  await see(tester, find.text(label));
  final field = find.descendant(of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.enterText(field.first, text);
  await tester.pumpAndSettle();
}

void clearToasts(WidgetTester tester) =>
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

List<WaterAllocRow> blank() => [for (final m in machines) waterBlankRow(m)];

void main() {
  group('allocation maths', () {
    test('capacity split sums exactly, money at 2dp, materials at 3dp', () {
      final rows = waterApplyMethod('ByMachineCapacity', blank(), pending);
      expect([for (final r in rows) r.v('bagsProduced')], [76, 25]);
      expect([for (final r in rows) r.v('electricityCost')].fold<num>(0, (a, b) => a + b), closeTo(100.01, 1e-9));
      expect([for (final r in rows) r.materialQty[11]], [3, 1]);
      final recon = waterBuildReconciliation(rows, pending);
      expect(recon.balanced, isTrue);
      expect(recon.lines.any((l) => l.key == 'litres'), isFalse, reason: 'blank litres are skipped');
      expect(recon.lines.last.info, isTrue);
    });

    test('recent output weighs, falls back to capacity, Manual leaves the grid', () {
      expect(waterWeightsForMethod('ByPreviousProduction', blank(), {4: 10, 5: 30}), [10, 30]);
      expect(waterWeightsForMethod('ByPreviousProduction', blank(), {}), [300, 100]);
      expect(waterWeightsForMethod('EqualSplit', blank()), [1, 1]);
      final rows = blank();
      expect(identical(waterApplyMethod('Manual', rows, pending), rows), isTrue);
    });

    test('row errors, day cost per bag, the payload', () {
      final r = waterBlankRow(machines.first)..values['bagsProduced'] = 2;
      r.values['damagedBags'] = 3;
      expect(waterRowErrors(r, 30), ['Damaged bags exceed bags produced']);
      final rows = waterApplyMethod('ByMachineCapacity', blank(), pending);
      expect(waterDayCostPerBag(rows, pending), closeTo(180.01 / 100, 1e-9));
      final p = waterRowsToAllocations(rows, pending, 'ByMachineCapacity');
      expect(p.first['allocationMethod'], 'ByMachineCapacity');
      expect((p.first['materials'] as List).single, {
        'waterDailyProductionMaterialId': 21, 'waterRawMaterialItemId': 11, 'itemName': 'Sachet film', 'quantityAllocated': 3,
        'expectedQuantityAllocated': 3.8, 'unitCost': 20,
      });
    });

    test('scope label, status filter', () {
      expect(waterMachineScopeLabel(pending), 'All active machines');
      expect(waterMachineScopeLabel(posted), 'Line A, Line B');
      expect([for (final r in filterWaterDaily([pending, posted, draft], status: 'Posted')) r['productionNumber']], ['DP-2']);
      expect([for (final r in filterWaterDaily([pending, posted, draft], search: 'smooth')) r['productionNumber']], ['DP-2']);
    });
  });

  test('on the sidebar route; the record, edit and allocate pages by link', () async {
    expect(pageScreens.containsKey('/water-daily-production'), isTrue);
    final s = await sessionFor(FakeApi());
    expect(moneyScreenForHref('/water-daily-production/9', s, company), isA<WaterBatchProductionDetailScreen>());
    expect(moneyScreenForHref('/water-daily-production/9/edit', s, company), isA<WaterBatchProductionFormScreen>());
    expect(moneyScreenForHref('/water-daily-production/9/allocate', s, company), isA<WaterBatchAllocateScreen>());
    expect(moneyScreenForHref('/water-daily-production/new', s, company), isA<WaterBatchProductionFormScreen>());
  });

  testWidgets('the list: totals, status filter, actions per status, Reverse confirmation', (tester) async {
    final a = api();
    await open(tester, WaterBatchProductionScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('Days'), findsOneWidget);
    expect(find.text('161'), findsOneWidget, reason: 'bags produced across the three');
    await see(tester, find.text('DP-1'));
    expect(find.text('Pending Allocation'), findsOneWidget);
    expect(find.byTooltip('Allocate across machines'), findsOneWidget);
    await see(tester, find.text('#3'));

    await tap(tester, find.byTooltip('Reverse'));
    expect(find.text("Reverse this day's production?"), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reverse'));
    await tester.pumpAndSettle();
    final w = a.writes.last;
    expect(w.url.path, '/api/Water/daily-productions/2/reverse');
    expect(w.url.queryParameters, {'farmId': 'farm-1', 'reversedBy': 'user-1'});
    expect(find.textContaining('Reverse done'), findsOneWidget);
    clearToasts(tester);

    await pick<String>(tester, 'All statuses', 'Posted');
    expect(find.text('DP-1'), findsNothing);
    await see(tester, find.text('DP-2'));
  });

  testWidgets('Log batch production: scope, recipe seed, validation, the body, on to allocation', (tester) async {
    final a = api();
    await open(tester, WaterBatchProductionFormScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('Log Batch Production'), findsWidgets);
    expect(find.text('1 machine in scope — Line A'), findsOneWidget, reason: 'all ACTIVE machines');

    await tap(tester, find.text('Log batch & allocate'));
    expect(find.textContaining('Bags produced must be greater than zero.'), findsOneWidget);
    clearToasts(tester);

    await pick<String>(tester, 'All active machines', 'Pick machines…');
    await tap(tester, find.text('Line B (UnderMaintenance)', findRichText: true));
    await see(tester, find.text('1 machine in scope — Line B'));
    await pick<String>(tester, 'Not recorded', 'North borehole');
    await pick<String>(tester, 'FullDay', 'Night');
    await enter(tester, 'Bags produced *', '100');
    await enter(tester, 'Damaged bags', '2');
    await enter(tester, 'Electricity', '40');
    await tap(tester, find.text('Seed from recipe'));
    expect(find.textContaining('Scaled to 100 bags'), findsOneWidget);
    clearToasts(tester);
    await see(tester, find.textContaining('Material cost (preview): ', findRichText: true));
    await tap(tester, find.text('Log batch & allocate'));

    final post = a.writes.firstWhere((w) => w.url.path == '/api/Water/daily-productions');
    final b = jsonDecode(post.body) as Map;
    expect((b['status'], b['machineSelectionType'], b['shift'], b['waterProductId'], b['waterBoreholeId']),
        ('PendingAllocation', 'CustomMachines', 'Night', 7, 2));
    expect((b['bagsProduced'], b['damagedBags'], b['electricityCost'], b['sachetsPerBag'], b['estimatedWaterUsedLitres']), (100, 2, 40, 30, null));
    expect((b['machines'] as List).single['waterMachineId'], 5);
    expect((b['materials'] as List).single, containsPair('quantityUsed', 5));
    expect(b['rawMaterialCost'], 100);
    expect(find.textContaining('Batch production logged'), findsOneWidget);
    expect(find.text('Split the batch automatically'), findsOneWidget, reason: 'a new batch opens on the allocation, method picker first');
  });

  testWidgets('Allocate: split by capacity, reconciliation, save and post', (tester) async {
    final a = api();
    await open(tester, WaterBatchAllocateScreen(session: await sessionFor(a), company: company, id: 1), size: phone);
    expect(find.text('Split the batch automatically'), findsOneWidget);
    await tester.tap(find.text('By machine capacity'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Split by machine capacity'), findsOneWidget);
    clearToasts(tester);
    await see(tester, find.textContaining('Balanced — ready to post', findRichText: true));

    await tap(tester, find.text('Reconciliation details'));
    expect(find.text('Raw Material Cost'), findsOneWidget);
    expect(find.text('Info only'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tap(tester, find.text('Post allocation'));
    final save = a.writes.firstWhere((w) => w.url.path == '/api/Water/daily-productions/1/allocation');
    final body = jsonDecode(save.body) as Map;
    expect((body['status'], body['updatedBy']), ('Allocated', 'user-1'));
    expect([for (final r in body['allocations'] as List) r['bagsProduced']], [76, 25]);
    expect(a.writes.last.url.path, '/api/Water/daily-productions/1/post');
    expect(find.textContaining('Batch posted'), findsOneWidget);
  });

  testWidgets('the record page: fields, allocation link, posting history', (tester) async {
    final a = api();
    await open(tester, WaterBatchProductionDetailScreen(session: await sessionFor(a), company: company, id: 2), size: phone);
    expect(find.text('Posted'), findsWidgets);
    expect(find.text('Edit'), findsNothing, reason: 'a posted record cannot be edited');
    expect(find.text('Allocation'), findsNothing);
    expect(find.text('Line A, Line B'), findsOneWidget);
    await see(tester, find.text('Allocation — 1 machine'));
    expect(find.text('DP-2-A'), findsWidgets);
    await see(tester, find.text('live'));
    await see(tester, find.text('smooth day'));
  });
}
