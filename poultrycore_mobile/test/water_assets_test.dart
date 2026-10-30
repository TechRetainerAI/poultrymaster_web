// Water → Expenses → Capital Investments/Assets (app/water-assets): the
// Poultry register on AssetRail.water at phone width — Water's wording, the
// table on every width, the supplier picker and the Credit rule in New asset,
// the supplier picker in Add cost, and the asset page's two Water notes.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/asset_detail_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/asset_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/assets_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';

import 'support/harness.dart';

final borehole = <String, Object?>{
  'waterCapitalAssetId': 1, 'assetNumber': 'WA-0001', 'assetName': 'Borehole 1', 'waterAssetCategoryId': 2,
  'categoryName': 'Boreholes', 'location': 'Yard', 'status': 'Active', 'acquisitionDate': '2026-01-10T00:00:00',
  'createdAt': '2026-01-10T09:00:00Z', 'acquisitionCost': 10000, 'additionalCost': 2000, 'totalCapitalizedCost': 12000,
  'residualValue': 0, 'depreciableAmount': 12000, 'usefulLifeMonths': 120, 'monthlyDepreciation': 100,
  'accumulatedDepreciation': 0, 'currentBookValue': 12000, 'depreciationEntries': 0,
  'inServiceDate': '2026-02-01T00:00:00', 'supplierName': 'DrillCo', 'createdBy': 'Ama', 'costEntries': 2,
};

final machine = <String, Object?>{
  'waterCapitalAssetId': 2, 'assetNumber': 'WA-0002', 'assetName': 'Sachet machine', 'waterAssetCategoryId': 3,
  'categoryName': 'Machinery', 'status': 'Active', 'acquisitionDate': '2025-06-01T00:00:00', 'acquisitionCost': 5000,
  'additionalCost': 0, 'totalCapitalizedCost': 5000, 'residualValue': 500, 'usefulLifeMonths': 60, 'monthlyDepreciation': 75,
  'accumulatedDepreciation': 900, 'currentBookValue': 4100, 'depreciationEntries': 12,
};

final fullBorehole = {
  ...borehole,
  'costs': [
    {'waterCapitalAssetCostId': 11, 'costDate': '2026-01-10T00:00:00', 'description': 'Drilling', 'sourceType': 'Acquisition',
      'amount': 10000, 'status': 'Posted', 'paymentStatus': 'Paid', 'paymentMethod': 'Cash', 'waterExpenseId': 501},
    {'waterCapitalAssetCostId': 12, 'costDate': '2026-03-02T00:00:00', 'description': 'Submersible pump', 'costCategory': 'Equipment',
      'sourceType': 'AdditionalCost', 'amount': 2000, 'status': 'Posted', 'paymentStatus': 'Partial', 'balance': 500,
      'supplierName': 'Pumps Ltd'},
  ],
  'depreciation': [
    {'waterAssetDepreciationId': 31, 'periodStart': '2026-02-01', 'amount': 100, 'sourceType': 'Monthly', 'status': 'Posted',
      'accumulatedAfter': 100, 'bookValueAfter': 11900, 'waterExpenseId': 601},
  ],
};

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Water/assets'] = [borehole, machine]
  ..gets['/api/Water/assets/categories'] = [
    {'waterAssetCategoryId': 2, 'categoryName': 'Boreholes', 'defaultUsefulLifeMonths': 240},
    {'waterAssetCategoryId': 3, 'categoryName': 'Machinery', 'defaultUsefulLifeMonths': 60},
  ]
  ..gets['/api/Water/assets/summary'] = {
    'totalAssetCost': 17000, 'accumulatedDepreciation': 900, 'currentBookValue': 16100, 'addedInPeriod': 2000, 'addedCount': 1,
    'activeAssets': 2, 'draftAssets': 0, 'fullyDepreciated': 0,
  }
  ..gets['/api/Water/asset-depreciation/due'] = <Map>[]
  ..gets['/api/Water/cash-accounts'] = [
    {'waterCashAccountId': 5, 'accountName': 'Main Cash', 'isActive': true},
  ]
  ..gets['/api/Water/suppliers'] = [
    {'waterSupplierId': 8, 'supplierName': 'DrillCo', 'isActive': true},
    {'waterSupplierId': 9, 'supplierName': 'Gone Ltd', 'isActive': true, 'isDeleted': true},
  ]
  ..gets['/api/Water/assets/1'] = fullBorehole;

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

Future<void> choose(WidgetTester tester, String shown, String option) async {
  await tapIn(tester, find.ancestor(of: inDialog(find.text(shown)), matching: find.byType(AppSelect<String>)).first);
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> enterIn(WidgetTester tester, String label, String text) async {
  final field = find.descendant(
    of: find.ancestor(of: inDialog(find.text(label)), matching: find.byType(Column)).first,
    matching: find.byType(TextFormField),
  );
  await tester.enterText(field.first, text);
  await tester.pump();
}

void clearToasts(WidgetTester tester) =>
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

Map<String, dynamic> body(FakeApi a, String path, [String method = 'POST']) =>
    jsonDecode(a.writes.lastWhere((w) => w.url.path == path && w.method == method).body) as Map<String, dynamic>;

/// The table's row action, by its tooltip (the Water page has no cards).
Future<void> rowAction(WidgetTester tester, String tooltip, {int row = 0}) async {
  await see(tester, find.byTooltip(tooltip));
  await tapIn(tester, find.byTooltip(tooltip).at(row));
}

void main() {
  test('the rail: endpoints, keys, links and the word', () {
    const r = AssetRail.water;
    expect((r.api, r.assetIdKey, r.categoryIdKey, r.costIdKey, r.depreciationIdKey, r.cashAccountIdKey, r.expenseIdKey),
        ('/api/Water', 'waterCapitalAssetId', 'waterAssetCategoryId', 'waterCapitalAssetCostId', 'waterAssetDepreciationId', 'waterCashAccountId', 'waterExpenseId'));
    expect((r.assetsHref, r.expensesHref, r.title), ('/water-assets', '/water-expenses', 'Assets'));
    expect(r.t(bookValueTooltip), startsWith('What the asset is still worth on the books'));
    expect(r.t('Investment name'), 'Asset name');
    expect(AssetRail.poultry.t('Investment name'), 'Investment name');
    final p = newAssetPreview('6000', '', '', '0', credit: true);
    expect((p.paid, p.owing), (0, 6000), reason: 'a blank Credit bill is unpaid');
    expect(newAssetPreview('6000', '', '', '0').paid, 6000);
  });

  test('on the sidebar route, and the asset page by link', () async {
    expect(pageScreens.containsKey('/water-assets'), isTrue);
    final s = moneyScreenForHref('/water-assets/1', await sessionFor(FakeApi()), company);
    expect(((s as AssetDetailScreen).assetId, s.rail), (1, AssetRail.water));
  });

  testWidgets('Water wording, the table on a phone, the history panel', (tester) async {
    final a = api();
    await open(tester, AssetsScreen(session: await sessionFor(a), company: company, rail: AssetRail.water), size: phone);

    expect(find.text('Assets'), findsWidgets);
    expect(find.text('Track major long-term business assets, their cost, depreciation, and current book value.'), findsOneWidget);
    expect(find.text('New asset'), findsOneWidget);
    expect(find.text('TOTAL ASSET COST'), findsOneWidget);
    expect(find.text('ACTIVE ASSETS'), findsOneWidget);
    expect(find.text('View table format'), findsNothing, reason: 'the Water page has no card list');
    await see(tester, find.text('Asset #'));
    expect(find.text('Borehole 1'), findsOneWidget);
    expect(find.text('GHC 2,000.00 added', findRichText: true), findsNothing);
    expect(find.text('Where these figures came from'), findsNothing);
    expect(find.byTooltip('Reverse this acquisition'), findsOneWidget, reason: 'the machine has depreciation');
    expect(find.textContaining('Capital assets affect Cash Flow'), findsOneWidget);

    await rowAction(tester, 'Show where these figures came from');
    await see(tester, find.text('Edit asset'));
    await tap(tester, find.textContaining('Depreciation history'));
    await see(tester, find.text('Expense #601'));
  });

  testWidgets('New asset: supplier picker, Credit means unpaid, a balance needs a supplier', (tester) async {
    final a = api();
    await open(tester, AssetsScreen(session: await sessionFor(a), company: company, rail: AssetRail.water), size: phone);
    await tap(tester, find.text('New asset'));
    expect(inDialog(find.text('New asset')), findsOneWidget);
    expect(inDialog(find.text('Supplier / payee')), findsNothing);
    await enterIn(tester, 'Asset name', 'Borehole 2');
    await enterIn(tester, 'Cost', '6000');
    await choose(tester, 'Cash', 'Credit');
    expect(find.text('Credit: blank means nothing has been paid.'), findsOneWidget);
    expect(find.textContaining('owed to the supplier GHC 6,000.00', findRichText: true), findsOneWidget);
    expect(find.text('A balance is outstanding but no supplier is chosen, so it would not appear on Supplier Balances.'), findsOneWidget);
    await tapIn(tester, inDialog(find.text('Record asset')));
    expect(find.textContaining('Choose a supplier'), findsOneWidget);
    expect(a.writes.where((w) => w.url.path == '/api/Water/assets'), isEmpty);
    expect(inDialog(find.text('Record asset')), findsOneWidget, reason: 'the refusal leaves the form usable');
    clearToasts(tester);

    await choose(tester, 'No supplier', 'DrillCo');
    expect(find.text('Gone Ltd'), findsNothing, reason: 'deleted suppliers are left out');
    await tapIn(tester, inDialog(find.text('Record asset')));
    final b = body(a, '/api/Water/assets');
    expect((b['assetName'], b['amount'], b['supplierId'], b['paymentMethod'], b['amountPaid']), ('Borehole 2', 6000, 8, 'Credit', 0));
    expect(b.containsKey('supplier'), isFalse);
    expect(find.textContaining('Asset recorded'), findsOneWidget);
  });

  testWidgets('Add cost picks a supplier; Reverse a cost names the asset', (tester) async {
    final a = api();
    await open(tester, AssetsScreen(session: await sessionFor(a), company: company, rail: AssetRail.water), size: phone);
    await rowAction(tester, 'Add capitalised cost');
    expect(find.textContaining('Drilling, the pump, casing, wiring — real extra money spent on this asset'), findsOneWidget);
    expect(inDialog(find.text('Capitalise to this asset')), findsOneWidget);
    await enterIn(tester, 'Amount', '750');
    await choose(tester, 'No supplier', 'DrillCo');
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Add cost')));
    final c = body(a, '/api/Water/assets/1/costs');
    expect((c['amount'], c['supplierId'], c['paymentMethod']), (750, 8, 'Cash'));
    expect(c.containsKey('supplier'), isFalse);
    clearToasts(tester);

    await rowAction(tester, 'Show where these figures came from');
    await tap(tester, find.textContaining('Cost history'));
    await see(tester, find.byTooltip('Reverse this cost'));
    await tester.tap(find.byTooltip('Reverse this cost'));
    await tester.pumpAndSettle();
    expect(find.textContaining("the asset's value falls by GHC 2,000.00"), findsOneWidget);
    await reasonOther(tester, 'Wrong asset');
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Reverse cost')));
    expect(a.writes.lastWhere((w) => w.method == 'DELETE').url.path, '/api/Water/assets/1/costs/12');
  });

  testWidgets('the asset page: Water notes, back link, reverse a charge', (tester) async {
    final a = api()..gets['/api/Water/assets/1'] = {...fullBorehole, 'status': 'Draft'};
    await open(tester, AssetDetailScreen(session: await sessionFor(a), company: company, assetId: 1, rail: AssetRail.water), size: phone);
    expect(find.text('Back to Assets'), findsOneWidget);
    expect(find.text(draftAssetNote), findsOneWidget);
    await see(tester, find.text(capitalNotExpenseNote));
    await see(tester, find.byTooltip('Reverse this charge'));
    await tester.tap(find.byTooltip('Reverse this charge'));
    await tester.pumpAndSettle();
    await reasonOther(tester, 'Wrong month');
    await tapIn(tester, inDialog(find.widgetWithText(FilledButton, 'Reverse')));
    expect(body(a, '/api/Water/asset-depreciation/31/reverse')['reason'], 'Wrong month');
  });
}
