// Report 34, part 1: the 28 Oct – 9 Nov web pull (merge 9202743d), Poultry
// broilers. Flocks have a flock type (Layer | Broiler, migration 399), picked
// on Add / Edit Flock and on Divide Batch Into Flocks, and the new
// Operations → Production → Weigh-ins page (migration 400). At phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/batch_allocation_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/flock_form_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/flock_type.dart';
import 'package:poultrycore_mobile/pages/poultry/weigh_in_stats.dart';
import 'package:poultrycore_mobile/pages/poultry/weigh_ins_screen.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  expect(f, findsWidgets);
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
}

Future<void> tapIt(WidgetTester tester, Finder f) async {
  await see(tester, f);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

const _autoHint = "Set from the breed and your company type. Change it if it's wrong.";

Map<String, dynamic> _flock({
  int id = 1,
  String name = 'House A',
  String? type,
  String? closed,
  String breed = 'Cobb 500',
}) =>
    {
      'flockId': id,
      'name': name,
      'breed': breed,
      'startDate': '2026-10-01T00:00:00',
      'quantity': 500,
      'active': true,
      'hasArrived': true,
      'batchId': 7,
      'houseId': null,
      'farmId': 'farm-1',
      'flockType': ?type,
      'closedDate': ?closed,
    };

FakeApi _farm({String? businessType}) {
  clearPoultryBusinessTypes();
  final api = FakeApi();
  api.gets['/api/MainFlockBatch'] = [
    {'batchId': 7, 'batchName': 'Batch Seven', 'numberOfBirds': 1000, 'startDate': '2026-10-01T00:00:00', 'breed': 'Isa Brown'},
  ];
  api.gets['/api/House'] = [
    {'houseId': 3, 'houseName': 'Pen 3', 'capacity': 2000},
  ];
  api.gets['/api/Flock'] = [];
  if (businessType == null) {
    api.statuses['/api/Poultry/company'] = 404;
  } else {
    api.gets['/api/Poultry/company'] = {'businessType': businessType};
  }
  return api;
}

Map<String, dynamic> _wi(int id, String date, int age, double avg, {double? gain, int? since, List<double>? weights, int n = 10}) => {
      'weighInId': id,
      'flockId': 1,
      'flockName': 'House A',
      'flockType': 'Broiler',
      'weighDate': date,
      'ageInDays': age,
      'sampleSize': n,
      'avgWeightG': avg,
      'minWeightG': avg - 100,
      'maxWeightG': avg + 100,
      'uniformityPct': 80.0,
      'cvPct': 7.5,
      'weightsG': weights,
      'notes': null,
      'prevAvgWeightG': null,
      'daysSincePrev': since,
      'dailyGainG': gain,
    };

void main() {
  // --------------------------------------------------- weigh-in-stats.test.ts
  group('computeWeighInStats (the web\'s cases)', () {
    test('1a: an even spread', () {
      final s = computeWeighInStats([1800, 1900, 2000, 2100, 2200])!;
      expect([s.sampleSize, s.avgWeightG, s.minWeightG, s.maxWeightG, s.uniformityPct, s.cvPct],
          [5, 2000, 1800, 2200, 100, 7.91]);
    });
    test('1b: outliers pull uniformity down and CV up', () {
      final s = computeWeighInStats([1000, 2000, 2000, 2000, 3000])!;
      expect(s.uniformityPct, 60);
      expect(s.cvPct, 35.36);
    });
    test('1c: one bird has no spread', () {
      final s = computeWeighInStats([1500])!;
      expect(s.uniformityPct, 100);
      expect(s.cvPct, isNull);
    });
    test('1d: exactly ±10% counts as uniform', () {
      expect(computeWeighInStats([2000, 1800, 2200])!.uniformityPct, 100);
    });
    test('nothing weighed, nothing computed', () => expect(computeWeighInStats([]), isNull));
  });

  group('parseWeights / formatWeight', () {
    test('splits on spaces, commas, semicolons and lines', () {
      expect(parseWeights('1850, 1920 1780;\n2010', WeightUnit.g).weightsG, [1850, 1920, 1780, 2010]);
    });
    test('converts kilograms', () {
      expect(parseWeights('1.85 2.1', WeightUnit.kg).weightsG, [1850, 2100]);
    });
    test('keeps what it cannot read', () {
      final p = parseWeights('1850 abc 0 -5 25000', WeightUnit.g);
      expect(p.weightsG, [1850]);
      expect(p.invalid, ['abc', '0', '-5', '25000']);
    });
    test('grams under a kilo, kilos above', () {
      expect(formatWeight(450), '450 g');
      expect(formatWeight(1850), '1.85 kg');
      expect(formatWeight(null), '—');
    });
  });

  // ------------------------------------------------------- flock-type.test.ts
  group('flock type rules (the web\'s cases)', () {
    test('isBroilerBreed', () {
      expect(isBroilerBreed('Cobb 500'), isTrue);
      expect(isBroilerBreed('ross 308'), isTrue);
      expect(isBroilerBreed('  Arbor   Acres '), isTrue);
      expect(isBroilerBreed('Broiller'), isTrue);
      expect(isBroilerBreed('Hubbard Classic'), isTrue);
      expect(isBroilerBreed('Isa Brown'), isFalse);
      expect(isBroilerBreed('Sasso'), isFalse);
      expect(isBroilerBreed(''), isFalse);
      expect(isBroilerBreed(null), isFalse);
    });
    test('defaultFlockType: breed first, then company, then Layer', () {
      expect(defaultFlockType('Cobb 500', 'Layers'), 'Broiler');
      expect(defaultFlockType('Local', 'Broilers'), 'Broiler');
      expect(defaultFlockType('Local', 'Both'), 'Layer');
      expect(defaultFlockType('Isa Brown', null), 'Layer');
    });
    test('flockTypeOf treats a missing type as Layer', () {
      expect(flockTypeOf({}), 'Layer');
      expect(flockTypeOf(null), 'Layer');
      expect(flockTypeOf({'flockType': 'Broiler'}), 'Broiler');
      expect(flockTypeOf({'FlockType': 'Broiler'}), 'Broiler');
    });
  });

  // ----------------------------------------------------- Add / Edit Flock
  group('Flock type on Add / Edit Flock', () {
    testWidgets('a new flock starts automatic, from the company type, and sends nothing', (tester) async {
      final api = _farm(businessType: 'Broilers');
      final s = await sessionFor(api);
      await open(tester, FlockFormScreen(session: s, company: company), size: phone);

      expect(find.text('Flock type'), findsOneWidget);
      expect(find.text('Layers (eggs)'), findsOneWidget);
      expect(find.text('Broilers (meat)'), findsOneWidget);
      expect(find.text(_autoHint), findsOneWidget);
      final broiler = tester.widget<Semantics>(find.ancestor(of: find.byKey(const ValueKey('flock-type-Broiler')), matching: find.byType(Semantics)).first);
      expect(broiler.properties.checked, isTrue, reason: 'Broilers company → Broiler by default');

      // Batch (prefills the start date), name, birds; then save.
      await tapIt(tester, find.text('Please select a batch'));
      await tester.tap(find.text('Batch Seven').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Broiler pen');
      await see(tester, find.text('Number of Birds'));
      await enter(tester, 'Number of Birds', '200');
      await tapIt(tester, find.text('Create Flock'));
      final body = api.lastBody('/api/Flock');
      expect(body.containsKey('flockType'), isFalse, reason: 'automatic = the database default');
      expect(body['breed'], 'Isa Brown');
    });

    testWidgets('choosing a type makes it explicit and it is sent', (tester) async {
      final api = _farm(businessType: 'Layers');
      final s = await sessionFor(api);
      await open(tester, FlockFormScreen(session: s, company: company), size: phone);
      await tapIt(tester, find.byKey(const ValueKey('flock-type-Broiler')));
      expect(find.text(_autoHint), findsNothing);
      expect(find.text('Meat birds: no egg records for this flock.'), findsOneWidget);

      await tapIt(tester, find.text('Please select a batch'));
      await tester.tap(find.text('Batch Seven').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Broiler pen');
      await see(tester, find.text('Number of Birds'));
      await enter(tester, 'Number of Birds', '200');
      await tapIt(tester, find.text('Create Flock'));
      expect(api.lastBody('/api/Flock')['flockType'], 'Broiler');
    });

    testWidgets('an existing flock shows its stored type, and a change is saved', (tester) async {
      final api = _farm(businessType: 'Layers');
      final s = await sessionFor(api);
      await open(tester, FlockFormScreen(session: s, company: company, existing: _flock(type: 'Broiler')), size: phone);
      expect(find.text(_autoHint), findsNothing);
      expect(find.text('Meat birds: no egg records for this flock.'), findsOneWidget);

      await tapIt(tester, find.byKey(const ValueKey('flock-type-Layer')));
      expect(find.text('Laying birds: egg records are kept for this flock.'), findsOneWidget);
      await tapIt(tester, find.text('Update Flock'));
      expect(api.lastBody('/api/Flock/1', 'PUT')['flockType'], 'Layer');
    });

    testWidgets('a flock saved before 399 (no type) edits as Layer', (tester) async {
      final api = _farm();
      final s = await sessionFor(api);
      await open(tester, FlockFormScreen(session: s, company: company, existing: _flock()), size: phone);
      await tapIt(tester, find.text('Update Flock'));
      expect(api.lastBody('/api/Flock/1', 'PUT')['flockType'], 'Layer');
    });

    test('Flock Groups rows: a broiler flock carries the Broiler badge', () {
      final badge = rowBadges['flocks']!;
      expect(badge(_flock(type: 'Broiler')), isA<BroilerBadge>());
      expect(badge(_flock(type: 'Layer')), isNull);
      expect(badge(_flock()), isNull);
    });
  });

  // ------------------------------------------------- Divide Batch Into Flocks
  group('Flock type on Divide Batch Into Flocks', () {
    FakeApi allocFarm(String? businessType) {
      final api = _farm(businessType: businessType);
      api.gets['/api/Flock/allocation-context/7'] = {
        'batch': {'batchCode': 'B7', 'batchName': 'Batch Seven', 'breed': 'Ross 308', 'startDate': '2026-10-01', 'originalBirds': 1000, 'allocatedBirds': 0, 'unallocatedBirds': 1000},
        'houses': [
          {'houseId': 3, 'houseName': 'Pen 3', 'capacity': 2000, 'occupied': 0},
        ],
        'existingFlockNames': [],
      };
      api.writeAnswers['/api/Flock/bulk-allocate'] = {'createdCount': 1, 'birdsAllocated': 1000, 'batch': {'unallocatedBirds': 0}};
      return api;
    }

    Future<void> allocateAll(WidgetTester tester) async {
      await tapIt(tester, find.text('Select all'));
      await tapIt(tester, find.text('Distribute Equally'));
      await tapIt(tester, find.text('Review & Create'));
      await tapIt(tester, find.text('Create 1 Flock'));
    }

    testWidgets('automatic from the batch breed: nothing is sent', (tester) async {
      final api = allocFarm('Layers');
      final s = await sessionFor(api);
      await open(tester, BatchAllocationScreen(session: s, company: company, batchId: 7), size: phone);
      expect(find.text(_autoHint), findsOneWidget);
      final broiler = tester.widget<Semantics>(find.ancestor(of: find.byKey(const ValueKey('flock-type-Broiler')), matching: find.byType(Semantics)).first);
      expect(broiler.properties.checked, isTrue, reason: 'Ross 308 is a broiler breed');
      await allocateAll(tester);
      expect(api.lastBody('/api/Flock/bulk-allocate').containsKey('FlockType'), isFalse);
    });

    testWidgets('a chosen type goes with every flock', (tester) async {
      final api = allocFarm('Layers');
      final s = await sessionFor(api);
      await open(tester, BatchAllocationScreen(session: s, company: company, batchId: 7), size: phone);
      await tapIt(tester, find.byKey(const ValueKey('flock-type-Layer')));
      await allocateAll(tester);
      expect(api.lastBody('/api/Flock/bulk-allocate')['FlockType'], 'Layer');
    });
  });

  // ----------------------------------------------------------------- Weigh-ins
  group('Weigh-ins page', () {
    test('sits in Operations → Production after Batch Production, and opens its own screen', () {
      final prod = webNavGroups['poultry']!
          .firstWhere((g) => g.title == 'Operations')
          .subGroups
          .firstWhere((g) => g.title == 'Production')
          .links
          .map((l) => l.href)
          .toList();
      expect(prod.indexOf('/poultry-weigh-ins'), prod.indexOf('/batch-production-records') + 1);
      expect(pageScreens['/poultry-weigh-ins'], isNotNull);
    });

    FakeApi wiFarm() {
      final api = FakeApi();
      api.gets['/api/CompanyTime/context'] = {'businessDate': '2026-11-09', 'companyLocalDateTime': '2026-11-09T10:00:00', 'utcNow': '2026-11-09T10:00:00Z'};
      api.gets['/api/Flock'] = [
        _flock(id: 1, name: 'House A', type: 'Broiler'),
        _flock(id: 2, name: 'Alpha layers', type: 'Layer', breed: 'Isa Brown'),
        _flock(id: 3, name: 'Old flock', type: 'Broiler', closed: '2026-09-30'),
      ];
      api.gets['/api/Poultry/weigh-ins'] = [
        _wi(10, '2026-10-08', 7, 180, n: 20, weights: null),
        _wi(11, '2026-10-15', 14, 450, gain: 38.6, since: 7, n: 25, weights: [400, 450, 500]),
      ];
      return api;
    }

    testWidgets('the flock, the four figures, the curve and the weigh-ins', (tester) async {
      final api = wiFarm();
      final s = await sessionFor(api);
      await open(tester, WeighInsScreen(session: s, company: company), size: phone);

      expect(find.text('Weigh a sample of birds to follow how a flock is growing.'), findsOneWidget);
      // Running broilers before layers, so House A is chosen first.
      expect(find.text('House A · Broiler'), findsOneWidget);
      expect(find.text('Broiler'), findsOneWidget);
      expect(find.text('· started 01 Oct 2026'), findsOneWidget);
      expect(api.requests.any((r) => r.url.path == '/api/Poultry/weigh-ins' && r.url.queryParameters['flockId'] == '1'), isTrue);

      expect(find.text('LATEST AVERAGE'), findsOneWidget);
      expect(find.text('450 g'), findsWidgets);
      expect(find.text('Day 14 · 15 Oct 2026'), findsOneWidget);
      expect(find.text('38.6 g'), findsOneWidget);
      expect(find.text('over the last 7 days'), findsOneWidget);
      expect(find.text('80.0%'), findsOneWidget);
      expect(find.text('45 birds weighed'), findsOneWidget);
      expect(find.byType(GrowthChart), findsOneWidget);

      // The curve: tap the second point for its details.
      await see(tester, find.byType(GrowthChart));
      final chart = tester.getRect(find.byType(GrowthChart));
      // Heaviest average 450 g → axis top 600 g; plot 208 px tall from y = 8.
      await tester.tapAt(Offset(chart.right - 16, chart.top + 8 + 208 * (1 - 450 / 600)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('growth-tooltip')), findsOneWidget);
      expect(find.text('Gain 38.6 g/day'), findsOneWidget);

      // Newest first.
      await see(tester, find.byKey(const ValueKey('weigh-in-10')));
      final y11 = tester.getTopLeft(find.byKey(const ValueKey('weigh-in-11'))).dy;
      final y10 = tester.getTopLeft(find.byKey(const ValueKey('weigh-in-10'))).dy;
      expect(y11 < y10, isTrue);
      expect(find.text('15 Oct 2026 · 25 birds'), findsOneWidget);
      expect(find.text('Gain 38.6 g/day · Uniformity 80.0%'), findsOneWidget);
      expect(find.text('Gain — · Uniformity 80.0%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the flock list is grouped, and a closed flock is read-only', (tester) async {
      final api = wiFarm();
      final s = await sessionFor(api);
      await open(tester, WeighInsScreen(session: s, company: company), size: phone);
      await tester.tap(find.byKey(const ValueKey('weigh-in-flock')));
      await tester.pumpAndSettle();
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Alpha layers'), findsWidgets);
      await tester.tap(find.text('Old flock').last);
      await tester.pumpAndSettle();
      expect(find.text('Closed: weigh-ins are read-only'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('weigh-in-new'))).onPressed, isNull);
      await see(tester, find.byTooltip('Edit weigh-in'));
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.edit_outlined).first).onPressed, isNull);
    });

    testWidgets('New weigh-in, bird by bird: the preview, then the weights are sent', (tester) async {
      final api = wiFarm();
      final s = await sessionFor(api);
      await open(tester, WeighInsScreen(session: s, company: company), size: phone);
      await tapIt(tester, find.byKey(const ValueKey('weigh-in-new')));
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('New weigh-in')), findsOneWidget);
      expect(find.text('Weigh a sample of birds spread across the house, not just the ones nearest the door.'), findsOneWidget);
      expect(find.text('Bird by bird'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('weigh-in-save'))).onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('weigh-in-weights')), '1800 1900 abc');
      await tester.pumpAndSettle();
      expect(find.text('Not a weight: abc'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('weigh-in-weights')), '1800, 1900 2000\n2100 2200');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('weigh-in-preview')), findsOneWidget);
      expect(find.text('2.00 kg'), findsOneWidget);
      expect(find.text('100.0%'), findsOneWidget);
      expect(find.text('7.91%'), findsOneWidget);

      // Kilograms: the same birds.
      await tester.tap(find.byKey(const ValueKey('toggle-kilograms')));
      await tester.enterText(find.byKey(const ValueKey('weigh-in-weights')), '1.8 1.9 2 2.1 2.2');
      await tester.pumpAndSettle();
      expect(find.text('Separate birds with spaces, commas or new lines. Use a point for decimals (1.85).'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('weigh-in-save')));
      await tester.tap(find.byKey(const ValueKey('weigh-in-save')));
      await tester.pumpAndSettle();

      final body = api.lastBody('/api/Poultry/weigh-ins');
      expect(body['flockId'], 1);
      expect(body['weighDate'], '2026-11-09', reason: "the company's business date");
      expect(body['weightsG'], [1800, 1900, 2000, 2100, 2200]);
      expect(body.containsKey('avgWeightG'), isFalse);
      expect(body['farmId'], 'farm-1');
      expect(find.text('Weigh-in saved'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Summary only: count and average are required; the rest is optional', (tester) async {
      final api = wiFarm();
      final s = await sessionFor(api);
      await open(tester, WeighInsScreen(session: s, company: company), size: phone);
      await tapIt(tester, find.byKey(const ValueKey('weigh-in-new')));
      await tester.tap(find.byKey(const ValueKey('toggle-Summary only')));
      await tester.pumpAndSettle();
      await enter(tester, 'Birds weighed *', '30');
      await tester.pumpAndSettle();
      expect(find.text('Enter the average weight in grams.'), findsOneWidget);
      await enter(tester, 'Average (g) *', '1450.5');
      await enter(tester, 'Uniformity (%)', '82');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('weigh-in-save')));
      await tester.tap(find.byKey(const ValueKey('weigh-in-save')));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/weigh-ins');
      expect(body['sampleSize'], 30);
      expect(body['avgWeightG'], 1450.5);
      expect(body['uniformityPct'], 82);
      expect(body['cvPct'], isNull);
      expect(body.containsKey('weightsG'), isFalse);
    });

    testWidgets('Edit: a summary weigh-in opens as a summary; a weighed one with its weights', (tester) async {
      final api = wiFarm();
      final s = await sessionFor(api);
      await open(tester, WeighInsScreen(session: s, company: company), size: phone);
      await see(tester, find.byKey(const ValueKey('weigh-in-10')));
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('weigh-in-10')), matching: find.byTooltip('Edit weigh-in')));
      await tester.pumpAndSettle();
      expect(find.text('Edit weigh-in'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '20'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '180'), findsOneWidget);
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final put = api.lastBody('/api/Poultry/weigh-ins/10', 'PUT');
      expect(put['sampleSize'], 20);
      expect(put['weighDate'], '2026-10-08');
      expect(find.text('Weigh-in updated'), findsOneWidget);

      await see(tester, find.byKey(const ValueKey('weigh-in-11')));
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('weigh-in-11')), matching: find.byTooltip('Edit weigh-in')));
      await tester.pumpAndSettle();
      expect(find.text('400 450 500'), findsOneWidget);
    });

    testWidgets('Delete asks for a reason from the list, then sends it', (tester) async {
      final api = wiFarm();
      final s = await sessionFor(api);
      await open(tester, WeighInsScreen(session: s, company: company), size: phone);
      await see(tester, find.byKey(const ValueKey('weigh-in-11')));
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('weigh-in-11')), matching: find.byTooltip('Delete weigh-in')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this weigh-in?'), findsOneWidget);
      expect(find.text('450 g on 15 Oct 2026. It is kept in the record as deleted, with your reason.'), findsOneWidget);
      await reasonPick(tester, 'Wrong flock');
      await tester.tap(find.text('Delete weigh-in').last);
      await tester.pumpAndSettle();
      final del = api.writes.lastWhere((w) => w.method == 'DELETE');
      expect(del.url.path, '/api/Poultry/weigh-ins/11');
      expect(del.url.queryParameters['reason'], 'Wrong flock');
      expect(del.url.queryParameters['farmId'], 'farm-1');
      expect(find.text('Weigh-in deleted'), findsOneWidget);
    });

    testWidgets('no weigh-ins yet', (tester) async {
      final api = wiFarm()..gets['/api/Poultry/weigh-ins'] = [];
      final s = await sessionFor(api);
      await open(tester, WeighInsScreen(session: s, company: company), size: phone);
      expect(find.text('No weigh-ins yet'), findsOneWidget);
      expect(find.text('Needs two weigh-ins'), findsOneWidget);
      expect(find.text('No weigh-ins for this flock yet.'), findsOneWidget);
    });
  });
}
