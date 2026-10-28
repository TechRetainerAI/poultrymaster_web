// The Hotel sidebar at phone width (2026-10-21), as the web drawer now draws
// it (components/dashboard/sidebar.tsx, the isHotel branch → renderMenu).
// Switched on for Hotel on 2026-10-28: the menu button on every Hotel page
// opens it, as it does for Poultry, Water and Restaurant.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/hotel/hotel_guest_service_screens.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';
import 'package:poultrycore_mobile/state/session.dart';
import 'package:poultrycore_mobile/widgets/module_sidebar.dart';

import 'support/harness.dart';

final hotel = Company(farmId: 'farm-1', name: 'Palm Hotel', type: CompanyType.hotel, role: 'Admin');
const menus = ['Quick Links', 'Operations', 'Restaurant & Bar', 'Sales, Expenses & Money', 'Reports', 'Setup'];

Future<void> _openSidebar(WidgetTester tester, Session s) async {
  await open(
    tester,
    Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
      onPressed: () => showModuleSidebar(context, session: s, company: hotel),
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
  test('the menus and their columns follow hotel-nav-config.ts; existing rows keep their lists', () {
    final groups = webNavGroups['hotel']!;
    expect([for (final g in groups) g.title], [...menus, 'System']);
    List<String> subs(String t) => [for (final s in groups.firstWhere((g) => g.title == t).subGroups) s.title];
    expect(subs('Operations'), ['Front Desk', 'Guest Services', 'Rooms & Housekeeping']);
    expect(subs('Sales, Expenses & Money'), ['Sales', 'Expenses', 'Money']);
    expect(subs('Setup'), ['Hotel', 'People', 'Finance', 'Facilities']);
    expect(subs('Reports'),
        ['All reports', 'Financial', 'Operations', 'Restaurant & Bar', 'Periodic Reports', 'Housekeeping & Inventory', 'Revenue Management']);
    final links = [for (final g in groups) for (final s in g.subGroups) ...s.links];
    expect([for (final l in links) if (l.href.startsWith('/hotel-reports/')) l].length, 27);
    final guests = links.firstWhere((l) => l.href == '/hotel-guests');
    expect(guests.specKey, 'hotel-guests');
    final system = groups.firstWhere((g) => g.title == 'System').subGroups.single.links;
    expect([for (final l in system) l.label], ['Account', 'Companies', 'Billing']);
  });

  testWidgets('sections start closed in the web order; Operations and Restaurant & Bar open', (tester) async {
    await _openSidebar(tester, await sessionFor(FakeApi()));
    for (final t in [...menus, 'System']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    final y = [for (final t in [...menus, 'System']) tester.getTopLeft(find.text(t)).dy];
    expect(y, [...y]..sort());
    expect(find.text('Check-in'), findsNothing);

    await _tapIn(tester, 'Operations');
    for (final t in ['FRONT DESK', 'GUEST SERVICES', 'ROOMS & HOUSEKEEPING', 'Check-in', 'Lost & Found', 'HK Schedule']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await _tapIn(tester, 'Operations');

    await _tapIn(tester, 'Restaurant & Bar');
    for (final t in ['Orders', 'Menu', 'Kitchen', 'Tables']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await _tapIn(tester, 'Restaurant & Bar');

    await _tapIn(tester, 'Setup');
    for (final t in ['HOTEL', 'PEOPLE', 'FINANCE', 'FACILITIES', 'Hotel Setup', 'Supplies']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });
  test('Hotel has the sidebar, and every Hotel row has its own icon', () {
    expect(hasSidebar(CompanyType.hotel), isTrue);
    for (final g in webNavGroups['hotel']!) {
      for (final s in g.subGroups) {
        for (final l in s.links) {
          expect(sidebarIconFor(l.href), isNot(Icons.insert_chart_outlined), reason: l.href);
        }
      }
    }
  });

  testWidgets('a Hotel page has the sidebar button, and its row is highlighted with its menu open', (tester) async {
    final api = FakeApi()..gets['/api/Hotel/communications'] = [];
    final s = await sessionFor(api);
    await open(tester, HotelGuestLogScreen(session: s, company: hotel), size: phone);
    await tester.tap(find.byTooltip('Open sidebar'));
    await tester.pumpAndSettle();
    expect(find.text('VisibilityCore'), findsOneWidget);
    expect(find.text('GUEST SERVICES'), findsOneWidget, reason: 'Operations starts open on the page it was opened from');
    expect(find.text('Guest Log'), findsNWidgets(2), reason: 'the page behind, and its row in the drawer');
    await _tapIn(tester, 'Requests');
    expect(find.byType(HotelGuestRequestsScreen), findsOneWidget);
  });

  testWidgets('Quick Links stays the fixed Hotel list, whatever is stored', (tester) async {
    final api = FakeApi()..gets['/api/UserQuickLinks'] = {'customised': true, 'hrefs': ['/hotel-rooms']};
    await _openSidebar(tester, await sessionFor(api));
    await _tapIn(tester, 'Quick Links');
    for (final t in ['Daily Closing', 'Night Audit', 'Shift Handover', 'Bookings']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Rooms'), findsNothing);
    expect(find.text('Customise…'), findsNothing);
    expect(api.requests.where((r) => r.url.path == '/api/UserQuickLinks'), isEmpty);
  });
}
