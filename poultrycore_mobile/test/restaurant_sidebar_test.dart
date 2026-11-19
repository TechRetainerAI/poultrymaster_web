// The Restaurant sidebar at phone width (2026-10-21), as the web drawer now
// draws it (components/dashboard/sidebar.tsx, the isRestaurant branch →
// renderMenu): one collapsible section per menu, as Poultry and Water.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';
import 'package:poultrycore_mobile/state/session.dart';
import 'package:poultrycore_mobile/widgets/module_sidebar.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const menus = ['Quick Links', 'Orders & Kitchen', 'Dining', 'Delivery & Online', 'Inventory', 'Sales, Expenses & Money', 'Growth', 'Reports', 'Setup'];

Future<void> _openSidebar(WidgetTester tester, Session s) async {
  await open(
    tester,
    Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
      onPressed: () => showModuleSidebar(context, session: s, company: rest),
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
  test('the menus and their columns follow restaurant-nav-config.ts; every report row has a native screen', () {
    final groups = webNavGroups['restaurant']!;
    expect([for (final g in groups) g.title], [...menus, 'System', 'More pages']);
    List<String> subs(String t) => [for (final s in groups.firstWhere((g) => g.title == t).subGroups) s.title];
    expect(subs('Orders & Kitchen'), ['Orders', 'Kitchen']);
    expect(subs('Delivery & Online'), ['Online Ordering', 'Delivery']);
    expect(subs('Growth'), ['Customers', 'More']);
    expect(subs('Setup'), ['Menu & Staff', 'Finance']);
    expect(subs('Reports'), ['All reports', 'Money', 'Cash & Ledger', 'Sales', 'Menu & Food', 'Operations', 'Guests & Channels']);
    final reports = [for (final s in groups.firstWhere((g) => g.title == 'Reports').subGroups) ...s.links];
    expect(reports.length, 35);
    for (final l in reports) {
      expect(pageScreens.containsKey(l.href), isTrue, reason: l.href);
    }
  });

  testWidgets('sections start closed, in the web order, with System below', (tester) async {
    await _openSidebar(tester, await sessionFor(FakeApi()));
    for (final t in [...menus, 'System']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('POS / New Order'), findsNothing, reason: 'sections are closed until tapped');
    expect(find.text('More pages'), findsNothing);
    final y = [for (final t in [...menus, 'System']) tester.getTopLeft(find.text(t)).dy];
    expect(y, [...y]..sort());
  });

  testWidgets('Orders & Kitchen shows its columns; Inventory and Dining list rows directly; Reports leads with All reports',
      (tester) async {
    await _openSidebar(tester, await sessionFor(FakeApi()));
    await _tapIn(tester, 'Orders & Kitchen');
    for (final t in ['ORDERS', 'KITCHEN', 'POS / New Order', 'New Guest Orders', 'All Orders', 'Kitchen Display']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await _tapIn(tester, 'Orders & Kitchen');

    await _tapIn(tester, 'Inventory');
    expect(find.text('Ingredients & Stock'), findsOneWidget);
    expect(find.text('Record Purchase'), findsOneWidget);
    expect(find.text('INVENTORY'), findsNothing, reason: 'a one-column menu shows its rows directly');
    await _tapIn(tester, 'Inventory');

    await _tapIn(tester, 'Setup');
    for (final t in ['MENU & STAFF', 'FINANCE', 'Menu Items', 'Staff', 'Restaurant Setup', 'Suppliers']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await _tapIn(tester, 'Setup');

    await _tapIn(tester, 'Reports');
    for (final t in ['ALL REPORTS', 'MONEY', 'CASH & LEDGER', 'GUESTS & CHANNELS', 'Takings by Account', 'Channel Profitability']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(tester.getTopLeft(find.text('ALL REPORTS')).dy, lessThan(tester.getTopLeft(find.text('MONEY')).dy));
    await _tapIn(tester, 'Reports');

    await _tapIn(tester, 'System');
    for (final t in ['Account', 'My Account', 'Companies', 'Billing']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });
}
