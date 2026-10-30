// The Water sidebar at phone width, as the web drawer draws it
// (components/dashboard/sidebar.tsx, the isWater branch → renderMenu): one
// collapsible section per top-nav menu, closed until tapped, each showing
// its columns as uppercase sub-headings with their rows.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/state/session.dart';
import 'package:poultrycore_mobile/widgets/module_sidebar.dart';

import 'support/harness.dart';

final water = Company(farmId: 'farm-1', name: 'Water Co', type: CompanyType.water, role: 'Admin');

Future<void> _openSidebar(WidgetTester tester, Session s, {String? activeHref}) async {
  await open(
    tester,
    Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
      onPressed: () => showModuleSidebar(context, session: s, company: water, activeHref: activeHref),
      child: const Text('menu'),
    )))),
    size: phone,
  );
  await tester.tap(find.text('menu'));
  await tester.pumpAndSettle();
}

Future<void> _tapIn(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sections start closed, in the web order, with System below', (tester) async {
    final a = FakeApi()..gets['/api/UserQuickLinks'] = {'customised': false, 'hrefs': []};
    await _openSidebar(tester, await sessionFor(a));
    for (final t in ['Business Office', 'Dashboard', 'Quick Links', 'Operations', 'Sales, Expenses & Money', 'Trackers', 'Reports', 'Setup', 'System']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Water Production'), findsNothing, reason: 'sections are closed until tapped');
    expect(find.text('PRODUCTION'), findsNothing);
    final y = [for (final t in ['Quick Links', 'Operations', 'Sales, Expenses & Money', 'Trackers', 'Reports', 'Setup', 'System']) tester.getTopLeft(find.text(t)).dy];
    expect(y, [...y]..sort());
  });

  testWidgets('Operations opens to Production, Inventory and Delivery with their pages', (tester) async {
    final a = FakeApi()..gets['/api/UserQuickLinks'] = {'customised': false, 'hrefs': []};
    await _openSidebar(tester, await sessionFor(a));
    await _tapIn(tester, 'Operations');
    for (final h in ['PRODUCTION', 'INVENTORY', 'DELIVERY']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }
    for (final p in ['Water Production', 'Batch Production', 'Maintenance', 'Stock movement', 'Inventory', 'Inventory & supply purchases',
      'Damages & loss', 'Production losses', 'Deliveries', 'Driver collection report']) {
      expect(find.text(p), findsOneWidget, reason: p);
    }
    expect(tester.getTopLeft(find.text('PRODUCTION')).dy, lessThan(tester.getTopLeft(find.text('Water Production')).dy));
    expect(tester.getTopLeft(find.text('Maintenance')).dy, lessThan(tester.getTopLeft(find.text('INVENTORY')).dy));

    // A sub-heading collapses on its own; the section collapses as a whole.
    await _tapIn(tester, 'INVENTORY');
    expect(find.text('Stock movement'), findsNothing);
    expect(find.text('Water Production'), findsOneWidget);
    await _tapIn(tester, 'Operations');
    expect(find.text('PRODUCTION'), findsNothing);
  });

  testWidgets('Sales, Expenses & Money and Reports show their groups; Trackers its rows directly', (tester) async {
    final a = FakeApi()..gets['/api/UserQuickLinks'] = {'customised': false, 'hrefs': []};
    await _openSidebar(tester, await sessionFor(a));
    await _tapIn(tester, 'Sales, Expenses & Money');
    for (final h in ['SALES', 'EXPENSES', 'MONEY']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }
    expect(find.text('Capital Investments/Assets'), findsOneWidget);
    await _tapIn(tester, 'Sales, Expenses & Money');

    await _tapIn(tester, 'Trackers');
    expect(find.text('Inventory tracker'), findsOneWidget);
    expect(find.text('STOCK'), findsNothing, reason: 'a one-column menu shows its rows directly');

    await _tapIn(tester, 'Reports');
    for (final h in ['ALL REPORTS', 'FINANCIAL', 'SALES & CUSTOMERS', 'PRODUCTION & INVENTORY', 'DELIVERY & OPERATIONS']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }
    expect(find.text('View all reports →'), findsNothing, reason: "that is the desktop panel's header link");
  });

  testWidgets('opened from Deliveries: Operations is already open', (tester) async {
    final a = FakeApi()..gets['/api/UserQuickLinks'] = {'customised': false, 'hrefs': []};
    await _openSidebar(tester, await sessionFor(a), activeHref: '/water-driver-returns');
    expect(find.text('DELIVERY'), findsOneWidget);
    expect(find.text('Deliveries'), findsWidgets);
  });
}
