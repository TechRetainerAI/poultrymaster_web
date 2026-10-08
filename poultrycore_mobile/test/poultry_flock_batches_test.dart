// Poultry → Operations → Purchase → Flock Purchases (Batches), at phone width.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/purchase/flock_batches_screen.dart';

import 'support/harness.dart';

final owing = <String, Object?>{
  'batchId': 1, 'batchName': 'Batch A', 'batchCode': 'B-001', 'breed': 'Isa Brown', 'numberOfBirds': 100, 'costPerChick': 5,
  'totalCost': 0, 'amountPaid': 200, 'supplierType': 'local', 'status': 'active', 'startDate': '2026-09-01T00:00:00',
};
final pending = <String, Object?>{
  'batchId': 2, 'batchName': 'Batch B', 'batchCode': 'B-002', 'breed': 'Cobb', 'numberOfBirds': 50, 'totalCost': 300, 'amountPaid': 300,
  'supplierType': 'foreign', 'status': 'pending', 'startDate': '2026-10-01T00:00:00', 'supplierName': 'Hatchery',
};

FakeApi api() => FakeApi()
  ..gets['/api/MainFlockBatch'] = [owing, pending]
  ..gets['/api/Flock'] = [
    {'flockId': 9, 'name': 'Pen 1', 'batchId': 1, 'quantity': 60, 'hasArrived': true, 'active': true, 'breed': 'Isa Brown', 'startDate': '2026-09-02T00:00:00'},
  ]
  ..gets['/api/Supplier'] = [{'supplierId': 4, 'name': 'Hatchery'}]
  ..gets['/api/Poultry/cash-accounts'] = [{'poultryCashAccountId': 5, 'accountName': 'Till', 'currentBalance': 900, 'isActive': true}]
  ..writeAnswers['/api/MainFlockBatch'] = {'batchId': 33, 'batchCode': 'B-003', 'numberOfBirds': 40};

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
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

Finder inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> tapIn(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Future<void> enterIn(WidgetTester tester, String label, String text) async {
  final field = find.descendant(of: find.ancestor(of: inDialog(find.text(label)), matching: find.byType(Column)).first, matching: find.byType(TextField));
  await tester.ensureVisible(field.first);
  await tester.enterText(field.first, text);
  await tester.pumpAndSettle();
}

void clearToasts(WidgetTester tester) => tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

void main() {
  test('status toggles, totals, allocation and filters', () {
    expect(batchToggles('pending'), (hasArrived: false, active: true));
    expect(batchStatus(true, false), 'inactive');
    expect((batchTotal(owing), batchOutstanding(owing)), (500, 300));
    expect(batchPaymentStatus(500, 200).$1, 'Part payment');
    expect(deriveTotalCost(2.555, 10), 25.55);
    final used = consumedByBatch([{'batchId': 1, 'quantity': 60}], [{'batchId': 1, 'historicalReduction': 10}]);
    expect(unallocatedForBatch(100, used[1]), 30);
    final f = BatchFilters()..status = 'pending';
    expect([for (final b in filterBatches([owing, pending], f)) b['batchId']], [2]);
    expect(filterBatches([owing, pending], BatchFilters()..search = 'b-001').length, 1);
    expect(pageScreens.containsKey('/flock-batch'), isTrue);
  });

  testWidgets('score cards, cards and actions, pay balance, delete', (tester) async {
    final a = api();
    await open(tester, FlockBatchesScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('Total Purchase Price (GHC)'), findsOneWidget);
    expect(find.text('800.00'), findsOneWidget, reason: '500 (derived) + 300');
    await see(tester, find.text('of 150 purchased'));

    await see(tester, find.text('Batch A'));
    expect(find.text('Divide'), findsNWidgets(2), reason: 'both batches still have unallocated birds');
    await tap(tester, find.text('Pay'));
    expect(find.text('Batch A — outstanding GHC 300.00'), findsOneWidget);
    await tester.enterText(inDialog(find.byType(TextField)).first, '400');
    await tapIn(tester, inDialog(find.text('Record payment')));
    expect(find.textContaining('Amount exceeds the outstanding balance (GHC 300.00).'), findsOneWidget);
    clearToasts(tester);
    await tester.enterText(inDialog(find.byType(TextField)).first, '100');
    await tapIn(tester, inDialog(find.text('Record payment')));
    final w = a.writes.last;
    expect(w.url.path, '/api/MainFlockBatch/1/pay-balance');
    expect((jsonDecode(w.body) as Map)['Amount'], 100);
    clearToasts(tester);

    await tap(tester, find.text('Delete'));
    expect(find.text('Delete Flock Batch'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(a.writes.any((x) => x.method == 'DELETE' && x.url.path == '/api/MainFlockBatch/1'), isTrue);

    await see(tester, find.text('TOTAL ACTIVE BIRDS'));
    await tap(tester, find.text('View table format'));
    expect(find.textContaining('60 allocated · 40 unallocated', findRichText: true), findsOneWidget);
  });

  testWidgets('add batch: checks, the derived total, the body, then divide prompt', (tester) async {
    final a = api();
    await open(tester, FlockBatchesScreen(session: await sessionFor(a), company: company), size: phone);
    await tester.tap(find.text('Add Flock Batch').first);
    await tester.pumpAndSettle();
    expect(find.text('Add New Flock Batch'), findsOneWidget);
    expect(inDialog(find.text('Dollar Conversion Rate')), findsNothing, reason: 'only for foreign purchases');
    await tapIn(tester, inDialog(find.text('Create Batch')));
    expect(inDialog(find.text('Please fill in all required fields')), findsOneWidget);
    clearToasts(tester);

    await enterIn(tester, 'Batch Name *', 'Batch C');
    await enterIn(tester, 'Batch Code *', 'B-003');
    await tapIn(tester, find.ancestor(of: inDialog(find.text('Start Date *')), matching: find.byType(Column)).first);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await enterIn(tester, 'Number of Birds *', '40');
    await enterIn(tester, 'Cost Per Chick', '2.5');
    expect(find.text('Part payment'), findsNothing);
    expect(find.text('Unpaid'), findsOneWidget, reason: 'total 100 now set, nothing paid');
    await tapIn(tester, inDialog(find.text('Create Batch')));
    final b = jsonDecode(a.writes.lastWhere((w) => w.url.path == '/api/MainFlockBatch').body) as Map;
    expect((b['BatchName'], b['NumberOfBirds'], b['TotalCost'], b['Status'], b['SupplierId'], b['PoultryCashAccountId']),
        ('Batch C', 40, 100, 'pending', null, null));
    expect(find.text('Batch B-003 created successfully'), findsOneWidget);
    expect(find.text("I'll Do This Later"), findsOneWidget);
  });

  testWidgets('edit batch PUTs the edit body', (tester) async {
    final a = api()..gets['/api/MainFlockBatch/1'] = owing;
    await open(tester, FlockBatchesScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Edit'));
    expect(find.text('Edit Flock Batch'), findsOneWidget);
    expect(inDialog(find.text('Raise this to record a further payment toward the balance.')), findsOneWidget);
    await tapIn(tester, inDialog(find.text('Update Batch')));
    final w = a.writes.last;
    expect((w.method, w.url.path), ('PUT', '/api/MainFlockBatch/1'));
    final b = jsonDecode(w.body) as Map;
    expect((b['StartDate'], b['Status'], b['PoultryCashAccountId'], b.containsKey('Notes')), ('2026-09-01T00:00:00Z', 'active', 0, false));
  });
}
