import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/expenses/asset_widgets.dart' show ReasonTextPrompt;
import '../poultry/expenses/deferred_costs_screen.dart' show qtyFmt;
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_format.dart';
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import '../shared/reason_select.dart' show ReasonSelectField, lossReasons, unapproveReasons;
import 'water_production_screen.dart' show WaterProductionDetailScreen;
import 'water_raw_materials_screen.dart' show filterWaterRows, numText;

/// Water → Operations → Inventory → Damages & loss (`app/water-loss-records/page.tsx`)
/// and Production losses (`app/water-production-losses/page.tsx`, read-only:
/// the losses production approval writes).

const waterLossTypes = [
  'ProductionDamage', 'DamagedBags', 'RejectedSachets', 'BurstSachets', 'ReturnedBags', 'MachineWaste', 'PackagingWaste', 'DriverShortage',
  'MissingStock', 'BadDebt', 'Other',
];

Widget waterLossStatusBadge(Object? status) {
  final s = tStr(status).isEmpty ? 'Pending' : tStr(status);
  final (bg, fg) = switch (s) {
    'Approved' => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
    'Pending' || 'Reopened' => (TColors.amber100, TColors.amber700),
    _ => (TColors.slate100, TColors.slate700),
  };
  return TBadge(s, bg: bg, fg: fg);
}

Widget waterProductionLossBadge(Object? status) {
  final s = tStr(status);
  return s == 'Approved'
      ? TBadge(s, bg: const Color(0xFFFFE4E6), fg: const Color(0xFF9F1239))
      : TBadge(s, bg: TColors.slate100, fg: TColors.slate700);
}

// ------------------------------------------------------------ damages & loss

class WaterLossRecordsScreen extends StatefulWidget {
  const WaterLossRecordsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterLossRecordsScreen> createState() => _WaterLossRecordsScreenState();
}

class _WaterLossRecordsScreenState extends State<WaterLossRecordsScreen> {
  List<Map> _items = [], _products = [];
  bool _loading = true;
  final _search = TextEditingController();
  String _from = '', _to = '', _type = 'ALL';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

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
    final q = {'farmId': _farmId};
    try {
      final r = await Future.wait([
        _api.get('/api/Water/loss-records', query: {...q, if (_type != 'ALL') 'lossType': _type}),
        _api.get('/api/Water/products', query: q),
      ]);
      if (!mounted) return;
      setState(() {
        _items = rowsOf(r[0]);
        _products = rowsOf(r[1]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load loss records', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _id(Map l) => tIntOrNull(l['waterLossRecordId']) ?? 0;
  bool _approved(Map l) => tStr(l['status']) == 'Approved';

  Future<void> _form([Map? editing]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _LossDialog(session: widget.session, company: widget.company, products: _products, editing: editing),
    );
    if (ok == true) await _load();
  }

  Future<void> _approve(Map l) async {
    try {
      await _api.post('/api/Water/loss-records/${_id(l)}/approve', query: {'farmId': _farmId, 'approvedBy': widget.session.tokens.userId ?? ''});
      if (mounted) trackerToast(context, 'Loss approved');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Approve failed', description: e.message, error: true);
    }
  }

  Future<void> _unapprove(Map l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ReasonTextPrompt(
        title: 'Unapprove this loss record?',
        description:
            'This will flip ${tStr(l['lossType'])} from Approved back to Pending so the record can be edited and approved again. Cash impact (if any) is reversed.',
        label: 'Reason for unapproving',
        options: unapproveReasons,
        placeholder: 'e.g. corrected reason / wrong quantity',
        confirmLabel: 'Unapprove',
        onSubmit: (reason) async {
          try {
            await _api.post('/api/Water/loss-records/${_id(l)}/unapprove',
                query: {'farmId': _farmId, 'unapprovedBy': widget.session.tokens.userId ?? ''}, body: {'reason': reason});
          } on ApiException catch (e) {
            if (mounted) trackerToast(context, 'Unapprove failed', description: e.message, error: true);
            rethrow;
          }
        },
      ),
    );
    if (ok == true) {
      if (mounted) trackerToast(context, 'Loss unapproved — now editable');
      await _load();
    }
  }

  List<Widget> _actions(Map l) => [
        if (!_approved(l)) OutlinedButton.icon(onPressed: () => _form(l), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
        if (!_approved(l))
          OutlinedButton.icon(
            onPressed: () => _approve(l),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF15803D), side: const BorderSide(color: Color(0xFFBBF7D0))),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Approve'),
          ),
        if (_approved(l))
          OutlinedButton.icon(
            onPressed: () => _unapprove(l),
            style: OutlinedButton.styleFrom(foregroundColor: TColors.amber700, side: const BorderSide(color: Color(0xFFFDE68A))),
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Unapprove'),
          ),
      ];

  Widget _score(String label, String value) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: TColors.slate900)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-loss-records');
    final visible = filterWaterRows(_items, const ['lossType', 'reason', 'notes'], search: _search.text, dateKey: 'lossDate', from: _from, to: _to);
    if (visible.length != _lastTotal) {
      _lastTotal = visible.length;
      _page = 1;
    }
    final approved = [for (final i in _items) if (_approved(i)) i];
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Loss records')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFE11D48)),
              SizedBox(width: 8),
              Flexible(child: Text('Loss records', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(onPressed: () => _form(), icon: const Icon(Icons.add, size: 16), label: const Text('Record loss')),
            ),
            const SizedBox(height: 12),
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search loss type, reason or notes',
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
                  value: _type,
                  items: [const AppSelectItem(value: 'ALL', label: 'All types'), for (final t in waterLossTypes) AppSelectItem(value: t, label: t)],
                  onChanged: (v) {
                    setState(() => _type = v ?? 'ALL');
                    _load();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            twoUp([
              _score('Approved value', _gh(approved.fold<num>(0, (s, i) => s + tNum(i['estimatedValue'])))),
              _score('Approved bags lost', qtyFmt(approved.fold<num>(0, (s, i) => s + tNum(i['quantityBags'])))),
              _score('Pending', '${_items.where((i) => !_approved(i)).length}'),
              _score('Total records', '${_items.length}'),
            ]),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
            else if (_items.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: const Text('No losses recorded yet.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
              )
            else
              MobileCardList<Map>(
                striped: true,
                items: pageSlice(visible, _page, _pageSize),
                keyOf: (l) => '${_id(l)}',
                primary: (l) => '${tStr(l['lossType'])} · ${_gh(tNum(l['estimatedValue']))}',
                secondaryBuilder: (l) => Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(fmtDateTime(l['lossDate'], l, _offset)),
                  waterLossStatusBadge(l['status']),
                ]),
                highlights: (l) => [
                  Highlight('Bags', qtyFmt(l['quantityBags']), accent: Accent.rose),
                  Highlight('Sachets', qtyFmt(l['quantitySachets']), accent: Accent.rose),
                  Highlight('Value', _gh(tNum(l['estimatedValue'])), accent: Accent.violet, wide: true),
                ],
                details: (l) => [
                  ('Date', fmtDateTime(l['lossDate'], l, _offset)),
                  ('Type', tStr(l['lossType'])),
                  ('Status', tStr(l['status']).isEmpty ? 'Pending' : tStr(l['status'])),
                  ('Reason', tStr(l['reason']).isEmpty ? '—' : tStr(l['reason'])),
                ],
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Date', width: 120), TCol('Type', width: 140), TCol('Bags', right: true, width: 70), TCol('Sachets', right: true, width: 80),
                    TCol('Value', right: true, width: 110), TCol('Reason', width: 200), TCol('Status', width: 100), TCol('Actions', right: true, width: 120),
                  ],
                  rows: [
                    for (final l in items)
                      [
                        cellText(fmtDateTime(l['lossDate'], l, _offset)),
                        Align(alignment: Alignment.centerLeft, child: TBadge(tStr(l['lossType']), bg: Colors.white, fg: TColors.slate700, border: TColors.slate300)),
                        Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(l['quantityBags']))),
                        Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(l['quantitySachets']))),
                        Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(l['estimatedValue'])))),
                        Text(tStr(l['reason']).isEmpty ? '—' : tStr(l['reason'])),
                        Align(alignment: Alignment.centerLeft, child: waterLossStatusBadge(l['status'])),
                        Wrap(alignment: WrapAlignment.end, children: [
                          if (!_approved(l)) IconButton(tooltip: 'Edit', onPressed: () => _form(l), icon: const Icon(Icons.edit_outlined, size: 18)),
                          if (!_approved(l))
                            IconButton(tooltip: 'Approve', onPressed: () => _approve(l), icon: const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF16A34A))),
                          if (_approved(l))
                            IconButton(tooltip: 'Unapprove', onPressed: () => _unapprove(l), icon: const Icon(Icons.undo, size: 18, color: TColors.amber600)),
                        ]),
                      ],
                  ],
                ),
                pager: CompactPager(
                  total: visible.length,
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

/// Record loss / Edit loss record.
class _LossDialog extends StatefulWidget {
  const _LossDialog({required this.session, required this.company, required this.products, this.editing});
  final Session session;
  final Company company;
  final List<Map> products;
  final Map? editing;

  @override
  State<_LossDialog> createState() => _LossDialogState();
}

class _LossDialogState extends State<_LossDialog> {
  late final Map? e = widget.editing;
  late String _date = e != null ? tStr(e!['lossDate']).split('T').first : DateTime.now().toUtc().toIso8601String().substring(0, 10);
  late String _type = e != null ? tStr(e!['lossType']) : 'DamagedBags';
  late int _productId = e != null ? (tIntOrNull(e!['waterProductId']) ?? 0) : (tIntOrNull(widget.products.firstOrNull?['waterProductId']) ?? 0);
  late final _bags = TextEditingController(text: numText(tNum(e?['quantityBags'])));
  late final _sachets = TextEditingController(text: numText(tNum(e?['quantitySachets'])));
  late final _value = TextEditingController(text: numText(tNum(e?['estimatedValue']), 2));
  late final _reason = TextEditingController(text: tStr(e?['reason']));
  late final _notes = TextEditingController(text: tStr(e?['notes']));

  @override
  void dispose() {
    for (final c in [_bags, _sachets, _value, _reason, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty) return trackerToast(context, 'Reason required', error: true);
    num? orNull(TextEditingController c) => (num.tryParse(c.text) ?? 0) == 0 ? null : num.parse(c.text);
    final body = <String, Object?>{
      'lossDate': _date,
      'lossType': _type,
      'waterProductId': _productId == 0 ? null : _productId,
      'quantityBags': orNull(_bags),
      'quantitySachets': orNull(_sachets),
      'estimatedValue': orNull(_value),
      'reason': _reason.text,
      'notes': _notes.text,
      'farmId': widget.company.farmId,
    };
    try {
      final api = widget.session.farmClient;
      if (e != null) {
        final id = tIntOrNull(e!['waterLossRecordId']);
        await api.put('/api/Water/loss-records/$id', query: {'farmId': widget.company.farmId}, body: {...body, 'waterLossRecordId': id});
        if (mounted) trackerToast(context, 'Loss updated');
      } else {
        await api.post('/api/Water/loss-records', body: body);
        if (mounted) trackerToast(context, 'Loss recorded — pending approval');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (x) {
      if (mounted) trackerToast(context, 'Save failed', description: x.message, error: true);
    }
  }

  Widget _num(TextEditingController c, {bool decimal = false}) => AppInput(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'^\d*\.?\d*' : r'^\d*'))],
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFFE11D48)),
          const SizedBox(width: 8),
          Flexible(child: Text(e != null ? 'Edit loss record' : 'Record loss')),
        ]),
        content: SizedBox(
          width: 600,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(e != null ? 'Update the loss details. Approved records must be Unapproved first.' : 'Log a loss for review and approval',
                style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection('Basics', const Color(0xFF4F46E5), [
              FilterLabel(
                'Date',
                AppDateField(
                  value: businessDateAsDateTime(_date),
                  hintText: 'dd/mm/yyyy',
                  onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)),
                ),
              ),
              FilterLabel(
                'Loss type',
                AppSelect<String>(
                  value: _type,
                  items: [for (final t in waterLossTypes) AppSelectItem(value: t, label: t)],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
              ),
              FilterLabel(
                'Product',
                AppSelect<int>(
                  value: _productId == 0 ? null : _productId,
                  hintText: '(optional)',
                  items: [for (final p in widget.products) AppSelectItem(value: tIntOrNull(p['waterProductId']) ?? 0, label: tStr(p['name']))],
                  onChanged: (v) => setState(() => _productId = v ?? 0),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Quantity & Value', const Color(0xFF2563EB), [
              FilterLabel('Bags', _num(_bags)),
              FilterLabel('Sachets', _num(_sachets)),
              FilterLabel('Estimated value', _num(_value, decimal: true)),
            ]),
            const SizedBox(height: 12),
            formSection('Details', TColors.slate600, [
              FilterLabel('Reason *', ReasonSelectField(controller: _reason, options: lossReasons)),
              FilterLabel('Notes', AppInput(controller: _notes, minLines: 3, maxLines: 6)),
            ]),
          ]),
        ),
        actions: [
          redCancelButton(() => Navigator.pop(context, false)),
          FilledButton(onPressed: _save, child: Text(e != null ? 'Save changes' : 'Record')),
        ],
      );
}

// ------------------------------------------------------------ production losses

class WaterProductionLossesScreen extends StatefulWidget {
  const WaterProductionLossesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterProductionLossesScreen> createState() => _WaterProductionLossesScreenState();
}

class _WaterProductionLossesScreenState extends State<WaterProductionLossesScreen> {
  List<Map> _losses = [];
  bool _busy = true;
  final _search = TextEditingController();
  String _from = '', _to = '';
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

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
    setState(() => _busy = true);
    try {
      final r = rowsOf(await widget.session.farmClient.get('/api/Water/production-losses', query: {'farmId': widget.company.farmId}));
      if (mounted) setState(() => _losses = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load losses', description: e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  bool _hasBatch(Map l) => tStr(l['sourceType']) == 'ProductionBatch' && tNum(l['sourceId']) != 0;

  void _viewBatch(Map l) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WaterProductionDetailScreen(session: widget.session, company: widget.company, batchId: tIntOrNull(l['sourceId'])!),
      ));

  String _batch(Map l) => tStr(l['batchNumber']).isNotEmpty ? tStr(l['batchNumber']) : '#${tStr(l['sourceId'])}';

  Widget _score(String label, String value, {Color? color}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: color ?? TColors.slate900)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-production-losses');
    final visible = filterWaterRows(_losses, const ['batchNumber', 'productName', 'lossType', 'reason'],
        search: _search.text, dateKey: 'lossDate', from: _from, to: _to);
    if (visible.length != _lastTotal) {
      _lastTotal = visible.length;
      _page = 1;
    }
    // Cancelled rows are reopened and don't count towards money lost.
    final approved = [for (final l in _losses) if (tStr(l['status']) == 'Approved') l];
    num sum(String k) => approved.fold<num>(0, (s, l) => s + tNum(l[k]));
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Production losses')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFFFFE4E6), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.trending_down, color: Color(0xFFE11D48)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Production losses', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
                  Text('Damaged bags / rejected sachets auto-recorded on production approval.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            twoUp([
              _score('Records', '${approved.length}'),
              _score('Bags lost', qtyFmt(sum('bagsLost'))),
              _score('Sachets lost', qtyFmt(sum('sachetsLost'))),
              _score('Total value', _gh(sum('totalValue')), color: const Color(0xFFBE123C)),
            ]),
            const SizedBox(height: 12),
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search batch number, product, type or reason',
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
            ),
            const SizedBox(height: 12),
            if (_busy)
              const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
            else if (_losses.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: const Text('No production losses recorded yet.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
              )
            else
              MobileCardList<Map>(
                striped: true,
                items: pageSlice(visible, _page, _pageSize),
                keyOf: (l) => tStr(l['waterProductionLossId']),
                primary: (l) => '${_batch(l)} · ${tStr(l['productName']).isEmpty ? '—' : tStr(l['productName'])}',
                secondaryBuilder: (l) => Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(fmtDateTime(l['lossDate'], l, _offset)),
                  waterProductionLossBadge(l['status']),
                ]),
                highlights: (l) => [
                  Highlight('Bags lost', qtyFmt(l['bagsLost']), accent: Accent.rose),
                  Highlight('Sachets lost', qtyFmt(l['sachetsLost']), accent: Accent.rose),
                  Highlight('Total value', _gh(tNum(l['totalValue'])), accent: Accent.violet, wide: true),
                ],
                details: (l) => [
                  ('Type', tStr(l['lossType'])),
                  ('Bags value', _gh(tNum(l['bagsLossValue']))),
                  ('Sachets value', _gh(tNum(l['sachetsLossValue']))),
                ],
                actions: (l) => [
                  if (_hasBatch(l))
                    OutlinedButton.icon(onPressed: () => _viewBatch(l), icon: const Icon(Icons.visibility_outlined, size: 16), label: const Text('View batch')),
                ],
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Date', width: 120), TCol('Batch', width: 110), TCol('Product', width: 130), TCol('Type', width: 120),
                    TCol('Bags', right: true, width: 70), TCol('Sachets', right: true, width: 80), TCol('Total value', right: true, width: 110),
                    TCol('Status', width: 100), TCol('Actions', right: true, width: 70),
                  ],
                  rows: [
                    for (final l in items)
                      [
                        cellText(fmtDateTime(l['lossDate'], l, _offset)),
                        cellText(_batch(l)),
                        cellText(tStr(l['productName']).isEmpty ? '—' : tStr(l['productName'])),
                        cellText(tStr(l['lossType'])),
                        Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(l['bagsLost']))),
                        Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(l['sachetsLost']))),
                        Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(l['totalValue'])), bold: true)),
                        Align(alignment: Alignment.centerLeft, child: waterProductionLossBadge(l['status'])),
                        _hasBatch(l)
                            ? IconButton(tooltip: 'View batch', onPressed: () => _viewBatch(l), icon: const Icon(Icons.visibility_outlined, size: 18))
                            : const SizedBox.shrink(),
                      ],
                  ],
                ),
                pager: CompactPager(
                  total: visible.length,
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
