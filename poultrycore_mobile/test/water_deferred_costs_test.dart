// Water → Expenses → Deferred inventory cost (app/water-deferred-costs): the
// rules, then the page at phone width — the table on every width, every
// filter, the figures, the production-batch history, the detail, the CSV.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';
import 'package:poultrycore_mobile/pages/water/water_deferred_costs_screen.dart';

import 'support/harness.dart';

final film = <String, Object?>{
  'waterRawMaterialPurchaseId': 41, 'waterRawMaterialItemId': 7, 'itemName': 'Sachet film', 'category': 'SachetFilm',
  'supplierName': 'Film Co', 'purchaseDate': '2026-09-02T00:00:00', 'purchasedQuantity': 1500, 'remainingQuantity': 600.5,
  'consumedQuantity': 899.5, 'productionUnit': 'kg', 'operationalCost': 3000, 'deferredTotalCost': 3000, 'recognizedCost': 1800,
  'deferredRemainingCost': 1200, 'recognitionPercent': 60, 'recognitionMethodLabel': 'Expense when consumed',
  'status': 'Partly expensed', 'quantityAheadInQueue': 250, 'costingMethod': 'FIFO',
};
final bags = <String, Object?>{
  'waterRawMaterialPurchaseId': 42, 'itemName': 'Outer bags', 'category': 'OuterBag', 'supplierName': 'Bag Ltd',
  'purchaseDate': '2026-09-10T00:00:00', 'purchasedQuantity': 500, 'remainingQuantity': 500, 'productionUnit': 'pcs',
  'operationalCost': 900, 'deferredTotalCost': 0, 'recognizedCost': 0, 'deferredRemainingCost': 0, 'recognitionPercent': 0,
  'status': 'Expensed at purchase',
};
final bad = <String, Object?>{
  'waterRawMaterialPurchaseId': 43, 'itemName': 'Packaging roll', 'category': 'PackagingRoll', 'supplierName': 'Roll Co',
  'purchaseDate': '2026-08-01T00:00:00', 'purchasedQuantity': 100, 'remainingQuantity': 0, 'productionUnit': 'kg',
  'operationalCost': 400, 'deferredTotalCost': 400, 'recognizedCost': 400, 'allocatedRecognizedCost': 350, 'deferredRemainingCost': 0,
  'recognitionPercent': 100, 'status': 'Exception', 'exceptionReason': 'Usages explain 350 of 400',
};

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Water/deferred-inventory-costs'] = {
    'summary': {
      'remainingDeferredCost': 1200, 'deferredPurchases': 1, 'blockedPurchases': 1, 'blockedCost': 500, 'recognizedCost': 2200,
      'recognitionPercent': 64.7, 'deferredBasis': 3400, 'purchaseCount': 3, 'fullyRecognized': 1, 'notRecognized': 0,
      'exceptions': 1, 'exceptionDrift': -50,
    },
    'purchases': [film, bags, bad],
  }
  ..gets['/api/Water/deferred-inventory-costs/41/history'] = [
    {'waterRawMaterialUsageId': 1, 'usedDate': '2026-09-05T00:00:00', 'sourceLabel': 'Batch WB-12', 'sourceType': 'Production',
      'waterProductionBatchId': 12, 'productName': 'Sachet 500ml', 'quantityDrawn': 500, 'productionUnit': 'kg', 'unitCostAtDraw': 2,
      'operationalCost': 1000, 'recognizedCost': 1000, 'recognitionOutcome': 'Expensed now', 'waterExpenseId': 88},
    {'waterRawMaterialUsageId': 2, 'usedDate': '2026-09-06T00:00:00', 'sourceLabel': 'Internal use', 'sourceType': 'InternalUse',
      'quantityDrawn': 100, 'productionUnit': 'kg', 'unitCostAtDraw': 2, 'operationalCost': 200, 'recognizedCost': 200,
      'recognitionOutcome': 'Reversed', 'isReversed': true},
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

Future<void> pickOn(WidgetTester tester, String shown, String option) async {
  await see(tester, find.text(shown));
  await tester.tap(find.ancestor(of: find.text(shown), matching: find.byType(AppSelect<String>)).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  test('Water categories, scopes and the CSV: no produced lots, the supplier or nothing', () {
    expect(waterDeferredCategoryLabel('SachetFilm'), 'Sachet Film');
    expect(waterDeferredCategoryLabel('UVLamp'), 'UV Lamp');
    expect(waterDeferredCategoryLabel('Chemical'), 'Chemical');
    expect(waterDeferredScopes.last.$3, 'Every raw material purchase, however its cost was recognised');
    final csv = waterDeferredCsv([film, {...bags, 'supplierName': null}]).split('\n');
    expect(csv[1], '41,2026-09-02,Sachet film,Sachet Film,Film Co,1500,kg,600.5,3000,3000,1800,1200,60,Expense when consumed,Partly expensed');
    expect(csv[2].split(',')[4], '');
  });

  test('on the sidebar route; ?itemId= and ?scope= open filtered', () async {
    expect(pageScreens.containsKey('/water-deferred-costs'), isTrue);
    final s = moneyScreenForHref('/water-deferred-costs?itemId=7&scope=ALL', await sessionFor(FakeApi()), company);
    expect(((s as WaterDeferredCostsScreen).itemId, s.scope), (7, 'ALL'));
  });

  testWidgets('figures, the table on a phone, filters reach the server, CSV', (tester) async {
    final shared = <(String, List<int>)>[];
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add((name, bytes));
    final a = api();
    await open(tester, WaterDeferredCostsScreen(session: await sessionFor(a), company: company, itemId: 7), size: phone);

    final q = a.requests.lastWhere((r) => r.url.path == '/api/Water/deferred-inventory-costs').url.queryParameters;
    expect((q['scope'], q['itemId']), ('DEFERRED', '7'));
    expect(find.text('Track raw material purchases whose costs are recognized in Profit & Loss as production consumes the stock.'), findsOneWidget);
    expect(find.textContaining('it moves into Profit & Loss as production draws the stock.'), findsOneWidget);
    await see(tester, find.text('GHC 1,200.00'));
    expect(find.textContaining('GHC 500.00 of this is queued behind older stock'), findsOneWidget);
    expect(find.text('64.7% of GHC 3,400.00 deferred'), findsOneWidget);
    expect(find.text('GHC 50.00 unexplained'), findsOneWidget);
    expect(find.text('View table format'), findsNothing, reason: 'the Water page has no card list');
    await see(tester, find.text('#41'));
    expect(find.text('Film Co'), findsOneWidget);
    expect(find.text('Sachet Film'), findsOneWidget);
    expect(find.text('behind 250 kg'), findsOneWidget);
    expect(find.text('Exception'), findsOneWidget);

    await pickOn(tester, 'Still to expense', 'Needs checking');
    expect(a.requests.lastWhere((r) => r.url.path == '/api/Water/deferred-inventory-costs').url.queryParameters['scope'], 'EXCEPTION');
    await pickOn(tester, 'All categories', 'Outer Bag');
    expect(a.requests.lastWhere((r) => r.url.path == '/api/Water/deferred-inventory-costs').url.queryParameters['category'], 'OuterBag');
    await pickOn(tester, 'All suppliers', 'Roll Co');
    expect(find.text('#41'), findsNothing, reason: 'the supplier filter works on the loaded rows');
    await see(tester, find.text('#43'));
    await tap(tester, find.text('Clear item filter'));
    expect(a.requests.lastWhere((r) => r.url.path == '/api/Water/deferred-inventory-costs').url.queryParameters.containsKey('itemId'), isFalse);

    await tap(tester, find.text('Export CSV'));
    expect(shared.single.$1, startsWith('water-deferred-inventory-costs-'));
    expect(utf8.decode(shared.single.$2), contains('Packaging roll'));
  });

  testWidgets('the history names the production batch; the detail has Open items', (tester) async {
    final a = api();
    await open(tester, WaterDeferredCostsScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('#41'));
    await see(tester, find.text('Batch WB-12'));
    expect(find.text('Production batch'), findsOneWidget);
    expect(find.text('Sachet 500ml'), findsOneWidget);
    expect(find.text('Internal use'), findsOneWidget, reason: 'a draw with no batch shows its label, unlinked');
    expect(find.text('Live usages (1)'), findsOneWidget);
    expect(find.byTooltip('Expense #88 — Charging this to Profit & Loss moves no money. The cash left the business when the stock was bought.'),
        findsOneWidget);
    await tap(tester, find.byTooltip('Purchase detail').first);
    expect(find.text('Purchase #41'), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Supplier')), findsOneWidget);
    expect(find.text('RECOGNITION HISTORY (2)'), findsOneWidget);
    expect(find.text('Open items'), findsOneWidget);
    expect(find.text('Open purchase'), findsOneWidget);
  });
}
