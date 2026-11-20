// Poultry → Reports → Batch Bird Reconciliation (413), as the web's
// app/poultry/reports/batch-bird-reconciliation/page.tsx.
//
// For every batch: the birds bought, where they went and what is left.
//   Original = originally allocated to flocks + removed before placing
//              (sold / died / culled / transferred / other) + unallocated live
//              + unexplained
// Flock-level history is shown on the batch's drilldown and is never
// subtracted again at batch level. Admins also get "Data checks": the
// read-only check of bird movements written before 413, a dry run, and the
// links-only repair.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart' show fmtNum;
import '../batch_reconcile_screen.dart';
import '../trackers/tracker_widgets.dart';
import 'report_format.dart' show fixed2;

import 'package:poultrycore_mobile/design/tone.dart';

const reconciliationReportHref = '/poultry/reports/batch-bird-reconciliation';

int _i(Object? v) => v is num ? v.truncate() : (num.tryParse('${v ?? ''}')?.truncate() ?? 0);
num? _numOrNull(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');
String _n(Object? v) => fmtNum(_i(v), 0);
String _money(Object? v) => _numOrNull(v) == null ? '—' : fixed2(_numOrNull(v)!);
String _day(Object? v) {
  final s = '${v ?? ''}';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

List<Map> _list(Object? v) => [for (final x in v is List ? v : const []) if (x is Map) x];

/// "Other dispositions": culled + transferred + other − birds added.
int otherDispositions(Map r) => _i(r['batchCulled']) + _i(r['batchTransferred']) + _i(r['batchOtherRemovals']) - _i(r['batchAdditions']);

/// The five cards' totals over all batches.
({int original, int flockLive, int unalloc, int live, int unexplained}) reconciliationTotals(List<Map> rows) => (
      original: rows.fold(0, (t, r) => t + _i(r['originalBirds'])),
      flockLive: rows.fold(0, (t, r) => t + _i(r['flockLiveBirds'])),
      unalloc: rows.fold(0, (t, r) => t + _i(r['unallocatedLive'])),
      live: rows.fold(0, (t, r) => t + _i(r['totalLiveBirds'])),
      unexplained: rows.fold(0, (t, r) => t + _i(r['unexplained'])),
    );

const _status = {
  'FullyAccountedFor': ('Fully accounted for', Tone.bg(0xFFD1FAE5), Tone.fg(0xFF065F46)),
  'NeedsReconciliation': ('Needs reconciliation', Tone.bg(0xFFFEF3C7), Tone.fg(0xFF92400E)),
  'OverAllocated': ('More placed than bought', Tone.bg(0xFFFEE2E2), Tone.fg(0xFF991B1B)),
};

Widget _statusPill(Object? status) {
  final s = _status['$status'] ?? ('$status', TColors.slate100, TColors.slate600);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: s.$2, borderRadius: BorderRadius.circular(99)),
    child: Text(s.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: s.$3)),
  );
}

Widget _num(Object? v, {Color? color, bool bold = false}) => Align(alignment: Alignment.centerRight, child: cellText(_n(v), color: color, bold: bold));

class BatchBirdReconciliationScreen extends StatefulWidget {
  const BatchBirdReconciliationScreen({super.key, required this.session, required this.company, this.batchId});
  final Session session;
  final Company company;

  /// Opens that batch's drilldown once the rows are in (the "View source"
  /// link Initial Farm Setup shows next to already-recorded birds).
  final int? batchId;

  @override
  State<BatchBirdReconciliationScreen> createState() => _BatchBirdReconciliationScreenState();
}

class _BatchBirdReconciliationScreenState extends State<BatchBirdReconciliationScreen> {
  List<Map>? _rows;
  String? _error;
  List<Map>? _checks;
  bool _checking = false;
  bool _deepLinked = false;

  ApiClient get _api => widget.session.farmClient;
  Map<String, String> get _farm => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await _api.get('/api/Poultry/bird-reconciliation/batches', query: _farm);
      if (!mounted) return;
      setState(() => _rows = _list(r));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.isNotEmpty ? e.message : 'Could not load';
        _rows = [];
      });
    }
    final id = widget.batchId;
    if (!_deepLinked && id != null && mounted) {
      _deepLinked = true;
      final row = (_rows ?? const <Map>[]).where((r) => _i(r['batchId']) == id).firstOrNull;
      if (row != null) _drill(row);
    }
  }

  void _toast(String title, [String? description, bool error = false]) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      backgroundColor: error ? Tone.button(TColors.rose700) : null,
      content: Text(description == null || description.isEmpty ? title : '$title — $description'),
    ));
  }

  void _drill(Map row) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _BatchDrilldown(session: widget.session, company: widget.company, row: row),
      ));

  Future<void> _reconcile(Map r) async {
    final posted = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BatchReconcileScreen(
        session: widget.session,
        company: widget.company,
        batchId: _i(r['batchId']),
        batchLabel: '${r['batchCode'] ?? ''} ${r['batchName'] ?? ''}'.trim(),
        source: 'Batch Bird Reconciliation report',
      ),
    ));
    if (posted == true) _load();
  }

  Future<void> _runChecks() async {
    setState(() => _checking = true);
    try {
      final r = await _api.get('/api/Poultry/bird-reconciliation/repair/diagnose', query: _farm);
      if (mounted) setState(() => _checks = _list(r));
    } on ApiException catch (e) {
      _toast('Data check failed', e.message, true);
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _repair(bool dryRun) async {
    if (!dryRun) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Repair verified links'),
          content: const Text('Link the verified movements to their batch and flock? No bird count changes.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _checking = true);
    try {
      final res = _list(await _api.post('/api/Poultry/bird-reconciliation/repair/apply', body: {'farmId': widget.company.farmId, 'dryRun': dryRun}));
      _toast(
        dryRun ? 'Dry run: ${res.length} movement(s) would be linked' : '${res.where((r) => r['applied'] == true).length} movement(s) linked',
        dryRun ? 'Nothing was changed.' : 'Only batch / flock links were set; no bird quantity changed. Each change is logged.',
      );
      if (mounted) setState(() => _checking = false);
      if (!dryRun) await _runChecks();
      return;
    } on ApiException catch (e) {
      _toast('Repair failed', e.message, true);
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: reconciliationReportHref);
    final rows = _rows;
    final t = reconciliationTotals(rows ?? const []);
    Widget card(String label, int value, {Color color = TColors.slate900, Key? key}) => Container(
          key: key,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .4, color: TColors.slate500)),
            const SizedBox(height: 4),
            Text(fmtNum(value, 0), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: color)),
          ]),
        );
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: const Text('Batch Bird Reconciliation'),
        actions: [IconButton(key: const ValueKey('recon-report-refresh'), tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          const Text('Every bird each batch bought: in a flock, waiting to be placed, or gone — and why.',
              style: TextStyle(fontSize: 14, color: TColors.slate500)),
          const SizedBox(height: 12),
          if (_error != null) ...[TrackerBanner.error(_error!), const SizedBox(height: 12)],
          LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - 10) / 2;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              SizedBox(width: w, child: card('Birds bought', t.original)),
              SizedBox(width: w, child: card('Live in flocks', t.flockLive)),
              SizedBox(width: w, child: card('Live, not yet in a flock', t.unalloc)),
              SizedBox(width: w, child: card('Total live birds', t.live, color: TColors.emerald700)),
              SizedBox(
                width: w,
                child: card('Unexplained', t.unexplained,
                    color: t.unexplained == 0 ? TColors.emerald700 : TColors.amber700, key: const ValueKey('recon-report-unexplained')),
              ),
            ]);
          }),
          const SizedBox(height: 14),
          if (rows == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else
            TCard(
              child: TrackerTable(
                emptyText: 'No batches yet.',
                columns: const [
                  TCol('Batch', width: 150),
                  TCol('Original birds', right: true, width: 110),
                  TCol('Originally allocated', right: true, width: 130),
                  TCol('Batch-level sales', right: true, width: 120),
                  TCol('Batch-level mortality', right: true, width: 140),
                  TCol('Other dispositions', right: true, width: 130),
                  TCol('Unallocated live', right: true, width: 120),
                  TCol('Current flock live birds', right: true, width: 160),
                  TCol('Total live', right: true, width: 100),
                  TCol('Unexplained difference', right: true, width: 150),
                  TCol('Status', width: 180),
                  TCol('', width: 130),
                ],
                rows: [
                  for (final r in rows)
                    [
                      InkWell(
                        key: ValueKey('recon-row-${r['batchId']}'),
                        onTap: () => _drill(r),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          cellText('${r['batchCode'] ?? ''}', bold: true),
                          Text('${r['batchName'] ?? ''}${r['isHistorical'] == true ? ' · existing batch' : ''}',
                              style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                        ]),
                      ),
                      _num(r['originalBirds']),
                      _num(r['originallyAllocated']),
                      _num(r['batchSold']),
                      _num(r['batchMortality']),
                      _num(otherDispositions(r)),
                      _num(r['unallocatedLive']),
                      _num(r['flockLiveBirds']),
                      _num(r['totalLiveBirds'], bold: true),
                      _num(r['unexplained'],
                          color: _i(r['unexplained']) == 0 ? null : _i(r['unexplained']) < 0 ? TColors.red600 : TColors.amber700),
                      Align(alignment: Alignment.centerLeft, child: _statusPill(r['status'])),
                      if (_i(r['unallocatedPool']) > 0 || '${r['status']}' != 'FullyAccountedFor')
                        OutlinedButton.icon(
                          key: ValueKey('recon-report-reconcile-${r['batchId']}'),
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: () => _reconcile(r),
                          icon: const Icon(Icons.fact_check_outlined, size: 16),
                          label: const Text('Reconcile'),
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Birds placed in a flock and lost later are on the flock (tap a batch). Historical sales are history only: they put no cash in today '
            "and are not this period's revenue; only money still owed appears, as an opening customer debt.",
            style: TextStyle(fontSize: 12, color: TColors.slate500),
          ),
          if (widget.company.isAdmin) ...[const SizedBox(height: 16), _dataChecks()],
        ]),
      ),
    );
  }

  Widget _dataChecks() {
    final checks = _checks;
    final repairable = checks != null && checks.any((c) => c['autoRepairable'] == true);
    return Container(
      key: const ValueKey('recon-data-checks'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate200))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [
              Icon(Icons.verified_user_outlined, size: 20, color: TColors.slate500),
              SizedBox(width: 8),
              Text('Data checks', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate800)),
            ]),
            const Text('Bird movements recorded before this check existed', style: TextStyle(fontSize: 12, color: TColors.slate500)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(
                key: const ValueKey('recon-run-check'),
                onPressed: _checking ? null : _runChecks,
                child: _checking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Run check'),
              ),
              if (repairable) ...[
                OutlinedButton(key: const ValueKey('recon-dry-run'), onPressed: _checking ? null : () => _repair(true), child: const Text('Dry run')),
                FilledButton(key: const ValueKey('recon-repair'), onPressed: _checking ? null : () => _repair(false), child: const Text('Repair verified links')),
              ],
            ]),
          ]),
        ),
        if (checks != null)
          checks.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Nothing to repair.', textAlign: TextAlign.center, style: TextStyle(color: TColors.emerald700)),
                )
              : TrackerTable(
                  columns: const [
                    TCol('Check', width: 170),
                    TCol('Severity', width: 90),
                    TCol('Flock / batch', width: 130),
                    TCol('Now', width: 110),
                    TCol('Expected', width: 110),
                    TCol('Proposed', width: 150),
                    TCol('Double-count risk', width: 130),
                    TCol('Confidence', width: 100),
                    TCol('Evidence', width: 220),
                  ],
                  rows: [
                    for (final c in checks)
                      [
                        Text('${c['checkCode'] ?? ''}'.replaceAll('_', ' ').toLowerCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        _small(c['severity']),
                        _small(c['flockName'] ?? (c['batchId'] != null ? 'batch #${c['batchId']}' : '—')),
                        _small(c['currentValue']),
                        _small(c['expectedValue']),
                        _small(c['proposedCorrection']),
                        _small(c['doubleApplicationRisk']),
                        _small(c['confidence']),
                        Text('${c['evidence'] ?? ''}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                      ],
                  ],
                ),
      ]),
    );
  }
}

Widget _small(Object? v) => Text(v == null ? '' : '$v', style: const TextStyle(fontSize: 12));

/// "<code> — where the birds went": flocks, bird movements, historical sales.
class _BatchDrilldown extends StatefulWidget {
  const _BatchDrilldown({required this.session, required this.company, required this.row});
  final Session session;
  final Company company;
  final Map row;
  @override
  State<_BatchDrilldown> createState() => _BatchDrilldownState();
}

class _BatchDrilldownState extends State<_BatchDrilldown> {
  Map? _detail;

  @override
  void initState() {
    super.initState();
    widget.session.farmClient
        .get('/api/Poultry/bird-reconciliation/batches/${widget.row['batchId']}', query: {'farmId': widget.company.farmId})
        .then((r) {
      if (mounted) setState(() => _detail = r is Map ? r : const {});
    }).catchError((Object e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        backgroundColor: Tone.button(TColors.rose700),
        content: Text('Could not load the batch${e is ApiException && e.message.isNotEmpty ? ' — ${e.message}' : ''}'),
      ));
    });
  }

  Widget _section(String title, Widget table) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate800)),
          const SizedBox(height: 6),
          TCard(child: table),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final strike = TextDecoration.lineThrough;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.row['batchCode'] ?? ''} — where the birds went')),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
              _section(
                'Flocks (flock-level history)',
                TrackerTable(
                  emptyText: 'None.',
                  columns: const [
                    TCol('Flock', width: 170),
                    TCol('Originally placed', right: true, width: 120),
                    TCol('Hist. mortality', right: true, width: 110),
                    TCol('Hist. sold', right: true, width: 90),
                    TCol('Hist. culled', right: true, width: 90),
                    TCol('Hist. transferred', right: true, width: 120),
                    TCol('Hist. other', right: true, width: 90),
                    TCol('Recorded mortality', right: true, width: 130),
                    TCol('Sold / culled / moved since', right: true, width: 170),
                    TCol('Live now', right: true, width: 90),
                  ],
                  rows: [
                    for (final f in _list(d['flocks']))
                      [
                        Text.rich(TextSpan(children: [
                          TextSpan(text: '${f['flockName'] ?? ''}${f['isClosed'] == true ? ' (closed)' : ''}${f['isDeleted'] == true ? ' (deleted)' : ''}'),
                          if (_i(f['productionRecordCount']) == 0)
                            const TextSpan(text: ' no production record', style: TextStyle(fontSize: 12, color: TColors.slate400)),
                        ]), style: const TextStyle(fontSize: 13)),
                        _num(f['originallyPlaced']),
                        _num(f['historicalMortality']),
                        _num(f['historicalSold']),
                        _num(f['historicalCulled']),
                        _num(f['historicalTransferred']),
                        _num(f['historicalOther']),
                        _num(f['recordedMortality']),
                        _num(_i(f['birdsSold']) + _i(f['birdsCulled']) + _i(f['birdsTransferred'])),
                        _num(f['currentLiveBirds'], bold: true),
                      ],
                  ],
                ),
              ),
              _section(
                'Bird movements',
                TrackerTable(
                  emptyText: 'None.',
                  columns: const [
                    TCol('Date', width: 100),
                    TCol('Pool', width: 160),
                    TCol('Reason', width: 160),
                    TCol('Birds', right: true, width: 80),
                    TCol('Before → after', right: true, width: 130),
                    TCol('Source', width: 120),
                    TCol('Note', width: 200),
                  ],
                  rows: [
                    for (final m in _list(d['movements']))
                      () {
                        final faded = m['reversedById'] != null || m['reversesId'] != null;
                        final q = _i(m['quantity']);
                        final grey = faded ? TColors.slate400 : null;
                        return [
                          cellText(_day(m['date']), color: grey),
                          cellText(m['scope'] == 'BatchUnallocated' ? 'Not placed in a flock' : '${m['flockName'] ?? ''}', color: grey),
                          cellText('${m['reason'] ?? m['movementType'] ?? ''}${m['reversedById'] != null ? ' (reversed)' : ''}', color: grey),
                          Align(
                            alignment: Alignment.centerRight,
                            child: cellText('${q > 0 ? '+' : ''}${fmtNum(q, 0)}', color: grey ?? (q < 0 ? TColors.red600 : TColors.emerald700)),
                          ),
                          Align(alignment: Alignment.centerRight, child: cellText('${_n(m['birdsBefore'])} → ${_n(m['birdsAfter'])}', color: grey)),
                          Text('${m['sourceType'] ?? '—'}', style: TextStyle(fontSize: 12, color: grey)),
                          Text('${m['note'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: grey)),
                        ];
                      }(),
                  ],
                ),
              ),
              _section(
                'Historical sales',
                TrackerTable(
                  emptyText: 'None.',
                  columns: const [
                    TCol('Date', width: 100),
                    TCol('From', width: 160),
                    TCol('Birds', right: true, width: 80),
                    TCol('Price', right: true, width: 90),
                    TCol('Value', right: true, width: 100),
                    TCol('Received', right: true, width: 100),
                    TCol('Owed', right: true, width: 100),
                    TCol('Customer / debt', width: 170),
                    TCol('Status', width: 90),
                  ],
                  rows: [
                    for (final h in _list(d['historicalSales']))
                      () {
                        final reversed = h['status'] == 'Reversed';
                        final style = TextStyle(fontSize: 13, color: reversed ? TColors.slate400 : null, decoration: reversed ? strike : null);
                        Widget right(String s) => Align(alignment: Alignment.centerRight, child: Text(s, style: style));
                        return [
                          Text(_day(h['saleDate']), style: style),
                          Text('${h['flockName'] ?? 'Not placed in a flock'}', style: style),
                          right(_n(h['birds'])),
                          right(h['valueUnknown'] == true ? 'unknown' : _money(h['pricePerBird'])),
                          right(_money(h['totalValue'])),
                          right(_money(h['amountReceived'])),
                          right(_money(h['amountOwed'])),
                          Text('${h['customerName'] ?? '—'}${'${h['debtNumber'] ?? ''}'.isNotEmpty ? ' · ${h['debtNumber']}' : ''}',
                              style: style.copyWith(fontSize: 12)),
                          Text('${h['status'] ?? ''}', style: style.copyWith(fontSize: 12)),
                        ];
                      }(),
                  ],
                ),
              ),
            ]),
    );
  }
}
