import 'package:flutter/material.dart';

import '../../design/ui/buttons.dart';

/// RESTAURANT_ROLES and ROLE_PERMISSIONS from `app/restaurant-staff/page.tsx`.
class RestaurantRole {
  const RestaurantRole(this.value, this.label, this.description, this.icon, this.permissions);
  final String value;
  final String label;
  final String description;
  final String icon;
  final List<String> permissions;
}

const restaurantPermissionAreas = [
  'POS & Orders', 'Kitchen Display', 'Menu Management', 'Floor Plan', 'Reservations',
  'Online Ordering', 'Delivery', 'Staff & Roles', 'Setup', 'Reports',
];

const restaurantRoles = [
  RestaurantRole('Owner', 'Owner', 'Full access to everything', '👑', restaurantPermissionAreas),
  RestaurantRole('Manager', 'Manager', 'Manage staff, reports, settings, and daily operations', '🏢',
      restaurantPermissionAreas),
  RestaurantRole('HeadChef', 'Head Chef', 'Kitchen management, menu items, KDS', '👨‍🍳',
      ['Kitchen Display', 'Menu Management', 'POS & Orders']),
  RestaurantRole('Chef', 'Chef / Cook', 'Kitchen display, order prep', '🍳', ['Kitchen Display']),
  RestaurantRole('Waiter', 'Waiter / Server', 'POS, take orders, manage tables', '🍽️',
      ['POS & Orders', 'Floor Plan', 'Reservations']),
  RestaurantRole('Cashier', 'Cashier', 'POS, process payments', '💰', ['POS & Orders']),
  RestaurantRole('Host', 'Host / Hostess', 'Reservations, waitlist, seating', '🙋',
      ['Reservations', 'Floor Plan']),
  RestaurantRole('Bartender', 'Bartender', 'Bar orders, KDS bar station', '🍸',
      ['Kitchen Display', 'POS & Orders']),
  RestaurantRole('Driver', 'Delivery Driver', 'Delivery dispatch and tracking', '🛵', ['Delivery']),
  RestaurantRole('Other', 'Other', 'Custom role', '👤', []),
];

RestaurantRole roleFor(String value) =>
    restaurantRoles.firstWhere((r) => r.value == value, orElse: () => restaurantRoles.last);

/// The module's colour on the web: rose-600 buttons, rose-500 selection.
const restaurantRose = Color(0xFFE11D48);

/// Restaurant Staff → "Roles & permissions": every role, what it can reach,
/// and how many staff hold it — the web's role cards and their Permissions
/// dialog, on one screen. Read-only on the web too.
class RestaurantRolesScreen extends StatelessWidget {
  const RestaurantRolesScreen({super.key, required this.staff});

  final List<Map<String, dynamic>> staff;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Roles & permissions')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          for (final r in restaurantRoles) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(r.icon, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            Text(r.description,
                                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                          ],
                        ),
                      ),
                      Text(_members(r.value),
                          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final area in restaurantPermissionAreas)
                        _Chip(label: area, allowed: r.permissions.contains(area)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  String _members(String role) {
    final n = staff.where((s) => s['role'] == role).length;
    return '$n team member${n == 1 ? '' : 's'}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.allowed});
  final String label;
  final bool allowed;

  @override
  Widget build(BuildContext context) {
    final fg = allowed ? const Color(0xFF15803D) : const Color(0xFF9CA3AF); // green-700 / gray-400
    final bg = allowed ? const Color(0xFFF0FDF4) : const Color(0xFFF9FAFB); // green-50 / gray-50
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(allowed ? Icons.check_circle_outline : Icons.cancel_outlined, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: fg)),
        ],
      ),
    );
  }
}
