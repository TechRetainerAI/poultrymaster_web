import 'package:flutter/material.dart';

import 'company.dart';

/// One destination in a company's navigation, mirroring the web's per-type nav.
class AppModule {
  const AppModule({
    required this.key,
    required this.label,
    required this.icon,
    this.ready = false,
  });

  final String key;
  final String label;
  final IconData icon;

  /// False until the module's screens are built; the UI marks these clearly
  /// rather than opening an empty page.
  final bool ready;
}

/// Colours for the bottom bar, copied from the web's `mobile-bottom-nav.tsx`.
///
/// The bar is a solid company-coloured surface — not a white bar with a tinted
/// accent. Inactive icons are the 100/90 tint of the same hue, the active one is
/// white, and it sits on a `bg-white/20` pill.
class NavTheme {
  const NavTheme({
    required this.bar,
    required this.borderTop,
    required this.inactive,
  });

  final Color bar;
  final Color borderTop;
  final Color inactive;

  static const _orange = NavTheme(
    bar: Color(0xFFF97316), // orange-500
    borderTop: Color(0xFFEA580C), // orange-600
    inactive: Color(0xE6FFEDD5), // orange-100 at 90%
  );
  static const _sky = NavTheme(
    bar: Color(0xFF0284C7), // sky-600
    borderTop: Color(0xFF0369A1), // sky-700
    inactive: Color(0xE6E0F2FE), // sky-100 at 90%
  );
  static const _emerald = NavTheme(
    bar: Color(0xFF059669), // emerald-600
    borderTop: Color(0xFF047857), // emerald-700
    inactive: Color(0xE6D1FAE5), // emerald-100 at 90%
  );
  static const _violet = NavTheme(
    bar: Color(0xFF7C3AED), // violet-600
    borderTop: Color(0xFF6D28D9), // violet-700
    inactive: Color(0xE6EDE9FE), // violet-100 at 90%
  );
  static const _rose = NavTheme(
    bar: Color(0xFFE11D48), // rose-600
    borderTop: Color(0xFFBE123C), // rose-700
    inactive: Color(0xE6FFE4E6), // rose-100 at 90%
  );

  static NavTheme forType(CompanyType type) => switch (type) {
        CompanyType.poultry => _orange,
        CompanyType.water => _sky,
        CompanyType.generic => _emerald,
        CompanyType.hotel => _violet,
        CompanyType.restaurant => _rose,
        // The web falls back to the Poultry bar during hydration.
        CompanyType.unknown => _orange,
      };
}

/// Navigation per company type.
///
/// The four main tabs are the web's, verbatim — not a set chosen here. The web
/// picked them deliberately ("a gym owner's thumb should not land on Products")
/// and changing them would mean a phone user learns different habits from the
/// same product on a laptop.
class Modules {
  const Modules._();

  // Poultry: Home, Flocks, Production, Sales
  static const _poultryMain = [
    AppModule(key: 'dashboard', label: 'Home', icon: Icons.home_outlined),
    AppModule(key: 'flocks', label: 'Flocks', icon: Icons.egg_outlined),
    AppModule(key: 'production-records', label: 'Production', icon: Icons.description_outlined),
    AppModule(key: 'sales', label: 'Sales', icon: Icons.shopping_cart_outlined),
  ];

  // Water: Home, Production, Deliveries, Sales
  static const _waterMain = [
    AppModule(key: 'water-dashboard', label: 'Home', icon: Icons.water_drop_outlined),
    AppModule(key: 'water-production-batches', label: 'Production', icon: Icons.factory_outlined),
    AppModule(key: 'water-driver-returns', label: 'Deliveries', icon: Icons.local_shipping_outlined),
    AppModule(key: 'water-sales', label: 'Sales', icon: Icons.shopping_cart_outlined),
  ];

  // Generic: Home + the business's own modules (the web varies these by
  // whether products are enabled; this takes the stocked-business set).
  static const _genericMain = [
    AppModule(key: 'generic-dashboard', label: 'Home', icon: Icons.home_outlined),
    AppModule(key: 'generic-sales', label: 'Sales', icon: Icons.shopping_cart_outlined),
    AppModule(key: 'generic-products', label: 'Products', icon: Icons.inventory_2_outlined),
    AppModule(key: 'generic-customers', label: 'Customers', icon: Icons.people_outline),
  ];

  // Hotel: Home, Bookings, Rooms, Guests
  static const _hotelMain = [
    AppModule(key: 'hotel-dashboard', label: 'Home', icon: Icons.home_outlined),
    AppModule(key: 'hotel-bookings', label: 'Bookings', icon: Icons.description_outlined),
    AppModule(key: 'hotel-rooms', label: 'Rooms', icon: Icons.meeting_room_outlined),
    AppModule(key: 'hotel-guests', label: 'Guests', icon: Icons.people_outline),
  ];

  // Restaurant: Home, POS, Orders, Kitchen
  static const _restaurantMain = [
    AppModule(key: 'restaurant-dashboard', label: 'Home', icon: Icons.home_outlined),
    AppModule(key: 'restaurant-pos', label: 'POS', icon: Icons.shopping_cart_outlined),
    AppModule(key: 'restaurant-orders', label: 'Orders', icon: Icons.description_outlined),
    AppModule(key: 'restaurant-kds', label: 'Kitchen', icon: Icons.factory_outlined),
  ];

  /// The four bottom-bar tabs. Index 0 is always Home (the dashboard).
  static List<AppModule> mainTabs(CompanyType type) => switch (type) {
        CompanyType.poultry => _poultryMain,
        CompanyType.water => _waterMain,
        CompanyType.generic => _genericMain,
        CompanyType.hotel => _hotelMain,
        CompanyType.restaurant => _restaurantMain,
        CompanyType.unknown => _poultryMain,
      };

  /// Everything behind "More", grouped as the web groups it.
  static List<ModuleGroup> moreGroups(CompanyType type) => switch (type) {
        CompanyType.poultry => const [
            ModuleGroup('Operations', [
              AppModule(key: 'egg-production', label: 'Egg production', icon: Icons.egg_outlined),
              AppModule(key: 'feed-tracker', label: 'Feed tracker', icon: Icons.grass_outlined),
              AppModule(key: 'raw-materials', label: 'Raw materials', icon: Icons.inventory_2_outlined),
              AppModule(key: 'medication', label: 'Medication', icon: Icons.medical_services_outlined),
            ]),
            ModuleGroup('Sales, Expenses & Money', [
              AppModule(key: 'cash', label: 'Cash', icon: Icons.account_balance_wallet_outlined),
              AppModule(key: 'expenses', label: 'Expenses', icon: Icons.receipt_long_outlined),
              AppModule(key: 'loans', label: 'Loans', icon: Icons.request_quote_outlined),
              AppModule(key: 'owner-money', label: 'Owner money', icon: Icons.savings_outlined),
              AppModule(key: 'employee-loans', label: 'Employee advances', icon: Icons.badge_outlined),
            ]),
            ModuleGroup('Analytics & Reports', [
              AppModule(key: 'financial-activity', label: 'Financial activity', icon: Icons.timeline_outlined),
              AppModule(key: 'profit-loss', label: 'Profit & loss', icon: Icons.insights_outlined),
              AppModule(key: 'assets', label: 'Capital assets', icon: Icons.precision_manufacturing_outlined),
              AppModule(key: 'reports', label: 'Reports', icon: Icons.assessment_outlined),
            ]),
          ],
        CompanyType.water => const [
            ModuleGroup('Operations', [
              AppModule(key: 'water-customers', label: 'Customers', icon: Icons.people_outline),
              AppModule(key: 'water-raw-materials', label: 'Raw materials', icon: Icons.inventory_2_outlined),
              AppModule(key: 'water-maintenance', label: 'Maintenance', icon: Icons.build_outlined),
            ]),
            ModuleGroup('Money', [
              AppModule(key: 'water-cash-accounts', label: 'Cash accounts', icon: Icons.account_balance_wallet_outlined),
              AppModule(key: 'water-expenses', label: 'Expenses', icon: Icons.receipt_long_outlined),
              AppModule(key: 'water-loans', label: 'Loans', icon: Icons.request_quote_outlined),
              AppModule(key: 'water-deferred-costs', label: 'Deferred costs', icon: Icons.timelapse_outlined),
            ]),
            ModuleGroup('People & Reports', [
              AppModule(key: 'water-staff', label: 'Staff', icon: Icons.badge_outlined),
              AppModule(key: 'water-payroll', label: 'Payroll', icon: Icons.payments_outlined),
              AppModule(key: 'water-reports', label: 'Reports', icon: Icons.assessment_outlined),
            ]),
          ],
        CompanyType.generic => const [
            ModuleGroup('Operations', [
              AppModule(key: 'generic-stock', label: 'Stock', icon: Icons.inventory_outlined),
              AppModule(key: 'generic-purchases', label: 'Purchases', icon: Icons.shopping_bag_outlined),
            ]),
            ModuleGroup('Money', [
              AppModule(key: 'generic-cash', label: 'Cash', icon: Icons.account_balance_wallet_outlined),
              AppModule(key: 'generic-expenses', label: 'Expenses', icon: Icons.receipt_long_outlined),
              AppModule(key: 'generic-subscriptions', label: 'Subscriptions', icon: Icons.card_membership_outlined),
            ]),
            ModuleGroup('Reports', [
              AppModule(key: 'generic-reports', label: 'Reports', icon: Icons.assessment_outlined),
            ]),
          ],
        CompanyType.hotel => const [
            ModuleGroup('Operations', [
              AppModule(key: 'hotel-frontdesk', label: 'Front desk', icon: Icons.login_outlined),
              AppModule(key: 'hotel-housekeeping', label: 'Housekeeping', icon: Icons.cleaning_services_outlined),
              AppModule(key: 'hotel-services', label: 'Services', icon: Icons.room_service_outlined),
            ]),
            ModuleGroup('Reports', [
              AppModule(key: 'hotel-reports', label: 'Reports', icon: Icons.assessment_outlined),
            ]),
          ],
        CompanyType.restaurant => const [
            ModuleGroup('Operations', [
              AppModule(key: 'restaurant-menu', label: 'Menu', icon: Icons.menu_book_outlined),
              AppModule(key: 'restaurant-reservations', label: 'Reservations', icon: Icons.event_seat_outlined),
              AppModule(key: 'restaurant-inventory', label: 'Inventory', icon: Icons.inventory_outlined),
              AppModule(key: 'restaurant-delivery', label: 'Delivery', icon: Icons.delivery_dining_outlined),
            ]),
            ModuleGroup('Customers', [
              AppModule(key: 'restaurant-crm', label: 'CRM', icon: Icons.people_outline),
              AppModule(key: 'restaurant-loyalty', label: 'Loyalty', icon: Icons.card_giftcard_outlined),
              AppModule(key: 'restaurant-feedback', label: 'Guest feedback', icon: Icons.reviews_outlined),
            ]),
            ModuleGroup('Reports', [
              AppModule(key: 'restaurant-reports', label: 'Reports', icon: Icons.assessment_outlined),
            ]),
          ],
        CompanyType.unknown => const [],
      };
}

class ModuleGroup {
  const ModuleGroup(this.title, this.items);
  final String title;
  final List<AppModule> items;
}
