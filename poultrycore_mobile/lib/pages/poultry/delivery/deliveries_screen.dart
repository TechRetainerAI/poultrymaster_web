// Poultry → Operations → Delivery → Deliveries (app/poultry-driver-returns/
// page.tsx): Load vehicle; the Active loads / Returns / Reconciled / Setup
// tabs with their filters, cards and tables; record, edit, approve, cancel,
// uncancel, delete, reverse and void; reload; the five page figures.

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../shared/business_dates.dart';
import '../../shared/company_clock.dart';
import '../expenses/asset_widgets.dart' show ReasonTextPrompt;
import '../money/money_widgets.dart';
import '../reports/report_format.dart';
import '../reports/report_routes.dart' show openAppHref;
import '../sales/balances_logic.dart' show pageSlice;
import '../sales/balances_widgets.dart' show CompactPager, ListFiltersCard;
import '../trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull, jsNum;
import '../trackers/tracker_widgets.dart';
import 'delivery_detail_screen.dart';
import 'delivery_dialogs.dart';
import 'delivery_logic.dart';

class DeliveriesScreen extends StatefulWidget {
  const DeliveriesScreen({super.key, required this.session, required this.company, this.date});
  final Session session;
  final Company company;

  /// `?date=` from Daily Closing: every date filter starts on that day.
  final String? date;

  @override
  State<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends State<DeliveriesScreen> {
  List<Map> _loadings = [], _returns = [], _vehicles = [], _routes = [], _products = [], _drivers = [];
  bool _loading = true;
  String _tab = 'active';
  final _loadSearch = TextEditingController(), _retSearch = TextEditingController();
  late String _loadFrom = widget.date ?? '', _loadTo = widget.date ?? '';
  late String _retFrom = widget.date ?? '', _retTo = widget.date ?? '';
  final _f = DeliveryFilters();
  int _activePage = 1, _activeSize = 10, _recPage = 1, _recSize = 10, _retPage = 1, _retSize = 10;
  FarmMoney _fmt = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, String> get _q => {'farmId': _farmId};

  /// usePermissions().isAdmin: anyone who is not plain staff.
  bool get _isAdmin => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _fmt = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  @override
  void dispose() {
    _loadSearch.dispose();
    _retSearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _api.post('/api/Poultry/products/ensure-defaults', query: _q);
    } on ApiException {
      // best effort, as on the web
    }
    final failures = <String>[];
    Future<List<Map>?> get(String name, String path) async {
      try {
        return rowsOf(await _api.get(path, query: _q));
      } on ApiException catch (e) {
        failures.add('$name: ${e.message}');
        return null;
      }
    }

    final r = await Future.wait([
      get('loadings', '/api/Poultry/vehicle-loadings'),
      get('returns', '/api/Poultry/driver-returns'),
      get('vehicles', '/api/Poultry/vehicles'),
      get('routes', '/api/Poultry/routes'),
      get('products', '/api/Poultry/products'),
      get('drivers', '/api/Poultry/drivers'),
    ]);
    if (!mounted) return;
    setState(() {
      if (r[0] != null) _loadings = r[0]!;
      if (r[1] != null) _returns = r[1]!;
      if (r[2] != null) _vehicles = r[2]!;
      if (r[3] != null) _routes = r[3]!;
      if (r[4] != null) _products = deliverableProducts(r[4]!);
      if (r[5] != null) _drivers = r[5]!;
      _loading = false;
    });
    if (failures.length == r.length) trackerToast(context, "Couldn't load this page", description: failures.first, error: true);
  }

  // ------------------------------------------------------------ actions

  void _details(Map l) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DeliveryDetailScreen(session: widget.session, company: widget.company, loadingId: tIntOrNull(l['poultryVehicleLoadingId']) ?? 0),
      ));

  Future<void> _loadVehicle() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => LoadVehicleDialog(
        session: widget.session,
        company: widget.company,
        drivers: _drivers,
        vehicles: _vehicles,
        routes: _routes,
        products: _products,
        money: _fmt,
      ),
    );
    if (ok == true) _load();
  }

  Future<void> _openReturn(Map l, {Map? existing}) async {
    final seed = await buildReturnSeed(context,
        api: _api, farmId: _farmId, loading: l, returns: _returns, products: _products, existing: existing);
    if (seed == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => DriverReturnDialog(session: widget.session, company: widget.company, seed: seed, products: _products, money: _fmt),
    );
    if (ok == true) _load();
  }

  Map? _loadingOf(Map r) => _loadings.where((x) => tStr(x['poultryVehicleLoadingId']) == tStr(r['poultryVehicleLoadingId'])).firstOrNull;

  void _editReturn(Map r) {
    final l = _loadingOf(r);
    if (l == null) {
      trackerToast(context, 'Loading not found', description: "Can't find the delivery run this return belongs to.", error: true);
      return;
    }
    _openReturn(l, existing: r);
  }

  Future<void> _post(String path, String ok, String fail) async {
    try {
      await _api.post(path, query: _q);
      if (mounted) trackerToast(context, ok);
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, fail, description: e.message, error: true);
    }
  }

  void _cancel(Map r) => _post('/api/Poultry/driver-returns/${r['poultryDriverReturnId']}/cancel', 'Return cancelled', 'Cancel failed');

  void _uncancel(Map r) => _post('/api/Poultry/driver-returns/${r['poultryDriverReturnId']}/uncancel',
      'Return uncancelled — back to Draft. Approve to reconcile.', 'Uncancel failed');

  Future<void> _reload(Map l) async {
    try {
      await _api.post('/api/Poultry/vehicle-loadings/${l['poultryVehicleLoadingId']}/reload',
          query: {..._q, 'createdBy': widget.session.tokens.userId ?? ''});
      if (mounted) trackerToast(context, 'Delivery reloaded — a fresh run was created');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Reload failed', description: e.message, error: true);
    }
  }

  /// ConfirmDeleteDialog: the action runs inside, then the success or error toast.
  Future<void> _confirm({
    required String title,
    required String description,
    required String confirmLabel,
    String busyLabel = 'Deleting…',
    bool destructive = true,
    required String successTitle,
    required String errorTitle,
    required Future<void> Function() action,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var busy = false;
        return StatefulBuilder(builder: (ctx, set) => AlertDialog(
              title: Text(title),
              content: Text(description),
              actions: [
                TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  style: destructive ? FilledButton.styleFrom(backgroundColor: TColors.red600) : null,
                  onPressed: busy
                      ? null
                      : () async {
                          set(() => busy = true);
                          try {
                            await action();
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) trackerToast(context, successTitle);
                          } on ApiException catch (e) {
                            set(() => busy = false);
                            if (mounted) trackerToast(context, errorTitle, description: e.message, error: true);
                          }
                        },
                  child: Text(busy ? busyLabel : confirmLabel),
                ),
              ],
            ));
      },
    );
  }

  void _approve(Map r) => _confirm(
        title: 'Approve & reconcile this return?',
        description: 'This finalizes the return, updates inventory, posts sales/payments if applicable, and marks the delivery as reconciled.',
        confirmLabel: 'Approve & Reconcile',
        busyLabel: 'Working…',
        destructive: false,
        successTitle: 'Return reconciled',
        errorTitle: 'Approve & Reconcile failed',
        action: () async {
          await _api.post('/api/Poultry/driver-returns/${r['poultryDriverReturnId']}/approve',
              query: {..._q, 'approvedBy': widget.session.tokens.userId ?? ''});
          await _load();
        },
      );

  void _delete(Map r) => _confirm(
        title: 'Delete cancelled return #${tStr(r['poultryDriverReturnId'])}?',
        description:
            'This permanently removes the return header, per-product items, customer-sale rows, and delivery expense rows. Only available for Cancelled returns. The action cannot be undone.',
        confirmLabel: 'Delete return',
        successTitle: 'Cancelled return deleted',
        errorTitle: 'Delete failed',
        action: () async {
          await _api.delete('/api/Poultry/driver-returns/${r['poultryDriverReturnId']}?farmId=${Uri.encodeQueryComponent(_farmId)}');
          if (mounted) trackerToast(context, 'Cancelled return #${tStr(r['poultryDriverReturnId'])} deleted');
          await _load();
        },
      );

  void _void(Map l) {
    final expected = tNum(l['expectedCash']);
    final who = tStr(l['driverName']).isNotEmpty ? tStr(l['driverName']) : tStr(l['vehicleName']);
    _confirm(
      title: 'Void this delivery?',
      description: 'Void delivery $who (${jsNum(tNum(l['cratesLoaded']))} crates${expected != 0 ? ', expected ${_fmt(expected)}' : ''})? '
          '${tStr(l['status']) == 'Loaded' ? 'This will return the crates to warehouse stock via an Adjust transaction. Blocked if a driver return is already recorded.' : 'Draft loadings have no stock to reverse.'}',
      confirmLabel: 'Void delivery',
      successTitle: 'Delivery voided — stock returned to warehouse',
      errorTitle: 'Void failed',
      action: () async {
        await _api.post('/api/Poultry/vehicle-loadings/${l['poultryVehicleLoadingId']}/void', query: _q);
        await _load();
      },
    );
  }

  Map? _approvedReturnOf(Map l) => _returns
      .where((x) => tStr(x['poultryVehicleLoadingId']) == tStr(l['poultryVehicleLoadingId']) && tStr(x['status']) == 'Approved')
      .firstOrNull;

  Future<void> _reverse(Map r, {bool edit = false}) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => ReasonTextPrompt(
        title: edit ? 'Edit reconciled return?' : 'Reverse this reconciliation?',
        description: edit
            ? "There's no direct \"update return\" endpoint — to change a reconciled return we first reverse the current reconciliation "
                '(undoing the linked sales, payments, inventory movements, customer balance updates, and shortage/overage records), then '
                're-open the Record Return dialog pre-filled with your existing data so you can change what you need. Saving re-records and re-approves.'
            : 'This will undo the linked sales, payments, inventory movements, customer balance updates, and shortage/overage records '
                'created by this reconciliation. You can then edit and reconcile the delivery again.',
        label: edit ? 'Reason for edit' : 'Reason for reversal',
        placeholder: 'e.g. wrong customer assigned / late MoMo correction',
        confirmLabel: edit ? 'Reverse & edit' : 'Reverse',
        onSubmit: (_) async {
          try {
            await _api.post('/api/Poultry/driver-returns/${r['poultryDriverReturnId']}/reverse', query: _q);
            if (!mounted) return;
            if (edit) {
              trackerToast(context, 'Reverted — re-opening the return for edit');
              await _load();
              final l = _loadingOf(r);
              if (l != null && mounted) _openReturn(l, existing: r);
            } else {
              trackerToast(context, 'Reconciliation reversed',
                  description: 'The load is back in Active loads — click Record return on it to re-record with the new values.');
              await _load();
            }
          } on ApiException catch (e) {
            if (mounted) trackerToast(context, edit ? 'Edit failed' : 'Reverse failed', description: e.message, error: true);
          }
        },
      ),
    );
  }

  void _reverseLoading(Map l) {
    final r = _approvedReturnOf(l);
    if (r == null) {
      trackerToast(context, 'No approved return found',
          description: 'This loading is reconciled but has no Approved return row to reverse.', error: true);
      return;
    }
    _reverse(r);
  }

  void _editReconciled(Map l) {
    final r = _approvedReturnOf(l);
    if (r == null) {
      trackerToast(context, 'No approved return found',
          description: 'This loading is reconciled but has no Approved return row to edit.', error: true);
      return;
    }
    _reverse(r, edit: true);
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-driver-returns');
    final loadedCount = _loadings.where((l) => l['status'] == 'Loaded').length;
    final reconciledCount = _loadings.where((l) => l['status'] == 'Reconciled').length;
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);

    Widget tabButton(String key, String label) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Material(
              color: _tab == key ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() => _tab = key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _tab == key ? TColors.slate900 : TColors.slate600)),
                ),
              ),
            ),
          ),
        );

    Widget kpi(String label, String value) => TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Deliveries')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.local_shipping_outlined, size: 24, color: TColors.sky700),
              SizedBox(width: 8),
              Text('Deliveries', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900)),
            ]),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              onPressed: _loadVehicle,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Load vehicle'),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: TColors.slate100, borderRadius: BorderRadius.circular(8)),
              child: Column(children: [
                Row(children: [tabButton('active', 'Active loads ($loadedCount)'), tabButton('returns', 'Returns (${_returns.length})')]),
                Row(children: [tabButton('reconciled', 'Reconciled ($reconciledCount)'), tabButton('setup', 'Setup')]),
              ]),
            ),
            const SizedBox(height: 12),
            ...switch (_tab) {
              'active' => _activeTab(),
              'returns' => _returnsTab(),
              'reconciled' => _reconciledTab(),
              _ => [_setupTab()],
            },
            const SizedBox(height: 16),
            twoUp([
              kpi('Vehicles out', '$loadedCount'),
              kpi('Returns today', '${_returns.where((r) => tStr(r['returnDate']).startsWith(today)).length}'),
              kpi('Total shortages', _fmt(_returns.fold<num>(0, (s, r) => s + tNum(r['shortageAmount'])))),
              kpi('Active vehicles', '${_vehicles.where((v) => v['status'] == 'Active').length}'),
              kpi('Active drivers', '${_drivers.where((d) => d['isActive'] == true).length}'),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _dropdowns(List<String> statusOptions) {
    Widget sel(String value, String all, List<(String, String)> opts, ValueChanged<String> on) => SizedBox(
          width: 150,
          child: AppSelect<String>(
            value: value,
            hintText: all,
            items: [AppSelectItem(value: 'ALL', label: all), for (final (v, l) in opts) AppSelectItem(value: v, label: l)],
            onChanged: (v) => setState(() {
              on(v ?? 'ALL');
              _activePage = _recPage = _retPage = 1;
            }),
          ),
        );
    return Wrap(spacing: 8, runSpacing: 8, children: [
      sel(_f.driver, 'All drivers',
          [for (final d in _drivers) if (d['isActive'] == true) (tStr(d['poultryDriverId']), tStr(d['driverName']))], (v) => _f.driver = v),
      sel(_f.vehicle, 'All vehicles',
          [for (final v in _vehicles) if (v['status'] == 'Active') (tStr(v['poultryVehicleId']), tStr(v['vehicleName']))], (v) => _f.vehicle = v),
      sel(_f.route, 'All routes', [for (final r in _routes) (tStr(r['poultryRouteId']), tStr(r['routeName']))], (v) => _f.route = v),
      sel(_f.status, 'All statuses', [for (final s in statusOptions) (s, s)], (v) => _f.status = v),
    ]);
  }

  Widget _loadingFilters(List<String> statusOptions) => ListFiltersCard(
        search: _loadSearch,
        searchPlaceholder: 'Search driver, vehicle or route',
        onSearch: () => setState(() => _activePage = _recPage = 1),
        from: _loadFrom,
        to: _loadTo,
        onDates: (f, t) => setState(() {
          _loadFrom = f;
          _loadTo = t;
          _activePage = _recPage = 1;
        }),
        onClear: () => setState(() {
          _loadSearch.clear();
          _loadFrom = _loadTo = '';
        }),
        extras: [_dropdowns(statusOptions)],
      );

  Widget _emptyCard(String text) => TCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate500)),
        ),
      );

  List<Widget> _activeTab() {
    final rows = visibleLoadings(_loadings, _f, search: _loadSearch.text, from: _loadFrom, to: _loadTo)
        .where((l) => l['status'] == 'Loaded' || l['status'] == 'Draft')
        .toList();
    return [
      _loadingFilters(const ['Draft', 'Loaded', 'Returned', 'Reconciled', 'Cancelled']),
      const SizedBox(height: 12),
      if (_loading)
        const TCard(child: Text('Loading…', style: TextStyle(color: TColors.slate500)))
      else if (!_loadings.any((l) => l['status'] == 'Loaded' || l['status'] == 'Draft'))
        TCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text.rich(
              const TextSpan(children: [
                TextSpan(text: 'No active loads. Click '),
                TextSpan(text: 'Load vehicle', style: TextStyle(fontWeight: FontWeight.w500)),
                TextSpan(text: ' above to dispatch a delivery.'),
              ]),
              textAlign: TextAlign.center,
              style: const TextStyle(color: TColors.slate500),
            ),
          ),
        )
      else
        TCard(child: _deliveriesList(rows, _activePage, _activeSize, (p) => setState(() => _activePage = p), (s) => setState(() {
              _activeSize = s;
              _activePage = 1;
            }), showActions: true)),
    ];
  }

  List<Widget> _reconciledTab() {
    final rows = visibleLoadings(_loadings, _f, search: _loadSearch.text, from: _loadFrom, to: _loadTo)
        .where((l) => l['status'] == 'Reconciled')
        .toList();
    return [
      _loadingFilters(const ['Reconciled']),
      const SizedBox(height: 12),
      if (!_loadings.any((l) => l['status'] == 'Reconciled'))
        _emptyCard('No reconciled loadings yet.')
      else
        TCard(child: _deliveriesList(rows, _recPage, _recSize, (p) => setState(() => _recPage = p), (s) => setState(() {
              _recSize = s;
              _recPage = 1;
            }), showActions: false, reconciled: true)),
    ];
  }

  Widget _statusBadge(Object? status) {
    final (bg, fg) = loadStatusTone(status);
    return TBadge(tStr(status), bg: bg, fg: fg);
  }

  /// DeliveriesTable.
  Widget _deliveriesList(List<Map> rows, int page, int size, ValueChanged<int> onPage, ValueChanged<int> onSize,
      {required bool showActions, bool reconciled = false}) {
    final pageRows = pageSlice(rows, page, size);
    String date(Map l) => fmtDateTime(l['loadDate'], l, _offset);
    String dash(Object? v) => tStr(v).isEmpty ? '—' : tStr(v);
    String st(Map l) => tStr(l['status']);
    return MobileCardList<Map>(
      items: pageRows,
      keyOf: (l) => tStr(l['poultryVehicleLoadingId']),
      primary: (l) => '${dash(l['driverName'])} · ${date(l)}',
      onPrimary: _details,
      secondaryBuilder: (l) => Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(dash(l['vehicleName'])),
        _statusBadge(l['status']),
      ]),
      details: (l) => [
        ('Date', date(l)),
        ('Driver', dash(l['driverName'])),
        ('Vehicle', dash(l['vehicleName'])),
        ('Route', dash(l['routeName'])),
        ('Loaded (crates)', jsNum(tNum(l['cratesLoaded']))),
        ('Expected', _fmt(tNum(l['expectedCash']))),
        ('Status', st(l)),
      ],
      actions: (l) => [
        OutlinedButton(onPressed: () => _details(l), child: const Text('View details')),
        if (showActions && st(l) == 'Loaded') OutlinedButton(onPressed: () => _openReturn(l), child: const Text('Record return')),
        if (showActions && (st(l) == 'Loaded' || st(l) == 'Draft')) OutlinedButton(onPressed: () => _reload(l), child: const Text('Reload')),
        if (showActions && (st(l) == 'Loaded' || st(l) == 'Draft'))
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: TColors.red200)),
            onPressed: () => _void(l),
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('Void'),
          ),
        if (reconciled && st(l) == 'Reconciled')
          OutlinedButton.icon(onPressed: () => _editReconciled(l), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
        if (reconciled && st(l) == 'Reconciled')
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: TColors.amber700, side: const BorderSide(color: TColors.amber200)),
            onPressed: () => _reverseLoading(l),
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Reverse'),
          ),
      ],
      pager: CompactPager(total: rows.length, page: page, pageSize: size, onPage: onPage, onPageSize: onSize),
      table: (items) => TrackerTable(
        columns: const [
          TCol('Date', width: 150),
          TCol('Driver', width: 120),
          TCol('Vehicle', width: 120),
          TCol('Route', width: 120),
          TCol('Loaded (crates)', right: true, width: 110),
          TCol('Expected', right: true, width: 110),
          TCol('Status', width: 100),
          TCol('Actions', width: 240),
        ],
        rows: [
          for (final l in items)
            [
              InkWell(onTap: () => _details(l), child: Text(date(l), style: const TextStyle(color: TColors.sky700))),
              cellText(dash(l['driverName'])),
              cellText(dash(l['vehicleName'])),
              cellText(dash(l['routeName'])),
              cellText(jsNum(tNum(l['cratesLoaded']))),
              cellText(_fmt(tNum(l['expectedCash']))),
              Align(alignment: Alignment.centerLeft, child: _statusBadge(l['status'])),
              Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _icon('View details', Icons.visibility_outlined, () => _details(l)),
                if (showActions && st(l) == 'Loaded') FilledButton(onPressed: () => _openReturn(l), child: const Text('Record return')),
                if (showActions && (st(l) == 'Loaded' || st(l) == 'Draft'))
                  _icon('Reload — clone into a fresh run', Icons.refresh, () => _reload(l), color: TColors.sky700),
                if (showActions && (st(l) == 'Loaded' || st(l) == 'Draft'))
                  _icon('Void this delivery (reverses stock)', Icons.cancel_outlined, () => _void(l), color: TColors.rose500),
                if (reconciled && st(l) == 'Reconciled')
                  _icon('Edit this reconciled return (reverses + re-opens for edit)', Icons.edit_outlined, () => _editReconciled(l), color: TColors.sky700),
                if (reconciled && st(l) == 'Reconciled') _icon('Reverse reconciliation', Icons.undo, () => _reverseLoading(l), color: TColors.amber600),
              ]),
            ],
        ],
      ),
    );
  }

  Widget _icon(String tip, IconData i, VoidCallback onTap, {Color? color}) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        padding: EdgeInsets.zero,
        icon: Icon(i, size: 18, color: color),
        onPressed: onTap,
      );

  List<Widget> _returnsTab() {
    final rows = visibleReturns(_returns, _loadings, _f, search: _retSearch.text, from: _retFrom, to: _retTo);
    final pageRows = pageSlice(rows, _retPage, _retSize);
    String dash(Object? v) => tStr(v).isEmpty ? '—' : tStr(v);
    String date(Map r) => fmtDateTime(r['returnDate'], r, _offset);
    String st(Map r) => tStr(r['status']);
    return [
      ListFiltersCard(
        search: _retSearch,
        searchPlaceholder: 'Search driver, vehicle or route',
        onSearch: () => setState(() => _retPage = 1),
        from: _retFrom,
        to: _retTo,
        onDates: (f, t) => setState(() {
          _retFrom = f;
          _retTo = t;
          _retPage = 1;
        }),
        onClear: () => setState(() {
          _retSearch.clear();
          _retFrom = _retTo = '';
        }),
        extras: [_dropdowns(const ['Draft', 'Approved', 'Cancelled'])],
      ),
      const SizedBox(height: 12),
      if (_returns.isEmpty)
        _emptyCard('No driver returns recorded yet.')
      else
        TCard(
          child: MobileCardList<Map>(
            items: pageRows,
            keyOf: (r) => tStr(r['poultryDriverReturnId']),
            primary: (r) => 'Delivery #${tStr(r['poultryVehicleLoadingId'])} · ${tStr(r['vehicleName']).isEmpty ? 'Vehicle —' : tStr(r['vehicleName'])} · '
                '${jsNum(tNum(r['cratesSold']))} crates sold',
            secondaryBuilder: (r) => Text.rich(TextSpan(children: [
              TextSpan(text: date(r)),
              if (tStr(r['driverName']).isNotEmpty) TextSpan(text: ' · ${tStr(r['driverName'])}'),
              if (tStr(r['routeName']).isNotEmpty) TextSpan(text: ' · ${tStr(r['routeName'])}'),
              if (tNum(r['shortageAmount']) > 0)
                TextSpan(text: ' · Short ${_fmt(tNum(r['shortageAmount']))}', style: const TextStyle(color: TColors.rose600)),
            ])),
            details: (r) => [
              ('Delivery #', tStr(r['poultryVehicleLoadingId'])),
              ('Date', date(r)),
              ('Vehicle', dash(r['vehicleName'])),
              ('Driver', dash(r['driverName'])),
              ('Route', dash(r['routeName'])),
              ('Status', st(r)),
              ('Sold (crates)', jsNum(tNum(r['cratesSold']))),
              ('Returned (crates)', jsNum(tNum(r['cratesReturned']))),
              ('Damaged (crates)', jsNum(tNum(r['cratesDamaged']))),
              ('Cash', _fmt(tNum(r['cashCollected']))),
              ('MoMo', _fmt(tNum(r['moMoCollected']))),
              ('Credit', _fmt(tNum(r['creditSalesAmount']))),
              ('Shortage', _fmt(tNum(r['shortageAmount']))),
            ],
            detailColor: (r, label) => label == 'Shortage' && tNum(r['shortageAmount']) > 0 ? TColors.rose600 : null,
            actions: (r) => [
              OutlinedButton(onPressed: () => _detailsOfReturn(r), child: const Text('View details')),
              if (st(r) == 'Draft')
                OutlinedButton.icon(onPressed: () => _editReturn(r), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
              if (st(r) == 'Draft')
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: TColors.green700, side: const BorderSide(color: Color(0xFFBBF7D0))),
                  onPressed: () => _approve(r),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Approve & Reconcile'),
                ),
              if (st(r) == 'Draft')
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: TColors.red200)),
                  onPressed: () => _cancel(r),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancel'),
                ),
              if (st(r) == 'Approved')
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: TColors.amber700, side: const BorderSide(color: TColors.amber200)),
                  onPressed: () => _reverse(r),
                  icon: const Icon(Icons.undo, size: 16),
                  label: const Text('Reverse'),
                ),
              if (st(r) == 'Cancelled')
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: TColors.emerald700, side: const BorderSide(color: TColors.emerald200)),
                  onPressed: () => _uncancel(r),
                  icon: const Icon(Icons.undo, size: 16),
                  label: const Text('Uncancel'),
                ),
              if (st(r) == 'Cancelled' && _isAdmin)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: TColors.red200)),
                  onPressed: () => _delete(r),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete'),
                ),
            ],
            pager: CompactPager(
              total: rows.length,
              page: _retPage,
              pageSize: _retSize,
              onPage: (p) => setState(() => _retPage = p),
              onPageSize: (s) => setState(() {
                _retSize = s;
                _retPage = 1;
              }),
            ),
            table: (items) => TrackerTable(
              columns: const [
                TCol('Delivery #', width: 90),
                TCol('Date', width: 150),
                TCol('Vehicle', width: 120),
                TCol('Driver', width: 120),
                TCol('Status', width: 100),
                TCol('Sold (crates)', right: true, width: 100),
                TCol('Returned (crates)', right: true, width: 120),
                TCol('Damaged (crates)', right: true, width: 120),
                TCol('Cash', right: true, width: 110),
                TCol('MoMo', right: true, width: 110),
                TCol('Credit', right: true, width: 110),
                TCol('Shortage', right: true, width: 110),
                TCol('Actions', width: 200),
              ],
              rows: [
                for (final r in items)
                  [
                    cellText('#${tStr(r['poultryVehicleLoadingId'])}', bold: true),
                    cellText(date(r)),
                    cellText(dash(r['vehicleName']), bold: true),
                    cellText(dash(r['driverName'])),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Builder(builder: (_) {
                        final (bg, fg) = returnStatusTone(r['status']);
                        return TBadge(st(r), bg: bg, fg: fg);
                      }),
                    ),
                    cellText(jsNum(tNum(r['cratesSold']))),
                    cellText(jsNum(tNum(r['cratesReturned']))),
                    cellText(jsNum(tNum(r['cratesDamaged']))),
                    cellText(_fmt(tNum(r['cashCollected']))),
                    cellText(_fmt(tNum(r['moMoCollected']))),
                    cellText(_fmt(tNum(r['creditSalesAmount']))),
                    cellText(_fmt(tNum(r['shortageAmount'])), color: tNum(r['shortageAmount']) > 0 ? TColors.rose600 : null),
                    Wrap(alignment: WrapAlignment.end, children: [
                      _icon('View details', Icons.visibility_outlined, () => _detailsOfReturn(r)),
                      if (st(r) == 'Draft')
                        _icon('Edit this Draft (pre-fills the Record Return dialog)', Icons.edit_outlined, () => _editReturn(r), color: TColors.sky700),
                      if (st(r) == 'Draft') _icon('Approve & Reconcile', Icons.check_circle_outline, () => _approve(r), color: TColors.green700),
                      if (st(r) == 'Draft') _icon('Cancel return', Icons.cancel_outlined, () => _cancel(r), color: TColors.rose500),
                      if (st(r) == 'Approved') _icon('Reverse reconciliation', Icons.undo, () => _reverse(r), color: TColors.amber600),
                      if (st(r) == 'Cancelled')
                        _icon('Uncancel (back to Draft so it can be re-approved)', Icons.undo, () => _uncancel(r), color: TColors.emerald600),
                      if (st(r) == 'Cancelled' && _isAdmin)
                        _icon('Delete this cancelled return (admin only, hard delete)', Icons.delete_outline, () => _delete(r), color: TColors.red600),
                    ]),
                  ],
              ],
            ),
          ),
        ),
    ];
  }

  void _detailsOfReturn(Map r) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            DeliveryDetailScreen(session: widget.session, company: widget.company, loadingId: tIntOrNull(r['poultryVehicleLoadingId']) ?? 0),
      ));

  Widget _setupTab() {
    Widget link(IconData icon, String title, String sub, String href) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(side: const BorderSide(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => openAppHref(context, widget.session, widget.company, href, label: title),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(icon, size: 16, color: TColors.sky700),
                    const SizedBox(width: 8),
                    Flexible(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900))),
                  ]),
                  const SizedBox(height: 4),
                  Text(sub, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
              ),
            ),
          ),
        );
    return TCard(
      child: Column(children: [
        link(Icons.groups_outlined, 'Drivers', '${_drivers.where((d) => d['isActive'] == true).length} active · manage drivers, base pay, commissions',
            '/poultry-drivers'),
        link(Icons.local_shipping_outlined, 'Vehicles',
            '${_vehicles.where((v) => v['status'] == 'Active').length} active · manage vehicles and capacity', '/poultry-vehicles'),
        link(Icons.place_outlined, 'Routes', '${_routes.length} configured · manage delivery routes', '/poultry-routes'),
        link(Icons.local_shipping_outlined, 'Driver collection report',
            'Per-driver per-product loaded / sold / returned / damaged with cash + shortage roll-up', '/poultry-driver-report'),
      ]),
    );
  }
}

/// `/poultry-driver-returns?date=…` and `/poultry-driver-returns/{id}`.
Widget? deliveriesScreenForHref(String href, Session s, Company c) {
  final uri = Uri.tryParse(href);
  if (uri == null) return null;
  final m = RegExp(r'^/poultry-driver-returns/(\d+)$').firstMatch(uri.path);
  if (m != null) return DeliveryDetailScreen(session: s, company: c, loadingId: int.parse(m[1]!));
  if (uri.path == '/poultry-driver-returns' && uri.query.isNotEmpty) {
    return DeliveriesScreen(session: s, company: c, date: toBusinessDate(uri.queryParameters['date']));
  }
  return null;
}
