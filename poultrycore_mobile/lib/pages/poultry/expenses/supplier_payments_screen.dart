import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../money/money_widgets.dart';
import '../reports/report_export.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart';
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../trackers/tracker_widgets.dart';

/// Poultry → Expenses → Supplier Payments, as `app/supplier-payments/page.tsx`
/// → `components/balances/payments-ledger-page.tsx`: every payment made to a
/// supplier, what it paid, and its reversal.

const supplierSourceFilters = ['SupplierBalances', 'PurchaseEntry', 'ExpenseEntry', 'SupplierPaymentsPage'];
const _sourceLabels = {
  'SupplierBalances': 'Supplier Balances',
  'PurchaseEntry': 'Purchase entry',
  'ExpenseEntry': 'Expense entry',
  'SupplierPaymentsPage': 'Supplier Payments',
};
String supplierSourceLabel(Object? t) => tStr(t).trim().isEmpty ? '—' : _sourceLabels[tStr(t).trim()] ?? tStr(t).trim();

const _payableLabels = {
  'RawMaterialPurchase': 'Purchase',
  'FlockBatch': 'Flock batch',
  'Expense': 'Expense',
  'Purchase': 'Purchase',
  'AssetCost': 'Capital investment',
};
String payableTypeLabel(Object? t) => tStr(t).trim().isEmpty ? '—' : _payableLabels[tStr(t).trim()] ?? tStr(t).trim();

/// documentHref for an allocation (app/supplier-payments/page.tsx).
String supplierDocumentHref(Map a) => switch (tStr(a['documentType'])) {
      'FlockBatch' => '/flock-batch/${tStr(a['documentId'])}',
      'Expense' => '/expenses?expenseId=${tStr(a['documentId'])}',
      _ => '/poultry-raw-materials?tab=purchases&purchaseId=${tStr(a['documentId'])}',
    };

class SupplierPaymentFilters {
  String search = '', supplier = 'all', method = 'all', account = 'all', source = 'all', status = 'all';
  String appliedTo = 'all', payableType = 'all', min = '', max = '';
}

/// The page's filters over the loaded rows; [allocations] feed the payable
/// type and the search (references and labels of what each payment paid).
List<Map> filterSupplierPayments(List<Map> rows, SupplierPaymentFilters f, Map<String, List<Map>> allocations) {
  final q = f.search.trim().toLowerCase();
  final min = f.min.trim().isEmpty ? null : num.tryParse(f.min);
  final max = f.max.trim().isEmpty ? null : num.tryParse(f.max);
  return rows.where((r) {
    final id = tStr(r['paymentId']);
    final count = tIntOrNull(r['allocationCount']) ?? 0;
    if (f.supplier != 'all' && tStr(r['partyId']) != f.supplier) return false;
    if (f.method != 'all' && tStr(r['paymentMethod']) != f.method) return false;
    if (f.account != 'all' && tStr(r['cashAccountId']) != f.account) return false;
    if (f.source != 'all' && tStr(r['sourceType']) != f.source) return false;
    if (f.status != 'all' && tStr(r['status']) != f.status) return false;
    if (f.appliedTo == 'single' && count != 1) return false;
    if (f.appliedTo == 'multiple' && count <= 1) return false;
    if (min != null && tNum(r['totalAmount']) < min) return false;
    if (max != null && tNum(r['totalAmount']) > max) return false;
    if (f.payableType != 'all') {
      final a = allocations[id];
      if (a != null && !a.any((x) => tStr(x['documentType']) == f.payableType)) return false;
    }
    if (q.isNotEmpty) {
      final a = allocations[id] ?? const [];
      final hay = [
        r['partyName'], r['reference'], r['notes'], r['sourceType'], r['paymentId'],
        for (final x in a) x['reference'],
        for (final x in a) x['label'],
      ].where((v) => v != null && '$v'.isNotEmpty).join(' ').toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }).toList();
}

const supplierExportHeaders = [
  'Date', 'Payment #', 'Supplier', 'Payable #', 'Payable type', 'Payable total', 'Payment amount', 'Balance before', 'Applied',
  'Balance after', 'Applied to', 'Method', 'Cash account', 'Reference', 'Source', 'Paid by', 'Status',
];

class SupplierPaymentsScreen extends StatefulWidget {
  const SupplierPaymentsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<SupplierPaymentsScreen> createState() => _SupplierPaymentsScreenState();
}

class _SupplierPaymentsScreenState extends State<SupplierPaymentsScreen> {
  List<Map> _rows = [], _accounts = [];
  bool _loading = true;
  final Map<String, List<Map>> _allocations = {};
  final Set<String> _inflight = {};
  String? _expanded, _reversing;
  final _reason = TextEditingController();
  final _search = TextEditingController(), _min = TextEditingController(), _max = TextEditingController();
  final _f = SupplierPaymentFilters();
  String _period = 'all', _from = '', _to = '';
  bool _showMore = false;
  int _page = 1, _pageSize = 10, _lastTotal = -1;
  FarmMoney _fmt = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  /// The web gates reversal on poultry.supplier-payments.reverse; the app has
  /// no permission flags, so the Staff role is the one left out.
  bool get _canReverse => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _loadAccounts();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_reason, _search, _min, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/api/Poultry/supplier-payments', query: {
        'farmId': _farmId,
        if (_from.isNotEmpty) 'from': _from,
        if (_to.isNotEmpty) 'to': _to,
      });
      if (!mounted) return;
      setState(() {
        _rows = rowsOf(res);
        _allocations.clear();
        _inflight.clear();
        _expanded = null;
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load payments', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadAccounts() async {
    try {
      final res = await _api.get('/api/Poultry/cash-accounts', query: {'farmId': _farmId});
      if (mounted) {
        setState(() => _accounts = [
              for (final a in rowsOf(res)) {'id': tIntOrNull(a['poultryCashAccountId']), 'name': tStr(a['accountName'])},
            ]);
      }
    } on ApiException {
      if (mounted) setState(() => _accounts = []);
    }
  }

  String _accountName(Object? id) {
    final i = tIntOrNull(id);
    if (i == null || i == 0) return '—';
    return tStr(_accounts.where((a) => a['id'] == i).firstOrNull?['name']).isNotEmpty
        ? tStr(_accounts.where((a) => a['id'] == i).first['name'])
        : 'Account #$i';
  }

  /// Fetch one payment's allocation; [silent] for the one-item rows the page
  /// fetches by itself (the web swallows those failures).
  Future<void> _fetch(String id, {bool silent = false}) async {
    if (_allocations.containsKey(id) || !_inflight.add(id)) return;
    try {
      final res = await _api.get('/api/Poultry/supplier-payments/${Uri.encodeComponent(id)}', query: {'farmId': _farmId});
      if (mounted) setState(() => _allocations[id] = res is Map ? rowsOf(res['allocations']) : []);
    } on ApiException catch (e) {
      if (silent) {
        if (mounted) setState(() => _allocations[id] = []);
      } else {
        _inflight.remove(id);
        if (mounted) trackerToast(context, 'Could not load allocation', description: e.message, error: true);
      }
    }
  }

  void _toggle(Map r) {
    final id = tStr(r['paymentId']);
    if (_expanded == id) return setState(() => _expanded = null);
    setState(() => _expanded = id);
    _fetch(id);
  }

  Map? _sole(Map r) {
    if (tIntOrNull(r['allocationCount']) != 1) return null;
    final a = _allocations[tStr(r['paymentId'])];
    return a != null && a.length == 1 ? a.first : null;
  }

  Future<void> _doReverse(Map r) async {
    if (_reason.text.trim().isEmpty) {
      return trackerToast(context, 'A reason is required',
          description: 'Say why this payment is being reversed — it is written to the audit trail.', error: true);
    }
    try {
      await _api.post('/api/Poultry/supplier-payments/${Uri.encodeComponent(tStr(r['paymentId']))}/reverse',
          body: {'farmId': _farmId, 'reason': _reason.text.trim(), 'reversedBy': widget.session.tokens.userId});
      if (!mounted) return;
      trackerToast(context, 'Payment reversed', description: '${_fmt(tNum(r['totalAmount']))} put back on the balance.');
      setState(() {
        _reversing = null;
        _reason.clear();
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not reverse payment', description: e.message, error: true);
    }
  }

  void _reset() {
    setState(() {
      _search.clear();
      _min.clear();
      _max.clear();
      _period = 'all';
      _from = '';
      _to = '';
      _f
        ..search = ''
        ..supplier = 'all'
        ..method = 'all'
        ..account = 'all'
        ..source = 'all'
        ..status = 'all'
        ..appliedTo = 'all'
        ..payableType = 'all'
        ..min = ''
        ..max = '';
    });
    _load();
  }

  List<List<String>> _exportRows(List<Map> rows) => [
        for (final r in rows)
          () {
            final a = _sole(r);
            final multi = (tIntOrNull(r['allocationCount']) ?? 0) > 1;
            final n = tIntOrNull(r['allocationCount']) ?? 0;
            String f2(Object? v) => tNum(v).toStringAsFixed(2);
            return [
              fmtDateTime(r['paymentDate'], r, _offset),
              tStr(r['paymentId']),
              tStr(r['partyName']).isEmpty ? '—' : tStr(r['partyName']),
              multi ? 'Multiple' : (a == null ? '—' : (tStr(a['reference']).isNotEmpty ? tStr(a['reference']) : tStr(a['documentId']))),
              multi ? 'Multiple' : payableTypeLabel(a?['documentType']),
              multi || a == null ? '' : f2(a['documentTotal']),
              f2(r['totalAmount']),
              multi || a == null ? '' : f2(a['balanceBefore']),
              multi ? f2(r['totalAmount']) : (a == null ? '' : f2(a['amountApplied'])),
              multi || a == null ? '' : f2(a['balanceAfter']),
              '$n item${n == 1 ? '' : 's'}',
              tStr(r['paymentMethod']).isEmpty ? '—' : tStr(r['paymentMethod']),
              _accountName(r['cashAccountId']),
              tStr(r['reference']).isEmpty ? '—' : tStr(r['reference']),
              supplierSourceLabel(r['sourceType']),
              tStr(r['createdBy']).isEmpty ? '—' : tStr(r['createdBy']),
              tStr(r['status']),
            ];
          }(),
      ];

  ReportDocument _doc(List<Map> rows) {
    final posted = rows.where((r) => tStr(r['status']) == 'Posted');
    return ReportDocument(
      title: 'Supplier Payments',
      filename: 'supplier-payments',
      farmName: widget.company.name,
      fromDate: _from.isEmpty ? null : _from,
      toDate: _to.isEmpty ? null : _to,
      landscape: true,
      cards: [
        (label: 'Payments', value: '${rows.length}', accent: null, note: null),
        (label: 'Total paid', value: _fmt(posted.fold<num>(0, (s, r) => s + tNum(r['totalAmount']))), accent: 'rose', note: null),
        (label: 'Reversed', value: '${rows.where((r) => tStr(r['status']) == 'Reversed').length}', accent: null, note: null),
      ],
      sections: [
        ReportSection(columns: [for (final h in supplierExportHeaders) ReportColumn(h)], rows: _exportRows(rows)),
      ],
    );
  }

  /// downloadCsv: the headers and rows only, with a BOM so Excel reads UTF-8.
  Future<void> _csv(List<Map> rows) {
    String esc(String v) => v.contains(',') || v.contains('"') || v.contains('\n') ? '"${v.replaceAll('"', '""')}"' : v;
    final csv = [supplierExportHeaders.map(esc).join(','), for (final r in _exportRows(rows)) r.map(esc).join(',')].join('\n');
    return ReportExport.sharer('supplier-payments-${DateTime.now().toUtc().toIso8601String().substring(0, 10)}.csv',
        [0xEF, 0xBB, 0xBF, ...utf8.encode(csv)], 'text/csv', 'Supplier Payments');
  }

  void _href(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  Widget _statusBadge(Map r) => tStr(r['status']) == 'Reversed'
      ? const TBadge('Reversed', bg: Colors.white, fg: TColors.slate500, border: TColors.slate300)
      : const TBadge('Posted', bg: TColors.slate100, fg: TColors.slate800);

  /// The reversal box: on the web it sits under the table row; on the phone it
  /// sits in the card it belongs to.
  Widget _reverseBox(Map r) {
    final n = tIntOrNull(r['allocationCount']) ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: TColors.amber50, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilterLabel('Why is this being reversed?', AppInput(controller: _reason, hintText: 'e.g. paid the wrong supplier')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          FilledButton(
            onPressed: () => _doReverse(r),
            style: FilledButton.styleFrom(backgroundColor: TColors.red600, foregroundColor: Colors.white),
            child: const Text('Reverse payment'),
          ),
          TextButton(onPressed: () => setState(() => _reversing = null), child: const Text('Cancel')),
        ]),
        const SizedBox(height: 6),
        Text(
          'This reverses the whole payment and restores the balance on${n == 1 ? ' the item' : ' all $n items'} it was applied to. The cash movement is undone. The payment is kept and marked reversed, never deleted.',
          style: const TextStyle(fontSize: 12, color: TColors.slate500),
        ),
      ]),
    );
  }

  Widget _allocationTable(Map r) {
    final allocs = _allocations[tStr(r['paymentId'])];
    if (allocs == null) {
      return const Row(children: [
        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 8),
        Text('Loading allocation…', style: TextStyle(fontSize: 13, color: TColors.slate500)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TrackerTable(
        columns: const [
          TCol('Type', width: 110),
          TCol('Purchase / Expense #', width: 160),
          TCol('Item', width: 130),
          TCol('Date', width: 140),
          TCol('Payable total', right: true, width: 120),
          TCol('Balance before', right: true, width: 120),
          TCol('Applied', right: true, width: 110),
          TCol('Balance after', right: true, width: 120),
          TCol('Status', width: 100),
          TCol('', width: 48),
        ],
        rows: [
          for (final a in allocs)
            [
              cellText(payableTypeLabel(a['documentType'])),
              Text(tStr(a['reference']).isNotEmpty ? tStr(a['reference']) : '#${tStr(a['documentId'])}', style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(tStr(a['label']).isEmpty ? '—' : tStr(a['label']), style: const TextStyle(color: TColors.slate600)),
              cellText(tStr(a['documentDate']).isEmpty ? '—' : fmtDateTime(a['documentDate'], a, _offset)),
              Align(alignment: Alignment.centerRight, child: Text(_fmt(tNum(a['documentTotal'])))),
              Align(alignment: Alignment.centerRight, child: Text(_fmt(tNum(a['balanceBefore'])), style: const TextStyle(color: TColors.slate500))),
              Align(alignment: Alignment.centerRight, child: Text(_fmt(tNum(a['amountApplied'])), style: const TextStyle(fontWeight: FontWeight.w500))),
              Align(alignment: Alignment.centerRight, child: Text(_fmt(tNum(a['balanceAfter'])))),
              Align(alignment: Alignment.centerLeft, child: _statusBadge(a)),
              IconButton(
                tooltip: 'Open the item this paid',
                onPressed: () => _href(supplierDocumentHref(a), payableTypeLabel(a['documentType'])),
                icon: const Icon(Icons.open_in_new, size: 16),
              ),
            ],
        ],
      ),
      const SizedBox(height: 4),
      Text('Entered from ${supplierSourceLabel(r['sourceType'])}${tStr(r['createdBy']).isNotEmpty ? ' by ${tStr(r['createdBy'])}' : ''}',
          style: const TextStyle(fontSize: 12, color: TColors.slate500)),
    ]);
  }

  Widget _table(List<Map> items) {
    final extras = [for (final r in items) if (_expanded == tStr(r['paymentId']) || _reversing == tStr(r['paymentId'])) r];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TrackerTable(
        columns: const [
          TCol('', width: 36),
          TCol('Date', width: 140),
          TCol('Payment #', width: 110),
          TCol('Supplier', width: 130),
          TCol('Paid against', width: 160),
          TCol('Amount', right: true, width: 120),
          TCol('Method', width: 100),
          TCol('Cash account', width: 120),
          TCol('Reference', width: 110),
          TCol('Status', width: 100),
          TCol('', width: 150),
        ],
        rows: [
          for (final r in items)
            () {
              final reversed = tStr(r['status']) == 'Reversed';
              final multi = (tIntOrNull(r['allocationCount']) ?? 0) > 1;
              final a = _sole(r);
              final id = tStr(r['paymentId']);
              final grey = reversed ? const TextStyle(color: TColors.slate400) : null;
              return <Widget>[
                InkWell(
                  onTap: () => _toggle(r),
                  child: Icon(_expanded == id ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 18),
                ),
                Text(fmtDateTime(r['paymentDate'], r, _offset), style: grey),
                Text('SPAY-$id', style: const TextStyle(fontWeight: FontWeight.w500)),
                tIntOrNull(r['partyId']) != null
                    ? InkWell(
                        onTap: () => _href('/suppliers', 'Suppliers'),
                        child: Text(tStr(r['partyName']).isNotEmpty ? tStr(r['partyName']) : '#${tStr(r['partyId'])}',
                            style: const TextStyle(color: Color(0xFF0369A1))),
                      )
                    : const Text('No supplier', style: TextStyle(color: TColors.slate400)),
                multi
                    ? Text('${tStr(r['allocationCount'])} items', style: const TextStyle(color: TColors.slate500))
                    : Text.rich(TextSpan(children: [
                        TextSpan(text: a == null ? '—' : (tStr(a['reference']).isNotEmpty ? tStr(a['reference']) : '#${tStr(a['documentId'])}')),
                        if (a != null) TextSpan(text: '  ${payableTypeLabel(a['documentType'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                      ])),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(_fmt(tNum(r['totalAmount'])),
                      style: TextStyle(fontWeight: FontWeight.w600, decoration: reversed ? TextDecoration.lineThrough : null, color: grey?.color)),
                ),
                Text(tStr(r['paymentMethod']).isEmpty ? '—' : tStr(r['paymentMethod']), style: grey),
                Text(_accountName(r['cashAccountId']), style: grey),
                Text(tStr(r['reference']).isEmpty ? '—' : tStr(r['reference']), style: grey),
                Align(alignment: Alignment.centerLeft, child: _statusBadge(r)),
                Wrap(alignment: WrapAlignment.end, children: [
                  if (!multi && a != null)
                    IconButton(
                      tooltip: 'Open the item this paid',
                      onPressed: () => _href(supplierDocumentHref(a), payableTypeLabel(a['documentType'])),
                      icon: const Icon(Icons.open_in_new, size: 16),
                    ),
                  if (_canReverse && !reversed)
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _reversing = id;
                        _reason.clear();
                      }),
                      icon: const Icon(Icons.undo, size: 14),
                      label: const Text('Reverse'),
                    ),
                ]),
              ];
            }(),
        ],
      ),
      for (final r in extras) ...[
        const SizedBox(height: 10),
        Text('SPAY-${tStr(r['paymentId'])}', style: const TextStyle(fontWeight: FontWeight.w600)),
        if (_reversing == tStr(r['paymentId'])) ...[const SizedBox(height: 6), _reverseBox(r)],
        if (_expanded == tStr(r['paymentId'])) ...[const SizedBox(height: 6), _allocationTable(r)],
      ],
    ]);
  }

  int get _moreActive =>
      [_f.method, _f.account, _f.source, _f.appliedTo, _f.payableType].where((v) => v != 'all').length +
      [_from, _to, _f.min.trim(), _f.max.trim()].where((v) => v.isNotEmpty).length;

  Widget _filters() {
    final suppliers = <String, String>{};
    for (final r in _rows) {
      final id = tIntOrNull(r['partyId']);
      if (id != null) suppliers['$id'] = tStr(r['partyName']).isNotEmpty ? tStr(r['partyName']) : 'Supplier #$id';
    }
    final sups = suppliers.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final methods = {for (final r in _rows) if (tStr(r['paymentMethod']).trim().isNotEmpty) tStr(r['paymentMethod']).trim()}.toList()..sort();
    AppSelect<String> sel(String value, List<AppSelectItem<String>> items, ValueChanged<String> on) =>
        AppSelect<String>(value: value, items: items, onChanged: (v) => setState(() => on(v ?? 'all')));
    final money = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilterLabel('Search', AppInput(controller: _search, hintText: 'Supplier, payment #, item, reference', onChanged: (v) => setState(() => _f.search = v))),
        const SizedBox(height: 10),
        FilterLabel('Supplier', sel(_f.supplier, [
          const AppSelectItem(value: 'all', label: 'All suppliers'),
          for (final e in sups) AppSelectItem(value: e.key, label: e.value),
        ], (v) => _f.supplier = v)),
        const SizedBox(height: 10),
        FilterLabel(
          'Period',
          AppSelect<String>(
            value: _period,
            items: [
              const AppSelectItem(value: 'all', label: 'All time'),
              for (final (_, opts) in periodGroups) for (final (k, l) in opts) AppSelectItem(value: k, label: l),
            ],
            onChanged: (v) {
              final r = v == null ? null : periodToRange(v);
              setState(() {
                _period = v ?? 'all';
                _from = r?.from ?? '';
                _to = r?.to ?? '';
              });
              _load();
            },
          ),
        ),
        const SizedBox(height: 10),
        FilterLabel('Status', sel(_f.status, const [
          AppSelectItem(value: 'all', label: 'All statuses'),
          AppSelectItem(value: 'Posted', label: 'Posted'),
          AppSelectItem(value: 'Reversed', label: 'Reversed'),
        ], (v) => _f.status = v)),
        if (_showMore) ...[
          const Divider(height: 24),
          filterRow([
            FilterLabel('From', FilterDate(value: _from, hint: 'From', onChanged: (v) {
              setState(() {
                _from = v;
                _period = rangeToPeriod(v, _to);
              });
              _load();
            })),
            FilterLabel('To', FilterDate(value: _to, hint: 'To', onChanged: (v) {
              setState(() {
                _to = v;
                _period = rangeToPeriod(_from, v);
              });
              _load();
            })),
          ]),
          const SizedBox(height: 10),
          FilterLabel('Payment method', sel(_f.method, [
            const AppSelectItem(value: 'all', label: 'All methods'),
            for (final m in methods) AppSelectItem(value: m, label: m),
          ], (v) => _f.method = v)),
          const SizedBox(height: 10),
          FilterLabel('Cash account', sel(_f.account, [
            const AppSelectItem(value: 'all', label: 'All accounts'),
            for (final a in _accounts) AppSelectItem(value: tStr(a['id']), label: tStr(a['name'])),
          ], (v) => _f.account = v)),
          const SizedBox(height: 10),
          FilterLabel('Entered from', sel(_f.source, [
            const AppSelectItem(value: 'all', label: 'Anywhere'),
            for (final s in supplierSourceFilters) AppSelectItem(value: s, label: supplierSourceLabel(s)),
          ], (v) => _f.source = v)),
          const SizedBox(height: 10),
          FilterLabel('Payable type', sel(_f.payableType, const [
            AppSelectItem(value: 'all', label: 'All types'),
            AppSelectItem(value: 'RawMaterialPurchase', label: 'Purchase'),
            AppSelectItem(value: 'FlockBatch', label: 'Flock batch'),
            AppSelectItem(value: 'Expense', label: 'Expense'),
          ], (v) => _f.payableType = v)),
          const SizedBox(height: 10),
          FilterLabel('Applied to', sel(_f.appliedTo, const [
            AppSelectItem(value: 'all', label: 'Any number of items'),
            AppSelectItem(value: 'single', label: 'A single item'),
            AppSelectItem(value: 'multiple', label: 'Several items'),
          ], (v) => _f.appliedTo = v)),
          const SizedBox(height: 10),
          filterRow([
            FilterLabel('Min amount', AppInput(controller: _min, hintText: '0', inputFormatters: money,
                keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) => setState(() => _f.min = v))),
            FilterLabel('Max amount', AppInput(controller: _max, hintText: 'Any', inputFormatters: money,
                keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) => setState(() => _f.max = v))),
          ]),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            onPressed: () => setState(() => _showMore = !_showMore),
            icon: const Icon(Icons.tune, size: 15),
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_showMore ? 'Fewer filters' : 'More filters'),
              if (_moreActive > 0) ...[const SizedBox(width: 6), TBadge('$_moreActive', bg: TColors.slate100, fg: TColors.slate800)],
            ]),
          ),
          OutlinedButton(onPressed: _reset, child: const Text('Reset')),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/supplier-payments');
    final filtered = filterSupplierPayments(_rows, _f, _allocations);
    if (filtered.length != _lastTotal) {
      _lastTotal = filtered.length;
      _page = 1;
    }
    final pageRows = pageSlice(filtered, _page, _pageSize);
    // The page fetches the one-item rows' allocation itself, to show what they paid.
    for (final r in pageRows) {
      if (tIntOrNull(r['allocationCount']) == 1 && !_allocations.containsKey(tStr(r['paymentId']))) _fetch(tStr(r['paymentId']), silent: true);
    }
    final posted = filtered.where((r) => tStr(r['status']) == 'Posted').fold<num>(0, (s, r) => s + tNum(r['totalAmount']));
    Widget stat(String label, String value) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            const SizedBox(height: 4),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TColors.slate900)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Supplier Payments')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.receipt_long, size: 24, color: TColors.amber600),
              SizedBox(width: 8),
              Expanded(child: Text('Supplier Payments', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 4),
            const Text('Track payments made to suppliers and apply them to unpaid or partially paid purchases and expenses.',
                style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 14),
            twoUp([
              stat('Payments', '${filtered.length}'),
              stat('Total paid', _fmt(posted)),
              stat('Across several items', '${filtered.where((r) => (tIntOrNull(r['allocationCount']) ?? 0) > 1).length}'),
              stat('Reversed', '${filtered.where((r) => tStr(r['status']) == 'Reversed').length}'),
            ]),
            const SizedBox(height: 14),
            _filters(),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: filtered.isEmpty ? null : () => _csv(filtered),
                icon: const Icon(Icons.download, size: 15),
                label: const Text('CSV'),
              ),
              OutlinedButton.icon(
                onPressed: filtered.isEmpty ? null : () => ReportExport.sharePdf(_doc(filtered)),
                icon: const Icon(Icons.description_outlined, size: 15),
                label: const Text('PDF'),
              ),
            ]),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading payments…'))
            else if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: const Text('No supplier payments match these filters.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
              )
            else
              MobileCardList<Map>(
                striped: true,
                stripeBlue: true,
                items: pageRows,
                keyOf: (r) => tStr(r['paymentId']),
                primary: (r) => 'SPAY-${tStr(r['paymentId'])}',
                secondary: (r) => '${tStr(r['partyName']).isEmpty ? 'No supplier' : tStr(r['partyName'])} · ${fmtDateTime(r['paymentDate'], r, _offset)}',
                trailing: (r) => Padding(padding: const EdgeInsets.only(left: 6), child: _statusBadge(r)),
                highlights: (r) {
                  final n = tIntOrNull(r['allocationCount']) ?? 0;
                  return [
                    Highlight('Paid', _fmt(tNum(r['totalAmount'])), accent: Accent.blue),
                    Highlight('Applied to', '$n item${n == 1 ? '' : 's'}', accent: Accent.violet),
                  ];
                },
                details: (r) {
                  final a = _sole(r);
                  final multi = (tIntOrNull(r['allocationCount']) ?? 0) > 1;
                  return [
                    ('Purchase / Expense #', multi ? 'Multiple' : (tStr(a?['reference']).isEmpty ? '—' : tStr(a?['reference']))),
                    ('Payable type', multi ? 'Multiple' : payableTypeLabel(a?['documentType'])),
                    ('Balance before', multi || a == null ? '—' : _fmt(tNum(a['balanceBefore']))),
                    ('Applied', multi ? _fmt(tNum(r['totalAmount'])) : (a != null ? _fmt(tNum(a['amountApplied'])) : '—')),
                    ('Balance after', multi || a == null ? '—' : _fmt(tNum(a['balanceAfter']))),
                    ('Method', tStr(r['paymentMethod']).isEmpty ? '—' : tStr(r['paymentMethod'])),
                    ('Cash account', _accountName(r['cashAccountId'])),
                    ('Reference', tStr(r['reference']).isEmpty ? '—' : tStr(r['reference'])),
                    ('Entered from', supplierSourceLabel(r['sourceType'])),
                    ('Paid by', tStr(r['createdBy']).isEmpty ? '—' : tStr(r['createdBy'])),
                  ];
                },
                extra: (r) => _reversing == tStr(r['paymentId']) ? _reverseBox(r) : const SizedBox.shrink(),
                actions: (r) => [
                  if (_canReverse && tStr(r['status']) == 'Posted' && _reversing != tStr(r['paymentId']))
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _reversing = tStr(r['paymentId']);
                        _reason.clear();
                      }),
                      icon: const Icon(Icons.undo, size: 15),
                      label: const Text('Reverse'),
                    ),
                ],
                table: _table,
                pager: CompactPager(
                  total: filtered.length,
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
