// Poultry → Operations → Production → Egg sorting, at phone width: the list
// (filters, the today's-totals discrepancy and sync, delete), and the Add /
// Edit pages with their push into the production record.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/production/egg_sorting_screen.dart';

import 'support/harness.dart';

String _today() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

final egg1 = <String, Object?>{
  'productionId': 31, 'flockId': 7, 'flockName': 'Unknown Flock', 'productionDate': '${_today()}T00:00:00', 'production9AM': 60, 'production12PM': 30,
  'production4PM': 10, 'production4thPick': 0, 'totalProduction': 100, 'brokenEggs': 2, 'notes': 'clean', 'eggGrade': 'Large',
};
final egg2 = <String, Object?>{
  'productionId': 32, 'flockId': 8, 'flockName': 'Pen 2', 'productionDate': '2026-09-01T00:00:00', 'production9AM': 40, 'totalProduction': 40, 'brokenEggs': 0,
};

FakeApi api() => FakeApi()
  ..gets['/api/EggProduction'] = [egg1, egg2]
  ..gets['/api/EggProduction/31'] = egg1
  ..gets['/api/ProductionRecord'] = [
    {'id': 5, 'flockId': 7, 'date': '${_today()}T00:00:00', 'totalProduction': 90, 'noOfBirds': 120, 'mortality': 1, 'noOfBirdsLeft': 119, 'feedKg': 4,
      'medication': 'Vit', 'ageInDays': 80, 'ageInWeeks': 11, 'farmId': 'farm-1', 'userId': 'u1', 'createdBy': 'u1'},
  ]
  ..gets['/api/Flock'] = [
    {'flockId': 7, 'name': 'Pen 1', 'batchId': 1, 'quantity': 130, 'active': true, 'hasArrived': true, 'startDate': '2026-07-10T00:00:00'},
    {'flockId': 8, 'name': 'Pen 2', 'batchId': 2, 'quantity': 80, 'active': true, 'hasArrived': true, 'startDate': '2026-08-01T00:00:00'},
    {'flockId': 9, 'name': 'Closed pen', 'batchId': 2, 'quantity': 10, 'hasArrived': true, 'closedDate': '2026-05-01'},
  ]
  ..gets['/api/MainFlockBatch'] = [
    {'batchId': 1, 'batchName': 'Batch A'},
    {'batchId': 2, 'batchCode': 'B-002'},
  ]
  ..gets['/api/FarmProductionSettings'] = {'enableFourthPick': true};

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 50 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 70 && f.evaluate().isEmpty; i++) {
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

Future<void> choose(WidgetTester tester, String shown, String option, {Finder? within}) async {
  final label = within == null ? find.text(shown) : find.descendant(of: within, matching: find.text(shown));
  await see(tester, label);
  final sel = find.ancestor(of: label.first, matching: find.byWidgetPredicate((w) => w is AppSelect)).first;
  await tester.ensureVisible(sel);
  await tester.pumpAndSettle();
  await tester.tap(sel);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// The number box in pick box [pick], field [field] (0 crates, 1 loose).
Future<void> pickEnter(WidgetTester tester, int pick, int field, String text) async {
  final box = find.byKey(ValueKey('egg-pick-$pick'));
  await see(tester, box);
  await tester.enterText(find.descendant(of: box, matching: find.byType(TextField)).at(field), text);
  await tester.pumpAndSettle();
}

void main() {
  test('helpers and routes', () {
    expect(eggFlockName(egg1, [{'flockId': 7, 'name': 'Pen 1'}]), 'Pen 1', reason: 'the Unknown Flock placeholder is ignored');
    expect(eggFlockName({'flockId': 4}, []), 'Flock #4');
    expect(eggPageNumbers(1, 6), [1, 2, 3, 4, 'ellipsis', 6]);
    final put = productionRecordPayload({'production9AM': 5, 'totalProduction': 5, 'eggGrade': null}, id: 9);
    expect(put.containsKey('farmId'), isFalse);
    expect(put.containsKey('meatyEggs'), isFalse);
    expect((put['id'], put['brokenEggs'], put['eggGrade'], put['feeds']), (9, 0, null, null));
    expect(pageScreens.containsKey('/egg-production'), isTrue);
  });

  testWidgets('list: tiles, discrepancy, filter, sync today, delete', (tester) async {
    final a = api();
    await open(tester, EggSortingScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text("Sync Today's Total"), findsOneWidget);
    final syncBtn = tester.widget<FilledButton>(find.ancestor(of: find.text("Sync Today's Total"), matching: find.byType(FilledButton)));
    expect(syncBtn.onPressed, isNull, reason: 'selected-flock scope with no flock chosen');

    await see(tester, find.text('140'));
    await see(tester, find.textContaining('Pen 1', findRichText: true));
    await tap(tester, find.text('All flocks'));
    expect(find.textContaining('Discrepancy detected for today. Flock #7: Egg Production 100 vs Production Records 90'), findsOneWidget);

    await tap(tester, find.text("Sync Today's Total"));
    final w = a.writes.lastWhere((w) => w.url.path == '/api/ProductionRecord/5');
    final b = jsonDecode(w.body) as Map;
    expect((b['id'], b['FlockId'], b['production9AM'], b['totalProduction'], b['brokenEggs'], b['noOfBirdsLeft'], b['medication']),
        (5, 7, 60, 100, 2, 119, 'Vit'));
    expect(b.containsKey('eggGrade'), isFalse);
    expect(find.textContaining("Today's totals synced — Updated 1 and created 0"), findsOneWidget);

    await tap(tester, find.text('Filters'));
    await choose(tester, 'All Flocks', 'Pen 2 (80 birds)', within: find.byType(BottomSheet));
    await choose(tester, 'All sizes', 'Not specified', within: find.byType(BottomSheet));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await see(tester, find.text('40'));
    expect(find.text('clean'), findsNothing);

    await tap(tester, find.text('Delete'));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect((a.writes.last.method, a.writes.last.url.path), ('DELETE', '/api/EggProduction/32'));
  });

  testWidgets('add: checks, picks, body, then the production record is created', (tester) async {
    final a = api()..gets['/api/ProductionRecord'] = [];
    await open(tester, EggSortingFormPage(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('Add New Egg Sorting Record'), findsWidgets);
    await choose(tester, 'All batches', 'B-002');
    await tester.tap(find.text('Select a flock'));
    await tester.pumpAndSettle();
    expect(find.text('Closed pen'), findsNothing);
    expect(find.text('Pen 1'), findsNothing, reason: 'filtered to batch B-002');
    await tester.tap(find.text('Pen 2').last);
    await tester.pumpAndSettle();

    await pickEnter(tester, 0, 1, '31');
    await tap(tester, find.text('Create Record'));
    await see(tester, find.text('Value must be less than or equal to 29.'));

    await pickEnter(tester, 0, 0, '2');
    await pickEnter(tester, 0, 1, '5');
    await pickEnter(tester, 3, 0, '1');
    await see(tester, find.text('95 eggs'));
    await choose(tester, 'Not specified', 'Jumbo');
    await tap(tester, find.text('Create Record'));

    final egg = jsonDecode(a.writes.firstWhere((w) => w.url.path == '/api/EggProduction').body) as Map;
    expect((egg['flockId'], egg['production9AM'], egg['production4thPick'], egg['totalProduction'], egg['eggCount'], egg['eggGrade']),
        (8, 65, 30, 95, 95, 'Jumbo'));
    expect(egg['specificFeedUsedId'], isNull);
    final pr = jsonDecode(a.writes.lastWhere((w) => w.url.path == '/api/ProductionRecord').body) as Map;
    expect((pr['FlockId'], pr['noOfBirds'], pr['medication'], pr['totalProduction'], pr['eggGrade'], pr['meatyEggs']), (8, 80, 'None', 95, 'Jumbo', null));
  });

  testWidgets('edit: loads the record, PUTs it and updates the matching production record', (tester) async {
    final a = api();
    final s = await sessionFor(a);
    expect(eggSortingScreenForHref('/egg-production/31', s, company), isA<EggSortingFormPage>());
    await open(tester, EggSortingFormPage(session: s, company: company, productionId: 31), size: phone);
    expect(find.text('Edit Production Record'), findsWidgets);
    expect(find.text('All batches'), findsNothing, reason: 'no batch filter on edit');
    await see(tester, find.text('100 eggs'));
    await pickEnter(tester, 2, 0, '1');
    await tap(tester, find.text('Update Record'));
    final w = a.writes.firstWhere((w) => w.url.path == '/api/EggProduction/31');
    final b = jsonDecode(w.body) as Map;
    expect((w.method, b['productionId'], b['flockId'], b['production4PM'], b['totalProduction'], b['notes'], b['eggGrade']),
        ('PUT', 31, 7, 40, 130, 'clean', 'Large'));
    final pr = jsonDecode(a.writes.lastWhere((w) => w.url.path == '/api/ProductionRecord/5').body) as Map;
    expect((pr['production4PM'], pr['totalProduction'], pr.containsKey('farmId')), (40, 130, false));
  });
}
