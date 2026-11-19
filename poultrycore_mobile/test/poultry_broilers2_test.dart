// Report 34, part 2: the 28 Oct – 9 Nov web pull (merge 9202743d), Poultry
// broilers continued. Broiler performance (402), bird sales by the kg (401)
// and a broiler-only company hiding its egg pages (399). The web's own test
// cases first, then the screens at phone width. The sale form, close-out
// wizard and production forms are covered in their own test files.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/bird_pricing.dart';
import 'package:poultrycore_mobile/pages/poultry/broiler_performance_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/flock_closeout_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/flock_type.dart';
import 'package:poultrycore_mobile/pages/poultry/poultry_features.dart';
import 'package:poultrycore_mobile/pages/poultry/trackers/tracker_logic.dart' show isBirdSaleProduct;
import 'package:poultrycore_mobile/pages/web_nav.dart';
import 'package:poultrycore_mobile/widgets/all_pages_sheet.dart';

import 'support/harness.dart';

const _perBird = BirdPricing();
BirdPricing _kg(num? kg, num? ppk) => BirdPricing(basis: BirdPricingBasis.perKg, liveWeightKg: kg, pricePerKg: ppk);
BirdPricing _bird(num? kg) => BirdPricing(liveWeightKg: kg);

List<String> _hrefs(List<NavGroup> groups) => [
      for (final g in groups)
        for (final s in g.subGroups)
          for (final l in s.links) l.href,
    ];

void main() {
  setUp(resetPoultryFeatures);

  // ------------------------------------------------------ bird-pricing.test.ts
  group('bird pricing (the web\'s cases)', () {
    test('isLiveBirdProduct mirrors fnpoultrysale_isbirdsale', () {
      for (final p in ['Birds', 'Chicken', 'Live broilers', 'Broilers', 'Cockerels']) {
        expect(isLiveBirdProduct(p), isTrue, reason: p);
      }
      for (final p in ['Broiler feed', 'Broiler starter mash', 'Fresh Eggs', 'Dead Birds', 'Manure', '']) {
        expect(isLiveBirdProduct(p), isFalse, reason: p);
      }
    });
    test('per kg: kg × price; per-bird price = amount / birds', () {
      final amt = birdLineAmount(100, 1, _kg(250, 30));
      expect(amt, 7500);
      expect(perBirdPrice(amt, 100), 75);
    });
    test('per bird: birds × unit price, weight only recorded', () => expect(birdLineAmount(20, 80, _bird(48.5)), 1600));
    test('rounds the way the database does', () => expect(perBirdPrice(1110, 14), 79.29));
    test('average weight', () {
      expect(avgKgPerBird(100, 250), 2.5);
      expect(avgKgPerBird(0, 250), isNull);
      expect(avgKgPerBird(10, null), isNull);
    });
    test('birdPricingProblem accepts a complete line, refuses what the database refuses', () {
      expect(birdPricingProblem(100, _kg(250, 30)), isNull);
      expect(birdPricingProblem(100, _perBird), isNull);
      expect(birdPricingProblem(10, _kg(null, 30)), contains('live weight'));
      expect(birdPricingProblem(10, _kg(25, null)), contains('price per kg'));
      expect(birdPricingProblem(10.5, _kg(25, 30)), contains('whole number'));
      expect(birdPricingProblem(2, _kg(50, 30)), contains('over 20 kg'));
    });
    test('payload', () {
      expect(birdPricingPayload(_perBird), isEmpty);
      expect(birdPricingPayload(_bird(48.5)), {'pricingBasis': 'PerBird', 'liveWeightKg': 48.5, 'pricePerKg': null});
      expect(birdPricingPayload(_kg(250, 30), amountOverridden: true),
          {'pricingBasis': 'PerKg', 'liveWeightKg': 250, 'pricePerKg': 30, 'amountOverridden': true});
    });
    test('round-trips a saved line', () {
      expect(birdPricingFromLine({'pricingBasis': 'PerKg', 'liveWeightKg': 250, 'pricePerKg': 30}), _kg(250, 30));
      expect(birdPricingFromLine({}), _bird(null));
    });
    test('the saved line note', () {
      expect(birdLineNote({'quantity': 100, 'pricingBasis': 'PerKg', 'liveWeightKg': 250, 'pricePerKg': 30}),
          '250 kg at 30.00 / kg · 2.50 kg a bird');
      expect(birdLineNote({'quantity': 20, 'pricingBasis': 'PerBird', 'liveWeightKg': 48.5}), '48.5 kg live weight · 2.42 kg a bird');
      expect(birdLineNote({'quantity': 20}), isNull);
    });
    test('one bird-sale rule (403): the Birds tracker uses the database\'s rule', () {
      for (final p in ['Birds', 'Chicken', 'Live broilers', 'Broiler feed', 'Layer mash', 'Poultry manure', 'Dead Birds', 'Fresh Eggs']) {
        expect(isBirdSaleProduct(p), isLiveBirdProduct(p), reason: p);
      }
      expect(isBirdSaleProduct('Poultry manure'), isFalse);
      expect(isBirdSaleProduct('Layer mash'), isFalse);
    });
  });

  // ------------------------------------------------------- broiler-kpis.test.ts
  group('broiler totals (the web\'s cases)', () {
    final big = {'birdsStarted': 1000, 'deaths': 50, 'kgProduced': 2300, 'feedKg': 4200, 'totalCost': 5000, 'profit': 15000, 'kgIsEstimated': true};
    final small = {'birdsStarted': 100, 'deaths': 10, 'kgProduced': 200, 'feedKg': 400, 'totalCost': 600, 'profit': 300, 'kgIsEstimated': false};
    final unknown = {'birdsStarted': 200, 'deaths': 0, 'kgProduced': null, 'feedKg': 0, 'totalCost': 1000, 'profit': -1000, 'kgIsEstimated': false};

    test('one flock gives back its own figures', () {
      final t = broilerTotals([big]);
      expect((t.fcr, t.liveabilityPct, t.costPerKg), (1.826, 95, 2.17));
    });
    test('adds quantities, not ratios: FCR = total feed / total kg', () {
      final t = broilerTotals([big, small]);
      expect((t.kgProduced, t.fcr, t.liveabilityPct, t.costPerKg, t.kgIsEstimated), (2500, 1.84, 94.55, 2.24, true));
    });
    test('a flock with unknown kg is left out of FCR and cost per kg, not out of birds or profit', () {
      final t = broilerTotals([big, unknown]);
      expect((t.flocks, t.flocksWithKg, t.fcr, t.costPerKg, t.birdsStarted, t.profit), (2, 1, 1.826, 2.17, 1200, 14000));
    });
    test('nothing known, nothing claimed', () {
      final t = broilerTotals([unknown]);
      expect((t.fcr, t.costPerKg), (null, null));
      expect(broilerTotals([]).liveabilityPct, isNull);
    });
    test('formats', () {
      expect(fmtFcr(1.8261), '1.826');
      expect(fmtKgEach(2.4210526), '2.42 kg');
      expect(fmtKgTotal(2300.4), '2,300 kg');
      expect(fmtFcr(null), '—');
    });
  });

  // --------------------------------------------------------- flock-type.test.ts
  group('which pages a farm needs (the web\'s cases)', () {
    const layer = {'flockType': 'Layer'};
    const broiler = {'flockType': 'Broiler'};
    const closedLayer = {'flockType': 'Layer', 'closedDate': '2026-01-01'};
    test('showEggFeatures', () {
      expect(showEggFeatures([layer, broiler], 'Broilers'), isTrue, reason: 'any open flock lays');
      expect(showEggFeatures([broiler, closedLayer], 'Both'), isFalse);
      expect(showEggFeatures([broiler], null), isFalse);
      expect(showEggFeatures([closedLayer], 'Broilers'), isFalse);
      expect(showEggFeatures([], 'Layers'), isTrue);
      expect(showEggFeatures([], 'Both'), isTrue);
      expect(showEggFeatures(null, null), isTrue);
      expect(showEggFeatures([], null), isTrue);
      expect(showEggFeatures([{...layer, 'isDeleted': true}, broiler], null), isFalse);
    });
    test('showBroilerFeatures', () {
      expect(showBroilerFeatures([{'flockType': 'Broiler', 'closedDate': '2026-01-01'}], 'Layers'), isTrue);
      expect(showBroilerFeatures([layer], 'Both'), isTrue);
      expect(showBroilerFeatures([], 'Broilers'), isTrue);
      expect(showBroilerFeatures([layer], 'Layers'), isFalse);
      expect(showBroilerFeatures([], null), isFalse);
      expect(showBroilerFeatures([{'flockType': 'Broiler', 'isDeleted': true}], 'Layers'), isFalse);
      expect(showBroilerFeatures(null, null), isTrue);
    });
    test('broiler sales', () {
      final flocks = [
        {'batchId': 1, 'flockType': 'Broiler'}, {'batchId': 1, 'flockType': 'Broiler'},
        {'batchId': 2, 'flockType': 'Broiler'}, {'batchId': 2, 'flockType': 'Layer'},
      ];
      expect(isBroilerBatch(1, flocks, null), isTrue);
      expect(isBroilerBatch(2, flocks, null), isFalse);
      expect(isBroilerBatch(0, flocks, null), isFalse);
      expect(isBroilerBatch(9, flocks, 'Cobb 500'), isTrue);
      expect(isBroilerBatch(9, flocks, 'Isa Brown'), isFalse);
      expect(shouldSwitchToChicken('Fresh Eggs'), isTrue);
      expect(shouldSwitchToChicken(''), isTrue);
      expect(shouldSwitchToChicken('Broken Eggs'), isFalse);
      expect(shouldSwitchToChicken('Manure'), isFalse);
      expect(shouldSwitchToChicken('Chicken'), isFalse);
    });
  });

  // ------------------------------------------------------------- the menus
  group('the menus follow the flocks', () {
    FakeApi farm(List<Map<String, Object>> flocks, {String? businessType}) {
      clearPoultryBusinessTypes();
      final api = FakeApi()..gets['/api/Flock'] = flocks;
      if (businessType == null) {
        api.statuses['/api/Poultry/company'] = 403;
      } else {
        api.gets['/api/Poultry/company'] = {'businessType': businessType};
      }
      return api;
    }

    List<String> gated() => _hrefs(gatePoultryFeatureLinks(webNavGroups['poultry']!, company));

    test('Broiler performance sits in Trackers after Birds tracker', () {
      final trackers = webNavGroups['poultry']!.expand((g) => g.subGroups).firstWhere((s) => s.title == 'Trackers').links.map((l) => l.href).toList();
      expect(trackers.indexOf(broilerPerformanceHref), trackers.indexOf('/birds-left-tracker') + 1);
      expect(pageScreens[broilerPerformanceHref], isNotNull);
    });

    test('until the answers are in, everything shows (fail open)', () {
      expect(gated(), containsAll([...poultryEggOnlyHrefs.where(_hrefs(webNavGroups['poultry']!).contains), broilerPerformanceHref]));
    });

    test('a broiler-only farm loses every egg page, Quick Links included, and keeps Broiler performance', () async {
      final s = await sessionFor(farm([{'flockId': 1, 'flockType': 'Broiler'}]));
      await loadPoultryFeatures(s, company);
      final hrefs = gated();
      for (final egg in poultryEggOnlyHrefs) {
        expect(hrefs, isNot(contains(egg)), reason: egg);
      }
      expect(hrefs, contains(broilerPerformanceHref));
      expect(hrefs, contains('/production-records'));
      final quick = gatePoultryFeatureLinks(webNavGroups['poultry']!, company).firstWhere((g) => g.title == 'Quick Links');
      expect(_hrefs([quick]), isNot(contains('/poultry-egg-sorting')));
      expect(showsHomeMetric(company, 'totalEggsProduced'), isFalse);
      expect(showsHomeMetric(company, 'saleableEggs'), isFalse);
      expect(showsHomeMetric(company, 'activeBirds'), isTrue);
    });

    test('a layer farm keeps its egg pages and has no Broiler performance', () async {
      final s = await sessionFor(farm([{'flockId': 1, 'flockType': 'Layer'}], businessType: 'Layers'));
      await loadPoultryFeatures(s, company);
      final hrefs = gated();
      expect(hrefs, contains('/poultry-egg-sorting'));
      expect(hrefs, contains('/egg-tracker'));
      expect(hrefs, isNot(contains(broilerPerformanceHref)));
      expect(showsHomeMetric(company, 'totalEggsProduced'), isTrue);
    });

    test('another company, or a flock list that cannot load, hides nothing', () async {
      final s = await sessionFor(farm([{'flockId': 1, 'flockType': 'Broiler'}]));
      await loadPoultryFeatures(s, company);
      final other = Company(farmId: 'farm-2', name: 'Other', type: CompanyType.poultry);
      expect(_hrefs(gatePoultryFeatureLinks(webNavGroups['poultry']!, other)), contains('/egg-tracker'));
      final broken = FakeApi()..statuses['/api/Flock'] = 500;
      await loadPoultryFeatures(await sessionFor(broken), company, force: true);
      expect(gated(), contains('/egg-tracker'));
    });

    test('saving or deleting a flock asks again (force), otherwise the answer is kept five minutes', () async {
      final api = farm([{'flockId': 1, 'flockType': 'Layer'}]);
      final s = await sessionFor(api);
      await loadPoultryFeatures(s, company);
      api.gets['/api/Flock'] = [{'flockId': 1, 'flockType': 'Broiler'}];
      await loadPoultryFeatures(s, company);
      expect(featuresFor(company).eggs, isTrue, reason: 'kept');
      await afterDelete['flocks']!(s, company);
      expect(featuresFor(company).eggs, isFalse, reason: 'Flock Groups delete refreshes');
    });

    testWidgets('the All pages sheet drops the egg pages on a broiler-only farm', (tester) async {
      final s = await sessionFor(farm([{'flockId': 1, 'flockType': 'Broiler'}]));
      await loadPoultryFeatures(s, company);
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return Scaffold(body: TextButton(onPressed: () => showAllPages(context, s, company), child: const Text('open')));
      })));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final section in ['Analytics', 'Operations']) {
        final f = find.text(section);
        if (f.evaluate().isNotEmpty) {
          await tester.ensureVisible(f.first);
          await tester.tap(f.first);
          await tester.pumpAndSettle();
        }
      }
      expect(find.text('Egg tracker'), findsNothing);
      expect(find.text('Egg Sorting'), findsNothing);
    });
  });

  // --------------------------------------------------- Broiler performance page
  group('Broiler performance page', () {
    Map<String, Object?> kpi(int id, String name, {String? closed, num kg = 2300, num? fcr = 1.826, String? missing}) => {
          'flockId': id, 'flockName': name, 'flockType': 'Broiler', 'breed': 'Cobb 500', 'status': closed == null ? 'Active' : 'Closed',
          'closedDate': closed, 'ageInDays': 42, 'birdsStarted': 1000, 'deaths': 50, 'liveabilityPct': 95, 'kgProduced': kg,
          'kgIsEstimated': false, 'avgLiveWeightKg': 2.42, 'feedKg': 4200, 'fcr': fcr, 'epef': 300.4, 'totalCost': 5000,
          'costPerKg': 2.17, 'revenuePerKg': 8.7, 'profit': 15000, 'profitPerKg': 6.53, 'missing': missing,
        };

    FakeApi api() => FakeApi()
      ..gets['/api/flock-closeout/broiler-kpis'] = [
        kpi(1, 'Broilers A'),
        kpi(2, 'Broilers B', closed: '2026-09-30', missing: 'a weigh-in or bird sales with a weight'),
      ];

    testWidgets('the four farm figures, a card per flock, the filter and the way into a flock', (tester) async {
      final a = api()
        ..gets['/api/flock-closeout/lifetime'] = []
        ..gets['/api/flock-closeout/1/history'] = [];
      await open(tester, BroilerPerformanceScreen(session: await sessionFor(a), company: company), size: phone);
      expect(a.requests.any((r) => r.url.path == '/api/flock-closeout/broiler-kpis' && r.url.queryParameters['broilersOnly'] == 'true'), isTrue);
      expect(find.text('Liveability, weight, feed conversion and cost per kg for every broiler flock.'), findsOneWidget);
      // Two flocks of 2,300 kg and 4,200 kg feed: 8,400 / 4,600 = 1.826.
      expect(find.text('FCR'), findsWidgets);
      expect(find.text('1.826'), findsWidgets);
      expect(find.text('kg feed per kg live weight'), findsOneWidget);
      expect(find.text('100 died of 2,000'), findsOneWidget);
      expect(find.text('4,600 kg'), findsOneWidget);
      expect(find.text('From sales and weigh-ins'), findsOneWidget);
      expect(find.text('GHC 2.17'), findsWidgets);
      expect(find.text('Running · 42 d'), findsOneWidget);
      expect(find.text('Closed · 42 d'), findsOneWidget);
      expect(find.text('a weigh-in or bird sales with a weight'), findsOneWidget);
      expect(find.text('300'), findsNWidgets(2), reason: 'EPEF, rounded');

      await tester.tap(find.byKey(const ValueKey('broiler-show-Running')));
      await tester.pumpAndSettle();
      expect(find.text('Broilers B'), findsNothing);
      expect(find.text('2,300 kg'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('broiler-show-All')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('broiler-1')));
      await tester.pumpAndSettle();
      expect(find.byType(FlockLifetimeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a flock with no known kg counts towards birds, not FCR', (tester) async {
      final a = FakeApi()..gets['/api/flock-closeout/broiler-kpis'] = [kpi(1, 'A'), {...kpi(2, 'B'), 'kgProduced': null}];
      await open(tester, BroilerPerformanceScreen(session: await sessionFor(a), company: company), size: phone);
      expect(find.text('1 of 2 flocks have a known kg'), findsOneWidget);
    });

    testWidgets('none yet', (tester) async {
      final a = FakeApi()..gets['/api/flock-closeout/broiler-kpis'] = [];
      await open(tester, BroilerPerformanceScreen(session: await sessionFor(a), company: company), size: phone);
      expect(find.text('No broiler flocks yet. A flock is a broiler flock when it is set to Broilers on the Flocks page.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('broiler-show-Closed')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No broiler flocks closed yet.'), findsOneWidget);
    });
  });
}
