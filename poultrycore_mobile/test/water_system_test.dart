// Water's System menu at phone width (water-nav-config.ts `system`): Alerts,
// Billing, Activity Log and Terms & Conditions — Account is hidden on the web.
// The pages are the web's shared ones, so Water opens the same screens as
// Poultry (their own behaviour is covered in poultry_settings_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/shared/activity_log_screen.dart';
import 'package:poultrycore_mobile/pages/shared/billing_screen.dart';
import 'package:poultrycore_mobile/pages/shared/terms_screen.dart';
import 'package:poultrycore_mobile/state/session.dart';
import 'package:poultrycore_mobile/widgets/all_pages_sheet.dart';
import 'package:poultrycore_mobile/widgets/module_sidebar.dart';

import 'support/harness.dart';

final water = Company(farmId: 'farm-1', name: 'Water Co', type: CompanyType.water, role: 'Admin');

FakeApi _api() => FakeApi()
  ..gets['/api/UserQuickLinks'] = {'customised': false, 'hrefs': []}
  ..gets['/api/AuditLogs'] = [];

Future<void> _openWith(WidgetTester tester, Session s, void Function(BuildContext) show) async {
  await open(
    tester,
    Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
      onPressed: () => show(context),
      child: const Text('menu'),
    )))),
    size: phone,
  );
  await tester.tap(find.text('menu'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _openSystem(WidgetTester tester, Session s) async {
  await _openWith(tester, s, (c) => showModuleSidebar(c, session: s, company: water));
  await _tap(tester, find.text('System'));
}

void main() {
  testWidgets('drawer: the web rows in order, no Account', (tester) async {
    await _openSystem(tester, await sessionFor(_api()));
    const rows = ['Alerts', 'Billing', 'Activity Log', 'Terms & Conditions'];
    for (final r in rows) {
      expect(find.text(r), findsOneWidget, reason: r);
    }
    expect(find.text('Account'), findsNothing);
    final y = [for (final r in rows) tester.getTopLeft(find.text(r)).dy];
    expect(y, [...y]..sort());
  });

  testWidgets('drawer: Alerts opens the alerts dialog', (tester) async {
    await _openSystem(tester, await sessionFor(_api()));
    await _tap(tester, find.text('Alerts'));
    expect(find.text('System Alerts and Notifications'), findsOneWidget);
    expect(find.text('No alerts'), findsOneWidget);
  });

  for (final (row, screen) in [('Billing', BillingScreen), ('Activity Log', ActivityLogScreen), ('Terms & Conditions', TermsScreen)]) {
    testWidgets('drawer: $row opens its own screen', (tester) async {
      await _openSystem(tester, await sessionFor(_api()));
      await _tap(tester, find.text(row));
      expect(find.byType(screen), findsOneWidget);
    });
  }

  testWidgets('More sheet: System → Alerts opens the dialog, not a page', (tester) async {
    final s = await sessionFor(_api());
    await _openWith(tester, s, (c) => showAllPages(c, s, water));
    await _tap(tester, find.text('SYSTEM'));
    expect(find.text('Account'), findsNothing);
    await _tap(tester, find.text('Alerts'));
    expect(find.text('System Alerts and Notifications'), findsOneWidget);
  });
}
