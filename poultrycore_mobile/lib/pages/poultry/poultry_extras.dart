import 'package:flutter/material.dart';

import '../../design/ui/inputs.dart';
import '../page_extras.dart';
import 'batch_allocation_screen.dart';
import 'bulk_house_screen.dart';
import 'product_screens.dart';
import 'driver_employee_screen.dart';
import 'staff_attendance_screen.dart';

/// What the Poultry web pages offer beyond Add / Edit / Delete.

final Map<String, List<ListExtra>> poultryListExtras = {
  // app/poultry-drivers/page.tsx — "Existing employee" beside the main
  // "New employee & driver" button.
  'poultry-drivers': [
    ListExtra('Existing employee', Icons.person_add_alt, (s, c, rows) => DriverEmployeeScreen(
          session: s, company: c, mode: DriverEmployeeMode.existing, drivers: rows)),
  ],
  // app/houses/page.tsx
  'house': [
    ListExtra('Add Multiple Houses/Pens', Icons.home_work_outlined, (s, c, rows) => BulkHouseScreen(
          session: s,
          company: c,
          existingNames: [for (final r in rows) '${r['houseName'] ?? r['name'] ?? ''}'],
        )),
  ],
  // app/flocks/page.tsx — the same allocation tool as Flock Purchases.
  'flocks': [
    ListExtra('Add Multiple Flocks', Icons.call_split,
        (s, c, rows) => BatchAllocationScreen(session: s, company: c, flocks: rows)),
  ],
};

final Map<String, List<RecordExtra>> poultryRecordExtras = {
  // app/poultry-products/page.tsx — the row's Add stock and Recipe buttons.
  'poultry-products': [
    RecordExtra('Add stock', Icons.add_box_outlined,
        (s, c, row) => ProductStockScreen(session: s, company: c, product: row)),
    RecordExtra('Recipe', Icons.checklist,
        (s, c, row) => ProductRecipeScreen(session: s, company: c, product: row),
        when: (row) => row['requiresRecipeSetup'] == true && row['isRawEggProduct'] != true),
  ],
  // app/poultry-staff/page.tsx — the row's "Attendance" button.
  'poultry-staff': [
    RecordExtra('Attendance', Icons.event_available_outlined,
        (s, c, row) => StaffAttendanceScreen(session: s, company: c, staff: row)),
  ],
};

int _int(Object? v) => int.tryParse('${v ?? ''}') ?? 0;

/// getFlockLifecycleStatus, for the Status filter: a closed flock is also
/// inactive, so closed is checked first.
String _flockStatus(Map<String, dynamic> f) {
  final closed = f['closedDate'] ?? f['closedAt'];
  if (closed != null && '$closed'.isNotEmpty) return 'closed';
  return f['active'] == true ? 'active' : 'inactive';
}

final Map<String, List<ListFilter>> poultryListFilters = {
  // app/flocks/page.tsx — Status, House and Batch.
  'flocks': [
    ListFilter(
      key: 'status',
      label: 'Status',
      allLabel: 'All Statuses',
      options: (_, _, _) async => const [
        AppSelectItem(value: 'active', label: 'Active'),
        AppSelectItem(value: 'inactive', label: 'Inactive'),
        AppSelectItem(value: 'closed', label: 'Closed'),
      ],
      matches: (row, v) => _flockStatus(row) == v,
    ),
    ListFilter(
      key: 'house',
      label: 'House',
      allLabel: 'All Houses',
      options: (s, c, _) async => [
        for (final h in await fetchRows(s, c, '/api/House'))
          if (_int(h['houseId']) > 0)
            AppSelectItem(
              value: '${h['houseId']}',
              label: '${h['houseName'] ?? h['name'] ?? 'House ${h['houseId']}'}',
            ),
      ],
      matches: (row, v) => '${row['houseId']}' == v,
    ),
    ListFilter(
      key: 'batch',
      label: 'Batch',
      allLabel: 'All Batches',
      options: (s, c, _) async => [
        for (final b in await fetchRows(s, c, '/api/MainFlockBatch'))
          if (_int(b['batchId']) > 0)
            AppSelectItem(value: '${b['batchId']}', label: '${b['batchName'] ?? b['batchId']}'),
      ],
      matches: (row, v) => '${row['batchId']}' == v,
    ),
  ],
};

final Map<String, BeforeLoad> poultryBeforeLoad = {
  'poultry-products': (s, c) => s.farmClient.post(
        '/api/Poultry/products/ensure-defaults',
        query: {'farmId': c.farmId},
      ),
};
