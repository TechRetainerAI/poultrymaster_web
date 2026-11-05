// Generic → Catalog → Stock adjustments, as
// `app/generic-stock-adjustments/page.tsx`: increase or decrease a product's
// stock by hand with a reason. A new adjustment is created and submitted in
// one go; approving it writes the stock movement, rejecting asks why.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/money/reconciliation_screen.dart' show ReasonPromptDialog;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import '../shared/reason_select.dart' show ReasonSelect, rejectReasons, stockAdjustmentReasons;
import 'generic_kit.dart';
import 'package:poultrycore_mobile/design/tone.dart';
import 'generic_products_screen.dart' show genericBandAmber, genericBandBlue, genericBandIndigo, genericEmptyCard;

const genericAdjustmentStatuses = ['All', 'Draft', 'Submitted', 'Approved', 'Rejected'];

/// badgeClass: Approved emerald, Submitted sky, Rejected rose, else slate.
Widget genericAdjustmentBadge(Object? status) {
  final (bg, fg) = switch (tStr(status)) {
    'Approved' => (TColors.emerald100, TColors.emerald800),
    'Submitted' => (TColors.sky100, TColors.sky800),
    'Rejected' => (TColors.rose100, TColors.rose800),
    _ => (TColors.slate100, TColors.slate700),
  };
  return TBadge(tStr(status), bg: bg, fg: fg);
}

/// The page's filters: search (product, reason, notes) and the date range.
List<Map> filterGenericAdjustments(List<Map> rows, {String search = '', String from = '', String to = ''}) {
  final q = search.trim().toLowerCase();
  return rows.where((r) {
    final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r['adjustmentDate']))?[1];
    if (day != null) {
      if (from.isNotEmpty && day.compareTo(from) < 0) return false;
      if (to.isNotEmpty && day.compareTo(to) > 0) return false;
    }
    if (q.isNotEmpty && !['productName', 'reason', 'notes'].any((k) => tStr(r[k]).toLowerCase().contains(q))) return false;
    return true;
  }).toList();
}

class GenericStockAdjustmentsScreen extends StatefulWidget {
  const GenericStockAdjustmentsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericStockAdjustmentsScreen> createState() => _GenericStockAdjustmentsScreenState();
}

class _GenericStockAdjustmentsScreenState extends State<GenericStockAdjustmentsScreen> {
  List<Map> _rows = [], _products = [];
  bool _loading = true;
  String _status = 'All';
  final _search = TextEditingController();
  String _from = '', _to = '';
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _base => '${genericBase(widget.company)}/inventory/adjustments';

  @override
  void initState() {
    super.initState();
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
      final res = await Future.wait([
        _api.get(_base, query: _status == 'All' ? null : {'status': _status}),
        _api.get('${genericBase(widget.company)}/products'),
      ]);
      if (mounted) {
        setState(() {
          _rows = rowsOf(res[0]);
          _products = rowsOf(res[1]);
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _id(Map a) => tIntOrNull(a['genericStockAdjustmentId']) ?? 0;
  String _product(Map a) => tStr(a['productName']).isEmpty ? '#${tStr(a['genericProductId'])}' : tStr(a['productName']);
  bool _up(Map a) => tStr(a['adjustmentType']) == 'Increase';

  Future<void> _create() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => GenericStockAdjustmentDialog(session: widget.session, company: widget.company, products: _products),
    );
    if (done == true) _load();
  }

  Future<void> _submit(Map a) async {
    try {
      await _api.post('$_base/${_id(a)}/submit', body: {});
      if (mounted) trackerToast(context, 'Submitted.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Submit failed', description: e.message, error: true);
    }
  }

  Future<void> _approve(Map a) async {
    final id = _id(a);
    try {
      await _api.post('$_base/$id/approve', body: {});
      if (mounted) trackerToast(context, 'Adjustment #$id approved. Stock updated.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Approve failed', description: e.message, error: true);
    }
  }

  Future<void> _reject(Map a) async {
    final id = _id(a);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => ReasonPromptDialog(
        title: 'Reject stock adjustment',
        description: 'Adjustment #$id will be rejected. Tell the originator why.',
        label: 'Rejection reason',
        placeholder: 'e.g. wrong product, count looks off, missing receipt…',
        confirmLabel: 'Reject',
        options: [for (final r in rejectReasons) (r, r)],
      ),
    );
    if (reason == null) return;
    try {
      await _api.post('$_base/$id/reject', body: {'rejectionReason': reason});
      if (mounted) trackerToast(context, 'Adjustment #$id rejected.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Reject failed', description: e.message, error: true);
    }
  }

  Widget _signed(Map a, {bool word = false}) {
    final up = _up(a);
    final color = up ? TColors.emerald700 : TColors.rose700;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(up ? Icons.arrow_circle_up_outlined : Icons.arrow_circle_down_outlined, size: 13, color: color),
      const SizedBox(width: 3),
      Text(word ? (up ? 'Increase' : 'Decrease') : '${up ? '+' : '-'}${tStr(a['quantity'])}', style: TextStyle(fontSize: 12, color: color)),
    ]);
  }

  List<Widget> _actions(Map a) => switch (tStr(a['status'])) {
        'Submitted' => [
            OutlinedButton.icon(
              onPressed: () => _approve(a),
              style: OutlinedButton.styleFrom(foregroundColor: TColors.emerald700, side: const BorderSide(color: TColors.emerald200)),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Approve'),
            ),
            OutlinedButton.icon(
              onPressed: () => _reject(a),
              style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: TColors.red200)),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Reject'),
            ),
          ],
        'Draft' => [OutlinedButton(onPressed: () => _submit(a), child: const Text('Submit'))],
        _ => const [],
      };

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-stock-adjustments');
    final visible = filterGenericAdjustments(_rows, search: _search.text, from: _from, to: _to);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Stock adjustments')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.inventory_2_outlined, size: 24, color: Tone.fg(0xFF0891B2)),
              SizedBox(width: 8),
              Expanded(child: Text('Stock adjustments', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const Text('Manually increase / decrease stock with a reason. Approval writes the matching movement.',
                style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add, size: 18), label: const Text('New adjustment')),
            const SizedBox(height: 12),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final s in genericAdjustmentStatuses)
                filterChipButton(s, s == _status, () {
                  if (s == _status) return;
                  setState(() => _status = s);
                  _load();
                }),
            ]),
            const SizedBox(height: 12),
            if (_loading)
              const LoadingLine('Loading...')
            else if (_rows.isEmpty)
              genericEmptyCard('No stock adjustments yet.')
            else ...[
              ListFiltersCard(
                search: _search,
                searchPlaceholder: 'Search product, reason or notes',
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
              const SizedBox(height: 14),
              MobileCardList<Map>(
                items: visible,
                keyOf: (a) => '${_id(a)}',
                primary: (a) => '#${_id(a)} · ${_product(a)}',
                secondaryBuilder: (a) => Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                  Text(fmtDateTime(a['adjustmentDate'], a, _offset), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  const Text('·', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                  _signed(a),
                ]),
                trailing: (a) => Padding(padding: const EdgeInsets.only(left: 6), child: genericAdjustmentBadge(a['status'])),
                details: (a) => [
                  ('Date', fmtDateTime(a['adjustmentDate'], a, _offset)),
                  ('Product', _product(a)),
                  ('Type', _up(a) ? 'Increase' : 'Decrease'),
                  ('Qty', tStr(a['quantity'])),
                  ('Reason', tStr(a['reason'])),
                ],
                detailColor: (a, label) => label == 'Type' ? (_up(a) ? TColors.emerald700 : TColors.rose700) : null,
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('#', width: 60), TCol('Date', width: 140), TCol('Product', width: 150), TCol('Type', width: 110),
                    TCol('Qty', right: true, width: 80), TCol('Reason', width: 150), TCol('Status', width: 100), TCol('', right: true, width: 200),
                  ],
                  rows: [
                    for (final a in items)
                      [
                        cellText('#${_id(a)}'),
                        cellText(fmtDateTime(a['adjustmentDate'], a, _offset)),
                        cellText(_product(a)),
                        Align(alignment: Alignment.centerLeft, child: _signed(a, word: true)),
                        Align(alignment: Alignment.centerRight, child: Text(tStr(a['quantity']))),
                        cellText(tStr(a['reason'])),
                        Align(alignment: Alignment.centerLeft, child: genericAdjustmentBadge(a['status'])),
                        Wrap(alignment: WrapAlignment.end, spacing: 4, children: _actions(a)),
                      ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// New stock adjustment: created, then submitted for approval.
class GenericStockAdjustmentDialog extends StatefulWidget {
  const GenericStockAdjustmentDialog({super.key, required this.session, required this.company, required this.products});
  final Session session;
  final Company company;
  final List<Map> products;

  @override
  State<GenericStockAdjustmentDialog> createState() => _GenericStockAdjustmentDialogState();
}

class _GenericStockAdjustmentDialogState extends State<GenericStockAdjustmentDialog> {
  String _productId = '', _type = 'Increase', _reason = '';
  String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final _qty = TextEditingController(text: '0'), _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _qty.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_productId.isEmpty) return trackerToast(context, 'Pick a product', error: true);
    if (_reason.trim().isEmpty) return trackerToast(context, 'Reason is required', error: true);
    final qty = num.tryParse(_qty.text.trim()) ?? 0;
    if (!(qty > 0)) return trackerToast(context, 'Quantity must be greater than zero', error: true);
    setState(() => _saving = true);
    final api = widget.session.farmClient;
    final base = '${genericBase(widget.company)}/inventory/adjustments';
    try {
      final created = await api.post(base, body: {
        'genericProductId': int.parse(_productId),
        'adjustmentType': _type,
        'quantity': qty,
        'reason': _reason,
        'adjustmentDate': _date,
        'notes': _notes.text.isEmpty ? null : _notes.text,
        'farmId': widget.company.farmId,
      });
      if (created is Map) {
        // Auto-submit so it's ready to approve.
        final id = tIntOrNull(created['genericStockAdjustmentId']);
        await api.post('$base/$id/submit', body: {});
        if (mounted) trackerToast(context, 'Adjustment #$id created and submitted.');
        if (mounted) Navigator.pop(context, true);
        return;
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not create adjustment', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final tracked = widget.products.where((p) => p['trackInventory'] == true);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Row(children: [
          Icon(Icons.inventory_2_outlined, size: 20, color: Tone.fg(0xFF0891B2)),
          SizedBox(width: 8),
          Expanded(child: Text('New stock adjustment')),
        ]),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Adjustment lands as Submitted. Approve to commit it to inventory.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection('Product', genericBandIndigo, [
              FilterLabel(
                'Product *',
                AppSelect<String>(
                  value: _productId.isEmpty ? null : _productId,
                  hintText: 'Pick product...',
                  items: [
                    for (final p in tracked)
                      AppSelectItem(value: tStr(p['genericProductId']), label: '${tStr(p['productName'])} – current: ${tStr(p['currentStock'])}'),
                  ],
                  onChanged: (v) => setState(() => _productId = v ?? ''),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Adjustment details', genericBandBlue, [
              FilterLabel(
                'Type *',
                AppSelect<String>(
                  value: _type,
                  items: const [
                    AppSelectItem(value: 'Increase', label: 'Increase (+)'),
                    AppSelectItem(value: 'Decrease', label: 'Decrease (−)'),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
              ),
              FilterLabel(
                'Quantity *',
                AppInput(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                ),
              ),
              FilterLabel(
                'Date',
                AppDateField(
                  value: businessDateAsDateTime(_date),
                  onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Reason & notes', genericBandAmber, [
              FilterLabel('Reason *', ReasonSelect(options: stockAdjustmentReasons, value: _reason, onChanged: (v) => setState(() => _reason = v))),
              FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4, inputFormatters: [LengthLimitingTextInputFormatter(1000)])),
            ]),
          ]),
        ),
        actions: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(backgroundColor: Tone.button(TColors.red600), foregroundColor: Colors.white, side: BorderSide.none),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Create & submit')),
        ],
      ),
    );
  }
}
