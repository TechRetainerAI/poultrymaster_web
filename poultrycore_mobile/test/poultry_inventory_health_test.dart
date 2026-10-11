// Poultry → Operations → Inventory & Health, at phone width: Inventory, Stock
// movements, Health Records and Loss & Damage — every dropdown used, and the
// request each save sends.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/inventory/health_records_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/inventory/inventory_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/inventory/loss_records_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/inventory/stock_movements_screen.dart';

import 'support/harness.dart';

final eggs = <String, Object?>{
  'poultryProductId': 1, 'name': 'Eggs', 'productType': 'Eggs', 'isRawEggProduct': true, 'isActive': true, 'stockOnHand': 95, 'unitPrice': 2,
  'createdDate': '2026-09-01T00:00:00',
};
final birds = <String, Object?>{
  'poultryProductId': 2, 'name': 'Birds', 'productType': 'Birds', 'isBirdProduct': true, 'isActive': true, 'stockOnHand': 0, 'unitPrice': 40,
  'createdDate': '2026-10-01T00:00:00',
};
final maize = <String, Object?>{
  'poultryRawMaterialItemId': 5, 'itemName': 'Maize', 'category': 'FeedIngredient', 'unitOfMeasure': 'Kilogram', 'currentQuantity': 10,
  'minimumStockAlert': 50, 'isActive': true, 'createdAt': '2026-09-15T00:00:00',
};

FakeApi api() => FakeApi()
  ..gets['/api/Poultry/products'] = [eggs, birds]
  ..gets['/api/Poultry/raw-material-items'] = [maize]
  ..gets['/api/Poultry/stock/transactions'] = [
    {'poultryStockTransactionId': 1, 'createdDate': '2026-10-03T08:00:00', 'productName': 'Eggs', 'txnType': 'Production', 'quantity': 120, 'unitCost': 1},
    {'poultryStockTransactionId': 2, 'createdDate': '2026-10-04T08:00:00', 'productName': 'Eggs', 'txnType': 'Sale', 'quantity': -25},
  ]
  ..gets['/api/Poultry/raw-material-purchases'] = [
    {'poultryRawMaterialPurchaseId': 9, 'purchaseDate': '2026-10-02T00:00:00', 'itemName': 'Maize', 'quantity': 4, 'unitCost': 300, 'totalCost': 1200},
  ]
  ..gets['/api/Poultry/loss-records'] = [
    {'poultryLossRecordId': 3, 'lossDate': '2026-10-05T00:00:00', 'lossType': 'Spoilage', 'productName': 'Eggs', 'quantity': 12, 'estimatedValue': 24,
      'status': 'Pending', 'reason': 'Heat'},
    {'poultryLossRecordId': 4, 'lossDate': '2026-10-01T00:00:00', 'lossType': 'Theft', 'quantity': 2, 'status': 'Approved'},
  ]
  ..gets['/api/Flock'] = [
    {'flockId': 7, 'name': 'Pen 1'},
    {'flockId': 8, 'name': 'Old pen', 'closedDate': '2026-01-01'},
  ]
  ..gets['/api/House'] = [{'houseId': 2, 'name': 'House A'}]
  ..gets['/api/InventoryItem'] = [{'itemId': 4, 'itemName': 'Wood shavings'}]
  ..gets['/api/Health'] = [
    {'id': 1, 'flockId': 7, 'recordDate': '2026-10-02T00:00:00', 'vaccination': 'Newcastle', 'notes': '[Type:Vaccination] first dose'},
    {'id': 2, 'houseId': 2, 'recordDate': '2026-10-03T00:00:00', 'medication': 'Disinfection', 'notes': '[Type:Treatment]'},
    {'id': 3, 'flockId': 7, 'recordDate': '2026-10-04T00:00:00', 'notes': '[Type:MedicationPhoto] label'},
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

/// Opens the dropdown currently showing [shown] and picks [option].
Future<void> choose(WidgetTester tester, String shown, String option, {Finder? within}) async {
  final label = within == null ? find.text(shown) : find.descendant(of: within, matching: find.text(shown));
  if (within == null) await see(tester, label);
  final sel = find.ancestor(of: label, matching: find.byWidgetPredicate((w) => w is AppSelect)).first;
  await tester.ensureVisible(sel);
  await tester.pumpAndSettle();
  await tester.tap(sel);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Finder get _dialog => find.byType(AlertDialog);

void clearToasts(WidgetTester tester) => tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

Map lastBody(FakeApi a, String path) => jsonDecode(a.writes.lastWhere((w) => w.url.path == path).body) as Map;

void main() {
  test('stock status, crates, links, moves, filters, health rules, routes', () {
    expect(productStockStatus(birds).label, 'Out of stock');
    expect(rawStockStatus(maize).tone, 'low');
    expect(crateEquivalent(95), '3 crates + 5');
    expect(productLink(eggs).label, 'Egg Tracker');
    expect(rawLink(maize).href, '/feed-inventory-tracker?itemId=5');
    final f = InventoryFilters()..status = 'out';
    expect(filterInventoryProducts([eggs, birds], f).single['name'], 'Birds');
    final g = InventoryFilters()..from = '2026-09-10';
    expect(filterInventoryRaw([maize], g).length, 1);

    final moves = buildStockMoves([
      {'poultryStockTransactionId': 1, 'createdDate': '2026-10-03', 'productName': 'Eggs', 'txnType': 'Sale', 'quantity': -3, 'unitCost': 2},
    ], [], [
      {'poultryRawMaterialUsageId': 1, 'usedDate': '2026-10-04', 'itemName': 'Maize', 'quantityUsed': 5},
    ], []);
    expect([for (final m in moves) (m['item'], m['qty'], m['source'])], [('Maize', -5, 'Production Usage'), ('Eggs', -3, 'Sale')]);
    expect(moves.last['total'], 6);
    expect(filterStockMoves(moves, StockMoveFilters()..movement = 'Sale').single['item'], 'Eggs');

    expect(withTypePrefix('Illness', '[Type:Vaccination] cough'), '[Type:Illness] cough');
    expect(parseTypeFromNotes('[type:treatment] x'), 'Treatment');
    expect(lossPayload(lossDate: 'd', lossType: 'Damage', productId: 0, quantity: 0, estimatedValue: 5, reason: '', notes: '')['quantity'], isNull);
    for (final r in ['/poultry-inventory', '/poultry-stock', '/health', '/poultry-loss-records']) {
      expect(pageScreens.containsKey(r), isTrue, reason: r);
    }
  });

  testWidgets('inventory: figures, every filter dropdown, tabs, details link, set product stock', (tester) async {
    final a = api();
    await open(tester, InventoryScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('Poultry inventory'), findsWidgets);
    expect(find.text('95'), findsWidgets, reason: 'total finished stock');
    await see(tester, find.text('95 (3 crates + 5)'));
    expect(find.text('Egg Tracker'), findsOneWidget);

    await choose(tester, 'All statuses', 'Out of stock');
    await see(tester, find.text('Birds'));
    expect(find.text('95 (3 crates + 5)'), findsNothing);
    await choose(tester, 'Out of stock', 'All statuses');
    await choose(tester, 'All categories', 'FeedIngredient');
    expect(find.text('No products match your filters.'), findsOneWidget);
    await tap(tester, find.text('Raw materials'));
    await see(tester, find.text('Maize'));
    expect(find.text('⚠ Low stock'), findsOneWidget);
    expect(find.text('Feed Tracker'), findsOneWidget);
    await tap(tester, find.text('Reset'));

    await tap(tester, find.text('Set product stock'));
    expect(find.text('Stock take — set product stock'), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget, reason: 'bird stock comes from the flocks');
    await tester.enterText(find.descendant(of: _dialog, matching: find.byType(TextField)).at(1), '90');
    await tester.pumpAndSettle();
    expect(find.text('Net -5'), findsOneWidget);
    await tester.tap(find.text('Save corrections'));
    await tester.pumpAndSettle();
    final w = a.writes.lastWhere((x) => x.url.path == '/api/Poultry/products/1/set-stock');
    expect((jsonDecode(w.body) as Map)['targetQuantity'], 90);
  });

  testWidgets('stock movements: filters, cards, new movement with the grouped item list', (tester) async {
    final a = api();
    await open(tester, StockMovementsScreen(session: await sessionFor(a), company: company), size: phone);
    await see(tester, find.textContaining('Production Record', findRichText: true));
    expect(find.textContaining('Qty: -25', findRichText: true), findsOneWidget);
    await choose(tester, 'All movements', 'Sale');
    expect(find.textContaining('Production Record', findRichText: true), findsNothing);
    await choose(tester, 'Sale', 'All movements');
    await choose(tester, 'All types', 'Raw Material');
    await see(tester, find.textContaining('Raw Material Purchase', findRichText: true));
    await choose(tester, 'All items', 'Eggs');
    expect(find.text('No stock movements yet.'), findsOneWidget);

    await tap(tester, find.text('New movement'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pick an item'), findsOneWidget);
    clearToasts(tester);
    await choose(tester, 'Pick a finished product, raw material or supply', 'Maize — FeedIngredient', within: _dialog);
    await choose(tester, 'Increase', 'Damage/Loss', within: _dialog);
    await tester.enterText(find.descendant(of: _dialog, matching: find.byType(TextField)).first, '3');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final b = lastBody(a, '/api/Poultry/raw-material-items/5/adjust');
    expect((b['quantity'], b['movementType'], b['note']), (-3, 'Damage/Loss', 'Manual stock adjustment'));
  });

  testWidgets('health records: tabs, filter dropdowns, create with type, edit keeps the type', (tester) async {
    final a = api();
    await open(tester, HealthRecordsScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('Flock health records'), findsOneWidget);
    expect(find.text('Newcastle'), findsOneWidget);
    expect(find.text('label'), findsNothing, reason: 'medication photo references are hidden');

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await choose(tester, 'All Flocks', 'Pen 1', within: find.byType(BottomSheet));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Newcastle'), findsOneWidget);

    await tap(tester, find.text('House'));
    expect(find.text('Disinfection'), findsOneWidget);
    await tap(tester, find.text('Inventory'));
    expect(find.text('No inventory health records yet'), findsOneWidget);
    await tap(tester, find.text('Add inventory health record'));
    expect(find.text('Record daily health information for your inventory items'), findsOneWidget);
    await tester.tap(find.text('Create Record'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose an inventory item for this record'), findsOneWidget);
    clearToasts(tester);
    await choose(tester, 'Select item', 'Wood shavings', within: _dialog);
    await choose(tester, 'Vaccination', 'Illness', within: _dialog);
    await tester.enterText(find.descendant(of: _dialog, matching: find.byType(TextField)).last, 'mould');
    await tester.tap(find.text('Create Record'));
    await tester.pumpAndSettle();
    final b = lastBody(a, '/api/Health');
    expect((b['ItemId'], b['FlockId'], b['Notes']), (4, null, '[Type:Illness] mould'));

    await tap(tester, find.text('Flock'));
    await tap(tester, find.text('Edit'));
    expect(find.text('Edit Health Record'), findsOneWidget);
    expect(find.descendant(of: _dialog, matching: find.text('Old pen')), findsNothing);
    await tester.tap(find.text('Update Record'));
    await tester.pumpAndSettle();
    final u = a.writes.lastWhere((w) => w.url.path == '/api/Health/1');
    expect((u.method, (jsonDecode(u.body) as Map)['Notes']), ('PUT', '[Type:Vaccination] first dose'));
  });

  testWidgets('loss & damage: cards, approve / unapprove, the form dropdowns, delete', (tester) async {
    final a = api();
    await open(tester, LossRecordsScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('SPOILAGE'), findsOneWidget);
    expect(find.text('GHC 24.00'), findsOneWidget);
    await tap(tester, find.text('Approve'));
    expect(a.writes.last.url.path, '/api/Poultry/loss-records/3/approve');
    clearToasts(tester);
    await tap(tester, find.text('Unapprove'));
    expect(a.writes.last.url.path, '/api/Poultry/loss-records/4/unapprove');
    clearToasts(tester);

    await tap(tester, find.text('New record'));
    await choose(tester, 'Damage', 'MissingStock', within: _dialog);
    await choose(tester, '—', 'Birds', within: _dialog);
    await tester.enterText(find.descendant(of: _dialog, matching: find.byType(TextField)).first, '4');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final b = lastBody(a, '/api/Poultry/loss-records');
    expect((b['lossType'], b['poultryProductId'], b['quantity'], b['estimatedValue']), ('MissingStock', 2, 4, null));
    clearToasts(tester);

    await tap(tester, find.text('Delete'));
    expect(find.text('This removes the pending record.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(a.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/Poultry/loss-records/3'), isTrue);
  });
}
