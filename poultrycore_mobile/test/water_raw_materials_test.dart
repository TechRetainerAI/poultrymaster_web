// Water → Operations → Inventory → Raw materials & supplies
// (app/water-raw-materials) at phone width: the three tabs, the low-stock
// alert, New item, Record purchase with its production conversion, Pay
// balance, the ?purchaseId= focus and the usage history with adjustments.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';
import 'package:poultrycore_mobile/pages/water/water_raw_materials_screen.dart';

import 'support/harness.dart';

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Water/raw-material-items'] = [
    {'waterRawMaterialItemId': 11, 'itemName': 'Sachet film', 'category': 'SachetFilm', 'unitOfMeasure': 'Kilogram', 'purchaseUnitOfMeasure': 'Roll',
      'currentQuantity': 5, 'minimumStockAlert': 10, 'isActive': true, 'usageMethod': 'FIFO'},
    {'waterRawMaterialItemId': 12, 'itemName': 'Outer bags', 'category': 'OuterBag', 'unitOfMeasure': 'Piece', 'currentQuantity': 900,
      'minimumStockAlert': 100, 'isActive': true},
  ]
  ..gets['/api/Water/raw-material-purchases'] = [
    {'waterRawMaterialPurchaseId': 41, 'waterRawMaterialItemId': 11, 'itemName': 'Sachet film', 'supplierName': 'Film Co',
      'purchaseDate': '2026-10-01T00:00:00', 'quantity': 2, 'unitCost': 500, 'totalCost': 1000, 'paymentMethod': 'Credit', 'amountPaid': 0,
      'balance': 1000, 'productionQuantity': 50, 'productionUnit': 'Kilogram', 'productionUnitCost': 20},
    {'waterRawMaterialPurchaseId': 42, 'waterRawMaterialItemId': 12, 'itemName': 'Outer bags', 'supplierName': 'Bag Ltd',
      'purchaseDate': '2026-09-01T00:00:00', 'quantity': 1000, 'unitCost': 0.5, 'totalCost': 500, 'paymentMethod': 'Cash', 'amountPaid': 500, 'balance': 0},
  ]
  ..gets['/api/Water/cash-accounts'] = [
    {'waterCashAccountId': 5, 'accountName': 'Main Cash', 'currentBalance': 900, 'isActive': true},
  ]
  ..gets['/api/Water/suppliers'] = [
    {'waterSupplierId': 3, 'supplierName': 'Film Co', 'supplierType': 'Packaging Supplier'},
  ]
  ..gets['/api/Water/raw-material-usage/history'] = [
    {'waterRawMaterialUsageId': 1, 'waterRawMaterialItemId': 11, 'itemName': 'Sachet film', 'unitOfMeasure': 'Kilogram', 'usedDate': '2026-10-02T00:00:00',
      'quantityUsed': 4.5, 'totalCost': 90, 'batchNumber': 'B-7', 'finishedProductName': 'Sachet 500ml'},
  ]
  ..gets['/api/Water/raw-material-adjustments'] = [
    {'waterRawMaterialAdjustmentId': 9, 'waterRawMaterialItemId': 12, 'itemName': 'Outer bags', 'adjustedDate': '2026-10-03T00:00:00',
      'quantity': 20, 'movementType': 'Return', 'note': 'found'},
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

Finder inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> tapIn(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Future<void> choose<T>(WidgetTester tester, String shown, String option) async {
  await tapIn(tester, find.ancestor(of: inDialog(find.text(shown)), matching: find.byType(AppSelect<T>)));
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> enterIn(WidgetTester tester, String label, String text) async {
  final field = find.descendant(of: find.ancestor(of: inDialog(find.text(label)), matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.ensureVisible(field.first);
  await tester.enterText(field.first, text);
  await tester.pumpAndSettle();
}

void clearToasts(WidgetTester tester) =>
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

Map<String, dynamic> lastBody(FakeApi a) => jsonDecode(a.writes.last.body) as Map<String, dynamic>;

void main() {
  test('helpers, the route and the ?tab= / ?purchaseId= link', () async {
    expect(numText(2.50), '2.5');
    expect(numText(3), '3');
    expect(waterUnitOptions('Drum').first, 'Drum');
    expect(waterUnitOptions('Roll').first, 'Roll');
    final adj = waterAdjustmentAsUsage({'waterRawMaterialAdjustmentId': 9, 'quantity': 20, 'movementType': 'Return', 'note': 'found'});
    expect((adj['waterRawMaterialUsageId'], adj['quantityUsed'], adj['varianceReason']), (-9, -20, 'Manual adjustment (Return) — found'));
    expect(pageScreens.containsKey('/water-raw-materials'), isTrue);
    final s = moneyScreenForHref('/water-raw-materials?tab=purchases&purchaseId=41', await sessionFor(FakeApi()), company);
    expect(((s as WaterRawMaterialsScreen).tab, s.purchaseId), ('purchases', 41));
  });

  testWidgets('Items: low-stock alert, category filter, New item body', (tester) async {
    final a = api();
    await open(tester, WaterRawMaterialsScreen(session: await sessionFor(a), company: company), size: phone);
    await see(tester, find.text('Low-stock items (1)'));
    expect(find.text('Sachet film (5 / min 10)'), findsOneWidget);
    await see(tester, find.text('Outer bags'));

    await tap(tester, find.text('New item'));
    await tapIn(tester, inDialog(find.text('Save')));
    expect(find.textContaining('Item name required'), findsOneWidget);
    clearToasts(tester);
    await enterIn(tester, 'Item name *', 'Chlorine');
    await choose<String>(tester, 'PackagingRoll', 'Chemical');
    await choose<String>(tester, 'Pick a unit', 'Litre');
    await enterIn(tester, 'Minimum stock alert', '4');
    await tapIn(tester, inDialog(find.text('HIFO')));
    await tapIn(tester, inDialog(find.text('Save')));
    final b = lastBody(a);
    expect(a.writes.last.url.path, '/api/Water/raw-material-items');
    expect((b['itemName'], b['category'], b['unitOfMeasure'], b['purchaseUnitOfMeasure'], b['minimumStockAlert'], b['usageMethod'], b['isActive']),
        ('Chlorine', 'Chemical', 'Litre', null, 4, 'HIFO', true));
  });

  testWidgets('Record purchase: conversion maths, cash account rule, the body', (tester) async {
    final a = api();
    await open(tester, WaterRawMaterialsScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Record purchase'));
    expect(find.text('Record raw material purchase'), findsOneWidget);
    await choose<int>(tester, 'Sachet film (Kilogram)', 'Outer bags (Piece)');
    await enterIn(tester, 'Purchase quantity (Piece) *', '10');
    await enterIn(tester, 'Total purchase cost *', '250');
    expect(find.text('GHC 25.00 per Piece'), findsNWidgets(2), reason: 'unit cost = total / quantity; production matches at 1 per unit');
    await enterIn(tester, 'Production-level quantity', '500');
    expect(find.text('GHC 0.50 per Piece'), findsOneWidget, reason: 'production unit cost = total / production quantity');
    await enterIn(tester, 'Amount paid', '100');
    await tapIn(tester, inDialog(find.text('Record purchase')));
    expect(find.textContaining('Pick the cash account to pay from'), findsOneWidget);
    clearToasts(tester);
    await choose<int>(tester, 'Pick account', 'Main Cash (900.00)');
    await choose<int>(tester, 'No supplier / Other', 'Film Co · Packaging Supplier');
    expect(find.textContaining('Balance: ', findRichText: true), findsOneWidget);
    await tapIn(tester, inDialog(find.text('Record purchase')));
    final b = lastBody(a);
    expect(a.writes.last.url.path, '/api/Water/raw-material-purchases');
    expect((b['waterRawMaterialItemId'], b['quantity'], b['totalCost'], b['unitCost'], b['productionUnitsPerPurchaseUnit']), (12, 10, 250, 25, 50));
    expect((b['amountPaid'], b['waterCashAccountId'], b['supplierId'], b['productionUnit'], b['paymentMethod']), (100, 5, 3, 'Piece', 'Cash'));
    expect(find.textContaining('Purchase recorded — stock updated'), findsOneWidget);
  });

  testWidgets('Purchases: the focus banner, Pay balance, usage history merges adjustments', (tester) async {
    final a = api();
    await open(tester, WaterRawMaterialsScreen(session: await sessionFor(a), company: company, tab: 'purchases', purchaseId: 41), size: phone);
    expect(find.textContaining('Showing purchase #41 only — Film Co.', findRichText: true), findsOneWidget);
    expect(find.text('Outer bags'), findsNothing);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Pay balance'));
    await enterIn(tester, 'Amount paid *', '2000');
    await tapIn(tester, inDialog(find.text('Record payment')));
    expect(find.textContaining('Amount exceeds the outstanding balance'), findsOneWidget);
    clearToasts(tester);
    await enterIn(tester, 'Amount paid *', '400');
    await choose<String>(tester, 'Cash', 'MoMo');
    await tapIn(tester, inDialog(find.text('Record payment')));
    final b = lastBody(a);
    expect(a.writes.last.url.path, '/api/Water/raw-material-purchases/41/pay-balance');
    expect((b['amount'], b['paymentMethod']), (400, 'MoMo'));
    clearToasts(tester);
    await tap(tester, find.text('Show all purchases'));
    await see(tester, find.text('Outer bags'));

    await tap(tester, find.text('Usage history'));
    await see(tester, find.text('Sachet film'));
    expect(a.requests.any((r) => r.url.path == '/api/Water/raw-material-adjustments'), isTrue);
    await see(tester, find.textContaining('-20', findRichText: true));
  });
}
