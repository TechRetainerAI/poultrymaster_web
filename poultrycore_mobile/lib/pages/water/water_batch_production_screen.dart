import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/expenses/deferred_costs_screen.dart' show qtyFmt;
import '../poultry/money/money_widgets.dart';
import '../poultry/production/batch_production_logic.dart' show distributeInteger, distributeDecimal;
import '../poultry/reports/report_format.dart';
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import 'water_production_screen.dart' show WaterProductionDetailScreen, waterShifts;

/// Water → Operations → Production → Batch Production, as
/// `app/water-daily-production/` (migration 193 — "WaterDailyProduction" in
/// the DB/API): the list with its Post / Repost / Reverse / Delete
/// confirmations, the Log / Edit form (`components/water/daily-production-form.tsx`),
/// the record page, and the allocation workspace that splits the day across
/// machines (`lib/utils/water-daily-allocation.ts`).

const waterDailyStatusLabels = {
  'Draft': 'Draft',
  'PendingAllocation': 'Pending Allocation',
  'Allocated': 'Allocated',
  'Posted': 'Posted',
  'Reversed': 'Reversed',
  'Cancelled': 'Cancelled',
};

String _today() => DateTime.now().toUtc().toIso8601String().substring(0, 10);
String _day10(Object? v) => tStr(v).length >= 10 ? tStr(v).substring(0, 10) : tStr(v);

/// "All active machines" / "Machine A, Machine B +2 more".
String waterMachineScopeLabel(Map d) {
  if (tStr(d['machineSelectionType']) == 'AllMachines') return 'All active machines';
  final names = [for (final m in rowsOf(d['machines'])) if (tStr(m['machineName']).isNotEmpty) tStr(m['machineName'])];
  if (names.isEmpty) return '${tNum(d['machineCount'])} machine(s)';
  return names.length <= 2 ? names.join(', ') : '${names.take(2).join(', ')} +${names.length - 2} more';
}

Widget waterDailyStatusBadge(Object? status) {
  final s = tStr(status);
  final (bg, fg) = switch (s) {
    'PendingAllocation' => (TColors.amber100, TColors.amber800),
    'Allocated' => (TColors.blue100, const Color(0xFF1D4ED8)),
    'Posted' => (TColors.emerald100, TColors.emerald700),
    'Reversed' => (const Color(0xFFF3E8FF), const Color(0xFF7E22CE)),
    'Cancelled' => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
    _ => (TColors.slate100, TColors.slate700),
  };
  return TBadge(waterDailyStatusLabels[s] ?? s, bg: bg, fg: fg);
}

/// filterByDateAndSearch on productionDate (document number, product, notes), then the status.
List<Map> filterWaterDaily(List<Map> rows, {String search = '', String from = '', String to = '', String status = 'all'}) {
  final q = search.trim().toLowerCase();
  return rows.where((r) {
    final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r['productionDate']))?[1];
    if (day != null) {
      if (from.isNotEmpty && day.compareTo(from) < 0) return false;
      if (to.isNotEmpty && day.compareTo(to) > 0) return false;
    }
    if (q.isNotEmpty && !['productionNumber', 'productName', 'notes'].any((k) => r[k] != null && '${r[k]}'.toLowerCase().contains(q))) return false;
    return status == 'all' || tStr(r['status']) == status;
  }).toList();
}

// ------------------------------------------------------------ allocation maths

/// The split methods (`METHODS`).
const waterAllocMethods = [
  ('Manual', 'Manual', "Type every machine's numbers yourself."),
  ('ByMachineCapacity', 'By machine capacity', "Split in proportion to each machine's bags-per-hour rating."),
  ('ByPreviousProduction', 'By recent output', 'Split by what each machine actually produced recently; falls back to capacity.'),
  ('EqualSplit', 'Equal split', 'Divide the batch evenly across every machine.'),
];

/// The grid's whole-number and money fields, in column order.
const waterAllocIntFields = ['bagsProduced', 'looseSachetsProduced', 'rejectedSachets', 'damagedBags', 'packagingRollsUsed', 'estimatedWaterUsedLitres'];
const waterAllocMoneyFields = ['electricityCost', 'fuelCost', 'laborCost', 'otherProductionCost'];

/// One machine's share of the day (`AllocRow`).
class WaterAllocRow {
  WaterAllocRow({
    required this.machineId,
    required this.machineName,
    this.capacity = 0,
    this.shift,
    this.operatorStaffId,
    Map<String, num>? values,
    Map<int, num>? materialQty,
    this.notes = '',
    this.generatedBatchNumber,
  })  : values = values ?? {for (final f in [...waterAllocIntFields, ...waterAllocMoneyFields]) f: 0},
        materialQty = materialQty ?? {};
  final int machineId;
  final String machineName;
  final num capacity;
  final String? shift;
  final int? operatorStaffId;
  final Map<String, num> values;
  final Map<int, num> materialQty;
  final String notes;
  final String? generatedBatchNumber;

  num v(String f) => values[f] ?? 0;
}

WaterAllocRow waterBlankRow(Map m) => WaterAllocRow(
      machineId: tIntOrNull(m['waterMachineId']) ?? 0,
      machineName: tStr(m['machineName']).isNotEmpty ? tStr(m['machineName']) : 'Machine #${tStr(m['waterMachineId'])}',
      capacity: tNum(m['capacityPerHour']),
      operatorStaffId: tIntOrNull(m['operatorStaffId']),
    );

/// Hydrate the grid from the allocation rows already saved on the record.
List<WaterAllocRow> waterAllocationsToRows(List<Map> allocations, List<Map> machines) {
  final cap = {for (final m in machines) tIntOrNull(m['waterMachineId']): tNum(m['capacityPerHour'])};
  return [
    for (final a in allocations)
      WaterAllocRow(
        machineId: tIntOrNull(a['waterMachineId']) ?? 0,
        machineName: tStr(a['machineName']).isNotEmpty ? tStr(a['machineName']) : 'Machine #${tStr(a['waterMachineId'])}',
        capacity: cap[tIntOrNull(a['waterMachineId'])] ?? 0,
        shift: tStr(a['shift']).isEmpty ? null : tStr(a['shift']),
        operatorStaffId: tIntOrNull(a['operatorStaffId']),
        values: {for (final f in [...waterAllocIntFields, ...waterAllocMoneyFields]) f: tNum(a[f])},
        materialQty: {for (final m in rowsOf(a['materials'])) tIntOrNull(m['waterRawMaterialItemId']) ?? 0: tNum(m['quantityAllocated'])},
        notes: tStr(a['notes']),
        generatedBatchNumber: tStr(a['generatedBatchNumber']).isEmpty ? null : tStr(a['generatedBatchNumber']),
      ),
  ];
}

List<num> waterWeightsForMethod(String method, List<WaterAllocRow> rows, [Map<int, num>? history]) {
  if (method == 'EqualSplit') return [for (final _ in rows) 1];
  if (method == 'ByMachineCapacity') {
    final w = [for (final r in rows) r.capacity];
    return w.any((x) => x > 0) ? w : [for (final _ in rows) 1];
  }
  if (method == 'ByPreviousProduction') {
    final w = [for (final r in rows) history?[r.machineId] ?? 0];
    if (w.any((x) => x > 0)) return w;
    // No history yet — fall back to capacity rather than silently going equal.
    return waterWeightsForMethod('ByMachineCapacity', rows);
  }
  return [for (final _ in rows) 1];
}

/// Distribute the day's totals across the rows. Manual leaves the grid alone.
List<WaterAllocRow> waterApplyMethod(String method, List<WaterAllocRow> rows, Map day, [Map<int, num>? history]) {
  if (method == 'Manual' || rows.isEmpty) return rows;
  final w = waterWeightsForMethod(method, rows, history);
  final parts = <String, List<num>>{
    for (final f in waterAllocIntFields) f: distributeInteger(tNum(day[f]), w),
    // dp 2: the server gates these buckets at 0.01.
    for (final f in waterAllocMoneyFields) f: distributeDecimal(tNum(day[f]), w, 2),
  };
  final perMaterial = {
    for (final m in rowsOf(day['materials'])) tIntOrNull(m['waterRawMaterialItemId']) ?? 0: distributeDecimal(tNum(m['quantityUsed']), w, 3),
  };
  return [
    for (var i = 0; i < rows.length; i++)
      WaterAllocRow(
        machineId: rows[i].machineId,
        machineName: rows[i].machineName,
        capacity: rows[i].capacity,
        shift: rows[i].shift,
        operatorStaffId: rows[i].operatorStaffId,
        values: {for (final e in parts.entries) e.key: e.value[i]},
        materialQty: {for (final e in perMaterial.entries) e.key: e.value[i]},
        notes: rows[i].notes,
        generatedBatchNumber: rows[i].generatedBatchNumber,
      ),
  ];
}

num waterRowGoodBags(WaterAllocRow r) => (r.v('bagsProduced') - r.v('damagedBags')).clamp(0, double.infinity);
num waterRowTotalSachets(WaterAllocRow r, num perBag) => r.v('bagsProduced') * perBag + r.v('looseSachetsProduced');
num waterRowProductionCost(WaterAllocRow r) => waterAllocMoneyFields.fold<num>(0, (s, f) => s + r.v(f));

/// Preview material cost; re-priced from the lots at posting.
num waterRowMaterialCost(WaterAllocRow r, Map day) =>
    rowsOf(day['materials']).fold<num>(0, (s, m) => s + (r.materialQty[tIntOrNull(m['waterRawMaterialItemId'])] ?? 0) * tNum(m['unitCost']));

num waterRowAllInCost(WaterAllocRow r, Map day) => waterRowProductionCost(r) + waterRowMaterialCost(r, day);

num waterRowCostPerBag(WaterAllocRow r, Map day) {
  final good = waterRowGoodBags(r);
  return good > 0 ? waterRowAllInCost(r, day) / good : 0;
}

/// SUM(allIn) / SUM(goodBags) — never the mean of the rows.
num waterDayCostPerBag(List<WaterAllocRow> rows, Map day) {
  final good = rows.fold<num>(0, (s, r) => s + waterRowGoodBags(r));
  return good <= 0 ? 0 : rows.fold<num>(0, (s, r) => s + waterRowAllInCost(r, day)) / good;
}

/// Per-row problems the server would reject, surfaced inline.
List<String> waterRowErrors(WaterAllocRow r, num perBag) => [
      if (['bagsProduced', 'damagedBags', 'rejectedSachets', 'looseSachetsProduced'].any((f) => r.v(f) < 0)) 'Quantities cannot be negative',
      if (r.v('damagedBags') > r.v('bagsProduced')) 'Damaged bags exceed bags produced',
      if (r.v('rejectedSachets') > waterRowTotalSachets(r, perBag)) 'Rejected sachets exceed sachets produced',
    ];

/// A reconciliation line (`ReconLine`).
class WaterReconLine {
  const WaterReconLine(this.key, this.label, this.dayTotal, this.allocated, this.balanced, {this.info = false, this.decimals, this.money = false});
  final String key, label;
  final num dayTotal, allocated;
  final bool balanced, info, money;
  final int? decimals;
  num get diff => allocated - dayTotal;
}

/// Output AND cost-bucket lines block posting; material cost is informational.
({List<WaterReconLine> lines, bool balanced}) waterBuildReconciliation(List<WaterAllocRow> rows, Map day) {
  num sum(num Function(WaterAllocRow) f) => rows.fold<num>(0, (s, r) => s + f(r));
  final lines = <WaterReconLine>[];
  void push(String key, String label, num dayTotal, num allocated, num tol, {bool info = false, int? decimals, bool money = false}) =>
      lines.add(WaterReconLine(key, label, dayTotal, allocated, (allocated - dayTotal).abs() <= tol + 1e-9,
          info: info, decimals: decimals, money: money));
  const labels = {
    'bagsProduced': ('bags', 'Bags Produced'),
    'looseSachetsProduced': ('loose', 'Loose Sachets'),
    'rejectedSachets': ('rejected', 'Rejected Sachets'),
    'damagedBags': ('damaged', 'Damaged Bags'),
    'packagingRollsUsed': ('rolls', 'Packaging Rolls'),
  };
  for (final e in labels.entries) {
    push(e.value.$1, e.value.$2, tNum(day[e.key]), sum((r) => r.v(e.key)), 0);
  }
  // The server skips this line when the header leaves litres blank.
  if (day['estimatedWaterUsedLitres'] != null) {
    push('litres', 'Water Used (L)', tNum(day['estimatedWaterUsedLitres']), sum((r) => r.v('estimatedWaterUsedLitres')), 0);
  }
  const money = {'electricityCost': ('elec', 'Electricity'), 'fuelCost': ('fuel', 'Fuel'), 'laborCost': ('labor', 'Labor'),
    'otherProductionCost': ('other', 'Other Production Cost')};
  for (final e in money.entries) {
    push(e.value.$1, e.value.$2, tNum(day[e.key]), sum((r) => r.v(e.key)), 0.01, money: true);
  }
  for (final m in rowsOf(day['materials'])) {
    final id = tIntOrNull(m['waterRawMaterialItemId']) ?? 0;
    push('mat-$id', '${tStr(m['itemName']).isEmpty ? 'Material' : tStr(m['itemName'])}${tStr(m['unitOfMeasure']).isNotEmpty ? ' (${tStr(m['unitOfMeasure'])})' : ''}',
        tNum(m['quantityUsed']), sum((r) => r.materialQty[id] ?? 0), 0.001, decimals: 3);
  }
  push('matCost', 'Raw Material Cost', tNum(day['rawMaterialCost']), sum((r) => waterRowMaterialCost(r, day)), 0.01, money: true, info: true);
  return (lines: lines, balanced: lines.where((l) => !l.info).every((l) => l.balanced));
}

/// The payload the save / post endpoints expect.
List<Map<String, Object?>> waterRowsToAllocations(List<WaterAllocRow> rows, Map day, String method) {
  final meta = {for (final m in rowsOf(day['materials'])) tIntOrNull(m['waterRawMaterialItemId']) ?? 0: m};
  num perBag(int id) => tNum(day['bagsProduced']) > 0 ? tNum(meta[id]?['expectedQuantityUsed']) / tNum(day['bagsProduced']) : 0;
  return [
    for (final r in rows)
      {
        'waterMachineId': r.machineId,
        'machineName': r.machineName,
        'allocationMethod': method,
        'shift': r.shift,
        'operatorStaffId': r.operatorStaffId,
        for (final f in [...waterAllocIntFields, ...waterAllocMoneyFields]) f: r.v(f),
        'rawMaterialCost': waterRowMaterialCost(r, day),
        'notes': r.notes.isEmpty ? null : r.notes,
        'materials': [
          for (final e in r.materialQty.entries)
            if (e.value > 0)
              {
                'waterDailyProductionMaterialId': tIntOrNull(meta[e.key]?['waterDailyProductionMaterialId']),
                'waterRawMaterialItemId': e.key,
                'itemName': meta[e.key]?['itemName'],
                'quantityAllocated': e.value,
                // Recomputed per row from the recipe rate, not distributed by weight.
                'expectedQuantityAllocated': num.parse((perBag(e.key) * r.v('bagsProduced')).toStringAsFixed(3)),
                'unitCost': meta[e.key]?['unitCost'],
              },
        ],
      },
  ];
}

// ------------------------------------------------------------ list

class WaterBatchProductionScreen extends StatefulWidget {
  const WaterBatchProductionScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterBatchProductionScreen> createState() => _WaterBatchProductionScreenState();
}

class _WaterBatchProductionScreenState extends State<WaterBatchProductionScreen> {
  List<Map> _rows = [];
  bool _loading = true;
  final _search = TextEditingController();
  String _from = '', _to = '', _status = 'all';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _user => widget.session.tokens.userId ?? '';

  /// The web gates Delete on canDelete; the app has no permission flags, so
  /// the Staff role is the one left out.
  bool get _canDelete => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = rowsOf(await _api.get('/api/Water/daily-productions', query: {'farmId': _farmId}));
      if (mounted) setState(() => _rows = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load batch production', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _id(Map r) => tIntOrNull(r['waterDailyProductionId']) ?? 0;

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _load();
  }

  Future<void> _confirm(String type, Map r, String title, String description, String label, {bool destructive = false}) async {
    var busy = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: destructive ? FilledButton.styleFrom(backgroundColor: TColors.red600) : null,
              onPressed: busy
                  ? null
                  : () async {
                      set(() => busy = true);
                      final done = await _run(type, _id(r), label);
                      if (ctx.mounted) Navigator.pop(ctx, done);
                    },
              child: Text(busy ? 'Working…' : label),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await _load();
  }

  Future<bool> _run(String type, int id, String label) async {
    final base = '/api/Water/daily-productions/$id';
    try {
      switch (type) {
        case 'delete':
          await _api.delete(base, query: {'farmId': _farmId, 'userId': _user});
        case 'post':
        case 'repost':
          await _api.post('$base/post', query: {'farmId': _farmId, 'postedBy': _user});
        case 'reverse':
          await _api.post('$base/reverse', query: {'farmId': _farmId, 'reversedBy': _user});
      }
      if (mounted) trackerToast(context, '$label done');
      return true;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, '$label failed', description: e.message, error: true);
      return false;
    }
  }

  List<Widget> _actions(Map r) {
    final id = _id(r);
    final s = widget.session, c = widget.company;
    final view = IconButton(
      tooltip: 'View',
      onPressed: () => _go(WaterBatchProductionDetailScreen(session: s, company: c, id: id)),
      icon: const Icon(Icons.visibility_outlined, size: 18),
    );
    final edit = IconButton(
      tooltip: 'Edit',
      onPressed: () => _go(WaterBatchProductionFormScreen(session: s, company: c, editId: id)),
      icon: const Icon(Icons.edit_outlined, size: 18),
    );
    final allocate = IconButton(
      tooltip: 'Allocate across machines',
      onPressed: () => _go(WaterBatchAllocateScreen(session: s, company: c, id: id)),
      icon: const Icon(Icons.layers_outlined, size: 18, color: Color(0xFF2563EB)),
    );
    final del = IconButton(
      tooltip: 'Delete',
      onPressed: () => _confirm('delete', r, 'Delete this batch production record?',
          "The day's totals, machine list and allocation will be removed. This cannot be undone.", 'Delete', destructive: true),
      icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
    );
    final post = IconButton(
      tooltip: 'Post',
      onPressed: () => _confirm('post', r, "Post this day's production?",
          'One production record is created and approved per machine. Finished goods, raw material lots, expenses and losses are all updated.', 'Post'),
      icon: const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF059669)),
    );
    final repost = IconButton(
      tooltip: 'Repost',
      onPressed: () => _confirm('repost', r, "Repost this day's production?",
          'Fresh production records are created and approved for each machine, at a new posting version.', 'Repost'),
      icon: const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF059669)),
    );
    final reverse = IconButton(
      tooltip: 'Reverse',
      onPressed: () => _confirm('reverse', r, "Reverse this day's production?",
          "Each machine's production record is reopened and cancelled: finished goods come back out of stock, raw material lots are restored, linked expenses are cancelled. The day stays available to re-allocate and repost.",
          'Reverse', destructive: true),
      icon: const Icon(Icons.undo, size: 18, color: Color(0xFF9333EA)),
    );
    final d = _canDelete ? del : null;
    return [
      ...switch (tStr(r['status'])) {
        'Draft' => [edit, ?d],
        'PendingAllocation' => [edit, allocate, ?d],
        'Allocated' => [allocate, post, ?d],
        'Posted' => [view, reverse],
        'Reversed' => [view, allocate, repost, ?d],
        _ => [view],
      },
    ];
  }

  Widget _score(String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: TColors.slate900)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-daily-production');
    if (_loading && _rows.isEmpty) {
      return Scaffold(
        appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Batch production')),
        body: const Padding(padding: EdgeInsets.all(24), child: LoadingLine('Loading batch production…')),
      );
    }
    final filtered = filterWaterDaily(_rows, search: _search.text, from: _from, to: _to, status: _status);
    if (filtered.length != _lastTotal) {
      _lastTotal = filtered.length;
      _page = 1;
    }
    final pageRows = pageSlice(filtered, _page, _pageSize);
    num sum(String k) => filtered.fold<num>(0, (s, r) => s + tNum(r[k]));
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Batch production')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.calendar_month_outlined, color: Color(0xFF0284C7)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Batch production', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
                  Text("Record the day's totals, then split them across the machines that produced them.",
                      style: TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _go(WaterBatchProductionFormScreen(session: widget.session, company: widget.company)),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Log batch production'),
              ),
            ),
            const SizedBox(height: 12),
            twoUp([
              _score('Days', qtyFmt(filtered.length)),
              _score('Bags produced', qtyFmt(sum('bagsProduced'))),
              _score('Good bags', qtyFmt(sum('goodBags'))),
              _score('Pending allocation', qtyFmt(filtered.where((r) => tStr(r['status']) == 'PendingAllocation').length)),
              _score('Posted', qtyFmt(filtered.where((r) => tStr(r['status']) == 'Posted').length)),
            ]),
            const SizedBox(height: 12),
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search by document number, product or notes',
              onSearch: () => setState(() {}),
              from: _from,
              to: _to,
              onDates: (f, t) => setState(() {
                _from = f;
                _to = t;
              }),
              onClear: () => setState(() {
                _search.clear();
                _from = '';
                _to = '';
              }),
              extras: [
                AppSelect<String>(
                  value: _status,
                  items: [
                    const AppSelectItem(value: 'all', label: 'All statuses'),
                    for (final e in waterDailyStatusLabels.entries) AppSelectItem(value: e.key, label: e.value),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: const Text("No batch production records yet. Log the day's totals to get started.",
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: TColors.slate500)),
              )
            else
              MobileCardList<Map>(
                striped: true,
                items: pageRows,
                keyOf: (r) => '${_id(r)}',
                primary: (r) => tStr(r['productionNumber']).isNotEmpty ? tStr(r['productionNumber']) : '#${_id(r)}',
                secondary: (r) => '${fmtDateTime(r['productionDate'], r, _offset)} · ${tStr(r['productName']).isEmpty ? '—' : tStr(r['productName'])}',
                trailing: (r) => Padding(padding: const EdgeInsets.only(left: 6), child: waterDailyStatusBadge(r['status'])),
                highlights: (r) => [
                  Highlight('Bags', qtyFmt(r['bagsProduced']), accent: Accent.blue),
                  Highlight('Good', qtyFmt(r['goodBags']), accent: Accent.emerald),
                  Highlight('All-in cost', _gh(tNum(r['allInCost'])), accent: Accent.violet, wide: true),
                ],
                details: (r) => [
                  ('Machines', waterMachineScopeLabel(r)),
                  ('Rejected', qtyFmt(r['rejectedSachets'])),
                  ('Cost/bag', _gh(tNum(r['costPerBag']))),
                ],
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Date', width: 130), TCol('Document', width: 130), TCol('Product', width: 130), TCol('Machines', width: 160),
                    TCol('Bags', right: true, width: 80), TCol('Good', right: true, width: 80), TCol('Rejected', right: true, width: 80),
                    TCol('All-in cost', right: true, width: 120), TCol('Cost/bag', right: true, width: 100), TCol('Status', width: 140),
                    TCol('Actions', right: true, width: 200),
                  ],
                  rows: [
                    for (final r in items)
                      [
                        cellText(fmtDateTime(r['productionDate'], r, _offset)),
                        cellText(tStr(r['productionNumber']).isNotEmpty ? tStr(r['productionNumber']) : '#${_id(r)}', bold: true),
                        cellText(tStr(r['productName']).isEmpty ? '—' : tStr(r['productName'])),
                        Text(waterMachineScopeLabel(r), style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                        Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(r['bagsProduced']))),
                        Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(r['goodBags']))),
                        Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(r['rejectedSachets']))),
                        Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(r['allInCost'])))),
                        Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(r['costPerBag'])))),
                        Align(alignment: Alignment.centerLeft, child: waterDailyStatusBadge(r['status'])),
                        Wrap(alignment: WrapAlignment.end, children: _actions(r)),
                      ],
                  ],
                ),
                pager: CompactPager(
                  total: filtered.length,
                  page: _page,
                  pageSize: _pageSize,
                  onPage: (p) => setState(() => _page = p),
                  onPageSize: (v) => setState(() {
                    _pageSize = v;
                    _page = 1;
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ form

/// Log Batch Production / Edit (`components/water/daily-production-form.tsx`).
/// The record is inert until an allocation is posted.
class WaterBatchProductionFormScreen extends StatefulWidget {
  const WaterBatchProductionFormScreen({super.key, required this.session, required this.company, this.editId});
  final Session session;
  final Company company;

  /// The record to edit (`/water-daily-production/{id}/edit`); null logs a new one.
  final int? editId;

  @override
  State<WaterBatchProductionFormScreen> createState() => _WaterBatchProductionFormScreenState();
}

class _MatLine {
  _MatLine(this.base, {required this.itemId, this.itemName, this.unit, required this.used, this.expected, this.unitCost})
      : usedCtl = TextEditingController(text: _plain(used)),
        expectedCtl = TextEditingController(text: expected == null ? '' : _plain(expected)),
        costCtl = TextEditingController(text: unitCost == null ? '' : _plain(unitCost));
  final Map base;
  int itemId;
  String? itemName, unit;
  num used;
  num? expected, unitCost;
  final TextEditingController usedCtl, expectedCtl, costCtl;

  static String _plain(num v) => qtyFmt(v).replaceAll(',', '');

  void dispose() {
    usedCtl.dispose();
    expectedCtl.dispose();
    costCtl.dispose();
  }
}

class _WaterBatchProductionFormScreenState extends State<WaterBatchProductionFormScreen> {
  Map? _existing;
  bool _loading = true, _saving = false;
  List<Map> _machines = [], _products = [], _boreholes = [], _items = [];
  final _number = TextEditingController(), _bags = TextEditingController(), _perBag = TextEditingController(text: '30');
  final _loose = TextEditingController(), _rejected = TextEditingController(), _damaged = TextEditingController();
  final _rolls = TextEditingController(), _litres = TextEditingController(), _elec = TextEditingController();
  final _fuel = TextEditingController(), _labor = TextEditingController(), _other = TextEditingController(), _notes = TextEditingController();
  String _date = _today(), _shift = 'FullDay', _scope = 'AllMachines';
  int? _productId, _boreholeId;
  List<int> _selected = [];
  final List<_MatLine> _materials = [];
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _user => widget.session.tokens.userId ?? '';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    _load();
  }

  @override
  void dispose() {
    for (final c in [_number, _bags, _perBag, _loose, _rejected, _damaged, _rolls, _litres, _elec, _fuel, _labor, _other, _notes]) {
      c.dispose();
    }
    for (final m in _materials) {
      m.dispose();
    }
    super.dispose();
  }

  static String _s(Object? v) => v == null ? '' : _MatLine._plain(tNum(v));

  Future<void> _load() async {
    final q = {'farmId': _farmId};
    if (widget.editId != null) {
      try {
        final r = await _api.get('/api/Water/daily-productions/${widget.editId}', query: q);
        final d = r is Map ? r : <String, Object?>{};
        final st = tStr(d['status']);
        if (st == 'Posted' || st == 'Cancelled') {
          if (!mounted) return;
          trackerToast(context, 'A ${st.toLowerCase()} record cannot be edited', error: true);
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => WaterBatchProductionDetailScreen(session: widget.session, company: widget.company, id: widget.editId!),
          ));
          return;
        }
        _existing = d;
        _number.text = tStr(d['productionNumber']);
        _date = _day10(d['productionDate']).isEmpty ? _today() : _day10(d['productionDate']);
        _shift = tStr(d['shift']).isEmpty ? 'FullDay' : tStr(d['shift']);
        _scope = tStr(d['machineSelectionType']).isEmpty ? 'AllMachines' : tStr(d['machineSelectionType']);
        _productId = tIntOrNull(d['waterProductId']);
        _boreholeId = tIntOrNull(d['waterBoreholeId']);
        _selected = [for (final m in rowsOf(d['machines'])) tIntOrNull(m['waterMachineId']) ?? 0];
        _bags.text = _s(d['bagsProduced']);
        _perBag.text = d['sachetsPerBag'] == null ? '30' : _s(d['sachetsPerBag']);
        _loose.text = _s(d['looseSachetsProduced']);
        _rejected.text = _s(d['rejectedSachets']);
        _damaged.text = _s(d['damagedBags']);
        _rolls.text = _s(d['packagingRollsUsed']);
        _litres.text = _s(d['estimatedWaterUsedLitres']);
        _elec.text = _s(d['electricityCost']);
        _fuel.text = _s(d['fuelCost']);
        _labor.text = _s(d['laborCost']);
        _other.text = _s(d['otherProductionCost']);
        _notes.text = tStr(d['notes']);
        _materials.addAll([
          for (final m in rowsOf(d['materials']))
            _MatLine(m,
                itemId: tIntOrNull(m['waterRawMaterialItemId']) ?? 0,
                itemName: tStr(m['itemName']).isEmpty ? null : tStr(m['itemName']),
                unit: tStr(m['unitOfMeasure']).isEmpty ? null : tStr(m['unitOfMeasure']),
                used: tNum(m['quantityUsed']),
                expected: m['expectedQuantityUsed'] == null ? null : tNum(m['expectedQuantityUsed']),
                unitCost: m['unitCost'] == null ? null : tNum(m['unitCost'])),
        ]);
      } on ApiException catch (e) {
        if (!mounted) return;
        trackerToast(context, 'Failed to load the record', description: e.message, error: true);
        Navigator.of(context).pop();
        return;
      }
    }
    try {
      Future<Object?> soft(String p) async {
        try {
          return await _api.get(p, query: q);
        } on ApiException {
          return const <Map>[];
        }
      }

      final r = await Future.wait([
        _api.get('/api/Water/machines', query: q),
        _api.get('/api/Water/products', query: q),
        soft('/api/Water/boreholes'),
        _api.get('/api/Water/raw-material-items', query: q),
      ]);
      _machines = rowsOf(r[0]);
      _products = rowsOf(r[1]);
      _boreholes = rowsOf(r[2]);
      _items = rowsOf(r[3]);
      if (_existing == null && _products.length == 1) _productId = tIntOrNull(_products.first['waterProductId']);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load form data', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  num _n(TextEditingController c) => num.tryParse(c.text) ?? 0;

  /// The machine set this day covers; AllMachines is frozen at save time.
  List<Map<String, Object?>> get _scoped {
    final pick = _scope == 'AllMachines'
        ? [for (final m in _machines) if (tStr(m['status']) == 'Active') m]
        : [for (final m in _machines) if (_selected.contains(tIntOrNull(m['waterMachineId']))) m];
    return [
      for (final m in pick)
        {
          'waterMachineId': tIntOrNull(m['waterMachineId']),
          'machineName': m['machineName'],
          'machineNumber': m['machineNumber'],
          'capacityPerHour': m['capacityPerHour'],
          'operatorStaffId': m['assignedOperatorStaffId'],
        },
    ];
  }

  num get _materialCost => _materials.fold<num>(0, (s, m) => s + m.used * (m.unitCost ?? 0));

  Future<void> _seed() async {
    if (_productId == null) return trackerToast(context, 'Pick the product first', error: true);
    final qty = _n(_bags);
    if (qty <= 0) return trackerToast(context, 'Enter the bags produced first', error: true);
    try {
      final recipe = await _api.get('/api/Water/products/$_productId/recipe', query: {'farmId': _farmId});
      final items = recipe is Map ? rowsOf(recipe['items']) : const <Map>[];
      if (!mounted) return;
      if (items.isEmpty) {
        return trackerToast(context, 'No recipe for this product', description: 'Set one up on the product page, or add materials by hand.');
      }
      setState(() {
        for (final m in _materials) {
          m.dispose();
        }
        _materials
          ..clear()
          ..addAll([
            for (final ri in items)
              () {
                final expected = (tNum(ri['quantityPerOutputUnit']) * qty * (1 + tNum(ri['wasteAllowancePercent']) / 100) * 1000).round() / 1000;
                return _MatLine(const {},
                    itemId: tIntOrNull(ri['waterRawMaterialItemId']) ?? 0,
                    itemName: tStr(ri['rawMaterialName']).isEmpty ? null : tStr(ri['rawMaterialName']),
                    unit: tStr(ri['rawMaterialUnit']).isEmpty ? null : tStr(ri['rawMaterialUnit']),
                    used: expected,
                    expected: expected,
                    unitCost: ri['latestUnitCost'] == null ? null : tNum(ri['latestUnitCost']));
              }(),
          ]);
      });
      trackerToast(context, 'Materials seeded from the recipe', description: 'Scaled to ${qtyFmt(qty)} bags. Adjust to what was actually used.');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load the recipe', description: e.message, error: true);
    }
  }

  String? _validate() {
    if (_productId == null) return 'Pick the product this batch produces.';
    if (_n(_bags) <= 0) return 'Bags produced must be greater than zero.';
    if (_n(_damaged) > _n(_bags)) return 'Damaged bags cannot exceed bags produced.';
    if (_scoped.isEmpty) return 'This batch needs at least one machine.';
    if (_date.compareTo(_today()) > 0) return 'Production date cannot be in the future.';
    for (final m in _materials) {
      if (m.itemId != 0 && m.used < 0) return 'Material quantities cannot be negative.';
    }
    return null;
  }

  Future<void> _save(String status) async {
    final err = _validate();
    if (err != null) return trackerToast(context, err, error: true);
    setState(() => _saving = true);
    final payload = <String, Object?>{
      'productionNumber': _number.text.isEmpty ? null : _number.text,
      'productionDate': _date,
      'shift': _shift,
      'machineSelectionType': _scope,
      'waterProductId': _productId,
      'waterBoreholeId': _boreholeId,
      'bagsProduced': _n(_bags),
      'sachetsPerBag': _n(_perBag) == 0 ? 30 : _n(_perBag),
      'looseSachetsProduced': _n(_loose),
      'rejectedSachets': _n(_rejected),
      'damagedBags': _n(_damaged),
      'packagingRollsUsed': _n(_rolls),
      'estimatedWaterUsedLitres': _litres.text.isEmpty ? null : _n(_litres),
      'electricityCost': _n(_elec),
      'fuelCost': _n(_fuel),
      'laborCost': _n(_labor),
      'otherProductionCost': _n(_other),
      'rawMaterialCost': _materialCost,
      'status': status,
      'notes': _notes.text.isEmpty ? null : _notes.text,
      'machines': _scoped,
      'materials': [
        for (final m in _materials)
          if (m.itemId > 0 && m.used > 0)
            {
              ...m.base,
              'waterRawMaterialItemId': m.itemId,
              'itemName': m.itemName,
              'unitOfMeasure': m.unit,
              'quantityUsed': m.used,
              'expectedQuantityUsed': m.expected,
              'unitCost': m.unitCost,
            },
      ],
      'farmId': _farmId,
      'userId': _user,
    };
    try {
      final s = widget.session, c = widget.company;
      if (_existing != null) {
        final id = widget.editId!;
        await _api.put('/api/Water/daily-productions/$id', body: {...payload, 'waterDailyProductionId': id, 'updatedBy': _user});
        if (!mounted) return;
        trackerToast(context, 'Batch production updated');
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => WaterBatchProductionDetailScreen(session: s, company: c, id: id)));
      } else {
        final saved = await _api.post('/api/Water/daily-productions', body: payload);
        if (!mounted) return;
        trackerToast(context, status == 'Draft' ? 'Draft saved' : 'Batch production logged',
            description: status == 'Draft' ? null : 'Now allocate the batch across the machines.');
        final id = saved is Map ? tIntOrNull(saved['waterDailyProductionId']) : null;
        if (id != null) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => WaterBatchAllocateScreen(session: s, company: c, id: id)));
        } else {
          Navigator.of(context).pop(true);
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed to save', description: e.message, error: true);
    }
  }

  Widget _num(TextEditingController c, {bool decimal = false}) => AppInput(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'^\d*\.?\d*' : r'^\d*'))],
        onChanged: (_) => setState(() {}),
      );

  Widget _hinted(String label, Widget field, String hint) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilterLabel(label, field),
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint, style: const TextStyle(fontSize: 11, color: TColors.slate500))),
      ]);

  Widget _matCard(_MatLine m) {
    final it = _items.where((i) => tIntOrNull(i['waterRawMaterialItemId']) == m.itemId).firstOrNull;
    const small = TextStyle(fontSize: 11, color: TColors.slate400);
    Widget numField(String label, TextEditingController c, ValueChanged<String> on, String note) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilterLabel(
              label,
              AppInput(
                controller: c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                onChanged: (t) => setState(() => on(t)),
              ),
            ),
            Text(note, style: small),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: FilterLabel(
              'Material',
              AppSelect<int>(
                value: m.itemId == 0 ? null : m.itemId,
                hintText: 'Pick material',
                items: [for (final i in _items) AppSelectItem(value: tIntOrNull(i['waterRawMaterialItemId']) ?? 0, label: tStr(i['itemName']))],
                onChanged: (v) => setState(() {
                  final i = _items.where((x) => tIntOrNull(x['waterRawMaterialItemId']) == v).firstOrNull;
                  m.itemId = v ?? 0;
                  m.itemName = tStr(i?['itemName']).isEmpty ? null : tStr(i?['itemName']);
                  m.unit = tStr(i?['unitOfMeasure']).isEmpty ? null : tStr(i?['unitOfMeasure']);
                }),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove material',
            onPressed: () => setState(() => _materials.remove(m..dispose())),
            icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          numField('Used${m.unit != null ? ' (${m.unit})' : ''}', m.usedCtl, (t) => m.used = num.tryParse(t) ?? 0,
              it != null ? 'In stock: ${qtyFmt(it['currentQuantity'])}' : ''),
          const SizedBox(width: 8),
          numField('Expected', m.expectedCtl, (t) => m.expected = t.isEmpty ? null : (num.tryParse(t) ?? 0), 'From the recipe'),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          numField('Unit cost', m.costCtl, (t) => m.unitCost = t.isEmpty ? null : (num.tryParse(t) ?? 0), 'Priced from lots at posting'),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Cost', style: TextStyle(fontSize: 12, color: TColors.slate500)),
              SizedBox(height: 40, child: Align(alignment: Alignment.centerRight, child: Text(_gh(m.used * (m.unitCost ?? 0))))),
            ]),
          ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _existing;
    final title = e != null
        ? 'Edit ${tStr(e['productionNumber']).isNotEmpty ? tStr(e['productionNumber']) : 'batch #${widget.editId}'}'
        : 'Log Batch Production';
    if (_loading) {
      return Scaffold(appBar: AppBar(title: Text(title)), body: const Padding(padding: EdgeInsets.all(24), child: LoadingLine('Loading…')));
    }
    final scoped = _scoped;
    final totalCost = _n(_elec) + _n(_fuel) + _n(_labor) + _n(_other);
    final matCost = _materialCost;
    final good = (_n(_bags) - _n(_damaged)).clamp(0, double.infinity);
    Widget fig(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]);
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF0F9FF), border: Border.all(color: const Color(0xFFBAE6FD)), borderRadius: BorderRadius.circular(10)),
              child: const Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Enter the batch totals only. ', style: TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(
                      text: 'Record everything the factory produced and consumed, combined across every machine. This record does nothing on its own — stock, expenses and finished goods are only touched once you allocate the batch across machines and post it.'),
                ]),
                style: TextStyle(fontSize: 13, color: Color(0xFF0C4A6E)),
              ),
            ),
            const SizedBox(height: 12),
            formSection('Batch & scope', const Color(0xFF2563EB), [
              FilterLabel(
                'Production date *',
                AppDateField(
                  value: businessDateAsDateTime(_date),
                  hintText: 'dd/mm/yyyy',
                  lastDate: businessDateAsDateTime(_today()),
                  onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)),
                ),
              ),
              _hinted('Document number', AppInput(controller: _number, hintText: 'DP-20260812-01'), 'Optional — used as the production number prefix'),
              FilterLabel(
                'Shift',
                AppSelect<String>(
                  value: _shift,
                  items: [for (final s in waterShifts) AppSelectItem(value: s, label: s)],
                  onChanged: (v) => setState(() => _shift = v ?? 'FullDay'),
                ),
              ),
              FilterLabel(
                'Product *',
                AppSelect<int>(
                  value: _productId,
                  hintText: _products.isNotEmpty ? 'Pick product' : 'No products',
                  items: [for (final p in _products) AppSelectItem(value: tIntOrNull(p['waterProductId']) ?? 0, label: tStr(p['name']))],
                  onChanged: (v) => setState(() => _productId = v),
                ),
              ),
              FilterLabel(
                'Borehole',
                AppSelect<String>(
                  value: _boreholeId == null ? 'none' : '$_boreholeId',
                  items: [
                    const AppSelectItem(value: 'none', label: 'Not recorded'),
                    for (final b in _boreholes) AppSelectItem(value: tStr(b['waterBoreholeId']), label: tStr(b['boreholeName'])),
                  ],
                  onChanged: (v) => setState(() => _boreholeId = v == null || v == 'none' ? null : int.tryParse(v)),
                ),
              ),
              _hinted(
                'Machines *',
                AppSelect<String>(
                  value: _scope == 'CustomMachines' ? 'CustomMachines' : 'AllMachines',
                  items: const [
                    AppSelectItem(value: 'AllMachines', label: 'All active machines'),
                    AppSelectItem(value: 'CustomMachines', label: 'Pick machines…'),
                  ],
                  onChanged: (v) => setState(() => _scope = v ?? 'AllMachines'),
                ),
                'Which machines ran for this batch',
              ),
              if (_scope == 'CustomMachines')
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                  child: Material(type: MaterialType.transparency, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('Select the machines that ran', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                    for (final m in _machines)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selected.contains(tIntOrNull(m['waterMachineId'])),
                        onChanged: (c) => setState(() {
                          final id = tIntOrNull(m['waterMachineId']) ?? 0;
                          c == true ? _selected.add(id) : _selected.remove(id);
                        }),
                        title: Text.rich(TextSpan(children: [
                          TextSpan(text: tStr(m['machineName'])),
                          if (tStr(m['status']) != 'Active')
                            TextSpan(text: ' (${tStr(m['status'])})', style: const TextStyle(fontSize: 11, color: TColors.amber600)),
                        ])),
                      ),
                  ])),
                ),
              Text(
                '${scoped.length} machine${scoped.length == 1 ? '' : 's'} in scope${scoped.isNotEmpty ? ' — ${scoped.map((m) => m['machineName']).join(', ')}' : ''}',
                style: const TextStyle(fontSize: 12, color: TColors.slate500),
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Batch output', const Color(0xFF059669), [
              FilterLabel('Bags produced *', _num(_bags)),
              FilterLabel('Sachets per bag', _num(_perBag)),
              FilterLabel('Loose sachets', _num(_loose)),
              FilterLabel('Rejected sachets', _num(_rejected)),
              FilterLabel('Damaged bags', _num(_damaged)),
              FilterLabel('Packaging rolls used', _num(_rolls)),
              _hinted('Water used (litres)', _num(_litres), 'Optional'),
              _hinted('Good bags', Text(qtyFmt(good), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate800)), 'Bags produced less damaged'),
            ]),
            const SizedBox(height: 12),
            formSection('Production costs', TColors.amber600, [
              FilterLabel('Electricity', _num(_elec, decimal: true)),
              FilterLabel('Fuel', _num(_fuel, decimal: true)),
              FilterLabel('Labor', _num(_labor, decimal: true)),
              FilterLabel('Other', _num(_other, decimal: true)),
              const Text(
                "Each bucket becomes a real expense on every machine's production record when the batch is posted, so the allocation has to add up to these figures exactly.",
                style: TextStyle(fontSize: 12, color: TColors.slate500),
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Raw materials used', const Color(0xFF059669), [
              if (_materials.isEmpty)
                const Text('No materials yet. Seed them from the product recipe, or add lines by hand.',
                    style: TextStyle(fontSize: 13, color: TColors.slate400)),
              for (final m in _materials) _matCard(m),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _materials.add(_MatLine(const {}, itemId: 0, used: 0))),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add material'),
                ),
                TextButton.icon(onPressed: _seed, icon: const Icon(Icons.auto_fix_high, size: 16), label: const Text('Seed from recipe')),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Material cost (preview): ', style: TextStyle(color: TColors.slate600)),
                  TextSpan(text: _gh(matCost), style: const TextStyle(fontWeight: FontWeight.w600)),
                ])),
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Notes', const Color(0xFF2563EB), [AppInput(controller: _notes, minLines: 2, maxLines: 4)]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
              child: twoUp([
                fig('Production cost', _gh(totalCost)),
                fig('Material cost', _gh(matCost)),
                fig('All-in cost', _gh(totalCost + matCost)),
                fig('Cost / good bag', _gh(good > 0 ? (totalCost + matCost) / good : 0)),
              ]),
            ),
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
              OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
              if (e == null)
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _save('Draft'),
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: Text(_saving ? 'Saving…' : 'Save as draft'),
                ),
              FilledButton.icon(
                onPressed: _saving ? null : () => _save(e != null ? tStr(e['status']) : 'PendingAllocation'),
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text(_saving ? 'Saving…' : (e != null ? 'Save changes' : 'Log batch & allocate')),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ record page

class WaterBatchProductionDetailScreen extends StatefulWidget {
  const WaterBatchProductionDetailScreen({super.key, required this.session, required this.company, required this.id});
  final Session session;
  final Company company;
  final int id;

  @override
  State<WaterBatchProductionDetailScreen> createState() => _WaterBatchProductionDetailScreenState();
}

class _WaterBatchProductionDetailScreenState extends State<WaterBatchProductionDetailScreen> {
  Map? _d;
  FarmMoney _gh = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.session.farmClient.get('/api/Water/daily-productions/${widget.id}', query: {'farmId': widget.company.farmId});
      if (mounted) setState(() => _d = r is Map ? r : <String, Object?>{});
    } on ApiException catch (e) {
      if (!mounted) return;
      trackerToast(context, 'Failed to load the record', description: e.message, error: true);
      _back();
    }
  }

  void _back() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacement(MaterialPageRoute(builder: (_) => WaterBatchProductionScreen(session: widget.session, company: widget.company)));
    }
  }

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _load();
  }

  Widget _card(String? title, List<Widget> children) => Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) ...[Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate700)), const SizedBox(height: 8)],
          ...children,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-daily-production');
    final d = _d;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Batch production')),
        body: const Padding(padding: EdgeInsets.all(24), child: LoadingLine('Loading…')),
      );
    }
    final st = tStr(d['status']);
    final canAllocate = const ['PendingAllocation', 'Allocated', 'Reversed'].contains(st);
    final canEdit = !const ['Posted', 'Cancelled'].contains(st);
    final name = tStr(d['productionNumber']).isNotEmpty ? tStr(d['productionNumber']) : 'Batch #${tStr(d['waterDailyProductionId'])}';
    final materials = rowsOf(d['materials']), allocations = rowsOf(d['allocations']), postings = rowsOf(d['postings']);
    Widget field(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate900)),
        ]);
    String ts(Object? v) => tStr(v).isEmpty ? '' : tStr(v).substring(0, tStr(v).length < 19 ? tStr(v).length : 19).replaceFirst('T', ' ');
    final s = widget.session, c = widget.company;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(name)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
          children: [
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton.icon(onPressed: _back, icon: const Icon(Icons.arrow_back, size: 16), label: const Text('Back')),
              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
              waterDailyStatusBadge(st),
            ]),
            Wrap(spacing: 8, children: [
              if (canEdit)
                OutlinedButton.icon(
                  onPressed: () => _go(WaterBatchProductionFormScreen(session: s, company: c, editId: widget.id)),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                ),
              if (canAllocate)
                FilledButton.icon(
                  onPressed: () => _go(WaterBatchAllocateScreen(session: s, company: c, id: widget.id)),
                  icon: const Icon(Icons.layers_outlined, size: 16),
                  label: const Text('Allocation'),
                ),
            ]),
            const SizedBox(height: 12),
            _card(null, [
              twoUp([
                field('Date', _day10(d['productionDate'])),
                field('Shift', tStr(d['shift'])),
                field('Product', tStr(d['productName']).isEmpty ? '—' : tStr(d['productName'])),
                field('Borehole', tStr(d['boreholeName']).isEmpty ? '—' : tStr(d['boreholeName'])),
                field('Machines', waterMachineScopeLabel(d)),
                field('Posting version', tStr(d['postingVersion'])),
                field('Bags produced', qtyFmt(d['bagsProduced'])),
                field('Sachets per bag', tStr(d['sachetsPerBag'])),
                field('Loose sachets', qtyFmt(d['looseSachetsProduced'])),
                field('Rejected', qtyFmt(d['rejectedSachets'])),
                field('Damaged bags', qtyFmt(d['damagedBags'])),
                field('Good bags', qtyFmt(d['goodBags'])),
                field('Packaging rolls', qtyFmt(d['packagingRollsUsed'])),
                field('Water used (L)', d['estimatedWaterUsedLitres'] == null ? '—' : qtyFmt(d['estimatedWaterUsedLitres'])),
                field('Production cost', _gh(tNum(d['totalProductionCost']))),
                field('Material cost', _gh(tNum(d['rawMaterialCost']))),
                field('All-in cost', _gh(tNum(d['allInCost']))),
                field('Cost / good bag', _gh(tNum(d['costPerBag']))),
              ]),
            ]),
            if (materials.isNotEmpty) ...[
              const SizedBox(height: 12),
              _card('Raw materials used (day total)', [
                TrackerTable(
                  columns: const [
                    TCol('Material', width: 160), TCol('Used', right: true, width: 90), TCol('Expected', right: true, width: 90),
                    TCol('Variance', right: true, width: 90), TCol('Cost', right: true, width: 110),
                  ],
                  rows: [
                    for (final m in materials)
                      () {
                        final variance = m['expectedQuantityUsed'] != null ? tNum(m['quantityUsed']) - tNum(m['expectedQuantityUsed']) : null;
                        return <Widget>[
                          cellText('${tStr(m['itemName'])}${tStr(m['unitOfMeasure']).isNotEmpty ? ' (${tStr(m['unitOfMeasure'])})' : ''}'),
                          Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(m['quantityUsed']))),
                          Align(alignment: Alignment.centerRight, child: cellText(m['expectedQuantityUsed'] == null ? '—' : qtyFmt(m['expectedQuantityUsed']))),
                          Align(
                            alignment: Alignment.centerRight,
                            child: cellText(
                              variance == null ? '—' : (variance > 0 ? '+${variance.toStringAsFixed(3)}' : variance.toStringAsFixed(3)),
                              color: variance != null && variance > 0 ? TColors.amber700 : null,
                            ),
                          ),
                          Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(m['totalCost'])))),
                        ];
                      }(),
                  ],
                ),
              ]),
            ],
            if (allocations.isNotEmpty) ...[
              const SizedBox(height: 12),
              _card('Allocation — ${allocations.length} machine${allocations.length == 1 ? '' : 's'}', [
                TrackerTable(
                  columns: const [
                    TCol('Machine', width: 130), TCol('Bags', right: true, width: 80), TCol('Rejected', right: true, width: 80),
                    TCol('Damaged', right: true, width: 80), TCol('Prod. cost', right: true, width: 110), TCol('Material cost', right: true, width: 110),
                    TCol('Production', width: 150),
                  ],
                  rows: [
                    for (final a in allocations)
                      [
                        cellText(tStr(a['machineName']), bold: true),
                        Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(a['bagsProduced']))),
                        Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(a['rejectedSachets']))),
                        Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(a['damagedBags']))),
                        Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(a['totalProductionCost'])))),
                        Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(a['rawMaterialCost'])))),
                        tIntOrNull(a['generatedWaterProductionBatchId']) != null
                            ? InkWell(
                                onTap: () => _go(WaterProductionDetailScreen(session: s, company: c, batchId: tIntOrNull(a['generatedWaterProductionBatchId'])!)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Flexible(child: Text(tStr(a['generatedBatchNumber']), style: const TextStyle(fontSize: 12, color: Color(0xFF0284C7)))),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.open_in_new, size: 12, color: Color(0xFF0284C7)),
                                ]),
                              )
                            : tStr(a['generatedBatchNumber']).isNotEmpty
                                ? cellText(tStr(a['generatedBatchNumber']), color: TColors.slate400, strike: true)
                                : cellText('—', color: TColors.slate400),
                      ],
                  ],
                ),
              ]),
            ],
            if (postings.isNotEmpty) ...[
              const SizedBox(height: 12),
              _card('Posting history', [
                TrackerTable(
                  columns: const [TCol('Version', width: 70), TCol('Production', width: 150), TCol('Posted', width: 150), TCol('Reversed', width: 150)],
                  rows: [
                    for (final p in postings)
                      [
                        cellText('v${tStr(p['postingVersion'])}'),
                        Text(tStr(p['batchNumber']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        cellText(tStr(p['postedAt']).isEmpty ? '—' : ts(p['postedAt']), color: TColors.slate600),
                        tStr(p['reversedAt']).isNotEmpty
                            ? cellText(ts(p['reversedAt']), color: TColors.slate600)
                            : cellText('live', color: TColors.emerald600),
                      ],
                  ],
                ),
              ]),
            ],
            if (tStr(d['notes']).isNotEmpty) ...[
              const SizedBox(height: 12),
              _card(null, [
                const Text('Notes', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                Text(tStr(d['notes']), style: const TextStyle(fontSize: 13, color: TColors.slate800)),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ allocation workspace

/// Split the batch's totals across the machines that ran. Nothing here touches
/// stock: Post is what creates and approves the per-machine records.
class WaterBatchAllocateScreen extends StatefulWidget {
  const WaterBatchAllocateScreen({super.key, required this.session, required this.company, required this.id});
  final Session session;
  final Company company;
  final int id;

  @override
  State<WaterBatchAllocateScreen> createState() => _WaterBatchAllocateScreenState();
}

class _WaterBatchAllocateScreenState extends State<WaterBatchAllocateScreen> {
  Map? _day;
  List<WaterAllocRow> _rows = [];
  Map<int, num> _history = {};
  String _method = 'Manual';
  bool _busy = false;
  int _version = 0;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _user => widget.session.tokens.userId ?? '';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.get('/api/Water/daily-productions/${widget.id}', query: {'farmId': _farmId});
      final d = r is Map ? r : <String, Object?>{};
      final allocations = rowsOf(d['allocations']);
      var openMethod = false;
      setState(() {
        _day = d;
        if (allocations.isNotEmpty) {
          _rows = waterAllocationsToRows(allocations, rowsOf(d['machines']));
          _method = 'Manual';
        } else {
          _rows = [for (final m in rowsOf(d['machines'])) waterBlankRow(m)];
          openMethod = true;
        }
        _version++;
      });
      // Recent machine output for ByPreviousProduction, bounded to 30 days.
      final to = _day10(d['productionDate']).isEmpty ? _today() : _day10(d['productionDate']);
      final toD = DateTime.parse(to);
      final from = toD.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);
      try {
        final recent = rowsOf(await _api.get('/api/Water/production-batches', query: {'farmId': _farmId, 'fromDate': from, 'toDate': to}));
        final acc = <int, (num, int)>{};
        for (final b in recent) {
          final k = tIntOrNull(b['waterMachineId']);
          if (tStr(b['status']) != 'Approved' || k == null || k == 0) continue;
          final cur = acc[k] ?? (0, 0);
          acc[k] = (cur.$1 + tNum(b['bagsProduced']), cur.$2 + 1);
        }
        if (mounted) setState(() => _history = {for (final e in acc.entries) e.key: e.value.$2 > 0 ? e.value.$1 / e.value.$2 : 0});
      } on ApiException {
        // Weighting falls back to capacity.
      }
      if (openMethod && mounted) await _methodDialog();
    } on ApiException catch (e) {
      if (!mounted) return;
      trackerToast(context, 'Failed to load the batch', description: e.message, error: true);
      Navigator.of(context).pop();
    }
  }

  bool get _readOnly => _day != null && !const ['PendingAllocation', 'Allocated', 'Reversed'].contains(tStr(_day!['status']));

  void _runMethod(String m) {
    final day = _day;
    if (day == null) return;
    setState(() {
      _method = m;
      _rows = waterApplyMethod(m, _rows, day, _history);
      _version++;
    });
    if (m != 'Manual') {
      trackerToast(context, 'Split ${waterAllocMethods.firstWhere((x) => x.$1 == m).$2.toLowerCase()}');
    }
  }

  Future<void> _methodDialog() async {
    final m = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Split the batch automatically'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Every method distributes exactly — the parts always add back up to the batch totals.',
              style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 10),
          for (final (v, label, desc) in waterAllocMethods)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => Navigator.pop(ctx, v),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                    Text(desc, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
    if (m != null) _runMethod(m);
  }

  Future<void> _reconDialog() async {
    final day = _day;
    if (day == null) return;
    final recon = waterBuildReconciliation(_rows, day);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Reconciliation'),
        content: SizedBox(
          width: 600,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              "Output and production-cost lines must match to post. Material cost is informational — the real price comes from the stock lots when each machine's production record is approved.",
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 10),
            TrackerTable(
              columns: const [
                TCol('Field', width: 150), TCol('Allocated', right: true, width: 100), TCol('Batch total', right: true, width: 100),
                TCol('Difference', right: true, width: 100), TCol('Status', right: true, width: 70),
              ],
              rows: [
                for (final l in recon.lines)
                  [
                    cellText(l.label),
                    Align(alignment: Alignment.centerRight, child: cellText(_fmt(l, l.allocated))),
                    Align(alignment: Alignment.centerRight, child: cellText(_fmt(l, l.dayTotal))),
                    Align(
                      alignment: Alignment.centerRight,
                      child: cellText(l.diff > 0 ? '+${_fmt(l, l.diff)}' : _fmt(l, l.diff),
                          color: !l.balanced && !l.info ? TColors.red600 : null, bold: !l.balanced && !l.info),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: l.info
                          ? const Text('Info only', style: TextStyle(fontSize: 11, color: TColors.slate400))
                          : l.balanced
                              ? const Text('OK', style: TextStyle(fontSize: 11, color: TColors.emerald600))
                              : const Text('Off', style: TextStyle(fontSize: 11, color: TColors.red600)),
                    ),
                  ],
              ],
            ),
          ]),
        ),
      ),
    );
  }

  String _fmt(WaterReconLine l, num v) => l.money ? _gh(v) : (l.decimals != null ? v.toStringAsFixed(l.decimals!) : qtyFmt(v));

  Future<bool> _saveAllocation() async {
    await _api.post('/api/Water/daily-productions/${widget.id}/allocation',
        query: {'farmId': _farmId}, body: {'updatedBy': _user, 'status': 'Allocated', 'allocations': waterRowsToAllocations(_rows, _day!, _method)});
    return true;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _saveAllocation();
      if (mounted) trackerToast(context, 'Allocation saved');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to save the allocation', description: e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _post() async {
    final day = _day;
    if (day == null) return;
    if (_rows.any((r) => waterRowErrors(r, tNum(day['sachetsPerBag'])).isNotEmpty)) {
      return trackerToast(context, 'Fix the highlighted rows first', error: true);
    }
    setState(() => _busy = true);
    try {
      await _saveAllocation();
      await _api.post('/api/Water/daily-productions/${widget.id}/post', query: {'farmId': _farmId, 'postedBy': _user});
      if (!mounted) return;
      trackerToast(context, 'Batch posted',
          description: 'A production record was created and approved for each machine. Stock, expenses and losses are updated.');
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => WaterBatchProductionDetailScreen(session: widget.session, company: widget.company, id: widget.id),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      trackerToast(context, 'Failed to post', description: e.message, error: true);
    }
  }

  Widget _input(int i, String field, {bool decimal = false, int? itemId}) {
    final r = _rows[i];
    final value = itemId != null ? (r.materialQty[itemId] ?? 0) : r.v(field);
    return SizedBox(
      width: decimal ? 96 : 80,
      child: AppInput(
        key: ValueKey('$_version-$i-$field-$itemId'),
        initialValue: qtyFmt(value).replaceAll(',', ''),
        enabled: !_readOnly,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'^\d*\.?\d*' : r'^\d*'))],
        onChanged: (t) => setState(() {
          final n = num.tryParse(t) ?? 0;
          if (itemId != null) {
            r.materialQty[itemId] = n;
          } else {
            r.values[field] = n;
          }
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    if (day == null) {
      return Scaffold(appBar: AppBar(title: const Text('Allocate')), body: const Padding(padding: EdgeInsets.all(24), child: LoadingLine('Loading…')));
    }
    final materials = rowsOf(day['materials']);
    final perBag = tNum(day['sachetsPerBag']);
    final recon = waterBuildReconciliation(_rows, day);
    final byKey = {for (final l in recon.lines) l.key: l};
    final name = tStr(day['productionNumber']).isNotEmpty ? tStr(day['productionNumber']) : 'batch #${tStr(day['waterDailyProductionId'])}';
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate600);
    final keys = ['bags', 'loose', 'rejected', 'damaged', 'rolls', 'litres', 'elec', 'fuel', 'labor', 'other', for (final m in materials) 'mat-${tStr(m['waterRawMaterialItemId'])}'];
    Widget cell(Widget w, {bool right = true}) => Padding(padding: const EdgeInsets.all(4), child: Align(alignment: right ? Alignment.centerRight : Alignment.centerLeft, child: w));
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text('Allocate $name')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          children: [
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton.icon(onPressed: _busy ? null : () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, size: 16), label: const Text('Back')),
              Text('Allocate $name', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: TColors.slate900)),
              TBadge(_day10(day['productionDate']), bg: Colors.white, fg: TColors.slate700, border: TColors.slate300),
              TBadge(tStr(day['productName']).isEmpty ? '—' : tStr(day['productName']), bg: Colors.white, fg: TColors.slate700, border: TColors.slate300),
            ]),
            if (_readOnly) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber300), borderRadius: BorderRadius.circular(10)),
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'This batch is '),
                    TextSpan(text: tStr(day['status']), style: const TextStyle(fontWeight: FontWeight.w600)),
                    const TextSpan(text: ' and can no longer be allocated.'),
                  ]),
                  style: const TextStyle(fontSize: 13, color: TColors.amber900),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: _readOnly ? null : _methodDialog,
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: const Text('Split automatically'),
              ),
              TextButton(onPressed: _reconDialog, child: const Text('Reconciliation details')),
              Text.rich(
                TextSpan(children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(recon.balanced ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                          size: 16, color: recon.balanced ? TColors.emerald700 : TColors.amber700),
                    ),
                  ),
                  TextSpan(text: recon.balanced ? 'Balanced — ready to post' : 'Does not add up to the batch totals yet'),
                ]),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: recon.balanced ? TColors.emerald700 : TColors.amber700),
              ),
            ]),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: TColors.slate50),
                      children: [
                        cell(const Text('Machine', style: head), right: false),
                        for (final h in ['Bags', 'Loose', 'Rejected', 'Damaged', 'Rolls', 'Litres', 'Elec', 'Fuel', 'Labor', 'Other']) cell(Text(h, style: head)),
                        for (final m in materials)
                          cell(Text('${tStr(m['itemName'])}${tStr(m['unitOfMeasure']).isNotEmpty ? ' (${tStr(m['unitOfMeasure'])})' : ''}', style: head)),
                        cell(const Text('Good', style: head)),
                        cell(const Text('Cost/bag', style: head)),
                      ],
                    ),
                    for (var i = 0; i < _rows.length; i++)
                      () {
                        final r = _rows[i];
                        final errs = waterRowErrors(r, perBag);
                        return TableRow(
                          decoration: BoxDecoration(color: errs.isNotEmpty ? const Color(0xFFFEF2F2) : null, border: const Border(top: BorderSide(color: TColors.slate100))),
                          children: [
                            cell(
                              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                Text(r.machineName, style: const TextStyle(fontWeight: FontWeight.w500)),
                                if (r.capacity > 0) Text('${qtyFmt(r.capacity)}/hr', style: const TextStyle(fontSize: 11, color: TColors.slate400)),
                                if (errs.isNotEmpty) Text(errs.first, style: const TextStyle(fontSize: 11, color: TColors.red600)),
                              ]),
                              right: false,
                            ),
                            for (final f in waterAllocIntFields) cell(_input(i, f)),
                            for (final f in waterAllocMoneyFields) cell(_input(i, f, decimal: true)),
                            for (final m in materials) cell(_input(i, 'mat', decimal: true, itemId: tIntOrNull(m['waterRawMaterialItemId']) ?? 0)),
                            cell(Text(qtyFmt(waterRowGoodBags(r)), style: const TextStyle(color: TColors.slate700))),
                            cell(Text(_gh(waterRowCostPerBag(r, day)), style: const TextStyle(color: TColors.slate700))),
                          ],
                        );
                      }(),
                    for (final kind in ['allocated', 'dayTotal', 'diff'])
                      TableRow(
                        decoration: const BoxDecoration(color: TColors.slate50, border: Border(top: BorderSide(color: TColors.slate200))),
                        children: [
                          cell(
                            Text(kind == 'allocated' ? 'ALLOCATED' : (kind == 'dayTotal' ? 'BATCH TOTAL' : 'DIFFERENCE'),
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: TColors.slate700)),
                            right: false,
                          ),
                          for (final k in keys)
                            () {
                              final l = byKey[k];
                              if (l == null) return cell(const Text('—', style: TextStyle(color: TColors.slate300)));
                              final v = kind == 'allocated' ? l.allocated : (kind == 'dayTotal' ? l.dayTotal : l.diff);
                              final t = _fmt(l, v);
                              return cell(Text(
                                kind == 'diff' && v > 0 ? '+$t' : t,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: kind == 'diff' ? (l.balanced ? TColors.emerald600 : TColors.red600) : TColors.slate700,
                                  fontWeight: kind == 'diff' && !l.balanced ? FontWeight.w600 : null,
                                ),
                              ));
                            }(),
                          cell(Text(kind == 'allocated' ? qtyFmt(_rows.fold<num>(0, (s, r) => s + waterRowGoodBags(r))) : '', style: const TextStyle(fontSize: 12))),
                          cell(Text(kind == 'allocated' ? _gh(waterDayCostPerBag(_rows, day)) : '', style: const TextStyle(fontSize: 12))),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
              OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
              OutlinedButton.icon(
                onPressed: _busy || _readOnly ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text(_busy ? 'Saving…' : 'Save allocation'),
              ),
              Tooltip(
                message: recon.balanced ? '' : 'The allocation has to add up to the batch totals first',
                child: FilledButton.icon(
                  onPressed: _busy || _readOnly || !recon.balanced ? null : _post,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(_busy ? 'Posting…' : 'Post allocation'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
