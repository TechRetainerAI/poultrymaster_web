import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../reports/report_format.dart';
import 'tracker_logic.dart';
import 'tracker_widgets.dart';

/// Poultry → Trackers → Medication tracker, as `app/medication-tracker/page.tsx`:
/// every raw-material item in the Medication category, each on its own —
/// purchases in, production usage out, a running balance per medication, and
/// the item's live currentQuantity as "Quantity left" (Raw Materials & Supplies'
/// own figure). Tapping a medication focuses the ledger on it.
class MedicationTrackerScreen extends StatefulWidget {
  const MedicationTrackerScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<MedicationTrackerScreen> createState() => _MedicationTrackerScreenState();
}

class _MedicationTrackerScreenState extends State<MedicationTrackerScreen> {
  List<Map> _items = [], _purchases = [], _usage = [];
  bool _loading = true;
  bool _refreshing = false;
  FarmMoney _money = const FarmMoney();

  SortState _byMedSort = (key: null, dir: null);
  String _medFilter = 'all';
  String _typeFilter = 'all';
  final _search = TextEditingController();
  String _from = '', _to = '';
  SortState _sort = (key: 'date', dir: SortDir.desc);
  int _page = 1;
  int _pageSize = trackerPageSizeDefault;
  final _ledgerKey = GlobalKey();

  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = !_refreshing);
    final fq = {'farmId': widget.company.farmId};
    Future<List<Map>> soft(String p) async {
      try {
        return rowsOf(await _api.get(p, query: fq));
      } on ApiException {
        return [];
      }
    }

    try {
      final r = await Future.wait([
        _api.get('/api/Poultry/raw-material-items', query: fq).then(rowsOf),
        soft('/api/Poultry/raw-material-purchases'),
        soft('/api/Poultry/raw-material-usage/history'),
      ]);
      if (!mounted) return;
      setState(() {
        _items = r[0];
        _purchases = r[1];
        _usage = r[2];
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load medications', description: e.message, error: true);
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  void _refresh() {
    setState(() => _refreshing = true);
    _load();
  }

  String fmt(num n) => loc(n, 2);

  /// The web's fmtDateTime: the business day, with the clock time when the
  /// stored value carries one.
  String _dateTime(String raw) {
    final day = formatShortDate(raw);
    final m = RegExp(r'T(\d{2}):(\d{2})').firstMatch(raw);
    if (m == null || (m[1] == '00' && m[2] == '00')) return day;
    return '$day, ${m[1]}:${m[2]}';
  }

  int get _activeFilters =>
      (_search.text.isNotEmpty ? 1 : 0) + (_from.isNotEmpty ? 1 : 0) + (_to.isNotEmpty ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/medication-tracker');
    final meds = medicationItems(_items);
    return Scaffold(
      appBar: AppBar(
        leading: lead.leading,
        leadingWidth: lead.width,
        title: const Text('Medication tracker'),
        actions: [RefreshAction(busy: _refreshing || _loading, onPressed: _refresh)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            TrackerHeader(
              icon: Icons.medication_outlined,
              iconBg: TColors.violet100,
              iconFg: TColors.violet800,
              title: 'Medication Tracker',
              blurb:
                  'Each medication tracked separately — purchases in, production usage out, and the quantity left for each. Same source as Raw Materials & Supplies.',
              session: widget.session,
              company: widget.company,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Row(children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Flexible(child: Text('Loading medications…', style: TextStyle(color: TColors.slate500))),
                ]),
              )
            else if (meds.isEmpty)
              TCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Text.rich(
                    TextSpan(children: [
                      t('No medications yet. Add items with category '),
                      b('Medication'),
                      t(' on the Raw Materials & Supplies page, then record their purchases — usage appears automatically when medication is consumed in production.'),
                    ]),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: TColors.slate600),
                  ),
                ),
              )
            else
              ..._content(meds),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(List<Map> meds) {
    final byMed = summarizeMedications(meds, _purchases, _usage);
    final low = byMed.where((x) => x.isActive && x.status == 'Low').length;
    final finished = byMed.where((x) => x.isActive && x.status == 'Finished').length;

    Widget stat(IconData icon, String label, int value, {Color? bg, Color? border, Color? fg, Color? iconColor}) =>
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg ?? Colors.white,
            border: Border.all(color: border ?? TColors.slate200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 16, color: iconColor ?? TColors.slate400),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label.toUpperCase(),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: TColors.slate500)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(loc(value), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: fg ?? TColors.slate900)),
            ],
          ),
        );

    return [
      LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(width: w, child: stat(Icons.inventory_2_outlined, 'Medications', meds.length, iconColor: TColors.violet600)),
          SizedBox(
            width: w,
            child: stat(Icons.warning_amber_rounded, 'Low stock', low,
                bg: low > 0 ? TColors.amber50 : null,
                border: low > 0 ? TColors.amber200 : null,
                fg: low > 0 ? TColors.amber700 : null,
                iconColor: low > 0 ? TColors.amber600 : null),
          ),
          SizedBox(
            width: w,
            child: stat(Icons.warning_amber_rounded, 'Finished', finished,
                bg: finished > 0 ? TColors.red50 : null,
                border: finished > 0 ? TColors.red200 : null,
                fg: finished > 0 ? TColors.red600 : null,
                iconColor: finished > 0 ? TColors.red600 : null),
          ),
        ]);
      }),
      const SizedBox(height: 16),
      _byMedication(byMed),
      const SizedBox(height: 16),
      _ledger(meds),
    ];
  }

  Widget _statusBadge(String s) => switch (s) {
        'Inactive' => const TBadge('Inactive', bg: TColors.slate100, fg: TColors.slate700),
        'Finished' => const TBadge('Finished', bg: TColors.red100, fg: TColors.red700),
        'Low' => const TBadge('Low stock', bg: TColors.amber100, fg: TColors.amber700),
        _ => const TBadge('In stock', bg: TColors.green100, fg: TColors.green700),
      };

  Widget _byMedication(List<MedSummary> byMed) {
    final sorted = sortRows(byMed, _byMedSort, (x, k) => switch (k) {
          'name' => x.name,
          'unit' => x.unit,
          'totalIn' => x.totalIn,
          'totalOut' => x.totalOut,
          'left' => x.left,
          'status' => x.status,
          _ => null,
        });
    final units = <String>[];
    for (final x in sorted) {
      final u = x.unit.trim();
      if (u.isNotEmpty && u != '—' && !units.contains(u)) units.add(u);
    }
    final mixed = units.length > 1;
    final unitLabel = units.length == 1 ? units.first : null;
    final tin = sorted.fold<num>(0, (s, x) => s + x.totalIn);
    final tout = sorted.fold<num>(0, (s, x) => s + x.totalOut);
    final tleft = sorted.fold<num>(0, (s, x) => s + x.left);
    const dash = Text('—', style: TextStyle(color: TColors.slate400));

    return TCard(
      title: 'By medication',
      description: 'Quantity left, total in and total out for each medication. Each one stands on its own.',
      child: TrackerTable(
        sort: _byMedSort,
        onSort: (k) => setState(() => _byMedSort = toggleSort(k, _byMedSort)),
        columns: const [
          TCol('Medication', sortKey: 'name', width: 150),
          TCol('Unit', sortKey: 'unit', width: 80),
          TCol('Total In', sortKey: 'totalIn', right: true, width: 90),
          TCol('Total Out', sortKey: 'totalOut', right: true, width: 90),
          TCol('Quantity Left', sortKey: 'left', right: true, width: 120),
          TCol('Status', sortKey: 'status', right: true, width: 100),
        ],
        rows: [
          for (final x in sorted)
            [
              // Tapping a medication focuses the ledger on it, as the web row does.
              InkWell(
                onTap: () {
                  setState(() {
                    _medFilter = '${x.id}';
                    _page = 1;
                  });
                  final ctx = _ledgerKey.currentContext;
                  if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
                },
                child: Text(x.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, color: TColors.blue600, decoration: TextDecoration.underline)),
              ),
              cellText(x.unit, color: TColors.slate500),
              cellText(fmt(x.totalIn), color: TColors.emerald700),
              cellText(fmt(x.totalOut), color: TColors.red600),
              cellText('${fmt(x.left)} ${x.unit != '—' ? x.unit : ''}', bold: true, color: x.left <= 0 ? TColors.red600 : null),
              _statusBadge(x.status),
            ],
        ],
        footer: [
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Total', style: TextStyle(fontWeight: FontWeight.w500)),
            TextSpan(
                text: ' (${loc(sorted.length)} ${sorted.length == 1 ? 'medication' : 'medications'})',
                style: const TextStyle(color: TColors.slate500)),
          ])),
          cellText(mixed ? 'mixed' : unitLabel ?? '', color: TColors.slate500),
          mixed ? dash : cellText(fmt(tin), color: TColors.emerald700, bold: true),
          mixed ? dash : cellText(fmt(tout), color: TColors.red700, bold: true),
          mixed ? dash : cellText('${fmt(tleft)} ${unitLabel ?? ''}', bold: true),
          mixed ? const Text('mixed units', style: TextStyle(fontSize: 12, color: TColors.slate500)) : const SizedBox(),
        ],
      ),
    );
  }

  Widget _ledger(List<Map> meds) {
    final all = buildMedicationLedger(meds, _purchases, _usage);
    var rows = all;
    if (_medFilter != 'all') rows = rows.where((r) => '${r.itemId}' == _medFilter).toList();
    if (_typeFilter != 'all') rows = rows.where((r) => r.type == _typeFilter).toList();
    // filterByDateAndSearch: calendar-day prefix, inclusive; search on
    // medication and source.
    final s = _search.text.trim().toLowerCase();
    rows = rows.where((r) {
      final day = dayOf(r.date);
      if (day.isNotEmpty) {
        if (_from.isNotEmpty && day.compareTo(_from) < 0) return false;
        if (_to.isNotEmpty && day.compareTo(_to) > 0) return false;
      }
      if (s.isNotEmpty && !r.medication.toLowerCase().contains(s) && !r.source.toLowerCase().contains(s)) return false;
      return true;
    }).toList();
    final sorted = sortRows(rows, _sort, (r, k) => switch (k) {
          'date' => DateTime.tryParse(r.date),
          'medication' => r.medication,
          'type' => r.type,
          'source' => r.source,
          'in' => r.inQty,
          'out' => r.outQty,
          'balance' => r.balance,
          'recognized' => r.recognized,
          _ => null,
        });
    final units = <String>[];
    for (final r in sorted) {
      final u = r.unit.trim();
      if (u.isNotEmpty && !units.contains(u)) units.add(u);
    }
    final mixed = units.length > 1;
    final unitLabel = units.length == 1 ? units.first : null;
    final tin = sorted.fold<num>(0, (a, r) => a + r.inQty);
    final tout = sorted.fold<num>(0, (a, r) => a + r.outQty);
    final rec = sorted.fold<num>(0, (a, r) => a + (r.reversed == true ? 0 : (r.recognized ?? 0)));
    final active = _medFilter != 'all' || _typeFilter != 'all' || s.isNotEmpty || _from.isNotEmpty || _to.isNotEmpty;
    final pageRows = pageOf(sorted, _page, _pageSize);
    final period = _from.isNotEmpty && _to.isNotEmpty ? rangeToPeriod(_from, _to) : 'custom';
    const dash = Text('—', style: TextStyle(color: TColors.slate400));

    return TCard(
      key: _ledgerKey,
      title: 'Ins & Outs ledger',
      descriptionSpans: [
        t('History of every purchase (in) and production usage (out). The '),
        b('Balance'),
        t(' is the running quantity left for that medication. Pick a medication to focus on just one.'),
      ],
      headerExtra: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterLabel(
              'Search',
              AppInput(
                controller: _search,
                hintText: 'Search medication or source',
                prefixIcon: const Icon(Icons.search, size: 18),
                onChanged: (_) => setState(() => _page = 1),
              ),
            ),
            const SizedBox(height: 8),
            FilterLabel(
              'Period',
              AppSelect<String>(
                value: period,
                hintText: 'Select period',
                items: [
                  for (final (_, opts) in periodGroups)
                    for (final (k, l) in opts) AppSelectItem(value: k, label: l),
                ],
                onChanged: (k) {
                  final r = k == null ? null : periodToRange(k);
                  if (r != null) {
                    setState(() {
                      _from = r.from;
                      _to = r.to;
                      _page = 1;
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            filterRow([
              FilterLabel('From', FilterDate(value: _from, hint: 'From', onChanged: (v) => setState(() {
                    _from = v;
                    _page = 1;
                  }))),
              FilterLabel('To', FilterDate(value: _to, hint: 'To', onChanged: (v) => setState(() {
                    _to = v;
                    _page = 1;
                  }))),
            ]),
            const SizedBox(height: 8),
            filterRow([
              AppSelect<String>(
                value: _medFilter,
                hintText: 'All medications',
                items: [
                  const AppSelectItem(value: 'all', label: 'All medications'),
                  for (final m in meds) AppSelectItem(value: '${tIntOrNull(m['poultryRawMaterialItemId'])}', label: tStr(m['itemName'])),
                ],
                onChanged: (v) => setState(() {
                  _medFilter = v ?? 'all';
                  _page = 1;
                }),
              ),
              AppSelect<String>(
                value: _typeFilter,
                hintText: 'All types',
                items: const [
                  AppSelectItem(value: 'all', label: 'All types'),
                  AppSelectItem(value: 'Purchase', label: 'Purchase (in)'),
                  AppSelectItem(value: 'Usage', label: 'Usage (out)'),
                ],
                onChanged: (v) => setState(() {
                  _typeFilter = v ?? 'all';
                  _page = 1;
                }),
              ),
            ]),
            if (_activeFilters > 0)
              TextButton.icon(
                onPressed: () => setState(() {
                  _search.clear();
                  _from = '';
                  _to = '';
                  _page = 1;
                }),
                icon: const Icon(Icons.close, size: 14),
                label: Text('Clear ($_activeFilters)'),
                style: TextButton.styleFrom(foregroundColor: TColors.slate500),
              ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text(
                  'No movements match. Record a purchase on Raw Materials & Supplies, or use this medication in production.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: TColors.slate600)),
            )
          else
            TrackerTable(
              sort: _sort,
              onSort: (k) => setState(() {
                _sort = toggleSort(k, _sort);
                _page = 1;
              }),
              columns: const [
                TCol('Date', sortKey: 'date', width: 130),
                TCol('Medication', sortKey: 'medication', width: 140),
                TCol('Type', sortKey: 'type', width: 70),
                TCol('Source', sortKey: 'source', width: 220),
                TCol('In', sortKey: 'in', right: true, width: 80),
                TCol('Out', sortKey: 'out', right: true, width: 80),
                TCol('Balance', sortKey: 'balance', right: true, width: 110),
                TCol('Cost recognised', sortKey: 'recognized', right: true, width: 170),
              ],
              rows: [
                for (final r in pageRows)
                  [
                    cellText(_dateTime(r.date)),
                    cellText(r.medication, bold: true),
                    TBadge(r.type == 'Purchase' ? 'In' : 'Out',
                        bg: r.type == 'Purchase' ? TColors.emerald100 : TColors.amber100,
                        fg: r.type == 'Purchase' ? TColors.emerald700 : TColors.amber700),
                    cellText(r.source, color: TColors.slate500),
                    cellText(r.inQty > 0 ? fmt(r.inQty) : '—', color: TColors.emerald700),
                    cellText(r.outQty > 0 ? fmt(r.outQty) : '—', color: TColors.red600),
                    cellText('${fmt(r.balance)} ${r.unit}', bold: true),
                    r.type != 'Usage'
                        ? const Text('—', style: TextStyle(color: TColors.slate300))
                        : RecognizedCostCell(
                            cost: r.cost,
                            recognized: r.recognized,
                            reversed: r.reversed == true,
                            money: _money,
                            onBreakdown: r.productionRecordId == null
                                ? null
                                : () => showCostBreakdown(context,
                                    session: widget.session,
                                    company: widget.company,
                                    productionRecordId: r.productionRecordId!,
                                    money: _money,
                                    title: 'Medication cost breakdown'),
                          ),
                  ],
              ],
              footer: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: active ? 'Filtered total' : 'Total', style: const TextStyle(fontWeight: FontWeight.w500)),
                  TextSpan(
                      text:
                          ' (${loc(sorted.length)} ${sorted.length == 1 ? 'row' : 'rows'}${mixed ? ' · mixed units' : unitLabel != null ? ' · $unitLabel' : ''})',
                      style: const TextStyle(color: TColors.slate500)),
                ])),
                const SizedBox(),
                const SizedBox(),
                const SizedBox(),
                mixed ? dash : cellText(fmt(tin), color: TColors.emerald700, bold: true),
                mixed ? dash : cellText(fmt(tout), color: TColors.red700, bold: true),
                const SizedBox(),
                cellText(_money(rec), color: TColors.amber700, bold: true),
              ],
            ),
          if (sorted.isNotEmpty)
            TrackerPager(
              total: sorted.length,
              page: _page,
              pageSize: _pageSize,
              onPage: (p) => setState(() => _page = p),
              onPageSize: (v) => setState(() {
                _pageSize = v;
                _page = 1;
              }),
            ),
        ],
      ),
    );
  }
}
