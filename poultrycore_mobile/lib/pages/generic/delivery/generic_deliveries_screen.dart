// Generic → Deliveries (`app/generic-deliveries/page.tsx`): load a product
// onto a driver, dispatch it, mark it delivered, reconcile what was sold,
// returned, damaged or short, and reverse or cancel. Summary cards, status
// filter, search and dates, GPS and place search on the load form, and the
// quick Add Driver / Add Route dialogs.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../poultry/money/money_widgets.dart';
import '../../poultry/sales/balances_logic.dart' show pageSlice;
import '../../poultry/sales/balances_widgets.dart';
import '../../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../../poultry/trackers/tracker_widgets.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../generic_kit.dart';
import '../reports/generic_report_kit.dart' show fmtMoney;
import 'delivery_kit.dart';
import 'generic_fleet_screens.dart';

import 'package:poultrycore_mobile/design/tone.dart';

const genericDeliveryStatuses = ['All', 'Loaded', 'InTransit', 'Delivered', 'Reconciled', 'Cancelled'];
const _notReconciled = ['Loaded', 'InTransit', 'Delivered'];

String deliveryStatusLabel(String s) => s == 'InTransit' ? 'In Transit' : s;

Widget deliveryStatusBadge(String s) {
  final c = switch (s) {
    'InTransit' => (TColors.blue100, const Tone.fg(0xFF1D4ED8)),
    'Delivered' => (TColors.emerald100, TColors.emerald700),
    'Reconciled' => (const Tone.bg(0xFFDCFCE7), const Tone.fg(0xFF15803D)),
    'Cancelled' => (TColors.amber100, TColors.amber700),
    _ => (TColors.slate100, TColors.slate700),
  };
  return TBadge(deliveryStatusLabel(s), bg: c.$1, fg: c.$2);
}

/// The web's filter: status, then search over its six fields and the date.
List<Map> filterGenericDeliveries(List<Map> rows, {String status = 'All', String search = '', String from = '', String to = ''}) {
  final q = search.trim().toLowerCase();
  return rows.where((d) {
    if (status != 'All' && d['status'] != status) return false;
    final day = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(tStr(d['deliveryDate']))?[1];
    if (day != null) {
      if (from.isNotEmpty && day.compareTo(from) < 0) return false;
      if (to.isNotEmpty && day.compareTo(to) > 0) return false;
    }
    if (q.isNotEmpty && !['productName', 'driverName', 'customerName', 'destination', 'route', 'transportMode'].any((k) => tStr(d[k]).toLowerCase().contains(q))) {
      return false;
    }
    return true;
  }).toList();
}

/// The four summary cards, over every delivery (not just the filtered ones).
({int total, int inTransit, int delivered, num sales}) genericDeliveryKpis(List<Map> rows) {
  var inTransit = 0, delivered = 0;
  num sales = 0;
  for (final d in rows) {
    if (d['status'] == 'InTransit') inTransit++;
    if (d['status'] == 'Delivered') delivered++;
    sales += tNum(d['totalSales']);
  }
  return (total: rows.length, inTransit: inTransit, delivered: delivered, sales: sales);
}

String _or(Object? v) => tStr(v).isEmpty ? '—' : tStr(v);

class GenericDeliveriesScreen extends StatefulWidget {
  const GenericDeliveriesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<GenericDeliveriesScreen> createState() => _GenericDeliveriesScreenState();
}

class _GenericDeliveriesScreenState extends State<GenericDeliveriesScreen> {
  List<Map> _rows = [], _products = [], _drivers = [], _routes = [], _customers = [];
  bool _loading = true;
  String _status = 'All', _from = '', _to = '';
  final _search = TextEditingController();
  int _page = 1, _size = 10;
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _base => genericBase(widget.company);

  @override
  void initState() {
    super.initState();
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

  // The web's Promise.allSettled: one failing list leaves the others.
  Future<List<Map>> _get(String p) async {
    try {
      return rowsOf(await _api.get('$_base/$p'));
    } on ApiException {
      return [];
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await Future.wait([_get('deliveries'), _get('products'), _get('drivers'), _get('routes'), _get('customers')]);
    if (!mounted) return;
    setState(() {
      _rows = r[0];
      _products = r[1];
      _drivers = r[2].where((d) => d['isActive'] == true).toList();
      _routes = r[3].where((x) => x['isActive'] == true).toList();
      _customers = r[4];
      _loading = false;
    });
  }

  Future<void> _act(Map d, String action, String done) async {
    try {
      await _api.post('$_base/deliveries/${tIntOrNull(d['genericDeliveryId'])}/$action', body: {});
      if (mounted) trackerToast(context, done);
      _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  void _dispatch(Map d) => _act(d, 'dispatch', 'Dispatched — in transit');
  void _delivered(Map d) => _act(d, 'mark-delivered', 'Marked as delivered');
  void _reverse(Map d) => _act(d, 'reverse', 'Reversed');
  void _cancel(Map d) => _act(d, 'cancel', 'Cancelled — stock restored');

  Future<void> _dialog(Widget w) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => w);
    if (ok == true) _load();
  }

  void _newLoad() => _dialog(_LoadDialog(
        session: widget.session,
        company: widget.company,
        products: _products,
        drivers: _drivers,
        routes: _routes,
        customers: _customers,
      ));
  void _reconcile(Map d) => _dialog(_ReconcileDialog(session: widget.session, company: widget.company, delivery: d));

  List<Widget> _cardActions(Map d) {
    final s = tStr(d['status']);
    Widget b(String label, IconData icon, Color c, VoidCallback tap) => OutlinedButton.icon(
          key: ValueKey('delivery-$label-${tIntOrNull(d['genericDeliveryId'])}'),
          onPressed: tap,
          style: OutlinedButton.styleFrom(foregroundColor: c, side: BorderSide(color: c.withValues(alpha: .35))),
          icon: Icon(icon, size: 16),
          label: Text(label),
        );
    return [
      if (s == 'Loaded') ...[
        b('Dispatch', Icons.send_outlined, const Tone.fg(0xFF1D4ED8), () => _dispatch(d)),
        b('Cancel', Icons.cancel_outlined, TColors.amber700, () => _cancel(d)),
      ],
      if (s == 'InTransit') b('Mark Delivered', Icons.inventory_outlined, TColors.emerald700, () => _delivered(d)),
      if (_notReconciled.contains(s)) b('Reconcile', Icons.check_circle_outline, const Tone.fg(0xFF15803D), () => _reconcile(d)),
      if (s == 'Reconciled') b('Reverse', Icons.undo, TColors.amber700, () => _reverse(d)),
    ];
  }

  // The table's icon buttons (the web also offers Cancel on In Transit and
  // Delivered rows there).
  Widget _tableActions(Map d) {
    final s = tStr(d['status']);
    IconButton i(String tip, IconData icon, Color c, VoidCallback tap) => IconButton(tooltip: tip, onPressed: tap, icon: Icon(icon, size: 18, color: c));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (s == 'Loaded') ...[
        i('Dispatch', Icons.send_outlined, TColors.blue600, () => _dispatch(d)),
        i('Cancel', Icons.cancel_outlined, TColors.amber600, () => _cancel(d)),
      ],
      if (s == 'InTransit') i('Mark Delivered', Icons.inventory_outlined, TColors.emerald600, () => _delivered(d)),
      if (_notReconciled.contains(s)) i('Reconcile', Icons.check_circle_outline, const Tone.fg(0xFF16A34A), () => _reconcile(d)),
      if (s == 'InTransit' || s == 'Delivered') i('Cancel', Icons.cancel_outlined, TColors.amber600, () => _cancel(d)),
      if (s == 'Reconciled') i('Reverse', Icons.undo, TColors.amber600, () => _reverse(d)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/generic-deliveries');
    final k = genericDeliveryKpis(_rows);
    final visible = filterGenericDeliveries(_rows, status: _status, search: _search.text, from: _from, to: _to);
    Widget kpi(String label, IconData icon, String v, {Color? color}) => TCard(
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
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Deliveries')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          dHeader(Icons.local_shipping_outlined, 'Deliveries', 'Load, dispatch, track and reconcile product deliveries.'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GenericDriversScreen(session: widget.session, company: widget.company))),
              icon: const Icon(Icons.groups_2_outlined, size: 18),
              label: const Text('Drivers'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GenericRoutesScreen(session: widget.session, company: widget.company))),
              icon: const Icon(Icons.place_outlined, size: 18),
              label: const Text('Routes'),
            ),
            FilledButton.icon(key: const ValueKey('delivery-new'), onPressed: _newLoad, icon: const Icon(Icons.add, size: 18), label: const Text('New Load')),
          ]),
          const SizedBox(height: 12),
          kpiGrid([
              kpi('Total', Icons.inventory_2_outlined, '${k.total}'),
              kpi('In Transit', Icons.send_outlined, '${k.inTransit}', color: const Tone.fg(0xFF1D4ED8)),
              kpi('Delivered', Icons.inventory_outlined, '${k.delivered}', color: TColors.emerald700),
              kpi('Total Sales', Icons.trending_up, fmtMoney(k.sales), color: TColors.emerald700),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final s in genericDeliveryStatuses)
              filterChipButton(
                s == 'All' ? 'All' : '${deliveryStatusLabel(s)} (${_rows.where((d) => d['status'] == s).length})',
                s == _status,
                () => setState(() {
                  _status = s;
                  _page = 1;
                }),
              ),
          ]),
          const SizedBox(height: 10),
          ListFiltersCard(
            search: _search,
            searchPlaceholder: 'Search product, driver, customer, route…',
            onSearch: () => setState(() => _page = 1),
            from: _from,
            to: _to,
            onDates: (f, t) => setState(() {
              _from = f;
              _to = t;
              _page = 1;
            }),
            onClear: () => setState(() {
              _search.clear();
              _from = '';
              _to = '';
            }),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const LoadingLine('Loading…')
          else if (visible.isEmpty)
            TCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Text(_rows.isEmpty ? 'No deliveries yet. Load a product to get started.' : 'No deliveries match this filter.',
                    textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate500)),
              ),
            )
          else
            MobileCardList<Map>(
              items: pageSlice(visible, _page, _size),
              keyOf: (d) => '${tIntOrNull(d['genericDeliveryId'])}',
              primary: (d) => tStr(d['productName']).isEmpty ? 'Product #${tStr(d['genericProductId'])}' : tStr(d['productName']),
              secondaryBuilder: (d) => Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                Text(
                  [fmtDateTime(d['deliveryDate'], d, _offset), if (tStr(d['driverName']).isNotEmpty) tStr(d['driverName'])].join(' · '),
                  style: const TextStyle(fontSize: 12, color: TColors.slate500),
                ),
                if (tStr(d['transportMode']).isNotEmpty) TBadge(tStr(d['transportMode']), bg: const Tone.bg(0xFFEFF6FF), fg: const Tone.fg(0xFF1D4ED8)),
              ]),
              trailing: (d) => Padding(padding: const EdgeInsets.only(left: 6), child: deliveryStatusBadge(tStr(d['status']))),
              highlights: (d) => [
                Highlight('Loaded', '${tStr(d['quantityLoaded'])} ${tStr(d['unit'])}'.trim(), accent: Accent.blue),
                if (d['status'] == 'Reconciled') ...[
                  Highlight('Sold', tStr(d['quantitySold']), accent: Accent.emerald),
                  Highlight('Sales', fmtMoney(d['totalSales']), accent: Accent.emerald),
                ],
              ],
              details: (d) => [
                ('Customer', _or(d['customerName'])),
                ('Destination', _or(d['destination'])),
                ('Route', _or(d['route'])),
                ('Vehicle', _or(d['vehicleName'])),
                ('Transport', _or(d['transportMode'])),
                if (tStr(d['deliveredAt']).isNotEmpty) ('Delivered at', fmtDateTime(d['deliveredAt'], d, _offset)),
                if (d['status'] == 'Reconciled') ...[
                  ('Returned', tStr(d['quantityReturned'])),
                  ('Damaged', tStr(d['quantityDamaged'])),
                  ('Short', tStr(d['quantityShort'])),
                  ('Cash collected', fmtMoney(d['cashCollected'])),
                ],
              ],
              actions: _cardActions,
              striped: true,
              stripeBlue: true,
              table: (items) => TrackerTable(
                columns: const [
                  TCol('Date', width: 140), TCol('Product', width: 130), TCol('Customer / Dest.', width: 150), TCol('Driver', width: 140),
                  TCol('Route', width: 110), TCol('Transport', width: 100), TCol('Loaded', right: true, width: 90),
                  TCol('Sold', right: true, width: 70), TCol('Sales', right: true, width: 100), TCol('Status', width: 100),
                  TCol('Actions', right: true, width: 140),
                ],
                rows: [
                  for (final d in items)
                    [
                      cellText(fmtDateTime(d['deliveryDate'], d, _offset)),
                      cellText(_or(d['productName']), bold: true),
                      cellText('${_or(d['customerName'])}${tStr(d['destination']).isEmpty ? '' : ' · ${tStr(d['destination'])}'}'),
                      cellText('${_or(d['driverName'])}${tStr(d['vehicleName']).isEmpty ? '' : ' / ${tStr(d['vehicleName'])}'}'),
                      cellText(_or(d['route'])),
                      tStr(d['transportMode']).isEmpty
                          ? cellText('—')
                          : Align(alignment: Alignment.centerLeft, child: TBadge(tStr(d['transportMode']), bg: const Tone.bg(0xFFEFF6FF), fg: const Tone.fg(0xFF1D4ED8))),
                      Align(alignment: Alignment.centerRight, child: cellText('${tStr(d['quantityLoaded'])} ${tStr(d['unit'])}'.trim())),
                      Align(alignment: Alignment.centerRight, child: cellText(d['status'] == 'Loaded' ? '—' : tStr(d['quantitySold']))),
                      Align(alignment: Alignment.centerRight, child: cellText(d['status'] == 'Loaded' ? '—' : fmtMoney(d['totalSales']))),
                      Align(alignment: Alignment.centerLeft, child: deliveryStatusBadge(tStr(d['status']))),
                      Align(alignment: Alignment.centerRight, child: _tableActions(d)),
                    ],
                ],
              ),
              pager: CompactPager(
                total: visible.length,
                page: _page,
                pageSize: _size,
                onPage: (p) => setState(() => _page = p),
                onPageSize: (v) => setState(() {
                  _size = v;
                  _page = 1;
                }),
              ),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- the load

class _LoadDialog extends StatefulWidget {
  const _LoadDialog({
    required this.session,
    required this.company,
    required this.products,
    required this.drivers,
    required this.routes,
    required this.customers,
  });
  final Session session;
  final Company company;
  final List<Map> products, drivers, routes, customers;
  @override
  State<_LoadDialog> createState() => _LoadDialogState();
}

class _LoadDialogState extends State<_LoadDialog> {
  late List<Map> _drivers = widget.drivers, _routes = widget.routes;
  int _productId = 0;
  String _unit = 'Piece', _mode = 'Car', _driver = '', _route = '', _customer = '';
  String _date = DateTime.now().toIso8601String().substring(0, 10);
  final _qty = TextEditingController(text: '0'), _price = TextEditingController(text: '0');
  final _vehicle = TextEditingController(), _start = TextEditingController(), _dest = TextEditingController();
  final _customerText = TextEditingController(), _notes = TextEditingController();
  bool _saving = false, _locating = false;

  @override
  void initState() {
    super.initState();
    // The web picks the first active product and its selling price.
    final first = widget.products.where((p) => p['isActive'] == true).firstOrNull ?? widget.products.firstOrNull;
    if (first != null) {
      _productId = tIntOrNull(first['genericProductId']) ?? 0;
      _price.text = tStr(first['sellingPrice']).isEmpty ? '0' : tStr(first['sellingPrice']);
    }
  }

  String get _base => genericBase(widget.company);

  void _pickDriver(String name) {
    final d = _drivers.where((x) => x['driverName'] == name).firstOrNull;
    setState(() {
      _driver = name;
      _vehicle.text = tStr(d?['vehicleName']);
      _mode = tStr(d?['transportMode']).isEmpty ? 'Car' : tStr(d?['transportMode']);
    });
  }

  void _pickRoute(String name) {
    final r = _routes.where((x) => x['routeName'] == name).firstOrNull;
    setState(() {
      _route = name;
      if (r?['startPoint'] != null) _start.text = tStr(r!['startPoint']);
      if (r?['endPoint'] != null) _dest.text = tStr(r!['endPoint']);
    });
  }

  Future<void> _addDriver() async {
    final saved = await showDialog<Object?>(
      context: context,
      builder: (_) => GenericDriverDialog(session: widget.session, company: widget.company, quick: true),
    );
    if (saved is! Map) return;
    try {
      final all = rowsOf(await widget.session.farmClient.get('$_base/drivers'));
      if (mounted) setState(() => _drivers = all.where((d) => d['isActive'] == true).toList());
    } on ApiException catch (_) {}
    setState(() {
      _driver = tStr(saved['driverName']);
      _vehicle.text = tStr(saved['vehicleName']);
      _mode = tStr(saved['transportMode']);
    });
  }

  Future<void> _addRoute() async {
    final saved = await showDialog<Object?>(
      context: context,
      builder: (_) => GenericRouteDialog(session: widget.session, company: widget.company, quick: true),
    );
    if (saved is! Map) return;
    try {
      final all = rowsOf(await widget.session.farmClient.get('$_base/routes'));
      if (mounted) setState(() => _routes = all.where((r) => r['isActive'] == true).toList());
    } on ApiException catch (_) {}
    setState(() {
      _route = tStr(saved['routeName']);
      _start.text = tStr(saved['startPoint']);
      _dest.text = tStr(saved['endPoint']);
    });
  }

  Future<void> _save() async {
    if (_productId == 0) return trackerToast(context, 'Pick a product', error: true);
    if (dNum(_qty) <= 0) return trackerToast(context, 'Quantity must be > 0', error: true);
    if (_driver.isEmpty && _drivers.isNotEmpty) return trackerToast(context, 'Select a driver', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('$_base/deliveries/load', body: {
        'genericProductId': _productId,
        'quantityLoaded': dNum(_qty),
        'unit': _unit,
        'unitPrice': dNum(_price),
        'driverName': _driver,
        'vehicleName': _vehicle.text,
        'route': _route,
        'customerName': widget.customers.isNotEmpty ? _customer : _customerText.text,
        'startPoint': _start.text,
        'destination': _dest.text,
        'transportMode': _mode,
        'deliveryDate': _date,
        'notes': _notes.text,
        'farmId': widget.company.farmId,
      });
      if (!mounted) return;
      trackerToast(context, 'Product loaded — stock reduced');
      Navigator.pop(context, true);
      return;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Load failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _withAdd(Widget select, String label, VoidCallback add, Key key) => Row(children: [
        Expanded(child: select),
        const SizedBox(width: 6),
        OutlinedButton.icon(key: key, onPressed: add, icon: const Icon(Icons.add, size: 14), label: Text(label)),
      ]);

  @override
  Widget build(BuildContext context) {
    final route = _routes.where((r) => r['routeName'] == _route).firstOrNull;
    void busy(bool b) => setState(() => _locating = b);
    return AlertDialog(
      scrollable: true,
      title: const Text('Load product for delivery'),
      content: SizedBox(
        width: 672,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          formSection('Product', const Tone.bg(0xFF4F46E5), [
            dField(
              'Product *',
              AppSelect<int>(
                key: const ValueKey('load-product'),
                value: _productId == 0 ? null : _productId,
                hintText: 'Pick product',
                items: [
                  for (final p in widget.products)
                    if (p['isActive'] == true)
                      AppSelectItem(value: tIntOrNull(p['genericProductId']) ?? 0, label: '${tStr(p['productName'])} (${tStr(p['currentStock'])} in stock)'),
                ],
                onChanged: (v) {
                  final p = widget.products.where((x) => tIntOrNull(x['genericProductId']) == v).firstOrNull;
                  setState(() {
                    _productId = v ?? 0;
                    if (p?['sellingPrice'] != null) _price.text = tStr(p!['sellingPrice']);
                  });
                },
              ),
            ),
            dField('Quantity *', dNumber(_qty, key: const ValueKey('load-qty'))),
            dField(
              'Unit',
              AppSelect<String>(
                value: _unit,
                items: [for (final u in genericDeliveryUnits) AppSelectItem(value: u, label: u)],
                onChanged: (v) => setState(() => _unit = v ?? _unit),
              ),
            ),
            dField('Unit price', dNumber(_price, key: const ValueKey('load-price'))),
          ]),
          const SizedBox(height: 12),
          formSection('Driver & Transport', const Tone.bg(0xFF2563EB), [
            dField(
              'Driver *',
              _withAdd(
                AppSelect<String>(
                  key: const ValueKey('load-driver'),
                  value: _driver.isEmpty || !_drivers.any((d) => d['driverName'] == _driver) ? null : _driver,
                  hintText: _drivers.isNotEmpty ? 'Select driver' : 'No drivers — click Add Driver',
                  items: [
                    for (final d in _drivers)
                      AppSelectItem(
                        value: tStr(d['driverName']),
                        label: '${tStr(d['driverName'])}${tStr(d['transportMode']).isEmpty ? '' : ' (${tStr(d['transportMode'])})'}',
                      ),
                  ],
                  onChanged: (v) => _pickDriver(v ?? ''),
                ),
                'Add Driver',
                _addDriver,
                const ValueKey('load-add-driver'),
              ),
            ),
            dField('Vehicle', AppInput(key: const ValueKey('load-vehicle'), controller: _vehicle)),
            dField(
              'Transport mode',
              AppSelect<String>(
                key: const ValueKey('load-mode'),
                value: genericTransportModes.contains(_mode) ? _mode : 'Other',
                items: [for (final m in genericTransportModes) AppSelectItem(value: m, label: m)],
                onChanged: (v) => setState(() => _mode = v ?? _mode),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          formSection('Route & Destination', TColors.emerald600, [
            dField(
              'Route',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _withAdd(
                  AppSelect<String>(
                    key: const ValueKey('load-route'),
                    value: _route.isEmpty || !_routes.any((r) => r['routeName'] == _route) ? null : _route,
                    hintText: _routes.isNotEmpty ? 'Select delivery route' : 'No routes — click Add Route',
                    items: [
                      for (final r in _routes)
                        AppSelectItem(
                          value: tStr(r['routeName']),
                          label: '${tStr(r['routeName'])}'
                              '${tStr(r['startPoint']).isNotEmpty && tStr(r['endPoint']).isNotEmpty ? ' (${tStr(r['startPoint'])} → ${tStr(r['endPoint'])})' : ''}',
                        ),
                    ],
                    onChanged: (v) => _pickRoute(v ?? ''),
                  ),
                  'Add Route',
                  _addRoute,
                  const ValueKey('load-add-route'),
                ),
                if (tStr(route?['estimatedTime']).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Est. time: ${tStr(route!['estimatedTime'])}', style: const TextStyle(fontSize: 12, color: Tone.fg(0xFF059669))),
                  ),
              ]),
            ),
            dField('Starting point', PlaceField(controller: _start, hint: "Where you're leaving from", keyPrefix: 'load-start', busy: _locating, onBusy: busy)),
            dField('Destination',
                PlaceField(controller: _dest, hint: "Where you're delivering to", keyPrefix: 'load-dest', gpsFirst: false, busy: _locating, onBusy: busy)),
            dField(
              'Customer',
              widget.customers.isNotEmpty
                  ? AppSelect<String>(
                      key: const ValueKey('load-customer'),
                      value: _customer.isEmpty ? null : _customer,
                      hintText: 'Select customer (optional)',
                      items: [
                        for (final c in widget.customers)
                          if (c['isActive'] != false) AppSelectItem(value: tStr(c['customerName']), label: tStr(c['customerName'])),
                      ],
                      onChanged: (v) => setState(() => _customer = v ?? ''),
                    )
                  : AppInput(key: const ValueKey('load-customer-text'), controller: _customerText, hintText: 'Who is this for?'),
            ),
          ]),
          const SizedBox(height: 12),
          formSection('Other', TColors.slate500, [
            dField('Date', AppDateField(value: businessDateAsDateTime(_date), onChanged: (v) => setState(() => _date = v == null ? _date : isoDay(v)))),
            dField('Notes', AppInput(controller: _notes)),
          ]),
        ]),
      ),
      actions: dialogButtons(context, label: 'Load & Create Delivery', saving: _saving, onSave: _save, saveKey: const ValueKey('load-save')),
    );
  }
}

// ------------------------------------------------------------ reconcile

/// What the reconcile form must add up to: sold + returned + damaged + short.
num deliveryAccounted(num sold, num returned, num damaged, num short) => sold + returned + damaged + short;

class _ReconcileDialog extends StatefulWidget {
  const _ReconcileDialog({required this.session, required this.company, required this.delivery});
  final Session session;
  final Company company;
  final Map delivery;
  @override
  State<_ReconcileDialog> createState() => _ReconcileDialogState();
}

class _ReconcileDialogState extends State<_ReconcileDialog> {
  Map get _d => widget.delivery;
  num get _loaded => tNum(_d['quantityLoaded']);
  late final _sold = TextEditingController(text: tStr(_d['quantityLoaded']));
  final _returned = TextEditingController(text: '0'), _damaged = TextEditingController(text: '0'), _short = TextEditingController(text: '0');
  late final _cash = TextEditingController(text: '${_loaded * tNum(_d['unitPrice'])}');
  final _credit = TextEditingController(text: '0'), _expenses = TextEditingController(text: '0');
  bool _saving = false;

  num get _accounted => deliveryAccounted(dNum(_sold), dNum(_returned), dNum(_damaged), dNum(_short));
  bool get _balances => (_accounted - _loaded).abs() < 0.001;

  Future<void> _save() async {
    if (!_balances) return trackerToast(context, 'Sold + returned + damaged + short must equal ${tStr(_d['quantityLoaded'])}', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('${genericBase(widget.company)}/deliveries/${tIntOrNull(_d['genericDeliveryId'])}/reconcile', body: {
        'quantitySold': dNum(_sold),
        'quantityReturned': dNum(_returned),
        'quantityDamaged': dNum(_damaged),
        'quantityShort': dNum(_short),
        'cashCollected': dNum(_cash),
        'creditSales': dNum(_credit),
        'deliveryExpenses': dNum(_expenses),
        'farmId': widget.company.farmId,
      });
      if (!mounted) return;
      trackerToast(context, 'Delivery reconciled');
      Navigator.pop(context, true);
      return;
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Reconcile failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    void redo(String _) => setState(() {});
    Widget info(String a, Object? av, String b, Object? bv, [String? c, Object? cv]) => Text.rich(TextSpan(children: [
          TextSpan(text: '$a: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: '${_or(av)} · '),
          TextSpan(text: '$b: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: _or(bv)),
          if (c != null) ...[
            const TextSpan(text: ' · '),
            TextSpan(text: '$c: ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: _or(cv)),
          ],
        ]), style: const TextStyle(fontSize: 13, color: TColors.slate600));
    return AlertDialog(
      scrollable: true,
      title: Text('Reconcile — ${tStr(_d['productName'])} (${tStr(_d['quantityLoaded'])} ${tStr(_d['unit'])} loaded)'),
      content: SizedBox(
        width: 672,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              info('Driver', _d['driverName'], 'Route', _d['route'], 'Transport', _d['transportMode']),
              const SizedBox(height: 4),
              info('Customer', _d['customerName'], 'Destination', _d['destination']),
            ]),
          ),
          const SizedBox(height: 12),
          formSection('Product accounting', const Tone.bg(0xFF2563EB), [
            dField('Sold', dNumber(_sold, key: const ValueKey('rec-sold'), onChanged: redo)),
            dField('Returned', dNumber(_returned, key: const ValueKey('rec-returned'), onChanged: redo)),
            dField('Damaged', dNumber(_damaged, key: const ValueKey('rec-damaged'), onChanged: redo)),
            dField('Short / missing', dNumber(_short, key: const ValueKey('rec-short'), onChanged: redo)),
            Text(
              'Accounted: ${_fmtQty(_accounted)} / ${tStr(_d['quantityLoaded'])} loaded ${_balances ? '— balances' : '— must balance'}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _balances ? const Tone.fg(0xFF16A34A) : TColors.red600),
            ),
          ]),
          const SizedBox(height: 12),
          formSection('Money', TColors.emerald600, [
            dField('Cash collected', dNumber(_cash, key: const ValueKey('rec-cash'))),
            dField('Credit sales', dNumber(_credit)),
            dField('Delivery expenses', dNumber(_expenses)),
            dField('Expected sales (auto)',
                AppInput(key: ValueKey('rec-expected-${_sold.text}'), initialValue: fmtMoney(dNum(_sold) * tNum(_d['unitPrice'])), enabled: false)),
          ]),
        ]),
      ),
      actions: dialogButtons(context, label: 'Reconcile', saving: _saving, onSave: _save, saveKey: const ValueKey('rec-save')),
    );
  }
}

String _fmtQty(num n) => n == n.roundToDouble() ? '${n.toInt()}' : '$n';
