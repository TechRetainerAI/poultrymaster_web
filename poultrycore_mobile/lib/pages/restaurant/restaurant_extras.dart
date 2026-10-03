import 'package:flutter/material.dart';

import '../../design/ui/inputs.dart';
import '../page_extras.dart';
import 'restaurant_roles.dart';

/// What the Restaurant web pages offer beyond Add / Edit / Delete.

final Map<String, List<ListExtra>> restaurantListExtras = {
  // app/restaurant-staff/page.tsx — the role cards and their Permissions view.
  'restaurant-staff': [
    ListExtra('Roles & permissions', Icons.admin_panel_settings_outlined,
        (_, _, rows) => RestaurantRolesScreen(staff: rows)),
  ],
};

final Map<String, List<RecordExtra>> restaurantRecordExtras = {};

/// SEGMENTS in app/restaurant-crm/page.tsx.
const restaurantSegments = ['New', 'Regular', 'VIP', 'Lapsed'];

final Map<String, List<ListFilter>> restaurantListFilters = {
  // The "All Roles" picker above the staff list.
  'restaurant-staff': [
    ListFilter(
      key: 'role',
      label: 'Role',
      allLabel: 'All Roles',
      options: (_, _, _) async => [
        for (final r in restaurantRoles) AppSelectItem(value: r.value, label: '${r.icon} ${r.label}'),
      ],
      matches: (row, v) => '${row['role']}' == v,
    ),
  ],
  // The "All Segments" picker above the customer list.
  'restaurant-crm-customers': [
    ListFilter(
      key: 'segment',
      label: 'Segment',
      allLabel: 'All Segments',
      options: (_, _, _) async => [
        for (final s in restaurantSegments) AppSelectItem(value: s, label: s),
      ],
      matches: (row, v) => '${row['segment']}' == v,
    ),
  ],
};

final Map<String, DeleteGuard> restaurantDeleteGuards = {};
