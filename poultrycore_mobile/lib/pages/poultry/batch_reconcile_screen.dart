import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../page_extras.dart' show fetchRows;
import '../shared/business_dates.dart' show fmtNum, isoDay;
import '../shared/reason_dialog.dart';
import 'bird_reconciliation.dart';

import 'package:poultrycore_mobile/design/tone.dart';

/// "Reconcile Birds" (413): what happened to the birds that never went into a
/// flock, as the web's components/poultry/batch-reconcile-dialog.tsx. Opened
/// from Flock Purchases (and its Farm Setup tab). A full page on the phone:
/// the web's dialog is long.
///
/// It never creates a sale, cash or revenue. A historical sale keeps its
/// price, value and what was received; only an amount still owed can become
/// one opening customer debt. Pops with true when something was posted.
class BatchReconcileScreen extends StatefulWidget {
  const BatchReconcileScreen({
    super.key,
    required this.session,
    required this.company,
    required this.batchId,
    this.batchLabel,
    this.costPerBird,
    this.source = 'Batch',
  });
  final Session session;
  final Company company;
  final int batchId;
  final String? batchLabel;

  /// The batch's purchase cost per bird, for the cost-basis note.
  final num? costPerBird;
  final String source;

  @override
  State<BatchReconcileScreen> createState() => _BatchReconcileScreenState();
}

const _kinds = [
  ReconciliationKind.mortality,
  ReconciliationKind.cull,
  ReconciliationKind.transferOut,
  ReconciliationKind.stockCorrection,
  ReconciliationKind.other,
];

num _num(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
/// toLocaleString with two decimals: "2,250.00".
String _money(num? n) {
  if (n == null) return '—';
  final parts = n.abs().toStringAsFixed(2).split('.');
  return '${n < 0 ? '-' : ''}${fmtNum(int.parse(parts[0]), 0)}.${parts[1]}';
}

/// 0 instead of "-0", and a real minus sign otherwise.
String _count(num n) => n == 0 ? '0' : n < 0 ? '−${fmtNum(-n, 0)}' : fmtNum(n, 0);

class _BatchReconcileScreenState extends State<BatchReconcileScreen> {
  Map? _detail;
  bool _loading = true;
  bool _saving = false;
  bool _posted = false;
  final List<ReconciliationLine> _rows = [];
  final _stillAlive = TextEditingController(text: '0');
  final _notes = TextEditingController();
  late String _asOf = isoDay(DateTime.now());
  String _requestKey = newRequestKey('br');
  List<(int, String)> _customers = const [];
  bool _showForm = false;

  bool get _isAdmin => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    _stillAlive.addListener(() => setState(() {}));
    _load();
    fetchRows(widget.session, widget.company, '/api/Customer').then((rows) {
      if (!mounted) return;
      setState(() => _customers = [
            for (final c in rows)
              if (_num(c['customerId'] ?? c['CustomerId']) > 0) (_num(c['customerId'] ?? c['CustomerId']).toInt(), '${c['name'] ?? c['Name'] ?? ''}'),
          ]);
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _stillAlive.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await widget.session.farmClient
          .get('/api/Poultry/bird-reconciliation/batches/${widget.batchId}', query: {'farmId': widget.company.farmId});
      if (mounted) setState(() => _detail = d is Map ? d : const {});
    } on ApiException catch (e) {
      if (mounted) _toast('Could not load the batch — ${e.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map get _s => (_detail?['summary'] is Map ? _detail!['summary'] as Map : const {});
  int get _pool => _num(_s['unallocatedpool']).toInt();

  List<Map> _list(String key) => [for (final x in (_detail?[key] is List ? _detail![key] as List : const [])) if (x is Map) x];

  BatchReconciliationPreview get _preview => previewBatchReconciliation(_pool, _rows, _num(_stillAlive.text));

  Future<void> _save() async {
    final p = _preview;
    if (p.status == 'Invalid') {
      _toast('Check the lines — ${p.problems.first}');
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await widget.session.farmClient.post(
        '/api/Poultry/bird-reconciliation/batches/${widget.batchId}/reconcile',
        body: {
          'farmId': widget.company.farmId,
          'batchId': widget.batchId,
          'asOfDate': _asOf.isEmpty ? null : _asOf,
          'lines': [for (final r in _rows) if (_num(r.quantity) > 0) r.toJson()],
          'stillUnallocatedLive': _num(_stillAlive.text).toInt(),
          'notes': _notes.text.isEmpty ? null : _notes.text,
          'source': widget.source,
          'requestKey': _requestKey,
        },
      );
      final r = res is Map ? res : const {};
      final no = '${r['reconciliationNo'] ?? ''}';
      final unexplained = _num(r['unexplainedBirds']);
      if (!mounted) return;
      _toast(r['repeated'] == true
          ? 'Already recorded — $no was saved earlier; nothing was posted twice.'
          : '${r['status'] == 'Reconciled' ? 'Batch fully accounted for' : 'Saved — some birds still unexplained'} — '
              '$no: ${fmtNum(_num(r['removedBirds']), 0)} birds explained${unexplained > 0 ? ', ${fmtNum(unexplained, 0)} still to explain' : ''}. '
              'No cash, sale or revenue was posted.');
      _posted = true;
      setState(() {
        _requestKey = newRequestKey('br');
        _rows.clear();
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) _toast('Not saved — ${e.message}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reverse(int id, String no) async {
    final reason = await showReasonDialog(context, title: 'Reverse $no?', description: 'Why is $no being reversed?', confirmLabel: 'Reverse', destructive: true);
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    try {
      await widget.session.farmClient.post('/api/Poultry/bird-reconciliation/reconciliations/$id/reverse',
          body: {'farmId': widget.company.farmId, 'reason': reason.trim()});
      if (!mounted) return;
      _toast('$no reversed — Its birds are back with the batch and any debt it created is reversed.');
      _posted = true;
      await _load();
    } on ApiException catch (e) {
      if (mounted) _toast('Not reversed — ${e.message}');
    }
  }

  void _add(ReconciliationKind kind) => setState(() {
        _showForm = true;
        _rows.add(ReconciliationLine(kind: kind, date: _asOf));
      });

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final status = '${s['status'] ?? 'FullyAccountedFor'}';
    final allAccounted = _pool == 0 && status == 'FullyAccountedFor';
    final formVisible = !allAccounted || _showForm || _rows.isNotEmpty;
    final nothingToSave = _pool == 0 && !_rows.any((r) => _num(r.quantity) > 0);
    final p = _preview;
    return PopScope(
      canPop: !_saving,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => Navigator.of(context).pop(_posted)),
          title: Row(children: [
            const Flexible(child: Text('Reconcile Birds', overflow: TextOverflow.ellipsis)),
            if (_detail != null) ...[const SizedBox(width: 8), _statusBadge(status)],
          ]),
        ),
        body: _loading && _detail == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(key: const ValueKey('reconcile-list'), padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                Text.rich(
                  TextSpan(children: [
                    if (widget.batchLabel != null) ...[
                      TextSpan(text: widget.batchLabel, style: const TextStyle(fontWeight: FontWeight.w600, color: _slate700)),
                      const TextSpan(text: ' · '),
                    ],
                    const TextSpan(text: 'Account for the birds that never went into a flock.'),
                  ]),
                  style: const TextStyle(fontSize: 13.5, color: _slate500),
                ),
                const SizedBox(height: 14),
                _whereTheyWent(s),
                const SizedBox(height: 14),
                if (!formVisible)
                  _accountedFor()
                else ...[
                  _lines(),
                  const SizedBox(height: 14),
                  _remaining(p),
                  const SizedBox(height: 10),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline, size: 16, color: _slate400),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This records history only: no cash, sale or revenue is posted.'
                        '${(widget.costPerBird ?? 0) > 0 ? ' Flocks carry the bird cost (${_money(widget.costPerBird)} × birds placed); birds sold or lost before placing are charged to no flock.' : ''}',
                        style: const TextStyle(fontSize: 12, color: _slate500),
                      ),
                    ),
                  ]),
                ],
                if (_list('reconciliations').isNotEmpty) ...[const SizedBox(height: 16), _history()],
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(_posted), child: const Text('Close'))),
                  if (formVisible) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        key: const ValueKey('reconcile-save'),
                        style: p.status == 'Reconciled' ? FilledButton.styleFrom(backgroundColor: Tone.button(const Tone.bg(0xFF059669))) : null,
                        onPressed: _saving || nothingToSave || p.status == 'Invalid' ? null : _save,
                        icon: _saving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : p.status == 'Reconciled'
                                ? const Icon(Icons.check_circle_outline, size: 18)
                                : const SizedBox.shrink(),
                        label: Text(p.status == 'Reconciled' ? 'Save — all accounted for' : 'Save (some still unexplained)'),
                      ),
                    ),
                  ],
                ]),
              ]),
      ),
    );
  }

  /// What the batch's birds became, as one bar: every bird is in exactly one
  /// of these, so the segments add up to the purchase.
  Widget _whereTheyWent(Map s) {
    final other = (_num(s['batchculled']) + _num(s['batchtransferred']) + _num(s['batchotherremovals']) - _num(s['batchadditions'])).clamp(0, 1 << 40);
    final unexplained = _num(s['unexplained']);
    final segments = [
      ('In flocks', _num(s['originallyallocated']), const Tone.bg(0xFF10B981)),
      ('Sold before placing', _num(s['batchsold']), const Tone.bg(0xFFFB923C)),
      ('Died before placing', _num(s['batchmortality']), const Tone.bg(0xFFFB7185)),
      ('Culled / transferred / other', other, const Tone.bg(0xFF94A3B8)),
      ('Waiting to be placed', _num(s['unallocatedlive']), const Tone.bg(0xFF818CF8)),
      (unexplained < 0 ? 'Over-allocated' : 'Unexplained', unexplained.abs(), unexplained < 0 ? const Tone.bg(0xFFEF4444) : const Tone.bg(0xFFFBBF24)),
    ].where((g) => g.$2 > 0).toList();
    final total = [_num(s['originalbirds']), segments.fold<num>(0, (a, g) => a + g.$2), 1].reduce((a, b) => a > b ? a : b);
    return _section(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: Text("Where the batch's birds went", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _slate900))),
        Text.rich(TextSpan(children: [
          TextSpan(text: fmtNum(_num(s['originalbirds']), 0), style: const TextStyle(fontWeight: FontWeight.w600, color: _slate900)),
          const TextSpan(text: ' birds bought'),
        ]), style: const TextStyle(fontSize: 12, color: _slate500)),
      ]),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 10,
          child: Row(children: [
            for (final g in segments) Expanded(flex: ((g.$2 / total) * 1000).round().clamp(1, 1000), child: ColoredBox(color: g.$3)),
            if (segments.fold<num>(0, (a, g) => a + g.$2) < total)
              Expanded(flex: (((total - segments.fold<num>(0, (a, g) => a + g.$2)) / total) * 1000).round().clamp(1, 1000), child: const ColoredBox(color: _slate100)),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      for (final g in segments)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: g.$3, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text(g.$1, style: const TextStyle(fontSize: 13, color: _slate600))),
            Text(fmtNum(g.$2, 0), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _slate900)),
          ]),
        ),
    ]));
  }

  Widget _accountedFor() => Container(
        key: const ValueKey('reconcile-all-accounted'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Tone.bg(0xFFECFDF5), border: Border.all(color: const Tone.line(0xFFA7F3D0)), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.check_circle_outline, size: 20, color: Tone.fg(0xFF059669)),
            SizedBox(width: 8),
            Expanded(child: Text('Every bird in this batch is accounted for', style: TextStyle(fontWeight: FontWeight.w600, color: Tone.fg(0xFF065F46)))),
          ]),
          const SizedBox(height: 4),
          const Text('There are no birds outside a flock left to explain.', style: TextStyle(fontSize: 13, color: Tone.fg(0xFF047857))),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => setState(() => _showForm = true),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Record a correction or value a historical sale'),
          ),
        ]),
      );

  Widget _lines() {
    final openingFlocks = [for (final f in _list('flocks')) if (f['hasOpeningPosition'] == true && _num(f['historicalSold']) > 0) f];
    num valuedBy(Object? flockId) => _list('historicalSales')
        .where((h) => h['status'] == 'Posted' && _num(h['flockId']) == _num(flockId))
        .fold<num>(0, (a, h) => a + _num(h['birds']));
    return _section(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('What happened to them?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _slate900)),
      const SizedBox(height: 2),
      Text.rich(
        _pool > 0
            ? TextSpan(children: [
                TextSpan(text: fmtNum(_pool, 0), style: const TextStyle(fontWeight: FontWeight.w600)),
                const TextSpan(text: ' birds are not in a flock. Add a line for each historical sale or loss.'),
              ])
            : const TextSpan(text: 'Add a line for each historical sale or correction.'),
        style: const TextStyle(fontSize: 13, color: _slate500),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 6, children: [
        OutlinedButton.icon(key: const ValueKey('reconcile-add-sale'), onPressed: () => _add(ReconciliationKind.sale), icon: const Icon(Icons.add, size: 16), label: const Text('Historical sale')),
        OutlinedButton.icon(key: const ValueKey('reconcile-add-loss'), onPressed: () => _add(ReconciliationKind.mortality), icon: const Icon(Icons.add, size: 16), label: const Text('Loss / other')),
      ]),
      const SizedBox(height: 10),
      if (_rows.isEmpty)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border.all(color: const Tone.line(0xFFCBD5E1)), borderRadius: BorderRadius.circular(8)),
          child: const Text.rich(
            TextSpan(children: [
              TextSpan(text: 'No lines yet. Use '),
              TextSpan(text: '+ Historical sale', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' for birds that were sold, or '),
              TextSpan(text: '+ Loss / other', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' for birds that died, were culled or moved.'),
            ]),
            style: TextStyle(fontSize: 13, color: _slate500),
          ),
        ),
      for (final (i, r) in _rows.indexed) ...[
        if (i > 0) const SizedBox(height: 10),
        _lineCard(i, r, openingFlocks, valuedBy),
      ],
    ]));
  }

  Widget _lineCard(int i, ReconciliationLine r, List<Map> openingFlocks, num Function(Object?) valuedBy) {
    final sale = r.kind == ReconciliationKind.sale;
    final v = sale ? saleValue(r) : null;
    return Container(
      key: ValueKey('reconcile-line-$i'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _slate50, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: _slate200, shape: BoxShape.circle),
            child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _slate700)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(sale ? 'Historical sale' : 'Loss / other', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _slate900))),
          IconButton(
            tooltip: 'Remove line',
            onPressed: () => setState(() => _rows.removeAt(i)),
            icon: const Icon(Icons.delete_outline, size: 18, color: Tone.fg(0xFFDC2626)),
          ),
        ]),
        const SizedBox(height: 6),
        sale
            ? _field('Sold from', AppSelect<int>(
                value: r.flockId ?? 0,
                items: [
                  const AppSelectItem(value: 0, label: 'Not placed in a flock'),
                  for (final f in openingFlocks)
                    AppSelectItem(
                      value: _num(f['flockId']).toInt(),
                      label: '${f['flockName']} (${fmtNum(_num(f['historicalSold']), 0)} sold, ${fmtNum(valuedBy(f['flockId']), 0)} valued)',
                    ),
                ],
                onChanged: (x) => setState(() => r.flockId = (x ?? 0) == 0 ? null : x),
              ))
            : _field('What happened', AppSelect<ReconciliationKind>(
                key: ValueKey('reconcile-kind-$i'),
                value: r.kind,
                items: [for (final k in _kinds) AppSelectItem(value: k, label: reconciliationKindLabels[k]!)],
                onChanged: (x) => setState(() => r.kind = x ?? r.kind),
              )),
        _pair(
          _field('Birds', _numField('reconcile-birds-$i', r.quantity == 0 ? '' : '${r.quantity}', (t) => r.quantity = num.tryParse(t) ?? 0, whole: true)),
          _field('Date', AppDateField(value: DateTime.tryParse(r.date ?? ''), lastDate: DateTime.now(), onChanged: (d) => setState(() => r.date = d == null ? null : isoDay(d)))),
        ),
        if (r.kind == ReconciliationKind.stockCorrection)
          _field('Direction', AppSelect<bool>(
            value: r.increase,
            items: const [
              AppSelectItem(value: false, label: 'Fewer birds than recorded'),
              AppSelectItem(value: true, label: 'More birds than recorded'),
            ],
            onChanged: (x) => setState(() => r.increase = x ?? false),
          )),
        if (sale)
          _field('Price per bird', _numField('reconcile-price-$i', r.pricePerBird == null ? '' : '${r.pricePerBird}', (t) => r.pricePerBird = t.isEmpty ? null : num.tryParse(t),
              enabled: !r.valueUnknown)),
        _field(r.kind == ReconciliationKind.other ? 'Note *' : 'Note',
            AppInput(key: ValueKey('reconcile-note-$i'), initialValue: r.note ?? '', hintText: r.kind == ReconciliationKind.other ? 'Say what happened' : 'Optional',
                onChanged: (t) => setState(() => r.note = t))),
        if (sale && v != null) ...[
          const Divider(height: 20, color: _slate200),
          InkWell(
            onTap: () => setState(() {
              r.valueUnknown = !r.valueUnknown;
              r.pricePerBird = null;
              r.amountReceived = null;
              r.createReceivable = false;
            }),
            child: Row(children: [
              SizedBox(width: 24, height: 24, child: Checkbox(value: r.valueUnknown, onChanged: (_) => setState(() {
                r.valueUnknown = !r.valueUnknown;
                r.pricePerBird = null;
                r.amountReceived = null;
                r.createReceivable = false;
              }))),
              const SizedBox(width: 6),
              const Expanded(child: Text("I don't know the value. Record the birds only", style: TextStyle(fontSize: 13, color: _slate700))),
            ]),
          ),
          if (!r.valueUnknown) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 16, children: [
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Value '),
                TextSpan(text: _money(v.total), style: const TextStyle(fontWeight: FontWeight.w600, color: _slate900)),
              ]), style: const TextStyle(fontSize: 13, color: _slate500)),
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Owed '),
                TextSpan(text: _money(v.owed), style: TextStyle(fontWeight: FontWeight.w600, color: v.owed > 0 ? const Tone.fg(0xFFB45309) : _slate900)),
              ]), style: const TextStyle(fontSize: 13, color: _slate500)),
            ]),
            _pair(
              _field('Already received', _numField('reconcile-received-$i', r.amountReceived == null ? '' : '${r.amountReceived}', (t) => r.amountReceived = t.isEmpty ? null : num.tryParse(t),
                  hint: v.total != null ? '${v.total}' : '')),
              _field('Customer${r.createReceivable ? ' *' : ''}', AppSelect<int>(
                value: r.customerId ?? 0,
                items: [const AppSelectItem(value: 0, label: '—'), for (final (id, name) in _customers) AppSelectItem(value: id, label: name)],
                onChanged: (x) => setState(() => r.customerId = (x ?? 0) == 0 ? null : x),
              )),
            ),
            _field('Reference', AppInput(initialValue: r.reference ?? '', hintText: 'Optional', onChanged: (t) => r.reference = t)),
            if (v.owed > 0)
              InkWell(
                onTap: () => setState(() => r.createReceivable = !r.createReceivable),
                child: Row(children: [
                  SizedBox(width: 24, height: 24, child: Checkbox(value: r.createReceivable, onChanged: (_) => setState(() => r.createReceivable = !r.createReceivable))),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Record the ${_money(v.owed)} still owed as an opening customer debt', style: const TextStyle(fontSize: 13, color: _slate700))),
                ]),
              ),
          ],
          if (v.problem != null && _num(r.quantity) > 0) ...[
            const SizedBox(height: 6),
            Text(v.problem!, style: const TextStyle(fontSize: 12, color: Tone.fg(0xFFB45309))),
          ],
        ],
      ]),
    );
  }

  Widget _remaining(BatchReconciliationPreview p) => _section(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _pair(
          _field('Still alive, not in a flock *', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppNumberInput(key: const ValueKey('reconcile-still-alive'), controller: _stillAlive),
            const SizedBox(height: 2),
            const Text('Birds waiting to be placed.', style: TextStyle(fontSize: 11.5, color: _slate500)),
          ])),
          _field('As of date', AppDateField(value: DateTime.tryParse(_asOf), lastDate: DateTime.now(), onChanged: (d) => setState(() => _asOf = d == null ? '' : isoDay(d)))),
        ),
        _field('Notes', AppInput(controller: _notes, hintText: 'Optional')),
        const SizedBox(height: 8),
        Container(
          key: const ValueKey('reconcile-after'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _slate50, border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('AFTER SAVING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: _slate500)),
            const SizedBox(height: 6),
            _line('Not in a flock now', _count(p.poolBefore)),
            _line('Explained by the lines', _count(-p.removed)),
            _line('Still alive', _count(-p.stillAlive)),
            const Divider(height: 12, color: _slate200),
            _line('Unexplained', _count(p.unexplained), strong: true, color: p.unexplained == 0 ? const Tone.fg(0xFF047857) : const Tone.fg(0xFFB45309)),
            if (p.saleBirds > 0) ...[
              const Divider(height: 12, color: _slate200),
              _line('Historical sales (birds)', _count(p.saleBirds)),
              _line('Historical sales value', _money(p.saleValue)),
              _line('Received', _money(p.received)),
              _line('Still owed', _money(p.owed), color: p.owed > 0 ? const Tone.fg(0xFFB45309) : null),
              if (p.receivablesToCreate > 0) _line('Customer debts to create', _count(p.receivablesToCreate)),
            ],
            for (final m in p.problems) Padding(padding: const EdgeInsets.only(top: 4), child: Text(m, style: const TextStyle(fontSize: 12, color: Tone.fg(0xFFB91C1C)))),
          ]),
        ),
      ]));

  Widget _history() {
    String day(Object? d) {
      final t = DateTime.tryParse('${d ?? ''}'.split('T').first);
      const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return t == null ? '${d ?? ''}' : '${t.day} ${m[t.month - 1]} ${t.year}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Row(children: [
        Icon(Icons.history, size: 16, color: _slate500),
        SizedBox(width: 6),
        Text('Earlier reconciliations', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _slate900)),
      ]),
      const SizedBox(height: 8),
      _section(Column(children: [
        for (final (i, r) in _list('reconciliations').indexed) ...[
          if (i > 0) const Divider(height: 16, color: _slate100),
          Opacity(
            opacity: r['status'] == 'Reversed' ? .6 : 1,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${r['reconciliationno']}',
                        style: TextStyle(fontWeight: FontWeight.w600, color: _slate900, decoration: r['status'] == 'Reversed' ? TextDecoration.lineThrough : null)),
                    _pill('${r['status']}', r['status'] == 'Reversed'
                        ? (_slate100, _slate600)
                        : r['status'] == 'Reconciled'
                            ? (const Tone.bg(0xFFECFDF5), const Tone.fg(0xFF047857))
                            : (const Tone.bg(0xFFFFFBEB), const Tone.fg(0xFFB45309))),
                    Text('${day(r['asofdate'])}${'${r['source'] ?? ''}'.isNotEmpty ? ' · ${r['source']}' : ''}', style: const TextStyle(fontSize: 12, color: _slate500)),
                  ]),
                  const SizedBox(height: 4),
                  Text('${fmtNum(_num(r['removedbirds']), 0)} explained · ${fmtNum(_num(r['stillunallocatedlive']), 0)} still alive · ${fmtNum(_num(r['unexplainedbirds']), 0)} unexplained',
                      style: const TextStyle(fontSize: 12.5, color: _slate600)),
                ]),
              ),
              if (r['status'] != 'Reversed' && _isAdmin)
                OutlinedButton.icon(
                  onPressed: () => _reverse(_num(r['reconciliationid']).toInt(), '${r['reconciliationno']}'),
                  icon: const Icon(Icons.undo, size: 16),
                  label: const Text('Reverse'),
                ),
            ]),
          ),
        ],
      ])),
    ]);
  }

  // ---- bits

  Widget _statusBadge(String status) {
    final (text, bg, fg) = switch (status) {
      'FullyAccountedFor' => ('All accounted for', const Tone.bg(0xFFECFDF5), const Tone.fg(0xFF047857)),
      'NeedsReconciliation' => ('Needs reconciliation', const Tone.bg(0xFFFFFBEB), const Tone.fg(0xFFB45309)),
      'OverAllocated' => ('Over-allocated', const Tone.bg(0xFFFEF2F2), const Tone.fg(0xFFB91C1C)),
      _ => (status, _slate50, _slate700),
    };
    return _pill(text, (bg, fg));
  }

  Widget _pill(String text, (Color, Color) c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.$1, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: c.$2)),
      );

  Widget _section(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Tone.bg(0xFFFFFFFF), border: Border.all(color: _slate200), borderRadius: BorderRadius.circular(12)),
        child: child,
      );

  Widget _field(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _slate700)),
          const SizedBox(height: 4),
          child,
        ]),
      );

  Widget _pair(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: a),
        const SizedBox(width: 10),
        Expanded(child: b),
      ]);

  Widget _numField(String key, String initial, ValueChanged<String> onChanged, {bool whole = false, bool enabled = true, String hint = ''}) => AppInput(
        key: ValueKey(key),
        initialValue: initial,
        hintText: hint,
        enabled: enabled,
        keyboardType: TextInputType.numberWithOptions(decimal: !whole),
        onChanged: (t) => setState(() => onChanged(t)),
      );

  Widget _line(String label, String value, {bool strong = false, Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: _slate600))),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: strong ? FontWeight.w600 : FontWeight.w400, color: color ?? _slate900)),
        ]),
      );
}

const _slate50 = Tone.bg(0xFFF8FAFC);
const _slate100 = Tone.bg(0xFFF1F5F9);
const _slate200 = Tone.line(0xFFE2E8F0);
const _slate400 = Tone.fg(0xFF94A3B8);
const _slate500 = Tone.fg(0xFF64748B);
const _slate600 = Tone.fg(0xFF475569);
const _slate700 = Tone.fg(0xFF334155);
const _slate900 = Tone.fg(0xFF0F172A);
