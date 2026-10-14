// Egg tracker additions since the egg-class migrations (341-344):
// - EggClassLedger: components/egg-sorting/egg-class-ledger.tsx — stock per egg
//   class (Unsorted + sizes), one ledger with a running balance per class, and
//   "Record loss / adjustment" against one class. Hidden for a farm without sizes.
// - EggDrillScreen: components/egg-tracker/egg-breakdown-drill-dialog.tsx — the
//   movements behind one Breakdown line.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/business_dates.dart' show formatLongDate;
import '../production/production_logic.dart' show eggsPerCrate;
import '../reports/report_routes.dart' show openAppHref;
import 'tracker_logic.dart';
import 'tracker_widgets.dart';

/// "962 cr + 10" (crates are display only); "10 eggs" under one crate.
String cratesText(num eggs, [int? perCrate]) {
  final per = perCrate ?? eggsPerCrate;
  final n = eggs.round() < 0 ? 0 : eggs.round();
  final crates = n ~/ per;
  final loose = n % per;
  if (crates == 0) return '$loose egg${loose == 1 ? '' : 's'}';
  return loose > 0 ? '${loc(crates)} cr + $loose' : '${loc(crates)} cr';
}

String fmtCount(num n) => loc(n.round());

/// TXN_LABEL (lib/production/egg-sorting.ts).
const eggTxnLabel = {
  'Production': 'Production',
  'Sale': 'Sale',
  'Sorting Out': 'Sorted (out of Unsorted)',
  'Sorting In': 'Sorted (into size)',
  'Sorting Reversal': 'Sorting reversed',
  'InternalUse': 'Internal use',
  'Adjustment': 'Adjustment',
  'Egg Loss': 'Breakage / loss',
  'Increase': 'Adjustment (+)',
  'Decrease': 'Adjustment (−)',
  'Opening Adjustment': 'Opening balance',
  'Driver Load Out': 'Driver load-out',
  'Driver Return In': 'Driver return',
  'Restock': 'Restock',
};

/// The ledger's Movement filter.
final eggTypeFilters = <(String, String, bool Function(String))>[
  ('all', 'All movements', (_) => true),
  ('production', 'Production', (t) => t == 'Production'),
  ('sorting', 'Sorting', (t) => t.startsWith('Sorting')),
  ('sale', 'Sales', (t) => t == 'Sale' || t == 'Sale Reversal' || t.startsWith('Driver') || t.startsWith('Delivery')),
  ('internal', 'Internal use', (t) => t == 'InternalUse'),
  ('adjustment', 'Adjustments & losses', (t) => RegExp('adjust|increase|decrease|opening|restock|egg loss', caseSensitive: false).hasMatch(t)),
];

/// What happened, for Record loss / adjustment.
const eggAdjustKinds = [
  ('Breakage', 'Breakage', 'Eggs broken in the store or on the way — taken out.'),
  ('Loss', 'Loss', 'Eggs missing, spoiled or thrown away — taken out.'),
  ('Stocktake', 'Stock-take', 'Counted stock differs: + found, − missing.'),
  ('Correction', 'Correction', 'Fix a recording mistake: + or −.'),
];

String _className(Map c) => c['classKind'] == 'Unsorted' ? 'Unsorted / General' : tStr(c['name']);

class EggClassLedger extends StatefulWidget {
  const EggClassLedger({super.key, required this.session, required this.company, required this.canAdjust});
  final Session session;
  final Company company;

  /// poultry.egg-sorting.edit on the web; anyone but Staff on the phone.
  final bool canAdjust;

  @override
  State<EggClassLedger> createState() => _EggClassLedgerState();
}

class _EggClassLedgerState extends State<EggClassLedger> {
  List<Map>? _classes;
  List<Map>? _rows;
  String _classFilter = 'all', _typeFilter = 'all', _flock = 'all';
  String _from = '', _to = '';
  int _epc = 30;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  bool get _multiClass => (_classes ?? const []).any((c) => c['classKind'] == 'Size');

  @override
  void initState() {
    super.initState();
    _api
        .get('/api/Poultry/egg-sorting/settings', query: {'farmId': _farmId})
        .then((res) {
          final n = res is Map ? tIntOrNull(res['eggsPerCrate']) : null;
          if (mounted && n != null && n > 0) setState(() => _epc = n);
        })
        .catchError((Object _) {});
    _reload();
  }

  Future<void> _reload() async {
    try {
      final res = await _api.get('/api/Poultry/egg-sorting/classes', query: {'farmId': _farmId, 'includeInactive': 'true', 'ensure': 'false'});
      if (mounted) setState(() => _classes = rowsOf(res));
    } on ApiException {
      if (mounted) setState(() => _classes = []);
    }
    if (_multiClass) await _loadLedger();
  }

  Future<void> _loadLedger() async {
    setState(() => _rows = null);
    try {
      final res = await _api.get(
        '/api/Poultry/egg-sorting/ledger',
        query: {
          'farmId': _farmId,
          if (_from.isNotEmpty) 'fromDate': _from,
          if (_to.isNotEmpty) 'toDate': _to,
          if (_classFilter != 'all') 'productId': _classFilter,
        },
      );
      if (mounted) setState(() => _rows = rowsOf(res));
    } on ApiException {
      if (mounted) setState(() => _rows = []);
    }
  }

  List<(String, String)> get _flocks {
    final m = <String, String>{};
    for (final r in _rows ?? const <Map>[]) {
      final id = tIntOrNull(r['flockId']);
      if (id != null && id != 0) m['$id'] = tStr(r['flockName']).isEmpty ? 'Flock $id' : tStr(r['flockName']);
    }
    return m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => a.$2.compareTo(b.$2));
  }

  List<Map> get _shown {
    final f = eggTypeFilters.firstWhere((x) => x.$1 == _typeFilter, orElse: () => eggTypeFilters.first);
    return [
      for (final r in _rows ?? const <Map>[])
        if (f.$3(tStr(r['txnType'])) && (_flock == 'all' || '${r['flockId']}' == _flock)) r,
    ];
  }

  Future<void> _adjust() async {
    final done = await showDialog<String>(
      context: context,
      builder: (_) => _EggAdjustDialog(session: widget.session, company: widget.company, classes: _classes!),
    );
    if (done == null || !mounted) return;
    trackerToast(context, 'Egg stock adjusted', description: done);
    _reload();
  }

  Widget _tile(String label, num eggs, {bool highlight = false, bool strong = false, bool muted = false}) => Opacity(
    opacity: muted ? .6 : 1,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? TColors.amber50
            : strong
            ? TColors.emerald50
            : Colors.white,
        border: Border.all(
          color: highlight
              ? TColors.amber200
              : strong
              ? TColors.emerald200
              : TColors.slate200,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .4, color: TColors.slate500)),
          Text(
            fmtCount(eggs),
            style: TextStyle(fontSize: strong ? 18 : 15, fontWeight: strong ? FontWeight.w700 : FontWeight.w600),
          ),
          Text(cratesText(eggs, _epc), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
        ],
      ),
    ),
  );

  Widget _filter(String label, Widget child) => FilterLabel(label, child);

  @override
  Widget build(BuildContext context) {
    final classes = _classes;
    if (classes == null || !_multiClass) return const SizedBox.shrink();
    final unsorted = classes.where((c) => c['classKind'] == 'Unsorted').firstOrNull;
    final sizes = [
      for (final c in classes)
        if (c['classKind'] == 'Size' && (c['isActive'] == true || tNum(c['onHand']) != 0)) c,
    ];
    final sizedTotal = sizes.fold<num>(0, (s, c) => s + tNum(c['onHand']));
    final rows = _rows;
    final shown = _shown;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TCard(
            titleWidget: const Text('Egg Stock By Category', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            descriptionSpans: [
              const TextSpan(text: 'Production adds to Unsorted. '),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: InkWell(
                  onTap: () => openAppHref(context, widget.session, widget.company, '/poultry-egg-sorting', label: 'Egg Sorting'),
                  child: const Text(
                    'Egg Sorting',
                    style: TextStyle(fontSize: 13, color: TColors.amber700, decoration: TextDecoration.underline),
                  ),
                ),
              ),
              const TextSpan(text: ' moves Unsorted eggs into sizes; sales and internal use take from the class they name.'),
            ],
            trailing: widget.canAdjust
                ? OutlinedButton.icon(
                    onPressed: _adjust,
                    icon: const Icon(Icons.remove_shopping_cart_outlined, size: 16),
                    label: const Text('Record loss / adjustment'),
                  )
                : null,
            child: LayoutBuilder(
              builder: (context, c) {
                final w = (c.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(width: w, child: _tile('Unsorted / General', tNum(unsorted?['onHand']), highlight: true)),
                    for (final s in sizes)
                      SizedBox(
                        width: w,
                        child: _tile(tStr(s['name']), tNum(s['onHand']), muted: s['isActive'] != true),
                      ),
                    SizedBox(width: w, child: _tile('Total saleable', tNum(unsorted?['onHand']) + sizedTotal, strong: true)),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          TCard(
            title: 'Egg ledger by class',
            description:
                'Every stock movement of every egg class, with a running balance per class. Nothing is deleted: reversals appear as their own rows.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                filterRow([
                  _filter(
                    'Class',
                    AppSelect<String>(
                      value: _classFilter,
                      items: [
                        const AppSelectItem(value: 'all', label: 'All classes'),
                        for (final c in classes) AppSelectItem(value: '${c['poultryProductId']}', label: _className(c)),
                      ],
                      onChanged: (v) {
                        setState(() => _classFilter = v ?? 'all');
                        _loadLedger();
                      },
                    ),
                  ),
                  _filter(
                    'Movement',
                    AppSelect<String>(
                      value: _typeFilter,
                      items: [for (final (k, l, _) in eggTypeFilters) AppSelectItem(value: k, label: l)],
                      onChanged: (v) => setState(() => _typeFilter = v ?? 'all'),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                _filter(
                  'Flock',
                  AppSelect<String>(
                    value: _flock,
                    items: [
                      const AppSelectItem(value: 'all', label: 'All flocks'),
                      for (final (id, name) in _flocks) AppSelectItem(value: id, label: name),
                    ],
                    onChanged: (v) => setState(() => _flock = v ?? 'all'),
                  ),
                ),
                const SizedBox(height: 10),
                filterRow([
                  _filter(
                    'Recorded from',
                    FilterDate(
                      value: _from,
                      hint: 'From',
                      onChanged: (v) {
                        setState(() => _from = v);
                        _loadLedger();
                      },
                    ),
                  ),
                  _filter(
                    'Recorded to',
                    FilterDate(
                      value: _to,
                      hint: 'To',
                      onChanged: (v) {
                        setState(() => _to = v);
                        _loadLedger();
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                if (rows == null)
                  const Row(
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Loading ledger…', style: TextStyle(fontSize: 13, color: TColors.slate500)),
                    ],
                  )
                else ...[
                  TrackerTable(
                    emptyText: 'No movements match.',
                    columns: const [
                      TCol('Business date', width: 150),
                      TCol('Movement', width: 190),
                      TCol('Class', width: 100),
                      TCol('In', right: true, width: 80),
                      TCol('Out', right: true, width: 80),
                      TCol('Balance', right: true, width: 90),
                      TCol('Flock', width: 110),
                      TCol('Reference', width: 170),
                    ],
                    rows: [
                      for (final r in shown.take(500))
                        [
                          cellText(
                            formatLongDate(tStr(r['businessDate']).length >= 10 ? tStr(r['businessDate']).substring(0, 10) : r['businessDate']),
                          ),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: eggTxnLabel[tStr(r['txnType'])] ?? tStr(r['txnType'])),
                                if (tStr(r['pickNumbers']).isNotEmpty)
                                  TextSpan(
                                    text: ' (${r['pickNumbers']})',
                                    style: const TextStyle(fontSize: 12, color: TColors.slate500),
                                  ),
                              ],
                            ),
                          ),
                          cellText(r['classKind'] == 'Unsorted' ? 'Unsorted' : tStr(r['className'])),
                          cellText(tNum(r['quantityIn']) != 0 ? fmtCount(tNum(r['quantityIn'])) : '', color: TColors.emerald700),
                          cellText(tNum(r['quantityOut']) != 0 ? fmtCount(tNum(r['quantityOut'])) : '', color: TColors.rose700),
                          cellText(fmtCount(tNum(r['runningBalance'])), bold: true),
                          cellText(tStr(r['flockName'])),
                          Text(
                            '${tStr(r['reference'])}${tStr(r['customerName']).isNotEmpty ? ' · ${r['customerName']}' : ''}',
                            style: const TextStyle(fontSize: 12, color: TColors.slate600),
                          ),
                        ],
                    ],
                  ),
                  if (shown.length > 500)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Showing the latest 500 of ${loc(shown.length)} movements — narrow the dates to see older ones.',
                        style: const TextStyle(fontSize: 12, color: TColors.slate500),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Record egg loss or adjustment": against one egg class. Pops the toast's
/// description when recorded.
class _EggAdjustDialog extends StatefulWidget {
  const _EggAdjustDialog({required this.session, required this.company, required this.classes});
  final Session session;
  final Company company;
  final List<Map> classes;
  @override
  State<_EggAdjustDialog> createState() => _EggAdjustDialogState();
}

class _EggAdjustDialogState extends State<_EggAdjustDialog> {
  String? _class;
  String _kind = 'Breakage';
  final _qty = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;

  bool get _outOnly => _kind == 'Breakage' || _kind == 'Loss';
  int? get _n => int.tryParse(_qty.text);
  Map? get _target => widget.classes.where((c) => '${c['poultryProductId']}' == _class).firstOrNull;
  int get _delta => _outOnly ? -(_n ?? 0).abs() : (_n ?? 0);
  bool get _valid => _n != null && _n != 0 && (!_outOnly || _n! > 0) && _class != null && _reason.text.trim().isNotEmpty;

  @override
  void dispose() {
    _qty.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = _target;
    if (t == null) return;
    setState(() => _busy = true);
    try {
      await widget.session.farmClient.post(
        '/api/Poultry/egg-sorting/adjustments',
        body: {
          'farmId': widget.company.farmId,
          'poultryProductId': tIntOrNull(t['poultryProductId']),
          'kind': _kind,
          'quantity': _n,
          'reason': _reason.text.trim(),
        },
      );
      if (!mounted) return;
      Navigator.pop(context, '${_className(t)}: ${_delta > 0 ? '+' : '−'}${fmtCount(_delta.abs())} eggs.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      trackerToast(context, e.statusCode == 409 ? 'Not enough eggs' : 'Not adjusted', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _target;
    final hint = eggAdjustKinds.firstWhere((k) => k.$1 == _kind).$3;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: const Text('Record egg loss or adjustment'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Against one egg class. Eggs lost while grading belong on the sorting itself, not here.',
                style: TextStyle(fontSize: 13, color: TColors.slate500),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Egg class',
                AppSelect<String>(
                  value: _class,
                  hintText: 'Choose a class',
                  items: [
                    for (final c in widget.classes)
                      if (c['classKind'] == 'Unsorted' || c['isActive'] == true || tNum(c['onHand']) != 0)
                        AppSelectItem(value: '${c['poultryProductId']}', label: '${_className(c)} — ${fmtCount(tNum(c['onHand']))} on hand'),
                  ],
                  onChanged: (v) => setState(() => _class = v),
                ),
              ),
              const SizedBox(height: 10),
              FilterLabel(
                'What happened',
                AppSelect<String>(
                  value: _kind,
                  items: [for (final (k, l, _) in eggAdjustKinds) AppSelectItem(value: k, label: l)],
                  onChanged: (v) => setState(() {
                    _kind = v ?? _kind;
                    if (_outOnly) _qty.text = _qty.text.replaceAll('-', '');
                  }),
                ),
              ),
              const SizedBox(height: 4),
              Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              const SizedBox(height: 10),
              FilterLabel(
                _outOnly ? 'Eggs lost' : 'Eggs (+ found / − missing)',
                AppInput(
                  controller: _qty,
                  hintText: _outOnly ? 'e.g. 30' : 'e.g. -12',
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(_outOnly ? RegExp(r'\d') : RegExp(r'[\d-]'))],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (t != null && _n != null && _n != 0) ...[
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${fmtCount(tNum(t['onHand']))} → ${fmtCount(tNum(t['onHand']) + _delta)} eggs'),
                      if (tNum(t['onHand']) + _delta < 0)
                        const TextSpan(
                          text: ' — more than is in stock',
                          style: TextStyle(color: TColors.rose700),
                        ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 12, color: TColors.slate500),
                ),
              ],
              const SizedBox(height: 10),
              FilterLabel(
                'Reason *',
                AppInput(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 4,
                  hintText: 'e.g. tray dropped in the store',
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: !_valid || _busy ? null : _submit, child: Text(_busy ? 'Recording…' : 'Record')),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ drill

/// rowsForBucket: the rows a bucket counted — same key (the type, or "Other")
/// and same side — newest first.
List<StockLedgerRow> rowsForBucket(List<StockLedgerRow> rows, FlowBucket bucket, bool inDirection) {
  final out = [
    for (final r in rows)
      if ((r.type.trim().isEmpty ? 'Other' : r.type.trim()) == bucket.key && (inDirection ? r.inQty : r.outQty) > 0) r,
  ];
  out.sort((a, b) => b.seq.compareTo(a.seq));
  return out;
}

/// What is behind one line of the Egg tracker's Breakdown: every ledger
/// movement of that kind, green for eggs in, red for eggs out. Its total is the
/// figure that was tapped.
class EggDrillScreen extends StatefulWidget {
  const EggDrillScreen({super.key, required this.bucket, required this.inDirection, required this.rows, this.eggsPerCrate = 30});
  final FlowBucket bucket;
  final bool inDirection;

  /// The whole egg ledger; the page picks out the bucket's rows.
  final List<StockLedgerRow> rows;
  final int eggsPerCrate;

  @override
  State<EggDrillScreen> createState() => _EggDrillScreenState();
}

class _EggDrillScreenState extends State<EggDrillScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  num _qty(StockLedgerRow r) => widget.inDirection ? r.inQty : r.outQty;

  @override
  Widget build(BuildContext context) {
    final inDir = widget.inDirection;
    final all = rowsForBucket(widget.rows, widget.bucket, inDir);
    final q = _q.text.trim().toLowerCase();
    final shown = q.isEmpty
        ? all
        : [
            for (final r in all)
              if ('${r.date} ${trackerDate(r.date)} ${r.description} ${r.type}'.toLowerCase().contains(q)) r,
          ];
    final shownTotal = shown.fold<num>(0, (s, r) => s + _qty(r));
    final filtered = q.isNotEmpty;
    final band = inDir ? TColors.emerald50 : TColors.rose50;
    final bandBorder = inDir ? TColors.emerald200 : TColors.rose200;
    final ink = inDir ? const Color(0xFF064E3B) : const Color(0xFF881337);
    final amount = inDir ? TColors.emerald700 : TColors.rose700;
    final rail = inDir ? const Color(0xFF34D399) : const Color(0xFFFB7185);
    final n = all.length;

    return Scaffold(
      appBar: AppBar(title: Text(widget.bucket.label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: band,
              border: Border.all(color: bandBorder),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      widget.bucket.label,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ink),
                    ),
                    TBadge(inDir ? 'Eggs in' : 'Eggs out', bg: Colors.white, fg: amount, border: bandBorder),
                    Text(
                      '${loc(widget.bucket.amount)} eggs',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: amount),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Every ${inDir ? 'movement that added eggs' : 'movement that took eggs out'} of this kind, newest first — '
                  '$n ${n == 1 ? 'entry' : 'entries'} (${cratesText(widget.bucket.amount, widget.eggsPerCrate)}).',
                  style: TextStyle(fontSize: 12, color: ink.withValues(alpha: .8)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (all.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text('Nothing behind this figure.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
              ),
            )
          else ...[
            AppInput(
              controller: _q,
              hintText: 'Filter these $n entries…',
              prefixIcon: const Icon(Icons.search, size: 18, color: TColors.slate400),
              suffixIcon: filtered
                  ? IconButton(
                      tooltip: 'Clear filter',
                      icon: const Icon(Icons.close, size: 18, color: TColors.slate400),
                      onPressed: () => setState(_q.clear),
                    )
                  : null,
              onChanged: (_) => setState(() {}),
            ),
            if (filtered && shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('Nothing here matches “${_q.text}”.', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                ),
              ),
            const SizedBox(height: 8),
            for (final r in shown)
              Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: rail, width: 2),
                    bottom: BorderSide(color: bandBorder),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            trackerDate(r.date).toUpperCase(),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: .4, color: TColors.slate500),
                          ),
                        ),
                        Text(
                          '${inDir ? '+' : '−'}${loc(_qty(r))}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: amount),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(r.description.isEmpty ? '—' : r.description, style: const TextStyle(fontSize: 14, color: TColors.slate900)),
                    Text('Stock after: ${loc(r.balance)}', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    filtered ? '${shown.length} of $n entries shown' : '$n ${n == 1 ? 'entry' : 'entries'}',
                    style: const TextStyle(fontSize: 13, color: TColors.slate500),
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${loc(shownTotal)} eggs',
                        style: TextStyle(fontWeight: FontWeight.w600, color: amount),
                      ),
                      if (filtered)
                        TextSpan(
                          text: ' of ${loc(widget.bucket.amount)}',
                          style: const TextStyle(color: TColors.slate500),
                        ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
