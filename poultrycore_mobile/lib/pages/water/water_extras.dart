import 'package:flutter/material.dart';

import '../../design/ui/inputs.dart';
import '../page_extras.dart';
import 'water_driver_employee_screen.dart';
import 'water_product_screens.dart';
import 'water_staff_form_screen.dart';

/// What the Water web pages offer beyond Add / Edit / Delete. Water's own —
/// nothing here is borrowed from Poultry.

final Map<String, List<ListExtra>> waterListExtras = {
  // app/water-drivers/page.tsx — "Existing employee" beside the main
  // "New employee & driver" button.
  'water-drivers': [
    ListExtra('Existing employee', Icons.person_add_alt, (s, c, rows) => WaterDriverEmployeeScreen(
          session: s, company: c, mode: WaterDriverMode.existing, drivers: rows)),
  ],
  // app/water-customers/page.tsx — migration 082: idempotently creates the
  // three system-managed customers (GeneralSales / GeneralDelivery /
  // GeneralCredit). Safe to re-run; existing ones are skipped.
  'water-customers': [
    ListExtra.action('Create default customers', Icons.group_add_outlined, (s, c) async {
      final res = await s.farmClient.post(
        '/api/Water/customers/create-defaults',
        query: {'farmId': c.farmId},
      );
      final rows = res is List ? res : const [];
      final created = [
        for (final r in rows)
          if (r is Map && r['wasCreated'] == true) '${r['name']}',
      ];
      return created.isEmpty
          ? 'All default customers already exist.'
          : 'Default customers created: ${created.join(', ')}';
    }),
  ],
};

final Map<String, List<RecordExtra>> waterRecordExtras = {
  // app/water-products/page.tsx — the card's "Go to Product Details" and
  // "Restock" buttons.
  'water-products': [
    RecordExtra('Go to Product Details', Icons.open_in_new,
        (s, c, row) => WaterProductDetailsScreen(
            session: s, company: c, productId: int.tryParse('${row['waterProductId']}') ?? 0)),
    RecordExtra('Restock', Icons.add_box_outlined,
        (s, c, row) => WaterProductStockScreen(session: s, company: c, product: row)),
  ],
};

final Map<String, List<ListFilter>> waterListFilters = {
  // app/water-staff/page.tsx — the "All roles" picker above the list.
  'water-staff': [
    ListFilter(
      key: 'role',
      label: 'Role',
      allLabel: 'All roles',
      options: (_, _, _) async => [
        for (final r in waterStaffRoles) AppSelectItem(value: r, label: r),
      ],
      matches: (row, v) => '${row['role']}' == v,
    ),
  ],
};

/// The web hides Delete on the system-generated customers.
final Map<String, DeleteGuard> waterDeleteGuards = {
  'water-customers': (row) => row['isSystemGenerated'] != true,
};
