// Generic → Sales → Customers, as `app/generic-customers/page.tsx`, and a
// customer's ledger (`app/generic-customers/[id]/ledger`). The words follow
// the business template: a gym has Members, a school Students.

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
import 'generic_products_screen.dart' show genericBandAmber, genericBandIndigo, genericBandSlate, genericEmptyCard;
import 'reports/generic_report_kit.dart' show fmtMoney;

const genericCustomerTypes = ['Individual', 'Business', 'Walk-in', 'Retail Customer', 'Wholesale Customer', 'Other'];

/// The status badge: Inactive, Over limit, Owes, or OK.
Widget genericCustomerBadge(Map c) {
  final bal = tNum(c['currentBalance']), limit = tNum(c['creditLimit']);
  if (c['isActive'] != true) return const TBadge('Inactive', bg: TColors.slate100, fg: TColors.slate900);
  if (limit > 0 && bal > limit) return const TBadge('Over limit', bg: TColors.rose100, fg: TColors.rose800);
  if (bal > 0) return const TBadge('Owes', bg: TColors.amber100, fg: TColors.amber800);
  return const TBadge('OK', bg: TColors.emerald100, fg: TColors.emerald800);
}

/// The page's search: name, phone, email or location.
List<Map> filterGenericCustomers(List<Map> rows, String search) {
  final q = search.trim().toLowerCase();
  if (q.isEmpty) return rows;
  return rows.where((c) => ['customerName', 'phoneNumber', 'email', 'location'].any((k) => tStr(c[k]).toLowerCase().contains(q))).toList();
}

String _orDash(Object? v) => tStr(v).isEmpty ? '—' : tStr(v);

class GenericCustomersScreen extends StatefulWidget {
  const GenericCustomersScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericCustomersScreen> createState() => _GenericCustomersScreenState();
}

class _GenericCustomersScreenState extends State<GenericCustomersScreen> {
  List<Map> _rows = [];
  bool _loading = true;
  final _search = TextEditingController();
  GenericLabels _l = genericLabels(null);

  ApiClient get _api => widget.session.farmClient;
  String get _base => '${genericBase(widget.company)}/customers';

  @override
  void initState() {
    super.initState();
    loadGenericModules(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _l = m.labels);
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
      final r = rowsOf(await _api.get(_base));
      if (mounted) setState(() => _rows = r);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load ${_l.customerPlural.toLowerCase()}', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openForm([Map? editing]) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => GenericCustomerFormDialog(session: widget.session, company: widget.company, labels: _l, editing: editing),
    );
    if (done == true) _load();
  }

  void _ledger(Map c) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => GenericCustomerLedgerScreen(session: widget.session, company: widget.company, customerId: tIntOrNull(c['genericCustomerId']) ?? 0),
      ));

  Future<void> _delete(Map c) async {
    final name = tStr(c['customerName']);
    final ok = await confirmDelete(
      context,
      title: 'Delete ${_l.customer.toLowerCase()}?',
      description: tNum(c['currentBalance']) > 0
          ? '"$name" owes ${fmtMoney(c['currentBalance'])}. Deleting may fail if there\'s an outstanding balance or sale history — backend will refuse if so.'
          : 'Are you sure you want to delete "$name"? This action cannot be undone.',
    );
    if (!ok) return;
    try {
      await _api.delete('$_base/${tIntOrNull(c['genericCustomerId'])}');
      if (mounted) trackerToast(context, '${_l.customer} deleted');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-customers');
    final visible = filterGenericCustomers(_rows, _search.text);
    Color? owes(Map c) => tNum(c['currentBalance']) > 0 ? TColors.rose700 : null;
    String limit(Map c) => tNum(c['creditLimit']) > 0 ? fmtMoney(c['creditLimit']) : '—';
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(_l.customerPlural)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(children: [
              const Icon(Icons.people_outline, size: 24, color: genericEmerald),
              const SizedBox(width: 8),
              Expanded(child: Text(_l.customerPlural, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            Text('${_rows.length} ${_rows.length == 1 ? _l.customer.toLowerCase() : _l.customerPlural.toLowerCase()}',
                style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: () => _openForm(), icon: const Icon(Icons.add, size: 18), label: Text('New ${_l.customer.toLowerCase()}')),
            const SizedBox(height: 14),
            if (_loading)
              const LoadingLine('Loading…')
            else if (_rows.isEmpty)
              genericEmptyCard('No ${_l.customerPlural.toLowerCase()} yet. Create your first one.')
            else ...[
              ListFiltersCard(
                search: _search,
                searchPlaceholder: 'Search name, phone, email or location',
                searchOnly: true,
                onSearch: () => setState(() {}),
                from: '',
                to: '',
                onDates: (_, _) {},
                onClear: () => setState(_search.clear),
              ),
              const SizedBox(height: 14),
              MobileCardList<Map>(
                items: visible,
                keyOf: (c) => '${tIntOrNull(c['genericCustomerId'])}',
                primary: (c) => tStr(c['customerName']),
                onPrimary: _ledger,
                secondaryBuilder: (c) => Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                  TBadge(tStr(c['customerType']), bg: Colors.white, fg: TColors.slate700, border: TColors.slate200),
                  if (tStr(c['phoneNumber']).isNotEmpty) Text('· ${tStr(c['phoneNumber'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
                trailing: (c) => Padding(padding: const EdgeInsets.only(left: 6), child: genericCustomerBadge(c)),
                details: (c) => [
                  ('Phone', _orDash(c['phoneNumber'])),
                  ('Location', _orDash(c['location'])),
                  ('Credit limit', limit(c)),
                  ('Owes us', fmtMoney(c['currentBalance'])),
                ],
                detailColor: (c, label) => label == 'Owes us' ? owes(c) : null,
                actions: (c) => [
                  OutlinedButton.icon(onPressed: () => _openForm(c), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
                  OutlinedButton.icon(
                    onPressed: () => _delete(c),
                    style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: TColors.red200)),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete'),
                  ),
                ],
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Name', width: 160), TCol('Type', width: 120), TCol('Phone', width: 120), TCol('Location', width: 120),
                    TCol('Credit limit', right: true, width: 110), TCol('Owes us', right: true, width: 110), TCol('Status', width: 100),
                    TCol('', right: true, width: 100),
                  ],
                  rows: [
                    for (final c in items)
                      [
                        InkWell(
                          onTap: () => _ledger(c),
                          child: Text(tStr(c['customerName']), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.emerald700)),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TBadge(tStr(c['customerType']), bg: Colors.white, fg: TColors.slate700, border: TColors.slate200),
                        ),
                        cellText(_orDash(c['phoneNumber'])),
                        cellText(_orDash(c['location'])),
                        Align(alignment: Alignment.centerRight, child: Text(limit(c))),
                        Align(alignment: Alignment.centerRight, child: Text(fmtMoney(c['currentBalance']), style: TextStyle(color: owes(c)))),
                        Align(alignment: Alignment.centerLeft, child: genericCustomerBadge(c)),
                        Wrap(alignment: WrapAlignment.end, children: [
                          IconButton(tooltip: 'Edit', onPressed: () => _openForm(c), icon: const Icon(Icons.edit_outlined, size: 18)),
                          IconButton(tooltip: 'Delete', onPressed: () => _delete(c), icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600)),
                        ]),
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

/// New customer / Edit customer (in the template's word).
class GenericCustomerFormDialog extends StatefulWidget {
  const GenericCustomerFormDialog({super.key, required this.session, required this.company, required this.labels, this.editing});
  final Session session;
  final Company company;
  final GenericLabels labels;
  final Map? editing;

  @override
  State<GenericCustomerFormDialog> createState() => _GenericCustomerFormDialogState();
}

class _GenericCustomerFormDialogState extends State<GenericCustomerFormDialog> {
  late final Map? _e = widget.editing;
  late final _name = TextEditingController(text: tStr(_e?['customerName']));
  late String _type = _e == null || tStr(_e['customerType']).isEmpty ? 'Individual' : tStr(_e['customerType']);
  late final _phone = TextEditingController(text: tStr(_e?['phoneNumber']));
  late final _email = TextEditingController(text: tStr(_e?['email']));
  late final _location = TextEditingController(text: tStr(_e?['location']));
  late final _address = TextEditingController(text: tStr(_e?['address']));
  late final _limit = TextEditingController(text: _e == null ? '0' : tStr(_e['creditLimit']));
  late final _terms = TextEditingController(text: _e == null ? '0' : tStr(_e['paymentTermsDays']));
  late final _opening = TextEditingController(text: _e == null ? '0' : tStr(_e['openingBalance']));
  late final _notes = TextEditingController(text: tStr(_e?['notes']));
  late final bool _active = _e == null ? true : _e['isActive'] == true;
  bool _saving = false;

  int? get _editId => tIntOrNull(_e?['genericCustomerId']);
  GenericLabels get _l => widget.labels;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _location, _address, _limit, _terms, _opening, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Name is required', error: true);
    String? opt(TextEditingController c) => c.text.isEmpty ? null : c.text;
    final payload = {
      'customerName': _name.text.trim(),
      'customerType': _type,
      'phoneNumber': opt(_phone),
      'email': opt(_email),
      'location': opt(_location),
      'address': opt(_address),
      'creditLimit': num.tryParse(_limit.text) ?? 0,
      'paymentTermsDays': num.tryParse(_terms.text) ?? 0,
      'openingBalance': num.tryParse(_opening.text) ?? 0,
      'isActive': _active,
      'notes': opt(_notes),
      'farmId': widget.company.farmId,
    };
    setState(() => _saving = true);
    final api = widget.session.farmClient;
    final base = '${genericBase(widget.company)}/customers';
    try {
      if (_editId != null) {
        await api.put('$base/$_editId', body: payload);
        if (mounted) trackerToast(context, '${_l.customer} updated.');
      } else {
        final created = await api.post(base, body: payload);
        if (mounted && created is Map) trackerToast(context, 'Customer "${tStr(created['customerName'])}" created.');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, _editId != null ? 'Could not save changes' : 'Could not create ${_l.customer.toLowerCase()}',
          description: e.message, error: true);
    }
  }

  Widget _text(String label, TextEditingController c, int max, {TextInputType? type}) =>
      FilterLabel(label, AppInput(controller: c, keyboardType: type, inputFormatters: [LengthLimitingTextInputFormatter(max)]));

  Widget _num(String label, TextEditingController c, {bool decimal = true, bool signed = false}) => FilterLabel(
        label,
        AppInput(
          controller: c,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal, signed: signed),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'^-?\d*\.?\d{0,2}' : r'^\d*'))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final editing = _editId != null;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Row(children: [
          Icon(editing ? Icons.edit_outlined : Icons.people_outline, size: 20, color: TColors.blue600),
          const SizedBox(width: 8),
          Expanded(child: Text('${editing ? 'Edit' : 'New'} ${_l.customer.toLowerCase()}')),
        ]),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Capture basic contact info, credit limit and any opening balance they already owe you.',
                style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection('Personal information', genericBandIndigo, [
              _text('${_l.customer} name *', _name, 200),
              FilterLabel(
                'Type',
                AppSelect<String>(
                  value: _type,
                  items: [
                    for (final t in {...genericCustomerTypes, _type}) AppSelectItem(value: t, label: t),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
              ),
              _text('Phone', _phone, 50, type: TextInputType.phone),
              _text('Email', _email, 150, type: TextInputType.emailAddress),
            ]),
            const SizedBox(height: 12),
            formSection('Address', const Color(0xFF16A34A), [
              _text('Location', _location, 255),
              _text('Address', _address, 500),
            ]),
            const SizedBox(height: 12),
            formSection('Credit & balance', genericBandAmber, [
              _num('Credit limit', _limit, signed: true),
              _num('Payment terms (days)', _terms, decimal: false),
              _num('Opening balance owed', _opening, signed: true),
            ]),
            const SizedBox(height: 12),
            formSection('Notes', genericBandSlate, [
              FilterLabel('Notes', AppInput(controller: _notes, minLines: 2, maxLines: 4)),
            ]),
          ]),
        ),
        actions: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(backgroundColor: TColors.red600, foregroundColor: Colors.white, side: BorderSide.none),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : (editing ? 'Save changes' : 'Create'))),
        ],
      ),
    );
  }
}

/// TYPE_COLORS of the ledger page: (background, text).
(Color, Color) genericLedgerTone(Object? type) => switch (tStr(type)) {
      'OpeningBalance' => (TColors.slate100, TColors.slate800),
      'SaleDebit' => (TColors.rose100, TColors.rose800),
      'PaymentCredit' => (TColors.emerald100, TColors.emerald800),
      'RefundDebit' || 'AdjustmentDebit' => (TColors.amber100, TColors.amber800),
      'AdjustmentCredit' => (TColors.sky100, TColors.sky800),
      'BadDebtWriteOff' => (TColors.slate200, TColors.slate700),
      _ => (TColors.slate100, TColors.slate800),
    };

/// The Ref column: "Sale #12", "Pay #4" or "—".
String genericLedgerRef(Map e) => e['saleId'] != null
    ? 'Sale #${tStr(e['saleId'])}'
    : e['paymentId'] != null
        ? 'Pay #${tStr(e['paymentId'])}'
        : '—';

class GenericCustomerLedgerScreen extends StatefulWidget {
  const GenericCustomerLedgerScreen({super.key, required this.session, required this.company, required this.customerId});
  final Session session;
  final Company company;
  final int customerId;

  @override
  State<GenericCustomerLedgerScreen> createState() => _GenericCustomerLedgerScreenState();
}

class _GenericCustomerLedgerScreenState extends State<GenericCustomerLedgerScreen> {
  Map? _customer;
  List<Map> _entries = [];
  bool _loading = true;
  Duration _offset = DateTime.now().timeZoneOffset;

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<void> _load() async {
    final api = widget.session.farmClient;
    final base = '${genericBase(widget.company)}/customers/${widget.customerId}';
    try {
      final r = await Future.wait([
        // getCustomer: a missing customer is null ("Customer not found").
        api.get(base).then<Object?>((v) => v, onError: (Object e) => e is ApiException && e.statusCode == 404 ? null : throw e),
        api.get('$base/ledger'),
      ]);
      if (mounted) {
        setState(() {
          _customer = r[0] is Map ? r[0] as Map : null;
          _entries = rowsOf(r[1]);
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load ledger', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = _customer;
    return Scaffold(
      appBar: AppBar(title: Text(c == null ? 'Ledger' : tStr(c['customerName']))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(foregroundColor: TColors.slate500, padding: EdgeInsets.zero),
              icon: const Icon(Icons.arrow_back, size: 14),
              label: const Text('Back to customers', style: TextStyle(fontSize: 13)),
            ),
          ),
          if (_loading)
            const LoadingLine('Loading…')
          else if (c == null)
            genericEmptyCard('Customer not found.')
          else ...[
            Row(children: [
              const Icon(Icons.menu_book_outlined, size: 24, color: genericEmerald),
              const SizedBox(width: 8),
              Expanded(child: Text(tStr(c['customerName']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            Text(
              '${tStr(c['customerType'])} · ${tStr(c['phoneNumber']).isEmpty ? 'no phone' : tStr(c['phoneNumber'])} · '
              '${tStr(c['location']).isEmpty ? 'no location' : tStr(c['location'])}',
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('CURRENT BALANCE', style: TextStyle(fontSize: 11, color: TColors.slate500)),
                Text(fmtMoney(c['currentBalance']),
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w600, color: tNum(c['currentBalance']) > 0 ? TColors.rose700 : TColors.emerald700)),
                Text('Credit limit: ${tNum(c['creditLimit']) > 0 ? fmtMoney(c['creditLimit']) : '—'}',
                    style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColors.slate900)),
                const SizedBox(height: 8),
                if (_entries.isEmpty)
                  const Text('No transactions yet.', style: TextStyle(fontSize: 14, color: TColors.slate500))
                else
                  for (final e in _entries) _entry(e),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _entry(Map e) {
    final (bg, fg) = genericLedgerTone(e['transactionType']);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate100))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              TBadge(tStr(e['transactionType']), bg: bg, fg: fg),
              Text(fmtDateTime(e['transactionDate'], e, _offset), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(fmtMoney(e['balanceAfterTransaction']), style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        Text(_orDash(e['description']), maxLines: 2, overflow: TextOverflow.ellipsis),
        Row(children: [
          Expanded(child: Text(genericLedgerRef(e), style: const TextStyle(fontSize: 12, color: TColors.slate500))),
          if (tNum(e['debitAmount']) > 0) Text('Debit ${fmtMoney(e['debitAmount'])}', style: const TextStyle(fontSize: 12)),
          if (tNum(e['creditAmount']) > 0) Text('Credit ${fmtMoney(e['creditAmount'])}', style: const TextStyle(fontSize: 12)),
        ]),
      ]),
    );
  }
}
