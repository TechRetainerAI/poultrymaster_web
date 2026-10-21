// Poultry → Egg Sorting Workspace and Egg Sorting Settings (341-344): the
// rules, then the pages at phone width against a fake API — sort a pick, sort
// all, drafts, reverse, the size report and the sizes & settings panel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/egg_sorting/egg_sorting_logic.dart';
import 'package:poultrycore_mobile/pages/poultry/egg_sorting/egg_sorting_screens.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';

import 'support/harness.dart';

Map<String, Object?> pickRow(int record, int n, {required String date, int flock = 7, String flockName = 'Layers A', int gross = 100, int sorted = 0, int available = 100, int recLeft = 200, int recSorted = 0}) => {
      'productionRecordId': record, 'flockId': flock, 'flockName': flockName, 'batchName': 'B-001', 'houseName': 'Pen 1',
      'productionDate': '${date}T00:00:00', 'pickNumber': n, 'pickGross': gross, 'pickSorted': sorted, 'pickLeft': gross - sorted,
      'available': available, 'recordGross': 210, 'recordCollectionLoss': 10, 'recordSaleable': 200, 'recordSorted': recSorted,
      'recordLeft': recLeft, 'byPickSorted': 0,
    };

final picks = [
  pickRow(11, 1, date: '2026-10-12'),
  pickRow(11, 2, date: '2026-10-12'),
  pickRow(10, 1, date: '2026-10-11', recLeft: 50, recSorted: 150, sorted: 70, available: 30),
];

final classes = [
  {'poultryProductId': 1, 'eggSizeId': null, 'name': 'Unsorted', 'classKind': 'Unsorted', 'sortOrder': 0, 'isActive': true, 'onHand': 250},
  {'poultryProductId': 21, 'eggSizeId': 1, 'name': 'Large', 'classKind': 'Size', 'sortOrder': 1, 'isActive': true, 'onHand': 40, 'pricePerCrate': 45},
  {'poultryProductId': 22, 'eggSizeId': 2, 'name': 'Medium', 'classKind': 'Size', 'sortOrder': 2, 'isActive': true, 'onHand': 0},
];

FakeApi api({bool on = true}) => FakeApi()
  ..gets['/api/CompanyTime/context'] = {'businessDate': '2026-10-13'}
  ..gets['/api/Poultry/egg-sorting/settings'] = {'enableEggSorting': on, 'closingPolicy': 'Warning', 'eggsPerCrate': 30, 'unsortedPricePerCrate': null}
  ..gets['/api/Poultry/egg-sorting/classes'] = classes
  ..gets['/api/Poultry/egg-sorting/picks'] = picks
  ..gets['/api/Poultry/egg-sorting/summary'] = {
    'businessDate': '2026-10-13T00:00:00', 'unsortedOnHand': 250, 'sizedOnHand': 40, 'sortedToday': 100, 'sizedCreatedToday': 95,
    'lossToday': 5, 'sessionsToday': 2, 'productionLeft': 250, 'recordsWithLeft': 2, 'oldestLeftDate': '2026-10-11T00:00:00',
  }
  ..gets['/api/Poultry/egg-sorting/production-duplicates'] = []
  ..gets['/api/Poultry/egg-sorting/sessions'] = [
    {
      'sessionId': 5, 'sessionNo': 'ES-0005', 'sortingMode': 'ByPick', 'flockId': 7, 'flockName': 'Layers A', 'productionRecordId': 10,
      'pickNumber': 1, 'scopeRecordIds': [10], 'sortingDate': '2026-10-12T00:00:00', 'status': 'Posted', 'inputQuantity': 70,
      'outputQuantity': 68, 'lossQuantity': 2, 'postedBy': 'kwame', 'postedAtUtc': '2026-10-12T10:00:00Z',
      'lines': [
        {'lineType': 'SizedOutput', 'eggSizeId': 1, 'sizeName': 'Large', 'quantity': 68},
        {'lineType': 'Breakage', 'eggSizeId': null, 'quantity': 2},
      ],
      'sources': [{'productionRecordId': 10, 'pickNumber': 1, 'productionDate': '2026-10-11T00:00:00', 'quantity': 70}],
    },
    {
      'sessionId': 6, 'sessionNo': 'ES-0006', 'sortingMode': 'Combined', 'flockId': 7, 'flockName': 'Layers A', 'productionRecordId': 11,
      'scopeRecordIds': [11], 'sortingDate': '2026-10-13T00:00:00', 'status': 'Draft', 'inputQuantity': 30, 'outputQuantity': 30, 'lossQuantity': 0,
      'lines': [{'lineType': 'SizedOutput', 'eggSizeId': 2, 'sizeName': 'Medium', 'quantity': 30}], 'sources': [],
    },
  ]
  ..gets['/api/Poultry/egg-sorting/audit'] = [
    {'auditId': 1, 'entity': 'Sorting', 'entityId': 5, 'action': 'Posted', 'actor': 'kwame', 'atUtc': '2026-10-12T10:00:00Z',
      'details': '{"sessionNo":"ES-0005","input":70,"sized":68,"loss":2}'},
  ]
  ..gets['/api/FarmProductionSettings'] = {'firstPickTime': '09:00', 'secondPickTime': '12:00'};

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
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

Future<void> tapSeen(WidgetTester tester, Finder f) async {
  ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last)).removeCurrentSnackBar();
  await tester.pumpAndSettle();
  await see(tester, f);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Future<void> openWs(WidgetTester tester, FakeApi a, {int? record, String? tab}) async =>
    open(tester, EggSortingWorkspaceScreen(session: await sessionFor(a), company: company, recordId: record, initialTab: tab), size: phone);

void main() {
  test('days, what can still be sorted after unsorted sales, the balance, the history sentence', () {
    final days = groupProductionDays(picks);
    expect([for (final d in days) d.productionRecordId], [11, 10], reason: 'newest day first');
    expect((days.first.saleable, days.first.left, days.first.status), (200, 200, 'NotStarted'));
    expect(days.last.status, 'Partial');
    // 250 left across the two days but only 220 on the shelf: 30 were sold, from the oldest day.
    final sortable = sortableByRecord(days, 220);
    expect(sortable, {10: 20, 11: 200});
    final capped = capToSortable(days.last, sortable[10]);
    expect((capped.left, capped.soldUnsorted, capped.picks.single['available']), (20, 30, 0));
    final b = sortingBalance(100, const [
      SortingLine(key: 'a', lineType: 'SizedOutput', eggSizeId: 1, text: '90'),
      SortingLine(key: 'b', lineType: 'Breakage', text: '5'),
    ]);
    expect((b.sized, b.loss, b.input, b.remainingAfter), (90, 5, 95, 5));
    expect(sortingBlocker(sortingBalance(10, const [SortingLine(key: 'a', lineType: 'SizedOutput', text: '12')])), 'That is 2 more than are left to sort.');
    expect(sortingBlocker(sortingBalance(10, const [SortingLine(key: 'a', lineType: 'SizedOutput', text: '1.5')])), 'Quantities must be whole numbers of eggs.');
    expect(describeAudit({'action': 'Posted', 'entityId': 5, 'details': '{"sessionNo":"ES-0005","input":70,"sized":68,"loss":2}'}),
        'ES-0005: 70 eggs (68 into sizes, 2 lost)');
    expect(statusOf(0, 0), 'Complete');
  });

  test('routes: the workspace, ?record=, ?tab=settings and the settings page', () async {
    expect(pageScreens.containsKey('/poultry-egg-sorting'), isTrue);
    expect(pageScreens.containsKey('/poultry-egg-sorting-settings'), isTrue);
    final s = await sessionFor(FakeApi());
    final w = moneyScreenForHref('/poultry-egg-sorting?record=11', s, company) as EggSortingWorkspaceScreen;
    expect(w.recordId, 11);
    expect((eggSortingWorkspaceForHref('/poultry-egg-sorting?tab=settings', s, company) as EggSortingWorkspaceScreen).initialTab, 'settings');
    expect(eggSortingWorkspaceForHref('/poultry-egg-sorting-settings', s, company), isA<EggSortingSettingsScreen>());
  });

  testWidgets('workspace: the six figures, a flock section, sort a pick and post it', (tester) async {
    final a = api()..writeAnswers['/api/Poultry/egg-sorting/sessions'] = {'sessionId': 9};
    await openWs(tester, a);
    expect(find.text('UNSORTED IN STOCK'), findsOneWidget);
    expect(find.text('250'), findsWidgets);
    expect(find.text('8 cr + 10'), findsOneWidget, reason: '250 eggs in crates');
    expect(find.text('oldest October 11, 2026'), findsOneWidget);
    await see(tester, find.text('Layers A'));
    expect(find.text('Sorted 150 of 400'), findsOneWidget, reason: 'the flock section totals');
    expect(find.text('October 12, 2026'), findsOneWidget);
    expect(find.textContaining('broken/lost'), findsWidgets);

    await tapSeen(tester, find.text('Sort pick'));
    expect(find.text('Sort 1st Pick (9:00 AM)'), findsOneWidget);
    await see(tester, find.byKey(const ValueKey('eggs-loss:Breakage')));
    await tester.enterText(find.byKey(const ValueKey('eggs-size:1')), '80');
    await tester.enterText(find.byKey(const ValueKey('eggs-loss:Breakage')), '30');
    await tester.pumpAndSettle();
    expect(find.text('That is 10 more than are left to sort.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post sorting')).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('eggs-loss:Breakage')), '5');
    await tester.pumpAndSettle();
    expect(find.text('Partial sorting: 15 eggs stay unsorted and can be sorted later.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Post sorting'));
    await tester.pumpAndSettle();
    final b = a.lastBody('/api/Poultry/egg-sorting/sessions');
    expect(b['productionRecordIds'], [11]);
    expect((b['sortingMode'], b['pickNumber'], b['post'], b['sortingDate'], b['farmId']), ('ByPick', 1, true, '2026-10-13', 'farm-1'));
    expect(b['lines'], [
      {'lineType': 'SizedOutput', 'eggSizeId': 1, 'quantity': 80, 'notes': null},
      {'lineType': 'Breakage', 'eggSizeId': null, 'quantity': 5, 'notes': null},
    ]);
    expect(b['clientRequestId'], isNotEmpty);
    expect(find.text('Sorting posted — 85 eggs sorted: 80 into sizes, 5 lost.'), findsOneWidget);
  });

  testWidgets('sort all available: the flock\'s open days, ticked together, saved as a draft', (tester) async {
    final a = api()..writeAnswers['/api/Poultry/egg-sorting/sessions'] = {'sessionId': 9};
    await openWs(tester, a);
    await tapSeen(tester, find.text('Sort all'));
    expect(find.text('Days to sort together'), findsOneWidget);
    expect(find.textContaining('1 of 2', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 of 2', findRichText: true), findsOneWidget);
    expect(find.textContaining('250', findRichText: true), findsWidgets, reason: '200 + 50 to sort');
    await see(tester, find.byKey(const ValueKey('eggs-size:2')));
    await tester.enterText(find.byKey(const ValueKey('eggs-size:2')), '120');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Save draft'));
    await tester.pumpAndSettle();
    final b = a.lastBody('/api/Poultry/egg-sorting/sessions');
    expect((b['productionRecordIds'] as List).toSet(), {10, 11});
    expect((b['sortingMode'], b['pickNumber'], b['post']), ('Combined', null, false));
    expect(find.text('Draft saved — Draft saved. It moves no stock until you post it.'), findsOneWidget);
  });

  testWidgets('sortings: the grading and sources, reverse needs a reason, discard a draft', (tester) async {
    final a = api();
    await openWs(tester, a, tab: 'sessions');
    await tapSeen(tester, find.text('ES-0005'));
    await tester.pumpAndSettle();
    await see(tester, find.text('GRADING'));
    expect(find.text('68 (97.1%)'), findsOneWidget);
    expect(find.text('October 11, 2026 · 1st Pick'), findsOneWidget);
    await see(tester, find.text('ES-0005: 70 eggs (68 into sizes, 2 lost)'));

    await tapSeen(tester, find.text('Reverse'));
    expect(find.text('Reverse ES-0005?'), findsOneWidget);
    await reasonOther(tester, 'wrong sizes');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reverse'));
    await tester.pumpAndSettle();
    expect(a.lastBody('/api/Poultry/egg-sorting/sessions/5/reversal')['reason'], 'wrong sizes');

    await tapSeen(tester, find.text('Discard'));
    final del = a.writes.lastWhere((w) => w.method == 'DELETE');
    expect(del.url.path, '/api/Poultry/egg-sorting/sessions/6');
  });

  testWidgets('sorting off: the notice, no sorting; settings tab turns it on and adds a size', (tester) async {
    final a = api(on: false);
    await openWs(tester, a);
    expect(find.textContaining('for this farm. Production goes into Unsorted', findRichText: true), findsOneWidget);
    await see(tester, find.text('Sort pick'));
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Sort pick').first).onPressed, isNull);

    // Setup > Egg Sorting Settings links here with ?tab=settings.
    await openWs(tester, a, tab: 'settings');
    await see(tester, find.text('Egg sorting'));
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    final s = a.lastBody('/api/Poultry/egg-sorting/settings', 'PUT');
    expect((s['enableEggSorting'], s['closingPolicy'], s['eggsPerCrate'], s['farmId']), (true, 'Warning', 30, 'farm-1'));

    await see(tester, find.text('e.g. Peewee'));
    await tester.enterText(find.widgetWithText(TextFormField, 'e.g. Peewee'), 'Peewee');
    await tester.pumpAndSettle();
    await tapSeen(tester, find.text('Add size'));
    final n = a.lastBody('/api/Poultry/egg-sorting/sizes', 'PUT');
    expect((n['eggSizeId'], n['name'], n['isActive']), (null, 'Peewee', true));
  });

  testWidgets('size reports: grouping by pick says what it leaves out', (tester) async {
    final a = api()
      ..gets['/api/Poultry/egg-sorting/composition'] = [
        {'groupKey': '2026-10-12', 'groupLabel': 'October 12, 2026', 'groupSort': '2026-10-12', 'lineType': 'SizedOutput', 'eggSizeId': 1, 'sizeName': 'Large',
          'sizeSort': 1, 'quantity': 60, 'sessions': 1, 'combinedSessions': 1},
        {'groupKey': '2026-10-12', 'groupLabel': 'October 12, 2026', 'groupSort': '2026-10-12', 'lineType': 'Breakage', 'eggSizeId': null,
          'sizeSort': 0, 'quantity': 20, 'sessions': 1, 'combinedSessions': 1},
      ]
      ..gets['/api/Poultry/egg-sorting/carryover'] = [
        {'productionDate': '2026-10-12T00:00:00', 'records': 1, 'gross': 210, 'collectionLoss': 10, 'saleable': 200, 'sorted': 80, 'leftUnsorted': 120},
      ];
    await openWs(tester, a, tab: 'reports');
    expect(find.text('75.0%'), findsOneWidget, reason: 'Large 60 of 80');
    expect(find.text('incl. combined'), findsOneWidget);
    expect(a.requests.lastWhere((r) => r.url.path == '/api/Poultry/egg-sorting/composition').url.queryParameters['fromDate'], '2026-09-14');
    await see(tester, find.text('Unsorted carryover'));
    expect(find.text('120'), findsOneWidget);
    await see(tester, find.text('Production date'));
    await pick(tester, 'Production date', 'Pick');
    expect(find.textContaining('Only sortings recorded pick by pick are counted here.'), findsOneWidget);
  });
}
