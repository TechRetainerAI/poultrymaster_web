// Poultry → Operations → Inventory & Health → Loss & Damage
// (app/poultry-loss-records/page.tsx): striped cards with the type and value
// tiles, Approve / Edit / Delete on pending records and Unapprove on approved
// ones, the table view, and the New / Edit loss record dialog.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../delivery/delivery_dialogs.dart' show NumBox;
import '../money/money_widgets.dart' show formSection;
import '../reports/report_format.dart';
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart' show CompactPager;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc;
import '../trackers/tracker_widgets.dart';

const lossTypes = ['Damage', 'Mortality', 'Theft', 'Spoilage', 'MissingStock', 'Other'];

/// The save body: an unset product, quantity or value goes as null.
Map<String, Object?> lossPayload({
  required String lossDate,
  required String lossType,
  required int productId,
  required num quantity,
  required num estimatedValue,
  required String reason,
  required String notes,
}) =>
    {
      'lossDate': lossDate,
      'lossType': lossType,
      'poultryProductId': productId == 0 ? null : productId,
      'quantity': quantity == 0 ? null : quantity,
      'estimatedValue': estimatedValue == 0 ? null : estimatedValue,
      'reason': reason,
      'notes': notes,
    };

class LossRecordsScreen extends StatefulWidget {
  const LossRecordsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<LossRecordsScreen> createState() => _LossRecordsScreenState();
}

class _LossRecordsScreenState extends State<LossRecordsScreen> {
  List<Map> _rows = [], _products = [];
  bool _loading = true, _table = false;
  int _page = 1, _size = 10;
  FarmMoney _fmt = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  Map<String, String> get _farm => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        _api.get('/api/Poultry/loss-records', query: _farm).then(rowsOf),
        _api.get('/api/Poultry/products', query: _farm).then(rowsOf),
      ]);
      if (mounted) {
        setState(() {
          _rows = r[0];
          _products = r[1];
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load loss records', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _post(Map l, String leaf, String ok) async {
    try {
      await _api.post('/api/Poultry/loss-records/${l['poultryLossRecordId']}/$leaf', query: _farm);
      if (mounted) trackerToast(context, ok);
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  Future<void> _form([Map? editing]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => LossRecordDialog(session: widget.session, company: widget.company, products: _products, editing: editing),
    );
    if (ok == true) await _load();
  }

  /// ConfirmDeleteDialog: the page's "Removed", then the dialog's "Deleted".
  Future<void> _delete(Map l) async {
    final yes = await confirmDelete(context, title: 'Delete loss record?', description: 'This removes the pending record.');
    if (!yes || !mounted) return;
    try {
      await _api.delete('/api/Poultry/loss-records/${l['poultryLossRecordId']}?farmId=${Uri.encodeQueryComponent(widget.company.farmId)}');
      if (mounted) trackerToast(context, 'Removed');
      await _load();
      if (mounted) trackerToast(context, 'Deleted');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  Widget _status(Map l) => tStr(l['status']) == 'Approved'
      ? const TBadge('Approved', bg: TColors.green100, fg: TColors.green700)
      : const TBadge('Pending', bg: TColors.amber100, fg: TColors.amber700);

  String _qty(Map l) => l['quantity'] == null ? '—' : loc(tNum(l['quantity']));
  String _value(Map l) => l['estimatedValue'] == null ? '—' : _fmt(tNum(l['estimatedValue']));

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-loss-records');
    final pageRows = pageSlice(_rows, _page, _size);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Loss & Damage Records')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Loss & Damage Records', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900)),
                  Text('Manual losses — damages, mortality, spoilage, missing stock.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
                ]),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: () => _form(), icon: const Icon(Icons.add, size: 16), label: const Text('New record')),
            ]),
            const SizedBox(height: 14),
            TCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_loading)
                  const Padding(padding: EdgeInsets.all(24), child: Text('Loading…', style: TextStyle(color: TColors.slate500)))
                else if (!_table) ...[
                  if (_rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('No loss records yet.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
                    )
                  else ...[
                    for (var i = 0; i < pageRows.length; i++) ...[_card(pageRows[i], i), const SizedBox(height: 10)],
                    ViewTableButton(onPressed: () => setState(() => _table = true)),
                  ],
                ] else ...[
                  TableViewBar(text: 'Table view • Scroll → for more', onCards: () => setState(() => _table = false)),
                  if (_rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('No loss records yet.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
                    )
                  else
                    _tableView(pageRows),
                ],
                CompactPager(total: _rows.length, page: _page, pageSize: _size, onPage: (x) => setState(() => _page = x), onPageSize: (s) => setState(() {
                      _size = s;
                      _page = 1;
                    })),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Map l, int i) {
    Widget tile(String label, String value, Color bg, Color border, Color lc, Color vc) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: lc)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: vc)),
            ),
          ]),
        );
    final pending = tStr(l['status']) == 'Pending';
    Widget btn(String label, IconData icon, VoidCallback onTap, {Color? fg, Color? border}) => OutlinedButton.icon(
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
    return _LossCard(
      key: ValueKey('loss-${l['poultryLossRecordId']}'),
      striped: i.isEven,
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(fmtDateTime(l['lossDate'], l, _offset), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
          _status(l),
        ]),
        const SizedBox(height: 2),
        Text(tStr(l['productName']).isEmpty ? 'No product' : tStr(l['productName']),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: tile(tStr(l['lossType']), _qty(l), TColors.rose100, const Color(0xFFFDA4AF), const Color(0xFF881337), TColors.rose800)),
          const SizedBox(width: 8),
          Expanded(child: tile('Value', _value(l), TColors.violet100, const Color(0xFFC4B5FD), const Color(0xFF4C1D95), const Color(0xFF4C1D95))),
        ]),
      ]),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (tStr(l['reason']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'Reason ', style: TextStyle(color: TColors.slate500)),
              TextSpan(text: tStr(l['reason']), style: const TextStyle(fontWeight: FontWeight.w500)),
            ]), style: const TextStyle(fontSize: 14)),
          ),
        if (pending) ...[
          Row(children: [
            Expanded(
                child: btn('Approve', Icons.check_circle_outline, () => _post(l, 'approve', 'Approved'),
                    fg: TColors.green700, border: const Color(0xFFBBF7D0))),
            const SizedBox(width: 8),
            Expanded(child: btn('Edit', Icons.edit_outlined, () => _form(l))),
          ]),
          const SizedBox(height: 8),
          btn('Delete', Icons.delete_outline, () => _delete(l), fg: TColors.red600, border: TColors.red200),
        ] else
          btn('Unapprove', Icons.undo, () => _post(l, 'unapprove', 'Reverted to pending'), fg: TColors.amber700, border: TColors.amber200),
      ]),
    );
  }

  Widget _tableView(List<Map> rows) {
    IconButton icon(String? tip, IconData i, VoidCallback onTap, {Color? color}) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(i, size: 18, color: color),
          onPressed: onTap,
        );
    return TrackerTable(
      columns: const [
        TCol('Date', width: 150), TCol('Type', width: 110), TCol('Product', width: 120), TCol('Qty', right: true, width: 80),
        TCol('Value', right: true, width: 110), TCol('Status', width: 100), TCol('Actions', width: 140),
      ],
      rows: [
        for (final l in rows)
          [
            cellText(fmtDateTime(l['lossDate'], l, _offset)),
            cellText(tStr(l['lossType'])),
            cellText(tStr(l['productName']).isEmpty ? '—' : tStr(l['productName'])),
            cellText(_qty(l)),
            cellText(_value(l)),
            Align(alignment: Alignment.centerLeft, child: _status(l)),
            Wrap(alignment: WrapAlignment.end, children: [
              if (tStr(l['status']) == 'Pending') ...[
                icon('Approve', Icons.check_circle_outline, () => _post(l, 'approve', 'Approved'), color: TColors.green700),
                icon(null, Icons.edit_outlined, () => _form(l)),
                icon(null, Icons.delete_outline, () => _delete(l), color: TColors.red600),
              ] else
                icon('Unapprove', Icons.undo, () => _post(l, 'unapprove', 'Reverted to pending'), color: TColors.amber600),
            ]),
          ],
      ],
    );
  }
}

class _LossCard extends StatefulWidget {
  const _LossCard({super.key, required this.striped, required this.header, required this.body});
  final bool striped;
  final Widget header, body;
  @override
  State<_LossCard> createState() => _LossCardState();
}

class _LossCardState extends State<_LossCard> {
  bool _open = true;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: widget.striped ? TColors.amber100 : Colors.white,
          border: Border.all(color: widget.striped ? TColors.amber300 : TColors.slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Stack(children: [
              Padding(padding: const EdgeInsets.only(right: 24), child: widget.header),
              Positioned(
                right: 0,
                top: 0,
                child: Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: TColors.slate400),
              ),
            ]),
          ),
          if (_open) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            widget.body,
          ],
        ]),
      );
}

class LossRecordDialog extends StatefulWidget {
  const LossRecordDialog({super.key, required this.session, required this.company, required this.products, this.editing});
  final Session session;
  final Company company;
  final List<Map> products;
  final Map? editing;
  @override
  State<LossRecordDialog> createState() => _LossRecordDialogState();
}

class _LossRecordDialogState extends State<LossRecordDialog> {
  late final Map? _e = widget.editing;
  late String _date = _e == null ? DateTime.now().toUtc().toIso8601String().substring(0, 10) : tStr(_e['lossDate']).split('T').first;
  late String _type = _e == null ? 'Damage' : tStr(_e['lossType']);
  late int _product = tIntOrNull(_e?['poultryProductId']) ?? 0;
  late num _qty = tNum(_e?['quantity']), _value = tNum(_e?['estimatedValue']);
  late String _reason = tStr(_e?['reason']);
  late final String _notes = tStr(_e?['notes']);
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = {
      ...lossPayload(lossDate: _date, lossType: _type, productId: _product, quantity: _qty, estimatedValue: _value, reason: _reason, notes: _notes),
      'farmId': widget.company.farmId,
    };
    try {
      final id = tIntOrNull(_e?['poultryLossRecordId']);
      if (id != null) {
        await widget.session.farmClient.put('/api/Poultry/loss-records/$id', body: {...body, 'poultryLossRecordId': id});
      } else {
        await widget.session.farmClient.post('/api/Poultry/loss-records', body: body);
      }
      if (!mounted) return;
      trackerToast(context, id != null ? 'Loss record updated' : 'Loss record added');
      Navigator.pop(context, true);
      return;
    } on ApiException catch (ex) {
      if (mounted) trackerToast(context, 'Save failed', description: ex.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
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
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(_e != null ? 'Edit loss record' : 'New loss record'),
        content: SizedBox(
          width: 480,
          child: formSection('Loss details', const Color(0xFFD97706), [
            _cell('Date', AppDateField(value: businessDateAsDateTime(_date), onChanged: (v) => setState(() => _date = v == null ? '' : isoDay(v)))),
            _cell(
              'Type',
              AppSelect<String>(
                value: _type,
                items: [for (final t in lossTypes) AppSelectItem(value: t, label: t)],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
            ),
            _cell(
              'Product (optional)',
              AppSelect<int>(
                value: _product,
                hintText: '—',
                items: [
                  const AppSelectItem(value: 0, label: '—'),
                  for (final p in widget.products) AppSelectItem(value: tIntOrNull(p['poultryProductId']) ?? 0, label: tStr(p['name'])),
                ],
                onChanged: (v) => setState(() => _product = v ?? 0),
              ),
            ),
            _cell('Quantity', NumBox(value: _qty, decimal: true, onChanged: (v) => _qty = v)),
            _cell('Estimated value', NumBox(value: _value, decimal: true, onChanged: (v) => _value = v)),
            _cell('Reason', AppInput(initialValue: _reason, onChanged: (v) => _reason = v)),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
        ],
      );
}
