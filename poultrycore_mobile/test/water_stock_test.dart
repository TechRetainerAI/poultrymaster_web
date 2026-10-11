// Water → Operations → Inventory → Stock movement (app/water-stock) and
// Inventory (app/water-inventory) at phone width: filters, the manual/system
// split, New entry for a product and for a raw material, the stock tools on
// their Water setting, and the inventory tabs and statuses.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/water/water_stock_screen.dart';

import 'support/harness.dart';

final products = [
  {'waterProductId': 7, 'name': 'Sachet 500ml', 'unit': 'Bag', 'isSachetProduct': true, 'sachetsPerBag': 30, 'stockOnHand': 40, 'unitPrice': 6, 'sku': 'SW-1'},
  {'waterProductId': 8, 'name': 'Bottle 1.5L', 'unit': 'Bottle', 'stockOnHand': 0, 'unitPrice': 4},
  {'waterProductId': 9, 'name': 'Dispenser', 'unit': 'Unit', 'stockOnHand': 120, 'unitPrice': 30},
];
final raw = [
  {'waterRawMaterialItemId': 11, 'itemName': 'Sachet film', 'category': 'SachetFilm', 'unitOfMeasure': 'kg', 'currentQuantity': 5, 'minimumStockAlert': 10, 'isActive': true},
  {'waterRawMaterialItemId': 12, 'itemName': 'Old caps', 'category': 'Other', 'currentQuantity': 50, 'isActive': false},
];

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Water/stock/transactions'] = [
    {'stockTxnId': 1, 'productName': 'Sachet 500ml', 'txnType': 'Production', 'quantity': 100, 'unitCost': 4.5, 'createdDate': '2026-10-05T08:00:00Z'},
    {'stockTxnId': 2, 'productName': 'Sachet 500ml', 'txnType': 'Restock', 'quantity': 20, 'createdDate': '2026-10-04T08:00:00Z', 'note': 'found in store'},
    {'stockTxnId': 3, 'productName': 'Bottle 1.5L', 'txnType': 'Sale', 'quantity': -12, 'createdDate': '2026-09-01T08:00:00Z'},
  ]
  ..gets['/api/Water/products'] = products
  ..gets['/api/Water/raw-material-items'] = raw
  ..gets['/api/Water/products/reconcile-stock'] = [
    {'productId': 7, 'name': 'Sachet 500ml', 'stockIn': 140, 'stockOut': 100, 'currentStock': 40},
  ];

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

Finder inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> choose<T>(WidgetTester tester, String shown, String option) async {
  final sel = find.ancestor(of: inDialog(find.text(shown)), matching: find.byType(AppSelect<T>)).first;
  await tester.ensureVisible(sel);
  await tester.pumpAndSettle();
  await tester.tap(sel);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> enterIn(WidgetTester tester, String label, String text) async {
  final field = find.descendant(of: find.ancestor(of: inDialog(find.text(label)), matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.ensureVisible(field.first);
  await tester.enterText(field.first, text);
  await tester.pump();
}

void clearToasts(WidgetTester tester) =>
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

void main() {
  group('stock rules', () {
    test('manual vs system, filters, statuses, sachet count', () {
      expect(isWaterManualTxn('Restock'), isTrue);
      expect(isWaterManualTxn('ProductionConsume'), isFalse);
      final rows = [for (final t in api().gets['/api/Water/stock/transactions'] as List) t as Map];
      expect([for (final t in filterWaterStockTxns(rows, source: 'manual')) t['stockTxnId']], [2]);
      expect([for (final t in filterWaterStockTxns(rows, source: 'system', to: '2026-09-30')) t['stockTxnId']], [3]);
      expect(signedQty(-12), '-12');
      expect(waterProductStatus(products[0]).$1, 'Low stock');
      expect(waterProductStatus(products[1]).$1, 'Out of stock');
      expect(waterProductStatus(products[2]).$1, 'In stock');
      expect(waterRawStatus(raw[0]).$1, 'Low stock');
      expect(waterSachetCount(products[0]), 1200);
      expect(waterSachetCount(products[2]), isNull);
    });

    test('both pages on the sidebar', () {
      expect(pageScreens.containsKey('/water-stock'), isTrue);
      expect(pageScreens.containsKey('/water-inventory'), isTrue);
    });
  });

  testWidgets('Stock movement: cards, product + source filters, Recalculate product stock', (tester) async {
    final a = api();
    await open(tester, WaterStockMovementScreen(session: await sessionFor(a), company: company), size: phone);
    await see(tester, find.text('Bottle 1.5L'));
    expect(find.text('-12 qty'), findsOneWidget);
    await pick<String>(tester, 'All entries', 'Manual only');
    expect(find.text('Bottle 1.5L'), findsNothing);
    expect(find.text('found in store'), findsOneWidget);
    await pick<int>(tester, 'All products', 'Sachet 500ml');
    expect(a.requests.lastWhere((r) => r.url.path == '/api/Water/stock/transactions').url.queryParameters['productId'], '7');

    await tap(tester, find.text('Recalculate product stock'));
    await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Recalculate')));
    await tester.pumpAndSettle();
    expect(a.requests.last.url.path, '/api/Water/products/reconcile-stock');
    expect(find.text('140'), findsOneWidget);
  });

  testWidgets('New entry: a product restock and a raw-material adjustment', (tester) async {
    final a = api();
    await open(tester, WaterStockMovementScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('New entry'));
    await tester.tap(inDialog(find.text('Save entry')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pick an item'), findsOneWidget);
    clearToasts(tester);

    await choose<String>(tester, 'Pick a finished product, raw material or supply…', 'Sachet 500ml');
    await enterIn(tester, 'Quantity ', '-5');
    await enterIn(tester, 'Unit cost (optional, for restocks)', '4.2');
    await tester.tap(inDialog(find.text('Save entry')));
    await tester.pumpAndSettle();
    final p = jsonDecode(a.writes.last.body) as Map;
    expect(a.writes.last.url.path, '/api/Water/stock/transactions');
    expect((p['waterProductId'], p['txnType'], p['quantity'], p['unitCost'], p['note']), (7, 'Restock', 5, 4.2, null),
        reason: 'a restock is always units in');
    clearToasts(tester);

    await tap(tester, find.text('New entry'));
    expect(find.text('Old caps — Other'), findsNothing, reason: 'inactive items are left out');
    await choose<String>(tester, 'Pick a finished product, raw material or supply…', 'Sachet film — SachetFilm');
    await choose<String>(tester, 'Restock (add stock)', 'Adjust (signed)');
    await enterIn(tester, 'Quantity (signed)', '-3');
    await tester.tap(inDialog(find.text('Save entry')));
    await tester.pumpAndSettle();
    final r = jsonDecode(a.writes.last.body) as Map;
    expect(a.writes.last.url.path, '/api/Water/raw-material-items/11/adjust');
    expect((r['quantity'], r['movementType'], r['note']), (-3, 'Adjust', 'Manual stock adjustment'));
    expect(find.textContaining('Stock updated'), findsOneWidget);
  });

  testWidgets('Inventory: counts, tabs, statuses, Set product stock', (tester) async {
    final a = api();
    await open(tester, WaterInventoryScreen(session: await sessionFor(a), company: company), size: phone);
    await see(tester, find.text('Total items'));
    expect(find.text('5'), findsOneWidget, reason: '3 products + 2 raw items');
    await see(tester, find.text('Sachet 500ml'));
    expect(find.text('Low stock'), findsWidgets);
    expect(find.text('1,200'), findsOneWidget, reason: 'sachets = bags × 30');
    await tap(tester, find.text('Raw materials'));
    await see(tester, find.text('Sachet film'));
    expect(find.text('Manage raw materials'), findsOneWidget);

    await tap(tester, find.text('Set product stock'));
    final count = find.descendant(of: find.byType(Dialog), matching: find.byType(TextFormField));
    expect(count, findsWidgets);
    await tester.enterText(count.at(1), '35');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save corrections'));
    await tester.pumpAndSettle();
    final w = a.writes.last;
    expect(w.url.path, '/api/Water/products/7/set-stock');
    expect((jsonDecode(w.body) as Map)['targetQuantity'], 35);
  });
}
