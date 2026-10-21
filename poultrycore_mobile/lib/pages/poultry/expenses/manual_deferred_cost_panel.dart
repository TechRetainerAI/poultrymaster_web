// Manual deferred cost entries (migration 371) on the Deferred Inventory Cost
// page, as `components/poultry/manual-deferred-cost-panel.tsx`.
//
// Cost for stock no purchase covers -- e.g. opening stock -- recorded as an
// event with a reason, recognised on Profit & Loss as the stock is used. The
// owner / an admin records and reverses; reversing takes back only what is not
// yet on Profit & Loss.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../../shared/reason_select.dart';
import '../reports/report_format.dart';
import '../sales/credit_widgets.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc;
import '../trackers/tracker_widgets.dart';

const manualDeferredEntryLabel = {
  'OpeningDeferredCost': 'Opening deferred cost',
  'HistoricalDeferredCost': 'Historical deferred cost',
  'CostAdjustment': 'Cost adjustment',
  'Migration': 'Migration',
  'Other': 'Other',
};

const _violet600 = Color(0xFF7C3AED);
const _violet700 = Color(0xFF6D28D9);
const _root = '/api/Poultry/deferred-inventory-costs';

class ManualDeferredCostPanel extends StatefulWidget {
  const ManualDeferredCostPanel({super.key, required this.session, required this.company, this.onChanged});
  final Session session;
  final Company company;
  final VoidCallback? onChanged;
  @override
  State<ManualDeferredCostPanel> createState() => _ManualDeferredCostPanelState();
}

class _ManualDeferredCostPanelState extends State<ManualDeferredCostPanel> {
  List<Map> _rows = [];
  bool _loaded = false, _open = false;
  FarmMoney _money = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  /// usePermissions().isAdmin: anyone who is not plain staff.
  bool get _isAdmin => (widget.company.role ?? '').toLowerCase() != 'staff';
  String get _fq => 'farmId=${Uri.encodeQueryComponent(widget.company.farmId)}';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.session.farmClient.get('$_root/manual', query: {'farmId': widget.company.farmId});
      if (mounted) setState(() => _rows = rowsOf(res));
    } on ApiException {
      if (mounted) setState(() => _rows = []);
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _add() async {
    final n = await showDialog<String>(
      context: context,
      builder: (_) => _ManualDeferredCostDialog(session: widget.session, company: widget.company, money: _money),
    );
    if (n == null || !mounted) return;
    trackerToast(context, 'Entry recorded', description: '$n: recognised on Profit & Loss as the stock is used.');
    setState(() => _open = true);
    _load();
    widget.onChanged?.call();
  }

  Future<void> _reverse(Map r) async {
    num? reversed;
    final ok = await showReverseWithReason(
      context,
      title: 'Reverse ${tStr(r['entryNumber'])}?',
      description: 'It stays in the history, marked Reversed.',
      action: 'Reverse',
      body: [
        warnBox([
          TextSpan(text: _money(tNum(r['remaining'])), style: boldSpan),
          const TextSpan(text: ' not yet recognised is taken back. '),
          TextSpan(text: _money(tNum(r['recognised'])), style: boldSpan),
          const TextSpan(text: ' already on Profit & Loss through usage stays there. The stock itself does not change.'),
        ]),
      ],
      onConfirm: (reason) async {
        final res = await widget.session.farmClient
            .post('$_root/manual/${tStr(r['entryId'])}/reverse?$_fq', body: {'farmId': widget.company.farmId, 'reason': reason});
        reversed = res is Map ? tNum(res['reversedAmount']) : null;
      },
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Entry reversed',
        description:
            '${tStr(r['entryNumber'])}: ${_money(reversed ?? 0)} not yet recognised was taken back. What was already on Profit & Loss stays.');
    _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || (_rows.isEmpty && !_isAdmin)) return const SizedBox.shrink();
    final waiting = _rows.where((r) => r['status'] == 'Posted').fold<num>(0, (t, r) => t + tNum(r['remaining']));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.violet200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: _rows.isEmpty ? null : () => setState(() => _open = !_open),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_rows.isNotEmpty) Icon(_open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 18, color: TColors.slate500),
            const Icon(Icons.layers_outlined, size: 16, color: _violet600),
            const SizedBox(width: 6),
            const Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Manual entries', style: TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
                  TextSpan(text: ' — cost for stock no purchase covers (e.g. opening stock)', style: TextStyle(color: TColors.slate500)),
                ]),
                style: TextStyle(fontSize: 13),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (_rows.isNotEmpty)
            Text('${_money(waiting)} waiting', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _violet700)),
          if (_isAdmin)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _violet600),
              onPressed: _add,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Manual deferred cost entry'),
            ),
        ]),
        if (_open && _rows.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final r in _rows) _entry(r),
        ],
      ]),
    );
  }

  Widget _entry(Map r) {
    final reversed = r['status'] == 'Reversed';
    final grey = reversed ? TColors.slate400 : TColors.slate900;
    Widget kv(String k, String v, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(children: [
            Expanded(child: Text(k, style: const TextStyle(fontSize: 12, color: TColors.slate500))),
            Text(v, style: TextStyle(fontSize: 12, color: color ?? grey, fontWeight: bold ? FontWeight.w600 : FontWeight.w400)),
          ]),
        );
    final detail = [r['reason'], r['reference'], r['notes']].map(tStr).where((s) => s.isNotEmpty).join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('${tStr(r['entryNumber'])} · ${tStr(r['itemName']).isEmpty ? 'Item ${tStr(r['poultryRawMaterialItemId'])}' : tStr(r['itemName'])}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: grey)),
          ),
          if (reversed) greyBadge('Reversed'),
        ]),
        Text('${fmtDateTime(r['effectiveDate'], null, _offset)} · ${manualDeferredEntryLabel[tStr(r['entryType'])] ?? tStr(r['entryType'])}',
            style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        const SizedBox(height: 4),
        kv('Quantity', '${loc(tNum(r['quantity']))} ${tStr(r['unitOfMeasure'])}'.trim()),
        kv('Cost', _money(tNum(r['amount']))),
        kv('On P&L', _money(tNum(r['recognised']))),
        kv('Waiting', _money(tNum(r['remaining'])), color: reversed ? TColors.slate400 : _violet700, bold: true),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(detail, style: TextStyle(fontSize: 12, color: reversed ? TColors.slate400 : TColors.slate600)),
        ],
        if (reversed)
          Text('Reversed ${r['reversedAmount'] != null ? _money(tNum(r['reversedAmount'])) : ''}: ${tStr(r['reversalReason'])}',
              style: const TextStyle(fontSize: 12, color: TColors.slate400)),
        if (!reversed && _isAdmin) ...[
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerRight, child: cardAction('Reverse', Icons.undo, () => _reverse(r))),
        ],
      ]),
    );
  }
}

class _ManualDeferredCostDialog extends StatefulWidget {
  const _ManualDeferredCostDialog({required this.session, required this.company, required this.money});
  final Session session;
  final Company company;
  final FarmMoney money;
  @override
  State<_ManualDeferredCostDialog> createState() => _ManualDeferredCostDialogState();
}

class _ManualDeferredCostDialogState extends State<_ManualDeferredCostDialog> {
  List<Map>? _items;
  int? _itemId;
  final _amount = TextEditingController(), _qty = TextEditingController(), _ref = TextEditingController(), _notes = TextEditingController();
  String _date = localToday(), _type = 'OpeningDeferredCost', _reason = '';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.session.farmClient.get('$_root/uncovered-stock', query: {'farmId': widget.company.farmId}).then((res) {
      if (mounted) setState(() => _items = rowsOf(res));
    }).catchError((Object _) {
      if (mounted) setState(() => _items = []);
    });
  }

  @override
  void dispose() {
    for (final c in [_amount, _qty, _ref, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Map? get _item => _items?.where((i) => tIntOrNull(i['poultryRawMaterialItemId']) == _itemId).firstOrNull;
  num get _amt => ((num.tryParse(_amount.text) ?? 0) * 100).round() / 100;
  num get _q => num.tryParse(_qty.text) ?? 0;
  bool get _valid =>
      _item != null && _amt > 0 && _q > 0 && _q <= tNum(_item!['uncoveredQuantity']) + 0.0005 && _date.isNotEmpty && _reason.trim().isNotEmpty;

  Future<void> _save() async {
    final item = _item;
    if (item == null || !_valid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final farmId = widget.company.farmId;
    try {
      final res = await widget.session.farmClient.post('$_root/manual?farmId=${Uri.encodeQueryComponent(farmId)}', body: {
        'poultryRawMaterialItemId': tIntOrNull(item['poultryRawMaterialItemId']),
        'amount': _amt,
        'quantity': _q,
        'effectiveDate': _date,
        'entryType': _type,
        'reason': _reason.trim(),
        'reference': _ref.text.trim().isEmpty ? null : _ref.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'farmId': farmId,
      });
      if (mounted) Navigator.pop(context, res is Map ? tStr(res['entryNumber']) : '');
      return;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items, item = _item;
    final unit = tStr(item?['unitOfMeasure']);
    final numFmt = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))];
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Row(children: [
          Icon(Icons.layers_outlined, color: _violet600),
          SizedBox(width: 8),
          Flexible(child: Text('Manual deferred cost entry')),
        ]),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'Cost for stock you already hold that no purchase here covers, e.g. opening stock. It goes on Profit & Loss as the stock '
              'is used, like any stock expensed when used. No purchase, no supplier, no cash, and the stock quantity does not change.',
              style: TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 14),
            FilterLabel(
              'Item *',
              items == null
                  ? const Text('Loading items…', style: TextStyle(fontSize: 13, color: TColors.slate500))
                  : items.isEmpty
                      ? summaryBox(const [
                          TextSpan(text: "Every item's stock is already covered by its purchases, so there is nothing to add a manual cost for."),
                        ])
                      : AppSelect<int>(
                          value: _itemId,
                          hintText: 'Choose the item',
                          items: [
                            for (final i in items)
                              AppSelectItem(
                                value: tIntOrNull(i['poultryRawMaterialItemId'])!,
                                label: '${tStr(i['itemName'])} · ${loc(tNum(i['uncoveredQuantity']))} ${tStr(i['unitOfMeasure'])} not covered',
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            _itemId = v;
                            if (_item != null) _qty.text = '${tNum(_item!['uncoveredQuantity'])}';
                          }),
                        ),
            ),
            const SizedBox(height: 10),
            filterRow([
              FilterLabel(
                'Quantity *${unit.isEmpty ? '' : ' ($unit)'}',
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  AppInput(
                    controller: _qty,
                    enabled: item != null,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: numFmt,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (item != null)
                    Text('At most ${loc(tNum(item['uncoveredQuantity']))} $unit.', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                ]),
              ),
              FilterLabel(
                'Cost *',
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  AppInput(
                    controller: _amount,
                    hintText: '0.00',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: numFmt,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_amt > 0 && _q > 0)
                    Text('${widget.money(_amt / _q)} per ${unit.isEmpty ? 'unit' : unit}', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            filterRow([
              FilterLabel('Effective date *', FilterDate(value: _date, hint: 'Date', onChanged: (v) => setState(() => _date = v))),
              FilterLabel(
                'Type *',
                AppSelect<String>(
                  value: _type,
                  items: [for (final e in manualDeferredEntryLabel.entries) AppSelectItem(value: e.key, label: e.value)],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            FilterLabel(
              'Reason *',
              ReasonSelect(options: deferredCostReasons, value: _reason, onChanged: (v) => setState(() => _reason = v)),
            ),
            const SizedBox(height: 10),
            FilterLabel('Reference', AppInput(controller: _ref, hintText: 'Optional, e.g. stock sheet')),
            const SizedBox(height: 10),
            FilterLabel('Notes', AppInput(controller: _notes, hintText: 'Optional', minLines: 2, maxLines: 4)),
            if (_error != null) ...[const SizedBox(height: 10), TrackerBanner.error(_error!)],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _violet600),
            onPressed: !_valid || _saving ? null : _save,
            child: Text(_saving ? 'Recording…' : 'Record entry'),
          ),
        ],
      ),
    );
  }
}
