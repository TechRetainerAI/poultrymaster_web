// Poultry → Operations → Production → Feed Production, at phone width: the
// formula scaling, the list, the new-batch form (recipe scaling, a formula,
// the checks, the body, the short-stock block) and the posted batch page.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/production/feed_production_form.dart';
import 'package:poultrycore_mobile/pages/poultry/production/feed_production_screen.dart';

import 'support/harness.dart';

final posted = <String, Object?>{
  'poultryFeedProductionBatchId': 4, 'batchNumber': 'FP-2026-0004', 'productionDate': '2026-10-01T00:00:00Z', 'finishedFeedItemId': 1,
  'finishedFeedItemName': 'Layer mash', 'quantityProduced': 500, 'outputUnit': 'kg', 'totalIngredientCost': 1000, 'totalAdditionalCost': 50,
  'totalProductionCost': 1050, 'costPerOutputUnit': 2.1, 'status': 'Posted', 'createdBy': 'ama', 'costRecognitionStatus': 'Carried in the feed',
  'deferredProductionCost': 0,
  'lines': [
    {'poultryFeedProductionBatchLineId': 1, 'ingredientItemId': 2, 'ingredientName': 'Maize', 'sourceType': 'FromInventory', 'quantityUsed': 250,
      'unitOfMeasure': 'kg', 'quantityMode': 'FixedQuantity', 'fixedQuantity': 50, 'unitCost': 2, 'totalCost': 500},
  ],
  'additionalCosts': [],
};
final draft = <String, Object?>{
  ...posted, 'poultryFeedProductionBatchId': 5, 'batchNumber': 'FP-2026-0005', 'status': 'Draft', 'totalProductionCost': 300,
};

FakeApi api() => FakeApi()
  ..gets['/api/Poultry/feed-production'] = [posted, draft]
  ..gets['/api/Poultry/feed-production/4'] = posted
  ..gets['/api/Poultry/feed-production/4/traceability'] = [
    {'poultryRawMaterialUsageId': 1, 'productionRecordId': 77, 'quantityDrawn': 12, 'unitCostAtDraw': 2.1, 'usedDate': '2026-10-03T00:00:00Z'},
  ]
  ..gets['/api/Poultry/feed-production/items'] = [
    {'poultryRawMaterialItemId': 1, 'itemName': 'Layer mash', 'category': 'FinishedFeed', 'unitOfMeasure': 'kg', 'currentQuantity': 0, 'isActive': true,
      'latestUnitCost': 0, 'availableFromLots': 0},
    {'poultryRawMaterialItemId': 2, 'itemName': 'Maize', 'category': 'FeedIngredient', 'unitOfMeasure': 'kg', 'currentQuantity': 300, 'isActive': true,
      'latestUnitCost': 2, 'availableFromLots': 200},
    {'poultryRawMaterialItemId': 3, 'itemName': 'Soya', 'category': 'FeedIngredient', 'unitOfMeasure': 'kg', 'currentQuantity': 900, 'isActive': true,
      'latestUnitCost': 5, 'availableFromLots': 900},
  ]
  ..gets['/api/Poultry/feed-formulas'] = [
    {'poultryFeedFormulaId': 9, 'formulaName': 'Layer 16%', 'isActive': true},
  ]
  ..gets['/api/Poultry/feed-formulas/9'] = {
    'poultryFeedFormulaId': 9, 'formulaName': 'Layer 16%', 'finishedFeedItemId': 1, 'defaultOutputUnit': 'kg',
    'lines': [
      {'poultryFeedFormulaLineId': 21, 'ingredientItemId': 2, 'quantityMode': 'Percentage', 'percentage': 60},
      {'poultryFeedFormulaLineId': 22, 'ingredientItemId': 3, 'quantityMode': 'Percentage', 'percentage': 40},
    ],
  }
  ..gets['/api/Poultry/cash-accounts'] = [
    {'poultryCashAccountId': 1, 'accountName': 'Main Cash Account'},
  ]
  ..gets['/api/Poultry/raw-material-items'] = []
  ..gets['/api/Poultry/feed-production/6'] = {...draft, 'poultryFeedProductionBatchId': 6, 'batchNumber': 'FP-2026-0006'}
  ..writeAnswers['/api/Poultry/feed-production'] = {'poultryFeedProductionBatchId': 6, 'batchNumber': 'FP-2026-0006'};

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 80 && f.evaluate().isEmpty; i++) {
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

Future<void> choose(WidgetTester tester, String shown, String option, {int which = 0}) async {
  final label = find.text(shown);
  await see(tester, label);
  final sel = find.ancestor(of: label.at(which), matching: find.byWidgetPredicate((w) => w is AppSelect)).first;
  await tester.ensureVisible(sel);
  await tester.pumpAndSettle();
  await tester.tap(sel);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// The text field under a label in the form.
Future<void> enter(WidgetTester tester, String label, String text, {int which = 0}) async {
  await see(tester, find.text(label));
  final f = find.descendant(of: find.ancestor(of: find.text(label).at(which), matching: find.byType(Column)).first, matching: find.byType(TextField));
  await tester.enterText(f.first, text);
  await tester.pumpAndSettle();
}

void main() {
  test('formula scaling and the post error', () {
    const pct = [RecipeLine(0, true, 60, 0), RecipeLine(1, true, 40, 0)];
    expect(scaleFormulaLines(pct, 500), {0: 300, 1: 200});
    const fixed = [RecipeLine(0, false, 0, 50), RecipeLine(1, false, 0, 30), RecipeLine(2, false, 0, 20)];
    expect(scaleFormulaLines(fixed, 500), {0: 250, 1: 150, 2: 100});
    const mixed = [RecipeLine(0, true, 50, 0), RecipeLine(1, false, 0, 2), RecipeLine(2, false, 0, 3)];
    expect(scaleFormulaLines(mixed, 100), {0: 50, 1: 20, 2: 30});
    expect(formulaUnitFactors(mixed)[2], closeTo(.3, 1e-9));
    expect(formulaCoverage(mixed).shape, 'mixed');
    expect(readableFeedError('Not enough tracked batch stock\nfor "Maize": need 300, only 200'),
        'Not enough ingredient stock to post: Maize (needs 300, only 200 available). Lower the quantity produced, or buy the shortfall during production.');
    expect(pageScreens.containsKey('/poultry-feed-production'), isTrue);
  });

  testWidgets('list: tiles, status filter, draft delete', (tester) async {
    final a = api();
    await open(tester, FeedProductionScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('FP-2026-0004'), findsOneWidget);
    expect(find.text('FP-2026-0005'), findsOneWidget);
    await see(tester, find.text('PRODUCED VALUE (POSTED)'));
    await choose(tester, 'All statuses', 'Draft');
    expect(find.text('FP-2026-0004'), findsNothing);
    await tap(tester, find.text('Delete'));
    expect(find.text('Batch FP-2026-0005 will be permanently removed.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect((a.writes.last.method, a.writes.last.url.path), ('DELETE', '/api/Poultry/feed-production/5'));
  });

  testWidgets('new batch: a typed recipe scales to the batch, checks, then the draft body', (tester) async {
    final a = api();
    await open(tester, FeedProductionNewScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Save Draft'));
    expect(find.textContaining('Pick the finished feed this batch produces.'), findsOneWidget);

    await choose(tester, 'Pick finished feed', 'Layer mash');
    await enter(tester, 'Quantity produced *', '100');
    await tap(tester, find.text('Save Draft'));
    expect(find.textContaining('Add at least one ingredient line.'), findsOneWidget);

    await choose(tester, 'Pick ingredient', 'Maize');
    await enter(tester, 'Qty used (kg)', '30');
    await tap(tester, find.text('Add ingredient'));
    await choose(tester, 'Pick ingredient', 'Soya');
    await enter(tester, 'Qty used (kg)', '20', which: 1);
    await see(tester, find.text('→ uses 60 kg'));

    await tap(tester, find.text('Add cost'));
    await enter(tester, 'Amount', '30');
    await choose(tester, 'Unpaid', 'Paid');
    await choose(tester, 'Account', 'Main Cash Account');
    await see(tester, find.text('Total cash out'));

    await tap(tester, find.text('Save Draft'));
    final b = jsonDecode(a.writes.lastWhere((w) => w.url.path == '/api/Poultry/feed-production').body) as Map;
    expect((b['finishedFeedItemId'], b['quantityProduced'], b['outputUnit'], b['formulaId'], b['farmId']), (1, 100, 'kg', null, company.farmId));
    final lines = b['lines'] as List;
    expect([for (final l in lines) ((l as Map)['ingredientItemId'], l['quantityUsed'], l['quantityMode'], l['fixedQuantity'], l['inventoryUnitCost'])],
        [(2, 60, 'FixedQuantity', 30, 2), (3, 40, 'FixedQuantity', 20, 5)]);
    final cost = (b['additionalCosts'] as List).single as Map;
    expect((cost['costType'], cost['amount'], cost['paymentStatus'], cost['amountPaid'], cost['paidFromCashAccountId'], cost['paymentMethod']),
        ('Labor', 30, 'Paid', 30, 1, 'Cash'));
    expect(find.textContaining('FP-2026-0006'), findsWidgets, reason: 'opens the saved batch');
  });

  testWidgets('new batch: a formula fills the lines; short stock blocks the post', (tester) async {
    final a = api();
    await open(tester, FeedProductionNewScreen(session: await sessionFor(a), company: company), size: phone);
    await choose(tester, 'Pick a formula', 'Layer 16%');
    expect(find.textContaining('Formula applied — 2 ingredients'), findsOneWidget);
    await enter(tester, 'Quantity produced *', '500');
    await see(tester, find.text('60% of batch'));
    await see(tester, find.textContaining('Short 100 — only 200 of Maize available to draw'));
    await see(tester, find.textContaining('Stock covers about'));

    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tap(tester, find.text('Save & Post'));
    expect(find.text('Not enough ingredient stock to post'), findsOneWidget);
    expect(find.text('needs 300, only 200 kg available'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(a.writes.where((w) => w.url.path.endsWith('/post')), isEmpty);

    await tap(tester, find.text('Use 333.333'));
    await see(tester, find.text('Reset to Layer 16%'));
  });

  testWidgets('posted batch: cost, audit, traceability and reverse', (tester) async {
    final a = api();
    await open(tester, FeedProductionBatchScreen(session: await sessionFor(a), company: company, batchId: 4), size: phone);
    expect(find.text('Batch FP-2026-0004'), findsWidgets);
    expect(find.text('None'), findsOneWidget, reason: 'nothing carried forward');
    await see(tester, find.text('from 50 in the recipe'));
    await see(tester, find.text('Record #77'));
    await tap(tester, find.text('Reverse'));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Wrong mix');
    await tester.tap(find.text('Reverse Batch'));
    await tester.pumpAndSettle();
    final w = a.writes.firstWhere((w) => w.url.path == '/api/Poultry/feed-production/4/reverse');
    expect((jsonDecode(w.body) as Map)['reversalReason'], 'Wrong mix');
  });
}
