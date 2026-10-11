// Water → Operations → Production → Maintenance (app/water-maintenance) at
// phone width: the due alerts, the log, Log issue, Complete with and without
// a cash account, and Delete.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/design/ui/inputs.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/water/water_maintenance_screen.dart';

import 'support/harness.dart';

final open1 = <String, Object?>{
  'waterMaintenanceLogId': 1, 'assetType': 'Machine', 'assetLabel': 'Line A', 'issueDate': '2026-10-05T00:00:00',
  'issueDescription': 'Sealer jaw worn', 'technicianName': 'Kojo', 'repairCost': 250, 'status': 'Open',
};
final done = <String, Object?>{
  'waterMaintenanceLogId': 2, 'assetType': 'Vehicle', 'assetLabel': 'Truck 1', 'issueDate': '2026-09-01T00:00:00',
  'issueDescription': 'Brake pads', 'repairCost': 400, 'status': 'Completed', 'cashTransactionWritten': true,
};

FakeApi api() => FakeApi()
  ..gets['/api/CompanyTime/context'] = {
    'businessDate': '2026-10-06', 'companyLocalDateTime': '2026-10-06T10:00:00', 'utcNow': '2026-10-06T10:00:00Z',
  }
  ..gets['/api/Water/maintenance-logs'] = [open1, done]
  ..gets['/api/Water/maintenance-logs/due-alerts'] = [
    {'assetType': 'Generator', 'assetId': 3, 'assetLabel': 'Genset', 'nextDueDate': '2026-10-01', 'daysUntilDue': -5, 'severity': 'Overdue'},
  ]
  ..gets['/api/Water/cash-accounts'] = [
    {'waterCashAccountId': 5, 'accountName': 'Main Cash', 'currentBalance': 900, 'isActive': true},
    {'waterCashAccountId': 6, 'accountName': 'Old box', 'currentBalance': 0, 'isActive': false},
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

Future<void> tapIn(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> enterIn(WidgetTester tester, String label, String text) async {
  final field = find.descendant(of: find.ancestor(of: inDialog(find.text(label)), matching: find.byType(Column)).first, matching: find.byType(TextFormField));
  await tester.ensureVisible(field.first);
  await tester.enterText(field.first, text);
  await tester.pump();
}

void clearToasts(WidgetTester tester) =>
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();

void main() {
  test('due wording, filters, the route', () {
    expect(waterDueIn(3), 'in 3d');
    expect(waterDueIn(-5), '5d ago');
    expect([for (final l in filterWaterMaintenance([open1, done], search: 'kojo')) l['assetLabel']], ['Line A']);
    expect([for (final l in filterWaterMaintenance([open1, done], to: '2026-09-30')) l['assetLabel']], ['Truck 1']);
    expect(pageScreens.containsKey('/water-maintenance'), isTrue);
  });

  testWidgets('alerts, cards, Complete only while open, Delete', (tester) async {
    final a = api();
    await open(tester, WaterMaintenanceScreen(session: await sessionFor(a), company: company), size: phone);
    expect(find.text('Due maintenance (1)'), findsOneWidget);
    expect(find.textContaining('(5d ago)'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    await see(tester, find.text('Machine · Line A'));
    expect(find.text('250.00'), findsOneWidget);
    await see(tester, find.text('Vehicle · Truck 1'));
    expect(find.widgetWithText(OutlinedButton, 'Complete'), findsOneWidget, reason: 'not on the completed log');

    await tap(tester, find.widgetWithText(OutlinedButton, 'Delete').last);
    expect(find.textContaining('Delete the log for "Truck 1"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    final d = a.writes.last;
    expect((d.method, d.url.path), ('DELETE', '/api/Water/maintenance-logs/2'));
    expect(find.textContaining('Log deleted'), findsOneWidget);
  });

  testWidgets('Complete: the active cash accounts, the body, the toast', (tester) async {
    final a = api();
    await open(tester, WaterMaintenanceScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Complete'));
    expect(find.textContaining('Picking a cash account will book a CashOut', findRichText: true), findsOneWidget);
    await tapIn(tester, find.ancestor(of: inDialog(find.text('None (no cash impact)')), matching: find.byType(AppSelect<int>)).first);
    expect(find.text('Old box (0.00)'), findsNothing, reason: 'inactive accounts are left out');
    await tester.tap(find.text('Main Cash (900.00)').last);
    await tester.pumpAndSettle();
    await tapIn(tester, inDialog(find.text('Mark completed')));
    final w = a.writes.last;
    expect(w.url.path, '/api/Water/maintenance-logs/1/complete');
    expect(w.url.queryParameters, {'farmId': 'farm-1', 'completedBy': 'user-1'});
    expect(jsonDecode(w.body), {'waterCashAccountId': 5});
    expect(find.textContaining('Marked completed — cash booked'), findsOneWidget);
  });

  testWidgets('Log issue: the required issue, the asset type, the body', (tester) async {
    final a = api();
    await open(tester, WaterMaintenanceScreen(session: await sessionFor(a), company: company), size: phone);
    await tap(tester, find.text('Log issue'));
    await tapIn(tester, inDialog(find.text('Log')));
    expect(find.textContaining('Issue description required'), findsOneWidget);
    clearToasts(tester);

    await tapIn(tester, find.ancestor(of: inDialog(find.text('Machine')), matching: find.byType(AppSelect<String>)).first);
    await tester.tap(find.text('Generator').last);
    await tester.pumpAndSettle();
    await enterIn(tester, 'Asset label / name', 'Genset');
    await enterIn(tester, 'Issue description *', 'Will not start');
    await enterIn(tester, 'Repair cost', '120.5');
    await enterIn(tester, 'Downtime hours', '3');
    await tapIn(tester, inDialog(find.text('Log')));
    final b = jsonDecode(a.writes.last.body) as Map;
    expect(a.writes.last.url.path, '/api/Water/maintenance-logs');
    expect((b['assetType'], b['assetLabel'], b['issueDescription'], b['repairCost'], b['downtimeHours'], b['assetId'], b['createdBy']),
        ('Generator', 'Genset', 'Will not start', 120.5, 3, null, 'user-1'));
    expect(find.textContaining('Maintenance logged'), findsOneWidget);
  });
}
