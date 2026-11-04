// Generic → Purchasing → Suppliers, as `app/generic-suppliers/page.tsx`, and a
// supplier's ledger (`app/generic-suppliers/[id]/ledger`). The Customers page's
// twin, from the other side: the balance is what we owe them.

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

const genericSupplierTypes = ['ProductSupplier', 'ServiceProvider', 'Landlord', 'UtilityProvider', 'Contractor', 'Other'];
const genericOrange = Color(0xFFEA580C); // orange-600
const _orange700 = Color(0xFFC2410C);

/// The status badge: Inactive, Owed (we owe them), or OK.
Widget genericSupplierBadge(Map s) {
  if (s['isActive'] != true) return const TBadge('Inactive', bg: TColors.slate100, fg: TColors.slate900);
  if (tNum(s['currentBalance']) > 0) return const TBadge('Owed', bg: TColors.amber100, fg: TColors.amber800);
  return const TBadge('OK', bg: TColors.emerald100, fg: TColors.emerald800);
}

/// The page's search: name, phone, email or location.
List<Map> filterGenericSuppliers(List<Map> rows, String search) {
  final q = search.trim().toLowerCase();
  if (q.isEmpty) return rows;
  return rows.where((s) => ['supplierName', 'phoneNumber', 'email', 'location'].any((k) => tStr(s[k]).toLowerCase().contains(q))).toList();
}

String _orDash(Object? v) => tStr(v).isEmpty ? '—' : tStr(v);
String _terms(Map s) => tNum(s['paymentTermsDays']) > 0 ? '${tStr(s['paymentTermsDays'])}d' : '—';

class GenericSuppliersScreen extends StatefulWidget {
  const GenericSuppliersScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<GenericSuppliersScreen> createState() => _GenericSuppliersScreenState();
}

class _GenericSuppliersScreenState extends State<GenericSuppliersScreen> {
  List<Map> _rows = [];
  bool _loading = true;
  final _search = TextEditingController();

  ApiClient get _api => widget.session.farmClient;
  String get _base => '${genericBase(widget.company)}/suppliers';

  @override
  void initState() {
    super.initState();
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
      if (mounted) trackerToast(context, 'Could not load suppliers', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openForm([Map? editing]) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => GenericSupplierFormDialog(session: widget.session, company: widget.company, editing: editing),
    );
    if (done == true) _load();
  }

  void _ledger(Map s) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => GenericSupplierLedgerScreen(session: widget.session, company: widget.company, supplierId: tIntOrNull(s['genericSupplierId']) ?? 0),
      ));

  Future<void> _delete(Map s) async {
    final name = tStr(s['supplierName']);
    final ok = await confirmDelete(
      context,
      title: 'Delete supplier?',
      description: tNum(s['currentBalance']) > 0
          ? 'Balance owed to "$name": ${fmtMoney(s['currentBalance'])}. Backend will refuse if purchases or open payments exist.'
          : 'Are you sure you want to delete "$name"? This action cannot be undone.',
    );
    if (!ok) return;
    try {
      await _api.delete('$_base/${tIntOrNull(s['genericSupplierId'])}');
      if (mounted) trackerToast(context, 'Supplier deleted');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-suppliers');
    final visible = filterGenericSuppliers(_rows, _search.text);
    Color? owed(Map s) => tNum(s['currentBalance']) > 0 ? TColors.rose700 : null;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Suppliers')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.local_shipping_outlined, size: 24, color: genericOrange),
              SizedBox(width: 8),
              Expanded(child: Text('Suppliers', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            Text('${_rows.length} supplier(s)', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: () => _openForm(), icon: const Icon(Icons.add, size: 18), label: const Text('New supplier')),
            const SizedBox(height: 14),
            if (_loading)
              const LoadingLine('Loading…')
            else if (_rows.isEmpty)
              genericEmptyCard('No suppliers yet.')
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
                keyOf: (s) => '${tIntOrNull(s['genericSupplierId'])}',
                primary: (s) => tStr(s['supplierName']),
                onPrimary: _ledger,
                secondaryBuilder: (s) => Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                  TBadge(tStr(s['supplierType']), bg: Colors.white, fg: TColors.slate700, border: TColors.slate200),
                  if (tStr(s['phoneNumber']).isNotEmpty) Text('· ${tStr(s['phoneNumber'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
                trailing: (s) => Padding(padding: const EdgeInsets.only(left: 6), child: genericSupplierBadge(s)),
                details: (s) => [
                  ('Phone', _orDash(s['phoneNumber'])),
                  ('Location', _orDash(s['location'])),
                  ('Terms', _terms(s)),
                  ('We owe them', fmtMoney(s['currentBalance'])),
                ],
                detailColor: (s, label) => label == 'We owe them' ? owed(s) : null,
                actions: (s) => [
                  OutlinedButton.icon(onPressed: () => _openForm(s), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
                  OutlinedButton.icon(
                    onPressed: () => _delete(s),
                    style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: TColors.red200)),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete'),
                  ),
                ],
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Name', width: 160), TCol('Type', width: 130), TCol('Phone', width: 120), TCol('Location', width: 120),
                    TCol('Terms', right: true, width: 80), TCol('We owe them', right: true, width: 120), TCol('Status', width: 100),
                    TCol('', right: true, width: 100),
                  ],
                  rows: [
                    for (final s in items)
                      [
                        InkWell(
                          onTap: () => _ledger(s),
                          child: Text(tStr(s['supplierName']), style: const TextStyle(fontWeight: FontWeight.w500, color: _orange700)),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TBadge(tStr(s['supplierType']), bg: Colors.white, fg: TColors.slate700, border: TColors.slate200),
                        ),
                        cellText(_orDash(s['phoneNumber'])),
                        cellText(_orDash(s['location'])),
                        Align(alignment: Alignment.centerRight, child: Text(_terms(s))),
                        Align(alignment: Alignment.centerRight, child: Text(fmtMoney(s['currentBalance']), style: TextStyle(color: owed(s)))),
                        Align(alignment: Alignment.centerLeft, child: genericSupplierBadge(s)),
                        Wrap(alignment: WrapAlignment.end, children: [
                          IconButton(tooltip: 'Edit', onPressed: () => _openForm(s), icon: const Icon(Icons.edit_outlined, size: 18)),
                          IconButton(tooltip: 'Delete', onPressed: () => _delete(s), icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600)),
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

/// New supplier / Edit supplier.
class GenericSupplierFormDialog extends StatefulWidget {
  const GenericSupplierFormDialog({super.key, required this.session, required this.company, this.editing});
  final Session session;
  final Company company;
  final Map? editing;

  @override
  State<GenericSupplierFormDialog> createState() => _GenericSupplierFormDialogState();
}

class _GenericSupplierFormDialogState extends State<GenericSupplierFormDialog> {
  late final Map? _e = widget.editing;
  late final _name = TextEditingController(text: tStr(_e?['supplierName']));
  late String _type = _e == null || tStr(_e['supplierType']).isEmpty ? 'ProductSupplier' : tStr(_e['supplierType']);
  late final _phone = TextEditingController(text: tStr(_e?['phoneNumber']));
  late final _email = TextEditingController(text: tStr(_e?['email']));
  late final _location = TextEditingController(text: tStr(_e?['location']));
  late final _address = TextEditingController(text: tStr(_e?['address']));
  late final _terms = TextEditingController(text: _e == null ? '0' : tStr(_e['paymentTermsDays']));
  late final _opening = TextEditingController(text: _e == null ? '0' : tStr(_e['openingBalance']));
  late final _notes = TextEditingController(text: tStr(_e?['notes']));
  late final bool _active = _e == null ? true : _e['isActive'] == true;
  bool _saving = false;

  int? get _editId => tIntOrNull(_e?['genericSupplierId']);

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _location, _address, _terms, _opening, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Name is required', error: true);
    String? opt(TextEditingController c) => c.text.isEmpty ? null : c.text;
    final payload = {
      'supplierName': _name.text.trim(),
      'supplierType': _type,
      'phoneNumber': opt(_phone),
      'email': opt(_email),
      'location': opt(_location),
      'address': opt(_address),
      'paymentTermsDays': num.tryParse(_terms.text) ?? 0,
      'openingBalance': num.tryParse(_opening.text) ?? 0,
      'isActive': _active,
      'notes': opt(_notes),
      'farmId': widget.company.farmId,
    };
    setState(() => _saving = true);
    final api = widget.session.farmClient;
    final base = '${genericBase(widget.company)}/suppliers';
    try {
      if (_editId != null) {
        await api.put('$base/$_editId', body: payload);
        if (mounted) trackerToast(context, 'Supplier updated.');
      } else {
        final created = await api.post(base, body: payload);
        if (mounted && created is Map) trackerToast(context, 'Supplier "${tStr(created['supplierName'])}" created.');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, _editId != null ? 'Could not save changes' : 'Could not create supplier', description: e.message, error: true);
    }
  }

  Widget _text(String label, TextEditingController c, int max, {TextInputType? type}) =>
      FilterLabel(label, AppInput(controller: c, keyboardType: type, inputFormatters: [LengthLimitingTextInputFormatter(max)]));

  @override
  Widget build(BuildContext context) {
    final editing = _editId != null;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Row(children: [
          Icon(editing ? Icons.edit_outlined : Icons.local_shipping_outlined, size: 20, color: TColors.blue600),
          const SizedBox(width: 8),
          Expanded(child: Text(editing ? 'Edit supplier' : 'New supplier')),
        ]),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Pre-existing balance is the amount you already owe them.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            formSection('Personal information', genericBandIndigo, [
              _text('Supplier name *', _name, 200),
              FilterLabel(
                'Type',
                AppSelect<String>(
                  value: _type,
                  items: [for (final t in {...genericSupplierTypes, _type}) AppSelectItem(value: t, label: t)],
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
            formSection('Payment terms', genericBandAmber, [
              FilterLabel(
                'Payment terms (days)',
                AppInput(controller: _terms, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
              ),
              FilterLabel(
                'Opening balance (you owe)',
                AppInput(
                  controller: _opening,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,2}'))],
                ),
              ),
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

/// TYPE_COLORS of the supplier ledger: (background, text).
(Color, Color) genericSupplierLedgerTone(Object? type) => switch (tStr(type)) {
      'OpeningBalance' => (TColors.slate100, TColors.slate800),
      'PurchaseCredit' => (TColors.rose100, TColors.rose800),
      'ExpenseCredit' => (TColors.amber100, TColors.amber800),
      'PaymentDebit' => (TColors.emerald100, TColors.emerald800),
      'AdjustmentDebit' => (TColors.sky100, TColors.sky800),
      'AdjustmentCredit' => (TColors.amber100, TColors.amber800),
      _ => (TColors.slate100, TColors.slate800),
    };

/// The Ref column: "Pur #3", "Exp #8", "Pay #4" or "—".
String genericSupplierLedgerRef(Map e) => e['purchaseId'] != null
    ? 'Pur #${tStr(e['purchaseId'])}'
    : e['expenseId'] != null
        ? 'Exp #${tStr(e['expenseId'])}'
        : e['paymentId'] != null
            ? 'Pay #${tStr(e['paymentId'])}'
            : '—';

class GenericSupplierLedgerScreen extends StatefulWidget {
  const GenericSupplierLedgerScreen({super.key, required this.session, required this.company, required this.supplierId});
  final Session session;
  final Company company;
  final int supplierId;

  @override
  State<GenericSupplierLedgerScreen> createState() => _GenericSupplierLedgerScreenState();
}

class _GenericSupplierLedgerScreenState extends State<GenericSupplierLedgerScreen> {
  Map? _supplier;
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
    final base = '${genericBase(widget.company)}/suppliers/${widget.supplierId}';
    try {
      final r = await Future.wait([
        // getSupplier: a missing supplier is null ("Supplier not found").
        api.get(base).then<Object?>((v) => v, onError: (Object e) => e is ApiException && e.statusCode == 404 ? null : throw e),
        api.get('$base/ledger'),
      ]);
      if (mounted) {
        setState(() {
          _supplier = r[0] is Map ? r[0] as Map : null;
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
    final s = _supplier;
    return Scaffold(
      appBar: AppBar(title: Text(s == null ? 'Ledger' : tStr(s['supplierName']))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(foregroundColor: TColors.slate500, padding: EdgeInsets.zero),
              icon: const Icon(Icons.arrow_back, size: 14),
              label: const Text('Back to suppliers', style: TextStyle(fontSize: 13)),
            ),
          ),
          if (_loading)
            const LoadingLine('Loading…')
          else if (s == null)
            genericEmptyCard('Supplier not found.')
          else ...[
            Row(children: [
              const Icon(Icons.menu_book_outlined, size: 24, color: genericOrange),
              const SizedBox(width: 8),
              Expanded(child: Text(tStr(s['supplierName']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            Text(
              '${tStr(s['supplierType'])} · ${tStr(s['phoneNumber']).isEmpty ? 'no phone' : tStr(s['phoneNumber'])} · '
              '${tStr(s['location']).isEmpty ? 'no location' : tStr(s['location'])}',
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('WE OWE THEM', style: TextStyle(fontSize: 11, color: TColors.slate500)),
                Text(fmtMoney(s['currentBalance']),
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w600, color: tNum(s['currentBalance']) > 0 ? TColors.rose700 : TColors.emerald700)),
                Text('Terms: ${tNum(s['paymentTermsDays']) > 0 ? '${tStr(s['paymentTermsDays'])} days' : '—'}',
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
    final (bg, fg) = genericSupplierLedgerTone(e['transactionType']);
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
          Expanded(child: Text(genericSupplierLedgerRef(e), style: const TextStyle(fontSize: 12, color: TColors.slate500))),
          if (tNum(e['debitAmount']) > 0) Text('Debit ${fmtMoney(e['debitAmount'])}', style: const TextStyle(fontSize: 12)),
          if (tNum(e['creditAmount']) > 0) Text('Credit ${fmtMoney(e['creditAmount'])}', style: const TextStyle(fontSize: 12)),
        ]),
      ]),
    );
  }
}
