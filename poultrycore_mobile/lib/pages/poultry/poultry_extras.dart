import 'package:flutter/material.dart';

import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../page_extras.dart';
import 'batch_allocation_screen.dart';
import 'bulk_house_screen.dart';
import 'feed_formula_form_screen.dart';
import '../../models/company.dart' show Company;
import '../../state/session.dart';
import '../lookup_loader.dart';
import 'delivery/fleet_validation.dart';
import 'flock_history.dart' show flockDeleteCheck, loadFlockEditContext;
import 'flock_type.dart';
import 'poultry_features.dart';
import 'product_screens.dart';
import 'driver_employee_screen.dart';
import 'staff_attendance_screen.dart';
import 'trackers/egg_tracker_screen.dart';
import 'trackers/feed_inventory_tracker_screen.dart';
import 'trackers/tracker_logic.dart';

import 'package:poultrycore_mobile/design/tone.dart';
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
  // app/egg-production/page.tsx — "For egg inventory and the ledger, open Egg tracker."
  'eggproduction': [
    ListExtra('Egg tracker', Icons.bar_chart, (s, c, rows) => EggTrackerScreen(session: s, company: c)),
  ],
};

/// Products that may not be deleted: 372's system products (Broken Eggs / Dead Birds).
final Map<String, bool Function(Map<String, dynamic> row)> poultryDeleteGuards = {
  'poultry-products': (row) => !isSystemProduct(row),
};

final Map<String, List<RecordExtra>> poultryRecordExtras = {
  // app/poultry-products/page.tsx — the row's Add stock and Recipe buttons.
  'poultry-products': [
    // 359: birds are adjusted per flock / batch on the Stock page; 372: system
    // products get their stock from production records.
    RecordExtra('Add stock', Icons.add_box_outlined,
        (s, c, row) => ProductStockScreen(session: s, company: c, product: row),
        when: (row) => !(row['isBirdProduct'] == true || row['name'] == 'Birds') && !isSystemProduct(row)),
    RecordExtra('Recipe', Icons.checklist,
        (s, c, row) => ProductRecipeScreen(session: s, company: c, product: row),
        when: (row) => row['requiresRecipeSetup'] == true && row['isRawEggProduct'] != true),
  ],
  // app/poultry-raw-materials/page.tsx — Track, on feed items only.
  'raw-materials': [
    RecordExtra('Track', Icons.history,
        (s, c, row) => FeedInventoryTrackerScreen(
            session: s, company: c, initialItemId: tIntOrNull(row['poultryRawMaterialItemId'])),
        when: (row) => feedItemKind(row['category']) != null),
  ],
  // app/poultry-feed-formulas/page.tsx — "Copy as my own formula": a new
  // formula started from this one, named "My <name>".
  'poultry-feed-formulas': [
    RecordExtra('Copy as my own formula', Icons.copy,
        (s, c, row) => FeedFormulaFormScreen(session: s, company: c, existing: row, asCopy: true)),
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
  // app/poultry-feed-formulas/page.tsx: the defaults are seeded once per farm
  // on the server; silent if it fails (staff, or 385 not applied).
  'poultry-feed-formulas': (s, c) async {
    if (_canManage(c)) await ensureDefaultFeedFormulas(s, c);
  },
};

bool _canManage(Company c) => (c.role ?? '').toLowerCase() != 'staff';

/// Flock Groups: a deleted flock can change which egg / broiler pages show.
final Map<String, AfterDelete> poultryAfterDelete = {
  'flocks': (s, c) => loadPoultryFeatures(s, c, force: true),
};

/// The sky "Default" badge after a default formula's name, and the
/// Broiler badge on Flock Groups.
final Map<String, RowBadge> poultryRowBadges = {
  'poultry-feed-formulas': (row) => row['isDefault'] == true ? const _DefaultBadge() : null,
  // Flock Groups: a broiler flock's name carries the orange badge (399).
  'flocks': (row) => isBroilerFlock(row) ? const BroilerBadge() : null,
};

class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: _sky50,
          border: Border.all(color: _sky300),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text('Default', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _sky700)),
      );
}

const _sky50 = Tone.bg(0xFFF0F9FF);
const _sky300 = Tone.line(0xFF7DD3FC);
const _sky700 = Tone.fg(0xFF0369A1);

/// Panels above a list (ListBanner). Feed Formulas' "Default formulas to
/// start with" panel went with the 9 Nov pull: its Add missing defaults is a
/// task on FeedFormulasScreen now.
final Map<String, ListBanner> poultryListBanners = {};

/// Flock Groups (414): say up front whether a flock can be deleted, and why not.
final Map<String, DeleteCheck> poultryDeleteChecks = {
  'flocks': (s, c, row) async => flockDeleteCheck(await loadFlockEditContext(s, c, _int(row['flockId']))),
};

/// Flock Groups: only what the server confirmed it did.
final Map<String, DeletedMessage> poultryDeletedMessages = {
  'flocks': (res) {
    final released = res is Map ? _int(res['birdsReleased']) : 0;
    final msg = res is Map && '${res['message'] ?? ''}'.isNotEmpty
        ? '${res['message']}'
        : released > 0
            ? 'Flock deleted. Its ${loc(released)} birds are back in the batch, available to place again.'
            : 'Flock deleted successfully';
    return 'Flock deleted — $msg';
  },
};

// ---- Vehicles, Drivers, Routes (A5, 9 Nov pull): the web's fleet-validation.ts

Future<List<Map>> _fleetRows(Session s, Company c, String path) async {
  try {
    return [for (final r in LookupLoader.rowsIn(await s.farmClient.get(path, query: {'farmId': c.farmId}))) if (r is Map) r];
  } catch (_) {
    return const [];
  }
}

/// Checked before the save is sent, in the order the form shows its fields.
final Map<String, FormCheck> poultryFormChecks = {
  'poultry-vehicles': (s, c, body, existing) async {
    final p = validateVehicle(body, await _fleetRows(s, c, '/api/Poultry/vehicles'), id: _int(existing?['poultryVehicleId']));
    return p == null ? null : (title: 'Check the vehicle details', problem: p);
  },
  'poultry-drivers': (s, c, body, existing) async {
    final r = await Future.wait([_fleetRows(s, c, '/api/Poultry/drivers/list-for-farm'), _fleetRows(s, c, '/api/Poultry/vehicles')]);
    final p = validateDriver(body, others: r[0], vehicleCount: r[1].length, id: _int(existing?['poultryDriverId']));
    return p == null ? null : (title: 'Check the driver details', problem: p);
  },
  'poultry-routes': (s, c, body, existing) async {
    final r = await Future.wait([_fleetRows(s, c, '/api/Poultry/routes'), _fleetRows(s, c, '/api/Poultry/vehicles')]);
    final p = validateRoute(body, others: r[0], vehicles: r[1], id: _int(existing?['poultryRouteId']));
    return p == null ? null : (title: 'Check the route details', problem: p);
  },
};

/// Vehicles: only the fuels the chosen type can use.
final Map<String, DependentOptions> poultryDependentOptions = {
  'poultry-vehicles.fuelType': (selects) => fuelsFor(selects['vehicleType'] ?? 'Truck'),
};
