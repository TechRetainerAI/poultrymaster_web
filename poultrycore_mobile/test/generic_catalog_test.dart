// Generic → Catalog at phone width (lib/nav/generic-nav-config.ts): Products,
// Inventory, Stock adjustments and Internal Use, each against a fake API, and
// the menu rows following their module switches.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/generic/generic_inventory_screen.dart';
import 'package:poultrycore_mobile/pages/generic/generic_kit.dart';
import 'package:poultrycore_mobile/pages/generic/generic_products_screen.dart';
import 'package:poultrycore_mobile/pages/generic/generic_stock_adjustments_screen.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart' show pageScreens;
import 'package:poultrycore_mobile/pages/water/water_internal_use_screen.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final generic = Company(farmId: 'g1', name: 'Kofi Shop', type: CompanyType.generic, role: 'Admin');
const base = '/api/generic-company/g1';

final soap = <String, Object?>{
  'genericProductId': 1, 'productName': 'Bar soap', 'sku': 'SP-1', 'unitOfMeasure': 'Piece', 'categoryName': 'Toiletries',
  'costPrice': 4, 'sellingPrice': 6.5, 'openingStock': 10, 'currentStock': 3, 'minimumStockAlert': 5,
  'trackInventory': true, 'isActive': true,
};
final rice = <String, Object?>{
  'genericProductId': 2, 'productName': 'Rice 5kg', 'barcode': '600100', 'unitOfMeasure': 'Bag', 'categoryName': 'Food',
  'costPrice': 80, 'sellingPrice': 95, 'openingStock': 0, 'currentStock': 0, 'minimumStockAlert': 0,
  'trackInventory': true, 'isActive': true,
};
final repair = <String, Object?>{
  'genericProductId': 3, 'productName': 'Repair service', 'costPrice': 0, 'sellingPrice': 50, 'openingStock': 0,
  'currentStock': 0, 'minimumStockAlert': 0, 'trackInventory': false, 'isActive': false,
};

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-11-04', 'companyLocalDateTime': '2026-11-04T10:00:00', 'utcNow': '2026-11-04T10:00:00Z',
  }
  ..gets['$base/products'] = [soap, rice, repair]
  ..gets['$base/inventory/adjustments'] = [
    {'genericStockAdjustmentId': 7, 'genericProductId': 1, 'productName': 'Bar soap', 'adjustmentDate': '2026-11-01T00:00:00',
      'adjustmentType': 'Decrease', 'quantity': 2, 'reason': 'Damaged', 'status': 'Submitted'},
    {'genericStockAdjustmentId': 8, 'genericProductId': 2, 'adjustmentDate': '2026-10-20T00:00:00',
      'adjustmentType': 'Increase', 'quantity': 5, 'reason': 'Found extra stock', 'status': 'Draft', 'notes': 'back store'},
  ]
  ..gets['/api/generic-company/internal-usage'] = [
    {'genericInternalUsageId': 4, 'referenceNo': 'IU-0004', 'usageDate': '2026-11-02T00:00:00', 'category': 'OfficeUse',
      'status': 'Draft', 'totalCostValue': 12, 'recipientName': 'Front office',
      'items': [{'genericProductId': 1, 'productName': 'Bar soap', 'entryQuantity': 3, 'entryUnit': 'Piece', 'entryUnitCost': 4}]},
  ]
  ..gets['/api/generic-company/internal-usage/suggested-cost'] = {'genericProductId': 1, 'unitCost': 4.25};

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

Finder inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> tapIn(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, Finder select, String option) async {
  await tapIn(tester, select);
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Finder selectShowing(String shown) => find.ancestor(of: find.text(shown), matching: find.byType(AppSelect<String>)).first;

Future<void> enterIn(WidgetTester tester, String label, String text) async {
  final field = find.descendant(of: find.ancestor(of: inDialog(find.text(label)), matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.ensureVisible(field.first);
  await tester.enterText(field.first, text);
  await tester.pump();
}

void clearToasts(WidgetTester tester) => tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

void main() {
  tearDown(invalidateGenericModules);

  test('the Catalog menu: first, in the web order, on native screens', () {
    final groups = webNavGroups['generic']!;
    expect(groups.first.title, 'Catalog');
    expect([for (final l in groups.first.subGroups.single.links) (l.label, l.href)], [
      ('Products', '/generic-products'),
      ('Inventory', '/generic-inventory'),
      ('Stock adjustments', '/generic-stock-adjustments'),
      ('Internal Use', '/generic-internal-use'),
    ]);
    final elsewhere = [for (final g in groups.skip(1)) for (final s in g.subGroups) for (final l in s.links) l.href];
    for (final href in ['/generic-products', '/generic-inventory', '/generic-stock-adjustments', '/generic-internal-use']) {
      expect(elsewhere, isNot(contains(href)), reason: '$href only under Catalog');
      expect(pageScreens[href], isNotNull, reason: href);
    }
  });

  testWidgets('a Catalog row goes when its module is switched off, and only then', (tester) async {
    final groups = webNavGroups['generic']!;
    final catalog = gateGenericCatalog(groups, generic);
    expect(catalog.first.subGroups.single.links.length, 4, reason: 'settings not loaded yet: everything shows');
    final a = FakeApi()
      ..gets['$base/module-settings'] = {for (final k in genericModuleKeys) k: true, 'enableInventory': false, 'enableInternalUse': null};
    await tester.runAsync(() async => loadGenericModules(await sessionFor(a), generic));
    final gated = gateGenericCatalog(groups, generic).first.subGroups.single.links.map((l) => l.href);
    expect(gated, ['/generic-products', '/generic-stock-adjustments', '/generic-internal-use']);
  });

  test('filters and statuses', () {
    final ps = [soap, rice, repair];
    expect([for (final p in filterGenericProducts(ps, 'toilet')) p['genericProductId']], [1]);
    expect([for (final p in filterGenericProducts(ps, 'sp-1')) p['genericProductId']], [1]);
    expect([for (final p in ps) genericStockStatus(p)], ['low', 'out', 'na']);
    expect([for (final p in filterGenericInventory(ps, status: 'ok')) p['genericProductId']], [3], reason: 'Not tracked counts as in stock');
    expect([for (final p in filterGenericInventory(ps, search: '600100')) p['genericProductId']], [2], reason: 'barcode');
    expect([for (final p in filterGenericInventory(ps, category: 'Food')) p['genericProductId']], [2]);
    expect(genericQty(1234.56789), '1,234.568');
    final rows = rowsOfApi();
    expect([for (final r in filterGenericAdjustments(rows, search: 'back')) r['genericStockAdjustmentId']], [8]);
    expect([for (final r in filterGenericAdjustments(rows, from: '2026-10-25')) r['genericStockAdjustmentId']], [7]);
    expect(describeWaterInternalQty({'items': [{'entryQuantity': 3, 'entryUnit': 'Piece'}]}, generic: true), '3 pieces');
  });

  testWidgets('Products: list, search, create, edit, delete', (tester) async {
    final a = api()..writeAnswers['$base/products'] = {'genericProductId': 9, 'productName': 'Soap'};
    await open(tester, GenericProductsScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.text('3 product(s)'), findsOneWidget);
    expect(find.text('Low stock'), findsNWidgets(2), reason: 'the web: tracked and stock <= alert, so 0 <= 0 is low');
    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('OK'), findsNothing);
    expect(find.text('n/a'), findsOneWidget, reason: 'the service has no stock');
    expect(find.text('GHS 6.50'), findsOneWidget, reason: "intl puts a no-break space after the code");

    // Create: name required, then the body carries farmId.
    await tap(tester, find.text('New product'));
    expect(find.text('Basics'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Product name is required'), findsOneWidget);
    clearToasts(tester);
    await enterIn(tester, 'Product name *', '  Soap ');
    await enterIn(tester, 'Selling price *', '7.5');
    await enterIn(tester, 'Retail price (optional)', '8');
    await tapIn(tester, inDialog(find.byType(Switch)).first);
    await tapIn(tester, find.widgetWithText(FilledButton, 'Create'));
    final body = a.lastBody('$base/products');
    expect(body['productName'], 'Soap');
    expect(body['farmId'], 'g1');
    expect((body['sellingPrice'], body['retailPrice'], body['wholesalePrice'], body['sku']), (7.5, 8, null, null));
    expect(body['trackInventory'], false);
    expect(body['isActive'], true);
    expect(find.textContaining('Product "Soap" created.'), findsOneWidget);
    clearToasts(tester);

    // Edit: PUT, no farmId.
    await tap(tester, find.widgetWithText(OutlinedButton, 'Edit'));
    expect(find.text('Edit product'), findsOneWidget);
    await tapIn(tester, find.widgetWithText(FilledButton, 'Save changes'));
    final put = a.lastBody('$base/products/1', 'PUT');
    expect(put.containsKey('farmId'), isFalse);
    expect((put['productName'], put['costPrice'], put['minimumStockAlert']), ('Bar soap', 4, 5));
    clearToasts(tester);

    // Delete: the stock warning, then DELETE.
    await tap(tester, find.widgetWithText(OutlinedButton, 'Delete'));
    expect(find.textContaining('"Bar soap" has 3 units in stock.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect((a.writes.last.method, a.writes.last.url.path), ('DELETE', '$base/products/1'));
    expect(find.textContaining('Product deleted'), findsOneWidget);
  });

  testWidgets('Inventory: stats, status and category filters, empty match', (tester) async {
    await open(tester, GenericInventoryScreen(session: await sessionFor(api()), company: generic), size: phone);
    expect(find.text('Total products'), findsOneWidget);
    expect(find.text('Not tracked'), findsOneWidget);
    expect(find.text('Out of stock'), findsWidgets);
    expect(find.text('GHC 12.00'), findsOneWidget, reason: 'stock value at cost: 3 × 4 + 0 × 80');

    await choose(tester, selectShowing('All status'), 'Low stock');
    expect(find.text('Bar soap'), findsOneWidget);
    expect(find.text('Rice 5kg'), findsNothing);
    expect(find.text('Reset extras'), findsOneWidget);
    await choose(tester, selectShowing('All categories'), 'Food');
    expect(find.text('No products match your filters.'), findsOneWidget);
    await tap(tester, find.text('Reset extras'));
    expect(find.text('Rice 5kg'), findsOneWidget);
  });

  testWidgets('Stock adjustments: create & submit, approve, reject with a reason', (tester) async {
    final a = api()..writeAnswers['$base/inventory/adjustments'] = {'genericStockAdjustmentId': 12};
    await open(tester, GenericStockAdjustmentsScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.text('#7 · Bar soap'), findsOneWidget);
    expect(find.text('#8 · Rice 5kg'), findsNothing, reason: 'no productName: falls back to the id');
    expect(find.text('#8 · #2'), findsOneWidget);
    expect(find.text('-2'), findsOneWidget);

    await tap(tester, find.text('New adjustment'));
    await tester.tap(find.widgetWithText(FilledButton, 'Create & submit'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pick a product'), findsOneWidget);
    clearToasts(tester);
    await choose(tester, inDialog(selectShowing('Pick product...')), 'Bar soap – current: 3');
    expect(find.text('Repair service – current: 0'), findsNothing, reason: 'only tracked products');
    await choose(tester, inDialog(selectShowing('Increase (+)')), 'Decrease (−)');
    await enterIn(tester, 'Quantity *', '1.5');
    await choose(tester, inDialog(selectShowing('Select a reason')), 'Expired');
    await tapIn(tester, find.widgetWithText(FilledButton, 'Create & submit'));
    final body = a.lastBody('$base/inventory/adjustments');
    expect((body['genericProductId'], body['adjustmentType'], body['quantity'], body['reason'], body['notes'], body['farmId']),
        (1, 'Decrease', 1.5, 'Expired', null, 'g1'));
    expect(a.writes.last.url.path, '$base/inventory/adjustments/12/submit');
    expect(find.textContaining('Adjustment #12 created and submitted.'), findsOneWidget);
    clearToasts(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Approve'));
    expect(a.writes.last.url.path, '$base/inventory/adjustments/7/approve');
    expect(find.textContaining('Adjustment #7 approved. Stock updated.'), findsOneWidget);
    clearToasts(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Reject'));
    expect(find.text('Adjustment #7 will be rejected. Tell the originator why.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await tester.pumpAndSettle();
    expect(find.text('Rejection reason is required.'), findsOneWidget);
    await choose(tester, selectShowing('e.g. wrong product, count looks off, missing receipt…'), 'Missing entries');
    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await tester.pumpAndSettle();
    expect(jsonDecode(a.writes.last.body), {'rejectionReason': 'Missing entries'});
    expect(a.writes.last.url.path, '$base/inventory/adjustments/7/reject');

    // Draft → Submit; and a status filter reloads.
    await tap(tester, find.widgetWithText(OutlinedButton, 'Submit'));
    expect(a.writes.last.url.path, '$base/inventory/adjustments/8/submit');
    await tap(tester, find.widgetWithText(OutlinedButton, 'Approved'));
    expect(find.widgetWithText(FilledButton, 'Approved'), findsOneWidget);
  });

  testWidgets('Internal Use: the Generic copy — wording, products, suggested cost, save', (tester) async {
    final a = api();
    await open(tester, WaterInternalUseScreen(session: await sessionFor(a), company: generic, generic: true), size: phone);
    expect(find.textContaining('Eggs, birds, feed or supplies used by the farm'), findsOneWidget);
    await see(tester, find.text('Office use · GHC 12.00'));
    expect(find.text('3 pieces'), findsOneWidget, reason: 'Quantity is a detail on Generic');

    await tap(tester, find.text('Record internal use'));
    expect(find.text('How much'), findsOneWidget);
    await choose(tester, inDialog(selectShowing('Pick a product')), 'Bar soap');
    expect(find.text('3 piece in stock'), findsOneWidget);
    expect(find.text("Suggested from the product's cost price — change it if you need to"), findsOneWidget);
    expect(find.text('Pieces each'), findsOneWidget, reason: 'staff mode, unit from the product');
    await enterIn(tester, 'Number of staff', '2');
    await enterIn(tester, 'Pieces each', '1');
    await tapIn(tester, find.widgetWithText(FilledButton, 'Save draft'));
    final body = a.lastBody('/api/generic-company/internal-usage');
    expect(body['items'], [
      {'genericProductId': 1, 'entryQuantity': 2, 'entryUnit': 'Piece', 'quantityPerStaff': 1, 'entryUnitCost': 4.25},
    ]);
    expect((body['staffCount'], body['farmId'], body['createdBy']), (2, 'g1', 'user-1'));
  });
}

List<Map> rowsOfApi() => [for (final r in api().gets['$base/inventory/adjustments']! as List) r as Map];
