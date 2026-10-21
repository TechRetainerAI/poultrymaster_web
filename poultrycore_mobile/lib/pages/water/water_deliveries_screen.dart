import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/expenses/asset_widgets.dart' show ReasonTextPrompt;
import '../poultry/expenses/deferred_costs_screen.dart' show qtyFmt;
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_format.dart';
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart';
import '../shared/company_clock.dart';
import '../shared/reason_select.dart' show reversalReasons;
import 'water_driver_return_screen.dart';
import 'water_raw_materials_screen.dart' show filterWaterRows;

/// Water → Operations → Delivery → Deliveries, as `app/water-driver-returns/
/// page.tsx`: Load vehicle (create / edit a delivery run), the Active loads /
/// Returns / Reconciled / Setup tabs with their filters and actions, the page
/// figures, the delivery-run page (`[id]/page.tsx`) and the Driver collection
/// report (`app/water-driver-report/page.tsx`).

String _today() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

Widget waterLoadStatusBadge(Object? status) {
  final s = tStr(status);
  final (bg, fg) = switch (s) {
    'Loaded' => (TColors.blue100, const Color(0xFF1D4ED8)),
    'Returned' => (TColors.amber100, TColors.amber700),
    'Reconciled' || 'Approved' => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
    _ => (TColors.slate100, TColors.slate700),
  };
  return TBadge(s, bg: bg, fg: fg);
}

Widget waterReturnStatusBadge(Object? status) {
  final s = tStr(status);
  final (bg, fg) = switch (s) {
    'Approved' => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
    'Cancelled' => (TColors.slate100, TColors.slate600),
    _ => (TColors.amber100, TColors.amber700),
  };
  return TBadge(s, bg: bg, fg: fg);
}

/// The driver / vehicle / route / status dropdown filters.
class WaterDeliveryFilters {
  String driver = 'ALL', vehicle = 'ALL', route = 'ALL', status = 'ALL';
  bool matches({Object? driverId, Object? vehicleId, Object? routeId, Object? status}) {
    if (driver != 'ALL' && tStr(driverId) != driver) return false;
    if (vehicle != 'ALL' && tStr(vehicleId) != vehicle) return false;
    if (route != 'ALL' && tStr(routeId) != route) return false;
    if (this.status != 'ALL' && tStr(status) != this.status) return false;
    return true;
  }
}

/// A return's current row for a loading: non-Cancelled first, then the latest.
Map? waterCurrentReturn(List<Map> returns, int loadingId) {
  final rows = [for (final r in returns) if (tIntOrNull(r['waterVehicleLoadingId']) == loadingId) r]
    ..sort((a, b) {
      final ac = tStr(a['status']) == 'Cancelled' ? 1 : 0, bc = tStr(b['status']) == 'Cancelled' ? 1 : 0;
      if (ac != bc) return ac - bc;
      return (tIntOrNull(b['waterDriverReturnId']) ?? 0) - (tIntOrNull(a['waterDriverReturnId']) ?? 0);
    });
  return rows.firstOrNull;
}

// ------------------------------------------------------------ deliveries

class WaterDeliveriesScreen extends StatefulWidget {
  const WaterDeliveriesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterDeliveriesScreen> createState() => _WaterDeliveriesScreenState();
}

class _WaterDeliveriesScreenState extends State<WaterDeliveriesScreen> {
  List<Map> _loadings = [], _returns = [], _vehicles = [], _routes = [], _products = [], _drivers = [], _staff = [], _customers = [];
  bool _loading = true;
  String _tab = 'active';
  final _lSearch = TextEditingController(), _rSearch = TextEditingController();
  String _lFrom = '', _lTo = '', _rFrom = '', _rTo = '';
  final _f = WaterDeliveryFilters();
  final Map<String, int> _page = {}, _size = {};
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, String> get _q => {'farmId': _farmId};
  String get _user => widget.session.tokens.userId ?? '';

  /// usePermissions().isAdmin: anyone who is not plain staff.
  bool get _isAdmin => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  @override
  void dispose() {
    _lSearch.dispose();
    _rSearch.dispose();
    super.dispose();
  }

  /// Each list loads on its own; only a total failure shows a banner.
  Future<void> _load() async {
    setState(() => _loading = true);
    Future<List<Map>?> one(String path) async {
      try {
        return rowsOf(await _api.get(path, query: _q));
      } on ApiException {
        return null;
      }
    }

    final r = await Future.wait([
      one('/api/Water/vehicle-loadings'), one('/api/Water/driver-returns'), one('/api/Water/vehicles'), one('/api/Water/routes'),
      one('/api/Water/products'), one('/api/Water/drivers'), one('/api/Water/staff'), one('/api/Water/customers'),
    ]);
    if (!mounted) return;
    setState(() {
      if (r[0] != null) _loadings = r[0]!;
      if (r[1] != null) _returns = r[1]!;
      if (r[2] != null) _vehicles = r[2]!;
      if (r[3] != null) _routes = r[3]!;
      // Only finished goods can be loaded onto a delivery.
      if (r[4] != null) _products = [for (final p in r[4]!) if ((tStr(p['productType']).isEmpty ? 'FinishedGood' : tStr(p['productType'])) == 'FinishedGood') p];
      if (r[5] != null) _drivers = r[5]!;
      if (r[6] != null) _staff = r[6]!;
      if (r[7] != null) _customers = r[7]!;
      _loading = false;
    });
    if (r.every((x) => x == null)) trackerToast(context, "Couldn't load this page", error: true);
  }

  int _lid(Map l) => tIntOrNull(l['waterVehicleLoadingId']) ?? 0;
  int _rid(Map r) => tIntOrNull(r['waterDriverReturnId']) ?? 0;

  Map? _loadingOf(int id) => _loadings.where((l) => _lid(l) == id).firstOrNull;

  Future<void> _push(Widget screen) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (ok == true) await _load();
  }

  void _view(int loadingId) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WaterDeliveryRunScreen(session: widget.session, company: widget.company, loadingId: loadingId),
      ));

  Future<void> _loadForm([Map? editing]) => _push(WaterLoadVehicleScreen(
        session: widget.session,
        company: widget.company,
        editing: editing,
        drivers: _drivers,
        vehicles: _vehicles,
        routes: _routes,
        products: _products,
        staff: _staff,
      ));

  Future<void> _returnForm(Map loading, [Map? existing]) => _push(WaterDriverReturnScreen(
        session: widget.session,
        company: widget.company,
        loading: loading,
        products: _products,
        customers: _customers,
        existing: existing,
      ));

  /// One open return per delivery: continue its draft, or refuse a reconciled one.
  Future<void> _recordReturn(Map l) async {
    final existing = _returns.where((r) => tIntOrNull(r['waterVehicleLoadingId']) == _lid(l) && tStr(r['status']) != 'Cancelled').firstOrNull;
    if (existing != null) {
      if (tStr(existing['status']) == 'Draft') {
        trackerToast(context, "Continuing this delivery's draft return", description: 'Edit the figures and Approve & Reconcile when ready.');
        return _returnForm(l, existing);
      }
      return trackerToast(context, 'This delivery is already reconciled', description: 'Reverse it from the Reconciled tab to make changes.', error: true);
    }
    return _returnForm(l);
  }

  Future<void> _editDraftReturn(Map r) async {
    final l = _loadingOf(tIntOrNull(r['waterVehicleLoadingId']) ?? 0);
    if (l == null) return trackerToast(context, 'Loading not found', description: "Can't find the delivery run this return belongs to.", error: true);
    return _returnForm(l, r);
  }

  Future<void> _void(Map l) async {
    final ok = await confirmDelete(
      context,
      title: 'Void this delivery?',
      description:
          'Void delivery ${tStr(l['driverName']).isNotEmpty ? tStr(l['driverName']) : tStr(l['vehicleName'])} (${tStr(l['bagsLoaded'])} bags${tNum(l['expectedCash']) != 0 ? ', expected ${_gh(tNum(l['expectedCash']))}' : ''})? ${tStr(l['status']) == 'Loaded' ? 'This will return the bags to warehouse stock via an Adjust transaction. Blocked if a driver return is already recorded.' : 'Draft loadings have no stock to reverse.'}',
      confirmLabel: 'Void delivery',
    );
    if (!ok) return;
    try {
      await _api.post('/api/Water/vehicle-loadings/${_lid(l)}/void', query: {..._q, 'voidedBy': _user}, body: {'reason': null});
      if (mounted) trackerToast(context, 'Delivery voided — stock returned to warehouse');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Void failed', description: e.message, error: true);
    }
  }

  Future<void> _approve(Map r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve & reconcile this return?'),
        content: const Text('This finalizes the return, updates inventory, posts sales/payments if applicable, and marks the delivery as reconciled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve & Reconcile')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.post('/api/Water/driver-returns/${_rid(r)}/approve-reconcile', query: {..._q, 'approvedBy': _user});
      if (mounted) trackerToast(context, 'Return reconciled');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Approve & Reconcile failed', description: e.message, error: true);
    }
  }

  Future<void> _simple(String path, String ok, String fail) async {
    try {
      await _api.post(path, query: _q);
      if (mounted) trackerToast(context, ok);
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, fail, description: e.message, error: true);
    }
  }

  Future<void> _deleteReturn(Map r) async {
    final ok = await confirmDelete(
      context,
      title: 'Delete cancelled return #${_rid(r)}?',
      description:
          'This permanently removes the return header, per-product items, customer-sale rows, and delivery expense rows. Only available for Cancelled returns. The action cannot be undone.',
      confirmLabel: 'Delete return',
    );
    if (!ok) return;
    try {
      await _api.delete('/api/Water/driver-returns/${_rid(r)}', query: _q);
      if (mounted) trackerToast(context, 'Cancelled return #${_rid(r)} deleted');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Delete failed', description: e.message, error: true);
    }
  }

  /// Reverse, or (edit) reverse and reopen the return with what was recorded.
  Future<void> _reverse(Map r, {bool edit = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ReasonTextPrompt(
        title: edit ? 'Edit reconciled return?' : 'Reverse this reconciliation?',
        description: edit
            ? "There's no direct \"update return\" endpoint — to change a reconciled return we first reverse the current reconciliation (undoing the linked sales, payments, inventory movements, customer balance updates, and shortage/overage records), then re-open the Record Return dialog pre-filled with your existing data so you can change what you need. Saving re-records and re-approves."
            : 'This will undo the linked sales, payments, inventory movements, customer balance updates, and shortage/overage records created by this reconciliation. You can then edit and reconcile the delivery again.',
        label: edit ? 'Reason for edit' : 'Reason for reversal',
        options: reversalReasons,
        placeholder: 'e.g. wrong customer assigned / late MoMo correction',
        confirmLabel: edit ? 'Reverse & edit' : 'Reverse',
        onSubmit: (reason) async {
          try {
            await _api.post('/api/Water/driver-returns/${_rid(r)}/reverse', query: {..._q, 'reversedBy': _user}, body: {'reason': reason});
          } on ApiException catch (e) {
            if (mounted) trackerToast(context, edit ? 'Edit failed' : 'Reverse failed', description: e.message, error: true);
            rethrow;
          }
        },
      ),
    );
    if (ok != true || !mounted) return;
    if (edit) {
      trackerToast(context, 'Reverted — re-opening the return for edit');
      await _load();
      final l = _loadingOf(tIntOrNull(r['waterVehicleLoadingId']) ?? 0);
      if (l != null && mounted) await _returnForm(l, r);
    } else {
      trackerToast(context, 'Reconciliation reversed',
          description: 'The load is back in Active loads — click Record return on it to re-record with the new values.');
      await _load();
    }
  }

  Map? _approvedReturn(Map l) =>
      _returns.where((r) => tIntOrNull(r['waterVehicleLoadingId']) == _lid(l) && tStr(r['status']) == 'Approved').firstOrNull;

  void _reconciledAction(Map l, {required bool edit}) {
    final r = _approvedReturn(l);
    if (r == null) {
      return trackerToast(context, 'No approved return found',
          description: edit ? 'This loading is reconciled but has no Approved return row to edit.' : 'This loading is reconciled but has no Approved return row to reverse.',
          error: true);
    }
    _reverse(r, edit: edit);
  }

  // ------------------------------------------------------------ lists

  List<Map> get _visibleLoadings => filterWaterRows(_loadings, const ['driverName', 'vehicleName', 'routeName'],
          search: _lSearch.text, dateKey: 'loadDate', from: _lFrom, to: _lTo)
      .where((l) => _f.matches(driverId: l['waterDriverId'], vehicleId: l['waterVehicleId'], routeId: l['waterRouteId'], status: l['status']))
      .toList();

  List<Map> get _visibleReturns => filterWaterRows(_returns, const ['driverName', 'vehicleName', 'routeName'],
          search: _rSearch.text, dateKey: 'returnDate', from: _rFrom, to: _rTo)
      .where((r) {
        final p = _loadingOf(tIntOrNull(r['waterVehicleLoadingId']) ?? 0);
        return _f.matches(driverId: p?['waterDriverId'], vehicleId: p?['waterVehicleId'], routeId: p?['waterRouteId'], status: r['status']);
      })
      .toList();

  List<Widget> _dropdowns(List<String> statuses) => [
        AppSelect<String>(
          value: _f.driver,
          hintText: 'All drivers',
          items: [
            const AppSelectItem(value: 'ALL', label: 'All drivers'),
            for (final d in _drivers) if (d['isActive'] == true) AppSelectItem(value: tStr(d['waterDriverId']), label: tStr(d['driverName'])),
          ],
          onChanged: (v) => setState(() => _f.driver = v ?? 'ALL'),
        ),
        AppSelect<String>(
          value: _f.vehicle,
          hintText: 'All vehicles',
          items: [
            const AppSelectItem(value: 'ALL', label: 'All vehicles'),
            for (final v in _vehicles) if (tStr(v['status']) == 'Active') AppSelectItem(value: tStr(v['waterVehicleId']), label: tStr(v['vehicleName'])),
          ],
          onChanged: (v) => setState(() => _f.vehicle = v ?? 'ALL'),
        ),
        AppSelect<String>(
          value: _f.route,
          hintText: 'All routes',
          items: [
            const AppSelectItem(value: 'ALL', label: 'All routes'),
            for (final r in _routes) AppSelectItem(value: tStr(r['waterRouteId']), label: tStr(r['routeName'])),
          ],
          onChanged: (v) => setState(() => _f.route = v ?? 'ALL'),
        ),
        AppSelect<String>(
          value: statuses.contains(_f.status) ? _f.status : 'ALL',
          hintText: 'All statuses',
          items: [const AppSelectItem(value: 'ALL', label: 'All statuses'), for (final s in statuses) AppSelectItem(value: s, label: s)],
          onChanged: (v) => setState(() => _f.status = v ?? 'ALL'),
        ),
      ];

  ListFiltersCard _loadingFilters(List<String> statuses) => ListFiltersCard(
        search: _lSearch,
        searchPlaceholder: 'Search driver, vehicle or route',
        onSearch: () => setState(() {}),
        from: _lFrom,
        to: _lTo,
        onDates: (f, t) => setState(() {
          _lFrom = f;
          _lTo = t;
        }),
        onClear: () => setState(() {
          _lSearch.clear();
          _lFrom = '';
          _lTo = '';
        }),
        extras: _dropdowns(statuses),
      );

  CompactPager _pager(String key, int total) => CompactPager(
        total: total,
        page: _page[key] ?? 1,
        pageSize: _size[key] ?? 10,
        onPage: (p) => setState(() => _page[key] = p),
        onPageSize: (v) => setState(() {
          _size[key] = v;
          _page[key] = 1;
        }),
      );

  List<Map> _slice(String key, List<Map> rows) {
    final size = _size[key] ?? 10;
    if (((_page[key] ?? 1) - 1) * size >= rows.length) _page[key] = 1;
    return pageSlice(rows, _page[key] ?? 1, size);
  }

  Widget _box(Widget child) => Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: child,
      );

  Widget _empty(Widget t) => Padding(padding: const EdgeInsets.all(32), child: Center(child: t));

  /// The loadings list used by the Active and Reconciled tabs.
  Widget _deliveries(String key, List<Map> rows, {required bool showActions}) {
    final reconciledTab = !showActions;
    List<Widget> actions(Map l) {
      final st = tStr(l['status']);
      final open = st == 'Loaded' || st == 'Draft';
      return [
        OutlinedButton(onPressed: () => _view(_lid(l)), child: const Text('View details')),
        if (showActions && st == 'Loaded') OutlinedButton(onPressed: () => _recordReturn(l), child: const Text('Record return')),
        if (showActions && open) OutlinedButton(onPressed: () => _loadForm(l), child: const Text('Reload / edit')),
        if (showActions && open)
          OutlinedButton.icon(
            onPressed: () => _void(l),
            style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: Color(0xFFFECACA))),
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('Void'),
          ),
        if (reconciledTab && st == 'Reconciled')
          OutlinedButton.icon(onPressed: () => _reconciledAction(l, edit: true), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
        if (reconciledTab && st == 'Reconciled')
          OutlinedButton.icon(
            onPressed: () => _reconciledAction(l, edit: false),
            style: OutlinedButton.styleFrom(foregroundColor: TColors.amber700, side: const BorderSide(color: Color(0xFFFDE68A))),
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Reverse'),
          ),
      ];
    }

    return MobileCardList<Map>(
      striped: true,
      items: _slice(key, rows),
      keyOf: (l) => '${_lid(l)}',
      primary: (l) => '${tStr(l['driverName']).isEmpty ? '—' : tStr(l['driverName'])} · ${fmtDateTime(l['loadDate'], l, _offset)}',
      onPrimary: (l) => _view(_lid(l)),
      secondaryBuilder: (l) => Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(tStr(l['vehicleName']).isEmpty ? '—' : tStr(l['vehicleName'])),
        waterLoadStatusBadge(l['status']),
      ]),
      highlights: (l) => [
        Highlight('Loaded (bags)', qtyFmt(l['bagsLoaded']), accent: Accent.blue),
        Highlight('Expected', _gh(tNum(l['expectedCash'])), accent: Accent.emerald),
      ],
      details: (l) => [
        ('Date', fmtDateTime(l['loadDate'], l, _offset)),
        ('Driver', tStr(l['driverName']).isEmpty ? '—' : tStr(l['driverName'])),
        ('Vehicle', tStr(l['vehicleName']).isEmpty ? '—' : tStr(l['vehicleName'])),
        ('Route', tStr(l['routeName']).isEmpty ? '—' : tStr(l['routeName'])),
        ('Status', tStr(l['status'])),
      ],
      actions: actions,
      table: (items) => TrackerTable(
        columns: const [
          TCol('Date', width: 130), TCol('Driver', width: 120), TCol('Vehicle', width: 110), TCol('Route', width: 110),
          TCol('Loaded (bags)', right: true, width: 100), TCol('Expected', right: true, width: 110), TCol('Status', width: 100),
          TCol('Actions', right: true, width: 220),
        ],
        rows: [
          for (final l in items)
            [
              InkWell(onTap: () => _view(_lid(l)), child: cellText(fmtDateTime(l['loadDate'], l, _offset), color: TColors.sky700)),
              cellText(tStr(l['driverName']).isEmpty ? '—' : tStr(l['driverName'])),
              cellText(tStr(l['vehicleName']).isEmpty ? '—' : tStr(l['vehicleName'])),
              cellText(tStr(l['routeName']).isEmpty ? '—' : tStr(l['routeName'])),
              Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(l['bagsLoaded']))),
              Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(l['expectedCash'])))),
              Align(alignment: Alignment.centerLeft, child: waterLoadStatusBadge(l['status'])),
              Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: [
                IconButton(tooltip: 'View details', onPressed: () => _view(_lid(l)), icon: const Icon(Icons.visibility_outlined, size: 18)),
                if (showActions && tStr(l['status']) == 'Loaded') FilledButton(onPressed: () => _recordReturn(l), child: const Text('Record return')),
                if (showActions && (tStr(l['status']) == 'Loaded' || tStr(l['status']) == 'Draft')) ...[
                  IconButton(tooltip: 'Reload / edit load', onPressed: () => _loadForm(l), icon: const Icon(Icons.refresh, size: 18, color: Color(0xFF0284C7))),
                  IconButton(
                    tooltip: 'Void this delivery (reverses stock)',
                    onPressed: () => _void(l),
                    icon: const Icon(Icons.cancel_outlined, size: 18, color: Color(0xFFF43F5E)),
                  ),
                ],
                if (reconciledTab && tStr(l['status']) == 'Reconciled') ...[
                  IconButton(
                    tooltip: 'Edit this reconciled return (reverses + re-opens for edit)',
                    onPressed: () => _reconciledAction(l, edit: true),
                    icon: const Icon(Icons.edit_outlined, size: 18, color: TColors.sky700),
                  ),
                  IconButton(
                    tooltip: 'Reverse reconciliation',
                    onPressed: () => _reconciledAction(l, edit: false),
                    icon: const Icon(Icons.undo, size: 18, color: TColors.amber600),
                  ),
                ],
              ]),
            ],
        ],
      ),
      pager: _pager(key, rows.length),
    );
  }

  List<Widget> _returnActions(Map r) {
    final st = tStr(r['status']);
    return [
      OutlinedButton(onPressed: () => _view(tIntOrNull(r['waterVehicleLoadingId']) ?? 0), child: const Text('View details')),
      if (st == 'Draft') OutlinedButton.icon(onPressed: () => _editDraftReturn(r), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
      if (st == 'Draft')
        OutlinedButton.icon(
          onPressed: () => _approve(r),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF15803D), side: const BorderSide(color: Color(0xFFBBF7D0))),
          icon: const Icon(Icons.check_circle_outline, size: 16),
          label: const Text('Approve & Reconcile'),
        ),
      if (st == 'Draft')
        OutlinedButton.icon(
          onPressed: () => _simple('/api/Water/driver-returns/${_rid(r)}/cancel', 'Return cancelled', 'Cancel failed'),
          style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: Color(0xFFFECACA))),
          icon: const Icon(Icons.cancel_outlined, size: 16),
          label: const Text('Cancel'),
        ),
      if (st == 'Approved')
        OutlinedButton.icon(
          onPressed: () => _reverse(r),
          style: OutlinedButton.styleFrom(foregroundColor: TColors.amber700, side: const BorderSide(color: Color(0xFFFDE68A))),
          icon: const Icon(Icons.undo, size: 16),
          label: const Text('Reverse'),
        ),
      if (st == 'Cancelled')
        OutlinedButton.icon(
          onPressed: () => _simple('/api/Water/driver-returns/${_rid(r)}/uncancel', 'Return uncancelled — back to Draft. Approve to reconcile.', 'Uncancel failed'),
          style: OutlinedButton.styleFrom(foregroundColor: TColors.emerald700, side: const BorderSide(color: TColors.emerald300)),
          icon: const Icon(Icons.undo, size: 16),
          label: const Text('Uncancel'),
        ),
      if (st == 'Cancelled' && _isAdmin)
        OutlinedButton.icon(
          onPressed: () => _deleteReturn(r),
          style: OutlinedButton.styleFrom(foregroundColor: TColors.red600, side: const BorderSide(color: Color(0xFFFECACA))),
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Delete'),
        ),
    ];
  }

  Widget _returnsList(List<Map> rows) => MobileCardList<Map>(
        striped: true,
        items: _slice('returns', rows),
        keyOf: (r) => '${_rid(r)}',
        primary: (r) =>
            'Delivery #${tStr(r['waterVehicleLoadingId'])} · ${tStr(r['vehicleName']).isEmpty ? 'Vehicle —' : tStr(r['vehicleName'])} · ${qtyFmt(r['bagsSold'])} bags sold',
        secondaryBuilder: (r) => Wrap(spacing: 4, children: [
          Text(fmtDateTime(r['returnDate'], r, _offset)),
          if (tStr(r['driverName']).isNotEmpty) Text('· ${tStr(r['driverName'])}'),
          if (tStr(r['routeName']).isNotEmpty) Text('· ${tStr(r['routeName'])}'),
          if (tNum(r['shortageAmount']) > 0) Text('· Short ${_gh(tNum(r['shortageAmount']))}', style: const TextStyle(color: TColors.rose600)),
        ]),
        highlights: (r) => [
          Highlight('Cash', _gh(tNum(r['cashCollected'])), accent: Accent.emerald),
          Highlight('Shortage', _gh(tNum(r['shortageAmount'])), accent: tNum(r['shortageAmount']) > 0 ? Accent.rose : Accent.slate),
        ],
        details: (r) => [
          ('Delivery #', tStr(r['waterVehicleLoadingId'])),
          ('Date', fmtDateTime(r['returnDate'], r, _offset)),
          ('Vehicle', tStr(r['vehicleName']).isEmpty ? '—' : tStr(r['vehicleName'])),
          ('Driver', tStr(r['driverName']).isEmpty ? '—' : tStr(r['driverName'])),
          ('Route', tStr(r['routeName']).isEmpty ? '—' : tStr(r['routeName'])),
          ('Status', tStr(r['status'])),
          ('Sold (bags)', qtyFmt(r['bagsSold'])),
          ('Returned (bags)', qtyFmt(r['bagsReturned'])),
          ('Damaged (bags)', qtyFmt(r['bagsDamaged'])),
          ('MoMo', _gh(tNum(r['moMoCollected']))),
          ('Credit', _gh(tNum(r['creditSalesAmount']))),
        ],
        actions: _returnActions,
        table: (items) => TrackerTable(
          columns: const [
            TCol('Delivery #', width: 80), TCol('Date', width: 120), TCol('Vehicle', width: 110), TCol('Driver', width: 110), TCol('Status', width: 100),
            TCol('Sold (bags)', right: true, width: 90), TCol('Returned (bags)', right: true, width: 110), TCol('Damaged (bags)', right: true, width: 110),
            TCol('Cash', right: true, width: 100), TCol('MoMo', right: true, width: 100), TCol('Credit', right: true, width: 100),
            TCol('Shortage', right: true, width: 100), TCol('Actions', right: true, width: 240),
          ],
          rows: [
            for (final r in items)
              [
                cellText('#${tStr(r['waterVehicleLoadingId'])}', bold: true),
                cellText(fmtDateTime(r['returnDate'], r, _offset)),
                cellText(tStr(r['vehicleName']).isEmpty ? '—' : tStr(r['vehicleName']), bold: true),
                cellText(tStr(r['driverName']).isEmpty ? '—' : tStr(r['driverName'])),
                Align(alignment: Alignment.centerLeft, child: waterReturnStatusBadge(r['status'])),
                Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(r['bagsSold']))),
                Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(r['bagsReturned']))),
                Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(r['bagsDamaged']))),
                Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(r['cashCollected'])))),
                Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(r['moMoCollected'])))),
                Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(r['creditSalesAmount'])))),
                Align(
                  alignment: Alignment.centerRight,
                  child: cellText(_gh(tNum(r['shortageAmount'])), color: tNum(r['shortageAmount']) > 0 ? TColors.rose600 : null),
                ),
                Wrap(alignment: WrapAlignment.end, children: [
                  IconButton(tooltip: 'View details', onPressed: () => _view(tIntOrNull(r['waterVehicleLoadingId']) ?? 0), icon: const Icon(Icons.visibility_outlined, size: 18)),
                  if (tStr(r['status']) == 'Draft') ...[
                    IconButton(
                      tooltip: 'Edit this Draft (pre-fills the Record Return dialog)',
                      onPressed: () => _editDraftReturn(r),
                      icon: const Icon(Icons.edit_outlined, size: 18, color: TColors.sky700),
                    ),
                    IconButton(tooltip: 'Approve & Reconcile', onPressed: () => _approve(r), icon: const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF16A34A))),
                    IconButton(
                      tooltip: 'Cancel return',
                      onPressed: () => _simple('/api/Water/driver-returns/${_rid(r)}/cancel', 'Return cancelled', 'Cancel failed'),
                      icon: const Icon(Icons.cancel_outlined, size: 18, color: Color(0xFFF43F5E)),
                    ),
                  ],
                  if (tStr(r['status']) == 'Approved')
                    IconButton(tooltip: 'Reverse reconciliation', onPressed: () => _reverse(r), icon: const Icon(Icons.undo, size: 18, color: TColors.amber600)),
                  if (tStr(r['status']) == 'Cancelled')
                    IconButton(
                      tooltip: 'Uncancel (back to Draft so it can be re-approved)',
                      onPressed: () => _simple('/api/Water/driver-returns/${_rid(r)}/uncancel', 'Return uncancelled — back to Draft. Approve to reconcile.', 'Uncancel failed'),
                      icon: const Icon(Icons.undo, size: 18, color: TColors.emerald600),
                    ),
                  if (tStr(r['status']) == 'Cancelled' && _isAdmin)
                    IconButton(
                      tooltip: 'Delete this cancelled return (admin only, hard delete)',
                      onPressed: () => _deleteReturn(r),
                      icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                    ),
                ]),
              ],
          ],
        ),
        pager: _pager('returns', rows.length),
      );

  Widget _setupLink(IconData icon, String title, String sub, String href) => InkWell(
        onTap: () => openAppHref(context, widget.session, widget.company, href, label: title),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 16, color: const Color(0xFF0284C7)),
              const SizedBox(width: 6),
              Flexible(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900))),
            ]),
            const SizedBox(height: 4),
            Text(sub, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ),
      );

  Widget _tabButton(String key, String label) {
    final on = _tab == key;
    return InkWell(
      onTap: () => setState(() => _tab = key),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(color: on ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: on ? TColors.slate900 : TColors.slate500)),
      ),
    );
  }

  Widget _score(String label, String value) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: TColors.slate900)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-driver-returns');
    final visibleL = _visibleLoadings;
    final loaded = _loadings.where((l) => tStr(l['status']) == 'Loaded').length;
    final reconciled = _loadings.where((l) => tStr(l['status']) == 'Reconciled').length;
    final activeAny = _loadings.any((l) => const ['Loaded', 'Draft'].contains(tStr(l['status'])));
    final today = _today();
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Deliveries')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            const Row(children: [
              Icon(Icons.local_shipping_outlined, color: Color(0xFF0284C7)),
              SizedBox(width: 8),
              Flexible(child: Text('Deliveries', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
            ]),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => _loadForm(),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Load vehicle'),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: TColors.slate100, borderRadius: BorderRadius.circular(8)),
              child: Wrap(spacing: 4, runSpacing: 4, children: [
                _tabButton('active', 'Active loads ($loaded)'),
                _tabButton('returns', 'Returns (${_returns.length})'),
                _tabButton('reconciled', 'Reconciled ($reconciled)'),
                _tabButton('setup', 'Setup'),
              ]),
            ),
            const SizedBox(height: 12),
            ...switch (_tab) {
              'returns' => [
                  ListFiltersCard(
                    search: _rSearch,
                    searchPlaceholder: 'Search driver, vehicle or route',
                    onSearch: () => setState(() {}),
                    from: _rFrom,
                    to: _rTo,
                    onDates: (f, t) => setState(() {
                      _rFrom = f;
                      _rTo = t;
                    }),
                    onClear: () => setState(() {
                      _rSearch.clear();
                      _rFrom = '';
                      _rTo = '';
                    }),
                    extras: _dropdowns(const ['Draft', 'Approved', 'Cancelled']),
                  ),
                  const SizedBox(height: 12),
                  _box(_returns.isEmpty
                      ? _empty(const Text('No driver returns recorded yet.', style: TextStyle(color: TColors.slate500)))
                      : Padding(padding: const EdgeInsets.all(8), child: _returnsList(_visibleReturns))),
                ],
              'reconciled' => [
                  _loadingFilters(const ['Reconciled']),
                  const SizedBox(height: 12),
                  _box(reconciled == 0
                      ? _empty(const Text('No reconciled loadings yet.', style: TextStyle(color: TColors.slate500)))
                      : _deliveries('reconciled', [for (final l in visibleL) if (tStr(l['status']) == 'Reconciled') l], showActions: false)),
                ],
              'setup' => [
                  _box(Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _setupLink(Icons.groups_outlined, 'Drivers',
                          '${_drivers.where((d) => d['isActive'] == true).length} active · manage drivers, base pay, commissions', '/water-drivers'),
                      const SizedBox(height: 10),
                      _setupLink(Icons.local_shipping_outlined, 'Vehicles',
                          '${_vehicles.where((v) => tStr(v['status']) == 'Active').length} active · manage vehicles and capacity', '/water-vehicles'),
                      const SizedBox(height: 10),
                      _setupLink(Icons.place_outlined, 'Routes', '${_routes.length} configured · manage delivery routes', '/water-routes'),
                      const SizedBox(height: 10),
                      _setupLink(Icons.local_shipping_outlined, 'Driver collection report',
                          'Per-driver per-product loaded / sold / returned / damaged with cash + shortage roll-up', '/water-driver-report'),
                    ]),
                  )),
                ],
              _ => [
                  _loadingFilters(const ['Draft', 'Loaded', 'Returned', 'Reconciled', 'Cancelled']),
                  const SizedBox(height: 12),
                  _box(_loading
                      ? const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading…'))
                      : !activeAny
                          ? _empty(const Text.rich(
                              TextSpan(children: [
                                TextSpan(text: 'No active loads. Click '),
                                TextSpan(text: 'Load vehicle', style: TextStyle(fontWeight: FontWeight.w500)),
                                TextSpan(text: ' above to dispatch a delivery.'),
                              ]),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: TColors.slate500),
                            ))
                          : _deliveries('active', [for (final l in visibleL) if (const ['Loaded', 'Draft'].contains(tStr(l['status']))) l], showActions: true)),
                ],
            },
            const SizedBox(height: 16),
            twoUp([
              _score('Vehicles out', '$loaded'),
              _score('Returns today', '${_returns.where((r) => tStr(r['returnDate']).startsWith(today)).length}'),
              _score('Total shortages', _gh(_returns.fold<num>(0, (s, r) => s + tNum(r['shortageAmount'])))),
              _score('Active vehicles', '${_vehicles.where((v) => tStr(v['status']) == 'Active').length}'),
              _score('Active drivers', '${_drivers.where((d) => d['isActive'] == true).length}'),
            ]),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ load vehicle

class _LoadLine {
  _LoadLine(this.key, this.productId, this.bags, this.price, this.perBag, this.notes);
  final int key;
  int productId;
  num bags, price, perBag;
  String notes;
}

/// Create delivery run — load driver / Edit delivery run (the same form).
class WaterLoadVehicleScreen extends StatefulWidget {
  const WaterLoadVehicleScreen({
    super.key,
    required this.session,
    required this.company,
    required this.drivers,
    required this.vehicles,
    required this.routes,
    required this.products,
    required this.staff,
    this.editing,
  });
  final Session session;
  final Company company;
  final List<Map> drivers, vehicles, routes, products, staff;
  final Map? editing;

  @override
  State<WaterLoadVehicleScreen> createState() => _WaterLoadVehicleScreenState();
}

class _WaterLoadVehicleScreenState extends State<WaterLoadVehicleScreen> {
  late final Map? e = widget.editing;
  late int _vehicleId, _driverId, _assistantId, _routeId;
  late num _opening;
  late String _notes, _date;
  final List<_LoadLine> _items = [];
  bool _saving = false, _ready = false;
  int _seq = 0, _ver = 0;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  String get _user => widget.session.tokens.userId ?? '';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    if (e != null) {
      final l = e!;
      _vehicleId = tIntOrNull(l['waterVehicleId']) ?? 0;
      _driverId = tIntOrNull(l['waterDriverId']) ?? 0;
      _assistantId = tIntOrNull(l['assistantStaffId']) ?? 0;
      _routeId = tIntOrNull(l['waterRouteId']) ?? 0;
      _opening = tNum(l['openingCashWithDriver']);
      _notes = tStr(l['notes']);
      _date = tStr(l['loadDate']).isNotEmpty ? tStr(l['loadDate']).split('T').first : _today();
      _prefillItems();
    } else {
      _vehicleId = tIntOrNull(widget.vehicles.where((v) => tStr(v['status']) == 'Active').firstOrNull?['waterVehicleId']) ?? 0;
      _driverId = tIntOrNull(widget.drivers.where((d) => d['isActive'] == true).firstOrNull?['waterDriverId']) ?? 0;
      _assistantId = 0;
      _routeId = tIntOrNull(widget.routes.firstOrNull?['waterRouteId']) ?? 0;
      _opening = 0;
      _notes = '';
      _date = _today();
      final p0 = widget.products.firstOrNull;
      if (p0 != null) _items.add(_LoadLine(_seq++, tIntOrNull(p0['waterProductId']) ?? 0, 0, tNum(p0['unitPrice']), 30, ''));
      _ready = true;
    }
  }

  Future<void> _prefillItems() async {
    final l = e!;
    try {
      final items = rowsOf(await _api.get('/api/Water/vehicle-loadings/${tStr(l['waterVehicleLoadingId'])}/items', query: {'farmId': _farmId}));
      if (items.isNotEmpty) {
        _items.addAll([
          for (final it in items)
            _LoadLine(_seq++, tIntOrNull(it['waterProductId']) ?? 0, tNum(it['bagsLoaded']), tNum(it['unitPrice']),
                it['sachetsPerBag'] == null ? 30 : tNum(it['sachetsPerBag']), tStr(it['notes'])),
        ]);
      } else if (tIntOrNull(l['waterProductId']) != null) {
        _items.add(_LoadLine(_seq++, tIntOrNull(l['waterProductId'])!, tNum(l['bagsLoaded']), tNum(l['expectedSellingPricePerBag']),
            l['sachetsPerBag'] == null ? 30 : tNum(l['sachetsPerBag']), ''));
      }
    } on ApiException {
      _items.clear();
    }
    if (mounted) {
      setState(() {
        _ready = true;
        _ver++;
      });
    }
  }

  void _addProduct() {
    final taken = {for (final i in _items) i.productId};
    final next = widget.products.where((p) => !taken.contains(tIntOrNull(p['waterProductId']))).firstOrNull ?? widget.products.firstOrNull;
    if (next == null) return trackerToast(context, 'No more products to add', error: true);
    setState(() => _items.add(_LoadLine(_seq++, tIntOrNull(next['waterProductId']) ?? 0, 0, tNum(next['unitPrice']), 30, '')));
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_vehicleId == 0) return trackerToast(context, 'Pick a vehicle', error: true);
    if (_driverId == 0) {
      return trackerToast(context, 'Driver is required', description: 'Drivers carry the stock and the money — the system needs to know who.', error: true);
    }
    if (_items.isEmpty) return trackerToast(context, 'Add at least one product line', error: true);
    if (_items.any((i) => i.productId == 0 || i.bags <= 0)) return trackerToast(context, 'Each line needs a product and a quantity > 0', error: true);
    final seen = <int>{};
    for (final i in _items) {
      if (!seen.add(i.productId)) return trackerToast(context, 'Duplicate product line', description: 'Each product can only appear once per load.', error: true);
    }
    setState(() => _saving = true);
    final items = [
      for (final i in _items)
        {'waterProductId': i.productId, 'bagsLoaded': i.bags, 'unitPrice': i.price, 'sachetsPerBag': i.perBag, 'notes': i.notes.isEmpty ? null : i.notes},
    ];
    final loadDate = '${_date}T00:00:00.000Z';
    final q = {'farmId': _farmId};
    try {
      if (e != null) {
        await _api.post('/api/Water/vehicle-loadings/${tStr(e!['waterVehicleLoadingId'])}/reload', query: {...q, 'updatedBy': _user}, body: {
          'waterDriverId': _driverId == 0 ? null : _driverId,
          'waterVehicleId': _vehicleId == 0 ? null : _vehicleId,
          'waterRouteId': _routeId == 0 ? null : _routeId,
          'openingCashWithDriver': _opening,
          'notes': _notes,
          'loadDate': loadDate,
          'items': items,
        });
        if (mounted) trackerToast(context, 'Delivery run updated');
      } else {
        final created = await _api.post('/api/Water/vehicle-loadings', body: {
          'waterVehicleId': _vehicleId,
          'waterDriverId': _driverId == 0 ? null : _driverId,
          'assistantStaffId': _assistantId == 0 ? null : _assistantId,
          'waterRouteId': _routeId == 0 ? null : _routeId,
          'openingCashWithDriver': _opening,
          'notes': _notes,
          'loadDate': loadDate,
          'bagsLoaded': 0,
          'items': items,
          'farmId': _farmId,
        });
        final id = created is Map ? tIntOrNull(created['waterVehicleLoadingId']) : null;
        if (id == null) throw ApiException(0, 'The load was created but the server did not return its id — please retry.');
        try {
          await _api.post('/api/Water/vehicle-loadings/$id/approve', query: {...q, 'approvedBy': _user});
        } on ApiException catch (x) {
          // Roll back the stuck Draft so it can't masquerade as a duplicate.
          try {
            await _api.post('/api/Water/vehicle-loadings/$id/void', query: {...q, 'voidedBy': _user}, body: {'reason': 'Auto-voided: load could not be confirmed'});
          } on ApiException {
            // best effort
          }
          throw ApiException(x.statusCode, x.message.isNotEmpty ? 'Load could not be confirmed: ${x.message}' : 'Load could not be confirmed — please retry.');
        }
        if (mounted) trackerToast(context, 'Delivery run loaded — stock moved out');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (x) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, e != null ? 'Update failed' : 'Load failed', description: x.message, error: true);
    }
  }

  Widget _numF(String key, num v, ValueChanged<num> on, {bool decimal = true}) => AppInput(
        key: ValueKey('$_ver-$key'),
        initialValue: v == v.roundToDouble() ? '${v.toInt()}' : '$v',
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'^\d*\.?\d*' : r'^\d*'))],
        onChanged: (t) => setState(() => on(num.tryParse(t) ?? 0)),
      );

  @override
  Widget build(BuildContext context) {
    final title = e != null ? 'Edit delivery run #${tStr(e!['waterVehicleLoadingId'])}' : 'Create delivery run — load driver';
    if (!_ready) return Scaffold(appBar: AppBar(title: Text(title)), body: const Padding(padding: EdgeInsets.all(24), child: LoadingLine('Loading…')));
    final activeDrivers = [for (final d in widget.drivers) if (d['isActive'] == true) d];
    final driverName = tStr(widget.drivers.where((d) => tIntOrNull(d['waterDriverId']) == _driverId).firstOrNull?['driverName']).trim().toLowerCase();
    final driverOpts = [for (final d in activeDrivers) if (tIntOrNull(d['waterDriverId']) != _driverId) d];
    final staffOpts = [
      for (final s in widget.staff)
        if (s['isActive'] == true && s['isDeleted'] != true && '${tStr(s['firstName'])} ${tStr(s['lastName'])}'.trim().toLowerCase() != driverName) s
    ];
    final total = _items.fold<num>(0, (s, i) => s + i.bags * i.price);
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            Text(
              e != null
                  ? 'Change driver, vehicle, route, products or quantities. Saving reverses the old stock-out and applies the new amounts atomically.'
                  : 'Assign a driver, pick the vehicle + route, and list the products being loaded. Stock moves out of the warehouse on save.',
              style: const TextStyle(fontSize: 13, color: TColors.slate500),
            ),
            const SizedBox(height: 12),
            formSection('Driver & route', const Color(0xFF4F46E5), [
              FilterLabel(
                'Driver *',
                AppSelect<int>(
                  value: _driverId == 0 ? null : _driverId,
                  hintText: 'Pick driver',
                  items: [for (final d in activeDrivers) AppSelectItem(value: tIntOrNull(d['waterDriverId']) ?? 0, label: tStr(d['driverName']))],
                  onChanged: (v) => setState(() {
                    _driverId = v ?? 0;
                    final d = widget.drivers.where((x) => tIntOrNull(x['waterDriverId']) == _driverId).firstOrNull;
                    // The driver's default vehicle fills the vehicle in.
                    _vehicleId = tIntOrNull(d?['defaultVehicleId']) ?? _vehicleId;
                  }),
                ),
              ),
              FilterLabel(
                'Vehicle *',
                AppSelect<int>(
                  value: _vehicleId == 0 ? null : _vehicleId,
                  hintText: 'Pick vehicle',
                  items: [
                    for (final v in widget.vehicles)
                      if (tStr(v['status']) == 'Active')
                        AppSelectItem(value: tIntOrNull(v['waterVehicleId']) ?? 0, label: '${tStr(v['vehicleName'])} (${tStr(v['vehicleType'])})'),
                  ],
                  onChanged: (v) => setState(() => _vehicleId = v ?? 0),
                ),
              ),
              FilterLabel(
                'Route',
                AppSelect<int>(
                  value: _routeId == 0 ? null : _routeId,
                  hintText: 'Pick route',
                  items: [for (final r in widget.routes) AppSelectItem(value: tIntOrNull(r['waterRouteId']) ?? 0, label: tStr(r['routeName']))],
                  onChanged: (v) => setState(() {
                    _routeId = v ?? 0;
                    final r = widget.routes.where((x) => tIntOrNull(x['waterRouteId']) == _routeId).firstOrNull;
                    // The route's vehicle only when none is set yet.
                    if (_vehicleId == 0) _vehicleId = tIntOrNull(r?['defaultVehicleId']) ?? _vehicleId;
                  }),
                ),
              ),
              FilterLabel(
                'Assistant (optional)',
                AppSelect<int>(
                  value: _assistantId,
                  hintText: 'Pick assistant',
                  items: [
                    const AppSelectItem(value: 0, label: '— none —'),
                    if (driverOpts.isEmpty && staffOpts.isEmpty) const AppSelectItem(value: -1, label: 'No other drivers or staff available.', enabled: false),
                    for (final d in driverOpts) AppSelectItem(value: tIntOrNull(d['waterDriverId']) ?? 0, label: '${tStr(d['driverName'])} · Driver'),
                    for (final s in staffOpts)
                      AppSelectItem(
                        value: tIntOrNull(s['waterStaffId']) ?? 0,
                        label: '${tStr(s['firstName'])} ${tStr(s['lastName'])}${tStr(s['role']).isNotEmpty ? ' · ${tStr(s['role'])}' : ''}',
                      ),
                  ],
                  onChanged: (v) => setState(() => _assistantId = v ?? 0),
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilterLabel('Opening cash with driver', _numF('opening', _opening, (v) => _opening = v)),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Cash float given to driver before departure (change, fuel, small expenses). Separate from sales cash.',
                      style: TextStyle(fontSize: 11, color: TColors.slate500)),
                ),
              ]),
              FilterLabel(
                'Load date',
                AppDateField(
                  value: businessDateAsDateTime(_date),
                  hintText: 'dd/mm/yyyy',
                  onChanged: (d) => setState(() => _date = d == null ? _date : isoDay(d)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  color: TColors.amber600,
                  padding: const EdgeInsets.only(left: 12, right: 6),
                  child: Row(children: [
                    const Expanded(child: Text('Products loaded', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))),
                    FilledButton.tonalIcon(onPressed: _addProduct, icon: const Icon(Icons.add, size: 16), label: const Text('Add product')),
                  ]),
                ),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('One row per product on this run.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                    const SizedBox(height: 8),
                    if (_items.isEmpty)
                      const Text('No products. Click "Add product" to add one.', style: TextStyle(fontSize: 12, color: TColors.slate500))
                    else
                      for (final it in _items)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Row(children: [
                              Expanded(
                                child: AppSelect<int>(
                                  value: it.productId == 0 ? null : it.productId,
                                  hintText: 'Pick product',
                                  items: [for (final p in widget.products) AppSelectItem(value: tIntOrNull(p['waterProductId']) ?? 0, label: tStr(p['name']))],
                                  onChanged: (v) => setState(() {
                                    final p = widget.products.where((x) => tIntOrNull(x['waterProductId']) == v).firstOrNull;
                                    it.productId = v ?? it.productId;
                                    if (p != null && p['unitPrice'] != null) it.price = tNum(p['unitPrice']);
                                    _ver++;
                                  }),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove product',
                                onPressed: () => setState(() => _items.remove(it)),
                                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                              ),
                            ]),
                            const SizedBox(height: 6),
                            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Expanded(child: FilterLabel('Qty (bags)', _numF('q${it.key}', it.bags, (v) => it.bags = v, decimal: false))),
                              const SizedBox(width: 6),
                              Expanded(child: FilterLabel('Unit price', _numF('p${it.key}', it.price, (v) => it.price = v))),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  const Text('Expected', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                                  Text(_gh(it.bags * it.price), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            ]),
                          ]),
                        ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            formSection('Notes', TColors.slate600, [
              FilterLabel(
                'Notes',
                AppInput(key: ValueKey('$_ver-notes'), initialValue: _notes, minLines: 3, maxLines: 6, onChanged: (t) => _notes = t),
              ),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Expanded(child: Text('Total expected cash:', style: TextStyle(color: TColors.slate500))),
                Text(_gh(total), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
              redCancelButton(_saving ? null : () => Navigator.pop(context, false)),
              FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : (e != null ? 'Save changes' : 'Load & approve'))),
            ]),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ delivery run page

/// Delivery run #N (`app/water-driver-returns/[id]/page.tsx`).
class WaterDeliveryRunScreen extends StatefulWidget {
  const WaterDeliveryRunScreen({super.key, required this.session, required this.company, required this.loadingId});
  final Session session;
  final Company company;
  final int loadingId;

  @override
  State<WaterDeliveryRunScreen> createState() => _WaterDeliveryRunScreenState();
}

class _WaterDeliveryRunScreenState extends State<WaterDeliveryRunScreen> {
  Map? _l, _ret;
  List<Map> _items = [], _retItems = [], _sales = [], _expenses = [];
  bool _busy = true;
  FarmMoney _gh = const FarmMoney();
  Duration _offset = DateTime.now().timeZoneOffset;

  ApiClient get _api => widget.session.farmClient;
  Map<String, String> get _q => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<List<Map>> _soft(String path) async {
    try {
      return rowsOf(await _api.get(path, query: _q));
    } on ApiException {
      return const [];
    }
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final r = await Future.wait([
        _api.get('/api/Water/vehicle-loadings', query: _q),
        _api.get('/api/Water/driver-returns', query: _q),
        _soft('/api/Water/vehicle-loadings/${widget.loadingId}/items'),
      ]);
      final l = rowsOf(r[0]).where((x) => tIntOrNull(x['waterVehicleLoadingId']) == widget.loadingId).firstOrNull;
      if (l == null) {
        if (mounted) {
          trackerToast(context, 'Delivery run not found',
              description: 'Delivery run #${widget.loadingId} not found in the list. It may have been deleted.', error: true);
          setState(() => _l = null);
        }
      } else {
        final ret = waterCurrentReturn(rowsOf(r[1]), widget.loadingId);
        List<Map> ri = [], cs = [], ex = [];
        if (ret != null) {
          final id = tStr(ret['waterDriverReturnId']);
          final x = await Future.wait([
            _soft('/api/Water/driver-returns/$id/items'),
            _soft('/api/Water/driver-returns/$id/customer-sales'),
            _soft('/api/Water/driver-returns/$id/expenses'),
          ]);
          ri = x[0];
          cs = x[1];
          ex = x[2];
        }
        if (mounted) {
          setState(() {
            _l = l;
            _items = r[2] as List<Map>;
            _ret = ret;
            _retItems = ri;
            _sales = cs;
            _expenses = ex;
          });
        }
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Could not load delivery run', description: e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _back() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacement(MaterialPageRoute(builder: (_) => WaterDeliveriesScreen(session: widget.session, company: widget.company)));
    }
  }

  Widget _section(String title, IconData? icon, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 16, color: TColors.slate500), const SizedBox(width: 6)],
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate800))),
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _empty(String t) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(t, style: const TextStyle(fontSize: 12, color: TColors.slate500)));

  Widget _card(String label, String value, {Color? color}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: color)),
        ]),
      );

  String _ts(Object? v) => tStr(v).split('.').first.replaceFirst('T', ' ');

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-driver-returns');
    final l = _l, ret = _ret;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: Text('Delivery run #${widget.loadingId}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: _back, icon: const Icon(Icons.arrow_back, size: 16), label: const Text('Back to Deliveries')),
            ),
            if (_busy)
              const Padding(padding: EdgeInsets.all(16), child: LoadingLine('Loading delivery run…'))
            else if (l == null)
              const Padding(padding: EdgeInsets.all(16), child: Text('Delivery run not found.', style: TextStyle(color: TColors.slate500)))
            else
              ..._body(l, ret),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(Map l, Map? ret) {
    final expected = _items.isEmpty
        ? tNum(l['expectedCash'])
        : (() {
            final s = _items.fold<num>(0, (s, it) => s + (it['expectedAmount'] != null ? tNum(it['expectedAmount']) : tNum(it['bagsLoaded']) * tNum(it['unitPrice'])));
            return s != 0 ? s : tNum(l['expectedCash']);
          })();
    final collected = ret == null ? 0 : tNum(ret['cashCollected']) + tNum(ret['moMoCollected']) + tNum(ret['bankCollected']) + tNum(ret['creditSalesAmount']);
    final short = tNum(ret?['shortageAmount']);
    final expTotal = _expenses.where((x) => x['isApproved'] == true).fold<num>(0, (s, x) => s + tNum(x['amount']));
    final loadedTotal = _items.fold<num>(0, (s, it) => s + tNum(it['bagsLoaded']));
    String itemExpected(Map it) => _gh(it['expectedAmount'] != null ? tNum(it['expectedAmount']) : tNum(it['bagsLoaded']) * tNum(it['unitPrice']));
    String salesOf(Map ri) => _gh(ri['expectedSales'] != null ? tNum(ri['expectedSales']) : tNum(ri['bagsSold']) * tNum(ri['unitPrice']));
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 150, child: Text(k, style: const TextStyle(fontSize: 13, color: TColors.slate500))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13, color: TColors.slate900))),
          ]),
        );
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.local_shipping_outlined, color: Color(0xFF0284C7)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Delivery run #${tStr(l['waterVehicleLoadingId'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900)),
            Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              waterLoadStatusBadge(l['status']),
              Text(fmtDateTime(l['loadDate'], l, _offset), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              if (tStr(l['driverName']).isNotEmpty)
                Text.rich(TextSpan(children: [
                  const TextSpan(text: '· Driver: '),
                  TextSpan(text: tStr(l['driverName']), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              if (tStr(l['vehicleName']).isNotEmpty) Text('· ${tStr(l['vehicleName'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              if (tStr(l['routeName']).isNotEmpty) Text('· ${tStr(l['routeName'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      twoUp([
        _card('Total loaded (bags)', loadedTotal != 0 ? qtyFmt(loadedTotal) : tStr(l['bagsLoaded'])),
        _card('Expected', _gh(expected)),
        _card('Collected', ret != null ? _gh(collected) : '—'),
        _card(short > 0 ? 'Shortage' : 'Overage', ret != null ? _gh(short > 0 ? short : tNum(ret['overageAmount'])) : '—',
            color: short > 0 ? TColors.rose600 : TColors.emerald600),
      ]),
      const SizedBox(height: 12),
      _section('Products loaded', Icons.inventory_2_outlined, [
        if (_items.isEmpty)
          _empty('No item rows. Legacy single-product loading.')
        else
          MobileCardList<Map>(
            striped: true,
            alwaysExpanded: true,
            items: _items,
            keyOf: (it) => tStr(it['waterVehicleLoadingItemId']),
            primary: (it) => tStr(it['productName']).isNotEmpty ? tStr(it['productName']) : 'Product #${tStr(it['waterProductId'])}',
            secondary: (it) => '${qtyFmt(it['bagsLoaded'])} bags · ${itemExpected(it)}',
            highlights: (it) => [
              Highlight('Loaded (bags)', qtyFmt(it['bagsLoaded']), accent: Accent.blue),
              Highlight('Expected', itemExpected(it), accent: Accent.emerald),
            ],
            details: (it) => [('Unit price', _gh(tNum(it['unitPrice'])))],
            table: (items) => const SizedBox.shrink(),
          ),
      ]),
      if (ret != null && RegExp('reversed by', caseSensitive: false).hasMatch(tStr(ret['notes'])))
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: TColors.amber50, border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Reversal history', style: TextStyle(fontWeight: FontWeight.w600, color: TColors.amber900)),
            const SizedBox(height: 4),
            Text(tStr(ret['notes']), style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: TColors.amber900)),
          ]),
        ),
      if (ret != null) ...[
        _section('Return reconciliation', Icons.receipt_long_outlined, [
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            waterLoadStatusBadge(ret['status']),
            Text('Return date: ${fmtDateTime(ret['returnDate'], ret, _offset)}', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
            if (tStr(ret['approvedBy']).isNotEmpty) Text('· Approved by ${tStr(ret['approvedBy'])}', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
            if (tStr(ret['approvedAt']).isNotEmpty) Text('at ${_ts(ret['approvedAt'])}', style: const TextStyle(fontSize: 12, color: TColors.slate600)),
          ]),
          const SizedBox(height: 8),
          if (_retItems.isNotEmpty)
            MobileCardList<Map>(
              striped: true,
              alwaysExpanded: true,
              items: _retItems,
              keyOf: (ri) => tStr(ri['waterDriverReturnItemId']),
              primary: (ri) => tStr(ri['productName']).isNotEmpty ? tStr(ri['productName']) : 'Product #${tStr(ri['waterProductId'])}',
              secondary: (ri) => 'Sold ${qtyFmt(ri['bagsSold'])} · ${salesOf(ri)}',
              highlights: (ri) => [
                Highlight('Sold', qtyFmt(ri['bagsSold']), accent: Accent.emerald),
                Highlight('Returned', qtyFmt(ri['bagsReturned']), accent: Accent.blue),
                Highlight('Sales', salesOf(ri), accent: Accent.violet, wide: true),
              ],
              details: (ri) => [
                ('Loaded', qtyFmt(ri['bagsLoaded'])),
                ('Damaged', qtyFmt(ri['bagsDamaged'])),
                ('Unit price', _gh(tNum(ri['unitPrice']))),
              ],
              table: (items) => const SizedBox.shrink(),
            )
          else
            _empty(
                'Legacy single-product return — totals: sold ${qtyFmt(ret['bagsSold'])}, returned ${qtyFmt(ret['bagsReturned'])}, damaged ${qtyFmt(ret['bagsDamaged'])}.'),
        ]),
        _section('Money collected', Icons.payments_outlined, [
          twoUp([
            for (final (k, v, red) in [
              ('Cash', tNum(ret['cashCollected']), false),
              ('MoMo', tNum(ret['moMoCollected']), false),
              ('Bank', tNum(ret['bankCollected']), false),
              ('Credit sales', tNum(ret['creditSalesAmount']), tNum(ret['creditSalesAmount']) > 0),
              ('Driver float returned', tNum(ret['cashReturnedByDriver']), false),
              ('Unaccounted cash', short, short > 0),
            ])
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(k, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  Text(_gh(v), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: red ? TColors.rose600 : null)),
                ]),
              ),
          ]),
        ]),
        _section('Customer sales breakdown (${_sales.length})', Icons.groups_outlined, [
          if (_sales.isEmpty)
            _empty('Summary-only return — no per-customer breakdown was recorded.')
          else
            for (final cs in _sales)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        tStr(cs['customerName']).isNotEmpty ? tStr(cs['customerName']) : (tStr(cs['customerLabel']).isNotEmpty ? tStr(cs['customerLabel']) : 'Walk-in'),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    tIntOrNull(cs['generatedWaterSaleId']) != null
                        ? InkWell(
                            onTap: () => openAppHref(context, widget.session, widget.company, '/water-sales?focus=${tStr(cs['generatedWaterSaleId'])}', label: 'Sales'),
                            child: Text('→ Sale #${tStr(cs['generatedWaterSaleId'])}', style: const TextStyle(fontSize: 12, color: TColors.sky700)),
                          )
                        : const Text('No sale yet (Draft return)', style: TextStyle(fontSize: 12, color: TColors.slate500)),
                  ]),
                  for (final it in rowsOf(cs['items']))
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(4)),
                      child: Row(children: [
                        Expanded(
                          child: Text(tStr(it['productName']).isNotEmpty ? tStr(it['productName']) : 'Product #${tStr(it['waterProductId'])}',
                              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                        Text.rich(TextSpan(children: [
                          TextSpan(text: '${qtyFmt(it['quantity'])} × ${_gh(tNum(it['unitPrice']))} = '),
                          TextSpan(text: _gh(tNum(it['lineTotal'])), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
                        ]), style: const TextStyle(fontSize: 13, color: TColors.slate600)),
                      ]),
                    ),
                  const Divider(height: 16),
                  Wrap(spacing: 12, runSpacing: 4, children: [
                    Text('Total: ${_gh(tNum(cs['totalAmount']))}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Text('Cash: ${_gh(tNum(cs['cashPaid']))}', style: const TextStyle(fontSize: 12)),
                    Text('MoMo: ${_gh(tNum(cs['moMoPaid']))}', style: const TextStyle(fontSize: 12)),
                    Text('Bank: ${_gh(tNum(cs['bankPaid']))}', style: const TextStyle(fontSize: 12)),
                    Text('Credit: ${_gh(tNum(cs['creditAmount']))}',
                        style: TextStyle(fontSize: 12, color: tNum(cs['creditAmount']) > 0 ? TColors.rose600 : null)),
                  ]),
                  if (tStr(cs['notes']).isNotEmpty)
                    Text('"${tStr(cs['notes'])}"', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: TColors.slate600)),
                ]),
              ),
        ]),
        _section('Delivery expenses (${_gh(expTotal)})', Icons.payments_outlined, [
          if (_expenses.isEmpty)
            _empty('No delivery expenses logged.')
          else
            MobileCardList<Map>(
              striped: true,
              alwaysExpanded: true,
              items: _expenses,
              keyOf: (x) => tStr(x['waterDeliveryExpenseId']),
              primary: (x) => tStr(x['expenseCategory']),
              secondaryBuilder: (x) => Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(_gh(tNum(x['amount']))),
                x['isApproved'] == true
                    ? const TBadge('Approved', bg: Color(0xFFDCFCE7), fg: Color(0xFF15803D))
                    : const TBadge('Pending', bg: TColors.amber100, fg: TColors.amber700),
              ]),
              highlights: (x) => [Highlight('Amount', _gh(tNum(x['amount'])), accent: Accent.rose, wide: true)],
              details: (x) => [
                ('Description', tStr(x['description']).isEmpty ? '—' : tStr(x['description'])),
                ('Status', x['isApproved'] == true ? 'Approved' : 'Pending'),
              ],
              table: (items) => const SizedBox.shrink(),
            ),
        ]),
      ] else
        _section('Return reconciliation', Icons.receipt_long_outlined, [
          _empty('No return recorded yet. ${tStr(l['status']) == 'Loaded' ? 'Use the Record Return action on the Deliveries page.' : ''}'.trim()),
        ]),
      _section('Audit trail', null, [
        row('Loading created', tStr(l['loadDate']).split('T').first),
        if (tStr(l['driverName']).isNotEmpty) row('Driver', tStr(l['driverName'])),
        if (tStr(l['vehicleName']).isNotEmpty) row('Vehicle', tStr(l['vehicleName'])),
        if (tStr(l['routeName']).isNotEmpty) row('Route', tStr(l['routeName'])),
        if (tNum(l['openingCashWithDriver']) != 0) row('Opening cash float', _gh(tNum(l['openingCashWithDriver']))),
        if (tStr(ret?['createdBy']).isNotEmpty) row('Return created by', tStr(ret?['createdBy'])),
        if (tStr(ret?['approvedBy']).isNotEmpty) row('Return approved by', tStr(ret?['approvedBy'])),
        if (tStr(ret?['approvedAt']).isNotEmpty) row('Approved at', _ts(ret?['approvedAt'])),
        if (tStr(l['notes']).isNotEmpty) row('Loading notes', tStr(l['notes'])),
        if (tStr(ret?['notes']).isNotEmpty) row('Return notes', tStr(ret?['notes'])),
      ]),
    ];
  }
}

// ------------------------------------------------------------ driver report

/// Driver collection report (`app/water-driver-report/page.tsx`).
class WaterDriverReportScreen extends StatefulWidget {
  const WaterDriverReportScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterDriverReportScreen> createState() => _WaterDriverReportScreenState();
}

class _WaterDriverReportScreenState extends State<WaterDriverReportScreen> {
  late String _from = defaultReportRange().from, _to = defaultReportRange().to;
  String _period = 'last30';
  int _driverId = 0;
  List<Map> _drivers = [], _totals = [], _detail = [];
  bool _hasReport = false, _busy = true;
  int _page = 1, _pageSize = 10;
  FarmMoney _gh = const FarmMoney();

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    _load();
  }

  Future<void> _load([String? from, String? to]) async {
    setState(() => _busy = true);
    final api = widget.session.farmClient;
    final farmId = widget.company.farmId;
    try {
      final r = await Future.wait([
        api.get('/api/Water/drivers', query: {'farmId': farmId}).then(rowsOf).catchError((_) => <Map>[]),
        api.get('/api/Water/reports/driver-collection', query: {
          'farmId': farmId,
          'fromDate': from ?? _from,
          'toDate': to ?? _to,
          if (_driverId != 0) 'waterDriverId': '$_driverId',
        }),
      ]);
      if (!mounted) return;
      final rep = r[1];
      setState(() {
        _drivers = r[0] as List<Map>;
        _totals = rep is Map ? rowsOf(rep['totals']) : [];
        String d(Map x) => tStr(x['driverName']).isEmpty ? 'Unassigned' : tStr(x['driverName']);
        _detail = (rep is Map ? rowsOf(rep['detail']) : <Map>[])
          ..sort((a, b) {
            final c = d(a).compareTo(d(b));
            return c != 0 ? c : tStr(a['productName']).compareTo(tStr(b['productName']));
          });
        _hasReport = rep is Map;
        _page = 1;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      trackerToast(context, 'Could not load driver report', description: e.message, error: true);
      setState(() => _hasReport = false);
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _stat(String label, String value, {bool rose = false}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: rose ? TColors.rose600 : TColors.slate900)),
        ]),
      );

  String _drv(Map t) => tStr(t['driverName']).isEmpty ? 'Unassigned' : tStr(t['driverName']);
  String _prod(Map r) => tStr(r['productName']).isNotEmpty ? tStr(r['productName']) : 'Product #${tStr(r['waterProductId'])}';

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-driver-report');
    num sum(String k) => _totals.fold<num>(0, (s, t) => s + tNum(t[k]));
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Driver collection report')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          const Row(children: [
            Icon(Icons.bar_chart, size: 24, color: Color(0xFF0284C7)),
            SizedBox(width: 8),
            Expanded(child: Text('Driver collection report', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
          ]),
          const SizedBox(height: 14),
          TCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FilterLabel(
                'Period',
                AppSelect<String>(
                  value: _period,
                  hintText: 'Select period',
                  items: [for (final (_, opts) in periodGroups) for (final (k, l) in opts) AppSelectItem(value: k, label: l)],
                  onChanged: (k) {
                    if (k == null) return;
                    setState(() => _period = k);
                    final r = periodToRange(k);
                    if (r != null) {
                      setState(() {
                        _from = r.from;
                        _to = r.to;
                      });
                      _load(r.from, r.to);
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              filterRow([
                FilterLabel('From', FilterDate(value: _from, hint: 'From', onChanged: (v) => setState(() {
                      _from = v;
                      _period = 'custom';
                    }))),
                FilterLabel('To', FilterDate(value: _to, hint: 'To', onChanged: (v) => setState(() {
                      _to = v;
                      _period = 'custom';
                    }))),
              ]),
              const SizedBox(height: 10),
              FilterLabel(
                'Driver',
                AppSelect<int>(
                  value: _driverId,
                  items: [
                    const AppSelectItem(value: 0, label: '— all drivers —'),
                    for (final d in _drivers)
                      if (d['isActive'] == true) AppSelectItem(value: tIntOrNull(d['waterDriverId']) ?? 0, label: tStr(d['driverName'])),
                  ],
                  onChanged: (v) => setState(() => _driverId = v ?? 0),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : () => _load(),
                icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          if (_busy)
            const TCard(child: LoadingLine('Loading report…'))
          else if (!_hasReport || _totals.isEmpty)
            const TCard(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No delivery activity in this period.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
              ),
            )
          else ...[
            twoUp([
              _stat('Delivery runs', qtyFmt(sum('deliveryRuns'))),
              _stat('Cash', _gh(sum('cashCollected'))),
              _stat('MoMo', _gh(sum('moMoCollected'))),
              _stat('Bank', _gh(sum('bankCollected'))),
              _stat('Credit', _gh(sum('creditSales'))),
              _stat('Shortage', _gh(sum('shortage')), rose: sum('shortage') > 0),
            ]),
            const SizedBox(height: 14),
            MobileCardList<Map>(
              striped: true,
              items: _totals,
              keyOf: (t) => tStr(t['waterDriverId']).isEmpty ? 'none-${_drv(t)}' : tStr(t['waterDriverId']),
              primary: _drv,
              secondary: (t) => '${qtyFmt(t['deliveryRuns'])} runs · Cash ${_gh(tNum(t['cashCollected']))}',
              highlights: (t) => [
                Highlight('Cash', _gh(tNum(t['cashCollected'])), accent: Accent.emerald),
                Highlight('Shortage', _gh(tNum(t['shortage'])), accent: tNum(t['shortage']) > 0 ? Accent.rose : Accent.slate),
              ],
              details: (t) => [
                ('Runs', qtyFmt(t['deliveryRuns'])),
                ('Reconciled', qtyFmt(t['reconciledRuns'])),
                ('MoMo', _gh(tNum(t['moMoCollected']))),
                ('Bank', _gh(tNum(t['bankCollected']))),
                ('Credit', _gh(tNum(t['creditSales']))),
                ('Overage', _gh(tNum(t['overage']))),
              ],
              detailColor: (t, label) => label == 'Overage' && tNum(t['overage']) > 0 ? TColors.emerald600 : null,
              table: (items) => TrackerTable(
                columns: const [
                  TCol('Driver', width: 130), TCol('Runs', right: true, width: 60), TCol('Reconciled', right: true, width: 90),
                  TCol('Cash', right: true, width: 100), TCol('MoMo', right: true, width: 100), TCol('Bank', right: true, width: 100),
                  TCol('Credit', right: true, width: 100), TCol('Shortage', right: true, width: 100), TCol('Overage', right: true, width: 100),
                ],
                rows: [
                  for (final t in items)
                    [
                      cellText(_drv(t), bold: true),
                      Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(t['deliveryRuns']))),
                      Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(t['reconciledRuns']))),
                      Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(t['cashCollected'])))),
                      Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(t['moMoCollected'])))),
                      Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(t['bankCollected'])))),
                      Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(t['creditSales'])))),
                      Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(t['shortage'])), color: tNum(t['shortage']) > 0 ? TColors.rose600 : null)),
                      Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(t['overage'])), color: tNum(t['overage']) > 0 ? TColors.emerald600 : null)),
                    ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text('Deliveries', style: TextStyle(fontWeight: FontWeight.w500, color: TColors.slate800)),
            const SizedBox(height: 8),
            MobileCardList<Map>(
              striped: true,
              items: pageSlice(_detail, _page, _pageSize),
              keyOf: (r) => '${tStr(r['waterDriverId']).isEmpty ? 'none' : tStr(r['waterDriverId'])}-${tStr(r['waterProductId'])}',
              primary: (r) => '${_drv(r)} · ${_prod(r)}',
              secondary: (r) => '${qtyFmt(r['bagsSold'])}/${qtyFmt(r['bagsLoaded'])} sold · ${_gh(tNum(r['salesValue']))}',
              highlights: (r) => [
                Highlight('Loaded (bags)', qtyFmt(r['bagsLoaded']), accent: Accent.blue),
                Highlight('Sold (bags)', qtyFmt(r['bagsSold']), accent: Accent.emerald),
                Highlight('Expected', _gh(tNum(r['expectedCash'])), accent: Accent.violet, wide: true),
              ],
              details: (r) => [
                ('Driver', _drv(r)),
                ('Product', _prod(r)),
                ('Returned (bags)', qtyFmt(r['bagsReturned'])),
                ('Damaged (bags)', qtyFmt(r['bagsDamaged'])),
                ('Sales', _gh(tNum(r['salesValue']))),
              ],
              table: (items) => TrackerTable(
                columns: const [
                  TCol('Driver', width: 120), TCol('Product', width: 130), TCol('Loaded (bags)', right: true, width: 100), TCol('Sold (bags)', right: true, width: 90),
                  TCol('Returned (bags)', right: true, width: 110), TCol('Damaged (bags)', right: true, width: 110), TCol('Expected', right: true, width: 100),
                  TCol('Sales', right: true, width: 100),
                ],
                rows: [
                  for (final r in items)
                    [
                      cellText(_drv(r), bold: true),
                      cellText(_prod(r)),
                      Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(r['bagsLoaded']))),
                      Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(r['bagsSold']))),
                      Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(r['bagsReturned']))),
                      Align(alignment: Alignment.centerRight, child: cellText(qtyFmt(r['bagsDamaged']))),
                      Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(r['expectedCash'])))),
                      Align(alignment: Alignment.centerRight, child: cellText(_gh(tNum(r['salesValue'])))),
                    ],
                ],
              ),
              pager: CompactPager(
                total: _detail.length,
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
        ],
      ),
    );
  }
}
