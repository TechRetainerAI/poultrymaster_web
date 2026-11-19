// Restaurant sweep (2026-10-21): every link in the Restaurant menus opens a
// native screen that draws at 360 px without an exception, and no screen
// calls an endpoint the server now keeps for another company type
// (RequireCompanyType, commit 2baf33a4) — except the two shared settings the
// web reads the same way (see plan.md).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/money/money_routes.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');

/// Links that are not pages, or are shared web pages by design.
const notNative = {'#alerts', '/terms', '/restaurant-qr-print'};

/// Read the same way by the web's Restaurant pages, and guarded on the server
/// for another type since the pull — reported, not changed here.
const knownShared = {'/api/Water/farm-settings', '/api/Hotel/setup/menu-category-types'};

List<NavLink> restaurantLinks() => [
      for (final g in webNavGroups['restaurant']!)
        for (final s in g.subGroups) ...s.links,
    ];

/// Every in-page link a Restaurant screen follows (collected from the source).
const inPageLinks = [
  '/restaurant-assets',
  '/restaurant-cash-accounts',
  '/restaurant-cash-flow',
  '/restaurant-cash-reconciliation',
  '/restaurant-cash-transfers',
  '/restaurant-crm',
  '/restaurant-customer-balances',
  '/restaurant-daily-closing',
  '/restaurant-dashboard',
  '/restaurant-deferred-costs',
  '/restaurant-delivery',
  '/restaurant-events',
  '/restaurant-expenses',
  '/restaurant-expenses?expenseId=5',
  '/restaurant-financial-activity',
  '/restaurant-floor-plan',
  '/restaurant-gift-cards',
  '/restaurant-internal-use',
  '/restaurant-inventory',
  '/restaurant-inventory?purchase=1',
  '/restaurant-inventory?tab=purchases',
  '/restaurant-inventory?tab=purchases&purchaseId=5',
  '/restaurant-kds',
  '/restaurant-loans',
  '/restaurant-loyalty',
  '/restaurant-menu',
  '/restaurant-notifications',
  '/restaurant-online-orders',
  '/restaurant-order-online',
  '/restaurant-orders',
  '/restaurant-orders?highlight=5',
  '/restaurant-orders?orderId=5',
  '/restaurant-owner-money',
  '/restaurant-payments',
  '/restaurant-payroll',
  '/restaurant-pending-orders',
  '/restaurant-pos',
  '/restaurant-profit-loss',
  '/restaurant-recurring-expenses',
  '/restaurant-reports',
  '/restaurant-reservations',
  '/restaurant-sales',
  '/restaurant-setup',
  '/restaurant-staff',
  '/restaurant-staff-loans',
  '/restaurant-staff-loans?staffId=5',
  '/restaurant-supplier-balances',
  '/restaurant-supplier-payments',
  '/restaurant-suppliers',
  '/restaurant-tills',
];

void main() {
  test('every in-page link between Restaurant screens reaches a native screen, never the in-app web page', () async {
    final s = await sessionFor(FakeApi());
    final specHrefs = {for (final l in restaurantLinks()) if (l.specKey != null) l.href};
    final web = [
      for (final h in inPageLinks)
        if (pageScreens[h] == null && moneyScreenForHref(h, s, rest) == null && !specHrefs.contains(h)) h,
    ];
    expect(web, isEmpty);
  });

  test('every Restaurant menu link has a native screen (its own page, or the generated list for its specKey)', () {
    final missing = [
      for (final l in restaurantLinks())
        if (!notNative.contains(l.href) && !pageScreens.containsKey(l.href) && l.specKey == null) '${l.label} ${l.href}',
    ];
    expect(missing, isEmpty);
  });

  final seen = <String>{};
  for (final l in restaurantLinks()) {
    // Generated lists (Suppliers, Users & Permissions) have their own tests.
    if (notNative.contains(l.href) || !pageScreens.containsKey(l.href) || !seen.add(l.href)) continue;
    testWidgets('${l.label} (${l.href}) opens at 360 px with no data', (tester) async {
      final api = FakeApi();
      final s = await sessionFor(api);
      await open(tester, pageScreens[l.href]!(s, rest), size: const Size(360, 1400));
      expect(tester.takeException(), isNull, reason: l.href);
      final foreign = {
        for (final r in api.requests)
          if (RegExp(r'^/api/(Poultry|Water|Hotel|Generic|poultry)/').hasMatch(r.url.path) && !knownShared.contains(r.url.path)) r.url.path,
      };
      expect(foreign, isEmpty, reason: '${l.href} calls another company type');
    });
  }
}
