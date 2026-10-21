// Restaurant → Inventory (2026-10-21): Ingredients & Stock and Record Purchase
// as `app/restaurant-inventory`, against a fake API at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_inventory_screen.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart' hide enter;

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(390, 4000);

Finder filled(String t) => find.widgetWithText(FilledButton, t);

Future<void> see(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.last);
  await tester.pumpAndSettle();
}

/// The box under [label] (the last one on screen); a required label carries " *".
Future<void> enter(WidgetTester tester, String label, String text) async {
  final re = RegExp('^${RegExp.escape(label)}' r'( \*)?$');
  final l = find.byWidgetPredicate((w) => w is Text && re.hasMatch(w.data ?? w.textSpan?.toPlainText() ?? ''));
  await see(tester, l);
  final box = find.descendant(of: find.ancestor(of: l.last, matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.enterText(box.first, text);
  await tester.pump();
}

final rice = {
  'ingredientId': 1, 'name': 'Rice', 'category': 'Dry Goods', 'unit': 'kg', 'costPerUnit': 2.5, 'currentStock': 40,
  'reorderPoint': 10, 'storageArea': 'Dry Store', 'supplierName': 'Farm Fresh', 'isActive': true, 'isLow': false,
};
final chicken = {
  'ingredientId': 2, 'name': 'Chicken', 'category': 'Proteins', 'unit': 'kg', 'costPerUnit': 8, 'currentStock': 2,
  'reorderPoint': 5, 'isActive': true, 'isLow': true,
};

FakeApi inventoryApi() => FakeApi()
  ..gets['/api/Restaurant/inventory/ingredients'] = [rice, chicken]
  ..gets['/api/Restaurant/inventory/low-stock'] = [chicken]
  ..gets['/api/Restaurant/inventory/waste'] = [
    {'wasteLogId': 1, 'ingredientName': 'Chicken', 'quantity': 1, 'unit': 'kg', 'reason': 'Spoilage', 'costAmount': 8, 'createdAt': '2026-10-20T10:00:00Z'},
  ]
  ..gets['/api/Restaurant/inventory/waste/summary'] = [{'reason': 'Spoilage', 'totalQuantity': 1, 'totalCost': 8, 'count': 1}]
  ..gets['/api/Restaurant/inventory/value'] = [
    {'ingredientId': 1, 'name': 'Rice', 'category': 'Dry Goods', 'unit': 'kg', 'currentStock': 40, 'costPerUnit': 2.5, 'totalValue': 100, 'isLow': false},
    {'ingredientId': 2, 'name': 'Chicken', 'unit': 'kg', 'currentStock': 2, 'costPerUnit': 8, 'totalValue': 16, 'isLow': true},
  ]
  ..gets['/api/Restaurant/setup/suppliers'] = [{'restaurantsupplierid': 7, 'name': 'Farm Fresh', 'category': 'Produce', 'isactive': true}]
  ..gets['/api/Restaurant/purchases'] = [
    {'purchaseId': 31, 'ingredientName': 'Rice', 'purchaseDate': '2026-10-15', 'quantity': 20, 'unit': 'kg', 'unitCost': 2.5, 'totalCost': 50,
      'supplierName': 'Farm Fresh', 'amountPaid': 20, 'allocated': 0, 'balance': 30, 'paymentStatus': 'Partially Paid', 'dueDate': '2026-11-01',
      'costMode': 'EXPENSE_WHEN_CONSUMED', 'status': 'Posted'},
  ]
  ..gets['/api/Restaurant/purchases/cost-recognition'] = [
    {'category': 'Dry Goods', 'ingredientCount': 1, 'costMode': 'EXPENSE_WHEN_CONSUMED'},
    {'category': 'Proteins', 'ingredientCount': 1, 'costMode': 'EXPENSE_WHEN_PURCHASED'},
  ]
  ..gets['/api/Restaurant/finance/accounts'] = [
    {'cashAccountId': 3, 'name': 'Main Cash Box', 'currentBalance': 500, 'isActive': true, 'defaultFor': 'Cash'},
  ];

void main() {
  test('routes, the Inventory menu, filters and the purchase arithmetic', () {
    for (final h in ['/restaurant-inventory', '/restaurant-inventory?purchase=1']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    final inv = webNavGroups['restaurant']!.firstWhere((g) => g.title == 'Inventory').subGroups.first;
    expect([for (final l in inv.links) l.label], ['Ingredients & Stock', 'Record Purchase']);
    expect(filterIngredients([rice, chicken], category: 'Proteins').map((i) => i['name']), ['Chicken']);
    expect(filterIngredients([rice, chicken], search: 'ri').map((i) => i['name']), ['Rice']);
    expect(ingredientFilterCategories([{...rice, 'category': 'Kitchen herbs'}]).contains('Kitchen herbs'), isTrue);
    final a = purchaseMath(quantity: 4, total: 100, method: 'Cash');
    expect((a.unitCost, a.paid, a.balance), (25, 100, 0));
    final b = purchaseMath(quantity: 4, total: 100, method: 'Credit');
    expect((b.paid, b.balance), (0, 100));
    expect(purchaseMath(quantity: 4, total: 100, method: 'Cash', typedPaid: 30).balance, 70);
  });

  testWidgets('Ingredients: stats, the low-stock alert, add, adjust, waste and the other tabs', (tester) async {
    final api = inventoryApi();
    await open(tester, RestaurantInventoryScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('2 ingredients tracked'), findsOneWidget);
    expect(find.textContaining('below reorder point: Chicken', findRichText: true), findsOneWidget);
    expect(find.text('116'), findsOneWidget, reason: 'Inventory Value, toFixed(0)');
    expect(find.text('Low Stock'), findsWidgets);

    await tester.tap(filled('Add Ingredient'));
    await tester.pumpAndSettle();
    await enter(tester, 'Name', 'Tomatoes');
    await enter(tester, 'Cost per Unit', '1.5');
    await enter(tester, 'Opening Stock', '10');
    await pick(tester, 'Select', 'Walk-in Cooler');
    await tester.tap(filled('Add Ingredient').last);
    await tester.pumpAndSettle();
    final b = api.lastBody('/api/Restaurant/inventory/ingredients');
    expect((b['name'], b['category'], b['unit'], b['costPerUnit'], b['currentStock'], b['storageArea'], b['farmId']),
        ('Tomatoes', 'Produce', 'kg', 1.5, 10, 'Walk-in Cooler', 'farm-1'));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Adjust').first);
    await tester.pumpAndSettle();
    await pick(tester, 'Adjustment In (+)', 'Transfer Out (-)');
    await enter(tester, 'Quantity', '3');
    await pick(tester, 'Select destination', 'Donation');
    await tester.tap(filled('Apply'));
    await tester.pumpAndSettle();
    final adj = api.lastBody('/api/Restaurant/inventory/ingredients/1/adjust');
    expect((adj['quantity'], adj['movementType'], adj['reason']), (3, 'TransferOut', 'To: Donation'));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Log Waste'));
    await tester.pumpAndSettle();
    await pick(tester, 'Select ingredient', 'Chicken (2 kg)');
    await enter(tester, 'Quantity', '0.5');
    await tester.tap(filled('Log Waste'));
    await tester.pumpAndSettle();
    final w = api.lastBody('/api/Restaurant/inventory/waste');
    expect((w['ingredientId'], w['quantity'], w['unit'], w['costAmount'], w['reason']), (2, 0.5, 'kg', 4, 'Spoilage'));

    await see(tester, find.text('Waste Log'));
    await tester.tap(find.text('Waste Log').last);
    await tester.pumpAndSettle();
    expect(find.text('Spoilage (1x)'), findsOneWidget);
    await see(tester, find.text('Inventory Value'));
    await tester.tap(find.text('Inventory Value').last);
    await tester.pumpAndSettle();
    expect(find.text('Total value: 116.00'), findsOneWidget);
    await see(tester, find.text('Cost recognition'));
    await tester.tap(find.text('Cost recognition').last);
    await tester.pumpAndSettle();
    await pick(tester, 'Expense when purchased', 'Expense when consumed');
    expect(api.lastBody('/api/Restaurant/purchases/cost-recognition', 'PUT'), {'category': 'Proteins', 'costMode': 'EXPENSE_WHEN_CONSUMED'});
  });

  testWidgets('Record Purchase: the checks, the payment rules, and the body; reverse a purchase', (tester) async {
    final api = inventoryApi();
    await open(tester, RestaurantInventoryScreen(session: await sessionFor(api), company: rest), size: tall);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Record Purchase'));
    await tester.pumpAndSettle();
    await tester.tap(filled('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pick an ingredient or supply'), findsOneWidget);
    await pick(tester, 'Pick item', 'Rice (kg) · Dry Goods');
    expect(find.text('Expense when consumed'), findsOneWidget, reason: "the category's cost recognition");
    await enter(tester, 'Purchase quantity (kg)', '20');
    await enter(tester, 'Total purchase cost', '50');
    expect(find.textContaining('2.50 per kg'), findsOneWidget);
    await pick(tester, 'Cash', 'Credit');
    await tester.tap(filled('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose the supplier'), findsOneWidget, reason: 'on Credit all of it is owed');
    await pick(tester, 'Not linked to a supplier', 'Farm Fresh (Produce)');
    await enter(tester, 'Amount paid', '10');
    expect(find.text('Main Cash Box (GHC 500.00)'), findsOneWidget, reason: "the 'Cash' default account is picked");
    await tester.tap(filled('Save'));
    await tester.pumpAndSettle();
    final p = api.lastBody('/api/Restaurant/purchases');
    expect((p['ingredientId'], p['quantity'], p['totalCost'], p['supplierId'], p['paymentMethod'], p['amountPaid'], p['cashAccountId']),
        (1, 20, 50, 7, 'Credit', 10, 3));

    await see(tester, find.text('Purchases'));
    await tester.tap(find.text('Purchases').last);
    await tester.pumpAndSettle();
    expect(find.text('Partially Paid'), findsOneWidget);
    expect(find.textContaining('owed GHC 30.00'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reverse'));
    await tester.pumpAndSettle();
    await reasonPick(tester, 'Duplicate entry');
    await tester.tap(filled('Reverse'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/purchases/31/reverse'), {'reason': 'Duplicate entry'});
  });

  testWidgets('Deep links: ?purchase=1&itemId= opens Record Purchase on the item; ?purchaseId= shows one purchase', (tester) async {
    final api = inventoryApi();
    await open(tester, RestaurantInventoryScreen(session: await sessionFor(api), company: rest, openPurchase: true, purchaseItemId: 2, purchaseQty: 5),
        size: tall);
    expect(find.text('New purchase'), findsOneWidget);
    expect(find.textContaining('Chicken (kg)'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel').last);
    await tester.pumpAndSettle();

    await open(tester, RestaurantInventoryScreen(session: await sessionFor(api), company: rest, purchaseId: 31), size: tall);
    expect(find.text('Showing purchase PO-31 only'), findsOneWidget);
  });
}
