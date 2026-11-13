// Generic → Reports → Delivery report
// (`app/generic-reports/delivery-report/page.tsx`): driver performance,
// product sell-through and route profitability, with the summary cards, the
// search, the dates (applied by Refresh, as on the web) and Export PDF.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../poultry/money/money_widgets.dart';
import '../../poultry/reports/report_export.dart';
import '../../poultry/sales/balances_widgets.dart';
import '../../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../../poultry/trackers/tracker_widgets.dart';
import '../generic_kit.dart';
import '../reports/generic_report_kit.dart';
import 'delivery_kit.dart';

import 'package:poultrycore_mobile/design/tone.dart';

/// The web's driverTotals: the four cards come from the driver rows.
({num deliveries, num sales, num expenses, int rate}) genericDeliveryReportTotals(List<Map> drivers) {
  num deliveries = 0, sales = 0, expenses = 0, loaded = 0, sold = 0;
  for (final d in drivers) {
    deliveries += tNum(d['totalDeliveries']);
    sales += tNum(d['totalSales']);
    expenses += tNum(d['totalExpenses']);
    loaded += tNum(d['totalLoaded']);
    sold += tNum(d['totalSold']);
  }
  return (deliveries: deliveries, sales: sales, expenses: expenses, rate: loaded > 0 ? (sold / loaded * 100).round() : 0);
}

/// The web's rate colours: 80 % and up green, 50 % and up amber, else red.
Color rateColor(num r) => r >= 80 ? TColors.emerald700 : r >= 50 ? TColors.amber600 : TColors.red600;

/// defaultReportRange(): the last 30 days, today included.
GenericRange last30Range([DateTime? today]) {
  final t = today ?? DateTime.now();
  return (from: ymd(t.subtract(const Duration(days: 29))), to: ymd(t));
}

class GenericDeliveryReportScreen extends StatefulWidget {
  const GenericDeliveryReportScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<GenericDeliveryReportScreen> createState() => _State();
}

class _State extends State<GenericDeliveryReportScreen> {
  String _tab = 'drivers';
  bool _loading = true;
  late GenericRange _range = last30Range();
  final _search = TextEditingController();
  List<Map> _drivers = [], _products = [], _routes = [];

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

  Future<List<Map>> _get(String by) async {
    try {
      return rowsOf(await widget.session.farmClient.get('${genericBase(widget.company)}/deliveries/reports/$by',
          query: {if (_range.from.isNotEmpty) 'fromDate': _range.from, if (_range.to.isNotEmpty) 'toDate': _range.to}));
    } on ApiException {
      return [];
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await Future.wait([_get('by-driver'), _get('by-product'), _get('by-route')]);
    if (!mounted) return;
    setState(() {
      _drivers = r[0];
      _products = r[1];
      _routes = r[2];
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _match(List<Map> rows, String key) {
    final q = _search.text.toLowerCase();
    return [for (final r in rows) if (q.isEmpty || tStr(r[key]).toLowerCase().contains(q)) Map<String, dynamic>.from(r)];
  }

  Future<void> _export() async {
    String money(Object? v) => fmtMoney(v);
    final (title, cols, rows) = switch (_tab) {
      'drivers' => (
          'By Driver',
          const [ReportColumn('Driver'), ReportColumn('Deliveries', right: true), ReportColumn('Loaded', right: true), ReportColumn('Sold', right: true), ReportColumn('Sales', right: true), ReportColumn('Rate %', right: true)],
          [for (final d in _drivers) [tStr(d['driverName']), tStr(d['totalDeliveries']), tStr(d['totalLoaded']), tStr(d['totalSold']), money(d['totalSales']), tStr(d['deliveryRate'])]],
        ),
      'products' => (
          'By Product',
          const [ReportColumn('Product'), ReportColumn('Deliveries', right: true), ReportColumn('Loaded', right: true), ReportColumn('Sold', right: true), ReportColumn('Sales', right: true), ReportColumn('Sell-through %', right: true)],
          [for (final p in _products) [tStr(p['productName']), tStr(p['totalDeliveries']), tStr(p['totalLoaded']), tStr(p['totalSold']), money(p['totalSales']), tStr(p['sellThroughRate'])]],
        ),
      _ => (
          'By Route',
          const [ReportColumn('Route'), ReportColumn('Deliveries', right: true), ReportColumn('Sales', right: true), ReportColumn('Expenses', right: true), ReportColumn('Net Revenue', right: true)],
          [for (final r in _routes) [tStr(r['route']), tStr(r['totalDeliveries']), money(r['totalSales']), money(r['totalExpenses']), money(r['netRevenue'])]],
        ),
    };
    try {
      await ReportExport.sharePdf(ReportDocument(
        title: 'Delivery Report — $title',
        filename: 'generic-delivery-report-$_tab',
        farmName: widget.company.name,
        subtitle: '${_range.from} to ${_range.to}',
        sections: [ReportSection(columns: cols, rows: rows)],
      ));
    } catch (_) {
      if (mounted) trackerToast(context, 'PDF export failed', description: 'Could not generate the PDF. Please try again.', error: true);
    }
  }

  Widget _kpi(String label, IconData icon, String v, {Color? color}) => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: TColors.slate500),
            const SizedBox(width: 4),
            Flexible(child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .4, color: TColors.slate500))),
          ]),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: color ?? TColors.slate900)),
          ),
        ]),
      );

  Widget _rate(Object? v) => Text('${tStr(v)}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: rateColor(tNum(v))));

  Widget _mini(num n, String word, Color bg, Color fg) => TBadge('${n is int ? n : n.round()} $word', bg: bg, fg: fg);

  Widget _section(String title, String sub, Widget body) => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColors.slate900)),
          Text(sub, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          const SizedBox(height: 8),
          body,
        ]),
      );

  Widget _body() {
    const red = TColors.red600, amber = TColors.amber600, green = TColors.emerald700;
    if (_tab == 'drivers') {
      return _section(
        'Driver Performance',
        '${_drivers.length} driver(s) in period',
        ReportTable(
          empty: 'No delivery data for this period.',
          rows: _drivers.isEmpty ? [] : _match(_drivers, 'driverName'),
          columns: [
            RCol('Driver', (d) => tStr(d['driverName']), bold: true),
            RCol('Transport', (d) => TBadge(tStr(d['transportMode']).isEmpty ? 'Car' : tStr(d['transportMode']), bg: TColors.blue100, fg: const Tone.fg(0xFF1D4ED8))),
            RCol('Trips', (d) => tStr(d['totalDeliveries']), right: true),
            RCol('Loaded', (d) => tStr(d['totalLoaded']), right: true),
            RCol('Sold', (d) => tStr(d['totalSold']), right: true, color: green),
            RCol('Returned', (d) => tStr(d['totalReturned']), right: true),
            RCol('Damaged', (d) => tStr(d['totalDamaged']), right: true, color: red),
            RCol('Short', (d) => tStr(d['totalShort']), right: true, color: amber),
            RCol('Sales', (d) => fmtMoney(d['totalSales']), right: true, bold: true),
            RCol('Cash', (d) => fmtMoney(d['totalCashCollected']), right: true),
            RCol('Expenses', (d) => fmtMoney(d['totalExpenses']), right: true, color: red),
            RCol('Rate', (d) => _rate(d['deliveryRate']), right: true),
            RCol(
              'Status Breakdown',
              (d) => Wrap(spacing: 4, runSpacing: 4, children: [
                if (tNum(d['loadedDeliveries']) > 0) _mini(tNum(d['loadedDeliveries']), 'loaded', TColors.slate100, TColors.slate700),
                if (tNum(d['inTransitDeliveries']) > 0) _mini(tNum(d['inTransitDeliveries']), 'transit', TColors.blue100, const Tone.fg(0xFF1D4ED8)),
                if (tNum(d['deliveredDeliveries']) > 0) _mini(tNum(d['deliveredDeliveries']), 'delivered', TColors.emerald100, TColors.emerald700),
                if (tNum(d['reconciledDeliveries']) > 0) _mini(tNum(d['reconciledDeliveries']), 'done', const Tone.bg(0xFFDCFCE7), const Tone.fg(0xFF15803D)),
                if (tNum(d['cancelledDeliveries']) > 0) _mini(tNum(d['cancelledDeliveries']), 'cancelled', TColors.amber100, TColors.amber700),
              ]),
            ),
          ],
        ),
      );
    }
    if (_tab == 'products') {
      return _section(
        'Product Delivery Performance',
        '${_products.length} product(s) delivered in period',
        ReportTable(
          empty: 'No reconciled deliveries in this period.',
          rows: _products.isEmpty ? [] : _match(_products, 'productName'),
          columns: [
            RCol('Product', (p) => tStr(p['productName']), bold: true),
            RCol('Deliveries', (p) => tStr(p['totalDeliveries']), right: true),
            RCol('Loaded', (p) => tStr(p['totalLoaded']), right: true),
            RCol('Sold', (p) => tStr(p['totalSold']), right: true, color: green),
            RCol('Returned', (p) => tStr(p['totalReturned']), right: true),
            RCol('Damaged', (p) => tStr(p['totalDamaged']), right: true, color: red),
            RCol('Short', (p) => tStr(p['totalShort']), right: true, color: amber),
            RCol('Sales', (p) => fmtMoney(p['totalSales']), right: true, bold: true),
            RCol('Sell-through', (p) => _rate(p['sellThroughRate']), right: true),
          ],
        ),
      );
    }
    return _section(
      'Route Profitability',
      '${_routes.length} route(s) in period',
      ReportTable(
        empty: 'No reconciled deliveries in this period.',
        rows: _routes.isEmpty ? [] : _match(_routes, 'route'),
        columns: [
          RCol('Route', (r) => tStr(r['route']), bold: true),
          RCol('Deliveries', (r) => tStr(r['totalDeliveries']), right: true),
          RCol('Loaded', (r) => tStr(r['totalLoaded']), right: true),
          RCol('Sold', (r) => tStr(r['totalSold']), right: true),
          RCol('Sales', (r) => fmtMoney(r['totalSales']), right: true),
          RCol('Expenses', (r) => fmtMoney(r['totalExpenses']), right: true, color: red),
          RCol('Net Revenue', (r) => Text(fmtMoney(r['netRevenue']),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tNum(r['netRevenue']) >= 0 ? green : red))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-reports/delivery-report');
    final t = genericDeliveryReportTotals(_drivers);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Delivery Report')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        dHeader(Icons.local_shipping_outlined, 'Delivery Report', 'Driver performance, product sell-through, and route profitability.'),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('delivery-report-pdf'),
            onPressed: _loading ? null : _export,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Export PDF'),
          ),
        ),
        const SizedBox(height: 12),
        kpiGrid([
            _kpi('Total Deliveries', Icons.inventory_2_outlined, '${t.deliveries}'),
            _kpi('Total Sales', Icons.trending_up, fmtMoney(t.sales), color: TColors.emerald700),
            _kpi('Total Expenses', Icons.trending_down, fmtMoney(t.expenses), color: TColors.red700),
            _kpi('Sell-through Rate', Icons.local_shipping_outlined, '${t.rate}%'),
          ],
        ),
        const SizedBox(height: 12),
        ListFiltersCard(
          search: _search,
          searchPlaceholder: 'Search driver, product, route…',
          onSearch: () => setState(() {}),
          from: _range.from,
          to: _range.to,
          onDates: (f, to) => setState(() => _range = (from: f, to: to)),
          onClear: () => setState(() {
            _search.clear();
            _range = (from: '', to: '');
          }),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final (id, label) in const [('drivers', 'By Driver'), ('products', 'By Product'), ('routes', 'By Route')])
            filterChipButton(label, _tab == id, () => setState(() => _tab = id)),
          TextButton(key: const ValueKey('delivery-report-refresh'), onPressed: _loading ? null : _load, child: const Text('Refresh')),
        ]),
        const SizedBox(height: 10),
        if (_loading) const LoadingLine('Loading report…') else _body(),
      ]),
    );
  }
}
