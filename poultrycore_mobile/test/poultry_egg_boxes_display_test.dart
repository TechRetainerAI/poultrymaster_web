// Report 30 Part 6: egg boxes shown across the Poultry screens (393–396):
// the "≈ boxes" hints, Inventory's equivalent, the Egg Tracker's crates line,
// Poultry Stock's packaging line, the audit wording, the reports' Sold as /
// Equivalent boxes, and a manual stock movement entered in boxes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart' show AppSelect;
import 'package:poultrycore_mobile/pages/poultry/egg_packaging.dart';
import 'package:poultrycore_mobile/pages/poultry/egg_sorting/egg_sorting_logic.dart' show describeAudit;
import 'package:poultrycore_mobile/pages/poultry/inventory/inventory_screen.dart' show crateEquivalent, isEggStock;
import 'package:poultrycore_mobile/pages/poultry/inventory/stock_movements_screen.dart' show NewStockMovementDialog, enteredAsLine;
import 'package:poultrycore_mobile/pages/poultry/reports/report_defs.dart' show poultryReportDefs;
import 'package:poultrycore_mobile/pages/poultry/reports/report_format.dart' show FarmMoney, FmtCtx;
import 'package:poultrycore_mobile/pages/poultry/trackers/egg_tracker_screen.dart' show eggCratesLine;

import 'support/harness.dart';

/// 14 crates of 30 to a box, shown boxes first (the farm in these tests).
void boxFarm({EggDisplay display = EggDisplay.boxesCratesPieces}) => applyEggPackaging('farm-1', {
      'enableBoxes': true,
      'cratesPerBox': 14,
      'eggDisplay': eggDisplayApi[display],
    });

void main() {
  tearDown(resetEggPackaging);

  test('the hints: only on a farm that shows boxes', () {
    expect(eggBoxesSuffix(840, currentEggPackaging), '', reason: 'boxes off');
    boxFarm();
    expect(eggBoxesSuffix(840, currentEggPackaging), ' (≈ 2 boxes)');
    expect(eggBoxesLine(485, currentEggPackaging), '≈ 1 box + 2 crates + 5 pcs');
    expect(eggBoxesHint(840, currentEggPackaging), ' · ≈ 2 boxes');
    boxFarm(display: EggDisplay.cratesPieces);
    expect(eggBoxesSuffix(840, currentEggPackaging), '', reason: 'a box farm that shows crates');
  });

  test('Inventory: the equivalent follows the packaging and every egg product', () {
    expect(crateEquivalent(95), '≈ 3 crates + 5 pcs');
    expect(crateEquivalent(20), isNull, reason: 'under one crate');
    boxFarm();
    expect(crateEquivalent(485), '≈ 1 box + 2 crates + 5 pcs');
    expect(isEggStock({'name': 'Eggs - Large'}), isTrue);
    expect(isEggStock({'name': 'Broken Eggs'}), isFalse, reason: 'a byproduct keeps its own unit');
  });

  test('Egg Tracker: the crates line, boxes first, keeps its sign', () {
    expect(eggCratesLine(65), '2 crates + 5 pieces');
    expect(eggCratesLine(-31), '−1 crate + 1 piece');
    boxFarm();
    expect(eggCratesLine(485), '1 box + 2 crates + 5 pieces');
  });

  test('Poultry Stock: as entered, else ≈ the equivalent; not for broken eggs', () {
    boxFarm();
    expect(enteredAsLine('Eggs', 485, {'boxes': 1, 'crates': 2, 'pieces': 5}), '1 box + 2 crates + 5 pcs');
    expect(enteredAsLine('Eggs - Large', -485, null), '≈ 1 box + 2 crates + 5 pcs');
    expect(enteredAsLine('Broken Eggs', 485, null), isNull);
    expect(enteredAsLine('Maize', 485, null), isNull);
    expect(enteredAsLine('Eggs', 12, null), isNull, reason: 'under a crate says nothing new');
  });

  test('the Egg Sorting change history names the box size', () {
    final s = describeAudit({
      'action': 'SettingsChanged',
      'details': '{"enableEggSorting":true,"closingPolicy":"Warning","eggsPerCrate":30,"enableBoxes":true,"cratesPerBox":14,"before":{"cratesPerBox":12}}',
    });
    expect(s, endsWith(', boxes on (14 crates per box) — box size was 12'));
    expect(describeAudit({'action': 'SettingsChanged', 'details': '{"enableEggSorting":false,"closingPolicy":"Off","eggsPerCrate":30}'}),
        isNot(contains('boxes')), reason: 'rows written before 393');
  });

  test('reports: the hints, Sold as (entered), Equivalent boxes, and the Sold as column', () {
    boxFarm();
    const c = FmtCtx(FarmMoney());
    final sales = poultryReportDefs['egg-sales']!;
    String card(String label, Map s) => sales.cards.firstWhere((x) => x.label == label).value(s, c);
    final summary = {'totalEggsSold': 840, 'actualBoxesSold': 2, 'actualCratesSold': 3, 'actualPiecesSold': 10, 'equivalentBoxes': 2};
    expect(card('Total eggs sold', summary), endsWith(' · ≈ 2 boxes'));
    expect(card('Sold as (entered)', summary), '2 boxes + 3 crates + 10 pcs');
    expect(card('Sold as (entered)', {'totalEggsSold': 10}), '—');
    expect(card('Equivalent boxes', {}), '—');
    final soldAs = sales.columns.firstWhere((x) => x.header == 'Sold as');
    expect(soldAs.cell({'cratesSold': null}, c), '—', reason: 'a sale entered before 394');
    expect(soldAs.cell({'boxesSold': 1, 'cratesSold': 0, 'piecesSold': 5}, c), '1 box + 5 pcs');
    expect(poultryReportDefs['egg-stock-balance']!.description, contains('Equivalents are counts, not packed stock.'));
  });

  testWidgets('a manual movement of eggs on a box farm is entered as boxes + crates + pieces', (tester) async {
    boxFarm();
    final a = FakeApi()
      ..gets['/api/Poultry/stock/birds/options'] = []
      ..gets['/api/Poultry/stock/manual-movements/preview'] = {
        'isBirds': false, 'systemRole': null, 'isEgg': true, 'itemOnHand': 1000, 'farmLiveBirds': 0, 'deadBirdsOnHand': 0,
        'brokenEggsOnHand': 0, 'businessDate': '2099-12-31',
      }
      ..writeAnswers['/api/Poultry/stock/manual-movements'] = {'movementId': 9, 'movementNo': 'MSM-00009', 'repeated': false, 'eggs': 485, 'packaging': '1 box + 2 crates + 5 pcs'};
    final s = await sessionFor(a);
    await open(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => NewStockMovementDialog(session: s, company: company, products: const [
                {'poultryProductId': 1, 'name': 'Eggs', 'isRawEggProduct': true, 'isActive': true},
              ], rawItems: const []),
            ),
            child: const Text('go'),
          ),
        ),
      ),
      size: phone,
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    final picker = find.ancestor(of: find.text('Pick a finished product, raw material or supply'), matching: find.byWidgetPredicate((w) => w is AppSelect)).first;
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eggs').last);
    await tester.pumpAndSettle();
    expect(find.text('boxes (14×30)'), findsOneWidget);
    expect(find.text('crates (30)'), findsOneWidget);
    for (final (k, v) in [('boxes', '1'), ('crates', '2'), ('pieces', '5')]) {
      await tester.enterText(find.descendant(of: find.byKey(ValueKey('manual-$k')), matching: find.byType(TextField)), v);
      await tester.pumpAndSettle();
    }
    expect(find.text('= 485 eggs. Always positive; the movement type sets the direction.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('manual-packaged-after')));
    expect(find.text('1 box + 2 crates + 5 pcs = +485 eggs. After: 3 boxes + 7 crates + 15 pcs (an equivalent; nothing is packed).'), findsOneWidget);

    // Save: one movement of eggs, with the boxes / crates / pieces for the server to convert.
    final reason = find.ancestor(of: find.text('Choose the reason'), matching: find.byWidgetPredicate((w) => w is AppSelect)).first;
    await tester.ensureVisible(reason);
    await tester.pumpAndSettle();
    await tester.tap(reason);
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((w) => w is Text && w.data == 'Opening Inventory').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final b = a.lastBody('/api/Poultry/stock/manual-movements');
    expect((b['quantity'], b['boxes'], b['crates'], b['pieces']), (485, 1, 2, 5));
    expect(find.text('MSM-00009 posted — 1 box + 2 crates + 5 pcs = 485 eggs'), findsOneWidget);
  });
}
