// Poultry → Raw Materials & Supplies, and Purchase → Record Purchase, at
// phone width.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/purchase/raw_material_dialogs.dart';
import 'package:poultrycore_mobile/pages/poultry/purchase/raw_materials_screen.dart';

import 'support/harness.dart';

final maize = <String, Object?>{
  'poultryRawMaterialItemId': 1, 'itemName': 'Maize', 'category': 'FeedIngredient', 'unitOfMeasure': 'Kilogram',
  'purchaseUnitOfMeasure': 'Bag', 'currentQuantity': 500, 'minimumStockAlert': 100, 'isActive': true, 'isLowStock': false,
  'effectiveCostRecognitionMethod': 'EXPENSE_WHEN_CONSUMED', 'costRecognitionSource': 'ItemOverride', 'usageMethod': 'FIFO',
  'costRecognitionOverride': 'EXPENSE_WHEN_CONSUMED',
};
final sacks = <String, Object?>{
  'poultryRawMaterialItemId': 2, 'itemName': 'Egg trays', 'category': 'Packaging', 'unitOfMeasure': 'Piece', 'currentQuantity': 5,
  'minimumStockAlert': 50, 'isActive': true, 'isLowStock': true,
};
final bought = <String, Object?>{
  'poultryRawMaterialPurchaseId': 11, 'poultryRawMaterialItemId': 1, 'itemName': 'Maize', 'supplierName': 'Agro', 'purchaseDate': '2026-10-01T00:00:00',
  'quantity': 10, 'unitOfMeasure': 'Bag', 'productionQuantity': 500, 'productionUnit': 'Kilogram', 'unitCost': 300, 'totalCost': 3000,
  'amountPaid': 2000, 'balance': 1000,
};
final produced = <String, Object?>{
  'poultryRawMaterialPurchaseId': 12, 'poultryRawMaterialItemId': 3, 'itemName': 'Layer mash', 'purchaseDate': '2026-10-02T00:00:00',
  'quantity': 5, 'totalCost': 900, 'amountPaid': 900, 'balance': 0, 'feedProductionRole': 'Produced', 'feedProductionBatchNumber': 'FP-1',
  'sourceFeedProductionBatchId': 4,
};

FakeApi api() => FakeApi()
  ..gets['/api/Poultry/raw-material-items'] = [maize, sacks]
  ..gets['/api/Poultry/raw-material-purchases'] = [bought, produced]
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 5, 'accountName': 'Bank', 'currentBalance': 100, 'isActive': true},
    {'poultryCashAccountId': 6, 'accountName': 'Main Cash Account', 'currentBalance': 900, 'isActive': true},
  ]
  ..gets['/api/Poultry/inventory-valuation'] = {
    'summary': {'operationalValue': 2500, 'itemsWithStock': 2, 'deferredValue': 800, 'itemsDeferring': 1, 'openLots': 3, 'deferredLots': 1},
    'items': [],
    'auditFindings': [{'severity': 'Warning', 'itemName': 'Maize', 'detail': 'Lots do not add up'}],
  }
  ..gets['/api/Poultry/raw-material-usage/history'] = [
    {'poultryRawMaterialUsageId': 1, 'poultryRawMaterialItemId': 1, 'itemName': 'Maize', 'unitOfMeasure': 'Kilogram', 'usedDate': '2026-10-03T00:00:00',
      'quantityUsed': 20, 'expectedQuantityUsed': 18, 'variance': 2},
  ]
  ..gets['/api/Poultry/raw-material-adjustments'] = [
    {'poultryRawMaterialAdjustmentId': 7, 'poultryRawMaterialItemId': 2, 'itemName': 'Egg trays', 'adjustedDate': '2026-10-04T00:00:00', 'quantity': 3,
      'movementType': 'Damage', 'note': 'wet'},
  ];

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
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

void clearToasts(WidgetTester tester) => tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

Finder fieldUnder(String label) =>
    find.descendant(of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first, matching: find.byType(TextField));

void main() {
  test('filters, usage merge, stats, cost recognition, routes', () async {
    expect(filterRawItems([maize, sacks], category: 'Packaging').single['itemName'], 'Egg trays');
    expect(filterRawItems([maize, sacks], unit: 'Bag').single['itemName'], 'Maize', reason: 'matches the purchase unit too');
    expect(filterRawPurchases([bought, produced], search: 'agro').length, 1);
    expect(filterRawPurchases([bought, produced], focusId: 12).single['itemName'], 'Layer mash');
    final u = mergeUsage([], [
      {'poultryRawMaterialAdjustmentId': 7, 'quantity': 3, 'movementType': 'Damage', 'note': 'wet'},
    ]).single;
    expect((u['poultryRawMaterialUsageId'], u['quantityUsed'], u['varianceReason']), (-7, -3, 'Manual adjustment (Damage) — wet'));
    final s = rawStats([maize, sacks], [bought, produced]);
    expect((s.low, s.purchaseTotal, s.outstanding, s.produced), (1, 3000, 1000, 1));
    final d = (feed: expenseWhenConsumed, medication: expenseWhenPurchased);
    expect(effectiveCostRecognition(null, 'FinishedFeed', d).method, expenseWhenConsumed);
    expect(effectiveCostRecognition(null, 'Packaging', d).method, expenseWhenPurchased);
    expect(unitOptions('Drum').first, 'Drum');
    expect(pageScreens.containsKey('/poultry-raw-materials?purchase=1'), isTrue);
    final r = rawMaterialsScreenForHref('/poultry-raw-materials?purchase=1&itemId=1&qty=4', await sessionFor(FakeApi()), company) as RawMaterialsScreen;
    expect((r.openPurchase, r.purchaseItemId, r.purchaseQty), (true, 1, 4));
  });

  testWidgets('summary, items, purchases and usage tabs, pay balance, delete', (tester) async {
    final a = api();
    await open(tester, RawMaterialsScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('ACTIVE ITEMS'), findsOneWidget);
    expect(find.text('need restocking'), findsOneWidget);
    await see(tester, find.textContaining('excludes 1 produced feed lot'));
    await see(tester, find.text('1 stock costing issue(s) found'));
    await see(tester, find.text('Maize'));
    expect(find.textContaining('On use (override)', findRichText: true), findsOneWidget);
    expect(find.byTooltip("Track this item's movements"), findsOneWidget, reason: 'feed items only');

    await tap(tester, find.text('Purchases'));
    await see(tester, find.text('Produced · FP-1'));
    expect(find.byTooltip('Open the feed production batch'), findsOneWidget);
    await tap(tester, find.byTooltip('Pay balance'));
    expect(find.text('Outstanding: GHC 1,000.00'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first, '1500');
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Amount exceeds the outstanding balance (GHC 1,000.00)'), findsOneWidget);
    clearToasts(tester);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first, '400');
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    final w = a.writes.lastWhere((x) => x.url.path == '/api/Poultry/raw-material-purchases/11/pay-balance');
    expect((jsonDecode(w.body) as Map)['amount'], 400);
    clearToasts(tester);

    await tap(tester, find.byIcon(Icons.delete_outline));
    expect(find.text('This will reverse the stock it added.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(a.writes.any((x) => x.method == 'DELETE' && x.url.path == '/api/Poultry/raw-material-purchases/11'), isTrue);
    expect(find.textContaining('Deleted'), findsOneWidget);

    await tap(tester, find.text('Usage History'));
    await see(tester, find.textContaining('Manual adjustment (Damage) — wet', findRichText: true));
    expect(find.text('Usage History'), findsWidgets);
  });

  testWidgets('record purchase from the menu: defaults, auto paid, credit, the body', (tester) async {
    final a = api();
    await open(tester, RawMaterialsScreen(session: await sessionFor(a), company: company, openPurchase: true, purchaseItemId: 1, purchaseQty: 4),
        size: phone);
    expect(find.text('New raw material purchase'), findsOneWidget);
    await see(tester, find.text('Main Cash Account (GHC 900.00)'));
    await see(tester, find.text('Total purchase cost *'));
    await tester.enterText(fieldUnder('Total purchase cost *'), '1200');
    await tester.pumpAndSettle();
    expect(find.text('GHC 300.00 per Bag'), findsOneWidget, reason: '1200 / 4 bags');
    await see(tester, find.text('Production units per purchase unit'));
    await tester.enterText(fieldUnder('Production units per purchase unit'), '50');
    await tester.pumpAndSettle();
    expect(find.text('GHC 6.00 per Kilogram'), findsOneWidget, reason: '1200 / 200 kg');

    await see(tester, find.text('Payment method'));
    await tester.tap(find.ancestor(of: find.text('Cash'), matching: find.byType(AppSelect<String>)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credit').last);
    await tester.pumpAndSettle();
    await see(tester, find.text('Balance (auto)'));
    expect(find.text('GHC 1,200.00'), findsWidgets, reason: 'nothing paid on credit');

    await tap(tester, find.text('Save'));
    final b = jsonDecode(a.writes.lastWhere((w) => w.url.path == '/api/Poultry/raw-material-purchases').body) as Map;
    expect((b['poultryRawMaterialItemId'], b['quantity'], b['totalCost'], b['unitCost'], b['productionUnitsPerPurchaseUnit']), (1, 4, 1200, 300, 50));
    expect((b['paymentMethod'], b['amountPaid'], b['poultryCashAccountId'], b['createdBy']), ('Credit', 0, 6, 'user-1'));
    expect(find.textContaining('Purchase recorded'), findsOneWidget);
  });

  testWidgets('new item: usage order, cost recognition, the body', (tester) async {
    final a = api()
      ..gets['/api/Poultry/financial-settings/cost-recognition'] = {
        'feedCostRecognitionMethod': 'EXPENSE_WHEN_CONSUMED',
        'medicationCostRecognitionMethod': 'EXPENSE_WHEN_PURCHASED',
      };
    await open(tester, RawMaterialsScreen(session: await sessionFor(a), company: company), size: phone);
    await tester.tap(find.text('New Item'));
    await tester.pumpAndSettle();
    expect(find.text('New raw material item'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Item name is required'), findsOneWidget);
    clearToasts(tester);
    await tester.enterText(fieldUnder('Item name *'), 'Soya');
    expect(find.text('HIFO'), findsOneWidget, reason: 'feed ingredients choose a usage order');
    expect(find.textContaining('currently expense when consumed'), findsOneWidget);
    expect(find.text(deferredActiveNote), findsOneWidget);
    await tester.ensureVisible(find.text('LIFO'));
    await tester.tap(find.text('LIFO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final b = jsonDecode(a.writes.lastWhere((w) => w.url.path == '/api/Poultry/raw-material-items').body) as Map;
    expect((b['itemName'], b['category'], b['usageMethod'], b['costRecognitionOverride'], b['setCostRecognitionOverride']),
        ('Soya', 'FeedIngredient', 'LIFO', null, true));
  });
}
