// Poultry → Operations → Purchase → Flock Purchases (Batches)
// (app/flock-batch/page.tsx): the four score cards, search and the Filters
// sheet, striped batch cards and the 13-column table, Pay Balance, Divide into
// flocks, Add / Edit Flock Batch, the batch's flocks, delete, the bird totals,
// and the one-batch edit page (app/flock-batch/[id]/page.tsx).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../batch_allocation_screen.dart';
import '../breed_picker.dart';
import '../money/money_widgets.dart' show formSection, redCancelButton;
import '../reports/report_format.dart';
import '../sales/sales_logic.dart' show pageNumbers, salePageSizes;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, trackerDate, sortRows, toggleSort, SortState, loc;
import '../trackers/tracker_widgets.dart';

// ------------------------------------------------------------ rules

/// batchTogglesFromStatus / batchStatusFromToggles (lib/utils/batch-status.ts).
({bool hasArrived, bool active}) batchToggles(Object? status) => switch ((tStr(status).isEmpty ? 'active' : tStr(status)).toLowerCase()) {
      'pending' => (hasArrived: false, active: true),
      'inactive' => (hasArrived: true, active: false),
      _ => (hasArrived: true, active: true),
    };

String batchStatus(bool hasArrived, bool active) => !hasArrived ? 'pending' : (active ? 'active' : 'inactive');

String batchStatusOf(Map b) => (tStr(b['status']).isEmpty ? 'active' : tStr(b['status'])).toLowerCase();

/// Total cost, falling back to cost per chick × birds.
num batchTotal(Map b) {
  final t = tNum(b['totalCost']);
  return t != 0 ? t : tNum(b['costPerChick']) * tNum(b['numberOfBirds']);
}

num batchOutstanding(Map b) => (batchTotal(b) - tNum(b['amountPaid'])).clamp(0, double.infinity);

/// paymentStatus (lib/poultry/batch-purchase.ts): label, background, text.
(String, Color, Color) batchPaymentStatus(num total, num paid) {
  if (total <= 0) return ('No cost set', TColors.slate100, TColors.slate600);
  if (paid >= total) return ('Paid in full', TColors.green100, const Color(0xFF166534));
  if (paid <= 0) return ('Unpaid', TColors.red100, TColors.red800);
  return ('Part payment', TColors.amber100, TColors.amber900);
}

/// deriveTotalCost: cost × birds to 2 dp, or null when that is not positive.
num? deriveTotalCost(num costPerChick, num birds) {
  final t = costPerChick * birds;
  return t > 0 ? double.parse(t.toStringAsFixed(2)) : null;
}

/// consumedByBatch: flock quantities plus opening-position reductions.
Map<int, num> consumedByBatch(List<Map> flocks, List<Map> openingPositions) {
  final m = <int, num>{};
  void add(Object? id, Object? n) {
    final b = tIntOrNull(id);
    final v = tNum(n);
    if (b == null || v <= 0) return;
    m[b] = (m[b] ?? 0) + v;
  }

  for (final f in flocks) {
    add(f['batchId'], f['quantity']);
  }
  for (final p in openingPositions) {
    add(p['batchId'], p['historicalReduction']);
  }
  return m;
}

num unallocatedForBatch(num birds, num? consumed) => (birds - (consumed ?? 0)).clamp(0, double.infinity);

class BatchFilters {
  String search = '', from = '', to = '', breed = 'ALL', status = 'ALL';
}

List<Map> filterBatches(List<Map> rows, BatchFilters f) {
  final q = f.search.toLowerCase();
  return rows.where((b) {
    if (q.isNotEmpty && !tStr(b['batchName']).toLowerCase().contains(q) && !tStr(b['batchCode']).toLowerCase().contains(q)) return false;
    final day = tStr(b['startDate']).split('T').first;
    if (f.from.isNotEmpty && day.compareTo(f.from) < 0) return false;
    if (f.to.isNotEmpty && day.compareTo(f.to) > 0) return false;
    if (f.breed != 'ALL' && tStr(b['breed']) != f.breed) return false;
    if (f.status != 'ALL' && batchStatusOf(b) != f.status) return false;
    return true;
  }).toList();
}

/// getFlockLifecycleStatus.
String flockLifecycle(Map f) {
  if (tStr(f['closedDate']).isNotEmpty) return 'closed';
  if (f['hasArrived'] != true) return 'pending';
  return f['active'] == true ? 'active' : 'inactive';
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';

void _formGuide(BuildContext context, String description) => trackerToast(context, 'Almost there', description: description);

// ------------------------------------------------------------ screen

class FlockBatchesScreen extends StatefulWidget {
  const FlockBatchesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<FlockBatchesScreen> createState() => _FlockBatchesScreenState();
}

class _FlockBatchesScreenState extends State<FlockBatchesScreen> {
  List<Map> _batches = [], _flocks = [], _opening = [], _suppliers = [], _accounts = [];
  bool _loading = true, _table = false;
  String _error = '';
  final _search = TextEditingController();
  final _f = BatchFilters();
  SortState _sort = (key: null, dir: null);
  int _page = 1, _perPage = 10;
  FarmMoney _fmt = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _userId => widget.session.tokens.userId ?? '';
  Map<String, String> get _ctx => {'userId': _userId, 'farmId': _farmId};

  /// usePermissions().canDelete is the admin rule: anyone but plain staff.
  bool get _canDelete => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _api.get('/api/Poultry/cash-accounts', query: {'farmId': _farmId}).then((r) {
      if (mounted) setState(() => _accounts = [for (final a in rowsOf(r)) if (a['isActive'] == true) a]);
    }).catchError((_) {});
    _loadBatches();
    _api.get('/api/Supplier', query: _ctx).then((r) {
      if (mounted) setState(() => _suppliers = rowsOf(r));
    }).catchError((_) {});
    _loadFlocks();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadBatches() async {
    try {
      final r = await _api.get('/api/MainFlockBatch', query: _ctx);
      if (mounted) {
        setState(() {
          _batches = rowsOf(r);
          _page = 1;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Failed to load flock batches');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadFlocks() async {
    try {
      final r = await _api.get('/api/Flock', query: _ctx);
      if (mounted) setState(() => _flocks = rowsOf(r));
    } on ApiException {
      // the web keeps what it had
    }
    try {
      final r = await _api.get('/api/PoultryFarmSetup/opening-positions', query: _ctx);
      final p = r is Map ? (r['positions'] ?? (r['data'] is Map ? r['data']['positions'] : null)) : null;
      if (mounted) setState(() => _opening = rowsOf(p));
    } on ApiException {
      // as above
    }
  }

  List<String> get _breeds => {for (final b in _batches) if (tStr(b['breed']).isNotEmpty) tStr(b['breed'])}.toList();

  Map<int, num> get _allocated => consumedByBatch(_flocks, _opening);

  num _unallocated(Map b) => unallocatedForBatch(tNum(b['numberOfBirds']), _allocated[tIntOrNull(b['batchId'])]);

  // ------------------------------------------------------------ actions

  Future<void> _openForm([int? batchId]) async {
    final created = await showDialog<Object?>(
      context: context,
      builder: (_) => FlockBatchDialog(
        session: widget.session,
        company: widget.company,
        batchId: batchId,
        breeds: _breeds,
        suppliers: _suppliers,
        accounts: _accounts,
        money: _fmt,
      ),
    );
    if (created == null || created == false) return;
    _loadBatches();
    if (created is Map && (tIntOrNull(created['batchId']) ?? 0) > 0 && mounted) _justCreated(created);
  }

  Future<void> _justCreated(Map b) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Batch ${tStr(b['batchCode'])} created successfully'),
        content: Text('${loc(tNum(b['numberOfBirds']))} birds available. Divide them across your houses/pens now, '
            'or come back to it whenever you are ready.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("I'll Do This Later")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TColors.blue600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Divide Into Flocks'),
          ),
        ],
      ),
    );
    if (go == true) _allocate(tIntOrNull(b['batchId']) ?? 0);
  }

  Future<void> _allocate(int batchId) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BatchAllocationScreen(
        session: widget.session,
        company: widget.company,
        flocks: [for (final f in _flocks) Map<String, dynamic>.from(f)],
        source: 'Flock Purchases page',
        batchId: batchId,
      ),
    ));
    if (ok == true) {
      await _loadFlocks();
      await _loadBatches();
    }
  }

  Future<void> _delete(Map b) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var busy = false;
        return StatefulBuilder(builder: (ctx, set) => AlertDialog(
              title: const Text('Delete Flock Batch'),
              content: const Text('Are you sure you want to delete this flock batch? This action cannot be undone.'),
              actions: [
                TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: TColors.red600),
                  onPressed: busy
                      ? null
                      : () async {
                          set(() => busy = true);
                          try {
                            await _api.delete('/api/MainFlockBatch/${b['batchId']}?userId=${Uri.encodeQueryComponent(_userId)}'
                                '&farmId=${Uri.encodeQueryComponent(_farmId)}');
                            if (mounted) trackerToast(context, 'Batch deleted', description: 'The flock batch has been successfully deleted.');
                            _loadBatches();
                          } on ApiException catch (e) {
                            if (mounted) {
                              trackerToast(context, 'Delete failed',
                                  description: e.message.isNotEmpty ? e.message : 'Something went wrong. Please try again.', error: true);
                            }
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                  child: Text(busy ? 'Deleting...' : 'Delete'),
                ),
              ],
            ));
      },
    );
  }

  Future<void> _pay(Map b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => PayBatchBalanceDialog(session: widget.session, company: widget.company, batch: b, money: _fmt),
    );
    if (ok == true) _loadBatches();
  }

  void _viewFlocks(Map b) => showDialog<void>(
        context: context,
        builder: (_) => _BatchFlocksDialog(session: widget.session, company: widget.company, batch: b, offset: _offset),
      );

  // ------------------------------------------------------------ filters sheet

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        void upd(VoidCallback f) {
          set(f);
          setState(() => _page = 1);
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Filters', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            filterRow([
              FilterLabel('Date From', FilterDate(value: _f.from, hint: 'Date From', onChanged: (v) => upd(() => _f.from = v))),
              FilterLabel('Date To', FilterDate(value: _f.to, hint: 'Date To', onChanged: (v) => upd(() => _f.to = v))),
            ]),
            const SizedBox(height: 12),
            FilterLabel(
              'Breed',
              AppSelect<String>(
                value: _f.breed,
                hintText: 'Breed',
                items: [const AppSelectItem(value: 'ALL', label: 'All Breeds'), for (final b in _breeds) AppSelectItem(value: b, label: b)],
                onChanged: (v) => upd(() => _f.breed = v ?? 'ALL'),
              ),
            ),
            const SizedBox(height: 12),
            FilterLabel(
              'Status',
              AppSelect<String>(
                value: _f.status,
                hintText: 'Status',
                items: const [
                  AppSelectItem(value: 'ALL', label: 'All Statuses'),
                  AppSelectItem(value: 'active', label: 'Active'),
                  AppSelectItem(value: 'inactive', label: 'Inactive'),
                  AppSelectItem(value: 'pending', label: 'Pending'),
                ],
                onChanged: (v) => upd(() => _f.status = v ?? 'ALL'),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => upd(() {
                    _search.clear();
                    _f
                      ..search = ''
                      ..from = ''
                      ..to = ''
                      ..breed = 'ALL'
                      ..status = 'ALL';
                  }),
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Apply'))),
            ]),
          ]),
        );
      }),
    );
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/flock-batch');
    final filtered = filterBatches(_batches, _f);
    final sorted = sortRows(filtered, _sort, (b, k) => b[k]);
    final totalPages = sorted.isEmpty ? 1 : (sorted.length + _perPage - 1) ~/ _perPage;
    final page = _page.clamp(1, totalPages);
    final start = (page - 1) * _perPage;
    final pageRows = sorted.sublist(start.clamp(0, sorted.length), (start + _perPage).clamp(0, sorted.length));
    final sym = _fmt.symbol;

    final totalPrice = _batches.fold<num>(0, (s, b) => s + batchTotal(b));
    final totalPaid = _batches.fold<num>(0, (s, b) => s + tNum(b['amountPaid']));
    final purchased = _batches.fold<num>(0, (s, b) => s + tNum(b['numberOfBirds']));
    final arrived = _flocks.where((f) => f['hasArrived'] == true).fold<num>(0, (s, f) => s + tNum(f['quantity']));
    final activeBatches = _batches.where((b) => batchStatusOf(b) == 'active').length;
    final activeBirds = _flocks.where((f) => f['hasArrived'] == true && f['active'] == true).fold<num>(0, (s, f) => s + tNum(f['quantity']));
    final inactiveBirds = _flocks.where((f) => f['hasArrived'] == true && f['active'] != true).fold<num>(0, (s, f) => s + tNum(f['quantity']));

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Flock Purchases (Batches)')),
      body: RefreshIndicator(
        onRefresh: _loadBatches,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: TColors.green100, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.flutter_dash, size: 20, color: Color(0xFF16A34A)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Flock Purchases (Batches)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
                  Text('Manage your bird flock batches', style: TextStyle(fontSize: 13, color: TColors.slate600)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: TColors.blue600, minimumSize: const Size.fromHeight(44)),
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Flock Batch'),
            ),
            const SizedBox(height: 16),
            if (!_loading && _batches.isNotEmpty) ...[
              _ScoreCard(
                label: 'Total Purchase Price ($sym)',
                value: fixed2(totalPrice),
                description: 'Sum of total cost across all batches.',
                icon: Icons.attach_money,
                chip: (TColors.emerald100, TColors.emerald700),
                color: TColors.emerald600,
              ),
              _ScoreCard(
                label: 'Total Amount Paid ($sym)',
                value: fixed2(totalPaid),
                description: 'Sum of amount paid across all batches.',
                icon: Icons.account_balance_wallet_outlined,
                chip: (TColors.sky100, TColors.sky700),
                color: TColors.sky700,
              ),
              _ScoreCard(
                label: 'Number of Birds',
                value: loc(arrived),
                description: 'Birds that have arrived across all batches.',
                note: purchased > 0 && purchased != arrived ? 'of ${loc(purchased)} purchased' : null,
                icon: Icons.flutter_dash,
                chip: (TColors.blue100, const Color(0xFF1D4ED8)),
                color: const Color(0xFF1D4ED8),
              ),
              _ScoreCard(
                label: 'Active Batches',
                value: loc(activeBatches),
                description: 'Batches currently marked as active.',
                icon: Icons.check_circle_outline,
                chip: (TColors.amber100, TColors.amber700),
                color: TColors.amber600,
              ),
              const SizedBox(height: 4),
            ],
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                Expanded(
                  child: AppInput(
                    controller: _search,
                    hintText: 'Search by name or code...',
                    prefixIcon: const Icon(Icons.search, size: 18, color: TColors.slate400),
                    onChanged: (v) => setState(() {
                      _f.search = v;
                      _page = 1;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: _openFilters, icon: const Icon(Icons.filter_list, size: 16), label: const Text('Filters')),
              ]),
            ),
            const SizedBox(height: 14),
            if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
            if (_loading)
              const TCard(child: Padding(padding: EdgeInsets.all(20), child: Text('Loading flock batches...', textAlign: TextAlign.center)))
            else if (filtered.isEmpty)
              TCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Column(children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(color: TColors.slate50, shape: BoxShape.circle),
                      child: const Icon(Icons.flutter_dash, size: 32, color: TColors.slate400),
                    ),
                    const SizedBox(height: 14),
                    const Text('No flock batches found', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text('Get started by creating your first flock batch.', style: TextStyle(color: TColors.slate600)),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: TColors.blue600),
                      onPressed: () => _openForm(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Flock Batch'),
                    ),
                  ]),
                ),
              )
            else
              TCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (!_table) ...[
                    for (var i = 0; i < pageRows.length; i++) ...[_card(pageRows[i], i), const SizedBox(height: 10)],
                    ViewTableButton(onPressed: () => setState(() => _table = true)),
                  ] else ...[
                    TableViewBar(text: 'Table view', onCards: () => setState(() => _table = false)),
                    _tableView(pageRows),
                  ],
                ]),
              ),
            if (!_loading && sorted.isNotEmpty) _pagination(sorted.length, page, totalPages, start),
            if (!_loading && _batches.isNotEmpty) ...[
              const SizedBox(height: 14),
              LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - 12) / 2;
                Widget tile(String label, num v, Color color) => SizedBox(
                      width: w,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: TColors.slate500)),
                          const SizedBox(height: 4),
                          Text(loc(v), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
                        ]),
                      ),
                    );
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  tile('Total Birds', arrived, TColors.slate900),
                  tile('Total Active Birds', activeBirds, TColors.emerald600),
                  tile('Total Inactive Birds', inactiveBirds, TColors.slate600),
                  tile('Total Birds Sold', 0, TColors.amber600),
                ]);
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(Map b) => switch (batchStatusOf(b)) {
        'pending' => const TBadge('Pending', bg: TColors.amber50, fg: TColors.amber800, border: TColors.amber200),
        'active' => const TBadge('Active', bg: TColors.green100, fg: Color(0xFF166534), border: Color(0xFFBBF7D0)),
        _ => const TBadge('Inactive', bg: Color(0xFFF3F4F6), fg: Color(0xFF1F2937)),
      };

  String _supplierLabel(Map b) {
    if (tStr(b['supplierName']).isNotEmpty) return tStr(b['supplierName']);
    final s = _suppliers.where((x) => tStr(x['supplierId']) == tStr(b['supplierId']) && tStr(b['supplierId']).isNotEmpty).firstOrNull;
    return s != null && tStr(s['name']).isNotEmpty ? tStr(s['name']) : '—';
  }

  Widget _card(Map b, int i) {
    final total = batchTotal(b);
    final owed = total - tNum(b['amountPaid']);
    Widget kv(String l, String v, {Color? color}) => Wrap(spacing: 4, children: [
          Text(l, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
        ]);
    Widget action(String label, IconData icon, VoidCallback onTap, {Color? fg, Color? border}) => OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: fg ?? TColors.slate800,
            side: border == null ? null : BorderSide(color: border),
            minimumSize: const Size.fromHeight(40),
          ),
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          label: Text(label),
        );
    final actions = [
      if (owed > 0) action('Pay', Icons.account_balance_wallet_outlined, () => _pay(b), fg: TColors.emerald600, border: TColors.emerald200),
      if (_unallocated(b) > 0) action('Divide', Icons.call_split, () => _allocate(tIntOrNull(b['batchId']) ?? 0), fg: const Color(0xFF4F46E5), border: const Color(0xFFC7D2FE)),
      action('Edit', Icons.edit_outlined, () => _openForm(tIntOrNull(b['batchId']))),
      if (_canDelete) action('Delete', Icons.delete_outline, () => _delete(b), fg: TColors.red600, border: TColors.red200),
    ];
    return _BatchCard(
      key: ValueKey('batch-${b['batchId']}'),
      striped: i.isEven,
      onHeaderTap: () => _viewFlocks(b),
      header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tStr(b['batchName']), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          TBadge(tStr(b['batchCode']), bg: Colors.white, fg: TColors.slate800, border: TColors.slate200),
          Text('${loc(tNum(b['numberOfBirds']))} birds', style: const TextStyle(color: TColors.slate600)),
          Text(tStr(b['breed']), style: const TextStyle(color: TColors.slate500)),
          _statusBadge(b),
        ]),
      ]),
      details: [
        Row(children: [
          Expanded(child: kv('Start', tStr(b['startDate']).isEmpty ? '—' : trackerDate(b['startDate']))),
          Expanded(child: kv('Cost/Chick', fixed2(tNum(b['costPerChick'])))),
        ]),
        Row(children: [
          Expanded(child: kv('Total Cost', fixed2(total))),
          Expanded(child: kv('Amount Paid (${_fmt.symbol})', fixed2(tNum(b['amountPaid'])))),
        ]),
        Row(children: [
          Expanded(child: kv('Balance (${_fmt.symbol})', fixed2(owed > 0 ? owed : 0), color: owed > 0 ? TColors.red600 : TColors.emerald700)),
          Expanded(child: kv('Supplier', _supplierLabel(b))),
        ]),
        kv('Type', tStr(b['supplierType']).isEmpty ? '—' : _cap(tStr(b['supplierType']))),
      ],
      actions: LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 8) / 2;
        return Wrap(spacing: 8, runSpacing: 8, children: [for (final a in actions) SizedBox(width: w, child: a)]);
      }),
    );
  }

  Widget _tableView(List<Map> rows) {
    IconButton icon(String? tip, IconData i, VoidCallback onTap, {Color? color}) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          icon: Icon(i, size: 18, color: color),
          onPressed: onTap,
        );
    final sym = _fmt.symbol;
    return TrackerTable(
      sort: _sort,
      onSort: (k) => setState(() => _sort = toggleSort(k, _sort)),
      columns: [
        const TCol('Name', sortKey: 'name', width: 150),
        const TCol('Code', sortKey: 'code', width: 100),
        const TCol('Number of Birds', sortKey: 'numberOfBirds', width: 170),
        const TCol('Breed', sortKey: 'breed', width: 150),
        const TCol('Cost/Chick', sortKey: 'costPerChick', width: 110),
        const TCol('Total Cost', sortKey: 'totalCost', width: 120),
        TCol('Amount Paid ($sym)', sortKey: 'amountPaid', width: 140),
        TCol('Balance ($sym)', width: 120),
        const TCol('Supplier', sortKey: 'supplierName', width: 150),
        const TCol('Type', sortKey: 'supplierType', width: 100),
        const TCol('Status', sortKey: 'status', width: 100),
        const TCol('Start Date', sortKey: 'startDate', width: 150),
        const TCol('Actions', width: 150),
      ],
      rows: [
        for (final b in rows)
          [
            InkWell(onTap: () => _viewFlocks(b), child: cellText(tStr(b['batchName']), bold: true)),
            cellText(tStr(b['batchCode'])),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Icon(Icons.people_outline, size: 15, color: TColors.slate400),
                const SizedBox(width: 6),
                Text('${loc(tNum(b['numberOfBirds']))} birds', style: const TextStyle(color: TColors.slate600)),
              ]),
              Text.rich(TextSpan(children: [
                TextSpan(text: '${loc(_allocated[tIntOrNull(b['batchId'])] ?? 0)} allocated'),
                if (_unallocated(b) > 0) TextSpan(text: ' · ${loc(_unallocated(b))} unallocated', style: const TextStyle(color: TColors.amber600)),
              ]), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
            Row(children: [
              const Icon(Icons.flutter_dash, size: 15, color: TColors.slate400),
              const SizedBox(width: 6),
              Flexible(child: Text(tStr(b['breed']), style: const TextStyle(color: TColors.slate600))),
            ]),
            cellText(fixed2(tNum(b['costPerChick'])), color: TColors.slate600),
            cellText(fixed2(batchTotal(b)), bold: true),
            cellText(fixed2(tNum(b['amountPaid'])), bold: true),
            cellText(fixed2(batchOutstanding(b)), bold: true, color: batchTotal(b) - tNum(b['amountPaid']) > 0 ? TColors.red600 : TColors.emerald700),
            cellText(_supplierLabel(b), color: TColors.slate600),
            tStr(b['supplierType']).isEmpty
                ? cellText('—', color: TColors.slate400)
                : Align(
                    alignment: Alignment.centerLeft,
                    child: tStr(b['supplierType']).toLowerCase() == 'foreign'
                        ? TBadge(_cap(tStr(b['supplierType'])), bg: const Color(0xFFFAF5FF), fg: const Color(0xFF6B21A8), border: const Color(0xFFE9D5FF))
                        : TBadge(_cap(tStr(b['supplierType'])), bg: const Color(0xFFEFF6FF), fg: const Color(0xFF1E40AF), border: TColors.blue200),
                  ),
            Align(alignment: Alignment.centerLeft, child: _statusBadge(b)),
            cellText(tStr(b['startDate']).isEmpty ? '—' : fmtDateTime(b['startDate'], b, _offset), color: TColors.slate600),
            Wrap(alignment: WrapAlignment.center, children: [
              if (batchTotal(b) - tNum(b['amountPaid']) > 0) icon('Pay balance', Icons.account_balance_wallet_outlined, () => _pay(b), color: TColors.emerald600),
              if (_unallocated(b) > 0)
                icon('Divide into flocks', Icons.call_split, () => _allocate(tIntOrNull(b['batchId']) ?? 0), color: const Color(0xFF4F46E5)),
              icon(null, Icons.edit_outlined, () => _openForm(tIntOrNull(b['batchId']))),
              if (_canDelete) icon(null, Icons.delete_outline, () => _delete(b), color: TColors.red600),
            ]),
          ],
      ],
    );
  }

  Widget _pagination(int total, int page, int totalPages, int start) {
    final end = (start + _perPage).clamp(0, total);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(children: [
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 6, children: [
          Text('Showing ${start + 1} to $end of $total records', style: const TextStyle(fontSize: 13, color: TColors.slate600)),
          SizedBox(
            width: 120,
            child: AppSelect<int>(
              value: _perPage,
              items: [for (final n in salePageSizes) AppSelectItem(value: n, label: '$n / page')],
              onChanged: (v) => setState(() {
                _perPage = v ?? _perPage;
                _page = 1;
              }),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, children: [
          TextButton.icon(
            onPressed: page == 1 ? null : () => setState(() => _page = page - 1),
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Previous'),
          ),
          for (final p in pageNumbers(page, totalPages))
            p == 'ellipsis'
                ? const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('…'))
                : SizedBox(
                    width: 36,
                    height: 36,
                    child: p == page
                        ? OutlinedButton(style: OutlinedButton.styleFrom(padding: EdgeInsets.zero), onPressed: () {}, child: Text('$p'))
                        : TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            onPressed: () => setState(() => _page = p as int),
                            child: Text('$p'),
                          ),
                  ),
          TextButton.icon(
            onPressed: page == totalPages ? null : () => setState(() => _page = page + 1),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('Next'),
          ),
        ]),
      ]),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.label,
    required this.value,
    required this.description,
    this.note,
    required this.icon,
    required this.chip,
    required this.color,
  });
  final String label, value, description;
  final String? note;
  final IconData icon;
  final (Color, Color) chip;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: chip.$1, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: chip.$2),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate900))),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: color)),
          ),
          const SizedBox(height: 4),
          Text(description, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          if (note != null) Text(note!, style: const TextStyle(fontSize: 12, color: TColors.slate400)),
        ]),
      );
}

/// One batch card: open by default, amber on even rows; tapping the header
/// also opens the batch's flocks, as the web's card does.
class _BatchCard extends StatefulWidget {
  const _BatchCard({super.key, required this.striped, required this.header, required this.details, required this.actions, required this.onHeaderTap});
  final bool striped;
  final Widget header, actions;
  final List<Widget> details;
  final VoidCallback onHeaderTap;
  @override
  State<_BatchCard> createState() => _BatchCardState();
}

class _BatchCardState extends State<_BatchCard> {
  bool _open = true;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: widget.striped ? TColors.amber100 : Colors.white,
          border: Border.all(color: widget.striped ? TColors.amber300 : TColors.slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () {
              setState(() => _open = !_open);
              widget.onHeaderTap();
            },
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: widget.header),
              Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: TColors.slate400),
            ]),
          ),
          if (_open) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: TColors.slate100),
            const SizedBox(height: 12),
            for (final d in widget.details) ...[d, const SizedBox(height: 6)],
            const SizedBox(height: 6),
            widget.actions,
          ],
        ]),
      );
}

// ------------------------------------------------------------ the batch's flocks

class _BatchFlocksDialog extends StatefulWidget {
  const _BatchFlocksDialog({required this.session, required this.company, required this.batch, required this.offset});
  final Session session;
  final Company company;
  final Map batch;
  final Duration offset;
  @override
  State<_BatchFlocksDialog> createState() => _BatchFlocksDialogState();
}

class _BatchFlocksDialogState extends State<_BatchFlocksDialog> {
  List<Map>? _flocks;

  @override
  void initState() {
    super.initState();
    widget.session.farmClient
        .get('/api/Flock', query: {'userId': widget.session.tokens.userId ?? '', 'farmId': widget.company.farmId})
        .then((r) => [for (final f in rowsOf(r)) if (tStr(f['batchId']) == tStr(widget.batch['batchId'])) f])
        .catchError((_) => <Map>[])
        .then((v) {
      if (mounted) setState(() => _flocks = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fl = _flocks;
    return AlertDialog(
      scrollable: true,
      title: Text('Flocks in Batch: ${tStr(widget.batch['batchName'])}'),
      content: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('View all flocks created under this batch', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          if (fl == null)
            const Padding(padding: EdgeInsets.all(20), child: Text('Loading flocks...', textAlign: TextAlign.center))
          else if (fl.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Column(children: [
                Icon(Icons.flutter_dash, size: 48, color: TColors.slate400),
                SizedBox(height: 12),
                Text('No flocks found for this batch', style: TextStyle(color: TColors.slate600)),
              ]),
            )
          else ...[
            TrackerTable(
              columns: const [
                TCol('Name', width: 130),
                TCol('Breed', width: 120),
                TCol('Quantity', width: 110),
                TCol('Start Date', width: 150),
                TCol('Status', width: 90),
              ],
              rows: [
                for (final f in fl)
                  [
                    cellText(tStr(f['name']), bold: true),
                    cellText(tStr(f['breed'])),
                    cellText('${loc(tNum(f['quantity']))} birds'),
                    cellText(fmtDateTime(f['startDate'], f, widget.offset)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: switch (flockLifecycle(f)) {
                        'pending' => const TBadge('Pending', bg: TColors.amber100, fg: TColors.amber900, border: TColors.amber200),
                        'active' => const TBadge('Active', bg: TColors.green100, fg: Color(0xFF166534)),
                        _ => const TBadge('Inactive', bg: Color(0xFFF3F4F6), fg: Color(0xFF1F2937)),
                      },
                    ),
                  ],
              ],
            ),
            const Divider(height: 24),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Total Flocks: '),
                  TextSpan(text: '${fl.length}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ]), style: const TextStyle(fontSize: 13, color: TColors.slate600)),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Total Birds: '),
                  TextSpan(
                    text: loc(fl.where((f) => f['active'] == true && f['hasArrived'] == true).fold<num>(0, (s, f) => s + tNum(f['quantity']))),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ]), style: const TextStyle(fontSize: 13, color: TColors.slate600)),
                const Text('Active flocks past start date only', style: TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------ Pay Balance

class PayBatchBalanceDialog extends StatefulWidget {
  const PayBatchBalanceDialog({super.key, required this.session, required this.company, required this.batch, required this.money});
  final Session session;
  final Company company;
  final Map batch;
  final FarmMoney money;
  @override
  State<PayBatchBalanceDialog> createState() => _PayBatchBalanceDialogState();
}

class _PayBatchBalanceDialogState extends State<PayBatchBalanceDialog> {
  late final _amount = TextEditingController(text: _plain(batchOutstanding(widget.batch)));
  String _method = 'Cash';
  String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  bool _saving = false;

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final fmt = widget.money;
    final outstanding = batchOutstanding(widget.batch);
    final amount = num.tryParse(_amount.text) ?? 0;
    if (amount <= 0) {
      trackerToast(context, 'Enter a payment amount greater than 0.', error: true);
      return;
    }
    if (amount > outstanding) {
      trackerToast(context, 'Amount exceeds the outstanding balance (${fmt(outstanding)}).', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final r = await widget.session.farmClient.post('/api/MainFlockBatch/${widget.batch['batchId']}/pay-balance', body: {
        'FarmId': widget.company.farmId,
        'Amount': amount,
        'PaymentMethod': _method,
        'PaymentDate': _date.isEmpty ? null : _date,
        'CreatedBy': widget.session.tokens.userId ?? '',
      });
      if (!mounted) return;
      final bal = r is Map ? tNum(r['balance'] ?? (r['data'] is Map ? r['data']['balance'] : null)) : 0;
      trackerToast(context, 'Balance payment recorded', description: 'New balance: ${fmt(bal)}.');
      Navigator.pop(context, true);
      return;
    } on ApiException catch (e) {
      if (mounted) {
        trackerToast(context, 'Payment failed', description: e.message.isNotEmpty ? e.message : 'Something went wrong. Please try again.', error: true);
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.batch;
    final fmt = widget.money;
    return AlertDialog(
      scrollable: true,
      title: const Row(children: [
        Icon(Icons.account_balance_wallet_outlined, size: 20, color: TColors.emerald600),
        SizedBox(width: 8),
        Text('Pay Balance'),
      ]),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${tStr(b['batchName'])} — outstanding ${fmt(batchOutstanding(b))}', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
            child: _strip(fmt, batchTotal(b), tNum(b['amountPaid']), batchOutstanding(b), balanceRed: true),
          ),
          const SizedBox(height: 12),
          FilterLabel(
            'Payment amount (${fmt.symbol})',
            AppInput(
              controller: _amount,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            ),
          ),
          const SizedBox(height: 4),
          const Text('Capped at the outstanding balance. This posts an expense for the amount paid.',
              style: TextStyle(fontSize: 12, color: TColors.slate500)),
          const SizedBox(height: 12),
          filterRow([
            FilterLabel(
              'Method',
              AppSelect<String>(
                value: _method,
                enabled: !_saving,
                items: const [
                  AppSelectItem(value: 'Cash', label: 'Cash'),
                  AppSelectItem(value: 'MoMo', label: 'MoMo'),
                  AppSelectItem(value: 'Bank', label: 'Bank'),
                  AppSelectItem(value: 'Card', label: 'Card'),
                ],
                onChanged: (v) => setState(() => _method = v ?? _method),
              ),
            ),
            FilterLabel(
              'Payment date',
              AppDateField(
                value: DateTime.tryParse(_date),
                enabled: !_saving,
                onChanged: (v) => setState(() => _date = v == null ? '' : isoDay(v)),
              ),
            ),
          ]),
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Recording...' : 'Record payment')),
      ],
    );
  }
}

/// "Total • Paid • Balance", as both dialogs show it.
Widget _strip(FarmMoney fmt, num total, num paid, num balance, {bool balanceRed = false}) => Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'Total '),
        TextSpan(text: fmt(total), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
        const TextSpan(text: '  •  ', style: TextStyle(color: TColors.slate300)),
        const TextSpan(text: 'Paid '),
        TextSpan(text: fmt(paid), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.emerald700)),
        const TextSpan(text: '  •  ', style: TextStyle(color: TColors.slate300)),
        const TextSpan(text: 'Balance '),
        TextSpan(
          text: fmt(balance),
          style: TextStyle(fontWeight: FontWeight.w600, color: balanceRed || balance > 0 ? TColors.red600 : TColors.emerald700),
        ),
      ]),
      style: const TextStyle(fontSize: 14, color: TColors.slate600),
    );

// ------------------------------------------------------------ Add / Edit Flock Batch

/// "Add New Flock Batch" (create) and "Edit Flock Batch" (edit): the web keeps
/// two dialogs with slightly different fields, and so does this.
/// Pops with the created batch (create), true (edit) or false.
class FlockBatchDialog extends StatefulWidget {
  const FlockBatchDialog({
    super.key,
    required this.session,
    required this.company,
    this.batchId,
    required this.breeds,
    required this.suppliers,
    required this.accounts,
    required this.money,
  });
  final Session session;
  final Company company;
  final int? batchId;
  final List<String> breeds;
  final List<Map> suppliers, accounts;
  final FarmMoney money;
  @override
  State<FlockBatchDialog> createState() => _FlockBatchDialogState();
}

class _FlockBatchDialogState extends State<FlockBatchDialog> {
  bool get _edit => widget.batchId != null;
  final _name = TextEditingController(), _code = TextEditingController(), _notes = TextEditingController();
  final _birds = TextEditingController(), _cost = TextEditingController(), _total = TextEditingController();
  final _paid = TextEditingController(), _rate = TextEditingController();
  String _breed = '', _start = '', _supplierType = 'local', _supplierId = '', _account = '', _order = '', _arrival = '';
  bool _hasArrived = false, _active = true, _saving = false, _fetching = false;
  String _error = '';

  String get _userId => widget.session.tokens.userId ?? '';

  @override
  void initState() {
    super.initState();
    if (_edit) _fetch();
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _notes, _birds, _cost, _total, _paid, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _num(num v) => v == 0 ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
  static String _day(Object? v) => tStr(v).split('T').first;

  Future<void> _fetch() async {
    setState(() => _fetching = true);
    try {
      final r = await widget.session.farmClient
          .get('/api/MainFlockBatch/${widget.batchId}', query: {'userId': _userId, 'farmId': widget.company.farmId});
      final b = r is Map && r['data'] is Map ? r['data'] as Map : r as Map;
      final t = batchToggles(b['status']);
      setState(() {
        _name.text = tStr(b['batchName']);
        _code.text = tStr(b['batchCode']);
        _start = _day(b['startDate']);
        _breed = tStr(b['breed']);
        _birds.text = _num(tNum(b['numberOfBirds']));
        _cost.text = _num(tNum(b['costPerChick']));
        _total.text = _num(tNum(b['totalCost']));
        _paid.text = _num(tNum(b['amountPaid']));
        _supplierType = tStr(b['supplierType']).isEmpty ? 'local' : tStr(b['supplierType']);
        _rate.text = _num(tNum(b['dollarConversionRate']));
        _supplierId = b['supplierId'] != null ? tStr(b['supplierId']) : '';
        _hasArrived = t.hasArrived;
        _active = t.active;
        _notes.text = tStr(b['notes']);
        _order = _day(b['orderPlacementDate']);
        _arrival = _day(b['estimatedArrivalDate']);
        _account = b['poultryCashAccountId'] != null ? tStr(b['poultryCashAccountId']) : '';
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message.isNotEmpty ? e.message : 'Failed to load flock batch');
    } on TypeError {
      setState(() => _error = 'Failed to load flock batch');
    }
    if (mounted) setState(() => _fetching = false);
  }

  num get _birdsN => num.tryParse(_birds.text) ?? 0;
  num get _costN => num.tryParse(_cost.text) ?? 0;
  num get _totalN => num.tryParse(_total.text) ?? 0;
  num get _paidN => num.tryParse(_paid.text) ?? 0;

  /// patchForCostChange: a positive cost × birds replaces the total.
  void _recompute() {
    final d = deriveTotalCost(_costN, _birdsN);
    if (d != null) _total.text = _num(d);
  }

  Future<void> _submit() async {
    setState(() => _error = '');
    if (_name.text.trim().isEmpty || _code.text.trim().isEmpty || _start.isEmpty) {
      setState(() => _error = 'Please fill in all required fields');
      _formGuide(context, 'Fill in batch name, batch code, and start date — they help track birds from arrival.');
      return;
    }
    if (_birdsN <= 0) {
      setState(() => _error = 'Number of birds must be greater than 0');
      _formGuide(context, 'Enter how many birds arrived in this batch — use a number greater than zero.');
      return;
    }
    setState(() => _saving = true);
    final rate = num.tryParse(_rate.text) ?? 0;
    final total = _totalN != 0 ? _totalN : (_costN * _birdsN);
    try {
      if (_edit) {
        await widget.session.farmClient.put('/api/MainFlockBatch/${widget.batchId}', body: {
          'UserId': _userId,
          'FarmId': widget.company.farmId,
          'BatchName': _name.text,
          'BatchCode': _code.text,
          'StartDate': '${_start}T00:00:00Z',
          'Breed': _breed,
          'NumberOfBirds': _birdsN,
          'CostPerChick': _costN,
          'TotalCost': total,
          'AmountPaid': _paidN,
          'SupplierType': _supplierType,
          'SupplierId': int.tryParse(_supplierId),
          'Status': batchStatus(_hasArrived, _active),
          if (_notes.text.isNotEmpty) 'Notes': _notes.text,
          'DollarConversionRate': rate != 0 ? rate : null,
          'OrderPlacementDate': _order.isEmpty ? null : _order,
          'EstimatedArrivalDate': _arrival.isEmpty ? null : _arrival,
          'PoultryCashAccountId': int.tryParse(_account) ?? 0,
        });
        if (!mounted) return;
        trackerToast(context, 'Success!', description: 'Flock batch updated successfully.');
        Navigator.pop(context, true);
      } else {
        final r = await widget.session.farmClient.post('/api/MainFlockBatch', body: {
          'UserId': _userId,
          'FarmId': widget.company.farmId,
          'BatchName': _name.text,
          'BatchCode': _code.text,
          'StartDate': _start,
          'Breed': _breed,
          'NumberOfBirds': _birdsN,
          'CostPerChick': _costN,
          'TotalCost': total,
          'AmountPaid': _paidN,
          'SupplierType': _supplierType,
          'SupplierId': int.tryParse(_supplierId),
          'Status': batchStatus(_hasArrived, _active),
          'Notes': _notes.text.isEmpty ? null : _notes.text,
          'DollarConversionRate': rate != 0 ? rate : null,
          'OrderPlacementDate': _order.isEmpty ? null : _order,
          'EstimatedArrivalDate': _arrival.isEmpty ? null : _arrival,
          'PoultryCashAccountId': int.tryParse(_account),
        });
        if (!mounted) return;
        trackerToast(context, 'Success!', description: 'Flock batch created successfully.');
        Navigator.pop(context, r is Map ? (r['data'] is Map ? r['data'] as Map : r) : true);
      }
      return;
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message.isNotEmpty ? e.message : (_edit ? 'Failed to update flock batch' : 'Failed to create flock batch'));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _cell(String label, Widget child, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
          const SizedBox(height: 6),
          child,
          if (hint != null) ...[const SizedBox(height: 4), Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500))],
        ]),
      );

  Widget _numInput(TextEditingController c, {String? hint, bool decimal = true, VoidCallback? onChanged}) => AppInput(
        controller: c,
        hintText: hint,
        enabled: !_saving,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.]' : r'[0-9]'))],
        onChanged: (_) => setState(() => onChanged?.call()),
      );

  Widget _date(String value, ValueChanged<String> on) => AppDateField(
        value: businessDateAsDateTime(value),
        enabled: !_saving,
        onChanged: (v) => setState(() => on(v == null ? '' : isoDay(v))),
      );

  Widget _switch(bool value, ValueChanged<bool>? on, String label, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Switch(value: value, onChanged: on),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
              TextSpan(text: '  $hint', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ])),
          ),
        ]),
      );

  Widget _accountField() => _cell(
        'Pay from cash account',
        AppSelect<String>(
          value: _account.isEmpty ? 'none' : _account,
          hintText: 'None (no cash movement)',
          enabled: !_saving,
          items: [
            const AppSelectItem(value: 'none', label: 'None (no cash movement)'),
            for (final a in widget.accounts)
              AppSelectItem(value: tStr(a['poultryCashAccountId']), label: '${tStr(a['accountName'])} (${fixed2(tNum(a['currentBalance']))})'),
          ],
          onChanged: (v) => setState(() => _account = v == null || v == 'none' ? '' : v),
        ),
        hint: "The amount paid comes out of this account's balance.",
      );

  @override
  Widget build(BuildContext context) {
    final fmt = widget.money;
    final balance = (_totalN - _paidN) > 0 ? _totalN - _paidN : 0;
    final (statusLabel, statusBg, statusFg) = batchPaymentStatus(_totalN, _paidN);
    final sym = fmt.symbol;
    final suppliers = [for (final s in widget.suppliers) AppSelectItem(value: tStr(s['supplierId']), label: tStr(s['name']))];

    final identity = [
      _cell('Batch Name *', AppInput(controller: _name, enabled: !_saving, hintText: 'e.g., Batch A - Rhode Island Reds')),
      _cell('Batch Code *', AppInput(controller: _code, enabled: !_saving, hintText: 'e.g., B-001')),
      _cell('Breed', BreedPicker(value: _breed, known: widget.breeds, enabled: !_saving, onChanged: (v) => setState(() => _breed = v))),
      _cell('Start Date *', _date(_start, (v) => _start = v)),
      _cell(
        'Number of Birds *',
        _numInput(_birds, hint: 'e.g., 100', decimal: false, onChanged: () {
          if (_edit) {
            if (_costN > 0) _total.text = _num(double.parse((_costN * _birdsN).toStringAsFixed(2)));
          } else {
            _recompute();
          }
        }),
      ),
    ];

    final purchase = _edit
        ? [
            _cell('Cost Per Chick', _numInput(_cost, hint: 'e.g., 2.50', onChanged: () {
              if (_birdsN > 0) _total.text = _num(double.parse((_costN * _birdsN).toStringAsFixed(2)));
            })),
            _cell('Total Cost', _numInput(_total, hint: 'Auto-calculated')),
            _cell('Amount Paid ($sym)', _numInput(_paid, hint: 'e.g., 250.00'), hint: 'Raise this to record a further payment toward the balance.'),
            _cell(
              'Type',
              AppSelect<String>(
                value: _supplierType,
                hintText: 'Supplier Type',
                enabled: !_saving,
                items: const [AppSelectItem(value: 'local', label: 'Local'), AppSelectItem(value: 'foreign', label: 'Foreign')],
                onChanged: (v) => setState(() => _supplierType = v ?? _supplierType),
              ),
            ),
            _cell(
              'Supplier',
              AppSelect<String>(
                value: _supplierId.isEmpty ? null : _supplierId,
                hintText: widget.suppliers.isEmpty ? 'No suppliers found' : 'Select supplier',
                enabled: !_saving,
                items: suppliers,
                onChanged: (v) => setState(() => _supplierId = v ?? ''),
              ),
            ),
            _accountField(),
            _cell('Dollar Conversion Rate', _numInput(_rate, hint: 'e.g., 15.5')),
          ]
        : [
            _cell('Cost Per Chick', _numInput(_cost, onChanged: _recompute)),
            _cell('Total Cost', _numInput(_total, hint: 'Auto-calculated')),
            _cell('Amount Paid Now ($sym)', _numInput(_paid), hint: 'Part payment is fine — pay the balance later by editing the batch.'),
            _cell(
              'Type',
              AppSelect<String>(
                value: _supplierType,
                enabled: !_saving,
                items: const [AppSelectItem(value: 'local', label: 'Local'), AppSelectItem(value: 'foreign', label: 'Foreign')],
                onChanged: (v) => setState(() => _supplierType = v ?? _supplierType),
              ),
            ),
            _cell(
              'Supplier',
              AppSelect<String>(
                value: _supplierId.isEmpty ? 'none' : _supplierId,
                hintText: widget.suppliers.isEmpty ? 'No suppliers found' : 'No supplier',
                enabled: !_saving,
                items: [const AppSelectItem(value: 'none', label: 'No supplier'), ...suppliers],
                onChanged: (v) => setState(() => _supplierId = v == null || v == 'none' ? '' : v),
              ),
            ),
            _accountField(),
            if (_supplierType == 'foreign' || _rate.text.trim().isNotEmpty) _cell('Dollar Conversion Rate', _numInput(_rate)),
          ];

    return AlertDialog(
      scrollable: true,
      title: Row(children: [
        Icon(_edit ? Icons.edit_outlined : Icons.flutter_dash, size: 20, color: _edit ? TColors.blue600 : const Color(0xFF16A34A)),
        const SizedBox(width: 8),
        Flexible(child: Text(_edit ? 'Edit Flock Batch' : 'Add New Flock Batch')),
      ]),
      content: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_edit ? 'Update the flock batch information below' : 'Enter the flock batch information below',
              style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
          if (_fetching)
            const Padding(padding: EdgeInsets.all(24), child: Text('Loading flock batch...', textAlign: TextAlign.center))
          else ...[
            formSection('Batch Details', const Color(0xFF4F46E5), identity),
            const SizedBox(height: 12),
            formSection('Purchase Details', const Color(0xFF059669), purchase),
            const SizedBox(height: 12),
            formSection('Order & Delivery', const Color(0xFF0284C7), [
              _cell('Order Placement Date', _date(_order, (v) => _order = v), hint: 'When you placed the order with the supplier.'),
              _cell('Estimated Arrival Date', _date(_arrival, (v) => _arrival = v), hint: 'When the birds are expected to arrive.'),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, children: [
                  _strip(fmt, _totalN, _paidN, balance),
                  TBadge(statusLabel, bg: statusBg, fg: statusFg),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Status & Notes', const Color(0xFF16A34A), [
              _switch(_hasArrived, _saving ? null : (v) => setState(() => _hasArrived = v), 'Batch Has Arrived',
                  _edit ? '(Turn on once birds physically arrive)' : '(Leave off until birds physically arrive — status stays Pending)'),
              _switch(_active, _saving || !_hasArrived ? null : (v) => setState(() => _active = v), 'Active Batch',
                  '(Only applies once the batch has arrived)'),
              _cell('Notes (Optional)',
                  AppInput(controller: _notes, enabled: !_saving, minLines: 3, maxLines: 5, hintText: 'Add any additional notes about the batch')),
            ]),
          ],
        ]),
      ),
      actions: [
        redCancelButton(() => Navigator.pop(context, false)),
        FilledButton.icon(
          onPressed: _saving || _fetching ? null : _submit,
          icon: Icon(_edit ? Icons.save_outlined : Icons.flutter_dash, size: 16),
          label: Text(_saving ? (_edit ? 'Saving...' : 'Creating...') : (_edit ? 'Update Batch' : 'Create Batch')),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ /flock-batch/{id}

/// app/flock-batch/[id]/page.tsx: name, code, breed, start date and birds.
class FlockBatchEditScreen extends StatefulWidget {
  const FlockBatchEditScreen({super.key, required this.session, required this.company, required this.batchId});
  final Session session;
  final Company company;
  final int batchId;
  @override
  State<FlockBatchEditScreen> createState() => _FlockBatchEditScreenState();
}

class _FlockBatchEditScreenState extends State<FlockBatchEditScreen> {
  final _name = TextEditingController(), _code = TextEditingController(), _birds = TextEditingController();
  String _breed = '', _start = '', _error = '';
  bool _loading = true, _saving = false;

  String get _userId => widget.session.tokens.userId ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _birds]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.session.farmClient
          .get('/api/MainFlockBatch/${widget.batchId}', query: {'userId': _userId, 'farmId': widget.company.farmId});
      final b = r is Map && r['data'] is Map ? r['data'] as Map : r as Map;
      setState(() {
        _name.text = tStr(b['batchName']);
        _code.text = tStr(b['batchCode']);
        _start = tStr(b['startDate']).split('T').first;
        _breed = tStr(b['breed']);
        _birds.text = tStr(tIntOrNull(b['numberOfBirds']) ?? 0);
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } on TypeError {
      setState(() => _error = 'Failed to fetch flock batch');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _back() => Navigator.of(context).maybePop();

  Future<void> _submit() async {
    final birds = int.tryParse(_birds.text) ?? 0;
    if (_name.text.trim().isEmpty || _code.text.trim().isEmpty || _start.isEmpty) {
      setState(() => _error = 'Please fill in all required fields');
      return;
    }
    if (birds <= 0) {
      setState(() => _error = 'Number of birds must be greater than 0');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await widget.session.farmClient.put('/api/MainFlockBatch/${widget.batchId}', body: {
        'UserId': _userId,
        'FarmId': widget.company.farmId,
        'BatchName': _name.text,
        'BatchCode': _code.text,
        'StartDate': '${_start}T00:00:00Z',
        'Breed': _breed,
        'NumberOfBirds': birds,
      });
      if (mounted) _back();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    }
  }

  Widget _cell(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
          const SizedBox(height: 6),
          child,
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit Flock Batch')),
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          Row(children: [
            IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back)),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: TColors.green100, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.flutter_dash, size: 20, color: Color(0xFF16A34A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Edit Flock Batch', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
                Text(_loading ? 'Loading flock batch information...' : 'Update the flock batch information below',
                    style: const TextStyle(fontSize: 13, color: TColors.slate600)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 12)],
          if (_loading)
            formSection('Batch Details', const Color(0xFF4F46E5), [const LinearProgressIndicator()])
          else ...[
            formSection('Batch Details', const Color(0xFF4F46E5), [
              _cell('Batch Name *', AppInput(controller: _name, enabled: !_saving, hintText: 'e.g., Batch A - Rhode Island Reds')),
              _cell('Batch Code *', AppInput(controller: _code, enabled: !_saving, hintText: 'e.g., B-001')),
              _cell('Breed', BreedPicker(value: _breed, enabled: !_saving, onChanged: (v) => setState(() => _breed = v))),
              _cell(
                'Start Date *',
                AppDateField(
                  value: businessDateAsDateTime(_start),
                  enabled: !_saving,
                  onChanged: (v) => setState(() => _start = v == null ? '' : isoDay(v)),
                ),
              ),
              _cell(
                'Number of Birds *',
                AppInput(
                  controller: _birds,
                  enabled: !_saving,
                  hintText: 'e.g., 100',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              SizedBox(width: 120, child: redCancelButton(_saving ? null : _back)),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text(_saving ? 'Updating...' : 'Update Flock Batch'),
              ),
            ]),
          ],
        ]),
      );
}

/// `/flock-batch/{id}` from Supplier Balances and Supplier Payments.
Widget? flockBatchScreenForHref(String href, Session s, Company c) {
  final m = RegExp(r'^/flock-batch/(\d+)$').firstMatch(Uri.tryParse(href)?.path ?? '');
  return m == null ? null : FlockBatchEditScreen(session: s, company: c, batchId: int.parse(m[1]!));
}
