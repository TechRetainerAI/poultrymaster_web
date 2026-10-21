import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../reports/report_export.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart';
import '../trackers/tracker_logic.dart'
    show tNum, tStr, tIntOrNull, loc, trackerDate, localDateKey, sortRows, toggleSort, SortState;
import '../trackers/tracker_widgets.dart';
import 'sale_dialogs.dart';
import 'sale_form_screen.dart';
import 'sale_reversal.dart';
import 'sales_logic.dart';

/// Poultry → Sales, Expenses & Money → Sales → Sales, as `app/sales/page.tsx`
/// (the phone layout: search, Filters sheet, PDF, Email, cards with a table
/// view). [initialDate] is the web's `?date=` (Daily Closing's Review link)
/// and [focusSaleId] its `?saleId=` (Customer Balances → Open sale).
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key, required this.session, required this.company, this.initialDate, this.focusSaleId});
  final Session session;
  final Company company;
  final String? initialDate;
  final int? focusSaleId;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List<Map> _sales = [], _flocks = [], _customers = [], _accounts = [], _products = [];

  /// Egg classes (341): Unsorted / General plus the farm's sizes.
  List<Map> _classes = [];

  /// The farm's eggs per crate (344).
  int _epc = 30;
  bool _loading = true;

  /// "All": a reversed sale stays in the list (struck through, never totalled)
  /// so it never looks deleted.
  String _status = 'All';
  FarmMoney _money = const FarmMoney();

  final _search = TextEditingController();
  late String _dateFrom = widget.initialDate ?? '';
  late String _dateTo = widget.initialDate ?? '';
  late int? _focusSaleId = widget.focusSaleId;
  SortState _sort = (key: null, dir: null);
  int _page = 1;
  int _perPage = 10;
  bool _table = false;
  bool _emailing = false;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String? get _userId => widget.session.tokens.userId;

  /// Staff are deny-by-default on the web; the phone has no permission flags,
  /// so reversing (a sale or a payment) is offered to everyone but staff.
  bool get _canReverse => (widget.company.role ?? '').toLowerCase() != 'staff';

  /// Edit & repost: a reversed sale that was not corrected yet.
  bool _canRepost(Map row) => isReversedSale(row) && tIntOrNull(row['correctedBySaleId']) == null;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _loadSales();
    _loadFlocks();
    _loadCustomers();
    _loadAccounts();
    _loadProducts();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _uq => {'userId': _userId, 'farmId': _farmId};

  Future<void> _loadSales() async {
    if ((_userId ?? '').isEmpty || _farmId.isEmpty) {
      trackerToast(context, 'Session issue',
          description: 'We could not confirm your farm or user. Please sign in again.', error: true);
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await _api.get('/api/Sale', query: {..._uq, 'includeReversed': 'true'});
      if (mounted) setState(() => _sales = rowsOf(res));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Error', description: e.message.isNotEmpty ? e.message : 'Failed to load sales', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadFlocks() async {
    try {
      final res = await _api.get('/api/Flock', query: _uq);
      if (mounted) setState(() => _flocks = rowsOf(res));
    } on ApiException {
      // As the web: the list simply stays empty.
    }
  }

  Future<void> _loadCustomers() async {
    try {
      final res = await _api.get('/api/Customer', query: _uq);
      if (mounted) setState(() => _customers = rowsOf(res));
    } on ApiException {
      // As the web.
    }
  }

  Future<void> _loadAccounts() async {
    try {
      final res = await _api.get('/api/Poultry/cash-accounts', query: {'farmId': _farmId});
      if (mounted) setState(() => _accounts = [for (final a in rowsOf(res)) if (a['isActive'] == true) a]);
    } on ApiException {
      if (mounted) setState(() => _accounts = []);
    }
  }

  /// A failure leaves no products, which lets every sale through — the stock
  /// check must never be what stops the day's trading.
  Future<void> _loadProducts() async {
    try {
      final res = await _api.get('/api/Poultry/products', query: {'farmId': _farmId});
      if (mounted) setState(() => _products = rowsOf(res));
    } on ApiException {
      if (mounted) setState(() => _products = []);
    }
    try {
      final res = await _api.get('/api/Poultry/egg-sorting/classes', query: {'farmId': _farmId, 'includeInactive': 'false', 'ensure': 'false'});
      if (mounted) setState(() => _classes = rowsOf(res));
    } on ApiException {
      // Before migration 341: no classes, sales stay Unsorted.
      if (mounted) setState(() => _classes = []);
    }
    try {
      final res = await _api.get('/api/Poultry/egg-sorting/settings', query: {'farmId': _farmId});
      final n = res is Map ? tIntOrNull(res['eggsPerCrate']) : null;
      if (mounted && n != null && n > 0) setState(() => _epc = n);
    } on ApiException {
      // Before 344 or offline: keep 30.
    }
  }

  // ------------------------------------------------------------ derived

  String _flockLabel(Object? id) {
    final fid = tIntOrNull(id);
    if (fid == null || fid == 0) return 'All flocks';
    final f = _flocks.where((x) => tIntOrNull(x['flockId']) == fid).firstOrNull;
    return f != null ? '${f['name']}' : '#$fid';
  }

  List<Map> get _rows => toSaleRows(_sales);

  List<Map> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return _rows.where((s) {
      if (_focusSaleId != null) return tIntOrNull(s['saleId']) == _focusSaleId;
      if (q.isNotEmpty) {
        final c = tStr(s['customerName']).toLowerCase().contains(q);
        final p = tStr(s['product']).toLowerCase().contains(q);
        if (!c && !p) return false;
      }
      final k = localDateKey(s['saleDate']);
      if (_dateFrom.isNotEmpty && k.compareTo(_dateFrom) < 0) return false;
      if (_dateTo.isNotEmpty && k.compareTo(_dateTo) > 0) return false;
      if (!matchesStatusFilter(s, paymentStatusOf(s), _status)) return false;
      return true;
    }).toList();
  }

  List<Map> _sorted(List<Map> rows) => sortRows(rows, _sort, (s, k) => switch (k) {
        'saleDate' => DateTime.tryParse(tStr(s['saleDate'])),
        'quantity' => tNum(s['quantity']),
        'unitPrice' => tNum(s['unitPrice']),
        'totalAmount' => tNum(s['totalAmount']),
        'amountPaid' => salePaid(s),
        'balance' => saleOwed(s),
        'paymentStatus' => paymentStatusOf(s),
        _ => s[k],
      });

  void _clearFilters() => setState(() {
        _status = 'Active';
        _search.clear();
        _dateFrom = '';
        _dateTo = '';
        _page = 1;
      });

  // ------------------------------------------------------------ actions

  Future<void> _openForm({SaleCorrection? correcting}) async {
    final saved = await Navigator.of(context).push<SaleSaved>(MaterialPageRoute(
      builder: (_) => SaleFormScreen(
        session: widget.session,
        company: widget.company,
        flocks: _flocks,
        customers: _customers,
        cashAccounts: _accounts,
        products: _products,
        eggClasses: _classes,
        eggsPerCrate: _epc,
        correcting: correcting,
      ),
    ));
    if (saved == null) return;
    await _afterCorrectionSaved(saved, correcting);
    _loadSales();
    _loadProducts();
  }

  /// After a corrected sale is saved on credit: offer the customer's credit.
  Future<void> _afterCorrectionSaved(SaleSaved saved, SaleCorrection? fix) async {
    if (fix == null || saved.saleId == null || saved.paidNow) return;
    final name = saved.customerName.trim().toLowerCase();
    final customer = _customers.where((c) => tStr(c['name'] ?? c['customerName']).trim().toLowerCase() == name).firstOrNull;
    final customerId = tIntOrNull(customer?['customerId'] ?? customer?['id']);
    if (customerId == null) return;
    try {
      final credit = await customerCreditTotal(widget.session, widget.company, customerId);
      if (credit > 0 && mounted) {
        await _applyCredit(ApplyCreditTarget(
          customerId: customerId,
          customerName: saved.customerName,
          saleId: saved.saleId!,
          saleLabel: saved.label,
          outstanding: saved.total,
        ));
      }
    } on ApiException {
      // The credit can still be applied from the sale's Pay dialog.
    }
  }

  Future<void> _applyCredit(ApplyCreditTarget target) async {
    final amount = await showApplyCredit(context, session: widget.session, company: widget.company, target: target);
    if (amount == null || !mounted) return;
    trackerToast(context, 'Credit applied',
        description: '${_money(amount)} of customer credit settled ${target.saleLabel}. No new cash was recorded.');
    _loadSales();
  }

  Future<void> _pay(Map sale) async {
    final outcome = await showRecordPayment(context, session: widget.session, company: widget.company, sale: sale);
    if (outcome == PayOutcome.paid) {
      _loadSales();
    } else if (outcome == PayOutcome.useCredit && mounted) {
      await _applyCredit(ApplyCreditTarget(
        customerId: tIntOrNull(sale['customerId']) ?? 0,
        customerName: tStr(sale['customerName']),
        saleId: tIntOrNull(sale['saleId']) ?? 0,
        saleLabel: tStr(sale['saleGroupNo']).isNotEmpty ? tStr(sale['saleGroupNo']) : '#${sale['saleId']}',
        outstanding: saleOwed(sale),
      ));
    }
  }

  void _history(Map sale) => showPaymentHistory(context,
      session: widget.session,
      company: widget.company,
      partyName: tStr(sale['customerName']).isEmpty ? null : tStr(sale['customerName']),
      documentType: 'Sale',
      documentId: tIntOrNull(sale['saleId']),
      canReverse: _canReverse,
      onReversed: _loadSales);

  void _invoice(Map sale) {
    final multi = multiLines(sale);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SaleInvoiceScreen(
        sale: sale,
        farmName: widget.company.name.isNotEmpty ? widget.company.name : 'Farm Name',
        money: _money,
        flockLabel: _flockLabel(sale['flockId']),
        invoiceNo: multi.isNotEmpty ? tStr(sale['saleGroupNo']) : null,
        eggsPerCrate: _epc,
        // Every sale prints its lines, a one-line sale too, so the egg size is
        // always on the invoice.
        lines: [
          for (final l in saleLinesOf(multi.isNotEmpty ? sale : {...sale, 'lines': null}))
            InvoiceLine(
              label: isEggProductName(l['product']) ? eggClassLabel(_classes, l['eggProductId']) : tStr(l['size']),
              quantity: tNum(l['quantity']),
              unitPrice: tNum(l['unitPrice']),
              totalAmount: tNum(l['totalAmount']),
            ),
        ],
      ),
    ));
  }

  String _lineLabel(Map l) {
    final q = SaleInvoiceScreen.jsQty(tNum(l['quantity']));
    if (!isEggProductName(l['product'])) return '${l['product']} · $q';
    return '${l['product']} · ${eggClassLabel(_classes, l['eggProductId'])} ${eggCrateBreakdown(tNum(l['quantity']), eggsPerCrate: _epc) ?? q}';
  }

  /// 351: view a sale (read-only), and the two ways to fix one.
  Future<void> _view(Map row) async {
    final action = await Navigator.of(context).push<SaleDetailsAction>(MaterialPageRoute(
      builder: (_) => SaleDetailsScreen(
        session: widget.session,
        company: widget.company,
        sale: row,
        flockLabel: _flockLabel(row['flockId']),
        lineLabel: _lineLabel,
        canReverse: _canReverse,
        canRepost: _canRepost(row),
        onNoteSaved: (_) => _loadSales(),
      ),
    ));
    if (!mounted || action == null) return;
    switch (action) {
      case SaleInvoiceAction():
        _invoice(row);
      case SaleReverseAction(:final mode):
        await _reverse(row, mode);
      case SaleRepostAction():
        await _repost(row);
      case SaleShowAction(:final saleId):
        final other = _rows.where((g) => tIntOrNull(g['saleId']) == saleId).firstOrNull;
        if (other != null) {
          setState(() => _status = 'All');
          await _view(other);
        }
    }
  }

  Future<void> _reverse(Map row, String mode) async {
    final label = saleLabel(row);
    final result = await Navigator.of(context).push<SaleReversed>(MaterialPageRoute(
      builder: (_) => ReverseSaleScreen(
        session: widget.session,
        company: widget.company,
        saleId: tIntOrNull(row['saleId']) ?? 0,
        saleLabel: label,
        mode: mode,
      ),
    ));
    if (result == null || !mounted) return;
    final credit = result.creditCreated, cashOut = result.cashReversed;
    trackerToast(context, 'Sale $label reversed',
        description: [
          'Revenue and stock undone.',
          if (credit > 0) '${_money(credit)} kept as customer credit.',
          if (cashOut > 0) '${_money(cashOut)} paid back out of cash.',
        ].join(' '));
    _loadSales();
    _loadProducts();
    if (mode == 'correct') await _openForm(correcting: SaleCorrection(sale: row, creditKept: credit));
  }

  /// Edit & repost: enter a reversed, not yet corrected sale again, pre-filled
  /// and linked to it. The reversed sale itself is never changed.
  Future<void> _repost(Map row) async {
    num credit = 0;
    try {
      final r = await _api.get('/api/Sale/${row['saleId']}/reversal', query: {'farmId': _farmId});
      if (r is Map) {
        final fixedBy = tIntOrNull(r['correctionSaleId']);
        if (fixedBy != null && fixedBy != 0) {
          if (mounted) trackerToast(context, 'Already reposted', description: 'This sale was already corrected by #$fixedBy.');
          _loadSales();
          return;
        }
        credit = tNum(r['creditCreated']);
      }
      // Credit kept at the reversal may have been used or refunded since.
      final cid = tIntOrNull(row['customerId']);
      if (credit > 0 && cid != null && cid != 0) {
        final now = await customerCreditTotal(widget.session, widget.company, cid);
        if (now < credit) credit = now;
      }
    } on ApiException {
      // Open the form anyway; the credit offer re-checks after saving.
    }
    if (mounted) await _openForm(correcting: SaleCorrection(sale: row, creditKept: credit));
  }

  ReportDocument _pdfDoc(List<Map> rows) {
    final counted = rows.where((x) => !isReversedSale(x));
    final total = counted.fold<num>(0, (s, x) => s + tNum(x['totalAmount']));
    final qty = counted.fold<num>(0, (s, x) => s + tNum(x['quantity']));
    final period =
        _dateFrom.isNotEmpty || _dateTo.isNotEmpty ? 'Period: ${_dateFrom.isEmpty ? '—' : _dateFrom} to ${_dateTo.isEmpty ? '—' : _dateTo}' : 'Period: All time';
    return ReportDocument(
      title: 'Sales Report',
      filename: 'sales',
      farmName: widget.company.name,
      subtitle: period,
      sections: [
        ReportSection(
          columns: const [
            ReportColumn('Sale ID'),
            ReportColumn('Date'),
            ReportColumn('Customer'),
            ReportColumn('Product'),
            ReportColumn('Qty', right: true),
            ReportColumn('Unit price', right: true),
            ReportColumn('Total', right: true),
            ReportColumn('Paid', right: true),
            ReportColumn('Balance', right: true),
            ReportColumn('Method'),
            ReportColumn('Status'),
            ReportColumn('Flock'),
          ],
          rows: [
            for (final s in rows)
              [
                '#${s['saleId']}',
                trackerDate(s['saleDate']),
                tStr(s['customerName']),
                tStr(s['product']),
                SaleInvoiceScreen.jsQty(tNum(s['quantity'])),
                _money(tNum(s['unitPrice'])),
                _money(tNum(s['totalAmount'])),
                _money(salePaid(s)),
                _money(saleOwed(s)),
                tStr(s['paymentMethod']),
                paymentStatusOf(s),
                _flockLabel(s['flockId']),
              ],
          ],
          totals: [
            '', '', '', 'TOTALS', loc(qty), '', _money(total),
            _money(rows.fold<num>(0, (a, s) => a + salePaid(s))),
            _money(rows.fold<num>(0, (a, s) => a + saleOwed(s))),
            '', '', '',
          ],
        ),
      ],
      notes: ['Total sales: ${_money(total)}  |  Total quantity: ${loc(qty)}  |  Transactions: ${rows.length}'],
    );
  }

  Future<void> _exportPdf(List<Map> rows) async {
    if (rows.isEmpty) {
      trackerToast(context, 'Nothing to export', description: 'No sales match the current filters.', error: true);
      return;
    }
    try {
      await ReportExport.sharePdf(_pdfDoc(rows));
    } catch (_) {
      if (mounted) trackerToast(context, 'PDF export failed', description: 'Could not generate PDF. Please try again.', error: true);
    }
  }

  Future<void> _email(List<Map> rows) async {
    if (rows.isEmpty) {
      trackerToast(context, 'Nothing to email', description: 'No sales match the current filters.', error: true);
      return;
    }
    final to = (widget.session.tokens.username ?? '').trim();
    if (to.isEmpty || !to.contains('@')) {
      trackerToast(context, 'Email failed',
          description: 'No recipient email found. Sign in with an email address or pass an explicit `to`.', error: true);
      return;
    }
    setState(() => _emailing = true);
    try {
      await ReportExport.email(_api, _pdfDoc(rows), [to]);
      if (mounted) trackerToast(context, 'Report emailed', description: 'Sent to $to.');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Email failed', description: e.message.isNotEmpty ? e.message : 'Could not send report.', error: true);
    }
    if (mounted) setState(() => _emailing = false);
  }

  Future<void> _openFilters() async {
    var from = _dateFrom, to = _dateTo;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final changed = from != _dateFrom || to != _dateTo;
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Filters', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              const Text('Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
              const SizedBox(height: 6),
              AppSelect<String>(
                value: _status,
                items: [for (final (v, l) in saleStatusFilters) AppSelectItem(value: v, label: l)],
                onChanged: (v) {
                  setState(() => _status = v ?? _status);
                  set(() {});
                },
              ),
              const SizedBox(height: 14),
              const Text('Date range', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
              const SizedBox(height: 10),
              FilterLabel('Start date', FilterDate(value: from, hint: 'Start date', onChanged: (v) => set(() => from = v))),
              const SizedBox(height: 12),
              FilterLabel('End date', FilterDate(value: to, hint: 'End date', onChanged: (v) => set(() => to = v))),
              const SizedBox(height: 14),
              const Text('Currency', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
              const SizedBox(height: 6),
              // Read-only: currency is a company setting (Setup > Company).
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: TColors.slate50,
                  border: Border.all(color: TColors.slate200),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  Expanded(child: Text(_money.code, style: const TextStyle(fontSize: 15, color: TColors.slate700))),
                  InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      openAppHref(context, widget.session, widget.company, '/poultry-setup', label: 'Setup');
                    },
                    child: const Text('Change',
                        style: TextStyle(color: TColors.amber700, fontWeight: FontWeight.w500, decoration: TextDecoration.underline)),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () {
                      _clearFilters();
                      Navigator.pop(ctx);
                      trackerToast(context, 'Filters cleared');
                    },
                    child: const Text('Clear all'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: !changed
                        ? null
                        : () {
                            setState(() {
                              _dateFrom = from;
                              _dateTo = to;
                              _page = 1;
                            });
                            Navigator.pop(ctx);
                            trackerToast(context, 'Filters applied', description: 'Sales list updated.');
                          },
                    child: const Text('Apply'),
                  ),
                ),
              ]),
            ]),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/sales');
    final filtered = _filtered;
    final sorted = _sorted(filtered);
    final totalPages = sorted.isEmpty ? 1 : (sorted.length + _perPage - 1) ~/ _perPage;
    final page = _page.clamp(1, totalPages);
    final start = (page - 1) * _perPage;
    final pageRows = sorted.sublist(start.clamp(0, sorted.length), (start + _perPage).clamp(0, sorted.length));
    // A reversed sale is not a sale: it is listed (Reversed / All) but never totalled.
    final counted = filtered.where((x) => !isReversedSale(x));
    final totalSales = counted.fold<num>(0, (s, x) => s + tNum(x['totalAmount']));
    final totalQty = counted.fold<num>(0, (s, x) => s + tNum(x['quantity']));
    final activeCount = [_search.text, _dateFrom, _dateTo].where((v) => v.isNotEmpty).length;

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Sales')),
      body: RefreshIndicator(
        onRefresh: _loadSales,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.shopping_cart_outlined, size: 20, color: Color(0xFF16A34A)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Sales', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
                  Text('Manage your farm sales and transactions', style: TextStyle(fontSize: 13, color: TColors.slate600)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: TColors.blue600, minimumSize: const Size.fromHeight(44)),
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Sale'),
            ),
            const SizedBox(height: 16),
            if (_focusSaleId != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      const TextSpan(text: 'Showing sale '),
                      TextSpan(text: 'S$_focusSaleId', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' only.'),
                    ]), style: const TextStyle(fontSize: 13, color: Color(0xFF0C4A6E))),
                  ),
                  TextButton(onPressed: () => setState(() => _focusSaleId = null), child: const Text('Show all sales')),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            AppInput(
              controller: _search,
              hintText: 'Search customer or product',
              prefixIcon: const Icon(Icons.search, size: 18, color: TColors.slate400),
              onChanged: (_) => setState(() => _page = 1),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: _openFilters,
                  icon: const Icon(Icons.filter_list, size: 18),
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Flexible(child: Text('Filters', overflow: TextOverflow.ellipsis)),
                    if (activeCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFF97316), borderRadius: BorderRadius.circular(999)),
                        child: Text('$activeCount', style: const TextStyle(fontSize: 12, color: Colors.white)),
                      ),
                    ],
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => _exportPdf(filtered),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('PDF'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _emailing ? null : () => _email(filtered),
                icon: _emailing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.mail_outline, size: 18),
                label: const Text('Email'),
              ),
            ]),
            const SizedBox(height: 16),
            _summary(filtered.length, totalSales, totalQty),
            const SizedBox(height: 16),
            if (_loading)
              const TrackerLoading('Loading sales...')
            else if (_sales.isEmpty)
              TCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Column(children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(color: TColors.slate50, shape: BoxShape.circle),
                      child: const Icon(Icons.shopping_cart_outlined, size: 32, color: TColors.slate400),
                    ),
                    const SizedBox(height: 14),
                    const Text('No sales found', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text('Get started by adding your first sale', style: TextStyle(color: TColors.slate600)),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: TColors.blue600),
                      onPressed: () => _openForm(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Your First Sale'),
                    ),
                  ]),
                ),
              )
            else if (filtered.isEmpty)
              TCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Column(children: [
                    const Text('No sales match the current filters.', style: TextStyle(color: TColors.slate600)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _clearFilters, child: const Text('Reset filters')),
                  ]),
                ),
              )
            else
              TCard(
                title: 'Recent Sales',
                description: 'View and manage your sales transactions',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (!_table) ...[
                    for (var i = 0; i < pageRows.length; i++) ...[_card(pageRows[i], i), const SizedBox(height: 10)],
                    ViewTableButton(onPressed: () => setState(() => _table = true)),
                  ] else ...[
                    TableViewBar(text: 'Table • Scroll → for more', onCards: () => setState(() => _table = false)),
                    _tableView(pageRows),
                  ],
                  _pagination(sorted.length, page, totalPages, start),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summary(int count, num total, num qty) {
    Widget card(String title, IconData icon, String value, String sub) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: TColors.slate200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
              Icon(icon, size: 16, color: TColors.slate500),
            ]),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            Text(sub, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        );
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 12) / 2;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(width: w, child: card('Total Sales', Icons.attach_money, _money(total), '$count transactions')),
        SizedBox(
          width: w,
          child: card('Total Quantity', Icons.inventory_2_outlined, loc(qty), eggCrateBreakdown(qty, long: true, eggsPerCrate: _epc) ?? '—'),
        ),
        SizedBox(
          width: w,
          child: card('Average Sale', Icons.trending_up, _money(count > 0 ? total / count : 0), 'per transaction'),
        ),
      ]);
    });
  }

  Widget _statusBadge(Map s) {
    if (isReversedSale(s)) {
      final by = tIntOrNull(s['correctedBySaleId']);
      return TBadge('Reversed${by != null && by != 0 ? ' · corrected by #$by' : ''}', bg: TColors.red100, fg: TColors.red700);
    }
    final st = paymentStatusOf(s);
    final (bg, fg) = switch (st) {
      'Paid' => (TColors.emerald100, TColors.emerald700),
      'Partial' => (TColors.amber100, TColors.amber700),
      _ => (TColors.slate100, TColors.slate700),
    };
    return TBadge(st, bg: bg, fg: fg);
  }

  Widget _card(Map s, int i) {
    final owed = saleOwed(s);
    final striped = i.isEven;
    Widget kv(String l, Widget v) => Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(l, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          DefaultTextStyle.merge(style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), child: v),
        ]);
    Widget action(String label, IconData icon, VoidCallback onTap, {Color? fg, Color? border}) => OutlinedButton.icon(
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
    final reversed = isReversedSale(s);
    final lines = multiLines(s);
    final actions = <Widget>[
      if (!reversed && owed > 0) action('Pay', Icons.account_balance_wallet_outlined, () => _pay(s), fg: TColors.emerald700, border: TColors.emerald200),
      action('View', Icons.visibility_outlined, () => _view(s)),
      action('Invoice', Icons.description_outlined, () => _invoice(s)),
      action('Payments', Icons.history, () => _history(s)),
      if (!reversed) action('Reverse', Icons.undo, () => _reverse(s, 'reverse'), fg: TColors.red600, border: TColors.red200),
      if (_canRepost(s)) action('Edit & repost', Icons.restart_alt, () => _repost(s), fg: const Color(0xFF1D4ED8), border: TColors.blue200),
    ];
    return _SaleCard(
      key: ValueKey('sale-${s['saleId']}'),
      striped: striped,
      header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(saleLabel(s), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          Text(trackerDate(s['saleDate']), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
          const Text('•', style: TextStyle(color: TColors.slate500)),
          Text(tStr(s['customerName']), overflow: TextOverflow.ellipsis, style: const TextStyle(color: TColors.slate600)),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
          Text(_money(tNum(s['totalAmount'])),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TColors.emerald600)),
          Text(tStr(s['product']), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(lineSummary(_classes, lines, _epc), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ],
      ]),
      details: [
        Row(children: [
          Expanded(child: kv('Quantity', Text(SaleInvoiceScreen.jsQty(tNum(s['quantity']))))),
          Expanded(child: kv('Flock', Text(_flockLabel(s['flockId'])))),
        ]),
        Row(children: [
          Expanded(child: kv('Paid', Text(_money(salePaid(s)), style: const TextStyle(color: TColors.emerald700)))),
          Expanded(
            child: kv('Balance',
                Text(_money(owed), style: TextStyle(color: owed > 0 ? TColors.amber700 : TColors.slate400))),
          ),
        ]),
        Row(children: [
          Expanded(child: kv('Method', Text(tStr(s['paymentMethod'])))),
          Expanded(child: kv('Status', _statusBadge(s))),
        ]),
      ],
      // Two per row, as the web's grid-cols-2.
      actions: LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 8) / 2;
        return Wrap(spacing: 8, runSpacing: 8, children: [for (final a in actions) SizedBox(width: w, child: a)]);
      }),
    );
  }

  Widget _tableView(List<Map> rows) {
    IconButton icon(String tip, IconData i, VoidCallback onTap, {Color? color}) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          padding: EdgeInsets.zero,
          icon: Icon(i, size: 18, color: color),
          onPressed: onTap,
        );
    return TrackerTable(
      sort: _sort,
      onSort: (k) => setState(() => _sort = toggleSort(k, _sort)),
      columns: const [
        TCol('Sale ID', sortKey: 'saleId', width: 80),
        TCol('Date', sortKey: 'saleDate', width: 100),
        TCol('Product', sortKey: 'product', width: 110),
        TCol('Customer', sortKey: 'customerName', width: 130),
        TCol('Flock', sortKey: 'flockId', width: 110),
        TCol('Quantity', sortKey: 'quantity', width: 120),
        TCol('Unit Price', sortKey: 'unitPrice', width: 110),
        TCol('Total', sortKey: 'totalAmount', width: 110),
        TCol('Paid', sortKey: 'amountPaid', width: 110),
        TCol('Balance', sortKey: 'balance', width: 110),
        TCol('Method', sortKey: 'paymentMethod', width: 120),
        TCol('Status', sortKey: 'paymentStatus', width: 90),
        TCol('Actions', width: 230),
      ],
      rows: [
        for (final s in rows) _tableRow(s, icon),
      ],
    );
  }

  /// One table row; a reversed sale is struck through and greyed, its Status
  /// and Actions are not.
  List<Widget> _tableRow(Map s, IconButton Function(String, IconData, VoidCallback, {Color? color}) icon) {
    final reversed = isReversedSale(s);
    final lines = multiLines(s);
    const strike = TextStyle(decoration: TextDecoration.lineThrough, color: TColors.slate400);
    Widget t(Widget w) => reversed ? DefaultTextStyle.merge(style: strike, child: w) : w;
    Widget cell(String text, {Color? color, bool bold = false}) => reversed ? Text(text, style: strike) : cellText(text, color: color, bold: bold);
    final qty = tNum(s['quantity']);
    final crates = eggCrateBreakdown(qty, eggsPerCrate: _epc);
    return [
      lines.isNotEmpty
          ? t(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(tStr(s['saleGroupNo']), style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate700)),
              Text('${lines.length} egg lines', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]))
          : cell('#${s['saleId']}', color: TColors.slate500),
      cell(trackerDate(s['saleDate'])),
      t(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(tStr(s['product'])),
        if (lines.isNotEmpty) Text(lineSummary(_classes, lines, _epc), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
      ])),
      cell(tStr(s['customerName'])),
      cell(_flockLabel(s['flockId'])),
      t(Text.rich(TextSpan(children: [
        TextSpan(text: SaleInvoiceScreen.jsQty(qty)),
        if (isEggProductName(s['product']) && crates != null)
          TextSpan(text: ' ($crates)', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
      ]))),
      t(Text.rich(TextSpan(children: [
        TextSpan(text: _money(tNum(s['unitPrice']))),
        if (lines.isNotEmpty) const TextSpan(text: ' avg', style: TextStyle(fontSize: 12, color: TColors.slate500)),
      ]))),
      cell(_money(tNum(s['totalAmount'])), bold: true),
      cell(_money(salePaid(s)), color: TColors.emerald700),
      cell(_money(saleOwed(s)), color: saleOwed(s) > 0 ? TColors.amber700 : TColors.slate400, bold: saleOwed(s) > 0),
      t(TBadge(tStr(s['paymentMethod']), bg: Colors.white, fg: TColors.slate800, border: TColors.slate200)),
      _statusBadge(s),
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (!reversed && saleOwed(s) > 0)
          icon('Record payment · ${_money(saleOwed(s))} owed', Icons.account_balance_wallet_outlined, () => _pay(s), color: TColors.emerald700),
        // Always offered, including on a settled sale.
        icon('Payment history', Icons.history, () => _history(s)),
        icon('View sale · correct or reverse it', Icons.visibility_outlined, () => _view(s)),
        if (!reversed) icon('Reverse sale', Icons.undo, () => _reverse(s, 'reverse'), color: TColors.red600),
        if (_canRepost(s))
          icon('Edit & repost -- enter it again, fixed, as a new sale', Icons.restart_alt, () => _repost(s), color: const Color(0xFF1D4ED8)),
        icon('View invoice', Icons.description_outlined, () => _invoice(s)),
      ]),
    ];
  }

  Widget _pagination(int total, int page, int totalPages, int start) {
    final end = (start + _perPage).clamp(0, total);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: const BoxDecoration(
        color: TColors.slate50,
        border: Border(top: BorderSide(color: TColors.slate200)),
      ),
      child: Column(children: [
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 6, children: [
          Text('Showing ${start + 1} to $end of $total records', style: const TextStyle(fontSize: 13, color: TColors.slate600)),
          SizedBox(
            width: 120,
            child: AppSelect<int>(
              value: _perPage,
              items: [for (final n in salePageSizes) AppSelectItem(value: n, label: '$n / page')],
              onChanged: (v) => setState(() {
                _perPage = v ?? _perPage;
                _page = 1;
              }),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, children: [
          TextButton.icon(
            onPressed: page == 1 ? null : () => setState(() => _page = page - 1),
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Previous'),
          ),
          for (final p in pageNumbers(page, totalPages))
            p == 'ellipsis'
                ? const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('…'))
                : SizedBox(
                    width: 36,
                    height: 36,
                    child: p == page
                        ? OutlinedButton(
                            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                            onPressed: () {},
                            child: Text('$p'),
                          )
                        : TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            onPressed: () => setState(() => _page = p as int),
                            child: Text('$p'),
                          ),
                  ),
          TextButton.icon(
            onPressed: page == totalPages ? null : () => setState(() => _page = page + 1),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('Next'),
          ),
        ]),
      ]),
    );
  }
}

/// One sale card: open by default, amber on even rows as the web stripes them.
class _SaleCard extends StatefulWidget {
  const _SaleCard({super.key, required this.striped, required this.header, required this.details, required this.actions});
  final bool striped;
  final Widget header;
  final List<Widget> details;
  final Widget actions;
  @override
  State<_SaleCard> createState() => _SaleCardState();
}

class _SaleCardState extends State<_SaleCard> {
  bool _open = true;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: widget.striped ? TColors.amber100 : Colors.white,
          border: Border.all(color: widget.striped ? TColors.amber300 : TColors.slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: widget.header),
              Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: TColors.slate400),
            ]),
          ),
          if (_open) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: TColors.slate100),
            const SizedBox(height: 12),
            for (final d in widget.details) ...[d, const SizedBox(height: 6)],
            const SizedBox(height: 6),
            widget.actions,
          ],
        ]),
      );
}

/// Opens `/sales` links natively, keeping `?date=` and `?saleId=`.
Widget? salesScreenForHref(String href, Session s, Company c) {
  final uri = Uri.tryParse(href);
  if (uri == null || uri.path != '/sales') return null;
  final d = toBusinessDate(uri.queryParameters['date']);
  final id = int.tryParse(uri.queryParameters['saleId'] ?? '');
  return SalesScreen(session: s, company: c, initialDate: d, focusSaleId: id != null && id > 0 ? id : null);
}
