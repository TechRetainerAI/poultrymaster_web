// Water → Operations → Production → Water Production
// (app/water-production-batches): the rules, then the list, the Record /
// Edit form and the Details page at phone width — every dropdown, the
// raw-materials section and each request body.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';
import 'package:poultrycore_mobile/pages/water/water_production_screen.dart';

import 'support/harness.dart';

final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);

final draft = <String, Object?>{
  'waterProductionBatchId': 1, 'batchNumber': 'B-1', 'productionDate': '${today}T00:00:00', 'shift': 'Morning',
  'waterMachineId': 4, 'machineName': 'Line A', 'machineScope': 'SingleMachine', 'waterProductId': 7, 'productName': 'Sachet 500ml',
  'bagsProduced': 100, 'sachetsPerBag': 30, 'damagedBags': 2, 'rejectedSachets': 5, 'electricityCost': 10, 'status': 'Draft',
  'allInCost': 490, 'costPerBag': 5, 'notes': 'first run',
};
final approved = <String, Object?>{
  'waterProductionBatchId': 2, 'batchNumber': 'B-2', 'productionDate': '${today}T00:00:00', 'machineScope': 'AllMachines',
  'bagsProduced': 50, 'goodBags': 48, 'damagedBags': 2, 'sachetsPerBag': 30, 'status': 'Approved', 'allInCost': 240, 'costPerBag': 5,
};
final child = <String, Object?>{
  'waterProductionBatchId': 3, 'batchNumber': 'DP-3', 'productionDate': '2026-01-05T00:00:00', 'bagsProduced': 20,
  'sachetsPerBag': 30, 'status': 'Approved', 'sourceType': 'DailyProductionAllocation', 'waterDailyProductionId': 9,
};

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Water/production-batches'] = [draft, approved, child]
  ..gets['/api/Water/machines'] = [
    {'waterMachineId': 4, 'machineName': 'Line A', 'status': 'Active'},
    {'waterMachineId': 5, 'machineName': 'Old line', 'status': 'Retired'},
  ]
  ..gets['/api/Water/products'] = [
    {'waterProductId': 8, 'name': 'Film roll', 'productType': 'RawMaterial', 'isActive': true},
    {'waterProductId': 7, 'name': 'Sachet 500ml', 'productType': 'FinishedGood', 'isActive': true},
  ]
  ..gets['/api/Water/raw-material-items'] = [
    {'waterRawMaterialItemId': 11, 'itemName': 'Sachet film', 'unitOfMeasure': 'kg', 'currentQuantity': 50, 'isActive': true},
    {'waterRawMaterialItemId': 12, 'itemName': 'Outer bags', 'unitOfMeasure': 'pcs', 'currentQuantity': 900, 'isActive': true},
  ]
  ..gets['/api/Water/raw-material-items/open-lots'] = [
    {'waterRawMaterialItemId': 11, 'waterRawMaterialPurchaseId': 91, 'remainingProductionQuantity': 4, 'productionUnitCost': 10,
      'productionUnitsPerPurchaseUnit': 1, 'purchaseDate': '2026-09-01', 'supplierName': 'Film Co', 'usageMethod': 'FIFO'},
    {'waterRawMaterialItemId': 11, 'waterRawMaterialPurchaseId': 92, 'remainingProductionQuantity': 10, 'productionUnitCost': 20,
      'productionUnitsPerPurchaseUnit': 1, 'purchaseDate': '2026-09-10', 'supplierName': 'Film Co', 'usageMethod': 'FIFO'},
  ]
  ..gets['/api/Water/products/7/recipe'] = {
    'items': [
      {'waterRawMaterialItemId': 11, 'quantityPerOutputUnit': 0.05, 'wasteAllowancePercent': 10, 'latestUnitCost': 20,
        'rawMaterialUnit': 'kg', 'rawMaterialStock': 50, 'rawMaterialName': 'Sachet film'},
    ],
  }
  ..gets['/api/Water/production-batches/1/materials'] = [
    {'waterRawMaterialUsageId': 1, 'waterRawMaterialItemId': 11, 'itemName': 'Sachet film', 'unitOfMeasure': 'kg',
      'expectedQuantityUsed': 5.5, 'quantityUsed': 6, 'unitCost': 15, 'totalCost': 90, 'variance': 0.5, 'currentStock': 50},
  ]
  ..gets['/api/Water/production-batches/1'] = draft
  ..gets['/api/Water/production-batches/1/linked-stock-txns'] = [
    {'waterStockTransactionId': 1, 'productName': 'Sachet 500ml', 'txnType': 'ProductionIn', 'quantity': 98, 'unitCost': 5,
      'createdAt': '2026-10-06T09:00:00Z', 'note': 'Batch B-1'},
  ]
  ..gets['/api/Water/production-batches/1/linked-expenses'] = <Map>[]
  ..gets['/api/Water/production-batches/1/linked-losses'] = [
    {'waterProductionLossId': 1, 'lossType': 'Damaged', 'lossDate': '2026-10-06T00:00:00', 'status': 'Posted', 'bagsLost': 2,
      'sachetsLost': 5, 'bagsLossValue': 10, 'sachetsLossValue': 1, 'totalValue': 11},
  ]
  ..writeAnswers['/api/Water/production-batches'] = {'waterProductionBatchId': 44};

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

void main() {
  group('production rules', () {
    test('the draw walks lots in order and blends the price', () {
      final lots = [for (final l in api().gets['/api/Water/raw-material-items/open-lots'] as List) l as Map];
      final p = planWaterDraw(lots, 6);
      expect((p.available, p.drawn, p.shortfall, p.totalCost, p.takes.length), (14, 6, 0, 80, 2));
      expect(p.unitCost, closeTo(13.333, .001));
      final short = planWaterDraw(lots, 20);
      expect((short.drawn, short.shortfall), (14, 6));
      expect(planWaterDraw(lots, 0).takes, isEmpty);
      expect(waterLotsForItem(lots, 12), isEmpty);
    });

    test('recipe rows, totals, filters, the batch number', () {
      final r = waterRecipeRow((api().gets['/api/Water/products/7/recipe'] as Map)['items'][0] as Map, 100, const []);
      expect((r.expected, r.actual, r.unitCost, r.unit, r.name), (5.5, 5.5, 20, 'kg', 'Sachet film'));
      final t = waterProductionTotals([draft, approved, child], today);
      expect((t.todayBags, t.draftCount), (48, 1));
      expect(isDailyProductionChild(child), isTrue);
      expect(isDailyProductionChild(draft), isFalse);
      expect([for (final b in filterWaterBatches([draft, approved, child], search: 'first')) b['batchNumber']], ['B-1']);
      expect([for (final b in filterWaterBatches([draft, approved, child], to: '2026-01-31')) b['batchNumber']], ['DP-3']);
      expect(makeWaterBatchNumber(DateTime(2026, 5, 24, 9, 30, 15)), 'B-20260524-093015');
    });
  });

  test('on the sidebar route, and a record by link', () async {
    expect(pageScreens.containsKey('/water-production-batches'), isTrue);
    final s = moneyScreenForHref('/water-production-batches/1', await sessionFor(FakeApi()), company);
    expect((s as WaterProductionDetailScreen).batchId, 1);
  });

  testWidgets('the list: figures, cards, the actions each status allows', (tester) async {
    final a = api();
    await open(tester, WaterProductionScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('3 production records on file.'), findsOneWidget);
    expect(find.text("Today's bags (good)"), findsOneWidget);
    expect(find.text('48'), findsWidgets);
    expect(find.text('Pending approval'), findsOneWidget);
    await see(tester, find.text('B-1 · 98 good bags'));
    expect(find.text('All Machines'), findsOneWidget);
    await see(tester, find.text('DP-3 · 20 good bags'));
    expect(find.text('Open batch production'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget, reason: 'only the Draft');
    expect(find.text('Reopen'), findsOneWidget, reason: 'the approved manual record, not the day child');

    await tap(tester, find.widgetWithText(OutlinedButton, 'Approve'));
    final w = a.writes.last;
    expect(w.url.path, '/api/Water/production-batches/1/approve');
    expect(w.url.queryParameters, {'farmId': 'farm-1', 'approvedBy': 'user-1'});
    expect(find.textContaining('Batch approved — bags added to inventory'), findsOneWidget);
    clearToasts(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Reopen'));
    expect(find.textContaining('will subtract its 48 good bags from stock'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reopen'));
    await tester.pumpAndSettle();
    expect(a.writes.last.url.path, '/api/Water/production-batches/2/reopen');
    expect(find.textContaining('Production record reopened — back to Draft'), findsOneWidget);
  });

  testWidgets('Record production: recipe, dropdowns, materials, override, Save & Approve', (tester) async {
    final a = api();
    await open(tester, WaterProductionScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Record production'));
    expect(find.text('Record production'), findsWidgets);
    await see(tester, find.text('✓ Using expected quantities'));
    expect(a.requests.any((r) => r.url.path == '/api/Water/products/7/recipe'), isTrue,
        reason: 'the first active finished good is preselected, not the raw-material product listed first');

    await tap(tester, find.text('Save & Approve'));
    expect(find.textContaining('Bags produced must be greater than zero'), findsOneWidget);
    clearToasts(tester);

    await enter(tester, 'Produced bags *', '100');
    await tap(tester, find.text('Use expected'));
    expect(find.text('5.5'), findsWidgets, reason: '100 bags × 0.05 kg × 1.10');
    await see(tester, find.text('blended over 2 purchase batches'));
    await pick<String>(tester, 'Line A', 'All Machines / Combined');
    await pick<String>(tester, 'Morning', 'Night');
    await enter(tester, 'Damaged bags', '4');
    await enter(tester, 'Electricity', '50');

    await tap(tester, find.text('Add material'));
    await see(tester, find.text('Outer bags'));
    await tap(tester, find.text('Save & Approve'));
    expect(find.textContaining('Some materials are missing'), findsOneWidget, reason: 'the added row has zero usage');
    clearToasts(tester);
    await tap(tester, find.text('Save anyway (override) — some required materials have zero usage'));
    await see(tester, find.textContaining('Good bags: 96', findRichText: true));
    await tap(tester, find.text('Save & Approve'));

    final post = a.writes.firstWhere((w) => w.url.path == '/api/Water/production-batches');
    final b = jsonDecode(post.body) as Map;
    expect((b['bagsProduced'], b['damagedBags'], b['shift'], b['machineScope'], b['waterMachineId'], b['waterProductId']),
        (100, 4, 'Night', 'AllMachines', null, 7));
    expect((b['electricityCost'], b['sachetsPerBag'], b['createdBy'], b['farmId']), (50, 30, 'user-1', 'farm-1'));
    expect(b['materialsUsed'], [
      {'waterRawMaterialItemId': 11, 'quantityUsed': 5.5, 'expectedQuantityUsed': 5.5, 'unitCost': 20},
      {'waterRawMaterialItemId': 12, 'quantityUsed': 0, 'expectedQuantityUsed': 0, 'unitCost': 0},
    ]);
    expect(a.writes.last.url.path, '/api/Water/production-batches/44/approve');
    expect(find.textContaining('Production saved & approved'), findsOneWidget);
  });

  testWidgets('Edit loads the recorded materials and PUTs the draft', (tester) async {
    final a = api();
    await open(tester, WaterProductionScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Edit'));
    expect(find.text('Edit production record'), findsOneWidget);
    await see(tester, find.text('Sachet film'));
    expect(find.text('5.5'), findsWidgets, reason: 'expected from the saved row');
    await pick<int>(tester, 'Sachet film', 'Outer bags');
    await tap(tester, find.text('Save changes'));
    final put = a.writes.singleWhere((w) => w.method == 'PUT');
    expect(put.url.path, '/api/Water/production-batches/1');
    final b = jsonDecode(put.body) as Map;
    expect((b['waterProductionBatchId'], b['batchNumber'], b['notes']), (1, 'B-1', 'first run'));
    expect((b['materialsUsed'] as List).single, {'waterRawMaterialItemId': 12, 'quantityUsed': 6, 'expectedQuantityUsed': 5.5, 'unitCost': 15});
    expect(find.textContaining('Production record updated'), findsOneWidget);
  });

  testWidgets('Details: figures, sections, the linked records', (tester) async {
    final a = api();
    await open(tester, WaterProductionDetailScreen(session: await sessionFor(a), company: company, batchId: 1), size: phone);
    expect(find.text('Back to production'), findsOneWidget);
    expect(find.text('Produced $today · Morning · Sachet 500ml'), findsOneWidget);
    expect(find.text('GOOD BAGS'), findsOneWidget);
    await see(tester, find.text('Batch information'));
    await see(tester, find.textContaining('Variance: 0.5', findRichText: true));
    await see(tester, find.text('ProductionIn'));
    expect(find.text('No production-linked expenses for this batch.'), findsOneWidget);
    await see(tester, find.text('Damaged'));
    await see(tester, find.text('first run'));
  });
}
