// Poultry → Operations → Production → Feed Usage, rebuilt for migration 389
// (feed from stock), at phone width: the split rules, the Feed log and
// Entries tabs, reversal, and the Record feed usage form for one flock and a
// whole batch.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/production/feed_usage_screen.dart';

import 'support/harness.dart';

const _items = [
  {'poultryRawMaterialItemId': 31, 'itemName': 'Layer Mash', 'category': 'FinishedFeed', 'isActive': true, 'currentQuantity': 500, 'usageMethod': 'FIFO'},
  {'poultryRawMaterialItemId': 32, 'itemName': 'Maize', 'category': 'FeedIngredient', 'isActive': true, 'currentQuantity': 900, 'usageMethod': 'FIFO'},
];
const _purchases = [
  {'poultryRawMaterialPurchaseId': 1, 'poultryRawMaterialItemId': 31, 'remainingQuantity': 500, 'unitCost': 2, 'purchaseDate': '2026-10-01'},
];
const _candidates = [
  {'flockId': 7, 'flockName': 'Pen 1', 'batchId': 3, 'batchName': 'Oct batch', 'houseName': 'House A', 'recordStatus': 'Recorded', 'productionRecordId': 70, 'birds': 300},
  {'flockId': 8, 'flockName': 'Pen 2', 'batchId': 3, 'batchName': 'Oct batch', 'recordStatus': 'None', 'birds': 100},
  {'flockId': 9, 'flockName': 'Pen 3', 'batchId': 3, 'batchName': 'Oct batch', 'recordStatus': 'Duplicate', 'birds': 50},
];

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {'businessDate': '2026-11-03', 'companyLocalDateTime': '2026-11-03T10:00:00', 'utcNow': '2026-11-03T10:00:00Z'}
  ..gets['/api/Poultry/feed-usage-entries/log'] = [
    {'usageDate': '2026-11-02T00:00:00', 'flockId': 7, 'flockName': 'Pen 1', 'productionRecordId': 70, 'recordSource': 'ManualSingleFlock', 'feedOnly': false,
      'itemId': 31, 'itemName': 'Layer Mash', 'quantityKg': 40, 'totalCost': 80, 'entryId': 5},
    {'usageDate': '2026-11-02T00:00:00', 'flockId': 8, 'flockName': 'Pen 2', 'productionRecordId': 71, 'recordSource': 'FeedUsage', 'feedOnly': true,
      'itemId': 31, 'itemName': 'Layer Mash', 'quantityKg': 10, 'totalCost': 20, 'entryId': 5},
    {'usageDate': '2026-09-20T00:00:00', 'flockId': 7, 'flockName': 'Pen 1', 'recordSource': 'Legacy', 'feedOnly': false, 'itemName': 'Layer Feed', 'quantityKg': 5, 'legacyFeedUsageId': 2},
  ]
  ..gets['/api/Poultry/feed-usage-entries'] = [
    {'poultryFeedUsageEntryId': 5, 'businessDate': '2026-11-02', 'scope': 'Batch', 'batchName': 'Oct batch', 'flockCount': 2, 'totalKg': 50, 'totalCost': 100,
      'feedOnlyRecords': 1, 'status': 'Posted', 'notes': 'Morning', 'postedBy': 'Ama', 'postedAtUtc': '2026-11-02T08:00:00Z'},
  ]
  ..gets['/api/Poultry/feed-usage-entries/5/lines'] = [
    {'poultryFeedUsageLineId': 1, 'flockName': 'Pen 1', 'productionRecordId': 70, 'createdRecord': false, 'itemName': 'Layer Mash', 'quantityKg': 40, 'totalCost': 80},
    {'poultryFeedUsageLineId': 2, 'flockName': 'Pen 2', 'productionRecordId': 71, 'createdRecord': true, 'itemName': 'Layer Mash', 'quantityKg': 10, 'totalCost': 20},
  ]
  ..gets['/api/Poultry/feed-usage-entries/candidates'] = _candidates
  ..gets['/api/Poultry/raw-material-items'] = _items
  ..gets['/api/Poultry/raw-material-purchases'] = _purchases
  ..writeAnswers['/api/Poultry/feed-usage-entries'] = {'poultryFeedUsageEntryId': 6};

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

/// Opens a dropdown showing [shown] and picks the option containing [option].
Future<void> choose(WidgetTester tester, String shown, String option) async {
  await tap(tester, find.text(shown));
  await tester.tap(find.textContaining(option).last);
  await tester.pumpAndSettle();
}

Future<void> openRecordForm(WidgetTester tester, FakeApi a) async {
  await open(tester, FeedUsageScreen(session: await sessionFor(a), company: company), size: phone);
  await tester.tap(find.byKey(const ValueKey('feed-usage-record')));
  await tester.pumpAndSettle();
  expect(find.text('Record feed usage'), findsWidgets);
}

Future<void> addFeed(WidgetTester tester, String kg) async {
  await choose(tester, 'None', 'Layer Mash');
  final qty = find.descendant(of: find.ancestor(of: find.text('Consumed'), matching: find.byType(Column)).first, matching: find.byType(TextField));
  await tester.enterText(qty.first, kg);
  await tester.pumpAndSettle();
}

void main() {
  group('split rules (lib/production/feed-usage.ts)', () {
    test('by birds and equally, in grams, summing exactly', () {
      final flocks = [(flockId: 1, birds: 300 as num?), (flockId: 2, birds: 100 as num?)];
      expect(splitFeed(50, flocks, 'Birds'), {1: 37.5, 2: 12.5});
      expect(splitFeed(10, flocks, 'Equal'), {1: 5, 2: 5});
      final odd = splitFeed(1, [(flockId: 1, birds: 1), (flockId: 2, birds: 1), (flockId: 3, birds: 1)], 'Equal');
      expect(sumKg(odd.values), 1, reason: 'the leftover gram is given out, never lost');
      expect(splitFeed(9, [(flockId: 1, birds: null), (flockId: 2, birds: 0)], 'Birds'), {1: 4.5, 2: 4.5}, reason: 'no birds known: equal');
      expect(splitBlocker('Layer Mash', 50, [40, 5]), contains('add up to 45 kg, not 50 kg'));
      expect(splitBlocker('Layer Mash', 50, [40, 10]), isNull);
      expect(feedSourceLabel({'recordSource': 'Legacy'}), 'Old entry (not from stock)');
      expect(feedSourceLabel({'distributionId': 3}), 'Distribute Feed');
      expect(batchesFrom(_candidates).single.flocks.length, 3);
    });

    test('the old "new" page opens the form on the page', () {
      final w = pageScreens['/feed-usage/new']!;
      expect(w, isNotNull);
    });
  });

  testWidgets('Feed log: the three figures, sources, feed-only badge; Entries: lines and reversal', (tester) async {
    final a = api();
    await open(tester, FeedUsageScreen(session: await sessionFor(a), company: company), size: phone);
    final q = a.requests.firstWhere((r) => r.url.path == '/api/Poultry/feed-usage-entries/log').url.queryParameters;
    expect((q['fromDate'], q['toDate']), ('2026-10-05', '2026-11-03'), reason: 'the last 30 days by the company date');
    expect(find.text('55 kg'), findsOneWidget);
    expect(find.text('FEED ONLY, PRODUCTION NOT FILLED'), findsOneWidget);
    await see(tester, find.text('Production not filled'));
    expect(find.text('Fill in production'), findsOneWidget);
    await see(tester, find.text('Entered from: Old entry (not from stock)'));

    // The flock filter.
    await choose(tester, 'All flocks', 'Pen 2');
    expect(find.text('10 kg'), findsWidgets);
    expect(find.text('Entered from: Old entry (not from stock)'), findsNothing);

    await tap(tester, find.byKey(const ValueKey('feed-usage-tab-entries')));
    expect(find.textContaining('Oct batch (2 flocks) · 50 kg'), findsOneWidget);
    expect(find.textContaining('made 1 feed-only record'), findsOneWidget);
    await tap(tester, find.textContaining('Oct batch (2 flocks)'));
    expect(find.text(' · made feed-only'), findsOneWidget);

    await tap(tester, find.byKey(const ValueKey('feed-usage-reverse-5')));
    expect(find.text('Reverse this feed usage?'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownMenuItem<String>).last);
    await tester.pumpAndSettle();
    final other = find.byType(TextField);
    if (other.evaluate().isNotEmpty) await tester.enterText(other.last, 'Wrong flock');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reverse').last);
    await tester.pumpAndSettle();
    expect(a.writes.any((w) => w.url.path == '/api/Poultry/feed-usage-entries/5/reversal'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Record feed usage, one flock: only finished feed, the checks, the post', (tester) async {
    final a = api();
    await openRecordForm(tester, a);
    await see(tester, find.text('Choose the flock.'));
    await choose(tester, 'Choose the flock', 'Pen 2');
    expect(find.textContaining('No production record yet. A feed-only record is made'), findsOneWidget);
    await tap(tester, find.text('None'));
    expect(find.textContaining('Maize'), findsNothing, reason: 'an ingredient reaches a flock through a feed batch');
    await tester.tap(find.textContaining('Layer Mash').last);
    await tester.pumpAndSettle();
    final qty = find.descendant(of: find.ancestor(of: find.text('Consumed'), matching: find.byType(Column)).first, matching: find.byType(TextField));
    await tester.enterText(qty.first, '600');
    await tester.pumpAndSettle();
    await see(tester, find.textContaining('Not enough Layer Mash in stock: only 500 available.'));
    await tester.enterText(qty.first, '12.5');
    await tester.pumpAndSettle();
    expect(find.text('Total: 12.5 kg · cost 25.00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rfu-save')));
    await tester.pumpAndSettle();
    final body = jsonDecode(a.writes.lastWhere((w) => w.url.path == '/api/Poultry/feed-usage-entries').body) as Map;
    expect((body['scope'], body['businessDate'], body['batchId'], body['splitBasis']), ('Flock', '2026-11-03', null, null));
    expect(body['lines'], [{'flockId': 8, 'itemId': 31, 'qty': 12.5, 'birds': 100}]);
    expect(find.textContaining('1 flock has no production for this day yet'), findsOneWidget);
  });

  testWidgets('Record feed usage, a whole batch: by birds, by hand must add up, duplicate left out', (tester) async {
    final a = api();
    await openRecordForm(tester, a);
    await tap(tester, find.byKey(const ValueKey('rfu-scope-Batch')));
    await choose(tester, 'Choose the batch', 'Oct batch · 3 flocks');
    await addFeed(tester, '40');
    await see(tester, find.text('Split across the flocks'));
    expect(find.text('30'), findsOneWidget, reason: 'Pen 1: 300 of 400 birds');
    expect(find.text('10'), findsOneWidget, reason: 'Pen 2');
    expect(find.text('40 / 40'), findsOneWidget);
    expect(find.textContaining('Flocks with no record yet get a feed-only record'), findsOneWidget);

    // By hand starts from the bird split; a share left out blocks saving.
    await tap(tester, find.byKey(const ValueKey('rfu-basis-Manual')));
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('rfu-manual-8-31')), matching: find.byType(TextField)), '5');
    await tester.pumpAndSettle();
    await see(tester, find.textContaining("the flocks' shares add up to 35 kg, not 40 kg"));
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('rfu-manual-8-31')), matching: find.byType(TextField)), '10');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rfu-save')));
    await tester.pumpAndSettle();
    final body = jsonDecode(a.writes.lastWhere((w) => w.url.path == '/api/Poultry/feed-usage-entries').body) as Map;
    expect((body['scope'], body['batchId'], body['splitBasis']), ('Batch', 3, 'Manual'));
    expect(body['lines'], [
      {'flockId': 7, 'itemId': 31, 'qty': 30, 'birds': 300},
      {'flockId': 8, 'itemId': 31, 'qty': 10, 'birds': 100},
    ], reason: 'the duplicate-record flock gets nothing');
  });
}
