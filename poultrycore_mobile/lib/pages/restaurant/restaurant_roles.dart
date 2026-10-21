import 'package:flutter/material.dart';


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
