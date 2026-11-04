// Generic → Sales → Payments, as `app/generic-customer-payments/page.tsx`:
// money coming in from customers. A payment is recorded as a Draft; approving
// it credits the customer's ledger and adds the cash.
//
// `supplier: true` is Generic → Purchasing → Supplier payments
// (`app/generic-supplier-payments/page.tsx`), the same page the other way:
// money going out to suppliers; approving debits the supplier's ledger and
// takes the cash out. Only the words, the party and the API differ.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import 'generic_kit.dart';
import 'generic_products_screen.dart' show genericBandBlue, genericBandIndigo, genericBandSlate, genericEmptyCard;
import 'reports/generic_report_kit.dart' show fmtMoney;

const genericPaymentStatuses = ['All', 'Draft', 'Approved', 'Cancelled'];
const genericPaymentMethods = ['Cash', 'MoMo', 'Bank', 'Card'];

/// Which side of the page: the party's keys, its API and its words.
class _Side {
  const _Side(this.supplier);
  final bool supplier;
  String get path => supplier ? 'supplier-payments' : 'customer-payments';
  String get parties => supplier ? 'suppliers' : 'customers';
  String get partyId => supplier ? 'genericSupplierId' : 'genericCustomerId';
  String get partyName => supplier ? 'supplierName' : 'customerName';
  String get paymentId => supplier ? 'genericSupplierPaymentId' : 'genericCustomerPaymentId';
  String get href => supplier ? '/generic-supplier-payments' : '/generic-customer-payments';
}

/// badgeClass: Approved emerald, Cancelled rose, else slate.
Widget genericPaymentBadge(Object? status) {
  final (bg, fg) = switch (tStr(status)) {
    'Approved' => (TColors.emerald100, TColors.emerald800),
    'Cancelled' => (TColors.rose100, TColors.rose800),
    _ => (TColors.slate100, TColors.slate800),
  };
  return TBadge(tStr(status), bg: bg, fg: fg);
}

/// The list's filters: search (customer, method, notes) and dates on paymentDate.
List<Map> filterGenericPayments(List<Map> rows, {String search = '', String from = '', String to = '', bool supplier = false}) {
  final q = search.trim().toLowerCase();
  return rows.where((r) {
    final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(r['paymentDate']))?[1];
    if (day != null) {
      if (from.isNotEmpty && day.compareTo(from) < 0) return false;
      if (to.isNotEmpty && day.compareTo(to) > 0) return false;
    }
    if (q.isNotEmpty && ![supplier ? 'supplierName' : 'customerName', 'paymentMethod', 'notes'].any((k) => tStr(r[k]).toLowerCase().contains(q))) return false;
    return true;
  }).toList();
}

class GenericCustomerPaymentsScreen extends StatefulWidget {
  const GenericCustomerPaymentsScreen({super.key, required this.session, required this.company, this.supplier = false});
  final Session session;
  final Company company;

  /// Generic → Purchasing → Supplier payments.
  final bool supplier;

  @override
  State<GenericCustomerPaymentsScreen> createState() => _GenericCustomerPaymentsScreenState();
}

class _GenericCustomerPaymentsScreenState extends State<GenericCustomerPaymentsScreen> {
  List<Map> _rows = [], _customers = [], _accounts = [];
  bool _loading = true;
  String _status = 'All';
  final _search = TextEditingController();
  String _from = '', _to = '';

  /// The form remembers the last cash account picked, as the web's.
  String _accountId = '';
  GenericLabels _l = genericLabels(null);
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _base => genericBase(widget.company);
  _Side get _side => _Side(widget.supplier);
  bool get _sup => widget.supplier;

  @override
  void initState() {
    super.initState();
    loadGenericModules(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _l = m.labels);
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
    try {
      final r = await Future.wait([
        _api.get('$_base/${_side.path}', query: _status == 'All' ? null : {'status': _status}),
        _api.get('$_base/${_side.parties}'),
        _api.get('$_base/cash-accounts'),
      ]);
      if (mounted) {
        setState(() {
          _rows = rowsOf(r[0]);
          _customers = rowsOf(r[1]);
          _accounts = rowsOf(r[2]);
          final first = _accounts.where((a) => a['isActive'] == true).firstOrNull;
          if (first != null && _accountId.isEmpty) _accountId = tStr(first['genericCashAccountId']);
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _record() async {
    final account = await showDialog<String>(
      context: context,
      builder: (_) => GenericCustomerPaymentDialog(
        session: widget.session,
        company: widget.company,
        labels: _l,
        supplier: _sup,
        customers: _customers,
        accounts: _accounts,
        accountId: _accountId,
      ),
    );
    if (account == null) return;
    _accountId = account;
    _load();
  }

  int _id(Map p) => tIntOrNull(p[_side.paymentId]) ?? 0;

  Future<void> _act(Map p, String action, String done, String failed) async {
    final id = _id(p);
    try {
      await _api.post('$_base/${_side.path}/$id/$action', body: {});
      if (mounted) trackerToast(context, 'Payment #$id $done.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, failed, description: e.message, error: true);
    }
  }

  List<Widget> _actions(Map p) => tStr(p['status']) != 'Draft'
      ? const []
      : [
          OutlinedButton.icon(
            onPressed: () => _act(p, 'approve', 'approved', 'Approve failed'),
            style: OutlinedButton.styleFrom(foregroundColor: TColors.emerald700, side: const BorderSide(color: TColors.emerald200)),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Approve'),
          ),
          OutlinedButton.icon(
            onPressed: () => _act(p, 'cancel', 'cancelled', 'Cancel failed'),
            style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: TColors.red200)),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancel'),
          ),
        ];

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: _side.href);
    final visible = filterGenericPayments(_rows, search: _search.text, from: _from, to: _to, supplier: _sup);
    String customer(Map p) => tStr(p[_side.partyName]).isEmpty ? '–' : tStr(p[_side.partyName]);
    final title = _sup ? 'Supplier payments' : _l.paymentPlural;
    final party = _sup ? 'Supplier' : 'Customer';
    final amountColor = _sup ? TColors.rose700 : TColors.emerald700;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(children: [
              Icon(Icons.credit_card, size: 24, color: _sup ? const Color(0xFFEA580C) : genericEmerald),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            Text(
                _sup
                    ? '${_rows.length} payment(s) – money going out to suppliers.'
                    : '${_rows.length} payment(s) – money coming in from ${_l.customerPlural.toLowerCase()}.',
                style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _record, icon: const Icon(Icons.add, size: 18), label: const Text('Record payment')),
            const SizedBox(height: 12),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final s in genericPaymentStatuses)
                filterChipButton(s, s == _status, () {
                  if (s == _status) return;
                  setState(() => _status = s);
                  _load();
                }),
            ]),
            const SizedBox(height: 12),
            if (_loading && _rows.isEmpty)
              const LoadingLine('Loading...')
            else if (_rows.isEmpty)
              genericEmptyCard(_sup ? 'No supplier payments yet.' : 'No ${_l.paymentPlural.toLowerCase()} yet.')
            else ...[
              ListFiltersCard(
                search: _search,
                searchPlaceholder: _sup ? 'Search supplier, method or notes' : 'Search customer, method or notes',
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
                keyOf: (p) => '${_id(p)}',
                primary: (p) => '#${_id(p)} · ${customer(p)}',
                secondary: (p) => '${fmtDateTime(p['paymentDate'], p, _offset)} · ${tStr(p['paymentMethod'])}',
                trailing: (p) => Padding(padding: const EdgeInsets.only(left: 6), child: genericPaymentBadge(p['status'])),
                details: (p) => [
                  ('Date', fmtDateTime(p['paymentDate'], p, _offset)),
                  (party, customer(p)),
                  ('Method', tStr(p['paymentMethod'])),
                  ('Amount', fmtMoney(p['amount'])),
                ],
                detailColor: (p, label) => label == 'Amount' ? amountColor : null,
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: [
                    const TCol('#', width: 60), const TCol('Date', width: 140), TCol(party, width: 150), const TCol('Method', width: 90),
                    const TCol('Amount', right: true, width: 110), const TCol('Status', width: 100), const TCol('', width: 220),
                  ],
                  rows: [
                    for (final p in items)
                      [
                        cellText('#${_id(p)}'),
                        cellText(fmtDateTime(p['paymentDate'], p, _offset)),
                        cellText(customer(p)),
                        cellText(tStr(p['paymentMethod'])),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(fmtMoney(p['amount']), style: TextStyle(fontWeight: FontWeight.w600, color: amountColor)),
                        ),
                        Align(alignment: Alignment.centerLeft, child: genericPaymentBadge(p['status'])),
                        Wrap(spacing: 4, children: _actions(p)),
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

/// New payment (in the template's word). Pops the cash account it used, so
/// the next payment starts on it; null when cancelled.
class GenericCustomerPaymentDialog extends StatefulWidget {
  const GenericCustomerPaymentDialog({
    super.key,
    required this.session,
    required this.company,
    required this.labels,
    required this.customers,
    required this.accounts,
    required this.accountId,
    this.supplier = false,
  });
  final Session session;
  final Company company;
  final GenericLabels labels;
  final List<Map> customers, accounts;
  final String accountId;
  final bool supplier;

  @override
  State<GenericCustomerPaymentDialog> createState() => _GenericCustomerPaymentDialogState();
}

class _GenericCustomerPaymentDialogState extends State<GenericCustomerPaymentDialog> {
  String _customerId = '', _method = 'Cash';
  late String _accountId = widget.accountId;
  String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final _amount = TextEditingController(text: '0'), _notes = TextEditingController();
  bool _saving = false;

  GenericLabels get _l => widget.labels;
  bool get _sup => widget.supplier;
  _Side get _side => _Side(widget.supplier);

  /// The party's word: "Supplier", or the template's customer word.
  String get _party => _sup ? 'Supplier' : _l.customer;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_customerId.isEmpty) return trackerToast(context, 'Pick a ${_party.toLowerCase()}', error: true);
    final amount = num.tryParse(_amount.text) ?? 0;
    if (!(amount > 0)) return trackerToast(context, 'Amount must be greater than zero', error: true);
    setState(() => _saving = true);
    try {
      final created = await widget.session.farmClient.post('${genericBase(widget.company)}/${_side.path}', body: {
        _side.partyId: int.parse(_customerId),
        'amount': amount,
        'paymentMethod': _method,
        'genericCashAccountId': _accountId.isEmpty ? null : int.parse(_accountId),
        'paymentDate': _date,
        'notes': _notes.text.isEmpty ? null : _notes.text,
        'farmId': widget.company.farmId,
      });
      if (created != null && mounted) {
        trackerToast(
            context, _sup ? 'Supplier payment created as Draft. Approve to debit supplier + cash.' : '${_l.payment} created as Draft. Approve to update ledger + cash.');
        Navigator.pop(context, _accountId);
        return;
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not create payment', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Row(children: [
          const Icon(Icons.credit_card, size: 20, color: TColors.blue600),
          const SizedBox(width: 8),
          Expanded(child: Text(_sup ? 'New supplier payment' : 'New ${_l.payment.toLowerCase()}')),
        ]),
        content: SizedBox(
          width: 512,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                _sup
                    ? 'Creates a Draft payment. Approval debits the supplier ledger and decreases cash.'
                    : "Creates a Draft payment. Approval credits the ${_l.customer.toLowerCase()}'s ledger and adds cash.",
                style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection(_party, genericBandIndigo, [
              FilterLabel(
                '$_party *',
                AppSelect<String>(
                  value: _customerId.isEmpty ? null : _customerId,
                  hintText: 'Pick ${_party.toLowerCase()}...',
                  items: [
                    for (final c in widget.customers)
                      AppSelectItem(
                        value: tStr(c[_side.partyId]),
                        label: '${tStr(c[_side.partyName])}'
                            '${tNum(c['currentBalance']) > 0 ? ' – ${_sup ? 'owed' : 'owes'} ${fmtMoney(c['currentBalance'])}' : ''}',
                      ),
                  ],
                  onChanged: (v) => setState(() => _customerId = v ?? ''),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Payment details', genericBandBlue, [
              FilterLabel(
                'Date',
                AppDateField(value: businessDateAsDateTime(_date), onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d))),
              ),
              FilterLabel(
                'Amount *',
                AppInput(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                ),
              ),
              FilterLabel(
                'Method',
                AppSelect<String>(
                  value: _method,
                  items: [for (final m in genericPaymentMethods) AppSelectItem(value: m, label: m)],
                  onChanged: (v) => setState(() => _method = v ?? _method),
                ),
              ),
              FilterLabel(
                _sup ? 'Cash account (paid from)' : 'Cash account (receives)',
                AppSelect<String>(
                  value: _accountId.isEmpty ? '__none__' : _accountId,
                  items: [
                    const AppSelectItem(value: '__none__', label: '– none –'),
                    for (final a in widget.accounts.where((a) => a['isActive'] == true))
                      AppSelectItem(value: tStr(a['genericCashAccountId']), label: '${tStr(a['accountName'])} (${tStr(a['accountType'])})'),
                  ],
                  onChanged: (v) => setState(() => _accountId = v == null || v == '__none__' ? '' : v),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            formSection('Notes', genericBandSlate, [
              FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4, inputFormatters: [LengthLimitingTextInputFormatter(1000)])),
            ]),
          ]),
        ),
        actions: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(backgroundColor: TColors.red600, foregroundColor: Colors.white, side: BorderSide.none),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Create')),
        ],
      ),
    );
  }
}
