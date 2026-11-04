// Report 30 Part 2: egg packaging (393/394) and Egg Configuration, at phone
// width -- the conversion rules (the web's egg-packaging.test.ts cases), the
// four tabs, Packaging & units with its confirm, and box / egg prices.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/poultry/egg_packaging.dart';
import 'package:poultrycore_mobile/pages/poultry/egg_pick_settings_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/trackers/egg_class_ledger.dart' show cratesText;
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

EggPackaging boxes(int cpb, [int epc = 30]) =>
    EggPackaging(eggsPerCrate: epc, enableBoxes: true, cratesPerBox: cpb, display: EggDisplay.boxesCratesPieces);
const crateOnly = EggPackaging();

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, 300));
    await tester.pumpAndSettle();
  }
  expect(f, findsWidgets);
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await see(tester, f);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

FakeApi configApi({bool boxesOn = false}) => FakeApi()
  ..gets['/api/FarmProductionSettings'] = {'firstPickTime': '09:00:00', 'secondPickTime': '12:00:00', 'thirdPickTime': '16:00:00', 'enableFourthPick': false}
  ..gets['/api/Poultry/egg-sorting/settings'] = {'enableEggSorting': true, 'closingPolicy': 'Warning', 'eggsPerCrate': 30, 'unsortedPricePerCrate': 30}
  ..gets['/api/Poultry/egg-sorting/classes'] = [
    {'poultryProductId': 10, 'name': 'Unsorted', 'classKind': 'Unsorted', 'isActive': true, 'onHand': 650, 'pricePerCrate': 30},
    {'poultryProductId': 11, 'eggSizeId': 1, 'name': 'Large', 'classKind': 'Size', 'isActive': true, 'onHand': 90, 'pricePerCrate': 40, 'sortOrder': 1},
  ]
  ..gets['/api/Poultry/egg-sorting/packaging'] = {
    'enableBoxes': boxesOn, 'cratesPerBox': boxesOn ? 14 : null, 'eggDisplay': boxesOn ? 'BoxesCratesPieces' : 'CratesPieces',
    'saleEntryUnit': 'Crates', 'packagingVersion': 1,
    'storedCratesPerBox': boxesOn ? 14 : null, 'storedDisplay': boxesOn ? 'BoxesCratesPieces' : 'CratesPieces', 'storedEntryUnit': 'Crates',
  };

void main() {
  tearDown(resetEggPackaging);

  group('packaging rules (egg-packaging.ts)', () {
    test('conversions', () {
      expect(boxes(14).eggsPerBox, 420);
      expect(toEggPieces(const PackagedQuantity(boxes: 2, crates: 3, pieces: 10), boxes(14)), 940);
      expect(toBoxesCratesPieces(10675, boxes(14)), const PackagedQuantity(boxes: 25, crates: 5, pieces: 25));
      expect(toBoxesCratesPieces(95, boxes(14)), const PackagedQuantity(crates: 3, pieces: 5));
      expect(toBoxesCratesPieces(1000, const EggPackaging(enableBoxes: true, cratesPerBox: 0)), const PackagedQuantity(crates: 33, pieces: 10));
      expect(toBoxesCratesPieces(500, boxes(10, 24)), const PackagedQuantity(boxes: 2, pieces: 20));
      expect(toBoxesCratesPieces(-485, boxes(14)), const PackagedQuantity(boxes: -1, crates: -2, pieces: -5));
      expect(normalizePackaged(const PackagedQuantity(boxes: 1, crates: 16, pieces: 35), boxes(14)), const PackagedQuantity(boxes: 2, crates: 3, pieces: 5));
      expect(toCratesPieces(10675, crateOnly), const PackagedQuantity(crates: 355, pieces: 25));
    });

    test('checks', () {
      expect(packagingConfigError(enableBoxes: true, cratesPerBox: null, display: EggDisplay.cratesPieces, saleEntryUnit: SaleEntryUnit.crates), isNotNull);
      expect(packagingConfigError(enableBoxes: true, cratesPerBox: 201, display: EggDisplay.cratesPieces, saleEntryUnit: SaleEntryUnit.crates), isNotNull);
      expect(packagingConfigError(enableBoxes: true, cratesPerBox: 14, display: EggDisplay.boxesCratesPieces, saleEntryUnit: SaleEntryUnit.boxes), isNull);
      expect(packagingConfigError(enableBoxes: false, cratesPerBox: 14, display: EggDisplay.boxesCratesPieces, saleEntryUnit: SaleEntryUnit.crates), isNotNull);
      expect(packagingConfigError(enableBoxes: false, cratesPerBox: 14, display: EggDisplay.cratesPieces, saleEntryUnit: SaleEntryUnit.boxes), isNotNull);
      expect(packagedQuantityError(const PackagedQuantity(crates: -1), boxes(14)), contains('negative'));
      expect(packagedQuantityError(const PackagedQuantity(boxes: 1), crateOnly), contains('not set up'));
    });

    test('text', () {
      expect(formatEggQuantity(10675, boxes(14)), '25 boxes + 5 crates + 25 pcs');
      expect(formatEggQuantity(10675, boxes(14), EggDisplay.cratesPieces), '355 crates + 25 pcs');
      expect(formatEggQuantity(10675, boxes(14), EggDisplay.pieces), '10,675 eggs');
      expect(formatEggQuantity(10675, crateOnly, EggDisplay.boxesCratesPieces), '355 crates + 25 pcs');
      expect(formatEggQuantity(25, boxes(14)), '25 eggs');
      expect(formatEggQuantity(1, boxes(14)), '1 egg');
      expect(formatEggQuantity(420, boxes(14)), '1 box');
      expect(formatPackaged(const PackagedQuantity(crates: 1)), '1 crate');
      expect(formatPackaged(const PackagedQuantity()), '0 eggs');
      expect(eggQuantityHint(10675, boxes(14)), '10,675 eggs');
      expect(eggQuantityHint(20, boxes(14)), isNull);
      expect(postedLineConversion({'boxes': 2, 'cratesPerBox': 14, 'eggsPerCrate': 30}), '1 box = 14 crates × 30 = 420 eggs');
      expect(postedLineQuantity({'quantity': 940, 'boxes': 2, 'crates': 3, 'pieces': 10}, crateOnly).asEntered, isTrue);
    });

    test('pricing: each part at its own price, once rounded', () {
      expect(packagedLineAmount(const PackagedQuantity(boxes: 2), pricePerCrate: 150, pricePerBox: 2000, p: boxes(14)), 4000);
      expect(packagedLineAmount(const PackagedQuantity(boxes: 1), pricePerCrate: 150, p: boxes(14)), 2100, reason: 'no box price: 14 × the crate');
      expect(packagedLineAmount(const PackagedQuantity(crates: 7, pieces: 10), pricePerCrate: 137.5, p: crateOnly), 1008.33);
    });

    test('the active farm, and cratesText with boxes first', () {
      applyEggPackaging('farm-1', {'enableBoxes': true, 'cratesPerBox': 14, 'eggDisplay': 'BoxesCratesPieces'});
      expect(boxSize(eggPackagingFor('farm-1')), 14);
      expect(boxSize(eggPackagingFor('farm-2')), isNull, reason: "never another company's box size");
      expect(cratesText(28870), '68 bx + 10 cr + 10');
      expect(cratesText(28870, 30), '962 cr + 10', reason: 'an explicit crate size keeps crates only');
    });
  });

  group('Egg Configuration (app/business-office/egg-pick-settings)', () {
    test('one menu row, renamed', () {
      final labels = [for (final g in webNavGroups['poultry']!) for (final s in g.subGroups) for (final l in s.links) l.label];
      expect(labels, contains('Egg Configuration'));
      expect(labels, isNot(contains('Egg Pick Times')));
      expect(labels, isNot(contains('Egg Sorting Settings')));
    });

    testWidgets('the four tabs, their status lines, and the pick cards', (tester) async {
      await open(tester, EggPickSettingsScreen(session: await sessionFor(configApi()), company: company), size: phone);
      expect(find.text('Egg Configuration'), findsWidgets);
      expect(find.text('3 picks a day'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);
      expect(find.text('Crates of 30'), findsOneWidget);
      expect(find.text('1 active'), findsOneWidget);
      expect(find.text('Always on'), findsNWidgets(3));
      expect(find.text('Pick times are saved.'), findsNothing, reason: 'below the picks');
      await see(tester, find.text('Pick times are saved.'));

      // Turning on the 4th pick: it joins "Your day" and the bar turns amber.
      await tap(tester, find.byKey(const ValueKey('egg-config-enable-4')));
      await see(tester, find.text('You have unsaved changes to the pick times.'));
      expect(tester.takeException(), isNull);

      await tap(tester, find.byKey(const ValueKey('egg-config-tab-sorting')));
      expect(find.text('Egg sorting'), findsWidgets);
      await see(tester, find.textContaining('Unsorted / General eggs on hand: 650'));
      expect(find.text('Egg sizes'), findsNothing, reason: 'its own tab');

      await tap(tester, find.byKey(const ValueKey('egg-config-tab-sizes')));
      await see(tester, find.text('Egg sizes'));
      expect(find.text('Price / box'), findsNothing, reason: 'boxes are off');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Packaging & units: turn on boxes of 14, confirm, saved', (tester) async {
      final api = configApi();
      await open(tester, EggPickSettingsScreen(session: await sessionFor(api), company: company, initialTab: 'packaging'), size: phone);
      expect(find.text('Egg packaging & units'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('packaging-boxes')));
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('packaging-crates')), matching: find.byType(TextField)), '14');
      await tester.pumpAndSettle();
      expect(find.text('1 box = 14 crates × 30 = 420 eggs'), findsOneWidget);
      expect(find.text('10,675 eggs → 25 boxes + 5 crates + 25 pcs'), findsOneWidget, reason: 'the preview');
      api.gets['/api/Poultry/egg-sorting/packaging'] = {
        'enableBoxes': true, 'cratesPerBox': 14, 'eggDisplay': 'BoxesCratesPieces', 'saleEntryUnit': 'Crates', 'packagingVersion': 2,
        'storedCratesPerBox': 14, 'storedDisplay': 'BoxesCratesPieces', 'storedEntryUnit': 'Crates',
      };
      await tap(tester, find.byKey(const ValueKey('packaging-save')));
      expect(find.text('Turn on boxes?'), findsOneWidget);
      expect(find.text('Your egg stock does not change. It is kept in individual eggs; only how it is shown changes.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('packaging-confirm-save')));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/egg-sorting/packaging', 'PUT');
      expect((body['enableBoxes'], body['cratesPerBox'], body['eggDisplay'], body['saleEntryUnit']), (true, 14, 'BoxesCratesPieces', 'Crates'));
      expect(find.text('Egg packaging saved'), findsOneWidget);
      expect(boxSize(eggPackagingFor(company.farmId)), 14, reason: 'applied at once');
      await see(tester, find.text('Boxes of 14 crates'));
    });

    testWidgets('a box farm: box and egg prices on Unsorted and each size', (tester) async {
      final api = configApi(boxesOn: true);
      await open(tester, EggPickSettingsScreen(session: await sessionFor(api), company: company, initialTab: 'sizes'), size: phone);
      await see(tester, find.text('Price / box'));
      expect(find.text('Price / egg'), findsOneWidget);
      // Empty = derived: 40 × 14 per box, 40 / 30 per egg.
      expect(find.text('560.00'), findsOneWidget);
      expect(find.text('1.3333'), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('size-box-1')), matching: find.byType(TextField)), '500');
      await tester.pumpAndSettle();
      await tap(tester, find.text('Save'));
      final body = api.lastBody('/api/Poultry/egg-sorting/classes/11/prices', 'PUT');
      expect((body['pricePerCrate'], body['pricePerBox'], body['pricePerPiece']), (40, 500, null));

      await tap(tester, find.byKey(const ValueKey('egg-config-tab-sorting')));
      await see(tester, find.text('Unsorted price per box'));
      expect(find.text('Empty = the crate price × 14 per box, and the crate price shared over 30 eggs.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
