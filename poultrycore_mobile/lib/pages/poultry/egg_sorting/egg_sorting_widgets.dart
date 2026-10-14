// The Egg Sorting Workspace's panels: Sizes & settings
// (components/egg-sorting/sizes-settings-panel.tsx), the change history
// (egg-sorting-audit-list.tsx) and the size reports (composition-report.tsx).

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/business_dates.dart';
import '../production/production_logic.dart' show setEggsPerCrate, eggsPerCrate;
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart' show CompactPager, LoadingLine;
import '../sales/payments_received_screen.dart' show fmtDateTimeLike;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';
import 'egg_sorting_logic.dart';

const _sm = TextStyle(fontSize: 12, color: TColors.slate500);

Widget _card({required Widget child, String? title, String? description, Widget? trailing}) => Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null || description != null)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate100))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (title != null) Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
                  if (description != null) Text(description, style: const TextStyle(fontSize: 13, color: TColors.slate600)),
                ]),
              ),
              ?trailing,
            ]),
          ),
        child,
      ]),
    );

// ------------------------------------------------------------------ audit list

/// The egg sorting audit trail (344): append-only, one sentence per change.
class EggSortingAuditList extends StatefulWidget {
  const EggSortingAuditList({super.key, required this.session, required this.company, this.title, this.description, this.entity, this.entityId, this.limit = 100, this.bare = false});
  final Session session;
  final Company company;
  final String? title, description, entity;
  final int? entityId;
  final int limit;

  /// No card chrome (inside an expanded sorting).
  final bool bare;

  @override
  State<EggSortingAuditList> createState() => _EggSortingAuditListState();
}

class _EggSortingAuditListState extends State<EggSortingAuditList> {
  List<Map>? _rows;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget.session.farmClient.get('/api/Poultry/egg-sorting/audit', query: {
      'farmId': widget.company.farmId,
      'entity': widget.entity,
      'entityId': widget.entityId,
      'limit': widget.limit,
    }).then((r) {
      if (mounted) setState(() => _rows = rowsOf(r));
    }).catchError((Object _) {
      if (mounted) {
        setState(() {
          _rows = [];
          _failed = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final body = rows == null
        ? const Padding(padding: EdgeInsets.all(12), child: LoadingLine('Loading history…'))
        : rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_failed ? 'The change history is not available yet.' : 'No changes recorded yet.',
                    style: const TextStyle(fontSize: 13, color: TColors.slate500)),
              )
            : Column(children: [
                for (var i = 0; i < rows.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: TColors.slate100))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, children: [
                        Text(auditActionLabel[rows[i]['action']] ?? tStr(rows[i]['action']),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate900)),
                        Text('${fmtDateTimeLike(rows[i]['atUtc'])}${tStr(rows[i]['actor']).isNotEmpty ? ' · ${rows[i]['actor']}' : ''}', style: _sm),
                      ]),
                      Text(describeAudit(rows[i]), style: const TextStyle(fontSize: 12, color: TColors.slate600)),
                    ]),
                  ),
              ]);
    if (widget.bare) {
      return Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
        child: body,
      );
    }
    return _card(title: widget.title, description: widget.description, child: body);
  }
}

// ------------------------------------------------------------------ sizes & settings

/// Egg sizes and sorting settings: on/off, the Daily Closing rule, eggs per
/// crate, the Unsorted price, and the sizes (rename, price, switch off — never
/// deleted). [onChanged] reloads the page's settings and classes.
class SizesSettingsPanel extends StatefulWidget {
  const SizesSettingsPanel({super.key, required this.session, required this.company, required this.settings, required this.classes, required this.canEdit, required this.onChanged});
  final Session session;
  final Company company;
  final Map? settings;
  final List<Map> classes;
  final bool canEdit;
  final VoidCallback onChanged;

  @override
  State<SizesSettingsPanel> createState() => _SizesSettingsPanelState();
}

class _SizesSettingsPanelState extends State<SizesSettingsPanel> {
  String? _busy;
  final Map<int, TextEditingController> _names = {}, _prices = {};
  final _newName = TextEditingController();
  final _crate = TextEditingController(text: '30');
  final _unsortedPrice = TextEditingController();
  int _auditKey = 0;

  List<Map> get _sizes => [for (final c in widget.classes) if (c['classKind'] == 'Size') c]
    ..sort((a, b) {
      final o = tNum(a['sortOrder']).compareTo(tNum(b['sortOrder']));
      return o != 0 ? o : tStr(a['name']).compareTo(tStr(b['name']));
    });

  @override
  void initState() {
    super.initState();
    _syncClasses();
    _syncSettings();
  }

  @override
  void didUpdateWidget(SizesSettingsPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.classes, widget.classes)) _syncClasses();
    if (!identical(old.settings, widget.settings)) _syncSettings();
  }

  void _syncClasses() {
    for (final s in _sizes) {
      final id = tIntOrNull(s['eggSizeId']) ?? 0;
      (_names[id] ??= TextEditingController()).text = tStr(s['name']);
      (_prices[id] ??= TextEditingController()).text = priceText(s['pricePerCrate']);
    }
  }

  void _syncSettings() {
    _crate.text = '${tIntOrNull(widget.settings?['eggsPerCrate']) ?? 30}';
    _unsortedPrice.text = priceText(widget.settings?['unsortedPricePerCrate']);
  }

  @override
  void dispose() {
    for (final c in [..._names.values, ..._prices.values, _newName, _crate, _unsortedPrice]) {
      c.dispose();
    }
    super.dispose();
  }

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  Future<void> _run(String key, Future<void> Function() fn, String ok) async {
    setState(() => _busy = key);
    try {
      await fn();
      if (mounted) trackerToast(context, ok);
      widget.onChanged();
      if (mounted) setState(() => _auditKey++);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Not saved', description: e.message, error: true);
    }
    if (mounted) setState(() => _busy = null);
  }

  bool get _on => widget.settings?['enableEggSorting'] == true;
  String get _policy => tStr(widget.settings?['closingPolicy']).isEmpty ? 'Warning' : tStr(widget.settings?['closingPolicy']);

  Future<void> _saveSettings(Map<String, dynamic> over, String ok) => _run('settings', () async {
        final next = {
          'enableEggSorting': _on,
          'closingPolicy': _policy,
          'eggsPerCrate': tIntOrNull(widget.settings?['eggsPerCrate']) ?? 30,
          'unsortedPricePerCrate': widget.settings?['unsortedPricePerCrate'],
          ...over,
        };
        await _api.put('/api/Poultry/egg-sorting/settings', body: {'farmId': _farmId, ...next});
        setEggsPerCrate(tIntOrNull(next['eggsPerCrate']) ?? 30);
      }, ok);

  Future<void> _saveSize(Map<String, dynamic> body) => _api.put('/api/Poultry/egg-sorting/sizes', body: {'farmId': _farmId, ...body});

  Future<void> _setPrice(int id, Object? price) =>
      _api.put('/api/Poultry/egg-sorting/sizes/$id/price', body: {'farmId': _farmId, 'pricePerCrate': price});

  @override
  Widget build(BuildContext context) {
    final can = widget.canEdit;
    final crateN = int.tryParse(_crate.text);
    final crateValid = crateN != null && crateN >= 1 && crateN <= 100;
    final up = parsePrice(_unsortedPrice.text);
    final dirty = crateValid &&
        up != 'bad' &&
        (crateN != (tIntOrNull(widget.settings?['eggsPerCrate']) ?? 30) ||
            up != (widget.settings?['unsortedPricePerCrate'] == null ? null : tNum(widget.settings!['unsortedPricePerCrate'])));
    final sizes = _sizes;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Egg sorting', style: TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
                  Text(
                    'Off: production goes into Unsorted / General eggs and you sell those directly — nothing else changes. '
                    'On: you can sort Unsorted eggs into the sizes below and sell each size separately.',
                    style: TextStyle(fontSize: 13, color: TColors.slate600),
                  ),
                ]),
              ),
              Switch(
                value: _on,
                onChanged: !can || _busy == 'settings'
                    ? null
                    : (v) => _saveSettings({'enableEggSorting': v}, v ? 'Egg sorting turned on' : 'Egg sorting turned off'),
              ),
            ]),
            const SizedBox(height: 12),
            FilterLabel(
              "Daily Closing, when the day's eggs are not all sorted",
              AppSelect<String>(
                value: _policy,
                enabled: can && _on && _busy != 'settings',
                items: [for (final e in closingPolicyText.entries) AppSelectItem(value: e.key, label: '${e.key} — ${e.value}')],
                onChanged: (v) {
                  if (v != null) _saveSettings({'closingPolicy': v}, 'Daily Closing rule saved');
                },
              ),
            ),
            const SizedBox(height: 12),
            FilterLabel(
              'Eggs per crate',
              AppInput(
                controller: _crate,
                enabled: can,
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final digits = v.replaceAll(RegExp(r'[^\d]'), '');
                  if (digits != v) _crate.text = digits;
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 4),
            const Text('Used wherever eggs are entered or shown as crates: production, sales, internal use, sorting. Stock is always kept in eggs.',
                style: TextStyle(fontSize: 11, color: TColors.slate500)),
            if (!crateValid) const Text('Between 1 and 100.', style: TextStyle(fontSize: 12, color: TColors.rose700)),
            const SizedBox(height: 12),
            FilterLabel(
              'Unsorted / General price per crate',
              AppInput(
                controller: _unsortedPrice,
                enabled: can,
                hintText: 'Not set',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 4),
            const Text('Offered as the price on a sale of unsorted eggs; you can still change it on the sale.',
                style: TextStyle(fontSize: 11, color: TColors.slate500)),
            if (up == 'bad') const Text('Enter a price of 0 or more.', style: TextStyle(fontSize: 12, color: TColors.rose700)),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: !can || !dirty || _busy == 'settings'
                  ? null
                  : () => _saveSettings({'eggsPerCrate': crateN, 'unsortedPricePerCrate': up == 'bad' ? null : up}, 'Settings saved'),
              child: const Text('Save'),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      _card(
        title: 'Egg sizes',
        description:
            'Each size is its own stock line with its own selling price. Rename, price or switch a size off; sizes are never deleted because stock and sales history refer to them.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (sizes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('No sizes yet. Turning sorting on adds the standard list.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            ),
          for (final s in sizes) _sizeRow(s, can),
          if (can)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: TColors.slate100))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: FilterLabel('New size', AppInput(controller: _newName, hintText: 'e.g. Peewee', onChanged: (_) => setState(() {})))),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _newName.text.trim().isEmpty || _busy == 'new'
                      ? null
                      : () => _run('new', () async {
                            await _saveSize({'eggSizeId': null, 'name': _newName.text.trim(), 'sortOrder': null, 'isActive': true});
                            _newName.clear();
                          }, 'Size added'),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add size'),
                ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 14),
      EggSortingAuditList(
        key: ValueKey('audit-$_auditKey'),
        session: widget.session,
        company: widget.company,
        title: 'Change history',
        description: 'Settings, sizes, sortings, sale classes and egg adjustments — who changed what, and when.',
      ),
    ]);
  }

  Widget _sizeRow(Map s, bool can) {
    final id = tIntOrNull(s['eggSizeId']) ?? 0;
    final name = _names[id]!, price = _prices[id]!;
    final nameChanged = name.text.trim() != tStr(s['name']);
    final p = parsePrice(price.text);
    final current = s['pricePerCrate'] == null ? null : tNum(s['pricePerCrate']);
    final priceChanged = p != 'bad' && p != current;
    final active = s['isActive'] == true;
    final busy = _busy == 'size:$id';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: active ? null : TColors.slate50, border: const Border(top: BorderSide(color: TColors.slate100))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'On hand '),
              TextSpan(text: fmtCount(tNum(s['onHand'])), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.slate800)),
              TextSpan(text: ' (${cratesText(tNum(s['onHand']), eggsPerCrate)})'),
            ]), style: _sm),
          ),
          const Text('Active', style: _sm),
          Switch(
            value: active,
            onChanged: !can || busy
                ? null
                : (v) => _run('size:$id', () => _saveSize({'eggSizeId': id, 'name': s['name'], 'sortOrder': s['sortOrder'], 'isActive': v}),
                    v ? '${s['name']} switched on' : '${s['name']} switched off'),
          ),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: FilterLabel('Size', AppInput(controller: name, enabled: can, onChanged: (_) => setState(() {})))),
          const SizedBox(width: 8),
          SizedBox(
            width: 112,
            child: FilterLabel(
              'Price / crate',
              AppInput(
                controller: price,
                enabled: can,
                hintText: 'Not set',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ]),
        if (p == 'bad') const Text('Price must be 0 or more', style: TextStyle(fontSize: 11, color: TColors.rose700)),
        if (nameChanged || priceChanged) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: !can || busy || name.text.trim().isEmpty
                ? null
                : () => _run('size:$id', () async {
                      if (nameChanged) await _saveSize({'eggSizeId': id, 'name': name.text.trim(), 'sortOrder': s['sortOrder'], 'isActive': active});
                      if (priceChanged) await _setPrice(id, p);
                    }, 'Size saved'),
            child: const Text('Save'),
          ),
        ],
      ]),
    );
  }
}

// ------------------------------------------------------------------ size reports

/// Egg size composition and unsorted carryover.
class CompositionReport extends StatefulWidget {
  const CompositionReport({super.key, required this.session, required this.company, required this.from, required this.to, this.flockId});
  final Session session;
  final Company company;
  final String from, to;
  final int? flockId;

  @override
  State<CompositionReport> createState() => _CompositionReportState();
}

class _CompositionReportState extends State<CompositionReport> {
  late String _from = widget.from, _to = widget.to;
  String _groupBy = 'productiondate';
  List<Map>? _rows, _carry;
  String? _error;
  int _gPage = 1, _gSize = 10, _cPage = 1, _cSize = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _rows = null;
      _carry = null;
      _error = null;
    });
    final q = {'farmId': widget.company.farmId, 'fromDate': _from, 'toDate': _to, 'flockId': widget.flockId};
    try {
      final r = await Future.wait([
        widget.session.farmClient.get('/api/Poultry/egg-sorting/composition', query: {...q, 'groupBy': _groupBy}),
        widget.session.farmClient.get('/api/Poultry/egg-sorting/carryover', query: q),
      ]);
      if (mounted) {
        setState(() {
          _rows = rowsOf(r[0]);
          _carry = rowsOf(r[1]);
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Could not load the report.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows, carry = _carry;
    // Columns: sizes in their order, then loss types.
    final cols = <String, ({String label, num sort, bool loss})>{};
    for (final r in rows ?? const <Map>[]) {
      final sized = r['lineType'] == 'SizedOutput';
      final key = sized ? 's${r['eggSizeId']}' : tStr(r['lineType']);
      cols.putIfAbsent(key, () => (label: lineTypeLabel(r['lineType'], r['sizeName']), sort: sized ? tNum(r['sizeSort']) : 100000 + key.length, loss: !sized));
    }
    final columns = cols.entries.toList()..sort((a, b) => a.value.sort.compareTo(b.value.sort));
    final showFlock = _groupBy != 'flock' && (rows ?? const <Map>[]).any((r) => tStr(r['flockName']).isNotEmpty);
    final showCarryFlock = (carry ?? const <Map>[]).any((c) => tStr(c['flockName']).isNotEmpty);
    final groups = <String, ({String key, String label, String sort, String flock, Map<String, num> cells, List<num> agg})>{};
    for (final r in rows ?? const <Map>[]) {
      final k = tStr(r['groupKey']);
      final g = groups.putIfAbsent(
          k, () => (key: k, label: tStr(r['groupLabel']), sort: tStr(r['groupSort']), flock: tStr(r['flockName']), cells: <String, num>{}, agg: [0, 0]));
      final col = r['lineType'] == 'SizedOutput' ? 's${r['eggSizeId']}' : tStr(r['lineType']);
      g.cells[col] = (g.cells[col] ?? 0) + tNum(r['quantity']);
      g.agg[0] += tNum(r['quantity']);
      if (tNum(r['combinedSessions']) > g.agg[1]) g.agg[1] = tNum(r['combinedSessions']);
    }
    final glist = groups.values.toList()
      ..sort((a, b) {
        final c = _groupBy.endsWith('date') ? b.sort.compareTo(a.sort) : _numericCompare(a.sort, b.sort);
        return c != 0 ? c : a.flock.compareTo(b.flock);
      });
    final anyCombined = glist.any((g) => g.agg[1] > 0);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            filterRow([
              FilterLabel('From', FilterDate(value: _from, hint: 'From', onChanged: (v) {
                setState(() => _from = v);
                _load();
              })),
              FilterLabel('To', FilterDate(value: _to, hint: 'To', onChanged: (v) {
                setState(() => _to = v);
                _load();
              })),
            ]),
            const SizedBox(height: 10),
            FilterLabel(
              'Size composition by',
              AppSelect<String>(
                value: _groupBy,
                items: [for (final (k, l) in compositionGroups) AppSelectItem(value: k, label: l)],
                onChanged: (v) {
                  setState(() => _groupBy = v ?? _groupBy);
                  _load();
                },
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      if (_error != null) TrackerBanner.error(_error!),
      if (rows == null && _error == null) const LoadingLine('Loading…'),
      if (rows != null)
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _groupBy == 'pick'
                    ? 'Only sortings recorded pick by pick are counted here. Eggs sorted as a combined pool are left out, because their sizes cannot honestly be attributed to one pick.'
                    : anyCombined
                        ? 'Includes combined sortings, shared across their source days by quantity. Percentages are of all eggs sorted in the group, losses included.'
                        : 'Percentages are of all eggs sorted in the group, losses included.',
                style: const TextStyle(fontSize: 12, color: TColors.slate600),
              ),
            ),
            if (glist.isEmpty)
              const Padding(padding: EdgeInsets.all(12), child: Text('No posted sorting in this period.', style: TextStyle(fontSize: 13, color: TColors.slate500))),
            for (final g in pageSlice(glist, _gPage, _gSize))
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: TColors.slate100))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(g.label, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                          if (g.agg[1] > 0 && _groupBy != 'pick') const TBadge('incl. combined', bg: TColors.slate100, fg: TColors.slate600),
                        ]),
                        if (showFlock && g.flock.isNotEmpty) Text(g.flock, style: _sm),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text('Sorted', style: _sm),
                      Text(fmtCount(g.agg[0]), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ]),
                  ]),
                  const SizedBox(height: 8),
                  LayoutBuilder(builder: (context, c) {
                    final w = (c.maxWidth - 12) / 3;
                    return Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final col in columns)
                        if ((g.cells[col.key] ?? 0) != 0)
                          SizedBox(
                            width: w,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: col.value.loss ? const Color(0xFFFFF1F2) : TColors.slate50,
                                border: Border.all(color: col.value.loss ? TColors.rose200 : TColors.slate200),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(col.value.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: col.value.loss ? TColors.rose700 : TColors.slate500)),
                                Text(pct(g.cells[col.key]!, g.agg[0]), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                Text(fmtCount(g.cells[col.key]!), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                              ]),
                            ),
                          ),
                    ]);
                  }),
                ]),
              ),
            CompactPager(
              total: glist.length,
              page: _gPage,
              pageSize: _gSize,
              onPage: (p) => setState(() => _gPage = p),
              onPageSize: (s) => setState(() {
                _gSize = s;
                _gPage = 1;
              }),
            ),
          ]),
        ),
      if (carry != null) ...[
        const SizedBox(height: 14),
        _card(
          title: 'Unsorted carryover',
          description: 'Per production date${showCarryFlock ? ' and flock' : ''}: saleable eggs (collected less broken, meaty, soft and lost) = sorted + still unsorted. '
              'Eggs sold or used unsorted also show as unsorted here.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (carry.isEmpty)
              const Padding(padding: EdgeInsets.all(12), child: Text('No production in this period.', style: TextStyle(fontSize: 13, color: TColors.slate500))),
            for (final c in pageSlice(carry, _cPage, _cSize))
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: TColors.slate100))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(formatLongDate(tStr(c['productionDate']).length >= 10 ? tStr(c['productionDate']).substring(0, 10) : c['productionDate']),
                            style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                        if (showCarryFlock && tStr(c['flockName']).isNotEmpty) Text(tStr(c['flockName']), style: _sm),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text('Not sorted', style: _sm),
                      Text(fmtCount(tNum(c['leftUnsorted'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ]),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: _kv('Collected', fmtCount(tNum(c['gross'])))),
                    const SizedBox(width: 12),
                    Expanded(child: _kv('Collection loss', tNum(c['collectionLoss']) != 0 ? fmtCount(tNum(c['collectionLoss'])) : '—', color: TColors.rose700)),
                  ]),
                  Row(children: [
                    Expanded(child: _kv('Saleable', fmtCount(tNum(c['saleable'])))),
                    const SizedBox(width: 12),
                    Expanded(child: _kv('Sorted', '${fmtCount(tNum(c['sorted']))} (${pct(tNum(c['sorted']), tNum(c['saleable']))})')),
                  ]),
                ]),
              ),
            CompactPager(
              total: carry.length,
              page: _cPage,
              pageSize: _cSize,
              onPage: (p) => setState(() => _cPage = p),
              onPageSize: (s) => setState(() {
                _cSize = s;
                _cPage = 1;
              }),
            ),
          ]),
        ),
      ],
    ]);
  }

  Widget _kv(String l, String v, {Color? color}) => Row(children: [
        Expanded(child: Text(l, style: _sm)),
        Text(v, style: TextStyle(fontSize: 12, color: color ?? TColors.slate800)),
      ]);

  static int _numericCompare(String a, String b) {
    final x = num.tryParse(a), y = num.tryParse(b);
    if (x != null && y != null) return x.compareTo(y);
    return a.compareTo(b);
  }
}
