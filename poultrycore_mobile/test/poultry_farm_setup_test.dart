// Poultry → Tools → Initial Farm Setup: the rules (farm_setup_wizard.dart,
// a port of lib/farm-setup/wizard.ts) and the screen against a fake API.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/poultry/farm_setup_wizard.dart';
import 'package:poultrycore_mobile/pages/poultry/initial_farm_setup_screen.dart';

import 'support/harness.dart';

SetupContext ctx({
  List<ExistingBatch> batches = const [],
  List<ExistingHouse> houses = const [],
  Map<int, int> allocated = const {},
}) =>
    SetupContext(
      existingBatches: batches,
      existingHouses: houses,
      allocatedByBatchId: allocated,
      businessDate: '2026-10-02',
    );

FlockRow flock(String placed, String live, {String batchKey = 'b1', String houseKey = 'h1', String name = 'F'}) =>
    FlockRow(
      key: nextKey('flock'),
      batchKey: batchKey,
      houseKey: houseKey,
      name: name,
      originallyPlaced: placed,
      currentLiveBirds: live,
      startDate: '2026-01-01',
    );

void main() {
  setUp(LookupLoader.clear);

  group('rules', () {
    test('unknown history is an adjustment, never mortality', () {
      final f = flock('1050', '960');
      expect(historicalReduction(f), 90);
      final b = breakdown(f);
      expect(b.mortality, 0);
      expect(b.other, 90);

      f
        ..historyKnown = true
        ..historicalMortality = '60'
        ..historicalSold = '10';
      final k = breakdown(f);
      expect(k.stated, 70);
      expect(k.other, 20);
      expect(k.overStated, isFalse);
    });

    test('mortality balances: Sold comes out of it; mortality itself does not move the others', () {
      final d = SetupDraft(flocks: [flock('1000', '919')]);
      seedReconciliation(d);
      final f = d.flocks.first;
      expect(f.historyKnown, isTrue);
      expect(f.historicalMortality, '81');

      balanceBreakdown(f, 'historicalSold', '10');
      expect(f.historicalMortality, '71');
      expect(f.reconciliationTouched, isTrue);
      balanceBreakdown(f, 'historicalMortality', '50');
      expect(f.historicalSold, '10');
      expect(breakdown(f).other, 21);

      // A touched flock is never re-seeded.
      f.currentLiveBirds = '900';
      seedReconciliation(d);
      expect(f.historicalMortality, '50');
    });

    test('a historical batch must be fully in pens; a new purchase may stay partial', () {
      final batch = BatchRow(key: 'b1', batchName: 'Batch 1', batchCode: 'B1', numberOfBirds: '1000', startDate: '2026-01-01');
      final house = HouseRow(key: 'h1', houseName: 'Pen 1');
      final d = SetupDraft(batches: [batch], houses: [house], flocks: [flock('800', '800')]);
      final e = validateSetup(d, ctx()).errors.where((x) => x.field == 'numberOfBirds').single;
      expect(e.message,
          'B1 is a batch you already had, so all 1,000 of its birds must be in a pen — 200 are unaccounted for. Put them in a pen, or lower the batch to 800.');

      batch.isHistorical = false;
      expect(validateSetup(d, ctx()).errors.where((x) => x.field == 'numberOfBirds'), isEmpty);

      d.flocks.first.originallyPlaced = '1200';
      d.flocks.first.currentLiveBirds = '1200';
      expect(validateSetup(d, ctx()).errors.where((x) => x.field == 'numberOfBirds').single.message,
          'Flocks from B1 were placed with 1,200 birds, but the batch only had 1,000.');
    });

    test('capacity: a warning for birds already standing, an error for newly bought ones', () {
      final batch = BatchRow(key: 'b1', batchName: 'Batch 1', batchCode: 'B1', numberOfBirds: '600', startDate: '2026-01-01');
      final house = HouseRow(key: 'h1', houseName: 'Pen 1', capacity: '500');
      final d = SetupDraft(batches: [batch], houses: [house], flocks: [flock('600', '600')]);
      final v = validateSetup(d, ctx());
      expect(v.warnings.where((w) => w.section == 'houses').single.message,
          'Pen 1 is recorded as taking 500 birds, but this setup puts 600 in it. Update the capacity — it is what decides where your next batch can go.');

      batch.isHistorical = false;
      expect(validateSetup(d, ctx()).errors.where((x) => x.section == 'houses').single.message,
          'Pen 1 holds 500 birds. You are placing 600 newly bought birds in it and only 500 will fit.');
    });

    test('duplicates, more standing than placed, and the existing farm', () {
      final d = SetupDraft(
        batches: [BatchRow(key: 'b1', batchName: 'x', batchCode: 'B1', numberOfBirds: '10', startDate: '2026-01-01')],
        houses: [HouseRow(key: 'h1', houseName: 'Pen 1'), HouseRow(key: 'h2', houseName: 'pen  1')],
        flocks: [flock('5', '6', name: 'A'), flock('5', '5', name: 'a', houseKey: 'h2')],
      );
      final v = validateSetup(d, ctx(batches: const [
        ExistingBatch(batchId: 1, batchCode: 'b1', batchName: 'Old', breed: '', numberOfBirds: 5),
      ]));
      final messages = v.errors.map((e) => e.message).toList();
      expect(messages, contains('A batch with code "B1" already exists — reuse it instead of creating a second one.'));
      expect(messages, contains('"pen  1" appears more than once in this setup.'));
      expect(messages, contains('There cannot be more birds standing (6) than were placed (5).'));
      expect(messages, contains('"A" appears more than once in this setup.'));
    });

    test('spread evenly and fill to capacity', () {
      final d = SetupDraft(
        houses: [
          HouseRow(key: 'h1', houseName: 'Pen 1', capacity: '300'),
          HouseRow(key: 'h2', houseName: 'Pen 2'),
          HouseRow(key: 'h3', houseName: 'Pen 3', existingHouseId: 9),
        ],
        flocks: [flock('', '', houseKey: 'h1'), flock('', '', houseKey: 'h2'), flock('', '', houseKey: 'h3')],
      );
      distributePensEvenly(d, 'b1', 1000);
      expect([for (final f in d.flocks) f.originallyPlaced], ['334', '333', '333']);
      expect([for (final f in d.flocks) f.currentLiveBirds], ['334', '333', '333']);

      final c = ctx(houses: const [ExistingHouse(houseId: 9, houseName: 'Pen 3', capacity: 100, occupied: 40)]);
      fillPensToCapacity(d, c, 'b1', 1000);
      expect([for (final f in d.flocks) f.originallyPlaced], ['300', '700', '']);
    });

    test('naming: generators, the next number, and a name that follows its pen', () {
      expect(nextStartNumber('Pen', ['Pen 1', 'pen  4', 'Pen 3A', 'Pens 9', 'pen7']), 8);
      expect(generateHouseRows(count: 2, prefix: 'Pen', startNumber: 5, capacity: '50').map((h) => h.houseName), ['Pen 5', 'Pen 6']);
      final b = generateBatches(
          count: 2, prefix: 'Batch', codePrefix: 'B', startNumber: 3, breed: 'Isa Brown', numberOfBirds: '100', startDate: '2026-01-01');
      expect(b.map((x) => '${x.batchName}/${x.batchCode}'), ['Batch 3/B3', 'Batch 4/B4']);
      expect(renameForHouse('B1 - Pen 1', 'B1', 'Pen 1', 'Pen 2'), 'B1 - Pen 2');
      expect(renameForHouse('Layers east', 'B1', 'Pen 1', 'Pen 2'), 'Layers east');
    });

    test('the request: an age becomes an estimated date; history goes to the buckets', () {
      final f = flock('100', '90')
        ..ageMode = 'age'
        ..currentAgeInWeeks = '10';
      final d = SetupDraft(
        batches: [BatchRow(key: 'b1', batchName: 'B', batchCode: 'B1', numberOfBirds: '100', startDate: '2026-01-01', costPerChick: '2.5')],
        houses: [HouseRow(key: 'h1', houseName: 'Pen 1', capacity: '200')],
        flocks: [f],
      );
      final r = toRequest(d, ctx(), 'u1', 'farm-1');
      final rf = (r['Flocks'] as List).single as Map;
      expect(rf['StartDate'], isNull);
      expect(rf['CurrentAgeInWeeks'], 10);
      expect(rf['OtherAdjustment'], 10);
      expect(resolveStartDate(f, '2026-10-02').date, '2026-07-24');
      final rb = (r['Batches'] as List).single as Map;
      expect(rb['StartDate'], '2026-01-01T00:00:00');
      expect(rb['CostPerChick'], 2.5);
      expect(rb['IsHistorical'], true);
      expect(((r['Houses'] as List).single as Map)['Capacity'], 200);
    });

    test("a draft saved by the web reads back, and the phone's draft reads on the web", () {
      final web = {
        'mode': 'existing',
        'batches': [
          {
            'key': 'batch-ab12-1', 'batchName': 'Batch 1', 'batchCode': 'B1', 'breed': '', 'numberOfBirds': '500',
            'startDate': '2026-01-01', 'costPerChick': '', 'isHistorical': true, 'totalCost': '', 'amountPaid': '',
            'supplierType': 'local', 'dollarConversionRate': '', 'orderPlacementDate': '', 'estimatedArrivalDate': '',
          },
        ],
        'houses': [
          {'key': 'house-ab12-2', 'existingHouseId': 4, 'houseName': 'Pen 1', 'capacity': '600', 'location': ''},
        ],
        'flocks': [
          {
            'key': 'flock-ab12-3', 'batchKey': 'batch-ab12-1', 'houseKey': 'house-ab12-2', 'name': 'B1 - Pen 1',
            'originallyPlaced': '500', 'currentLiveBirds': '480', 'ageMode': 'date', 'startDate': '2026-01-01',
            'currentAgeInWeeks': '', 'breed': '', 'hasArrived': true, 'historyKnown': true, 'reconciliationTouched': false,
            'historicalMortality': '20', 'historicalSold': '', 'historicalCulled': '', 'historicalTransferred': '',
          },
        ],
      };
      final d = SetupDraft.fromJson(jsonDecode(jsonEncode(web)))!;
      expect(d.houses.single.existingHouseId, 4);
      expect(breakdown(d.flocks.single).mortality, 20);
      expect(d.toJson(), web, reason: 'the same shape goes back');
      expect(SetupDraft.fromJson({'nonsense': 1}), isNull);
    });
  });

  group('screen', () {
    Map<String, dynamic> context0({bool complete = false}) => {
          'status': {
            'isComplete': complete, 'looksEmpty': true, 'existingBatches': 0, 'existingHouses': 0, 'existingFlocks': 0,
            'batchCount': 1, 'flockCount': 2, 'openingLiveBirds': 980, 'historicalReduction': 20,
            'completedBusinessDate': '2026-10-02T00:00:00',
          },
          'businessDate': '2026-10-02T00:00:00',
          'batches': [], 'houses': [], 'flocks': [], 'existingFlockNames': [], 'allocatedByBatchId': {},
        };

    FakeApi setupApi({Map<String, dynamic>? draft}) => FakeApi()
      ..gets['/api/CompanyTime/context'] = {'businessDate': '2026-10-02'}
      ..gets['/api/PoultryFarmSetup/context'] = context0()
      ..gets['/api/PoultryFarmSetup/opening-positions'] = {'flockCount': 0, 'positions': []}
      ..gets['/api/Supplier'] = [
        {'supplierId': 3, 'name': 'Hatchery Ltd'},
      ]
      ..gets['/api/Poultry/cash-accounts'] = [
        {'poultryCashAccountId': 8, 'accountName': 'Cash box', 'currentBalance': 1500, 'isActive': true},
        {'poultryCashAccountId': 9, 'accountName': 'Closed', 'currentBalance': 0, 'isActive': false},
      ]
      ..gets['/api/PoultryFarmSetup/draft'] = draft ?? {'hasDraft': false};

    final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

    Future<void> into(WidgetTester tester, Finder f) async {
      await tester.scrollUntilVisible(f, 250, scrollable: list);
      await tester.pumpAndSettle();
    }

    Future<void> type(WidgetTester tester, String key, String text) async {
      final f = find.byKey(ValueKey(key));
      await into(tester, f);
      await tester.enterText(f, text);
      await tester.pump();
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      await into(tester, find.text(text).first);
      await tester.tap(find.text(text).first);
      await tester.pumpAndSettle();
    }

    testWidgets('the whole flow on a phone: pens, batch, allocation, reconciliation, review, complete', (tester) async {
      final api = setupApi()
        ..writeAnswers['/api/PoultryFarmSetup/complete'] = {
          'success': true, 'batchesCreated': 1, 'housesCreated': 2, 'flocksCreated': 2, 'openingLiveBirds': 980,
          'historicalReduction': 20,
        };
      await open(tester, InitialFarmSetupScreen(session: await sessionFor(api), company: company), size: phone);

      expect(find.text('Set Up Your Farm'), findsOneWidget);
      await tapText(tester, 'Quick Farm Setup');
      expect(find.text('Houses/Pens'), findsOneWidget);
      expect(find.text('Step 1 of 5'), findsWidgets);

      // ---- Houses: two pens of 600.
      await type(tester, 'gen.penCount', '2');
      await type(tester, 'gen.penCapacity', '600');
      await tapText(tester, 'Create New Houses/Pens');
      await into(tester, find.text('PEN 2'));
      expect(find.text('PEN 1'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // ---- Batches: one historical batch of 1,000, bought from a supplier, paid from cash.
      expect(find.text('What batches/groups of birds do you currently have?'), findsOneWidget);
      await type(tester, 'gen.batchCount', '1');
      await type(tester, 'gen.batchBirds', '1000');
      await tapText(tester, 'Create New Batches');
      // The batch's own Start Date (the generator's default date comes first).
      await into(tester, find.text('Start Date *'));
      await tester.ensureVisible(find.text('Pick a date').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pick a date').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await type(tester, 'b.${(await _batchKey(tester))}.cost', '2');
      expect(find.byKey(ValueKey('b.${await _batchKey(tester)}.total')), findsOneWidget);
      expect(tester.widget<EditableText>(find.descendant(
              of: find.byKey(ValueKey('b.${await _batchKey(tester)}.total')), matching: find.byType(EditableText))).controller.text,
          '2000', reason: 'cost × birds');
      await into(tester, find.text('No supplier'));
      await tester.tap(find.text('No supplier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hatchery Ltd').last);
      await tester.pumpAndSettle();
      await into(tester, find.text('None'));
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      expect(find.text('Closed (0.00)'), findsNothing, reason: 'inactive accounts are not offered');
      await tester.tap(find.text('Cash box (1,500.00)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // ---- Allocation: choose the batch, both pens, spread evenly, 20 lost in Pen 1.
      expect(find.text('Select a Batch'), findsOneWidget);
      await tester.tap(find.text('Choose the batch to divide'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B1 · Batch 1 · 1,000 of 1,000 birds left').last);
      await tester.pumpAndSettle();
      expect(find.text('Choose Houses/Pens'), findsOneWidget);
      await tapText(tester, 'Select all');
      expect(find.text('2 selected'), findsOneWidget);
      await tapText(tester, 'Continue to allocation');
      await tapText(tester, 'Spread evenly');
      expect(find.text('Fully allocated.'), findsOneWidget);
      final live = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.endsWith('.live')).first;
      await tester.scrollUntilVisible(live, 250, scrollable: list);
      await tester.enterText(live, '480');
      await tester.pump();
      expect(find.text('−20'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // ---- Reconciliation: pre-filled as mortality; 5 sold comes out of it.
      expect(find.text('What happened to the missing birds?'), findsOneWidget);
      final sold = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.endsWith('.historicalSold'));
      await tester.enterText(sold, '5');
      await tester.pump();
      expect(find.text('20 of 20 accounted for; the remaining 0 is recorded as unknown, not as mortality.'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // ---- Review, then create.
      expect(find.text('Farm setup summary'), findsOneWidget);
      expect(find.text('980'), findsWidgets);
      await tester.tap(find.text('Complete Farm Setup'));
      await tester.pumpAndSettle();

      final body = api.lastBody('/api/PoultryFarmSetup/complete');
      expect(body['SetupMode'], 'ExistingFarm');
      final batches = body['Batches'] as List;
      expect((batches.single as Map)['NumberOfBirds'], 1000);
      expect((batches.single as Map)['SupplierId'], 3);
      expect((batches.single as Map)['PoultryCashAccountId'], 8);
      expect((batches.single as Map)['TotalCost'], 2000);
      final flocks = (body['Flocks'] as List).cast<Map>();
      expect(flocks.map((f) => f['CurrentLiveBirds']), [480, 500]);
      expect(flocks.first['HistoricalMortality'], 15);
      expect(flocks.first['HistoricalSold'], 5);
      expect(flocks.first['OtherAdjustment'], 0);
      expect((body['Houses'] as List).map((h) => (h as Map)['HouseName']), ['Pen 1', 'Pen 2']);
      expect(find.text('Your farm is ready.'), findsOneWidget);
      expect(api.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/PoultryFarmSetup/draft'), isTrue,
          reason: 'the finished draft is discarded');
    });

    testWidgets('a saved draft is offered, resumes at its step, and edits save after a pause', (tester) async {
      final saved = SetupDraft(
        batches: [BatchRow(key: 'b1', batchName: 'Batch 1', batchCode: 'B1', numberOfBirds: '100', startDate: '2026-01-01')],
        houses: [HouseRow(key: 'h1', houseName: 'Pen 1')],
      );
      final api = setupApi(draft: {
        'hasDraft': true,
        'draft': {
          'farmId': 'farm-1', 'draft': jsonEncode(saved.toJson()), 'step': 1, 'phase': 'batch',
          'updatedBy': 'ama', 'updatedAt': '2026-10-02T09:30:00Z',
        },
      });
      await open(tester, InitialFarmSetupScreen(session: await sessionFor(api), company: company), size: phone);
      expect(find.text('You have an unfinished setup'), findsOneWidget);
      expect(find.text('1 batch · 1 pen · 0 flocks — Batches'), findsOneWidget);
      expect(find.text('Last edited 2 Oct 2026, 09:30 by ama.'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(find.text('What batches/groups of birds do you currently have?'), findsOneWidget);
      await type(tester, 'b.b1.name', 'Layers 2026');
      await tester.pump(const Duration(milliseconds: 1300));
      final put = api.lastBody('/api/PoultryFarmSetup/draft', 'PUT');
      expect(put['Step'], 1);
      expect((jsonDecode(put['Draft'] as String) as Map)['batches'][0]['batchName'], 'Layers 2026');

      // The phone's Back walks back a step instead of leaving.
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      await nav.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Where are your birds housed?'), findsOneWidget);
    });

    testWidgets('over-allocating a batch offers the bird-count fix', (tester) async {
      final api = setupApi()
        ..gets['/api/PoultryFarmSetup/context'] = {
          ...context0(),
          'batches': [
            {'batchId': 5, 'batchCode': 'B5', 'batchName': 'Batch 5', 'breed': 'Isa Brown', 'numberOfBirds': 100, 'isHistorical': false},
          ],
          'houses': [
            {'houseId': 2, 'houseName': 'Pen A', 'capacity': 1000, 'occupied': 0, 'activeFlocks': 0},
          ],
        };
      await open(tester, InitialFarmSetupScreen(session: await sessionFor(api), company: company), size: phone);
      await tapText(tester, 'Quick Farm Setup');
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose the batch to divide'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('B5 · Batch 5').last);
      await tester.pumpAndSettle();
      await tapText(tester, 'Select all');
      await tapText(tester, 'Continue to allocation');
      final placed = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.endsWith('.placed'));
      await tester.scrollUntilVisible(placed, 250, scrollable: list);
      await tester.enterText(placed, '150');
      await tester.pump();
      await tester.drag(list, const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(find.textContaining('This allocation is 50 birds more than B5 has.'), findsOneWidget);
      await tester.ensureVisible(find.text('Update B5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update B5'));
      await tester.pumpAndSettle();
      expect(find.text('Update B5 bird count'), findsOneWidget);
      expect(find.textContaining('This also adds 50 birds to your bird stock'), findsOneWidget);
    });
  });
}

/// The key of the one new batch row on screen (generated keys are random).
Future<String> _batchKey(WidgetTester tester) async {
  final f = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.endsWith('.name') &&
      '${(w.key as ValueKey).value}'.startsWith('b.'));
  final k = '${(tester.widget(f.first).key as ValueKey).value}';
  return k.substring(2, k.length - '.name'.length);
}
