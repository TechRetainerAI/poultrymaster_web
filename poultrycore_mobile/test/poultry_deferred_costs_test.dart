// Poultry → Expenses → Deferred inventory cost: the rules, then the page at
// phone width — every filter, the figures, the history, the detail, the CSV.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/expenses/deferred_costs_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';

import 'support/harness.dart';

final maize = <String, Object?>{
  'poultryRawMaterialPurchaseId': 41, 'poultryRawMaterialItemId': 7, 'itemName': 'Maize', 'category': 'FeedIngredient',
  'supplierName': 'Agro Ltd', 'purchaseDate': '2026-09-02T00:00:00', 'purchasedQuantity': 1500, 'remainingQuantity': 600.5,
  'consumedQuantity': 899.5, 'productionUnit': 'kg', 'operationalCost': 3000, 'deferredTotalCost': 3000, 'recognizedCost': 1800,
  'deferredRemainingCost': 1200, 'recognitionPercent': 60, 'recognitionMethodLabel': 'Expense when consumed',
  'status': 'Partly expensed', 'quantityAheadInQueue': 250, 'costingMethod': 'FIFO',
};
final lot = <String, Object?>{
  'poultryRawMaterialPurchaseId': 42, 'itemName': 'Layer mash', 'category': 'FinishedFeed', 'isLotProduced': true,
  'feedProductionBatchNumber': 'FP-9', 'purchaseDate': '2026-09-10T00:00:00', 'purchasedQuantity': 500, 'remainingQuantity': 500,
  'productionUnit': 'kg', 'operationalCost': 900, 'deferredTotalCost': 0, 'recognizedCost': 0, 'deferredRemainingCost': 0,
  'recognitionPercent': 0, 'status': 'Expensed at purchase',
};
final bad = <String, Object?>{
  'poultryRawMaterialPurchaseId': 43, 'itemName': 'Soya', 'category': 'FeedIngredient', 'supplierName': 'Soy Co',
  'purchaseDate': '2026-08-01T00:00:00', 'purchasedQuantity': 100, 'remainingQuantity': 0, 'productionUnit': 'kg',
  'operationalCost': 400, 'deferredTotalCost': 400, 'recognizedCost': 400, 'allocatedRecognizedCost': 350, 'deferredRemainingCost': 0,
  'recognitionPercent': 100, 'status': 'Exception', 'exceptionReason': 'Usages explain 350 of 400',
};

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Poultry/deferred-inventory-costs'] = {
    'summary': {
      'remainingDeferredCost': 1200, 'deferredPurchases': 1, 'blockedPurchases': 1, 'blockedCost': 500, 'recognizedCost': 2200,
      'recognitionPercent': 64.7, 'deferredBasis': 3400, 'purchaseCount': 3, 'fullyRecognized': 1, 'notRecognized': 0,
      'exceptions': 1, 'exceptionDrift': -50,
    },
    'purchases': [maize, lot, bad],
  }
  ..gets['/api/Poultry/deferred-inventory-costs/41/history'] = [
    {'poultryRawMaterialUsageId': 1, 'usedDate': '2026-09-05T00:00:00', 'sourceLabel': 'Feed batch FP-3', 'sourceType': 'FeedProduction',
      'quantityDrawn': 500, 'productionUnit': 'kg', 'unitCostAtDraw': 2, 'operationalCost': 1000, 'recognizedCost': 1000,
      'recognitionOutcome': 'Expensed now', 'expenseId': 88},
    {'poultryRawMaterialUsageId': 2, 'usedDate': '2026-09-06T00:00:00', 'sourceLabel': 'Wrong batch', 'sourceType': 'FeedProduction',
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
  group('deferred cost rules', () {
    test('quantities, the queue note, the CSV, failure wording', () {
      expect(qtyFmt(1234.5678, 'kg'), '1,234.568 kg');
      expect(qtyFmt(600.5), '600.5');
      expect(deferredQueueNote(maize), '250 kg of older stock is used before this cost starts reaching Profit & Loss (FIFO).');
      expect(deferredQueueNote(lot), isNull);
      final csv = deferredCsv([maize, lot]).split('\n');
      expect(csv[1], '41,2026-09-02,Maize,Feed Ingredient,Agro Ltd,1500,kg,600.5,3000,3000,1800,1200,60,Expense when consumed,Partly expensed');
      expect(csv[2], contains('Produced FP-9'));
      expect(explainLoadFailure('function x does not exist', 'deferred inventory costs').headline,
          "Deferred inventory costs aren't switched on yet.");
      expect(explainLoadFailure('Request failed (500)').headline, 'Could not load this page.');
    });
  });

  test('on the sidebar route; ?itemId= opens filtered', () async {
    expect(pageScreens.containsKey('/poultry-deferred-costs'), isTrue);
    final s = moneyScreenForHref('/poultry-deferred-costs?itemId=7', await sessionFor(FakeApi()), company);
    expect((s as DeferredCostsScreen).itemId, 7);
  });

  testWidgets('figures, cards, filters reach the server, supplier on the page, CSV', (tester) async {
    final shared = <(String, List<int>)>[];
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add((name, bytes));
    final a = api();
    await open(tester, DeferredCostsScreen(session: await sessionFor(a), company: company, itemId: 7), size: phone);

    final q = a.requests.lastWhere((r) => r.url.path == '/api/Poultry/deferred-inventory-costs').url.queryParameters;
    expect((q['scope'], q['itemId']), ('DEFERRED', '7'));
    await see(tester, find.text('GHC 1,200.00'));
    expect(find.textContaining('GHC 500.00 of this is queued behind older stock'), findsOneWidget);
    expect(find.text('64.7% of GHC 3,400.00 deferred'), findsOneWidget);
    expect(find.text('GHC 50.00 unexplained'), findsOneWidget);
    await see(tester, find.text('Maize'));
    expect(find.text('behind 250 kg'), findsOneWidget);
    await see(tester, find.text('FP-9'));
    await see(tester, find.text('Usages explain 350 of 400'));

    await pickOn(tester, 'Still to expense', 'Needs checking');
    expect(a.requests.lastWhere((r) => r.url.path == '/api/Poultry/deferred-inventory-costs').url.queryParameters['scope'], 'EXCEPTION');
    expect(find.text('Purchases whose figures do not agree with their usages'), findsOneWidget);
    await pickOn(tester, 'All categories', 'Finished Feed');
    expect(a.requests.lastWhere((r) => r.url.path == '/api/Poultry/deferred-inventory-costs').url.queryParameters['category'], 'FinishedFeed');
    await pickOn(tester, 'All suppliers', 'Soy Co');
    expect(find.text('Maize'), findsNothing, reason: 'the supplier filter works on the loaded rows');
    await see(tester, find.text('Soya'));
    await tap(tester, find.text('Clear item filter'));
    expect(a.requests.lastWhere((r) => r.url.path == '/api/Poultry/deferred-inventory-costs').url.queryParameters.containsKey('itemId'), isFalse);

    await tap(tester, find.text('Export CSV'));
    expect(shared.single.$1, startsWith('deferred-inventory-costs-'));
    expect(utf8.decode(shared.single.$2), contains('Soya'));
  });

  testWidgets('table view: the history panel, then the purchase detail shows it', (tester) async {
    final a = api();
    await open(tester, DeferredCostsScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('View table format'));
    await tap(tester, find.text('#41'));
    await see(tester, find.text('Feed batch FP-3'));
    expect(find.text('Live usages (1)'), findsOneWidget);
    expect(find.text('GHC 1,000.00'), findsWidgets);
    await tap(tester, find.byTooltip('Purchase detail'));
    expect(find.text('Purchase #41'), findsOneWidget);
    expect(find.text('60.00%'), findsOneWidget);
    expect(find.text('RECOGNITION HISTORY (2)'), findsOneWidget);
    expect(find.text('Open item'), findsOneWidget);
    expect(find.text('Open purchase'), findsOneWidget);
  });

  testWidgets('a failed load explains itself and can be retried', (tester) async {
    final a = api()..statuses['/api/Poultry/deferred-inventory-costs'] = 500;
    await open(tester, DeferredCostsScreen(session: await sessionFor(a), company: company), size: phone);
    await see(tester, find.text('Could not load deferred inventory costs.'));
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Technical detail'));
    await tester.pumpAndSettle();
    expect(find.textContaining('status 500'), findsOneWidget);
  });

  testWidgets('Staff are not shown inventory costs', (tester) async {
    final staff = Company(farmId: 'farm-1', name: 'Test Farm', type: CompanyType.poultry, role: 'Staff');
    await open(tester, DeferredCostsScreen(session: await sessionFor(api()), company: staff), size: phone);
    expect(find.text('You do not have permission to view inventory costs.'), findsOneWidget);
  });
}
