// Hotel → Setup → Finance → Customers and Suppliers, as
// `app/hotel-customers/page.tsx` and `app/hotel-suppliers/page.tsx`, with their
// statements (`[id]/ledger/page.tsx`). The two web pages are near-twins, so one
// screen serves both, told apart by [HotelPartyKind]:
// - the three summary cards, search, a card per row with the balance and its
//   status, and View statement / Edit / Delete;
// - the New / Edit dialog (customers: Basic Info, Address, Terms; suppliers: one
//   column), where the opening balance is offered only on a new record;
// - suppliers page their list ten at a time, as the web does.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/form_dialog.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/reports/report_format.dart' show fixed2;
import '../poultry/sales/balances_widgets.dart' show CompactPager, LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import 'hotel_kit.dart';

/// What differs between the Customers and the Suppliers page.
class HotelPartyKind {
  const HotelPartyKind._({
    required this.href,
    required this.title,
    required this.singular,
    required this.api,
    required this.idKey,
    required this.nameKey,
    required this.typeKey,
    required this.types,
    required this.summary,
    required this.searchHint,
    required this.balanceLabel,
    required this.ledgerIdKey,
    required this.ledgerColors,
  });

  final String href, title, singular, api, idKey, nameKey, typeKey, searchHint, balanceLabel, ledgerIdKey;
  final List<String> types;

  /// The three summary cards: (label, key, colour, suffix).
  final List<(String, String, Color, String)> summary;

  /// TYPE_COLORS on the statement.
  final Map<String, (Color, Color)> ledgerColors;

  bool get isCustomer => this == customers;

  static const customers = HotelPartyKind._(
    href: '/hotel-customers',
    title: 'Customers',
    singular: 'Customer',
    api: '/api/Hotel/customers',
    idKey: 'hotelCustomerId',
    nameKey: 'customerName',
    typeKey: 'customerType',
    types: ['Corporate', 'TravelAgent', 'Government', 'Individual', 'Other'],
    summary: [
      ('Total Customers', 'totalCustomers', TColors.slate900, ''),
      ('Customers Owing', 'customersOwing', TColors.amber600, ''),
      ('Total Balance Owed', 'totalBalance', TColors.red600, ''),
    ],
    searchHint: 'Search by name, phone, email...',
    balanceLabel: 'Balance',
    ledgerIdKey: 'hotelCustomerLedgerId',
    ledgerColors: {
      'OpeningBalance': (TColors.slate100, TColors.slate700),
      'InvoiceCredit': (TColors.blue100, Color(0xFF1D4ED8)),
      'PaymentDebit': (TColors.emerald100, TColors.emerald700),
      'AdjustmentCredit': (TColors.amber100, TColors.amber700),
      'AdjustmentDebit': (Color(0xFFF3E8FF), Color(0xFF7E22CE)),
    },
  );

  static const suppliers = HotelPartyKind._(
    href: '/hotel-suppliers',
    title: 'Suppliers',
    singular: 'Supplier',
    api: '/api/Hotel/suppliers',
    idKey: 'hotelSupplierId',
    nameKey: 'supplierName',
    typeKey: 'supplierType',
    types: ['ProductSupplier', 'ServiceProvider', 'Landlord', 'UtilityProvider', 'Contractor', 'Other'],
    summary: [
      ('Total Suppliers', 'totalSuppliers', TColors.slate900, ''),
      ('We Owe', 'suppliersOwed', TColors.amber600, ' suppliers'),
      ('Total Payable', 'totalBalance', TColors.red600, ''),
    ],
    searchHint: 'Search...',
    balanceLabel: 'We Owe',
    ledgerIdKey: 'hotelSupplierLedgerId',
    ledgerColors: {
      'OpeningBalance': (TColors.slate100, TColors.slate700),
      'ExpenseCredit': (TColors.blue100, Color(0xFF1D4ED8)),
      'PaymentDebit': (TColors.emerald100, TColors.emerald700),
      'AdjustmentCredit': (TColors.amber100, TColors.amber700),
      'AdjustmentDebit': (Color(0xFFF3E8FF), Color(0xFF7E22CE)),
    },
  );
}

/// The web's `toLocaleString` with two decimals.
String _fmt(Object? v) => fixed2(tNum(v));

class HotelPartiesScreen extends StatefulWidget {
  const HotelPartiesScreen({super.key, required this.session, required this.company, required this.kind});
  final Session session;
  final Company company;
  final HotelPartyKind kind;

  @override
  State<HotelPartiesScreen> createState() => _HotelPartiesScreenState();
}

class _HotelPartiesScreenState extends State<HotelPartiesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _summary;
  String _search = '';
  int _page = 1, _pageSize = 10;

  HotelPartyKind get _k => widget.kind;
  ApiClient get _api => widget.session.farmClient;
  Map<String, dynamic> get _q => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([_api.get(_k.api, query: _q), _api.get('${_k.api}/balance-summary', query: _q)]);
      _rows = hotelRows(r[0]);
      _summary = r[1] is Map ? Map<String, dynamic>.from(r[1] as Map) : null;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _rows;
    final s = _search.toLowerCase();
    return [
      for (final r in _rows)
        if (tStr(r[_k.nameKey]).toLowerCase().contains(s) ||
            tStr(r['phone']).toLowerCase().contains(s) ||
            // Customers also search email and type; suppliers only name and phone.
            (_k.isCustomer && (tStr(r['email']).toLowerCase().contains(s) || tStr(r[_k.typeKey]).toLowerCase().contains(s))))
          r,
    ];
  }

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PartyDialog(api: _api, farmId: widget.company.farmId, kind: _k, existing: existing),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final name = tStr(r[_k.nameKey]);
    final ok = await hotelConfirmDelete(
      context,
      title: 'Delete ${_k.singular}',
      message: _k.isCustomer ? 'Are you sure you want to delete "$name"? This action cannot be undone.' : 'Delete "$name"?',
      onConfirm: () => _api.delete('${_k.api}/${r[_k.idKey]}', query: _q),
    );
    if (!ok || !mounted) return;
    trackerToast(context, _k.isCustomer ? 'Customer deleted' : 'Deleted');
    _load();
  }

  void _statement(Map<String, dynamic> r) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => HotelPartyLedgerScreen(session: widget.session, company: widget.company, kind: _k, id: tIntOrNull(r[_k.idKey]) ?? 0),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: _k.href);
    final rows = _filtered;
    // Suppliers page ten at a time (usePagination); customers list them all.
    final pages = (rows.length / _pageSize).ceil().clamp(1, 1 << 30);
    final page = _page.clamp(1, pages);
    final shown = _k.isCustomer ? rows : rows.skip((page - 1) * _pageSize).take(_pageSize).toList();
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text(_k.title)),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _k.title,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900),
                        ),
                      ),
                      FilledButton.icon(
                        style: hotelPrimary,
                        onPressed: () => _openForm(),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text('New ${_k.singular}'),
                      ),
                    ],
                  ),
                  if (_summary != null) ...[
                    const SizedBox(height: 14),
                    for (final (label, key, color, suffix) in _k.summary) ...[
                      _summaryCard(
                        label,
                        key == 'totalBalance' ? _fmt(_summary![key]) : '${tIntOrNull(_summary![key]) ?? 0}$suffix',
                        color,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                  const SizedBox(height: 8),
                  AppSearchField(
                    hintText: _k.searchHint,
                    onChanged: (v) => setState(() {
                      _search = v;
                      _page = 1;
                    }),
                  ),
                  const SizedBox(height: 12),
                  if (rows.isEmpty) hotelEmpty('No ${_k.title.toLowerCase()} found'),
                  for (final r in shown) ...[_row(r), const SizedBox(height: 8)],
                  if (!_k.isCustomer && rows.isNotEmpty)
                    CompactPager(
                      total: rows.length,
                      page: page,
                      pageSize: _pageSize,
                      onPage: (p) => setState(() => _page = p),
                      onPageSize: (s) => setState(() {
                        _pageSize = s;
                        _page = 1;
                      }),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: TColors.slate200),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 13.5, color: TColors.slate500)),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    ),
  );

  Widget _row(Map<String, dynamic> r) {
    final balance = tNum(r['currentBalance']);
    final owed = balance > 0;
    final status = owed
        ? hotelBadge('Owed', TColors.amber100, TColors.amber700)
        : (!_k.isCustomer || r['isActive'] != false)
        ? hotelBadge('OK', TColors.emerald100, TColors.emerald700)
        : hotelBadge('Inactive', TColors.slate100, TColors.slate700);
    final contact = [
      tStr(r['phone']).isEmpty ? '—' : tStr(r['phone']),
      if (_k.isCustomer) tStr(r['email']).isEmpty ? '—' : tStr(r['email']),
    ].join(' · ');
    return HotelRowCard(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                tStr(r[_k.nameKey]),
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: TColors.slate900),
              ),
              hotelBadge(tStr(r[_k.typeKey]), Colors.white, TColors.slate600),
            ],
          ),
          const SizedBox(height: 3),
          Text(contact, style: const TextStyle(fontSize: 12.5, color: TColors.slate500)),
          const SizedBox(height: 5),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${_k.balanceLabel} ${_fmt(balance)}',
                style: TextStyle(
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: owed ? FontWeight.w700 : FontWeight.w500,
                  color: owed ? TColors.red600 : TColors.slate700,
                ),
              ),
              status,
            ],
          ),
        ],
      ),
      extra: [
        IconButton(
          tooltip: 'View statement',
          visualDensity: VisualDensity.compact,
          onPressed: () => _statement(r),
          icon: const Icon(Icons.visibility_outlined, size: 18),
        ),
        IconButton(
          tooltip: 'Edit',
          visualDensity: VisualDensity.compact,
          onPressed: () => _openForm(r),
          icon: const Icon(Icons.edit_outlined, size: 18),
        ),
      ],
      onDelete: () => _delete(r),
    );
  }
}

/// New / Edit Customer or Supplier. Pops true once saved.
class _PartyDialog extends StatefulWidget {
  const _PartyDialog({required this.api, required this.farmId, required this.kind, this.existing});
  final ApiClient api;
  final String farmId;
  final HotelPartyKind kind;
  final Map<String, dynamic>? existing;
  @override
  State<_PartyDialog> createState() => _PartyDialogState();
}

class _PartyDialogState extends State<_PartyDialog> {
  late final Map<String, dynamic> _e = widget.existing ?? const {};
  HotelPartyKind get _k => widget.kind;
  bool get _edit => widget.existing != null;

  late final _name = TextEditingController(text: tStr(_e[_k.nameKey]));
  late String _type = tStr(_e[_k.typeKey]).isEmpty ? _k.types.first : tStr(_e[_k.typeKey]);
  late final _phone = TextEditingController(text: tStr(_e['phone']));
  late final _email = TextEditingController(text: tStr(_e['email']));
  late final _address = TextEditingController(text: tStr(_e['address']));
  late final _city = TextEditingController(text: tStr(_e['city']));
  late final _location = TextEditingController(text: tStr(_e['location']));
  late final _terms = TextEditingController(text: '${tIntOrNull(_e['paymentTermDays']) ?? 0}');
  late final _limit = TextEditingController(text: _num(_e['creditLimit']));
  late final _opening = TextEditingController(text: _num(_e['openingBalance']));
  late final _notes = TextEditingController(text: tStr(_e['notes']));
  bool _saving = false;

  static String _num(Object? v) {
    final x = tNum(v);
    return x == x.roundToDouble() ? '${x.toInt()}' : '$x';
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Name required', error: true);
    setState(() => _saving = true);
    final body = <String, dynamic>{
      _k.nameKey: _name.text,
      _k.typeKey: _type,
      'phone': _phone.text,
      'email': _email.text,
      'address': _address.text,
      if (_k.isCustomer) 'city': _city.text else 'location': _location.text,
      'paymentTermDays': int.tryParse(_terms.text) ?? 0,
      if (_k.isCustomer) 'creditLimit': double.tryParse(_limit.text) ?? 0,
      'openingBalance': double.tryParse(_opening.text) ?? 0,
      'notes': _notes.text,
      'isActive': _e['isActive'] != false,
      'farmId': widget.farmId,
    };
    try {
      if (_edit) {
        await widget.api.put('${_k.api}/${_e[_k.idKey]}', body: body);
      } else {
        await widget.api.post(_k.api, body: body);
      }
      if (!mounted) return;
      trackerToast(context, '${_k.singular} ${_edit ? 'updated' : 'created'}');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Error', description: e.message, error: true);
    }
  }

  Widget _numField(String label, TextEditingController c, {bool decimal = false}) => FilterLabel(
    label,
    AppInput(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'^\d*\.?\d{0,2}' : r'^\d*'))],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final type = FilterLabel(
      _k.isCustomer ? 'Customer Type' : 'Type',
      AppSelect<String>(
        value: _type,
        items: [for (final t in _k.types) AppSelectItem(value: t, label: t)],
        onChanged: (v) => setState(() => _type = v ?? _type),
      ),
    );
    final phone = FilterLabel('Phone', AppInput(controller: _phone, keyboardType: TextInputType.phone));
    final email = FilterLabel('Email', AppInput(controller: _email, keyboardType: TextInputType.emailAddress));
    final terms = _numField('Payment Terms (Days)', _terms);
    final opening = _numField('Opening Balance', _opening, decimal: true);
    final notes = FilterLabel('Notes', AppTextarea(controller: _notes));
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: FormDialogTitle(
          icon: _edit ? Icons.edit_outlined : (_k.isCustomer ? Icons.person_add_alt : Icons.local_shipping_outlined),
          color: FormColor.purple,
          text: '${_edit ? 'Edit' : 'New'} ${_k.singular}',
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_k.isCustomer) ...[
                Text(
                  _edit ? 'Update customer details' : 'Add a new credit customer',
                  style: const TextStyle(fontSize: 13, color: TColors.slate500),
                ),
                const SizedBox(height: 12),
                TintedSection(
                  title: 'Basic Info',
                  color: FormColor.slate,
                  children: [
                    FilterLabel('Customer Name *', AppInput(controller: _name)),
                    type,
                    phone,
                    email,
                  ],
                ),
                const SizedBox(height: 12),
                TintedSection(
                  title: 'Address',
                  color: FormColor.slate,
                  children: [
                    FilterLabel('Address', AppInput(controller: _address)),
                    FilterLabel('City', AppInput(controller: _city)),
                  ],
                ),
                const SizedBox(height: 12),
                TintedSection(
                  title: 'Terms',
                  color: FormColor.slate,
                  children: [terms, _numField('Credit Limit', _limit, decimal: true), if (!_edit) opening],
                ),
                const SizedBox(height: 12),
                notes,
              ] else
                for (final (i, w) in [
                  FilterLabel('Supplier Name *', AppInput(controller: _name)),
                  type,
                  phone,
                  email,
                  FilterLabel('Location', AppInput(controller: _location)),
                  terms,
                  if (!_edit) opening,
                  notes,
                ].indexed) ...[if (i > 0) const SizedBox(height: 12), w],
            ],
          ),
        ),
        actions: [
          FormDialogFooter(
            onCancel: () => Navigator.pop(context),
            cancelDisabled: _saving,
            children: [
              FilledButton(
                style: hotelPrimary,
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_edit ? 'Update' : 'Create'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Name — Statement": the info cards and every ledger line, in the order the
/// API returns them.
class HotelPartyLedgerScreen extends StatefulWidget {
  const HotelPartyLedgerScreen({super.key, required this.session, required this.company, required this.kind, required this.id});
  final Session session;
  final Company company;
  final HotelPartyKind kind;
  final int id;

  @override
  State<HotelPartyLedgerScreen> createState() => _HotelPartyLedgerScreenState();
}

class _HotelPartyLedgerScreenState extends State<HotelPartyLedgerScreen> {
  bool _loading = true;
  Map<String, dynamic>? _party;
  List<Map<String, dynamic>> _ledger = [];

  HotelPartyKind get _k => widget.kind;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = widget.session.farmClient;
    final q = {'farmId': widget.company.farmId};
    try {
      final r = await Future.wait([api.get('${_k.api}/${widget.id}', query: q), api.get('${_k.api}/${widget.id}/ledger', query: q)]);
      _party = r[0] is Map && (r[0] as Map).isNotEmpty ? Map<String, dynamic>.from(r[0] as Map) : null;
      _ledger = hotelRows(r[1]);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _date(Object? v) {
    final d = DateTime.tryParse(tStr(v));
    return d == null ? '' : AppDateField.format(d.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final p = _party;
    return Scaffold(
      appBar: AppBar(title: Text(p == null ? 'Statement' : '${tStr(p[_k.nameKey])} — Statement')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : p == null
          ? Center(
              child: Text('${_k.singular} not found', style: const TextStyle(color: TColors.slate500)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              children: [
                Text(
                  '${tStr(p[_k.nameKey])} — Statement',
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: TColors.slate900),
                ),
                const SizedBox(height: 12),
                _infoGrid(p),
                const SizedBox(height: 14),
                if (_ledger.isEmpty) hotelEmpty('No transactions yet'),
                for (final e in _ledger) ...[_line(e), const SizedBox(height: 8)],
              ],
            ),
    );
  }

  Widget _info(String label, Widget value) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: TColors.slate200),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: TColors.slate500)),
        const SizedBox(height: 4),
        value,
      ],
    ),
  );

  Widget _infoGrid(Map<String, dynamic> p) {
    final balance = tNum(p['currentBalance']);
    Widget plain(String t) => Text(
      t,
      style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900),
    );
    final cells = [
      _info('Type', plain(tStr(p[_k.typeKey]))),
      if (_k.isCustomer) _info('Phone', plain(tStr(p['phone']).isEmpty ? '—' : tStr(p['phone']))),
      _info('Payment Terms', plain('${tIntOrNull(p['paymentTermDays']) ?? 0} days')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cells.length; i += 2) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cells[i]),
              const SizedBox(width: 8),
              Expanded(child: i + 1 < cells.length ? cells[i + 1] : const SizedBox.shrink()),
            ],
          ),
          const SizedBox(height: 8),
        ],
        _info(
          _k.isCustomer ? 'Balance Owed' : 'We Owe Them',
          Text(
            _fmt(balance),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: balance > 0 ? TColors.red600 : TColors.emerald600),
          ),
        ),
      ],
    );
  }

  Widget _line(Map<String, dynamic> e) {
    final type = tStr(e['transactionType']);
    final (bg, fg) = _k.ledgerColors[type] ?? (TColors.slate100, TColors.slate700);
    final debit = tNum(e['debitAmount']), credit = tNum(e['creditAmount']);
    // The customer statement's Ref column.
    final ref = !_k.isCustomer
        ? null
        : tIntOrNull(e['invoiceId']) != null
        ? 'Inv #${e['invoiceId']}'
        : tIntOrNull(e['paymentId']) != null
        ? 'Pay #${e['paymentId']}'
        : '—';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(_date(e['transactionDate']), style: const TextStyle(fontSize: 12.5, color: TColors.slate500)),
                    hotelBadge(type, bg, fg),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _fmt(e['balanceAfterTransaction']),
                style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.slate900),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tStr(e['description']).isEmpty ? '—' : tStr(e['description']),
            style: const TextStyle(fontSize: 13.5, color: TColors.slate800),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              if (ref != null) Text(ref, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              if (debit > 0) Text('Debit ${_fmt(debit)}', style: const TextStyle(fontSize: 12, color: TColors.slate700)),
              if (credit > 0) Text('Credit ${_fmt(credit)}', style: const TextStyle(fontSize: 12, color: TColors.slate700)),
            ],
          ),
        ],
      ),
    );
  }
}
