// Finished-product stock tools shared by Inventory and Stock Movements:
// "Set product stock" (components/inventory/set-product-stock-button.tsx) and
// "Recalculate product stock" (components/inventory/reconcile-product-stock-button.tsx).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, loc;
import '../trackers/tracker_widgets.dart';

const birdStockLockedReason =
    'Bird stock comes from the birds left in your flocks — correct it in the flock / production records (record mortality, or edit the flock).';

/// The products the stock take lists: id, name, current stock, and why it is locked.
List<({int id, String name, num current, String? locked})> stockTakeProducts(List<Map> products) => [
      for (final p in products)
        (
          id: tIntOrNull(p['poultryProductId']) ?? 0,
          name: tStr(p['name']),
          current: tNum(p['stockOnHand']),
          locked: p['isBirdProduct'] == true || tStr(p['name']) == 'Birds' ? birdStockLockedReason : null,
        ),
    ];

class SetProductStockDialog extends StatefulWidget {
  const SetProductStockDialog({super.key, required this.session, required this.company, required this.products});
  final Session session;
  final Company company;
  final List<Map> products;
  @override
  State<SetProductStockDialog> createState() => _SetProductStockDialogState();
}

class _SetProductStockDialogState extends State<SetProductStockDialog> {
  late final _rows = stockTakeProducts(widget.products);
  late final Map<int, TextEditingController> _counts = {for (final p in _rows) p.id: TextEditingController(text: _plain(p.current))};
  final _note = TextEditingController(), _q = TextEditingController();
  bool _busy = false;
  int _done = 0, _total = 0;

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    for (final c in _counts.values) {
      c.dispose();
    }
    _note.dispose();
    _q.dispose();
    super.dispose();
  }

  num? _delta(({int id, String name, num current, String? locked}) p) {
    final raw = _counts[p.id]!.text;
    if (raw.isEmpty) return null;
    final v = num.tryParse(raw);
    return v == null ? null : v - p.current;
  }

  List<({int id, String name, num current, String? locked})> get _changed =>
      [for (final p in _rows) if (p.locked == null && (_delta(p) ?? 0) != 0) p];

  void _resetAll() => setState(() {
        for (final p in _rows) {
          _counts[p.id]!.text = _plain(p.current);
        }
      });

  Future<void> _save() async {
    final changed = _changed;
    if (changed.isEmpty) {
      trackerToast(context, 'No changes to apply');
      return;
    }
    setState(() {
      _busy = true;
      _done = 0;
      _total = changed.length;
    });
    var ok = 0, fail = 0;
    for (final p in changed) {
      try {
        await widget.session.farmClient.post('/api/Poultry/products/${p.id}/set-stock', body: {
          'farmId': widget.company.farmId,
          'targetQuantity': num.parse(_counts[p.id]!.text),
          'note': _note.text.isEmpty ? 'Stock-take correction' : _note.text,
          'createdBy': widget.session.tokens.userId ?? '',
        });
        ok++;
      } on ApiException {
        fail++;
      }
      if (mounted) setState(() => _done++);
    }
    if (!mounted) return;
    trackerToast(context, 'Stock updated', description: '$ok product(s) corrected${fail > 0 ? ', $fail failed' : ''}.', error: fail > 0);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final changed = _changed;
    final net = changed.fold<num>(0, (s, p) => s + (_delta(p) ?? 0));
    final term = _q.text.trim().toLowerCase();
    final visible = term.isEmpty ? _rows : [for (final p in _rows) if (p.name.toLowerCase().contains(term)) p];

    Widget pill(String text, Color bg, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
          child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
        );

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: const EdgeInsets.all(16),
          color: TColors.slate50,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: TColors.emerald100, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.fact_check_outlined, size: 20, color: TColors.emerald700),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Stock take — set product stock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: "Enter each product's "),
                    TextSpan(text: 'actual (physical) count', style: TextStyle(fontWeight: FontWeight.w500, color: TColors.slate700)),
                    TextSpan(text: '. We write a correcting stock entry for every row that changed, so the displayed stock matches your count.'),
                  ]),
                  style: TextStyle(fontSize: 13, color: TColors.slate500),
                ),
              ]),
            ),
          ]),
        ),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppInput(
              controller: _q,
              hintText: 'Find a product…',
              prefixIcon: const Icon(Icons.search, size: 18, color: TColors.slate400),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              pill('${changed.length} change${changed.length == 1 ? '' : 's'}', changed.isNotEmpty ? TColors.amber100 : TColors.slate100,
                  changed.isNotEmpty ? TColors.amber800 : TColors.slate600),
              if (changed.isNotEmpty) ...[
                pill('Net ${net > 0 ? '+' : ''}${loc(net)}', net < 0 ? TColors.rose100 : TColors.emerald100, net < 0 ? TColors.rose700 : TColors.emerald700),
                TextButton.icon(onPressed: _busy ? null : _resetAll, icon: const Icon(Icons.undo, size: 14), label: const Text('Reset')),
              ],
            ]),
            const SizedBox(height: 8),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_rows.isEmpty ? 'No finished products.' : 'No products match your search.',
                    textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate500)),
              )
            else
              for (final p in visible) _row(p),
            const SizedBox(height: 12),
            const Text('Note (optional)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
            const SizedBox(height: 4),
            AppInput(controller: _note, enabled: !_busy, hintText: 'e.g. month-end stock take'),
            const SizedBox(height: 4),
            const Text('Saved on every correcting entry, so the audit log explains the adjustment.',
                style: TextStyle(fontSize: 12, color: TColors.slate500)),
            const SizedBox(height: 12),
            Text(
              _busy && _total > 0
                  ? 'Saving $_done of $_total…'
                  : changed.isEmpty
                      ? 'No corrections yet — edit an actual count to begin.'
                      : '${changed.length} product(s) will be corrected.',
              style: const TextStyle(fontSize: 12, color: TColors.slate500),
            ),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: _busy || changed.isEmpty ? null : _save, child: Text(_busy ? 'Saving…' : 'Save corrections')),
        ],
      ),
    );
  }

  Widget _row(({int id, String name, num current, String? locked}) p) {
    final delta = p.locked != null ? null : _delta(p);
    final dirty = delta != null && delta != 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: dirty ? TColors.amber50 : Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Opacity(
        opacity: p.locked != null ? .7 : 1,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Flexible(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w500))),
            if (p.locked != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.lock_outline, size: 14, color: TColors.slate400),
              Tooltip(
                message: p.locked!,
                triggerMode: TooltipTriggerMode.tap,
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.info_outline, size: 14, color: TColors.slate400)),
              ),
            ],
            const Spacer(),
            Text('Current ${loc(p.current)}', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Text('Actual count', style: TextStyle(fontSize: 12, color: TColors.slate500)),
            const SizedBox(width: 8),
            Expanded(
              child: p.locked != null
                  ? const Text('Locked', style: TextStyle(fontSize: 12, color: TColors.slate400))
                  : AppInput(
                      controller: _counts[p.id],
                      enabled: !_busy,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      onChanged: (_) => setState(() {}),
                    ),
            ),
            if (dirty)
              IconButton(
                tooltip: 'Reset ${p.name}',
                icon: const Icon(Icons.close, size: 14),
                onPressed: _busy ? null : () => setState(() => _counts[p.id]!.text = _plain(p.current)),
              ),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            const Text('Change ', style: TextStyle(fontSize: 12, color: TColors.slate500)),
            if (!dirty)
              const Text('—', style: TextStyle(color: TColors.slate400))
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: delta < 0 ? TColors.rose100 : TColors.emerald100, borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(delta < 0 ? Icons.arrow_downward : Icons.arrow_upward, size: 12, color: delta < 0 ? TColors.rose700 : TColors.emerald700),
                  Text('${delta > 0 ? '+' : ''}${loc(delta)}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: delta < 0 ? TColors.rose700 : TColors.emerald700)),
                ]),
              ),
          ]),
        ]),
      ),
    );
  }
}

class ReconcileProductStockDialog extends StatefulWidget {
  const ReconcileProductStockDialog({super.key, required this.session, required this.company, required this.products});
  final Session session;
  final Company company;
  final List<Map> products;
  @override
  State<ReconcileProductStockDialog> createState() => _ReconcileProductStockDialogState();
}

class _ReconcileProductStockDialogState extends State<ReconcileProductStockDialog> {
  String _target = 'all';
  bool _busy = false, _ran = false;
  List<Map>? _result;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final r = await widget.session.farmClient.get('/api/Poultry/products/reconcile-stock',
          query: {'farmId': widget.company.farmId, if (_target != 'all') 'productId': _target});
      if (!mounted) return;
      _ran = true;
      setState(() => _result = rowsOf(r));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Recalculate failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final res = _result;
    return AlertDialog(
      scrollable: true,
      title: const Text('Recalculate product stock'),
      content: SizedBox(
        width: 520,
        child: res == null
            ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Finished-product stock is worked out live from its transactions —'),
                    TextSpan(text: ' produced/added in − sold/removed out', style: TextStyle(fontWeight: FontWeight.w500)),
                    TextSpan(text: '. This re-derives it and shows the breakdown so you can verify a figure. To change a finished good, use '),
                    TextSpan(text: 'New stock entry → Adjust', style: TextStyle(fontWeight: FontWeight.w500)),
                    TextSpan(text: '.'),
                  ]),
                  style: TextStyle(fontSize: 14, color: TColors.slate600),
                ),
                const SizedBox(height: 12),
                FilterLabel(
                  'Product to check',
                  AppSelect<String>(
                    value: _target,
                    items: [
                      const AppSelectItem(value: 'all', label: 'All finished products'),
                      for (final p in widget.products) AppSelectItem(value: tStr(p['poultryProductId']), label: tStr(p['name'])),
                    ],
                    onChanged: (v) => setState(() => _target = v ?? 'all'),
                  ),
                ),
              ])
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (res.isEmpty)
                  const Text('No finished products found.', style: TextStyle(fontSize: 14, color: TColors.slate600))
                else
                  TrackerTable(
                    columns: const [TCol('Product', width: 150), TCol('In', right: true, width: 80), TCol('Out', right: true, width: 80), TCol('Current', right: true, width: 90)],
                    rows: [
                      for (final x in res)
                        [
                          cellText(tStr(x['name']), bold: true),
                          cellText(loc(tNum(x['stockIn'])), color: TColors.green700),
                          cellText(loc(tNum(x['stockOut'])), color: TColors.red600),
                          cellText(loc(tNum(x['currentStock'])), bold: true),
                        ],
                    ],
                  ),
                const SizedBox(height: 8),
                const Text('Current = In − Out. Finished stock is ledger-derived, so this verifies rather than overwrites.',
                    style: TextStyle(fontSize: 11, color: TColors.slate400)),
              ]),
      ),
      actions: res == null
          ? [
              OutlinedButton(onPressed: () => Navigator.pop(context, _ran), child: const Text('Cancel')),
              FilledButton(onPressed: _busy ? null : _run, child: Text(_busy ? 'Working…' : 'Recalculate')),
            ]
          : [
              OutlinedButton(onPressed: () => setState(() => _result = null), child: const Text('Back')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Done')),
            ],
    );
  }
}
