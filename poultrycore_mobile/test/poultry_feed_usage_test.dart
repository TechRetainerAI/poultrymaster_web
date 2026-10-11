// Poultry → Operations → Production → Feed Usage, at phone width: the list
// and filters, the Add dialog (checks, body, the production-record write),
// edit and delete.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/production/feed_usage_screen.dart';

import 'support/harness.dart';

FakeApi api() => FakeApi()
  ..gets['/api/FeedUsage'] = [
    {'feedUsageId': 1, 'flockId': 7, 'usageDate': '2026-10-05T00:00:00', 'feedType': 'Layer Feed', 'quantityKg': 25.5},
    {'feedUsageId': 2, 'flockId': 8, 'usageDate': '2026-09-02T00:00:00', 'feedType': 'Grower Feed', 'quantityKg': 10},
  ]
  ..gets['/api/FeedUsage/1'] = {'feedUsageId': 1, 'flockId': 7, 'usageDate': '2026-10-05T00:00:00', 'feedType': 'Layer Feed', 'quantityKg': 25.5}
  ..gets['/api/ProductionRecord'] = [
    {'id': 5, 'flockId': 7, 'date': '2026-10-05T00:00:00Z', 'feedKg': 3},
  ]
  ..gets['/api/Flock'] = [
    {'flockId': 7, 'name': 'Pen 1', 'breed': 'Isa', 'quantity': 130, 'active': true, 'hasArrived': true, 'startDate': '2026-07-10T00:00:00'},
    {'flockId': 8, 'name': 'Pen 2', 'breed': 'Lohmann', 'quantity': 80, 'active': true, 'hasArrived': true, 'startDate': '2026-08-01T00:00:00'},
    {'flockId': 9, 'name': 'Waiting', 'breed': 'Isa', 'quantity': 50, 'active': true, 'hasArrived': false},
  ];

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
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
  final sel = find.ancestor(of: label.first, matching: find.byWidgetPredicate((w) => w is AppSelect)).first;
  await tester.ensureVisible(sel);
  await tester.pumpAndSettle();
  await tester.tap(sel);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Finder get _dialog => find.byType(AlertDialog);

void main() {
  test('flock label and route', () {
    expect(feedFlockLabel({'name': 'Pen 1', 'breed': 'Isa', 'quantity': 130, 'active': true, 'hasArrived': true}), 'Pen 1 (Isa) - 130 birds');
    expect(feedFlockLabel({'name': 'P', 'breed': 'B', 'quantity': 1, 'active': true, 'hasArrived': false}), 'P (B) - 1 birds · Pending arrival');
    expect(pageScreens.containsKey('/feed-usage'), isTrue);
  });

  testWidgets('list: tiles, filters, delete', (tester) async {
    final a = api();
    await open(tester, FeedUsageScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('35.50 kg'), findsOneWidget);
    expect(find.text('25.5 kg'), findsOneWidget);

    await tap(tester, find.text('Filters'));
    await choose(tester, 'All Flocks', 'Pen 2', within: find.byType(BottomSheet));
    await choose(tester, 'All Months', 'September', within: find.byType(BottomSheet));
    await choose(tester, 'All Years', '2026', within: find.byType(BottomSheet));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('25.5 kg'), findsNothing);
    expect(find.text('10.00 kg'), findsOneWidget);

    await tap(tester, find.text('Delete'));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect((a.writes.last.method, a.writes.last.url.path), ('DELETE', '/api/FeedUsage/2'));
  });

  testWidgets('add: the checks, then the body and a new production record', (tester) async {
    final a = api();
    await open(tester, FeedUsageScreen(session: await sessionFor(a), company: company), size: phone);
    await tester.tap(find.text('Add Usage'));
    await tester.pumpAndSettle();
    expect(find.text('Record feed consumption for a flock'), findsOneWidget);

    await tester.enterText(find.descendant(of: _dialog, matching: find.byType(TextField)), '12');
    await tester.tap(find.text('Record Usage'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _dialog, matching: find.text('Choose a flock')), findsOneWidget);

    await choose(tester, 'Select a flock', 'Pen 2 (Lohmann) - 80 birds', within: _dialog);
    expect(find.text('Waiting (Isa) - 50 birds · Pending arrival'), findsNothing);
    await tester.tap(find.text('Record Usage'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _dialog, matching: find.text('Choose a feed type')), findsOneWidget);
    await choose(tester, 'Select feed type', 'Grower Feed', within: _dialog);
    await tester.tap(find.text('Record Usage'));
    await tester.pumpAndSettle();

    final b = jsonDecode(a.writes.firstWhere((w) => w.url.path == '/api/FeedUsage').body) as Map;
    expect((b['FlockId'], b['FeedType'], b['QuantityKg'], b['FeedUsageId']), (8, 'Grower Feed', 12, 0));
    expect((b['UsageDate'] as String).endsWith('T00:00:00Z'), isTrue);
    final pr = jsonDecode(a.writes.lastWhere((w) => w.url.path == '/api/ProductionRecord').body) as Map;
    expect((pr['FlockId'], pr['feedKg'], pr['noOfBirds'], pr['medication'], pr['totalProduction']), (8, 12, 80, 'None', 0));
    expect(find.textContaining('Feed usage recorded successfully.'), findsOneWidget);
  });

  testWidgets('edit: loads the record, PUTs and updates the matching production record', (tester) async {
    final a = api();
    await open(tester, FeedUsageScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Edit'));
    expect(find.text('Edit Feed Usage'), findsOneWidget);
    expect(find.text('Layer Feed'), findsWidgets);
    await tester.enterText(find.descendant(of: _dialog, matching: find.byType(TextField)), '30');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    final w = a.writes.firstWhere((w) => w.url.path == '/api/FeedUsage/1');
    final b = jsonDecode(w.body) as Map;
    expect((w.method, b['FeedUsageId'], b['FlockId'], b['QuantityKg'], b['UsageDate']), ('PUT', 1, 7, 30, '2026-10-05T00:00:00Z'));
    final pr = jsonDecode(a.writes.lastWhere((w) => w.url.path == '/api/ProductionRecord/5').body) as Map;
    expect((pr['id'], pr['feedKg'], pr.containsKey('FlockId')), (5, 30, false));
  });
}
