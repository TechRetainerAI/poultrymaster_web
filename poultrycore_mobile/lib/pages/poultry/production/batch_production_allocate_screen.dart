// app/batch-production-records/[id]/allocate: distribute a batch's totals
// across its included flocks (one of four pre-fill methods, then edit any
// cell), reconcile against the batch, and save or post.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../delivery/delivery_dialogs.dart' show NumBox;
import '../reports/report_routes.dart' show openAppHref;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc;
import '../trackers/tracker_widgets.dart';
import 'batch_production_logic.dart';

class BatchAllocateScreen extends StatefulWidget {
  const BatchAllocateScreen({super.key, required this.session, required this.company, required this.batchId, this.returnTo});
  final Session session;
  final Company company;
  final int batchId;

  /// Where a successful post goes (already checked by safeReturnPath).
  final String? returnTo;
  @override
  State<BatchAllocateScreen> createState() => _BatchAllocateScreenState();
}

class _BatchAllocateScreenState extends State<BatchAllocateScreen> {
  bool _loading = true, _saving = false;
  Map? _batch;
  Map<int, Map> _flocksById = {};
  List<Map> _records = [];
  List<AllocRow> _rows = [];
  String? _method;
  int _seed = 0;

  ApiClient get _api => widget.session.farmClient;
  String get _userId => widget.session.tokens.userId ?? '';
  String get _farmId => widget.company.farmId;
  bool get _readOnly => _batch != null && !const ['PendingAllocation', 'Allocated', 'Reversed'].contains(tStr(_batch!['status']));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ctx = {'userId': _userId, 'farmId': _farmId};
    Future<List<Map>> list(String path) async {
      try {
        return rowsOf(await _api.get(path, query: ctx));
      } on ApiException {
        return <Map>[];
      }
    }

    Object? b;
    String? err;
    final lists = Future.wait([list('/api/Flock'), list('/api/ProductionRecord')]);
    try {
      b = await _api.get('/api/ProductionBatchRecord/${widget.batchId}', query: {'farmId': _farmId});
    } on ApiException catch (e) {
      err = e.message;
    }
    final r = await lists;
    if (!mounted) return;
    if (b is! Map) {
      trackerToast(context, 'Could not load batch', description: err, error: true);
      setState(() => _loading = false);
      return;
    }
    final batch = b;
    var openMethod = false;
    setState(() {
      _batch = batch;
      _flocksById = {for (final f in r[0]) tIntOrNull(f['flockId']) ?? 0: f};
      _records = r[1];
      if (listOf(batch, 'allocations').isNotEmpty) {
        _rows = allocationsToRows(batch);
        _method = 'Manual';
      } else {
        _rows = buildBlankRows(batch, _flocksById, _records);
        openMethod = const ['PendingAllocation', 'Allocated'].contains(tStr(batch['status']));
      }
      _seed++;
      _loading = false;
    });
    if (openMethod) WidgetsBinding.instance.addPostFrameCallback((_) => _chooseMethodDialog());
  }

  ({List<ReconLine> lines, bool balanced}) get _recon => _batch == null ? (lines: <ReconLine>[], balanced: false) : buildReconciliation(_rows, _batch!);

  void _chooseMethod(String m) {
    final b = _batch;
    if (b == null) return;
    setState(() {
      _method = m;
      _rows = applyMethod(m, _rows.isNotEmpty ? _rows : buildBlankRows(b, _flocksById, _records), b, _records);
      _seed++;
    });
  }

  Future<void> _chooseMethodDialog() async {
    if (!mounted) return;
    final m = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose an allocation method'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Pick how the batch totals are pre-filled across the included flocks. You can edit any value afterwards.',
                style: TextStyle(fontSize: 14, color: TColors.slate500)),
            const SizedBox(height: 12),
            for (final (key, title, desc) in allocMethods)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.pop(ctx, key),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text(desc, style: const TextStyle(fontSize: 14, color: TColors.slate500)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
    if (m != null) _chooseMethod(m);
  }

  List<Map<String, Object?>> _payload() {
    final b = _batch!;
    final feeds = listOf(b, 'feeds'), meds = listOf(b, 'medications');
    num r2(num v) => double.parse(v.toStringAsFixed(2));
    return [
      for (final r in _rows)
        {
          'flockId': r.flockId,
          'flockName': r.flockName,
          'allocationMethod': _method ?? 'Manual',
          'ageInWeeks': r.ageInWeeks,
          'ageInDays': r.ageInDays,
          'birdsBefore': r.birdsBefore,
          'deaths': r.deaths,
          'birdsAfter': rowBirdsAfter(r),
          'firstPickEggs': r.p1,
          'secondPickEggs': r.p2,
          'thirdPickEggs': r.p3,
          'fourthPickEggs': r.p4,
          'fifthPickEggs': r.p5,
          'sixthPickEggs': r.p6,
          'brokenEggs': r.broken,
          'meatyEggs': r.meaty,
          'softEggs': r.soft,
          'lostEggs': r.lost,
          'totalEggs': rowTotalEggs(r),
          'eggPercentage': r2(rowEggPct(r)),
          'feedKg': feeds.fold<num>(0, (s, f) => s + (r.feedQty[tIntOrNull(f['itemId'])] ?? 0)),
          'totalFeedCost': r2(rowFeedCost(r, b)),
          'totalMedicationCost': r2(rowMedCost(r, b)),
          'totalCostOfProduction': r2(rowFeedCost(r, b) + rowMedCost(r, b)),
          'notes': r.notes.isEmpty ? null : r.notes,
          'feeds': [
            for (final f in feeds)
              {
                'batchUsageId': tIntOrNull(f['id']),
                'itemId': tIntOrNull(f['itemId']),
                'itemName': f['itemName'],
                'qty': r.feedQty[tIntOrNull(f['itemId'])] ?? 0,
                'unitCost': f['unitCost'],
                'totalCost': r2((r.feedQty[tIntOrNull(f['itemId'])] ?? 0) * tNum(f['unitCost'])),
              },
          ],
          'medications': [
            for (final m in meds)
              {
                'batchUsageId': tIntOrNull(m['id']),
                'itemId': tIntOrNull(m['itemId']),
                'itemName': m['itemName'],
                'qty': r.medQty[tIntOrNull(m['itemId'])] ?? 0,
                'unitCost': m['unitCost'],
                'totalCost': r2((r.medQty[tIntOrNull(m['itemId'])] ?? 0) * tNum(m['unitCost'])),
              },
          ],
        },
    ];
  }

  Future<Object?> _saveCall() => _api.post('/api/ProductionBatchRecord/${widget.batchId}/allocation',
      query: {'farmId': _farmId}, body: {'updatedBy': _userId, 'status': 'Allocated', 'allocations': _payload()});

  Future<void> _save() async {
    if (_batch == null) return;
    setState(() => _saving = true);
    try {
      final res = await _saveCall();
      if (!mounted) return;
      trackerToast(context, 'Allocation saved', description: 'Marked as Allocated. Post it to apply to flock records.');
      setState(() {
        if (res is Map) _batch = res;
        _saving = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Save failed', description: e.message, error: true);
    }
  }

  Future<void> _post() async {
    if (_batch == null) return;
    if (!_recon.balanced) {
      trackerToast(context, 'Allocation is not balanced', description: 'Resolve the highlighted differences before posting.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _saveCall();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Save failed', description: e.message, error: true);
      return;
    }
    try {
      await _api.post('/api/ProductionBatchRecord/${widget.batchId}/post', query: {'farmId': _farmId}, body: {'userId': _userId});
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Allocation posted', description: 'Flock records, inventory and bird counts have been updated.');
      final nav = Navigator.of(context);
      nav.pop();
      if (widget.returnTo != null) openAppHref(nav.context, widget.session, widget.company, widget.returnTo!, label: 'Farm Completeness');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Posting failed', description: e.message, error: true);
    }
  }

  void _reconDialog() {
    final recon = _recon;
    final mismatches = recon.lines.where((l) => !l.money && !l.balanced).length;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Reconciliation details'),
          _balancedBadge(recon.balanced, 'Needs attention'),
        ]),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                recon.balanced
                    ? 'Every allocatable field matches the batch totals. You can post this allocation.'
                    : '$mismatches field${mismatches == 1 ? '' : 's'} do not match the batch totals. Resolve the differences below before posting.',
                style: const TextStyle(fontSize: 14, color: TColors.slate500),
              ),
              const SizedBox(height: 12),
              TrackerTable(
                columns: const [
                  TCol('Field', width: 170),
                  TCol('Allocated Total', right: true, width: 110),
                  TCol('Total Batch', right: true, width: 100),
                  TCol('Difference', right: true, width: 100),
                  TCol('Status', right: true, width: 130),
                ],
                rows: [
                  for (final l in recon.lines)
                    [
                      cellText(l.label, color: l.balanced ? null : TColors.red700),
                      cellText(fmtRecon(l, l.allocated)),
                      cellText(fmtRecon(l, l.batchTotal)),
                      cellText('${l.diff > 0 ? '+' : ''}${fmtRecon(l, l.diff)}', bold: true, color: l.balanced ? TColors.emerald700 : TColors.red700),
                      Align(
                        alignment: Alignment.centerRight,
                        child: l.balanced
                            ? const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.check_circle_outline, size: 14, color: TColors.emerald700),
                                SizedBox(width: 4),
                                Flexible(child: Text('Reconciled', style: TextStyle(fontSize: 12, color: TColors.emerald700))),
                              ])
                            : l.money
                                ? const Text('Info only', style: TextStyle(fontSize: 12, color: TColors.amber600))
                                : const Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.warning_amber_outlined, size: 14, color: TColors.red700),
                                    SizedBox(width: 4),
                                    Flexible(child: Text('Needs attention', style: TextStyle(fontSize: 12, color: TColors.red700))),
                                  ]),
                      ),
                    ],
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Egg and quantity fields must match exactly to post. Cost lines are informational — final costs are recomputed server-side when the flock records are created.',
                style: TextStyle(fontSize: 12, color: TColors.slate500),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _balancedBadge(bool balanced, String badText) => balanced
      ? const TBadge('✓ Reconciled', bg: TColors.emerald100, fg: TColors.emerald800)
      : TBadge('⚠ $badText', bg: TColors.red600, fg: Colors.white);

  @override
  Widget build(BuildContext context) {
    final b = _batch;
    return Scaffold(
      appBar: AppBar(
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back'),
        ),
        leadingWidth: 96,
        title: const Text('Allocate Batch Production'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        const Text('Allocate Batch Production', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const Text(
          'Distribute the batch-level totals across the flocks included in this batch. The allocated totals must match the batch totals before posting.',
          style: TextStyle(fontSize: 14, color: TColors.slate500),
        ),
        if (b != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(batchNameLabel(b), style: const TextStyle(fontWeight: FontWeight.w500)),
              TBadge(tStr(b['status']), bg: Colors.white, fg: TColors.slate800, border: TColors.slate200),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 64),
            child: Text('Loading batch…', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: TColors.slate500)),
          ),
        if (!_loading && b != null && _readOnly)
          TCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'This batch is '),
                  TextSpan(text: tStr(b['status']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' and can no longer be allocated.'),
                ]),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: TColors.slate500),
              ),
            ),
          ),
        if (!_loading && b != null && !_readOnly) ..._editor(b),
      ]),
    );
  }

  List<Widget> _editor(Map b) {
    final recon = _recon;
    final byKey = {for (final l in recon.lines) l.key: l};
    final mismatches = recon.lines.where((l) => !l.money && !l.balanced).length;
    final fifth = tNum(b['fifthPickTotal']) > 0, sixth = tNum(b['sixthPickTotal']) > 0;
    final feeds = listOf(b, 'feeds'), meds = listOf(b, 'medications');
    final allocBirds = _rows.fold<num>(0, (s, r) => s + r.birdsBefore);
    String n(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

    // Column spec: header, width, cell for a row, footer recon key.
    final cols = <(String, double, Widget Function(int i, AllocRow r), String?)>[
      ('Age', 60, (i, r) => _txt(r.ageInWeeks != null ? '${r.ageInWeeks}w' : '—', muted: true, right: false), null),
      ('Birds', 70, (i, r) => _txt(loc(r.birdsBefore), muted: true), '#birds'),
      ('1st', 72, (i, r) => _num(i, 'p1', r.p1, (v) => r.p1 = v.toInt()), 'p1'),
      ('2nd', 72, (i, r) => _num(i, 'p2', r.p2, (v) => r.p2 = v.toInt()), 'p2'),
      ('3rd', 72, (i, r) => _num(i, 'p3', r.p3, (v) => r.p3 = v.toInt()), 'p3'),
      ('4th', 72, (i, r) => _num(i, 'p4', r.p4, (v) => r.p4 = v.toInt()), 'p4'),
      if (fifth) ('5th', 72, (i, r) => _num(i, 'p5', r.p5, (v) => r.p5 = v.toInt()), 'p5'),
      if (sixth) ('6th', 72, (i, r) => _num(i, 'p6', r.p6, (v) => r.p6 = v.toInt()), 'p6'),
      ('Broken', 72, (i, r) => _num(i, 'broken', r.broken, (v) => r.broken = v.toInt()), 'broken'),
      ('Meaty', 72, (i, r) => _num(i, 'meaty', r.meaty, (v) => r.meaty = v.toInt()), 'meaty'),
      ('Soft', 72, (i, r) => _num(i, 'soft', r.soft, (v) => r.soft = v.toInt()), 'soft'),
      ('Lost', 72, (i, r) => _num(i, 'lost', r.lost, (v) => r.lost = v.toInt()), 'lost'),
      ('Total', 70, (i, r) => _txt('${rowTotalEggs(r)}', bold: true), 'total'),
      ('Egg %', 70, (i, r) => _txt('${rowEggPct(r).toStringAsFixed(1)}%', muted: true), null),
      ('Deaths', 72, (i, r) => _num(i, 'deaths', r.deaths, (v) => r.deaths = v.toInt()), 'deaths'),
      ('Left', 70, (i, r) => _txt(n(rowBirdsAfter(r)), muted: true), null),
      for (final f in feeds)
        (
          '${tStr(f['itemName']).isNotEmpty ? tStr(f['itemName']) : 'Feed'} (kg)',
          120,
          (i, r) => _num(i, 'feed-${f['itemId']}', r.feedQty[tIntOrNull(f['itemId'])] ?? 0, (v) => r.feedQty[tIntOrNull(f['itemId']) ?? 0] = v, decimal: true),
          'feed-${tIntOrNull(f['itemId'])}',
        ),
      for (final m in meds)
        (
          tStr(m['itemName']).isNotEmpty ? tStr(m['itemName']) : 'Med',
          120,
          (i, r) => _num(i, 'med-${m['itemId']}', r.medQty[tIntOrNull(m['itemId'])] ?? 0, (v) => r.medQty[tIntOrNull(m['itemId']) ?? 0] = v, decimal: true),
          'med-${tIntOrNull(m['itemId'])}',
        ),
      ('Cost', 80, (i, r) => _txt((rowFeedCost(r, b) + rowMedCost(r, b)).toStringAsFixed(2), muted: true), 'prodCost'),
      ('Notes', 140, (i, r) => _notes(i, r), null),
    ];

    Widget footer(String metric) => Row(children: [
          _cell(
            140,
            metric == 'diff'
                ? Row(children: [
                    const Flexible(child: Text('Difference', overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w500))),
                    const SizedBox(width: 4),
                    Icon(recon.balanced ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                        size: 14, color: recon.balanced ? TColors.emerald600 : TColors.red600),
                  ])
                : Text(metric == 'allocated' ? 'Allocated Total' : 'Total Batch',
                    style: TextStyle(fontWeight: metric == 'batch' ? FontWeight.w400 : FontWeight.w500, color: metric == 'batch' ? TColors.slate500 : null)),
          ),
          for (final (_, w, _, key) in cols)
            _cell(w, () {
              if (key == '#birds') return _txt(metric == 'allocated' ? loc(allocBirds) : '');
              final l = key == null ? null : byKey[key];
              if (l == null) return const SizedBox.shrink();
              final v = metric == 'allocated' ? l.allocated : (metric == 'batch' ? l.batchTotal : l.diff);
              final isDiff = metric == 'diff';
              final bad = isDiff && !l.money && !l.balanced;
              return Align(
                alignment: Alignment.centerRight,
                child: Text('${isDiff && v > 0 ? '+' : ''}${fmtRecon(l, v)}',
                    style: TextStyle(
                      fontWeight: bad ? FontWeight.w600 : null,
                      color: bad ? TColors.red700 : (isDiff && !l.money ? TColors.emerald700 : (metric == 'batch' ? TColors.slate500 : null)),
                    )),
              );
            }()),
        ]);

    return [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(
          onPressed: _chooseMethodDialog,
          icon: const Icon(Icons.balance, size: 16),
          label: Text(_method != null ? 'Method: $_method' : 'Choose method'),
        ),
        _balancedBadge(recon.balanced, '$mismatches field${mismatches == 1 ? '' : 's'} need attention'),
        TextButton.icon(
          onPressed: _reconDialog,
          icon: const Icon(Icons.fact_check_outlined, size: 16),
          label: const Text('View reconciliation details'),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined, size: 16), label: const Text('Save Allocation')),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: recon.balanced ? '' : 'Resolve the highlighted differences before posting',
            child: FilledButton.icon(
              onPressed: _saving || !recon.balanced ? null : _post,
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Post Allocation'),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      TCard(
        padding: EdgeInsets.zero,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate200))),
              child: Row(children: [
                _cell(140, _head('Flock', right: false)),
                for (final (h, w, _, _) in cols) _cell(w, _head(h, right: h != 'Age' && h != 'Notes')),
              ]),
            ),
            for (var i = 0; i < _rows.length; i++)
              Container(
                key: ValueKey('alloc-row-${_rows[i].flockId}'),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate100))),
                child: Row(children: [
                  _cell(140, Text(_rows[i].flockName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500))),
                  for (final (_, w, cell, _) in cols) _cell(w, cell(i, _rows[i])),
                ]),
              ),
            Container(
              decoration: const BoxDecoration(color: TColors.slate50, border: Border(top: BorderSide(color: TColors.slate300, width: 2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [footer('allocated'), footer('batch'), footer('diff')]),
            ),
          ]),
        ),
      ),
    ];
  }

  Widget _cell(double w, Widget child) => Container(width: w, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: child);

  Widget _head(String t, {bool right = true}) => Text(t,
      textAlign: right ? TextAlign.right : TextAlign.left,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate500));

  Widget _txt(String t, {bool muted = false, bool bold = false, bool right = true}) => Text(t,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: TextStyle(fontWeight: bold ? FontWeight.w500 : null, color: muted ? TColors.slate500 : null));

  Widget _num(int i, String k, num v, void Function(num) set, {bool decimal = false}) => NumBox(
        key: ValueKey('alloc-$_seed-$i-$k'),
        value: v,
        decimal: decimal,
        onChanged: (x) => setState(() => set(x)),
      );

  Widget _notes(int i, AllocRow r) => TextFormField(
        key: ValueKey('alloc-$_seed-$i-notes'),
        initialValue: r.notes,
        decoration: const InputDecoration(isDense: true),
        onChanged: (v) => setState(() => r.notes = v),
      );
}
