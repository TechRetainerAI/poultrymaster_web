// Generic → Sales → Customer Credits (`app/generic-customer-credits/page.tsx`)
// and Generic → Purchasing → Supplier Credits & Advances
// (`app/generic-supplier-credits/page.tsx`): advances, overpayments and credit
// notes held for a customer, or with a supplier. One screen; `supplier: true`
// is the second page. Only the words, the party, the type order and the API
// differ.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import 'generic_kit.dart';
import 'generic_products_screen.dart' show genericEmptyCard;
import 'reports/generic_report_kit.dart' show fmtMoney;

import 'package:poultrycore_mobile/design/tone.dart';

const genericCustomerCreditTypes = ['Overpayment', 'Advance', 'CreditNote', 'Refund'];
const genericSupplierCreditTypes = ['Advance', 'CreditNote', 'Overpayment', 'Refund'];

/// Total credits, the active balance and what has been used (the web's cards).
({num total, num active, num used}) genericCreditTotals(List<Map> rows) {
  num total = 0, active = 0, used = 0;
  for (final c in rows) {
    total += tNum(c['amount']);
    if (c['status'] == 'Active') {
      active += tNum(c['remainingBalance']);
    } else {
      used += tNum(c['amount']) - tNum(c['remainingBalance']);
    }
  }
  return (total: total, active: active, used: used);
}

Widget _badge(String text, Map<String, (Color, Color)> colors) {
  final c = colors[text] ?? (TColors.slate100, TColors.slate700);
  return TBadge(text, bg: c.$1, fg: c.$2);
}

const _typeColors = {
  'Overpayment': (TColors.blue100, Tone.fg(0xFF1D4ED8)),
  'Advance': (Tone.bg(0xFFE0E7FF), Tone.fg(0xFF4338CA)),
  'CreditNote': (TColors.violet100, TColors.violet700),
  'Refund': (TColors.amber100, TColors.amber700),
};
const _customerStatusColors = {
  'Active': (TColors.emerald100, TColors.emerald700),
  'Used': (TColors.slate100, TColors.slate700),
  'Expired': (TColors.amber100, TColors.amber700),
};
const _supplierStatusColors = {
  'Active': (TColors.emerald100, TColors.emerald700),
  'Used': (TColors.slate100, TColors.slate700),
};

class _Side {
  const _Side(this.supplier);
  final bool supplier;
  String get path => supplier ? 'supplier-credits' : 'customer-credits';
  String get parties => supplier ? 'suppliers' : 'customers';
  String get partyId => supplier ? 'genericSupplierId' : 'genericCustomerId';
  String get partyName => supplier ? 'supplierName' : 'customerName';
  String get creditId => supplier ? 'genericSupplierCreditId' : 'genericCustomerCreditId';
  String get href => supplier ? '/generic-supplier-credits' : '/generic-customer-credits';
  String get title => supplier ? 'Supplier Credits & Advances' : 'Customer Credits';
  String get blurb => supplier ? 'Credit held with suppliers, advance payments and credit notes.' : 'Advances, overpayments and credit notes held for customers.';
  String get party => supplier ? 'Supplier' : 'Customer';
  List<String> get types => supplier ? genericSupplierCreditTypes : genericCustomerCreditTypes;
  Map<String, (Color, Color)> get statusColors => supplier ? _supplierStatusColors : _customerStatusColors;
}

class GenericCreditsScreen extends StatefulWidget {
  const GenericCreditsScreen({super.key, required this.session, required this.company, this.supplier = false});
  final Session session;
  final Company company;
  final bool supplier;
  @override
  State<GenericCreditsScreen> createState() => _GenericCreditsScreenState();
}

class _GenericCreditsScreenState extends State<GenericCreditsScreen> {
  List<Map> _rows = [], _parties = [];
  bool _loading = true;
  int _page = 1, _size = 10;
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _base => genericBase(widget.company);
  _Side get _side => _Side(widget.supplier);

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([_api.get('$_base/${_side.path}'), _api.get('$_base/${_side.parties}')]);
      if (mounted) {
        setState(() {
          _rows = rowsOf(r[0]);
          _parties = rowsOf(r[1]);
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _new() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => GenericCreditDialog(session: widget.session, company: widget.company, parties: _parties, supplier: widget.supplier),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _side;
    final lead = sidebarLeading(context, widget.session, widget.company, href: s.href);
    final t = genericCreditTotals(_rows);
    String who(Map c) => tStr(c[s.partyName]).isEmpty ? 'Unknown' : tStr(c[s.partyName]);
    Widget card(String label, num v, {Color? color}) => Expanded(
          child: TCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .4, color: TColors.slate500)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(fmtMoney(v), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color ?? TColors.slate900)),
              ),
            ]),
          ),
        );
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(s.title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(children: [
              Icon(widget.supplier ? Icons.handshake_outlined : Icons.card_giftcard, size: 22, color: genericEmerald),
              const SizedBox(width: 8),
              Expanded(child: Text(s.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            Text(s.blurb, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const ValueKey('credit-new'),
              onPressed: _new,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Credit'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              card('Total Credits', t.total),
              const SizedBox(width: 8),
              card('Active Balance', t.active, color: TColors.emerald700),
              const SizedBox(width: 8),
              card('Used', t.used, color: TColors.slate500),
            ]),
            const SizedBox(height: 12),
            if (_loading)
              const LoadingLine('Loading…')
            else if (_rows.isEmpty)
              genericEmptyCard('No credits.')
            else
              MobileCardList<Map>(
                items: pageSlice(_rows, _page, _size),
                keyOf: (c) => '${tIntOrNull(c[s.creditId])}',
                primary: who,
                secondary: (c) => fmtDateTime(c['creditDate'], c, _offset),
                trailing: (c) => Padding(padding: const EdgeInsets.only(left: 6), child: _badge(tStr(c['status']), s.statusColors)),
                highlights: (c) => [
                  Highlight('Amount', fmtMoney(c['amount']), accent: Accent.blue),
                  Highlight('Remaining', fmtMoney(c['remainingBalance']), accent: tNum(c['remainingBalance']) > 0 ? Accent.emerald : Accent.slate),
                ],
                details: (c) => [
                  ('Type', tStr(c['creditType'])),
                  ('Notes', tStr(c['notes']).isEmpty ? '—' : tStr(c['notes'])),
                ],
                striped: true,
                stripeBlue: true,
                table: (items) => TrackerTable(
                  columns: [
                    const TCol('Date', width: 140), TCol(s.party, width: 150), const TCol('Type', width: 120),
                    const TCol('Amount', right: true, width: 110), const TCol('Remaining', right: true, width: 110),
                    const TCol('Status', width: 90), const TCol('Notes', width: 180),
                  ],
                  rows: [
                    for (final c in items)
                      [
                        cellText(fmtDateTime(c['creditDate'], c, _offset)),
                        cellText(tStr(c[s.partyName]).isEmpty ? '—' : tStr(c[s.partyName]), bold: true),
                        Align(alignment: Alignment.centerLeft, child: _badge(tStr(c['creditType']), _typeColors)),
                        Align(alignment: Alignment.centerRight, child: cellText(fmtMoney(c['amount']))),
                        Align(alignment: Alignment.centerRight, child: cellText(fmtMoney(c['remainingBalance']), bold: true)),
                        Align(alignment: Alignment.centerLeft, child: _badge(tStr(c['status']), s.statusColors)),
                        cellText(tStr(c['notes']).isEmpty ? '—' : tStr(c['notes']), color: TColors.slate600),
                      ],
                  ],
                ),
                pager: CompactPager(
                  total: _rows.length,
                  page: _page,
                  pageSize: _size,
                  onPage: (p) => setState(() => _page = p),
                  onPageSize: (v) => setState(() {
                    _size = v;
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

/// "Record customer credit" (or supplier credit). Pops true when saved.
class GenericCreditDialog extends StatefulWidget {
  const GenericCreditDialog({super.key, required this.session, required this.company, required this.parties, this.supplier = false});
  final Session session;
  final Company company;
  final List<Map> parties;
  final bool supplier;
  @override
  State<GenericCreditDialog> createState() => _GenericCreditDialogState();
}

class _GenericCreditDialogState extends State<GenericCreditDialog> {
  late final _Side _s = _Side(widget.supplier);
  String _partyId = '';
  late String _type = _s.types.first;
  String _date = DateTime.now().toIso8601String().substring(0, 10);
  final _amount = TextEditingController(text: '0'), _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_partyId.isEmpty) return trackerToast(context, 'Select a ${_s.party.toLowerCase()}', error: true);
    final amount = num.tryParse(_amount.text) ?? 0;
    if (amount <= 0) return trackerToast(context, 'Amount must be > 0', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('${genericBase(widget.company)}/${_s.path}', body: {
        _s.partyId: int.parse(_partyId),
        'creditType': _type,
        'amount': amount,
        'creditDate': _date,
        'notes': _notes.text,
        'farmId': widget.company.farmId,
      });
      if (!mounted) return;
      trackerToast(context, 'Credit recorded');
      Navigator.pop(context, true);
      return;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _field(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
          const SizedBox(height: 6),
          child,
        ]),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(widget.supplier ? 'Record supplier credit' : 'Record customer credit'),
        content: SizedBox(
          width: 512,
          child: formSection('Credit details', const Tone.bg(0xFF4F46E5), [
            _field(
              '${_s.party} *',
              AppSelect<String>(
                key: const ValueKey('credit-party'),
                value: _partyId.isEmpty ? null : _partyId,
                hintText: 'Select ${_s.party.toLowerCase()}',
                items: [
                  for (final p in widget.parties)
                    if (p['isActive'] != false)
                      AppSelectItem(value: tStr(p[_s.partyId]), label: tStr(p[_s.partyName])),
                ],
                onChanged: (v) => setState(() => _partyId = v ?? ''),
              ),
            ),
            _field(
              'Credit type',
              AppSelect<String>(
                key: const ValueKey('credit-type'),
                value: _type,
                items: [for (final t in _s.types) AppSelectItem(value: t, label: t)],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
            ),
            _field(
              'Amount *',
              AppInput(
                key: const ValueKey('credit-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              ),
            ),
            _field('Date', AppDateField(value: businessDateAsDateTime(_date), onChanged: (v) => setState(() => _date = v == null ? '' : isoDay(v)))),
            _field('Notes', AppInput(key: const ValueKey('credit-notes'), controller: _notes)),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('credit-save'),
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Record Credit'),
          ),
        ],
      );
}
