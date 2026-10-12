// GENERATED from poultry_internal_use_test.dart for Water (app/water-internal-use):
// bags and sachets for crates and eggs, /api/Water and water* ids.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/water/water_internal_use_screen.dart';

import 'package:poultrycore_mobile/models/company.dart';

import 'support/harness.dart';

final water = Company(farmId: 'farm-1', name: 'Win Water', type: CompanyType.water);

final draft = <String, Object?>{
  'waterInternalUsageId': 1, 'referenceNo': 'IU-0001', 'usageDate': '2026-10-01T00:00:00', 'category': 'StaffWelfare',
  'recipientName': 'Production team', 'staffCount': 4, 'status': 'Draft', 'totalCostValue': 240,
  'items': [{'waterProductId': 1, 'productName': 'Sachet water', 'entryQuantity': 4, 'entryUnit': 'Bag', 'unitsPerEntryUnit': 30,
    'stockQuantity': 120, 'entryUnitCost': 60, 'quantityPerStaff': 1}],
};
final posted = <String, Object?>{
  'waterInternalUsageId': 2, 'referenceNo': 'IU-0002', 'usageDate': '2026-09-20T00:00:00', 'category': 'Donation',
  'status': 'Posted', 'totalCostValue': 90, 'reason': 'Church harvest',
  'items': [{'waterProductId': 2, 'productName': 'Bottle 1.5L', 'entryQuantity': 3, 'entryUnit': 'Pack', 'unitsPerEntryUnit': 1, 'entryUnitCost': 30}],
};
final reversed = <String, Object?>{
  'waterInternalUsageId': 3, 'usageDate': '2026-09-10T00:00:00', 'category': 'OwnerUse', 'status': 'Reversed', 'totalCostValue': 10,
  'reversalReason': 'Wrong quantity', 'reversedAt': '2026-09-11T10:00:00Z', 'reversedBy': 'Ama', 'createdBy': 'Kofi', 'createdAt': '2026-09-10T08:00:00Z',
  'items': [{'waterProductId': 1, 'productName': 'Sachet water', 'entryQuantity': 10, 'entryUnit': 'Sachet', 'unitsPerEntryUnit': 1, 'entryUnitCost': 1}],
};

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Water/internal-usage'] = [draft, posted, reversed]
  ..gets['/api/Water/products'] = [
    {'waterProductId': 1, 'name': 'Sachet water', 'isSachetProduct': true, 'unit': 'Sachet', 'sachetsPerBag': 30, 'stockOnHand': 300},
    {'waterProductId': 2, 'name': 'Bottle 1.5L', 'isSachetProduct': false, 'unit': 'Pack', 'stockOnHand': 10},
  ]
  ..gets['/api/Water/internal-usage/suggested-cost'] = {'unitCost': 55.5};

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 80 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, 200));
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

Finder inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> tapIn(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String shown, String option) async {
  await tapIn(tester, find.ancestor(of: inDialog(find.text(shown)), matching: find.byType(AppSelect<String>)).first);
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> enterIn(WidgetTester tester, String label, String text) async {
  final field = find.descendant(of: find.ancestor(of: inDialog(find.text(label)), matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.enterText(field.first, text);
  await tester.pump();
}

void clearToasts(WidgetTester tester) => tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

void main() {
  test('labels, quantities and filters', () {
    expect(waterInternalUseCategoryLabel('StaffWelfare'), 'Staff water allowance');
    expect(waterIsStaffCategory('OfficeUse'), isTrue);
    expect(describeWaterInternalQty(draft), '4 bags (120 sachets)');
    expect(describeWaterInternalQty(posted), '3 packs');
    final rows = [draft, posted, reversed];
    expect([for (final r in filterWaterInternalUse(rows, search: 'church')) r['waterInternalUsageId']], [2]);
    expect([for (final r in filterWaterInternalUse(rows, status: 'Reversed')) r['waterInternalUsageId']], [3]);
    expect([for (final r in filterWaterInternalUse(rows, category: 'Donation', from: '2026-09-15')) r['waterInternalUsageId']], [2]);
    expect(pageScreens.containsKey('/water-internal-use'), isTrue);
  });

  testWidgets('figures, cards, actions by status, post, delete, reverse, details', (tester) async {
    final a = api();
    await open(tester, WaterInternalUseScreen(session: await sessionFor(a), company: water), size: phone);

    expect(find.text('GHC 90.00'), findsWidgets, reason: 'posted cost');
    await see(tester, find.text('4 bags (120 sachets)'));
    expect(find.text('Production team'), findsOneWidget);

    await tap(tester, find.byTooltip('Post'));
    expect(find.textContaining('4 bags (120 sachets) comes out of stock and GHC 240.00'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    await tester.pumpAndSettle();
    expect(a.writes.last.url.path, '/api/Water/internal-usage/1/post');
    expect(a.writes.last.url.queryParameters['postedBy'], 'user-1');
    clearToasts(tester);

    await tap(tester, find.byTooltip('Reverse'));
    expect(find.text('Reverse this internal use?'), findsOneWidget);
    await tester.tap(find.ancestor(of: find.text('Select a reason'), matching: find.byType(AppSelect<String>)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wrong recipient or reason').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reverse'));
    await tester.pumpAndSettle();
    expect(a.writes.last.url.path, '/api/Water/internal-usage/2/reverse');
    expect(jsonDecode(a.writes.last.body), {'reason': 'Wrong recipient', 'userId': 'user-1'});
    clearToasts(tester);

    await tap(tester, find.byTooltip('Post again'));
    expect(find.text('Post this reversed record again?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await tap(tester, find.byTooltip('Delete').last);
    expect(find.text('Delete this reversed record?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(a.writes.last.method, 'DELETE');
    expect(a.writes.last.url.path, '/api/Water/internal-usage/3');

    await tap(tester, find.byTooltip('View details').last);
    expect(find.text('Reversed — Wrong quantity'), findsOneWidget);
    expect(find.text('10 sachets @ GHC 1.00'), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
  });

  testWidgets('the form: staff × each in crates, suggested cost, not enough stock, the body', (tester) async {
    final a = api();
    await open(tester, WaterInternalUseScreen(session: await sessionFor(a), company: water), size: phone);
    await tap(tester, find.text('Record internal use'));

    // The only sachet product is picked for you, as on the web.
    expect(find.text('300 sachet in stock · 1 bag = 30 sachets'), findsOneWidget);
    await tapIn(tester, inDialog(find.text('Save draft')));
    expect(find.textContaining('Enter a quantity greater than zero.'), findsOneWidget);
    clearToasts(tester);
    expect(a.requests.last.url.queryParameters['entryUnit'], 'Bag');
    await enterIn(tester, 'Number of staff', '3');
    await enterIn(tester, 'Bags each', '4');
    await tester.pumpAndSettle();
    expect(find.text('12 bags'), findsOneWidget);
    expect(find.text('360 sachets'), findsOneWidget);
    expect(find.textContaining('Not enough stock: only 300 sachet available, 360 needed.'), findsOneWidget);
    expect(tester.widget<FilledButton>(inDialog(find.widgetWithText(FilledButton, 'Save draft'))).onPressed, isNull);

    await enterIn(tester, 'Bags each', '2');
    await tester.pumpAndSettle();
    expect(find.text('= GHC 1.85 per sachet'), findsOneWidget, reason: '55.5 a bag');
    await tapIn(tester, inDialog(find.text('Save draft')));

    final b = jsonDecode(a.writes.lastWhere((w) => w.url.path == '/api/Water/internal-usage').body) as Map;
    expect((b['category'], b['staffCount'], b['createdBy']), ('StaffWelfare', 3, 'user-1'));
    final item = (b['items'] as List).single as Map;
    expect((item['waterProductId'], item['entryQuantity'], item['entryUnit'], item['quantityPerStaff'], item['entryUnitCost']),
        (1, 6, 'Bag', 2, 55.5));
    expect(item.containsKey('eggsPerCrate'), isFalse);
    expect(find.textContaining('Draft saved'), findsOneWidget);
  });

  testWidgets('editing a draft opens on its own figures and PUTs', (tester) async {
    final a = api();
    await open(tester, WaterInternalUseScreen(session: await sessionFor(a), company: water), size: phone);
    await tap(tester, find.byTooltip('Edit'));
    expect(find.text('Edit draft'), findsOneWidget);
    expect(find.text('Total quantity'), findsOneWidget);
    await tapIn(tester, inDialog(find.text('Save draft')));
    final w = a.writes.last;
    expect((w.method, w.url.path), ('PUT', '/api/Water/internal-usage/1'));
    expect((jsonDecode(w.body) as Map)['waterInternalUsageId'], 1);
  });
}
