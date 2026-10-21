// lib/nav/setup-admin-routes.ts: Setup (company master data) is for the
// account owner and employees granted admin, not ordinary employees. The web
// drops these rows from every menu for anyone else, and SetupAccessGuard sends
// a direct visit back to the dashboard; the Farm API refuses the writes too.
//
// Deliberately NOT here, because they are daily work: flocks, stock movements,
// raw-material items, Staff and Users & Permissions (they keep their own gates).

import '../../models/company.dart';
import '../web_nav.dart';

const setupAdminRoutes = [
  // Poultry
  '/poultry-setup', '/poultry-company-setup', '/poultry-financial-settings', '/poultry-farm-setup',
  '/poultry-drivers', '/poultry-vehicles', '/poultry-routes',
  '/poultry-products', '/poultry-feed-formulas', '/poultry-egg-sorting-settings', '/business-office/egg-pick-settings',
  '/customers', '/suppliers', '/houses',
  // Water
  '/water-setup', '/water-company-setup', '/water-financial-settings',
  '/water-drivers', '/water-vehicles', '/water-routes',
  '/water-products', '/water-machines', '/water-boreholes',
  '/water-customers', '/water-suppliers',
  // Generic
  '/generic-setup', '/generic-settings',
  // Hotel
  '/hotel-company-setup', '/hotel-setup', '/hotel-customers', '/hotel-suppliers',
  // Restaurant
  '/restaurant-setup', '/restaurant-menu', '/restaurant-suppliers',
];

/// isSetupAdminRoute: a Setup page or anything under it (/water-products/12).
/// The query string is ignored.
bool isSetupAdminRoute(String? href) {
  if (href == null || href.isEmpty) return false;
  final path = href.split('?').first;
  return setupAdminRoutes.any((r) => path == r || path.startsWith('$r/'));
}

/// permissions.isAdmin, as the app reads it everywhere: anyone not Staff.
bool canOpenSetup(Company company) => (company.role ?? '').toLowerCase() != 'staff';

/// The menu as this user sees it: Setup rows dropped for an ordinary
/// employee, and any section left empty dropped with them.
List<NavGroup> gateSetupLinks(List<NavGroup> groups, Company company) {
  if (canOpenSetup(company)) return groups;
  return [
    for (final g in groups)
      if (_gated(g) case final kept? when kept.subGroups.isNotEmpty) kept,
  ];
}

NavGroup? _gated(NavGroup g) => NavGroup(g.title, [
      for (final s in g.subGroups)
        if (s.links.where((l) => !isSetupAdminRoute(l.href)).toList() case final links when links.isNotEmpty)
          NavSubGroup(s.title, links),
    ]);
