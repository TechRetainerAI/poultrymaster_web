// Hotel → Sales, Expenses & Money → Sales, as `app/hotel-sales/page.tsx` on the
// shared `components/sales/module-sales-view.tsx` (the same view as Restaurant
// Sales): each stay (room nights plus everything charged to the folio) and each
// walk-in restaurant order, as money — total, paid, balance, Paid / Partial /
// Pending — with search, the Filters sheet (dates, sale type, status), PDF,
// Email, the four cards, phone cards with "View table format", and per row
// Pay, Edit, Invoice, Payments, Bill to account and Delete. Migration 332.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/form_dialog.dart';
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
import '../restaurant/restaurant_expenses_screen.dart' show fmtShortDate;
import '../restaurant/restaurant_money_kit.dart' show rDateInput, rField, rStatusBadge;
import '../restaurant/restaurant_sales_screen.dart' show saleStatusBadge, saleStatusOf;
import '../shared/business_dates.dart' show isoDay;
import 'hotel_kit.dart';

/// The balances prefix for Hotel (lib/api/balances.ts: "/Hotel/balances").
const hotelBalancesApi = '/api/Hotel/balances';

typedef HotelSaleView = ({
  String reference,
  String date,
  String customer,
  String product,
  num? nights,
  num total,
  num paid,
  num balance,
  String? method,
  String status,
  List<(String, String)> details,
});

bool _isStay(Map s) => s['documentType'] == 'Stay';

/// `toRow`: the sale as the shared view shows it.
HotelSaleView hotelSaleRow(Map s) {
  final total = tNum(s['totalAmount']), paid = tNum(s['amountPaid']);
  final ps = tStr(s['paymentStatus']);
  return (
    reference: tStr(s['reference']).isNotEmpty ? tStr(s['reference']) : '#${s['documentId']}',
    date: tStr(s['docDate']),
    customer: tStr(s['partyName']),
    product: tStr(s['label']).isNotEmpty ? tStr(s['label']) : (_isStay(s) ? 'Stay' : 'Restaurant order'),
    nights: s['nights'] == null ? null : tNum(s['nights']),
    total: total,
    paid: paid,
    balance: tNum(s['balance']),
    method: tStr(s['paymentMethod']).isEmpty ? null : tStr(s['paymentMethod']),
    status: const ['Paid', 'Partial', 'Pending'].contains(ps) ? ps : saleStatusOf(total, paid),
    details: [
      ('Type', _isStay(s) ? 'Stay' : 'Restaurant'),
      if (tStr(s['roomNumber']).isNotEmpty) ('Room', tStr(s['roomNumber'])),
      if (tStr(s['bookingStatus']).isNotEmpty) ('Booking', tStr(s['bookingStatus'])),
      if (s['billedToAccount'] == true) ('Billed to', 'Account'),
    ],
  );
}

String _day(String instant) {
  final t = DateTime.tryParse(instant);
  if (t == null) return instant.length >= 10 ? instant.substring(0, 10) : instant;
  return isoDay(t.isUtc ? t.toLocal() : t);
}

String _short(String instant) => fmtShortDate(_day(instant));

/// The view's filters: the date range, Sale type, Status, then the search.
List<Map> filterHotelSales(
  List<Map> rows, {
  String from = '',
  String to = '',
  String type = 'all',
  String status = 'all',
  String search = '',
}) {
  final q = search.trim().toLowerCase();
  return [
    for (final s in rows)
      if (() {
        final r = hotelSaleRow(s);
        final d = _day(r.date);
        if (from.isNotEmpty && d.compareTo(from) < 0) return false;
        if (to.isNotEmpty && d.compareTo(to) > 0) return false;
        if (type != 'all' && s['documentType'] != type) return false;
        if (status != 'all' && s['paymentStatus'] != status) return false;
        if (q.isNotEmpty && ![r.customer, r.reference, r.product].any((v) => v.toLowerCase().contains(q))) return false;
        return true;
      }())
        s,
  ];
}

class HotelSalesScreen extends StatefulWidget {
  const HotelSalesScreen({super.key, required this.session, required this.company, this.focusBookingId});
  final Session session;
  final Company company;

  /// `?bookingId=` (from the balance pages): that one stay.
  final int? focusBookingId;

  @override
  State<HotelSalesScreen> createState() => _HotelSalesScreenState();
}

class _HotelSalesScreenState extends State<HotelSalesScreen> {
  List<Map> _sales = [];
  List<Map> _accounts = [], _customers = [];
  bool _loading = true, _emailing = false, _table = false;
  late int? _focus = widget.focusBookingId;
  final _search = TextEditingController();
  String _from = '', _to = '', _type = 'all', _status = 'all';
  int _page = 1, _pageSize = 10;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  /// hotel.customer-payments.create / .reverse on the web; Staff are refused here.
  bool get _can => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    _loadSide();
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
      final res = await _api.get(
        '/api/Hotel/sales',
        query: {'farmId': _farmId, if (_from.isNotEmpty) 'from': _from, if (_to.isNotEmpty) 'to': _to},
      );
      if (mounted) setState(() => _sales = hotelRows(res));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Error', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// loadHotelCashAccounts and the active corporate customers.
  Future<void> _loadSide() async {
    try {
      final rows = hotelAlias(hotelRows(await _api.get('/api/Hotel/finance/cash-accounts', query: {'farmId': _farmId})), [
        'hotelCashAccountId',
        'accountName',
        'currentBalance',
        'allowNegativeBalance',
        'isActive',
      ]);
      _accounts = [
        for (final a in rows)
          if (a['isActive'] != false)
            {
              'id': a['hotelCashAccountId'],
              'name': a['accountName'],
              'currentBalance': a['currentBalance'],
              'allowNegativeBalance': a['allowNegativeBalance'] == true,
            },
      ];
    } catch (_) {
      _accounts = [];
    }
    try {
      _customers = [
        for (final c in hotelRows(await _api.get('/api/Hotel/customers', query: {'farmId': _farmId})))
          if (c['isActive'] != false) c,
      ];
    } catch (_) {
      _customers = [];
    }
    if (mounted) setState(() {});
  }

  void _go(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  bool _canBill(Map s) =>
      _isStay(s) && s['bookingStatus'] == 'CheckedOut' && s['billedToAccount'] != true && tNum(s['balance']) > 0 && _can;

  Future<void> _pay(Map s) async {
    final r = hotelSaleRow(s);
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordPaymentScreen(
          session: widget.session,
          company: widget.company,
          api: hotelBalancesApi,
          sourceType: 'SaleEntry',
          cashAccounts: _accounts,
          party: {
            'partyId': tIntOrNull(s['partyId']) ?? 0,
            'partyName': r.customer,
            'paymentTermsDays': 0,
            'totalBalance': r.balance,
            'openDocumentCount': 1,
            'overdueAmount': 0,
            'totalInvoiced': r.total,
            'totalPaid': r.paid,
          },
          single: {
            'documentType': s['documentType'],
            'documentId': tIntOrNull(s['documentId']),
            'reference': s['reference'],
            'documentDate': r.date,
            'label': s['label'],
            'totalAmount': r.total,
            'amountPaid': r.paid,
            'balance': r.balance,
            'dueDate': s['dueDate'],
            'ageDays': 0,
            'status': r.paid > 0 ? 'Partially Paid' : 'Unpaid',
            'isOverdue': s['isOverdue'] == true,
          },
        ),
      ),
    );
    if (ok == true) _load();
  }

  void _payments(Map s) => showPaymentHistory(
    context,
    session: widget.session,
    company: widget.company,
    partyName: tStr(s['partyName']).isEmpty ? null : tStr(s['partyName']),
    documentType: 'Sale',
    documentId: tIntOrNull(s['documentId']),
    canReverse: _can,
    onReversed: _load,
    api: hotelBalancesApi,
  );

  void _edit(Map s) => _go('/hotel-bookings?edit=${s['documentId']}', 'Bookings');

  Future<void> _delete(Map s) async {
    final r = hotelSaleRow(s);
    var busy = false;
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const FormDialogTitle(icon: Icons.delete_outline, color: FormColor.red, text: 'Delete sale?'),
          content: SizedBox(
            width: 420,
            child: Text(
              '${r.reference} · ${r.customer}. The booking is cancelled and its room freed. A sale with money paid on it can\'t be '
              'deleted: reverse the payments first (Payments button).',
              style: const TextStyle(fontSize: 14, color: TColors.slate600),
            ),
          ),
          actions: [
            FormDialogFooter(
              onCancel: () => Navigator.pop(ctx),
              cancelDisabled: busy,
              children: [
                FilledButton(
                  style: formPrimary(FormColor.red),
                  onPressed: busy
                      ? null
                      : () async {
                          setLocal(() => busy = true);
                          try {
                            await _api.delete('/api/Hotel/sales/${s['documentId']}', query: {'farmId': _farmId});
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } on ApiException catch (e) {
                            setLocal(() => busy = false);
                            if (ctx.mounted) trackerToast(ctx, 'Could not delete', description: e.message, error: true);
                          }
                        },
                  child: Text(busy ? 'Deleting…' : 'Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (done == true) {
      if (mounted) trackerToast(context, 'Sale deleted', description: '${r.reference} was cancelled.');
      _load();
    }
  }

  Future<void> _billTo(Map s) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _BillToDialog(session: widget.session, company: widget.company, sale: s, customers: _customers, fmt: _gh),
    );
    if (done == true) _load();
  }

  Future<void> _invoice(Map s) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _InvoiceScreen(company: widget.company, sale: s, fmt: _gh),
    ),
  );

  ReportDocument _pdfDoc(List<Map> rows) {
    final rs = [for (final s in rows) hotelSaleRow(s)];
    final total = rs.fold<num>(0, (t, r) => t + r.total);
    final qty = rs.fold<num>(0, (t, r) => t + (r.nights ?? 0));
    return ReportDocument(
      title: 'Hotel Sales',
      filename: 'hotel-sales',
      farmName: widget.company.name,
      fromDate: _from.isEmpty ? null : _from,
      toDate: _to.isEmpty ? null : _to,
      landscape: true,
      violet: true,
      sections: [
        ReportSection(
          columns: const [
            ReportColumn('Sale ID'),
            ReportColumn('Date'),
            ReportColumn('Sale'),
            ReportColumn('Customer'),
            ReportColumn('Room Nights', right: true),
            ReportColumn('Total', right: true),
            ReportColumn('Paid', right: true),
            ReportColumn('Balance', right: true),
            ReportColumn('Method'),
            ReportColumn('Status'),
          ],
          rows: [
            for (final r in rs)
              [
                r.reference,
                _short(r.date),
                r.product,
                r.customer,
                r.nights == null ? '' : '${r.nights!.toInt()}',
                _gh(r.total),
                _gh(r.paid),
                _gh(r.balance),
                r.method ?? '',
                r.status,
              ],
          ],
          totals: [
            '',
            '',
            '',
            'TOTALS',
            '${qty.toInt()}',
            _gh(total),
            _gh(rs.fold<num>(0, (t, r) => t + r.paid)),
            _gh(rs.fold<num>(0, (t, r) => t + r.balance)),
            '',
            '',
          ],
        ),
      ],
      notes: ['Total sales: ${_gh(total)}  |  Room Nights: ${qty.toInt()}  |  Transactions: ${rows.length}'],
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
      if (mounted) {
        trackerToast(context, 'Email failed', description: e.message.isNotEmpty ? e.message : 'Could not send report.', error: true);
      }
    }
    if (mounted) setState(() => _emailing = false);
  }

  int get _activeCount =>
      [_search.text, _from, _to, _type != 'all' ? 'x' : '', _status != 'all' ? 'x' : ''].where((x) => x.isNotEmpty).length;

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Filters', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                const Text(
                  'Date range',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700),
                ),
                const SizedBox(height: 10),
                rField('Start date', rDateInput(from, (v) => set(() => from = v))),
                const SizedBox(height: 12),
                rField('End date', rDateInput(to, (v) => set(() => to = v))),
                const SizedBox(height: 14),
                rField(
                  'Sale type',
                  AppSelect<String>(
                    value: type,
                    items: const [
                      AppSelectItem(value: 'all', label: 'All sales'),
                      AppSelectItem(value: 'Stay', label: 'Stays'),
                      AppSelectItem(value: 'Order', label: 'Restaurant orders'),
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
                Row(
                  children: [
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
                        style: FilledButton.styleFrom(backgroundColor: hotelViolet, minimumSize: const Size.fromHeight(48)),
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
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-sales');
    final items = _focus != null
        ? [
            for (final s in _sales)
              if (_isStay(s) && tIntOrNull(s['documentId']) == _focus) s,
          ]
        : _sales;
    final filtered = filterHotelSales(items, from: _from, to: _to, type: _type, status: _status, search: _search.text);
    final rows = [for (final s in filtered) hotelSaleRow(s)];
    final totalSales = rows.fold<num>(0, (t, r) => t + r.total);
    final totalQty = rows.fold<num>(0, (t, r) => t + (r.nights ?? 0));
    final totalOwed = rows.fold<num>(0, (t, r) => t + r.balance);
    if ((_page - 1) * _pageSize >= filtered.length && _page > 1) _page = 1;
    final pageItems = pageSlice(filtered, _page, _pageSize);

    Widget card(String title, IconData icon, String value, String hint, {Color? color}) => TCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              Icon(icon, size: 16, color: TColors.slate400),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color ?? TColors.slate900),
            ),
          ),
          Text(hint, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Sales')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const HotelPageHeader(
              icon: Icons.shopping_cart_outlined,
              title: 'Sales',
              description: 'Stays and restaurant sales, what was paid and what is still owed',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(44))),
              onPressed: () => _go('/hotel-bookings?new=1', 'Bookings'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Booking'),
            ),
            if (_focus != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: TColors.violet50,
                  border: Border.all(color: TColors.violet200),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Showing one stay.', style: TextStyle(fontSize: 13, color: Color(0xFF4C1D95))),
                    ),
                    InkWell(
                      onTap: () => setState(() => _focus = null),
                      child: const Text(
                        'Show all sales',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.violet700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            AppInput(
              controller: _search,
              hintText: 'Search customer, reference or room',
              prefixIcon: const Icon(Icons.search, size: 18),
              onChanged: (_) => setState(() => _page = 1),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _filters,
                  icon: const Icon(Icons.filter_list, size: 16),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Filters'),
                      if (_activeCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(color: const Color(0xFFF97316), borderRadius: BorderRadius.circular(999)),
                          child: Text('$_activeCount', style: const TextStyle(fontSize: 12, color: Colors.white)),
                        ),
                      ],
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _exportPdf(filtered),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: _emailing ? null : () => _email(filtered),
                  icon: _emailing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.mail_outline, size: 16),
                  label: const Text('Email'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: card('Total Sales', Icons.attach_money, _gh(totalSales), '${filtered.length} transactions')),
                const SizedBox(width: 10),
                Expanded(child: card('Room Nights', Icons.inventory_2_outlined, '${totalQty.toInt()}', 'nights sold')),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: card(
                    'Average Sale',
                    Icons.trending_up,
                    _gh(filtered.isEmpty ? 0 : totalSales / filtered.length),
                    'per transaction',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: card(
                    'Balance',
                    Icons.account_balance_wallet_outlined,
                    _gh(totalOwed),
                    'still owed',
                    color: totalOwed > 0 ? TColors.amber700 : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const TCard(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: LoadingLine('Loading…')),
                ),
              )
            else if (items.isEmpty)
              const TCard(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 40, color: TColors.slate400),
                      SizedBox(height: 12),
                      Text(
                        'No sales found',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TColors.slate900),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Bookings and restaurant orders appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: TColors.slate600),
                      ),
                    ],
                  ),
                ),
              )
            else if (filtered.isEmpty)
              TCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Column(
                    children: [
                      const Text('No sales match the current filters.', style: TextStyle(color: TColors.slate600)),
                      const SizedBox(height: 10),
                      OutlinedButton(onPressed: _clear, child: const Text('Reset filters')),
                    ],
                  ),
                ),
              )
            else
              TCard(
                title: 'Recent Sales',
                description: 'View and manage your sales transactions',
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_table) ...[
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Table • Scroll → for more', style: TextStyle(fontSize: 12, color: TColors.slate600)),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() => _table = false),
                            icon: const Icon(Icons.keyboard_arrow_up, size: 16),
                            label: const Text('Cards'),
                          ),
                        ],
                      ),
                      _tableView(pageItems),
                    ] else ...[
                      for (final (i, s) in pageItems.indexed)
                        _SaleCard(
                          key: ValueKey('${s['documentType']}-${s['documentId']}'),
                          striped: i.isEven,
                          actions: _cardActions(s),
                          sale: s,
                          fmt: _gh,
                        ),
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
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Poultry's order: Pay, Edit, Invoice (built into the shared view),
  /// Payments, Bill to account, Delete. A walk-in restaurant order is settled
  /// at the till, so only Invoice applies to it.
  List<Widget> _cardActions(Map s) {
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
    final stay = _isStay(s);
    return [
      if (stay && tNum(s['balance']) > 0 && _can) b('Pay', Icons.account_balance_wallet_outlined, () => _pay(s), color: TColors.emerald700),
      if (stay) b('Edit', Icons.edit_outlined, () => _edit(s)),
      b('Invoice', Icons.description_outlined, () => _invoice(s)),
      if (stay) b('Payments', Icons.history, () => _payments(s)),
      if (_canBill(s)) b('Bill to account', Icons.apartment_outlined, () => _billTo(s), color: TColors.violet700),
      if (stay) b('Delete', Icons.delete_outline, () => _delete(s), color: TColors.red600),
    ];
  }

  Widget _tableView(List<Map> items) => TrackerTable(
    columns: const [
      TCol('Sale ID', width: 100),
      TCol('Date', width: 120),
      TCol('Sale', width: 160),
      TCol('Customer', width: 130),
      TCol('Room Nights', right: true, width: 90),
      TCol('Total', right: true, width: 110),
      TCol('Paid', right: true, width: 110),
      TCol('Balance', right: true, width: 110),
      TCol('Method', width: 100),
      TCol('Status', width: 90),
      TCol('Actions', width: 270),
    ],
    rows: [
      for (final s in items)
        () {
          final r = hotelSaleRow(s);
          final stay = _isStay(s);
          return [
            cellText(r.reference, color: TColors.slate500),
            cellText(_short(r.date)),
            cellText(r.product),
            cellText(r.customer),
            cellText(r.nights == null ? '—' : '${r.nights!.toInt()}'),
            cellText(_gh(r.total), bold: true),
            cellText(_gh(r.paid), color: TColors.emerald700),
            cellText(_gh(r.balance), color: r.balance > 0 ? TColors.amber700 : TColors.slate400, bold: r.balance > 0),
            r.method == null ? cellText('—') : Align(alignment: Alignment.centerLeft, child: rStatusBadge(r.method!)),
            Align(alignment: Alignment.centerLeft, child: saleStatusBadge(r.status)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (stay && r.balance > 0 && _can)
                  IconButton(
                    tooltip: 'Record payment · ${_gh(r.balance)} owed',
                    icon: const Icon(Icons.account_balance_wallet_outlined, size: 18, color: TColors.emerald700),
                    onPressed: () => _pay(s),
                  ),
                if (stay) IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(s)),
                IconButton(tooltip: 'Invoice', icon: const Icon(Icons.description_outlined, size: 18), onPressed: () => _invoice(s)),
                if (stay) IconButton(tooltip: 'Payment history', icon: const Icon(Icons.history, size: 18), onPressed: () => _payments(s)),
                if (_canBill(s))
                  IconButton(
                    tooltip: 'Bill to account',
                    icon: const Icon(Icons.apartment_outlined, size: 18, color: TColors.violet700),
                    onPressed: () => _billTo(s),
                  ),
                if (stay)
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600),
                    onPressed: () => _delete(s),
                  ),
              ],
            ),
          ];
        }(),
    ],
  );
}

/// One expandable sale card: reference, date and customer; the total and what
/// was sold; then the figures (Room Nights, the details, Paid, Balance,
/// Method, Status) and the buttons, two to a row.
class _SaleCard extends StatefulWidget {
  const _SaleCard({super.key, required this.sale, required this.fmt, required this.actions, required this.striped});
  final Map sale;
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
    final r = hotelSaleRow(widget.sale);
    final gh = widget.fmt;
    // Wraps rather than overflows: "Room Nights" is long for half a phone.
    Widget kv(String k, Widget v) => Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('$k ', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          child: v,
        ),
      ],
    );
    final details = [
      kv('Room Nights', Text(r.nights == null ? '—' : '${r.nights!.toInt()}')),
      for (final (k, v) in r.details) kv(k, Text(v)),
      kv('Paid', Text(gh(r.paid), style: const TextStyle(color: TColors.emerald700))),
      kv('Balance', Text(gh(r.balance), style: TextStyle(color: r.balance > 0 ? TColors.amber700 : TColors.slate400))),
      kv('Method', Text(r.method ?? '—')),
      kv('Status', saleStatusBadge(r.status)),
    ];
    Widget pairs(List<Widget> ws, double gap) => Column(
      children: [
        for (var i = 0; i < ws.length; i += 2) ...[
          if (i > 0) SizedBox(height: gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: ws[i]),
              const SizedBox(width: 8),
              Expanded(child: i + 1 < ws.length ? ws[i + 1] : const SizedBox()),
            ],
          ),
        ],
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: widget.striped ? TColors.amber100 : Colors.white,
        border: Border.all(color: widget.striped ? TColors.amber300 : TColors.slate200),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(r.reference, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                          Text(
                            _short(r.date),
                            style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900),
                          ),
                          const Text('•', style: TextStyle(color: TColors.slate500)),
                          Text(r.customer, style: const TextStyle(color: TColors.slate600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            gh(r.total),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: TColors.emerald600),
                          ),
                          Text(r.product, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: TColors.slate400),
              ],
            ),
          ),
          if (_open) ...[
            const Divider(height: 24, color: TColors.slate100),
            pairs(details, 8),
            const SizedBox(height: 12),
            pairs(widget.actions, 8),
          ],
        ],
      ),
    );
  }
}

/// "Bill to account": the stay's balance moves from the guest to a corporate
/// account. Pops true once billed.
class _BillToDialog extends StatefulWidget {
  const _BillToDialog({required this.session, required this.company, required this.sale, required this.customers, required this.fmt});
  final Session session;
  final Company company;
  final Map sale;
  final List<Map> customers;
  final FarmMoney fmt;
  @override
  State<_BillToDialog> createState() => _BillToDialogState();
}

class _BillToDialogState extends State<_BillToDialog> {
  int? _customer;
  bool _busy = false;

  Future<void> _bill() async {
    if (_customer == null) return;
    setState(() => _busy = true);
    final r = hotelSaleRow(widget.sale);
    try {
      await widget.session.farmClient.post(
        '/api/Hotel/sales/${widget.sale['documentId']}/bill-to',
        body: {'farmId': widget.company.farmId, 'hotelCustomerId': _customer},
      );
      if (!mounted) return;
      trackerToast(context, 'Billed to account', description: "${r.reference} moved to the account's balance.");
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      trackerToast(context, 'Error', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = hotelSaleRow(widget.sale);
    Widget line(String k, Widget v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(k, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(width: 8),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: v),
          ),
        ],
      ),
    );
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: const FormDialogTitle(icon: Icons.apartment_outlined, color: FormColor.purple, text: 'Bill to account'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "The stay's balance moves from the guest to a corporate account and appears on Customer Balances.",
                style: TextStyle(fontSize: 13, color: TColors.slate500),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: TColors.slate50,
                  border: Border.all(color: TColors.slate200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    line(
                      'Sale',
                      Text(
                        '${r.reference} · ${r.customer}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    line(
                      'Owed',
                      Text(
                        widget.fmt(r.balance),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: TColors.amber700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilterLabel(
                'Customer *',
                AppSelect<int>(
                  value: _customer,
                  hintText: 'Select a customer',
                  items: [
                    for (final c in widget.customers)
                      AppSelectItem(value: tIntOrNull(c['hotelCustomerId']) ?? 0, label: tStr(c['customerName'])),
                  ],
                  onChanged: (v) => setState(() => _customer = v),
                ),
              ),
              if (widget.customers.isEmpty) ...[
                const SizedBox(height: 6),
                const Text('No customers yet. Add one under Customers.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
              ],
            ],
          ),
        ),
        actions: [
          FormDialogFooter(
            onCancel: () => Navigator.pop(context),
            cancelDisabled: _busy,
            children: [
              FilledButton(
                style: hotelPrimary,
                onPressed: _busy || _customer == null ? null : _bill,
                child: Text(_busy ? 'Saving…' : 'Bill to account'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The shared view's Invoice: Hotel passes no line loader, so the sale is its
/// one line. Print shares the PDF.
class _InvoiceScreen extends StatelessWidget {
  const _InvoiceScreen({required this.company, required this.sale, required this.fmt});
  final Company company;
  final Map sale;
  final FarmMoney fmt;

  Future<void> _print() async {
    final r = hotelSaleRow(sale);
    await ReportExport.sharePdf(
      ReportDocument(
        title: 'Invoice ${r.reference}',
        filename: 'invoice-${r.reference}',
        farmName: company.name,
        subtitle: 'Bill to: ${r.customer} · ${_short(r.date)}',
        violet: true,
        landscape: false,
        sections: [
          ReportSection(
            columns: const [
              ReportColumn('Description'),
              ReportColumn('Qty', right: true),
              ReportColumn('Unit price', right: true),
              ReportColumn('Amount', right: true),
            ],
            rows: [
              [r.product, '1', fmt(r.total), fmt(r.total)],
            ],
            totals: ['', '', 'Total', fmt(r.total)],
          ),
        ],
        notes: ['Paid: ${fmt(r.paid)}', 'Balance due: ${fmt(r.balance)}'],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = hotelSaleRow(sale);
    const sm = TextStyle(fontSize: 12, color: TColors.slate500);
    Widget totalRow(String k, String v, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              textAlign: TextAlign.right,
              style: TextStyle(color: bold ? TColors.slate900 : TColors.slate500, fontWeight: bold ? FontWeight.w600 : null),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 110,
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: bold ? FontWeight.w600 : null),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Review the invoice and print or save a PDF for your customer.',
            style: TextStyle(fontSize: 13, color: TColors.slate500),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(company.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const Text('Invoice', style: sm),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(r.reference, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(_short(r.date), style: sm),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Bill to: ',
                  style: TextStyle(color: TColors.slate500),
                ),
                TextSpan(
                  text: r.customer,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TrackerTable(
            columns: const [
              TCol('Description', width: 160),
              TCol('Qty', right: true, width: 60),
              TCol('Unit price', right: true, width: 100),
              TCol('Amount', right: true, width: 100),
            ],
            rows: [
              [cellText(r.product), cellText('1'), cellText(fmt(r.total)), cellText(fmt(r.total))],
            ],
          ),
          const SizedBox(height: 8),
          totalRow('Total', fmt(r.total), bold: true),
          totalRow('Paid', fmt(r.paid)),
          totalRow('Balance due', fmt(r.balance), bold: true),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              FilledButton.icon(
                style: hotelPrimary,
                onPressed: _print,
                icon: const Icon(Icons.print_outlined, size: 16),
                label: const Text('Print'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
