import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../page_extras.dart';
import 'batch_allocation_screen.dart';
import 'bulk_house_screen.dart';
import 'feed_formula_form_screen.dart';
import 'product_screens.dart';
import 'driver_employee_screen.dart';
import 'staff_attendance_screen.dart';
import 'trackers/egg_tracker_screen.dart';
import 'trackers/feed_inventory_tracker_screen.dart';
import 'trackers/tracker_logic.dart';

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

/// The sky "Default" badge after a default formula's name.
final Map<String, RowBadge> poultryRowBadges = {
  'poultry-feed-formulas': (row) => row['isDefault'] == true ? const _DefaultBadge() : null,
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

const _sky50 = Color(0xFFF0F9FF);
const _sky100 = Color(0xFFE0F2FE);
const _sky200 = Color(0xFFBAE6FD);
const _sky300 = Color(0xFF7DD3FC);
const _sky600 = Color(0xFF0284C7);
const _sky700 = Color(0xFF0369A1);
const _sky800 = Color(0xFF075985);
const _sky900 = Color(0xFF0C4A6E);

/// Panels above a list (ListBanner).
final Map<String, ListBanner> poultryListBanners = {
  'poultry-feed-formulas': (s, c, reload) => _FeedDefaultsBanner(session: s, company: c, reload: reload),
};

/// The defaults (385) are an example, not a rule -- the web says so where
/// they appear, with "Add missing defaults" for managers.
class _FeedDefaultsBanner extends StatefulWidget {
  const _FeedDefaultsBanner({required this.session, required this.company, required this.reload});
  final Session session;
  final Company company;
  final Future<void> Function() reload;

  @override
  State<_FeedDefaultsBanner> createState() => _FeedDefaultsBannerState();
}

class _FeedDefaultsBannerState extends State<_FeedDefaultsBanner> {
  bool _restoring = false;

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final (formulas, items) = await ensureDefaultFeedFormulas(widget.session, widget.company, force: true);
      messenger.showSnackBar(SnackBar(
        content: Text(formulas + items == 0
            ? 'Nothing to add. All the default formulas and feeds are already here.'
            : 'Default formulas added. $formulas formula${formulas == 1 ? '' : 's'} and $items feed item${items == 1 ? '' : 's'} added.'),
      ));
      await widget.reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not add the default formulas. ${e.message}')));
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const text = TextStyle(fontSize: 13, color: _sky900, height: 1.4);
    const bold = TextStyle(fontWeight: FontWeight.w700);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _sky50, border: Border.all(color: _sky200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.auto_awesome, size: 20, color: _sky600)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Default formulas to start with', style: text.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Starter, Grower, Developer and Layer formulas — each for '),
                  TextSpan(text: '1,000 kg (1 tonne)', style: bold),
                  TextSpan(text: ' of feed — are ready to use. This is one great example many farmers use. '
                      'To make 2 tonnes, every amount is simply doubled.'),
                ]),
                style: text,
              ),
              const SizedBox(height: 4),
              const Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Most farms have their own variation. '),
                  TextSpan(text: 'Copy', style: bold),
                  TextSpan(text: ' a default to make your own version, edit it, or create a new formula from scratch.'),
                ]),
                style: text,
              ),
            ]),
          ),
        ]),
        if (_canManage(widget.company)) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _sky800,
                side: const BorderSide(color: _sky300),
                overlayColor: _sky100,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _restoring ? null : _restore,
              icon: _restoring
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add, size: 16),
              label: const Text('Add missing defaults'),
            ),
          ),
        ],
      ]),
    );
  }
}
