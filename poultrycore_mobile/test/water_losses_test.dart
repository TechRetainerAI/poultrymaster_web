// Water → Operations → Inventory → Damages & loss (app/water-loss-records)
// and Production losses (app/water-production-losses) at phone width.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/water/water_losses_screen.dart';

import 'support/harness.dart';

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Water/loss-records'] = [
    {'waterLossRecordId': 1, 'lossDate': '2026-10-05T00:00:00', 'lossType': 'BurstSachets', 'quantityBags': 0, 'quantitySachets': 40,
      'estimatedValue': 20, 'reason': 'Heat', 'status': 'Pending', 'waterProductId': 7},
    {'waterLossRecordId': 2, 'lossDate': '2026-10-01T00:00:00', 'lossType': 'DriverShortage', 'quantityBags': 3, 'estimatedValue': 18,
      'reason': 'Short on return', 'status': 'Approved'},
  ]
  ..gets['/api/Water/products'] = [
    {'waterProductId': 7, 'name': 'Sachet 500ml'},
  ]
  ..gets['/api/Water/production-losses'] = [
    {'waterProductionLossId': 1, 'lossDate': '2026-10-04T00:00:00', 'lossType': 'DamagedBags', 'sourceType': 'ProductionBatch', 'sourceId': 5,
      'batchNumber': 'B-5', 'productName': 'Sachet 500ml', 'bagsLost': 2, 'sachetsLost': 10, 'bagsLossValue': 10, 'sachetsLossValue': 1,
      'totalValue': 11, 'status': 'Approved'},
    {'waterProductionLossId': 2, 'lossDate': '2026-10-03T00:00:00', 'lossType': 'DamagedBags', 'sourceType': 'ProductionBatch', 'sourceId': 6,
      'bagsLost': 9, 'sachetsLost': 0, 'totalValue': 45, 'status': 'Cancelled'},
  ];

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

Future<void> enterIn(WidgetTester tester, String label, String text) async {
  final field = find.descendant(of: find.ancestor(of: inDialog(find.text(label)), matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.ensureVisible(field.first);
  await tester.enterText(field.first, text);
  await tester.pumpAndSettle();
}

Future<void> tapIn(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

void clearToasts(WidgetTester tester) =>
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

void main() {
  test('both pages on the sidebar', () {
    expect(pageScreens.containsKey('/water-loss-records'), isTrue);
    expect(pageScreens.containsKey('/water-production-losses'), isTrue);
  });

  testWidgets('Loss records: totals, type filter, Approve, Unapprove with a reason', (tester) async {
    final a = api();
    await open(tester, WaterLossRecordsScreen(session: await sessionFor(a), company: company), size: phone);
    await see(tester, find.text('Approved value'));
    expect(find.text('GHC 18.00'), findsWidgets);
    await see(tester, find.text('BurstSachets · GHC 20.00'));
    await tap(tester, find.widgetWithText(OutlinedButton, 'Approve'));
    expect(a.writes.last.url.path, '/api/Water/loss-records/1/approve');
    expect(a.writes.last.url.queryParameters['approvedBy'], 'user-1');
    clearToasts(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Unapprove'));
    expect(find.textContaining('flip DriverShortage from Approved back to Pending'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Unapprove'));
    await tester.pumpAndSettle();
    expect(find.text('Reason for unapproving is required.'), findsOneWidget);
    await reasonPick(tester, 'Wrong quantity');
    await tester.tap(find.widgetWithText(FilledButton, 'Unapprove'));
    await tester.pumpAndSettle();
    final w = a.writes.last;
    expect((w.url.path, w.url.queryParameters['unapprovedBy']), ('/api/Water/loss-records/2/unapprove', 'user-1'));
    expect(jsonDecode(w.body), {'reason': 'Wrong quantity'});
    expect(find.textContaining('Loss unapproved — now editable'), findsOneWidget);
    clearToasts(tester);

    await see(tester, find.text('All types'));
    await tester.tap(find.ancestor(of: find.text('All types'), matching: find.byType(AppSelect<String>)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('BurstSachets').last);
    await tester.pumpAndSettle();
    expect(a.requests.lastWhere((r) => r.url.path == '/api/Water/loss-records').url.queryParameters['lossType'], 'BurstSachets');
  });

  testWidgets('Record loss: the reason is required, blanks go as null, Edit PUTs', (tester) async {
    final a = api();
    await open(tester, WaterLossRecordsScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Record loss'));
    await tapIn(tester, inDialog(find.text('Record')));
    expect(find.textContaining('Reason required'), findsOneWidget);
    clearToasts(tester);
    await enterIn(tester, 'Bags', '2');
    await reasonOther(tester, 'Dropped');
    await tapIn(tester, inDialog(find.text('Record')));
    final b = jsonDecode(a.writes.last.body) as Map;
    expect((b['lossType'], b['quantityBags'], b['quantitySachets'], b['estimatedValue'], b['waterProductId'], b['reason']),
        ('DamagedBags', 2, null, null, 7, 'Dropped'));
    expect(find.textContaining('Loss recorded — pending approval'), findsOneWidget);
    clearToasts(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Edit'));
    expect(find.text('Edit loss record'), findsOneWidget);
    // 'Heat' is not in LOSS_REASONS, so the form opens on Other with it typed.
    await reasonOther(tester, 'Heat wave');
    await tapIn(tester, inDialog(find.text('Save changes')));
    final w = a.writes.last;
    expect((w.method, w.url.path), ('PUT', '/api/Water/loss-records/1'));
    expect((jsonDecode(w.body) as Map)['reason'], 'Heat wave');
  });

  testWidgets('Production losses: approved-only totals, View batch', (tester) async {
    final a = api();
    await open(tester, WaterProductionLossesScreen(session: await sessionFor(a), company: company), size: phone);
    await see(tester, find.text('Total value'));
    expect(find.text('GHC 11.00'), findsWidgets, reason: 'the cancelled loss is left out');
    await see(tester, find.text('B-5 · Sachet 500ml'));
    await see(tester, find.text('#6 · —'));
    expect(find.text('View batch'), findsNWidgets(2));
  });
}
