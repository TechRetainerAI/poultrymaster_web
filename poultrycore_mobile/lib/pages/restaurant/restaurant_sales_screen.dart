// Restaurant → Sales → Sales, as `app/restaurant-sales/page.tsx` on the shared
// `components/sales/module-sales-view.tsx`: every order that was not
// cancelled, as money — total, paid, balance, Paid / Partial / Pending — with
// search, the Filters sheet, PDF, Email, the four cards, phone cards with
// "View table format", and Pay / Edit / Invoice / Payments / Delete. Add Sale
// opens the POS; Pay settles a pay-later order (migration 333).

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/reports/poultry_report_screen.dart' show defaultEmailRecipient;
import '../poultry/reports/report_export.dart';
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager, LoadingLine, RecordPaymentScreen;
import '../poultry/sales/sale_dialogs.dart' show showPaymentHistory;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart' show isoDay;
import 'restaurant_expenses_screen.dart' show fmtShortDate;
import 'restaurant_money_kit.dart';
import 'restaurant_roles.dart' show restaurantRose;

num orderPaid(Map o) => tNum(o['paidAmount']);
num orderOwed(Map o) {
  final v = tNum(o['totalAmount']) - orderPaid(o);
  return v > 0 ? v : 0;
}

String orderTypeLabel(Map o) =>
    (tStr(o['orderType']).isEmpty ? 'Order' : tStr(o['orderType'])).replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');

/// A completed order that is still owed can only be a pay-later order, which is what Pay settles.
bool isPayLaterOrder(Map o) => o['status'] == 'Completed' && tIntOrNull(o['customerId']) != null && orderOwed(o) > 0;

/// saleStatusOf: Paid / Partial / Pending from the amounts.
String saleStatusOf(num total, num paid) {
  if (total > 0 && paid >= total - 0.005) return 'Paid';
  if (paid > 0) return 'Partial';
  return total <= 0 ? 'Paid' : 'Pending';
}

/// The order as the sales view shows it (`toRow`).
({String reference, String date, String customer, String product, num quantity, num total, num paid, num balance, String? method, String status})
    orderSaleRow(Map o) => (
          reference: tStr(o['orderNumber']),
          date: tStr(o['createdAt']),
          customer: tStr(o['customerName']).isNotEmpty
              ? tStr(o['customerName'])
              : tStr(o['tableNumber']).isNotEmpty
                  ? 'Table ${tStr(o['tableNumber'])}'
                  : 'Walk-in',
          product: '${orderTypeLabel(o)} · ${tNum(o['itemCount']).toInt()} item${tNum(o['itemCount']) == 1 ? '' : 's'}',
          quantity: tNum(o['itemCount']),
          total: tNum(o['totalAmount']),
          paid: orderPaid(o),
          balance: orderOwed(o),
          method: tStr(o['guestPaymentIntent']).isEmpty ? null : tStr(o['guestPaymentIntent']),
          status: saleStatusOf(tNum(o['totalAmount']), orderPaid(o)),
        );

/// The sales view's filters: date, the two selects, and the search.
List<Map> filterOrderSales(List<Map> orders, {String from = '', String to = '', String type = 'all', String status = 'all', String search = ''}) {
  final q = search.trim().toLowerCase();
  return [
    for (final o in orders)
      if (() {
        final r = orderSaleRow(o);
        final d = _localDay(r.date);
        if (from.isNotEmpty && d.compareTo(from) < 0) return false;
        if (to.isNotEmpty && d.compareTo(to) > 0) return false;
        if (type != 'all' && tStr(o['orderType']).replaceAll(RegExp(r'[\s-]'), '').toLowerCase() != type.toLowerCase()) return false;
        if (status != 'all' && r.status != status) return false;
        if (q.isNotEmpty && ![r.customer, r.reference, r.product].any((v) => v.toLowerCase().contains(q))) return false;
        return true;
      }())
        o,
  ];
}

/// The order's day: its instant on this phone's calendar, as the web's Date does.
String _localDay(String instant) {
  final t = DateTime.tryParse(instant);
  if (t == null) return instant.length >= 10 ? instant.substring(0, 10) : instant;
  return isoDay(t.isUtc ? t.toLocal() : t);
}

String _shortDate(String instant) => fmtShortDate(_localDay(instant));

const _statusCls = {
  'Paid': (TColors.emerald100, TColors.emerald700),
  'Partial': (TColors.amber100, TColors.amber700),
  'Pending': (TColors.slate100, TColors.slate700),
};
Widget saleStatusBadge(String s) {
  final (bg, fg) = _statusCls[s] ?? (TColors.slate100, TColors.slate700);
  return rStatusBadge(s, bg: bg, fg: fg, border: bg);
}

class RestaurantSalesScreen extends StatefulWidget {
  const RestaurantSalesScreen({super.key, required this.session, required this.company, this.focusOrderId});
  final Session session;
  final Company company;

  /// `?orderId=` (from the balance pages): one order only.
  final int? focusOrderId;

  @override
  State<RestaurantSalesScreen> createState() => _RestaurantSalesScreenState();
}

class _RestaurantSalesScreenState extends State<RestaurantSalesScreen> {
  List<Map> _orders = [];
  List<Map> _accounts = [];
  bool _loading = true;
  bool _emailing = false;
  late int? _focus = widget.focusOrderId;
  final _search = TextEditingController();
  String _from = '', _to = '', _type = 'all', _status = 'all';
  int _page = 1, _pageSize = 10;
  bool _table = false;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  /// restaurant.customer-payments.create / .reverse on the web; Staff are refused here.
  bool get _can => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    _loadAccounts();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The server compares createdAt <= toDate, so the end of that day is sent.
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get('/api/Restaurant/orders', query: {
        '_': '1',
        if (_from.isNotEmpty) 'fromDate': _from,
        if (_to.isNotEmpty) 'toDate': '${_to}T23:59:59',
        'farmId': _farmId,
      });
      if (mounted) setState(() => _orders = [for (final o in rowsOf(res)) if (o['status'] != 'Cancelled') o]);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Error', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// loadRestaurantCashAccounts.
  Future<void> _loadAccounts() async {
    try {
      final list = await loadRestaurantAccounts(_api, _farmId);
      if (!mounted) return;
      setState(() => _accounts = [
            for (final a in list)
              if (a['isActive'] == true)
                {'id': a['cashAccountId'], 'name': a['name'], 'currentBalance': a['currentBalance'], 'allowNegativeBalance': a['allowNegative']},
          ]);
    } on ApiException {
      if (mounted) setState(() => _accounts = []);
    }
  }

  void _go(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  Future<void> _pay(Map o) async {
    final r = orderSaleRow(o);
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RecordPaymentScreen(
        session: widget.session,
        company: widget.company,
        api: '/api/Restaurant',
        sourceType: 'SaleEntry',
        cashAccounts: _accounts,
        party: {
          'partyId': tIntOrNull(o['customerId']) ?? 0,
          'partyName': tStr(o['customerName']),
          'paymentTermsDays': 0,
          'totalBalance': r.balance,
          'openDocumentCount': 1,
          'overdueAmount': 0,
          'totalInvoiced': r.total,
          'totalPaid': r.paid,
        },
        single: {
          'documentType': 'Order',
          'documentId': tIntOrNull(o['orderId']),
          'reference': r.reference,
          'documentDate': r.date,
          'label': orderTypeLabel(o),
          'totalAmount': r.total,
          'amountPaid': r.paid,
          'balance': r.balance,
          'dueDate': null,
          'ageDays': 0,
          'status': r.paid > 0 ? 'Partially Paid' : 'Unpaid',
          'isOverdue': false,
        },
      ),
    ));
    if (ok == true) _load();
  }

  void _payments(Map o) => showPaymentHistory(
        context,
        session: widget.session,
        company: widget.company,
        partyName: tStr(o['customerName']).isEmpty ? null : tStr(o['customerName']),
        documentType: 'Order',
        documentId: tIntOrNull(o['orderId']),
        canReverse: _can,
        onReversed: _load,
        api: '/api/Restaurant',
      );

  /// Poultry's Delete: the order is cancelled; one with money paid is refused.
  Future<void> _delete(Map o) async {
    final ref = tStr(o['orderNumber']).isNotEmpty ? tStr(o['orderNumber']) : '${o['orderId']}';
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => RConfirmDialog(
        title: 'Delete sale?',
        description:
            "Order $ref will be cancelled. An order with money paid on it can't be deleted: reverse the payments (Payments button) or refund it on Orders first.",
        confirmLabel: 'Delete',
        errorTitle: 'Could not delete',
        onConfirm: () => _api.patch('/api/Restaurant/orders/${tIntOrNull(o['orderId'])}/status?farmId=${Uri.encodeQueryComponent(_farmId)}',
            body: {'status': 'Cancelled', 'reason': 'Deleted from Sales'}),
      ),
    );
    if (done == true) {
      if (mounted) trackerToast(context, 'Sale deleted', description: 'Order $ref was cancelled.');
      _load();
    }
  }

  void _edit(Map o) => _go('/restaurant-orders?orderId=${o['orderId']}', 'Orders');

  Future<void> _invoice(Map o) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _InvoiceScreen(session: widget.session, company: widget.company, order: o, fmt: _gh),
      ));

  ReportDocument _pdfDoc(List<Map> rows) {
    final rs = [for (final o in rows) orderSaleRow(o)];
    final total = rs.fold<num>(0, (s, r) => s + r.total);
    final qty = rs.fold<num>(0, (s, r) => s + r.quantity);
    return ReportDocument(
      title: 'Restaurant Sales',
      filename: 'restaurant-sales',
      farmName: widget.company.name,
      fromDate: _from.isEmpty ? null : _from,
      toDate: _to.isEmpty ? null : _to,
      landscape: true,
      rose: true,
      sections: [
        ReportSection(
          columns: const [
            ReportColumn('Sale ID'), ReportColumn('Date'), ReportColumn('Sale'), ReportColumn('Customer'),
            ReportColumn('Total Items', right: true), ReportColumn('Total', right: true), ReportColumn('Paid', right: true),
            ReportColumn('Balance', right: true), ReportColumn('Method'), ReportColumn('Status'),
          ],
          rows: [
            for (final r in rs)
              [r.reference, _shortDate(r.date), r.product, r.customer, '${r.quantity.toInt()}', _gh(r.total), _gh(r.paid), _gh(r.balance), r.method ?? '', r.status],
          ],
          totals: ['', '', '', 'TOTALS', '${qty.toInt()}', _gh(total), _gh(rs.fold<num>(0, (s, r) => s + r.paid)), _gh(rs.fold<num>(0, (s, r) => s + r.balance)), '', ''],
        ),
      ],
      notes: ['Total sales: ${_gh(total)}  |  Total Items: ${qty.toInt()}  |  Transactions: ${rows.length}'],
    );
  }

  Future<void> _exportPdf(List<Map> rows) async {
    if (rows.isEmpty) return trackerToast(context, 'Nothing to export', description: 'No sales match the current filters.', error: true);
    try {
      await ReportExport.sharePdf(_pdfDoc(rows));
    } catch (_) {
      if (mounted) trackerToast(context, 'PDF export failed', description: 'Could not generate PDF. Please try again.', error: true);
    }
  }

  Future<void> _email(List<Map> rows) async {
    if (rows.isEmpty) return trackerToast(context, 'Nothing to email', description: 'No sales match the current filters.', error: true);
    final to = defaultEmailRecipient(widget.session, widget.company);
    if (!to.contains('@')) return trackerToast(context, 'Email failed', description: 'Could not send report.', error: true);
    setState(() => _emailing = true);
    try {
      await ReportExport.email(_api, _pdfDoc(rows), [to]);
      if (mounted) trackerToast(context, 'Report emailed', description: 'Sent to $to.');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Email failed', description: e.message.isNotEmpty ? e.message : 'Could not send report.', error: true);
    }
    if (mounted) setState(() => _emailing = false);
  }

  int get _activeCount => [_search.text, _from, _to, _type != 'all' ? 'x' : '', _status != 'all' ? 'x' : ''].where((x) => x.isNotEmpty).length;

  void _clear() {
    final reload = _from.isNotEmpty || _to.isNotEmpty;
    setState(() {
      _search.clear();
      _from = '';
      _to = '';
      _type = 'all';
      _status = 'all';
      _page = 1;
    });
    if (reload) _load();
  }

  Future<void> _filters() async {
    var from = _from, to = _to, type = _type, status = _status;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Filters', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              const Text('Date range', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
              const SizedBox(height: 10),
              rField('Start date', rDateInput(from, (v) => set(() => from = v))),
              const SizedBox(height: 12),
              rField('End date', rDateInput(to, (v) => set(() => to = v))),
              const SizedBox(height: 14),
              rField(
                'Order type',
                AppSelect<String>(
                  value: type,
                  items: const [
                    AppSelectItem(value: 'all', label: 'All types'),
                    AppSelectItem(value: 'DineIn', label: 'Dine in'),
                    AppSelectItem(value: 'Takeaway', label: 'Takeaway'),
                    AppSelectItem(value: 'Delivery', label: 'Delivery'),
                  ],
                  onChanged: (v) => set(() => type = v ?? 'all'),
                ),
              ),
              const SizedBox(height: 12),
              rField(
                'Status',
                AppSelect<String>(
                  value: status,
                  items: const [
                    AppSelectItem(value: 'all', label: 'All statuses'),
                    AppSelectItem(value: 'Paid', label: 'Paid'),
                    AppSelectItem(value: 'Partial', label: 'Partial'),
                    AppSelectItem(value: 'Pending', label: 'Pending'),
                  ],
                  onChanged: (v) => set(() => status = v ?? 'all'),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () {
                      _clear();
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
                    onPressed: () {
                      final reload = from != _from || to != _to;
                      setState(() {
                        _from = from;
                        _to = to;
                        _type = type;
                        _status = status;
                        _page = 1;
                      });
                      Navigator.pop(ctx);
                      if (reload) _load();
                    },
                    child: const Text('Apply'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-sales');
    final items = _focus != null ? [for (final o in _orders) if (tIntOrNull(o['orderId']) == _focus) o] : _orders;
    final filtered = filterOrderSales(items, from: _from, to: _to, type: _type, status: _status, search: _search.text);
    final rows = [for (final o in filtered) orderSaleRow(o)];
    final totalSales = rows.fold<num>(0, (s, r) => s + r.total);
    final totalQty = rows.fold<num>(0, (s, r) => s + r.quantity);
    final totalOwed = rows.fold<num>(0, (s, r) => s + r.balance);
    if ((_page - 1) * _pageSize >= filtered.length && _page > 1) _page = 1;
    final pageItems = pageSlice(filtered, _page, _pageSize);

    Widget card(String title, IconData icon, String value, String hint, {Color? color}) => TCard(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
              Icon(icon, size: 16, color: TColors.slate400),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color ?? TColors.slate900)),
            ),
            Text(hint, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          ]),
        );

    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Sales')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: const Color(0xFFFFE4E6), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.shopping_cart_outlined, size: 20, color: Color(0xFFE11D48)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sales', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: TColors.slate900)),
                Text('Every order as a sale: what was paid and what is still owed', style: TextStyle(fontSize: 13, color: TColors.slate600)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: restaurantRose, minimumSize: const Size.fromHeight(44)),
            onPressed: () => _go('/restaurant-pos', 'POS / New Order'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Sale'),
          ),
          if (_focus != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: TColors.rose50, border: Border.all(color: TColors.rose200), borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                const Expanded(child: Text('Showing one order.', style: TextStyle(fontSize: 13, color: Color(0xFF881337)))),
                InkWell(
                  onTap: () => setState(() => _focus = null),
                  child: const Text('Show all sales', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.rose700)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          AppInput(
            controller: _search,
            hintText: 'Search customer, order or type',
            prefixIcon: const Icon(Icons.search, size: 18),
            onChanged: (_) => setState(() => _page = 1),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: _filters,
              icon: const Icon(Icons.filter_list, size: 16),
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Filters'),
                if (_activeCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(color: const Color(0xFFF97316), borderRadius: BorderRadius.circular(999)),
                    child: Text('$_activeCount', style: const TextStyle(fontSize: 12, color: Colors.white)),
                  ),
                ],
              ]),
            ),
            OutlinedButton.icon(onPressed: () => _exportPdf(filtered), icon: const Icon(Icons.download, size: 16), label: const Text('PDF')),
            OutlinedButton.icon(
              onPressed: _emailing ? null : () => _email(filtered),
              icon: _emailing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.mail_outline, size: 16),
              label: const Text('Email'),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: card('Total Sales', Icons.attach_money, _gh(totalSales), '${filtered.length} transactions')),
            const SizedBox(width: 10),
            Expanded(child: card('Total Items', Icons.inventory_2_outlined, '${totalQty.toInt()}', 'items sold')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: card('Average Sale', Icons.trending_up, _gh(filtered.isEmpty ? 0 : totalSales / filtered.length), 'per transaction')),
            const SizedBox(width: 10),
            Expanded(
                child: card('Balance', Icons.account_balance_wallet_outlined, _gh(totalOwed), 'still owed',
                    color: totalOwed > 0 ? TColors.amber700 : null)),
          ]),
          const SizedBox(height: 14),
          if (_loading)
            const TCard(child: Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: LoadingLine('Loading…'))))
          else if (items.isEmpty)
            const TCard(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Column(children: [
                  Icon(Icons.shopping_cart_outlined, size: 40, color: TColors.slate400),
                  SizedBox(height: 12),
                  Text('No sales found', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TColors.slate900)),
                  SizedBox(height: 6),
                  Text('Orders taken at the POS or online appear here.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate600)),
                ]),
              ),
            )
          else if (filtered.isEmpty)
            TCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Column(children: [
                  const Text('No sales match the current filters.', style: TextStyle(color: TColors.slate600)),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: _clear, child: const Text('Reset filters')),
                ]),
              ),
            )
          else
            TCard(
              title: 'Recent Sales',
              description: 'View and manage your sales transactions',
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_table) ...[
                  Row(children: [
                    const Expanded(child: Text('Table • Scroll → for more', style: TextStyle(fontSize: 12, color: TColors.slate600))),
                    TextButton.icon(
                        onPressed: () => setState(() => _table = false), icon: const Icon(Icons.keyboard_arrow_up, size: 16), label: const Text('Cards')),
                  ]),
                  _tableView(pageItems),
                ] else ...[
                  for (final (i, o) in pageItems.indexed) _SaleCard(key: ValueKey(o['orderId']), striped: i.isEven, actions: _cardActions(o), order: o, fmt: _gh),
                  TextButton.icon(
                    onPressed: () => setState(() => _table = true),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                    label: const Text('View table format'),
                    style: TextButton.styleFrom(foregroundColor: TColors.slate600, minimumSize: const Size.fromHeight(40)),
                  ),
                ],
                CompactPager(
                  total: filtered.length,
                  page: _page,
                  pageSize: _pageSize,
                  onPage: (p) => setState(() => _page = p),
                  onPageSize: (v) => setState(() {
                    _pageSize = v;
                    _page = 1;
                  }),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  /// Poultry's order: Pay, Edit, Invoice, Payments, Delete.
  List<Widget> _cardActions(Map o) {
    Widget b(String label, IconData icon, VoidCallback on, {Color? color}) => OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: color == null ? null : BorderSide(color: color.withValues(alpha: .35)),
            minimumSize: const Size.fromHeight(40),
          ),
          onPressed: on,
          icon: Icon(icon, size: 16),
          label: Text(label),
        );
    const green = TColors.emerald700;
    return [
      if (isPayLaterOrder(o) && _can) b('Pay', Icons.account_balance_wallet_outlined, () => _pay(o), color: green),
      if (!isPayLaterOrder(o) && o['status'] != 'Completed' && orderOwed(o) > 0)
        b('Pay at till', Icons.account_balance_wallet_outlined, () => _go('/restaurant-orders', 'Orders'), color: green),
      b('Edit', Icons.edit_outlined, () => _edit(o)),
      b('Invoice', Icons.description_outlined, () => _invoice(o)),
      b('Payments', Icons.history, () => _payments(o)),
      b('Delete', Icons.delete_outline, () => _delete(o), color: TColors.red600),
    ];
  }

  Widget _tableView(List<Map> items) => TrackerTable(
        columns: const [
          TCol('Sale ID', width: 100), TCol('Date', width: 120), TCol('Sale', width: 160), TCol('Customer', width: 130),
          TCol('Items', right: true, width: 70), TCol('Total', right: true, width: 110), TCol('Paid', right: true, width: 110),
          TCol('Balance', right: true, width: 110), TCol('Method', width: 100), TCol('Status', width: 90), TCol('Actions', width: 230),
        ],
        rows: [
          for (final o in items)
            () {
              final r = orderSaleRow(o);
              return [
                cellText(r.reference, color: TColors.slate500),
                cellText(_shortDate(r.date)),
                cellText(r.product),
                cellText(r.customer),
                cellText('${r.quantity.toInt()}'),
                cellText(_gh(r.total), bold: true),
                cellText(_gh(r.paid), color: TColors.emerald700),
                cellText(_gh(r.balance), color: r.balance > 0 ? TColors.amber700 : TColors.slate400, bold: r.balance > 0),
                r.method == null ? cellText('—') : Align(alignment: Alignment.centerLeft, child: rStatusBadge(r.method!)),
                Align(alignment: Alignment.centerLeft, child: saleStatusBadge(r.status)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isPayLaterOrder(o) && _can)
                    IconButton(
                        tooltip: 'Record payment · ${_gh(orderOwed(o))} owed',
                        icon: const Icon(Icons.account_balance_wallet_outlined, size: 18, color: TColors.emerald700),
                        onPressed: () => _pay(o)),
                  IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(o)),
                  IconButton(tooltip: 'Invoice', icon: const Icon(Icons.description_outlined, size: 18), onPressed: () => _invoice(o)),
                  IconButton(tooltip: 'Payment history', icon: const Icon(Icons.history, size: 18), onPressed: () => _payments(o)),
                  IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600), onPressed: () => _delete(o)),
                ]),
              ];
            }(),
        ],
      );
}

/// One expandable sale card: reference, date and customer; the total in green
/// and what was sold; then the figures and the buttons, two to a row.
class _SaleCard extends StatefulWidget {
  const _SaleCard({super.key, required this.order, required this.fmt, required this.actions, required this.striped});
  final Map order;
  final FarmMoney fmt;
  final List<Widget> actions;
  final bool striped;
  @override
  State<_SaleCard> createState() => _SaleCardState();
}

class _SaleCardState extends State<_SaleCard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final r = orderSaleRow(o);
    final gh = widget.fmt;
    Widget kv(String k, Widget v) => Row(children: [
          Text('$k ', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          Flexible(child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), child: v)),
        ]);
    final details = [
      kv('Items', Text('${r.quantity.toInt()}')),
      kv('Type', Text(orderTypeLabel(o))),
      kv('Order', Text(tStr(o['status']))),
      if (tStr(o['onlineSource']).isNotEmpty) kv('Source', Text('Online · ${tStr(o['onlineSource'])}')),
      if (tStr(o['tableNumber']).isNotEmpty) kv('Table', Text(tStr(o['tableNumber']))),
      kv('Paid', Text(gh(r.paid), style: const TextStyle(color: TColors.emerald700))),
      kv('Balance', Text(gh(r.balance), style: TextStyle(color: r.balance > 0 ? TColors.amber700 : TColors.slate400))),
      kv('Method', Text(r.method ?? '—')),
      kv('Status', saleStatusBadge(r.status)),
    ];
    Widget pairs(List<Widget> ws, double gap) => Column(children: [
          for (var i = 0; i < ws.length; i += 2) ...[
            if (i > 0) SizedBox(height: gap),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: ws[i]),
              const SizedBox(width: 8),
              Expanded(child: i + 1 < ws.length ? ws[i + 1] : const SizedBox()),
            ]),
          ],
        ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(r.reference, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  Text(_shortDate(r.date), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
                  const Text('•', style: TextStyle(color: TColors.slate500)),
                  Text(r.customer, style: const TextStyle(color: TColors.slate600)),
                ]),
                const SizedBox(height: 4),
                Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(gh(r.total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: TColors.emerald600)),
                  Text(r.product, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
              ]),
            ),
            Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: TColors.slate400),
          ]),
        ),
        if (_open) ...[
          const Divider(height: 24, color: TColors.slate100),
          pairs(details, 8),
          const SizedBox(height: 12),
          pairs(widget.actions, 8),
        ],
      ]),
    );
  }
}

/// The Invoice dialog, as a page: the order's lines (voided and cancelled ones
/// left out), the total, paid and balance due; Print shares the PDF.
class _InvoiceScreen extends StatefulWidget {
  const _InvoiceScreen({required this.session, required this.company, required this.order, required this.fmt});
  final Session session;
  final Company company;
  final Map order;
  final FarmMoney fmt;
  @override
  State<_InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<_InvoiceScreen> {
  List<({String description, num quantity, num unitPrice, num total})>? _lines;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = orderSaleRow(widget.order);
    final fallback = [(description: r.product, quantity: 1 as num, unitPrice: r.total, total: r.total)];
    try {
      final items = rowsOf(await widget.session.farmClient
          .get('/api/Restaurant/orders/${tIntOrNull(widget.order['orderId'])}/items', query: {'farmId': widget.company.farmId}));
      final lines = [
        for (final i in items)
          if (i['status'] != 'Voided' && i['status'] != 'Cancelled')
            (
              description: tStr(i['itemName']),
              quantity: tNum(i['quantity']),
              unitPrice: tNum(i['unitPrice']) + tNum(i['modifierTotal']),
              total: tNum(i['lineTotal']),
            ),
      ];
      if (mounted) setState(() => _lines = lines.isEmpty ? fallback : lines);
    } on ApiException {
      if (mounted) setState(() => _lines = fallback);
    }
  }

  String _q(num n) => n == n.roundToDouble() ? n.toInt().toString() : '$n';

  Future<void> _print() async {
    final r = orderSaleRow(widget.order);
    final gh = widget.fmt;
    await ReportExport.sharePdf(ReportDocument(
      title: 'Invoice ${r.reference}',
      filename: 'invoice-${r.reference}',
      farmName: widget.company.name,
      subtitle: 'Bill to: ${r.customer} · ${_shortDate(r.date)}',
      rose: true,
      landscape: false,
      sections: [
        ReportSection(
          columns: const [ReportColumn('Description'), ReportColumn('Qty', right: true), ReportColumn('Unit price', right: true), ReportColumn('Amount', right: true)],
          rows: [for (final l in _lines!) [l.description, _q(l.quantity), gh(l.unitPrice), gh(l.total)]],
          totals: ['', '', 'Total', gh(r.total)],
        ),
      ],
      notes: ['Paid: ${gh(r.paid)}', 'Balance due: ${gh(r.balance)}'],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = orderSaleRow(widget.order);
    final gh = widget.fmt;
    const sm = TextStyle(fontSize: 12, color: TColors.slate500);
    Widget totalRow(String k, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(k, textAlign: TextAlign.right, style: TextStyle(color: bold ? TColors.slate900 : TColors.slate500, fontWeight: bold ? FontWeight.w600 : null))),
            const SizedBox(width: 16),
            SizedBox(width: 110, child: Text(v, textAlign: TextAlign.right, style: TextStyle(fontWeight: bold ? FontWeight.w600 : null))),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Review the invoice and print or save a PDF for your customer.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.company.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Text('Invoice', style: sm),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(r.reference, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(_shortDate(r.date), style: sm),
          ]),
        ]),
        const SizedBox(height: 10),
        Text.rich(TextSpan(children: [
          const TextSpan(text: 'Bill to: ', style: TextStyle(color: TColors.slate500)),
          TextSpan(text: r.customer, style: const TextStyle(fontWeight: FontWeight.w500)),
        ])),
        const SizedBox(height: 10),
        if (_lines == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: LoadingLine('Loading…'))
        else ...[
          TrackerTable(
            columns: const [TCol('Description', width: 160), TCol('Qty', right: true, width: 60), TCol('Unit price', right: true, width: 100), TCol('Amount', right: true, width: 100)],
            rows: [for (final l in _lines!) [cellText(l.description), cellText(_q(l.quantity)), cellText(gh(l.unitPrice)), cellText(gh(l.total))]],
          ),
          const SizedBox(height: 8),
          totalRow('Total', gh(r.total), bold: true),
          totalRow('Paid', gh(r.paid)),
          totalRow('Balance due', gh(r.balance), bold: true),
        ],
        const SizedBox(height: 16),
        Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: restaurantRose),
            onPressed: _lines == null ? null : _print,
            icon: const Icon(Icons.print_outlined, size: 16),
            label: const Text('Print'),
          ),
        ]),
      ]),
    );
  }
}
