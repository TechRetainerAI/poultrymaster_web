import 'dart:math';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import '../shared/iam_permissions.dart';
import '../shared/reason_dialog.dart' show companyToday;
import 'expenses/asset_widgets.dart' show ReasonTextPrompt;
import 'money/money_widgets.dart';
import 'poultry_links.dart';
import 'purchase_receipt_logic.dart';
import 'reports/report_format.dart';
import 'sales/balances_logic.dart' show pageSlice;
import 'sales/balances_widgets.dart';
import 'trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import 'trackers/tracker_widgets.dart';

/// Poultry → Tools → Receive Purchase, as `app/poultry-purchase-receipts/page.tsx`
/// with `components/poultry/receive-purchase-dialog.tsx` (migration 345): one
/// supplier invoice — several items, additional costs and whatever was paid on
/// the spot — received in one save; listed, opened and reversed here.

const receiptViewKey = 'poultry.purchase-receipts.view';
const receiptCreateKey = 'poultry.purchase-receipts.create';
const receiptApproveKey = 'poultry.purchase-receipts.approve';
const supplierPayKey = 'poultry.supplier-payments.create';

const _emerald600 = Color(0xFF059669);
const _indigo = Color(0xFF4F46E5);
const _blue = Color(0xFF2563EB);
const _slateBand = Color(0xFF475569);
const _amberBand = Color(0xFFD97706);

String _day(Object? v) {
  final s = tStr(v);
  return s.isEmpty ? '—' : (s.length >= 10 ? s.substring(0, 10) : s);
}

/// A version-4 id: one idempotency key per opened form.
String newClientRequestId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// STATUS_TONE: (bg, fg, border).
(Color, Color, Color) _statusTone(Object? s) => switch (s) {
      'Paid' => (TColors.emerald100, TColors.emerald800, TColors.emerald300),
      'Part paid' => (TColors.amber100, TColors.amber800, TColors.amber300),
      'Unpaid' => (TColors.rose100, TColors.rose800, const Color(0xFFFDA4AF)),
      _ => (TColors.slate100, TColors.slate600, TColors.slate300),
    };

Widget receiptStatusBadge(Map r) {
  final (bg, fg, border) = _statusTone(r['paymentStatus']);
  return Wrap(spacing: 4, children: [
    TBadge(tStr(r['paymentStatus']), bg: bg, fg: fg, border: border),
    if (r['isOverdue'] == true) const TBadge('Overdue', bg: TColors.rose50, fg: TColors.rose700, border: Color(0xFFFDA4AF)),
  ]);
}

class PurchaseReceiptsScreen extends StatefulWidget {
  const PurchaseReceiptsScreen({super.key, required this.session, required this.company, this.openReceive = false});
  final Session session;
  final Company company;

  /// `?receive=1`: opens the Receive Purchase form straight away.
  final bool openReceive;

  @override
  State<PurchaseReceiptsScreen> createState() => _PurchaseReceiptsScreenState();
}

class _PurchaseReceiptsScreenState extends State<PurchaseReceiptsScreen> {
  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  static const _base = '/api/Poultry/purchase-receipts';
  List<Map> _rows = [];
  bool _loading = true;
  final _search = TextEditingController();
  String _status = 'All';
  List<Map> _items = [], _suppliers = [], _cash = [];
  bool _permsLoaded = false;
  Set<String> _held = {};
  String _today = '';
  int _page = 1, _pageSize = 10;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  bool get _canView => !_permsLoaded || _held.contains(receiptViewKey);
  bool get _canReceive => _held.contains(receiptCreateKey);
  bool get _canReverse => _held.contains(receiptApproveKey);
  bool get _canPay => _held.contains(supplierPayKey);

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    companyToday(widget.session, widget.company).then((t) {
      if (mounted) setState(() => _today = t);
    });
    canDoAll(widget.session, widget.company, const [receiptViewKey, receiptCreateKey, receiptApproveKey, supplierPayKey]).then((h) {
      if (!mounted) return;
      setState(() {
        _held = h;
        _permsLoaded = true;
      });
      if (widget.openReceive && _canReceive) _receive();
    });
    _load();
    _loadLookups();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _api.get(_base, query: {'farmId': _farmId});
      if (mounted) setState(() => _rows = rowsOf(r));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load purchase receipts', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadLookups() async {
    Future<List<Map>> soft(String path, Map<String, dynamic> q) async {
      try {
        return rowsOf(await _api.get(path, query: q));
      } on ApiException {
        return [];
      }
    }

    final r = await Future.wait([
      soft('/api/Poultry/raw-material-items', {'farmId': _farmId}),
      soft('/api/Poultry/cash-accounts', {'farmId': _farmId}),
      soft('/api/Supplier', {'userId': widget.session.tokens.userId ?? '', 'farmId': _farmId}),
    ]);
    if (!mounted) return;
    setState(() {
      _items = r[0];
      _cash = r[1];
      _suppliers = [...r[2]]..sort((a, b) => tStr(a['name']).compareTo(tStr(b['name'])));
    });
  }

  Future<void> _receive() async {
    final receipt = await Navigator.of(context).push<Map>(MaterialPageRoute(
      builder: (_) => ReceivePurchaseScreen(
        session: widget.session,
        company: widget.company,
        items: _items,
        suppliers: _suppliers,
        cashAccounts: _cash,
        today: _today,
        canPay: _canPay,
      ),
    ));
    if (receipt == null || !mounted) return;
    await Future.wait([_load(), _loadLookups()]);
    if (mounted) _openDetail(tIntOrNull(receipt['poultryPurchaseReceiptId']) ?? 0);
  }

  Future<void> _openDetail(int id) async {
    final first = _rows.where((r) => tIntOrNull(r['poultryPurchaseReceiptId']) == id);
    await showDialog<void>(
      context: context,
      builder: (_) => _ReceiptDetailDialog(
        session: widget.session,
        company: widget.company,
        id: id,
        initial: first.isEmpty ? null : first.first,
        canReverse: _canReverse,
        gh: _gh,
        offset: _offset,
        onReversed: _load,
      ),
    );
  }

  List<Map> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final r in _rows)
        if (!(_status == 'Open' && !(r['status'] == 'Posted' && tNum(r['balance']) > 0)) &&
            !(_status == 'Paid' && r['paymentStatus'] != 'Paid') &&
            !(_status == 'Reversed' && r['status'] != 'Reversed') &&
            (q.isEmpty || [r['receiptNumber'], r['supplierName'], r['referenceNo'], r['itemSummary']].any((v) => tStr(v).toLowerCase().contains(q))))
          r,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-purchase-receipts');
    if (!_canView) {
      return Scaffold(
        appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Purchase Receipts')),
        body: ListView(padding: const EdgeInsets.all(14), children: const [
          TCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Column(children: [
                Icon(Icons.lock_outline, size: 24, color: TColors.slate400),
                SizedBox(height: 8),
                Text('You do not have access to Purchase Receipts.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate600)),
              ]),
            ),
          ),
        ]),
      );
    }
    final filtered = _filtered;
    final pageRows = pageSlice(filtered, _page, _pageSize);
    final posted = _rows.where((r) => r['status'] == 'Posted').toList();
    final outstanding = posted.fold<num>(0, (s, r) => s + tNum(r['balance']));
    final overdue = posted.where((r) => r['isOverdue'] == true).fold<num>(0, (s, r) => s + tNum(r['balance']));
    final awaitingPl = posted.fold<num>(0, (s, r) => s + tNum(r['deferredCost']));
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Purchase Receipts')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.inventory_outlined, size: 22, color: _emerald600),
              SizedBox(width: 8),
              Expanded(child: Text('Purchase Receipts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 4),
            Wrap(children: [
              const Text('Receive a supplier invoice in one step: the stock, what you owe and anything paid now. Balances are paid later from ',
                  style: TextStyle(fontSize: 13, color: TColors.slate600)),
              InkWell(
                onTap: () => openPoultryHref(context, widget.session, widget.company, '/supplier-balances', label: 'Supplier Balances'),
                child: const Text('Supplier Balances', style: TextStyle(fontSize: 13, color: Color(0xFF1D4ED8))),
              ),
              const Text('.', style: TextStyle(fontSize: 13, color: TColors.slate600)),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
              if (_canReceive)
                FilledButton.icon(onPressed: _receive, icon: const Icon(Icons.inventory_outlined, size: 16), label: const Text('Receive purchase')),
            ]),
            const SizedBox(height: 14),
            twoUp([
              _tile('Receipts', fmtNum(posted.length, 0)),
              _tile('Owed to suppliers', _gh(outstanding), tone: Accent.amber),
              _tile('Overdue', _gh(overdue), tone: overdue > 0 ? Accent.rose : null),
              _tile('Held as stock until used', _gh(awaitingPl), tone: Accent.violet),
            ]),
            const SizedBox(height: 12),
            ListFiltersCard(
              search: _search,
              searchPlaceholder: 'Search receipt, supplier, invoice or item',
              onSearch: () => setState(() => _page = 1),
              from: '',
              to: '',
              onDates: (_, _) {},
              onClear: () => setState(() {
                _search.clear();
                _page = 1;
              }),
              searchOnly: true,
            ),
            const SizedBox(height: 8),
            AppSelect<String>(
              value: _status,
              items: const [
                AppSelectItem(value: 'All', label: 'All receipts'),
                AppSelectItem(value: 'Open', label: 'With a balance'),
                AppSelectItem(value: 'Paid', label: 'Paid'),
                AppSelectItem(value: 'Reversed', label: 'Reversed'),
              ],
              onChanged: (v) => setState(() {
                _status = v ?? _status;
                _page = 1;
              }),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const TCard(child: LoadingLine('Loading…'))
            else if (filtered.isEmpty)
              TCard(
                child: Center(
                  child: Text(_rows.isEmpty ? 'No purchase has been received yet.' : 'Nothing matches these filters.',
                      style: const TextStyle(color: TColors.slate500)),
                ),
              )
            else
              MobileCardList<Map>(
                items: pageRows,
                keyOf: (r) => '${r['poultryPurchaseReceiptId']}',
                primary: (r) => '${tStr(r['receiptNumber'])} · ${tStr(r['supplierName'])}',
                onPrimary: (r) => _openDetail(tIntOrNull(r['poultryPurchaseReceiptId']) ?? 0),
                secondary: (r) => '${fmtDateTime(r['purchaseDate'], r, _offset)}${tStr(r['referenceNo']).isNotEmpty ? ' · Inv ${tStr(r['referenceNo'])}' : ''}',
                trailing: (r) => receiptStatusBadge(r),
                highlights: (r) => [
                  Highlight('Total', _gh(tNum(r['totalCost']))),
                  Highlight('Balance', _gh(tNum(r['balance'])), accent: tNum(r['balance']) > 0 ? Accent.amber : Accent.emerald),
                ],
                details: (r) => [
                  ('Items', tStr(r['itemSummary']).isEmpty ? '—' : tStr(r['itemSummary'])),
                  ('Paid', _gh(tNum(r['amountPaid']))),
                  ('Due', tNum(r['balance']) > 0 ? _day(r['dueDate']) : '—'),
                ],
                actions: (r) => [
                  OutlinedButton(onPressed: () => _openDetail(tIntOrNull(r['poultryPurchaseReceiptId']) ?? 0), child: const Text('Open')),
                ],
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Receipt', width: 120),
                    TCol('Date', width: 140),
                    TCol('Supplier', width: 150),
                    TCol('Invoice', width: 110),
                    TCol('Items', width: 220),
                    TCol('Total', right: true, width: 120),
                    TCol('Paid', right: true, width: 120),
                    TCol('Balance', right: true, width: 120),
                    TCol('Status', width: 170),
                  ],
                  rows: [
                    for (final r in items)
                      [
                        InkWell(
                          onTap: () => _openDetail(tIntOrNull(r['poultryPurchaseReceiptId']) ?? 0),
                          child: Text(tStr(r['receiptNumber']), style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF1D4ED8))),
                        ),
                        cellText(fmtDateTime(r['purchaseDate'], r, _offset)),
                        cellText(tStr(r['supplierName'])),
                        cellText(tStr(r['referenceNo']).isEmpty ? '—' : tStr(r['referenceNo'])),
                        cellText(tStr(r['itemSummary'])),
                        Align(alignment: Alignment.centerRight, child: Text(_gh(tNum(r['totalCost'])))),
                        Align(alignment: Alignment.centerRight, child: Text(_gh(tNum(r['amountPaid'])))),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(_gh(tNum(r['balance'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        receiptStatusBadge(r),
                      ],
                  ],
                ),
                pager: CompactPager(
                  total: filtered.length,
                  page: _page,
                  pageSize: _pageSize,
                  onPage: (p) => setState(() => _page = p),
                  onPageSize: (s) => setState(() {
                    _pageSize = s;
                    _page = 1;
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tile(String label, String value, {Accent? tone}) {
    final (bg, border, lc, vc) = tone == null ? (Colors.white, TColors.slate200, TColors.slate500, TColors.slate900) : accentTone(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, color: lc)),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: vc)),
      ]),
    );
  }
}

// =============================================================================
// Receipt detail
// =============================================================================

Widget _sectionLabel(String text) => Text(text.toUpperCase(),
    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: TColors.slate500));

Widget _figure(String label, String value, {Color? tone}) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tone ?? TColors.slate900)),
      ]),
    );

class _ReceiptDetailDialog extends StatefulWidget {
  const _ReceiptDetailDialog({
    required this.session,
    required this.company,
    required this.id,
    required this.initial,
    required this.canReverse,
    required this.gh,
    required this.offset,
    required this.onReversed,
  });
  final Session session;
  final Company company;
  final int id;
  final Map? initial;
  final bool canReverse;
  final FarmMoney gh;
  final Duration offset;
  final Future<void> Function() onReversed;

  @override
  State<_ReceiptDetailDialog> createState() => _ReceiptDetailDialogState();
}

class _ReceiptDetailDialogState extends State<_ReceiptDetailDialog> {
  late Map? _r = widget.initial;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.session.farmClient.get('/api/Poultry/purchase-receipts/${widget.id}', query: {'farmId': widget.company.farmId}).then((r) {
      if (mounted) {
        setState(() {
          if (r is Map) _r = r;
          _loading = false;
        });
      }
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() => _loading = false);
      trackerToast(context, 'Could not open the receipt', description: e is ApiException ? e.message : '$e', error: true);
    });
  }

  Future<void> _reverse(Map r) async {
    Map? result;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ReasonTextPrompt(
        title: 'Reverse ${tStr(r['receiptNumber'])}?',
        description:
            'The stock comes back out, any payment made on this receipt is reversed and its cash returns to the account, and the supplier no longer owes anything for it. Nothing is deleted: the receipt stays here marked Reversed.',
        placeholder: 'e.g. Entered against the wrong supplier',
        confirmLabel: 'Reverse receipt',
        onSubmit: (reason) async {
          try {
            final res = await widget.session.farmClient.post('/api/Poultry/purchase-receipts/${widget.id}/reverse',
                query: {'farmId': widget.company.farmId},
                body: {'farmId': widget.company.farmId, 'reason': reason, 'reversedBy': widget.session.tokens.userId});
            result = res is Map ? res : null;
          } on ApiException catch (e) {
            if (mounted) trackerToast(context, 'Could not reverse the receipt', description: e.message, error: true);
            rethrow;
          }
        },
      ),
    );
    if (ok != true || !mounted) return;
    final n = tNum(result?['linesReversed']).toInt();
    trackerToast(context, '${tStr(r['receiptNumber'])} reversed', description: '$n item${n == 1 ? '' : 's'} taken back out of stock.');
    if (result?['receipt'] is Map) setState(() => _r = result!['receipt'] as Map);
    await widget.onReversed();
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final gh = widget.gh;
    if (r == null) {
      return const AlertDialog(content: SizedBox(width: 600, child: LoadingLine('Loading…')));
    }
    const small = TextStyle(fontSize: 12, color: TColors.slate600);
    final lines = [for (final l in (r['lines'] as List? ?? const [])) if (l is Map) l];
    final balance = tNum(r['balance']);
    final posted = r['status'] == 'Posted';
    return AlertDialog(
      scrollable: true,
      title: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Icon(Icons.inventory_outlined, size: 20, color: _emerald600),
        Text(tStr(r['receiptNumber'])),
        receiptStatusBadge(r),
      ]),
      content: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            '${tStr(r['supplierName'])} · ${fmtDateTime(r['purchaseDate'], r, widget.offset)}${tStr(r['referenceNo']).isNotEmpty ? ' · Invoice ${tStr(r['referenceNo'])}' : ''}',
            style: const TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 16),
          _sectionLabel('Money'),
          const SizedBox(height: 8),
          twoUp([
            _figure('Total', gh(tNum(r['totalCost']))),
            _figure('Paid', gh(tNum(r['amountPaid']))),
            _figure('Balance', gh(balance)),
            _figure('Due', balance > 0 ? (tStr(r['dueDate']).isEmpty ? 'Supplier terms' : _day(r['dueDate'])) : '—'),
          ]),
          const SizedBox(height: 6),
          if (tNum(r['additionalCosts']) > 0)
            Text(
              'Includes ${gh(tNum(r['additionalCosts']))} additional costs${tStr(r['additionalCostsNote']).isNotEmpty ? ' (${tStr(r['additionalCostsNote'])})' : ''}, spread over the items.',
              style: small,
            ),
          if (tNum(r['amountPaidAtReceipt']) > 0)
            Text(
              '${gh(tNum(r['amountPaidAtReceipt']))} paid on receipt from ${tStr(r['cashAccountName']).isEmpty ? 'a cash account' : tStr(r['cashAccountName'])}'
              '${tStr(r['paymentMethod']).isNotEmpty ? ' (${tStr(r['paymentMethod'])})' : ''}'
              '${r['poultrySupplierPaymentId'] != null ? ' — supplier payment #${tStr(r['poultrySupplierPaymentId'])}' : ''}.',
              style: small,
            ),
          if (tNum(r['expensedAtPurchaseCost']) > 0)
            Text('${gh(tNum(r['expensedAtPurchaseCost']))} of items are expensed as they are paid.', style: small),
          if (tNum(r['deferredCost']) > 0) Text('${gh(tNum(r['deferredCost']))} of items reach Profit & Loss only when used.', style: small),
          if (posted && balance > 0)
            Wrap(children: [
              const Text('Pay the balance from ', style: small),
              InkWell(
                onTap: () => openPoultryHref(context, widget.session, widget.company, '/supplier-balances', label: 'Supplier Balances'),
                child: const Text('Supplier Balances', style: TextStyle(fontSize: 12, color: Color(0xFF1D4ED8))),
              ),
              const Text('.', style: small),
            ]),
          const SizedBox(height: 16),
          Row(children: [
            _sectionLabel('Items'),
            if (_loading) ...[const SizedBox(width: 6), const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5))],
          ]),
          const SizedBox(height: 8),
          for (final l in lines) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(tStr(l['itemName']), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate800))),
                  Text(gh(tNum(l['lineTotal'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
                Text(
                  '${fmtNum(tNum(l['quantity']), 3)} × ${gh(tNum(l['unitCost']))}'
                  '${tNum(l['allocatedAdditionalCost']) > 0 ? ' + ${gh(tNum(l['allocatedAdditionalCost']))} additional · landed ${gh(tNum(l['landedUnitCost']))}' : ''}'
                  '${l['productionUnitsPerPurchaseUnit'] != null && tNum(l['productionUnitsPerPurchaseUnit']) != 1 ? ' · ${fmtNum(tNum(l['productionQuantity']), 3)} ${tStr(l['unitOfMeasure'])} into stock' : ''}',
                  style: small,
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (tStr(l['recognitionLabel']).isNotEmpty) TBadge(tStr(l['recognitionLabel']), bg: Colors.white, fg: TColors.slate900, border: TColors.slate300),
                  if (posted && tNum(l['consumedQuantity']) > 0)
                    TBadge('${fmtNum(tNum(l['consumedQuantity']), 3)} used', bg: Colors.white, fg: TColors.amber800, border: TColors.amber300),
                  if (posted && tNum(l['balance']) > 0)
                    TBadge('${gh(tNum(l['balance']))} owed', bg: Colors.white, fg: TColors.amber800, border: TColors.amber300),
                ]),
              ]),
            ),
            const SizedBox(height: 8),
          ],
          if (tStr(r['notes']).isNotEmpty) ...[
            const SizedBox(height: 8),
            _sectionLabel('Notes'),
            const SizedBox(height: 4),
            Text(tStr(r['notes']), style: const TextStyle(fontSize: 13, color: TColors.slate700)),
          ],
          const SizedBox(height: 16),
          _sectionLabel('Reversal'),
          const SizedBox(height: 8),
          if (r['status'] == 'Reversed')
            Text(
              'Reversed ${fmtInstant(r['reversedAt'], widget.offset)}${tStr(r['reversalReason']).isNotEmpty ? ' — ${tStr(r['reversalReason'])}' : ''}. The stock was taken back out with an opposite adjustment; the lots and the payment remain in the history.',
              style: const TextStyle(fontSize: 13, color: TColors.slate600),
            )
          else if (tStr(r['reversalBlocker']).isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: TColors.amber200), borderRadius: BorderRadius.circular(6)),
              child: Text("Can't be reversed yet: ${tStr(r['reversalBlocker'])}", style: const TextStyle(fontSize: 13, color: TColors.amber800)),
            )
          else if (widget.canReverse)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: TColors.rose700, side: const BorderSide(color: Color(0xFFFDA4AF))),
                onPressed: () => _reverse(r),
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('Reverse receipt'),
              ),
            )
          else
            const Text("You don't have permission to reverse receipts.", style: TextStyle(fontSize: 13, color: TColors.slate500)),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

// =============================================================================
// Receive purchase
// =============================================================================

const receivePaymentMethods = ['Cash', 'MoMo', 'Bank', 'Card'];

class _Line {
  _Line(this.key);
  final int key;
  int itemId = 0;
  num quantity = 0, unitCost = 0, unitsPerPurchaseUnit = 1;
  String notes = '';
}

/// The web's ReceivePurchaseDialog, as a full page: pops with the receipt.
class ReceivePurchaseScreen extends StatefulWidget {
  const ReceivePurchaseScreen({
    super.key,
    required this.session,
    required this.company,
    required this.items,
    required this.suppliers,
    required this.cashAccounts,
    required this.today,
    required this.canPay,
  });
  final Session session;
  final Company company;
  final List<Map> items, suppliers, cashAccounts;

  /// The company's business date, yyyy-mm-dd.
  final String today;

  /// Whether this user may pay on receipt (supplier-payments.create).
  final bool canPay;

  @override
  State<ReceivePurchaseScreen> createState() => _ReceivePurchaseScreenState();
}

class _ReceivePurchaseScreenState extends State<ReceivePurchaseScreen> {
  String _supplier = '';
  late String _purchaseDate = widget.today;
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  final List<_Line> _lines = [_Line(1)];
  num _additional = 0;
  final _additionalNote = TextEditingController();
  late String _payMode = widget.canPay ? 'full' : 'credit';
  num _partAmount = 0;
  String _paymentMethod = 'Cash';
  late int _cashAccountId = () {
    final a = widget.cashAccounts.where((a) => a['isActive'] == true);
    return a.isEmpty ? 0 : tIntOrNull(a.first['poultryCashAccountId']) ?? 0;
  }();
  String _dueDate = '';
  bool _showErrors = false;
  bool _saving = false;
  final String _requestId = newClientRequestId();
  int _nextKey = 2;
  FarmMoney _gh = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
  }

  @override
  void dispose() {
    _reference.dispose();
    _notes.dispose();
    _additionalNote.dispose();
    super.dispose();
  }

  Map? _item(int id) {
    for (final i in widget.items) {
      if (tIntOrNull(i['poultryRawMaterialItemId']) == id) return i;
    }
    return null;
  }

  Map? get _matchedSupplier {
    final t = _supplier.trim().toLowerCase();
    if (t.isEmpty) return null;
    for (final s in widget.suppliers) {
      if (tStr(s['name']).trim().toLowerCase() == t) return s;
    }
    return null;
  }

  List<ReceiptLineDraft> get _drafts => [
        for (final l in _lines)
          ReceiptLineDraft(
            itemId: l.itemId == 0 ? null : l.itemId,
            quantity: l.quantity,
            unitCost: l.unitCost,
            unitsPerPurchaseUnit: l.unitsPerPurchaseUnit == 0 ? 1 : l.unitsPerPurchaseUnit,
            method: tStr(_item(l.itemId)?['effectiveCostRecognitionMethod']).isEmpty ? null : tStr(_item(l.itemId)?['effectiveCostRecognitionMethod']),
          ),
      ];

  Future<void> _save(List<String> errors, num amountPaid, ReceiptPreview preview) async {
    if (_saving) return;
    if (errors.isNotEmpty) return setState(() => _showErrors = true);
    setState(() => _saving = true);
    final matched = _matchedSupplier;
    try {
      final r = await widget.session.farmClient.post('/api/Poultry/purchase-receipts', query: {
        'farmId': widget.company.farmId,
      }, body: {
        'supplierId': matched == null ? null : tIntOrNull(matched['supplierId']),
        'supplierName': matched == null ? _supplier.trim() : null,
        'purchaseDate': _purchaseDate,
        'referenceNo': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        'dueDate': preview.balance > 0 && _dueDate.isNotEmpty ? _dueDate : null,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'additionalCosts': _additional,
        'additionalCostsNote': _additional > 0 && _additionalNote.text.trim().isNotEmpty ? _additionalNote.text.trim() : null,
        'amountPaid': amountPaid,
        'paymentMethod': amountPaid > 0 ? _paymentMethod : null,
        'cashAccountId': amountPaid > 0 ? _cashAccountId : null,
        'clientRequestId': _requestId,
        'lines': [
          for (final l in _lines)
            {
              'poultryRawMaterialItemId': l.itemId,
              'quantity': l.quantity,
              'unitCost': l.unitCost,
              'productionUnit': _item(l.itemId)?['unitOfMeasure'],
              'productionUnitsPerPurchaseUnit': l.unitsPerPurchaseUnit != 0 && l.unitsPerPurchaseUnit != 1 ? l.unitsPerPurchaseUnit : null,
              'notes': l.notes.trim().isEmpty ? null : l.notes.trim(),
            },
        ],
        'farmId': widget.company.farmId,
        'createdBy': widget.session.tokens.userId,
      });
      if (!mounted) return;
      final receipt = r is Map ? r : <String, dynamic>{};
      final n = tNum(receipt['lineCount']).toInt();
      trackerToast(context, 'Received as ${tStr(receipt['receiptNumber'])}',
          description: '$n item${n == 1 ? '' : 's'} · ${_gh(tNum(receipt['totalCost']))} · ${tStr(receipt['paymentStatus'])}');
      Navigator.of(context).pop(receipt);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not receive the purchase', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _label(String text, Widget child, {String? hint}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate700)),
        const SizedBox(height: 4),
        child,
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ],
      ]);

  @override
  Widget build(BuildContext context) {
    final gh = _gh;
    final drafts = _drafts;
    final totalOnly = previewReceipt(drafts, _additional, 0).total;
    final amountPaid = _payMode == 'full' ? totalOnly : (_payMode == 'part' ? _partAmount : 0);
    final preview = previewReceipt(drafts, _additional, amountPaid);
    final errors = validateReceipt(
      supplierChosen: _supplier.trim().isNotEmpty,
      purchaseDate: _purchaseDate,
      today: widget.today,
      dueDate: _dueDate.isEmpty ? null : _dueDate,
      lines: drafts,
      additionalCosts: _additional,
      amountPaid: amountPaid,
      cashAccountId: _cashAccountId == 0 ? null : _cashAccountId,
    );
    if (_payMode == 'part' && (_partAmount <= 0 || _partAmount >= totalOnly) && totalOnly > 0) {
      errors.add('A part payment must be more than 0 and less than the total. Use Paid in full or On credit otherwise.');
    }
    final deferredAny = preview.lines.any((l) => l.deferred);
    final accounts = widget.cashAccounts.where((a) => a['isActive'] == true).toList();
    final account = widget.cashAccounts.where((a) => tIntOrNull(a['poultryCashAccountId']) == _cashAccountId);
    final acct = account.isEmpty ? null : account.first;
    final activeItems = widget.items.where((i) => i['isActive'] == true).toList();
    final matched = _matchedSupplier;

    return Scaffold(
      appBar: AppBar(title: const Text('Receive purchase')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          const Text('One supplier invoice: the stock, what you owe and anything you paid now are recorded together.',
              style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 14),
          formSection('Supplier & Invoice', _indigo, [
            _label(
              'Supplier *',
              Autocomplete<String>(
                optionsBuilder: (v) => [for (final s in widget.suppliers) tStr(s['name'])].where((n) => n.toLowerCase().contains(v.text.toLowerCase())),
                onSelected: (v) => setState(() => _supplier = v),
                fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
                  controller: controller,
                  focusNode: focus,
                  decoration: const InputDecoration(hintText: 'Pick or type a supplier'),
                  onChanged: (v) => setState(() => _supplier = v),
                ),
              ),
              hint: _supplier.trim().isNotEmpty && matched == null ? 'New supplier — it will be added to your suppliers.' : null,
            ),
            _label(
              'Purchase date *',
              AppDateField(
                value: DateTime.tryParse(_purchaseDate),
                lastDate: DateTime.tryParse(widget.today),
                onChanged: (d) {
                  if (d != null) setState(() => _purchaseDate = isoDay(d));
                },
              ),
            ),
            _label('Invoice / reference', AppInput(controller: _reference, hintText: 'e.g. INV-2041'),
                hint: "The same invoice can't be received twice from one supplier."),
          ]),
          const SizedBox(height: 12),
          formSection('Items received', _blue, [
            for (var idx = 0; idx < _lines.length; idx++) _lineCard(_lines[idx], idx, preview, activeItems),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _lines.length >= 50
                    ? null
                    : () => setState(() {
                          _lines.add(_Line(_nextKey));
                          _nextKey += 1;
                        }),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add item'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          formSection('Additional costs', _slateBand, [
            _label(
              'Amount',
              _NumField(value: _additional, decimal: true, onChanged: (v) => setState(() => _additional = v)),
              hint: 'Transport, offloading … spread over the items by value, so it becomes part of their stock cost.',
            ),
            _label('What it was for', AppInput(controller: _additionalNote, hintText: 'e.g. Transport', enabled: _additional > 0)),
          ]),
          const SizedBox(height: 12),
          formSection('Payment', _amberBand, [
            _label(
              'Payment status *',
              Column(children: [
                for (final (m, label, hint) in const [
                  ('full', 'Paid in full', 'Cash leaves now; nothing owed.'),
                  ('part', 'Part payment', 'Pay some now; the rest is owed.'),
                  ('credit', 'On credit', 'Nothing paid; all of it is owed.'),
                ]) ...[
                  _payChoice(m, label, hint),
                  const SizedBox(height: 8),
                ],
              ]),
            ),
            if (_payMode == 'part')
              _label('Amount paid now *', _NumField(value: _partAmount, decimal: true, onChanged: (v) => setState(() => _partAmount = v))),
            if (_payMode != 'credit') ...[
              _label(
                'Paid from *',
                AppSelect<int>(
                  value: accounts.any((a) => tIntOrNull(a['poultryCashAccountId']) == _cashAccountId) ? _cashAccountId : null,
                  hintText: 'Pick cash account',
                  items: [
                    for (final a in accounts)
                      AppSelectItem(
                        value: tIntOrNull(a['poultryCashAccountId']) ?? 0,
                        label: '${tStr(a['accountName'])} (${gh(tNum(a['currentBalance']))})',
                      ),
                  ],
                  onChanged: (v) => setState(() => _cashAccountId = v ?? _cashAccountId),
                ),
              ),
              _label(
                'Method',
                AppSelect<String>(
                  value: _paymentMethod,
                  items: [for (final m in receivePaymentMethods) AppSelectItem(value: m, label: m)],
                  onChanged: (v) => setState(() => _paymentMethod = v ?? _paymentMethod),
                ),
              ),
            ],
            if (preview.balance > 0)
              _label(
                'Due date',
                AppDateField(
                  value: DateTime.tryParse(_dueDate),
                  hintText: 'Supplier terms',
                  firstDate: DateTime.tryParse(_purchaseDate),
                  onChanged: (d) => setState(() => _dueDate = d == null ? '' : isoDay(d)),
                ),
                hint: "Empty = the supplier's payment terms.",
              ),
          ]),
          const SizedBox(height: 12),
          formSection('Notes', _slateBand, [
            _label('Notes', AppTextarea(controller: _notes, rows: 2, hintText: 'Optional')),
          ]),
          const SizedBox(height: 12),
          // ------------------------------------------- what will be posted
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _sectionLabel('What this will record'),
              const SizedBox(height: 8),
              twoUp([
                _figure('Stock value in', gh(preview.inventoryIncrease)),
                _figure('Cash out${acct != null && preview.cashOut > 0 ? ' · ${tStr(acct['accountName'])}' : ''}', gh(preview.cashOut)),
                _figure('Owed to supplier', gh(preview.payableIncrease), tone: preview.payableIncrease > 0 ? TColors.amber700 : null),
                _figure('Expense today', gh(preview.expenseNow)),
              ]),
              const SizedBox(height: 8),
              if (preview.expenseNow > 0) _bullet('${gh(preview.expenseNow)} reaches Profit & Loss today — items expensed as they are paid.'),
              if (preview.expenseWhenBalancePaid > 0) _bullet('${gh(preview.expenseWhenBalancePaid)} more will be expensed as the balance is paid.'),
              if (deferredAny)
                _bullet('${gh(preview.deferredToConsumption)} is held as stock and reaches Profit & Loss only when it is used (Awaiting P&L until then).'),
              if (acct != null && preview.cashOut > 0 && tNum(acct['currentBalance']) < preview.cashOut && acct['allowNegativeBalance'] != true)
                _bullet('${tStr(acct['accountName'])} only holds ${gh(tNum(acct['currentBalance']))}; this payment would overdraw it.', color: TColors.rose700),
            ]),
          ),
          if (_showErrors && errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: TColors.rose50, border: Border.all(color: TColors.rose200), borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final e in errors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.warning_amber_rounded, size: 16, color: TColors.rose800),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e, style: const TextStyle(fontSize: 13, color: TColors.rose800))),
                    ]),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Total '),
              TextSpan(text: gh(preview.total), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
              if (preview.additionalCosts > 0) TextSpan(text: ' (incl. ${gh(preview.additionalCosts)} additional)'),
            ]),
            style: const TextStyle(fontSize: 13, color: TColors.slate600),
          ),
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: _saving ? null : () => _save(errors, amountPaid, preview),
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Receive purchase'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _bullet(String text, {Color color = TColors.slate600}) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('•  ', style: TextStyle(fontSize: 12, color: color)),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
        ]),
      );

  Widget _payChoice(String m, String label, String hint) {
    final disabled = m != 'credit' && !widget.canPay;
    final on = _payMode == m;
    return Opacity(
      opacity: disabled ? .5 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: disabled ? null : () => setState(() => _payMode = m),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: on ? TColors.emerald50 : Colors.white,
            border: Border.all(color: on ? TColors.emerald500 : TColors.slate200, width: on ? 2 : 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate800)),
            Text(disabled ? "You can't record supplier payments." : hint, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ),
      ),
    );
  }

  Widget _lineCard(_Line l, int idx, ReceiptPreview preview, List<Map> activeItems) {
    final it = _item(l.itemId);
    final p = idx < preview.lines.length ? preview.lines[idx] : null;
    final deferred = it?['effectiveCostRecognitionMethod'] == expenseWhenConsumed;
    final purchaseUnit = tStr(it?['purchaseUnitOfMeasure']);
    final unit = tStr(it?['unitOfMeasure']);
    return Container(
      key: ValueKey('line-${l.key}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('ITEM ${idx + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .5, color: TColors.slate500)),
          ),
          if (it != null)
            TBadge(deferred ? 'Expensed when used' : 'Expensed as paid',
                bg: deferred ? TColors.violet50 : TColors.amber50,
                fg: deferred ? TColors.violet800 : TColors.amber800,
                border: deferred ? const Color(0xFFC4B5FD) : TColors.amber300),
          if (_lines.length > 1)
            IconButton(
              tooltip: 'Remove item',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 18, color: TColors.rose600),
              onPressed: () => setState(() => _lines.remove(l)),
            ),
        ]),
        const SizedBox(height: 8),
        _label(
          'Item *',
          AppSelect<int>(
            value: l.itemId == 0 ? null : l.itemId,
            hintText: 'Pick item',
            items: [
              for (final i in activeItems)
                AppSelectItem(
                  value: tIntOrNull(i['poultryRawMaterialItemId']) ?? 0,
                  label: '${tStr(i['itemName'])}${tStr(i['unitOfMeasure']).isNotEmpty ? ' (${tStr(i['unitOfMeasure'])})' : ''}',
                ),
            ],
            onChanged: (v) => setState(() => l.itemId = v ?? 0),
          ),
        ),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: _label('Quantity${purchaseUnit.isNotEmpty ? ' ($purchaseUnit)' : ''} *',
                _NumField(key: ValueKey('qty-${l.key}'), value: l.quantity, decimal: true, onChanged: (v) => setState(() => l.quantity = v))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _label('Unit cost *',
                _NumField(key: ValueKey('cost-${l.key}'), value: l.unitCost, decimal: true, onChanged: (v) => setState(() => l.unitCost = v))),
          ),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: _label(unit.isNotEmpty ? '$unit per unit' : 'Units per purchase unit',
                _NumField(key: ValueKey('upu-${l.key}'), value: l.unitsPerPurchaseUnit, decimal: true, onChanged: (v) => setState(() => l.unitsPerPurchaseUnit = v))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Line total', style: TextStyle(fontSize: 12, color: TColors.slate500)),
              const SizedBox(height: 14),
              Text(_gh(p?.total ?? 0), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        if (p != null && (p.allocatedAdditional > 0 || (l.unitsPerPurchaseUnit != 0 && l.unitsPerPurchaseUnit != 1))) ...[
          const SizedBox(height: 6),
          Text(
            '${p.allocatedAdditional > 0 ? 'Includes ${_gh(p.allocatedAdditional)} of additional costs · landed ${_gh(p.landedUnitCost)} per unit. ' : ''}'
            '${l.unitsPerPurchaseUnit != 0 && l.unitsPerPurchaseUnit != 1 ? 'Adds ${fmtNum(p.productionQuantity, 3)} ${unit.isNotEmpty ? unit : 'units'} to stock.' : ''}',
            style: const TextStyle(fontSize: 12, color: TColors.slate500),
          ),
        ],
      ]),
    );
  }
}

/// A number box that keeps its own text while the parent rebuilds.
class _NumField extends StatefulWidget {
  const _NumField({super.key, required this.value, required this.onChanged, this.decimal = false});
  final num value;
  final bool decimal;
  final ValueChanged<num> onChanged;

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final _c = TextEditingController(text: widget.value == 0 ? '' : '${widget.value}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppNumberInput(
        controller: _c,
        allowDecimal: widget.decimal,
        hintText: '0',
        onChanged: (v) => widget.onChanged(num.tryParse(v.trim()) ?? 0),
      );
}
