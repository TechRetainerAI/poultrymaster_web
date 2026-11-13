// Report 34, A2 part 2: the redesigned Farm Setup views (9 Nov pull,
// components/setup-views/*): Houses, Feed formulas, and the lighter tabs'
// task bars (Customers, Suppliers, Cash accounts, Financial settings). At
// phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/farm_setup_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/setup/feed_formulas_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/setup/houses_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/setup/setup_views_kit.dart';

import 'package:poultrycore_mobile/pages/poultry/egg_pick_settings_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/purchase/raw_materials_screen.dart';
import 'poultry_egg_configuration_test.dart' as egg;
import 'poultry_raw_materials_test.dart' as raw;
import 'support/harness.dart';

Finder _onBar(Finder f) => find.descendant(of: find.byKey(const ValueKey('setup-task-bar')), matching: f);

/// Ids of the tasks Farm Setup's bar offers now (inline, or under More).
Future<List<String>> _barTasks(WidgetTester tester) async {
  final ids = [
    for (final e in _onBar(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('task-'))).evaluate())
      (e.widget.key as ValueKey<String>).value.substring(5),
  ];
  return ids;
}

final _houses = [
  {'houseId': 1, 'houseName': 'Pen 1', 'capacity': 1000, 'location': 'North Wing'},
  {'houseId': 2, 'houseName': 'Pen 2', 'capacity': 500, 'location': null},
  {'houseId': 3, 'houseName': 'Brooder', 'capacity': null, 'location': 'Back'},
];
final _flocks = [
  {'flockId': 1, 'houseId': 1, 'active': true, 'quantity': 850},
  {'flockId': 2, 'houseId': 2, 'active': true, 'quantity': 500},
  {'flockId': 3, 'houseId': 2, 'active': false, 'quantity': 999},
];

void main() {
  group('house occupancy (house-picker.tsx)', () {
    test('active flocks only; empty, has space, full and in use', () {
      final f = [for (final x in _flocks) Map<String, dynamic>.from(x)];
      final a = houseOccupancy(_houses[0], f);
      expect((a.capacity, a.occupied, a.free, a.flockCount, a.state), (1000, 850, 150, 1, 'free'));
      final b = houseOccupancy(_houses[1], f);
      expect((b.occupied, b.free, b.state), (500, 0, 'full'));
      expect(houseOccupancy(_houses[2], f).state, 'empty');
      expect(houseOccupancy({'houseId': 3, 'capacity': 0}, [{'houseId': 3, 'active': true, 'quantity': 5}]).state, 'unknown');
      expect(houseOccupancy(_houses[0], f, excludeFlockId: 1).state, 'empty');
    });
    test('pages of 10', () {
      final p = pagedSlice(List.generate(23, (i) => i), 3, 10);
      expect(p.items, [20, 21, 22]);
      expect((p.page, p.pages), (3, 3));
      expect(pagedSlice(<int>[], 4, 10).page, 1);
    });
  });

  group('Houses', () {
    FakeApi api() => FakeApi()
      ..gets['/api/House'] = _houses
      ..gets['/api/Flock'] = _flocks;

    testWidgets('cards: occupancy, free birds, status; an occupied house cannot be deleted', (tester) async {
      final a = api();
      await open(tester, HousesScreen(session: await sessionFor(a), company: company), size: phone);
      expect(find.text('Manage poultry houses'), findsOneWidget);
      expect(find.text('Add House'), findsOneWidget);
      expect(find.text('3 of 3 houses'), findsOneWidget);
      expect(find.text('850 / 1,000 birds'), findsOneWidget);
      expect(find.text('150 free'), findsOneWidget);
      expect(find.text('Has space'), findsOneWidget);
      expect(find.text('Full'), findsOneWidget);
      expect(find.text('No location set'), findsOneWidget);
      expect(find.text('1 active flock'), findsWidgets);
      final del1 = tester.widget<IconButton>(find.byKey(const ValueKey('house-delete-1')));
      expect(del1.onPressed, isNull);
      expect(del1.tooltip, 'Holds 850 birds in 1 flock. Move or close them before deleting this house.');

      await tester.enterText(find.byKey(const ValueKey('setup-search')).first, 'north');
      await tester.pumpAndSettle();
      expect(find.text('1 of 3 houses'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('setup-search')).first, 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No house matches "zzz".'), findsOneWidget);
    });

    testWidgets('table: the columns and the totals row; the choice is kept', (tester) async {
      final a = api();
      await open(tester, HousesScreen(session: await sessionFor(a), company: company), size: phone);
      await tester.tap(find.byKey(const ValueKey('view-table')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('houses-table')), findsOneWidget);
      expect(find.text('Birds in house'), findsOneWidget);
      expect(find.text('Total, all 3 houses (1 full)'), findsOneWidget);
      expect(find.text('1,500'), findsOneWidget, reason: 'capacity of the three');
      expect(find.text('1,350'), findsOneWidget, reason: 'birds in them');
      expect(await loadSetupView('houses-view'), SetupView.table);
    });

    testWidgets('create, edit, delete an empty house', (tester) async {
      final a = api();
      await open(tester, HousesScreen(session: await sessionFor(a), company: company), size: phone);
      await tester.tap(find.byKey(const ValueKey('task-add')));
      await tester.pumpAndSettle();
      expect(find.text('Create New House'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('house-save')));
      await tester.pumpAndSettle();
      expect(find.text('Give this house a name so you can find it later in lists and reports.'), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('house-name')), matching: find.byType(EditableText)), 'Pen 9');
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('house-capacity')), matching: find.byType(EditableText)), '300');
      await tester.tap(find.byKey(const ValueKey('house-save')));
      await tester.pumpAndSettle();
      final body = a.lastBody('/api/House');
      expect((body['HouseName'], body['Capacity'], body['Location'], body['FarmId']), ('Pen 9', 300, null, 'farm-1'));

      await tester.tap(find.byKey(const ValueKey('house-edit-2')));
      await tester.pumpAndSettle();
      expect(find.text('Edit House'), findsOneWidget);
      expect(find.text('Update House'), findsOneWidget);
      await tester.tap(find.text('Update House'));
      await tester.pumpAndSettle();
      expect(a.lastBody('/api/House/2', 'PUT')['HouseName'], 'Pen 2');

      await tester.scrollUntilVisible(find.byKey(const ValueKey('house-delete-3')), 200, scrollable: find.byType(Scrollable).first);
      // A message from the first save may still sit over the bottom of the list.
      tester.widget<IconButton>(find.byKey(const ValueKey('house-delete-3'))).onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Are you sure you want to delete "Brooder"? This action cannot be undone.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      final del = a.writes.lastWhere((w) => w.method == 'DELETE');
      expect(del.url.path, '/api/House/3');
      expect(del.url.queryParameters['farmId'], 'farm-1');
    });

    testWidgets('inside Farm Setup: no title, Add House and Add Multiple on the task bar', (tester) async {
      await open(tester, FarmSetupScreen(session: await sessionFor(api()), company: company, href: '/poultry-setup?tab=houses'), size: phone);
      expect(find.text('Manage poultry houses'), findsNothing);
      expect(find.text('Manage the houses and pens where your birds are kept.'), findsOneWidget);
      expect(_onBar(find.byKey(const ValueKey('task-add'))), findsOneWidget);
      expect(await _barTasks(tester), anyOf(contains('bulk'), contains('more')));
      expect(pageScreens['/houses'], isNotNull);
    });
  });

  group('Feed formulas', () {
    FakeApi api() => FakeApi()
      ..writeAnswers['/api/Poultry/feed-formulas/ensure-defaults'] = {'formulasCreated': 0, 'itemsCreated': 0}
      ..gets['/api/Poultry/feed-formulas'] = [
        {'poultryFeedFormulaId': 1, 'formulaName': 'Layer Mash', 'finishedFeedItemName': 'Layer feed', 'lineCount': 6, 'percentageTotal': 100,
          'isActive': true, 'isDefault': true},
        {'poultryFeedFormulaId': 2, 'formulaName': 'My Grower', 'finishedFeedItemName': null, 'lineCount': 4, 'percentageTotal': 92.5,
          'isActive': false, 'isDefault': false},
        {'poultryFeedFormulaId': 3, 'formulaName': 'Fixed mix', 'lineCount': 3, 'percentageTotal': 0, 'isActive': true},
      ];

    testWidgets('no defaults panel; Add missing defaults is a task; the cards and their actions', (tester) async {
      final a = api();
      await open(tester, FeedFormulasScreen(session: await sessionFor(a), company: company), size: phone);
      expect(find.text('Default formulas to start with'), findsNothing);
      expect(find.text('New Formula'), findsOneWidget);
      expect(find.byKey(const ValueKey('task-defaults')).evaluate().isNotEmpty || find.byKey(const ValueKey('task-more')).evaluate().isNotEmpty, isTrue,
          reason: 'Add missing defaults is a task (folded into More when the row is narrow)');
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('No finished feed'), findsWidgets);
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('92.5%'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('fixed'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('fixed'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Layer Mash'), -200, scrollable: find.byType(Scrollable).first);
      final copies = find.text('Copy as my own formula').evaluate().length;
      expect(copies, greaterThan(0));

      // Folding a card hides its actions.
      await tester.tap(find.text('Layer Mash'));
      await tester.pumpAndSettle();
      expect(find.text('Copy as my own formula').evaluate().length, copies - 1);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('setup-search')).first, 'grow');
      await tester.pumpAndSettle();
      expect(find.text('Fixed mix'), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('formula-action-Delete')).first);
      await tester.tap(find.byKey(const ValueKey('formula-action-Delete')).first);
      await tester.pumpAndSettle();
      expect(find.text('"My Grower" will be permanently removed. This does not affect past production batches.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(a.writes.lastWhere((w) => w.method == 'DELETE').url.path, '/api/Poultry/feed-formulas/2');
    });

    testWidgets('Add missing defaults asks the server again', (tester) async {
      final a = api();
      await open(tester, FeedFormulasScreen(session: await sessionFor(a), company: company), size: phone);
      final before = a.writes.where((w) => w.url.path == '/api/Poultry/feed-formulas/ensure-defaults').length;
      if (find.byKey(const ValueKey('task-defaults')).evaluate().isEmpty) {
        await tester.tap(find.byKey(const ValueKey('task-more')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add missing defaults').last);
      } else {
        await tester.tap(find.byKey(const ValueKey('task-defaults')));
      }
      await tester.pumpAndSettle();
      expect(a.writes.where((w) => w.url.path == '/api/Poultry/feed-formulas/ensure-defaults').length, before + 1);
      expect(find.textContaining('Nothing to add'), findsOneWidget);
    });

    testWidgets('empty', (tester) async {
      final a = FakeApi()..gets['/api/Poultry/feed-formulas'] = [];
      await open(tester, FeedFormulasScreen(session: await sessionFor(a), company: company), size: phone);
      expect(find.text('No feed formulas yet. Create one to speed up feed production.'), findsOneWidget);
    });
  });

  group('the lighter tabs on the task bar', () {
    Future<void> openTab(WidgetTester tester, FakeApi a, String tab) async =>
        open(tester, FarmSetupScreen(session: await sessionFor(a), company: company, href: '/poultry-setup?tab=$tab'), size: const Size(1200, 900));

    testWidgets('Customers: Add Customer, Export and Email Report (once there are customers); no filter row', (tester) async {
      final a = FakeApi()..gets['/api/Customer'] = [{'customerId': 1, 'name': 'Ama'}];
      await openTab(tester, a, 'customers');
      expect(await _barTasks(tester), containsAll(['add', 'pdf', 'email']));
      expect(_onBar(find.text('Add Customer')), findsOneWidget);
      expect(_onBar(find.text('Email Report')), findsOneWidget);
      expect(find.text('Filters'), findsNothing, reason: 'only the search stays in a tab');
    });

    testWidgets('Cash accounts: the web\'s seven tasks, Create default account under More', (tester) async {
      final a = FakeApi()
        ..gets['/api/Poultry/cash-accounts'] = [
          {'poultryCashAccountId': 5, 'accountName': 'Main Cash Account', 'accountType': 'Cash', 'currentBalance': 100, 'isActive': true},
        ];
      await openTab(tester, a, 'cash-accounts');
      expect(await _barTasks(tester), containsAll(['new', 'transfer', 'more']), reason: 'the primary first; what does not fit folds into More');
      expect(_onBar(find.text('Create default account')), findsNothing, reason: 'always in More');
      final inline = await _barTasks(tester);
      await tester.tap(find.byKey(const ValueKey('task-more')));
      await tester.pumpAndSettle();
      expect(find.text('Create default account'), findsOneWidget);
      // Every task is offered: on the bar or in More.
      for (final (id, label) in [('adjust', 'Record Cash Adjustment'), ('reconcile', 'Reconcile'), ('recalc', 'Recalculate'), ('report', 'Cash Account Report')]) {
        expect(inline.contains(id) || find.text(label).evaluate().isNotEmpty, isTrue, reason: label);
      }
    });

    testWidgets('Financial settings: Save changes on the task bar', (tester) async {
      final a = FakeApi()
        ..gets['/api/Poultry/financial-settings/cost-recognition'] = {
          'feedCostRecognitionMethod': 'ExpenseOnPurchase', 'medicationCostRecognitionMethod': 'ExpenseOnPurchase', 'isConfigured': true,
        };
      await openTab(tester, a, 'financial-settings');
      expect(_onBar(find.text('Save changes')), findsOneWidget);
      expect(await _barTasks(tester), isNot(contains('discard')), reason: 'nothing changed yet');
    });
  });

  group('Egg settings inside Farm Setup', () {
    testWidgets('the four tabs become four titled panels with their status; Open Egg Sorting is a task', (tester) async {
      await open(tester, FarmSetupScreen(session: await sessionFor(egg.configApi()), company: company, href: '/poultry-setup?tab=egg-settings'),
          size: const Size(1200, 4000));
      for (final t in ['Pick times', 'Egg sorting', 'Packaging & units', 'Egg sizes']) {
        expect(find.byKey(ValueKey('egg-quadrant-$t')), findsOneWidget, reason: t);
      }
      expect(find.text('3 picks a day'), findsOneWidget);
      expect(find.text('Crates of 30'), findsOneWidget);
      expect(find.text('1 active'), findsOneWidget);
      expect(find.textContaining('Unsorted on hand: 650', findRichText: true), findsOneWidget);
      expect(_onBar(find.text('Open Egg Sorting')), findsOneWidget);
      expect(find.text('Pick times are saved.'), findsOneWidget);

      // A pick time switched on is an unsaved change Farm Setup knows about.
      await tester.tap(find.byKey(const ValueKey('egg-config-qtoggle-4')));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Houses & pens'));
      await tester.pumpAndSettle();
      expect(find.text('You have unsaved changes on this tab. Leave without saving them?'), findsOneWidget);
    });

    testWidgets('on its own page it keeps its four tabs', (tester) async {
      await open(tester, EggPickSettingsScreen(session: await sessionFor(egg.configApi()), company: company), size: phone);
      expect(find.byKey(const ValueKey('egg-quadrant-Pick times')), findsNothing);
      expect(find.text('Egg Settings'), findsWidgets);
    });
  });

  group('Supply items', () {
    testWidgets('own page: Record Purchase first, then New Item and Receive Invoice; the redesigned cards', (tester) async {
      await open(tester, RawMaterialsScreen(session: await sessionFor(raw.api()), company: company), size: const Size(1200, 3000));
      expect(find.byKey(const ValueKey('task-purchase')), findsOneWidget);
      expect(find.byKey(const ValueKey('task-item')), findsOneWidget);
      expect(find.byKey(const ValueKey('task-more')), findsOneWidget, reason: 'Produce feed and Recalculate stock live in More');
      expect(find.byKey(ValueKey('raw-item-${raw.maize['poultryRawMaterialItemId']}')), findsOneWidget);
      expect(find.text('Stock value'), findsWidgets);
      expect(find.byTooltip('Buy more'), findsWidgets);
    });

    testWidgets('inside Farm Setup: the Items list only, New Item alone on the bar, no buying', (tester) async {
      await open(tester, FarmSetupScreen(session: await sessionFor(raw.api()), company: company, href: '/poultry-setup?tab=inventory'),
          size: const Size(1200, 3000));
      expect(await _barTasks(tester), ['item']);
      expect(find.text('Inventory & Supply Purchases'), findsNothing);
      expect(find.text('Purchases'), findsNothing, reason: 'no tabs, no summary');
      expect(find.byTooltip('Buy more'), findsNothing);
      expect(find.byTooltip('Edit item'), findsWidgets);
    });
  });
}
