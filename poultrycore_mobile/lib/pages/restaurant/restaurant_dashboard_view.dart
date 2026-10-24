// Restaurant → Dashboard, as `app/restaurant-dashboard/page.tsx`: Welcome back
// with the date and Open POS; the four figures (Active Orders, Today's
// Revenue, Tables, Reservations); Kitchen Status and Delivery Status; the
// Waitlist; Quick Actions; the 86'd-items alert; and the latest active orders.
//
// Each section falls back to empty when its call fails, and the failures are
// named in one toast, as the web does.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import 'restaurant_money_kit.dart' show rTodayIso;
import 'restaurant_widgets.dart';

const restaurantQuickActions = [
  ('/restaurant-pos', 'New Order', Icons.shopping_cart_outlined, Color(0xFFFFE4E6), Color(0xFFE11D48)),
  ('/restaurant-orders', 'View Orders', Icons.assignment_outlined, Color(0xFFDBEAFE), Color(0xFF2563EB)),
  ('/restaurant-kds', 'Kitchen', Icons.soup_kitchen_outlined, Color(0xFFFEF3C7), Color(0xFFD97706)),
  ('/restaurant-reservations', 'Reservations', Icons.calendar_month_outlined, Color(0xFFF3E8FF), Color(0xFF9333EA)),
  ('/restaurant-floor-plan', 'Floor Plan', Icons.place_outlined, Color(0xFFCCFBF1), Color(0xFF0D9488)),
  ('/restaurant-menu', 'Menu Items', Icons.restaurant, Color(0xFFDCFCE7), Color(0xFF16A34A)),
  ('/restaurant-online-orders', 'Online Orders', Icons.public, Color(0xFFE0E7FF), Color(0xFF4F46E5)),
  ('/restaurant-delivery', 'Delivery', Icons.local_shipping_outlined, Color(0xFFFFEDD5), Color(0xFFEA580C)),
];

/// The page's figures, worked out from the loaded lists.
class RestaurantDashboardFigures {
  RestaurantDashboardFigures(List<Map> orders, List<Map> menu, List<Map> tables, {DateTime? now}) {
    final t = now ?? DateTime.now();
    active = [for (final o in orders) if (!const ['Completed', 'Cancelled', 'Refunded'].contains(tStr(o['status']))) o];
    final today = [
      for (final o in orders)
        if (DateTime.tryParse(tStr(o['createdAt']))?.toLocal() case final d? when d.year == t.year && d.month == t.month && d.day == t.day) o,
    ];
    todayOrders = today.length;
    todayRevenue = today.where((o) => tStr(o['paymentStatus']) == 'Paid').fold<num>(0, (s, o) => s + tNum(o['totalAmount']));
    occupied = tables.where((x) => tStr(x['status']) == 'Occupied').length;
    available = tables.where((x) => tStr(x['status']) == 'Available').length;
    tableCount = tables.length;
    unavailableItems = menu.where((i) => i['isAvailable'] == false).length;
  }

  late final List<Map> active;
  late final int todayOrders;
  late final num todayRevenue;
  late final int occupied;
  late final int available;
  late final int tableCount;
  late final int unavailableItems;
}

class RestaurantDashboardView extends StatefulWidget {
  const RestaurantDashboardView({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantDashboardView> createState() => _RestaurantDashboardViewState();
}

class _RestaurantDashboardViewState extends State<RestaurantDashboardView> {
  bool _loading = true;
  List<Map> _orders = [], _menu = [], _tables = [];
  Map? _kds, _delivery, _waitlist;
  int _reservations = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = widget.session.farmClient;
    final q = {'farmId': widget.company.farmId};
    final failed = <String>[];
    Future<Object?> safe(String label, Future<Object?> f, Object? empty) => f.catchError((Object _) {
          failed.add(label);
          return empty;
        });
    List<Map> rows(Object? v) => [for (final x in (v is List ? v : const [])) if (x is Map) x];
    final r = await Future.wait<Object?>([
      safe('Orders', api.get('/api/Restaurant/orders', query: {...q, '_': 1}), const []),
      safe('Menu', api.get('/api/Restaurant/menu/items', query: {...q, '_': 1}), const []),
      safe('Tables', api.get('/api/Restaurant/floor/tables', query: {...q, '_': 1}), const []),
      safe('Kitchen', api.get('/api/Restaurant/kds/stats', query: q), null),
      safe('Delivery', api.get('/api/Restaurant/delivery/stats', query: {...q, '_': 1}), null),
      safe('Waitlist', api.get('/api/Restaurant/reservations/waitlist/stats', query: q), null),
      safe('Reservations', api.get('/api/Restaurant/reservations', query: {...q, '_': 1, 'date': rTodayIso()}), const []),
    ]);
    if (!mounted) return;
    if (failed.isNotEmpty) {
      trackerToast(context, 'Some figures could not load', description: '${failed.join(', ')} -- these show as empty. Refresh to try again.', error: true);
    }
    setState(() {
      _orders = rows(r[0]);
      _menu = rows(r[1]);
      _tables = rows(r[2]);
      _kds = r[3] is Map ? r[3] as Map : null;
      _delivery = r[4] is Map ? r[4] as Map : null;
      _waitlist = r[5] is Map ? r[5] as Map : null;
      _reservations = rows(r[6]).length;
      _loading = false;
    });
  }

  void _go(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'));
    final f = RestaurantDashboardFigures(_orders, _menu, _tables);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 28), children: [
        const Text('Welcome back', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
        Text('${widget.company.name.isEmpty ? 'Restaurant' : widget.company.name} — ${DateFormat('EEEE, MMMM d, y').format(DateTime.now())}',
            style: const TextStyle(fontSize: 14, color: TColors.slate500)),
        const SizedBox(height: 10),
        roseButton('Open POS', () => _go('/restaurant-pos', 'POS / New Order'), icon: Icons.shopping_cart_outlined),
        const SizedBox(height: 14),
        twoColumns([
          _kpi("ACTIVE ORDERS", '${f.active.length}', null, Icons.assignment_outlined, const Color(0xFFF43F5E), const Color(0xFFFFE4E6), const Color(0xFFE11D48)),
          _kpi("TODAY'S REVENUE", f.todayRevenue.toStringAsFixed(0), '${f.todayOrders} orders today', Icons.attach_money, const Color(0xFF22C55E),
              const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
          _kpi('TABLES', '${f.occupied}/${f.tableCount}', '${f.available} available', Icons.place_outlined, const Color(0xFF3B82F6),
              const Color(0xFFDBEAFE), const Color(0xFF2563EB)),
          _kpi('RESERVATIONS', '$_reservations', 'Today', Icons.calendar_month_outlined, const Color(0xFFA855F7), const Color(0xFFF3E8FF),
              const Color(0xFF9333EA)),
        ], gap: 10),
        const SizedBox(height: 14),
        _kitchen(),
        const SizedBox(height: 14),
        _deliveryCard(),
        const SizedBox(height: 14),
        _waitlistCard(),
        const SizedBox(height: 14),
        _quickActions(),
        if (f.unavailableItems > 0) ...[const SizedBox(height: 14), _eightySixed(f.unavailableItems)],
        const SizedBox(height: 14),
        _recent(f.active),
      ]),
    );
  }

  Widget _kpi(String label, String value, String? hint, IconData icon, Color stripe, Color tileBg, Color tileFg) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 4, color: stripe),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .5, color: TColors.slate500)),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                        ),
                      ]),
                    ),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, size: 20, color: tileFg),
                    ),
                  ]),
                  if (hint != null) ...[const SizedBox(height: 6), Text(hint, style: const TextStyle(fontSize: 12, color: TColors.slate500))],
                ]),
              ),
            ),
          ]),
        ),
      );

  Widget _cardHead(String title, IconData icon, Color bg, Color fg, {String? link, String? linkLabel, String? linkTitle}) => Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: fg),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        if (link != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE11D48), visualDensity: VisualDensity.compact),
            onPressed: () => _go(link, linkTitle ?? linkLabel!),
            child: Text('$linkLabel →', style: const TextStyle(fontSize: 12)),
          ),
      ]);

  Widget _figure(String value, String label, Color bg, Color big, Color small) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: big)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: small)),
            ),
          ]),
        ),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
      );

  Widget _kitchen() {
    final k = _kds;
    final longest = tNum(k?['longestWaitMinutes']);
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardHead('Kitchen Status', Icons.soup_kitchen_outlined, const Color(0xFFFEF3C7), const Color(0xFFD97706),
            link: '/restaurant-kds', linkLabel: 'Open KDS', linkTitle: 'Kitchen Display'),
        const SizedBox(height: 12),
        if (k == null)
          _empty('No kitchen data')
        else
          Row(children: [
            _figure('${tNum(k['pendingCount']).toInt()}', 'Pending', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8), const Color(0xFF2563EB)),
            const SizedBox(width: 8),
            _figure('${tNum(k['preparingCount']).toInt()}', 'Preparing', const Color(0xFFFFFBEB), const Color(0xFFB45309), const Color(0xFFD97706)),
            const SizedBox(width: 8),
            _figure('${tNum(k['readyCount']).toInt()}', 'Ready', const Color(0xFFF0FDF4), const Color(0xFF15803D), const Color(0xFF16A34A)),
          ]),
        if (k != null && k['longestWaitMinutes'] != null && longest > 10) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(child: Text('Longest wait: ${longest.floor()}min', style: const TextStyle(fontSize: 14, color: Color(0xFFB45309)))),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _deliveryCard() {
    final d = _delivery;
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardHead('Delivery Status', Icons.local_shipping_outlined, const Color(0xFFE0E7FF), const Color(0xFF4F46E5),
            link: '/restaurant-delivery', linkLabel: 'Manage', linkTitle: 'Drivers & Dispatch'),
        const SizedBox(height: 12),
        if (d == null)
          _empty('No delivery data')
        else
          Row(children: [
            _figure('${tNum(d['availableDrivers']).toInt()}', 'Drivers Free', const Color(0xFFF0FDF4), const Color(0xFF15803D), const Color(0xFF16A34A)),
            const SizedBox(width: 8),
            _figure('${tNum(d['activeCount']).toInt()}', 'Active', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8), const Color(0xFF2563EB)),
            const SizedBox(width: 8),
            _figure('${tNum(d['deliveredCount']).toInt()}', 'Delivered', const Color(0xFFF9FAFB), const Color(0xFF374151), const Color(0xFF4B5563)),
          ]),
      ]),
    );
  }

  Widget _waitlistCard() {
    final w = _waitlist;
    Widget line(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(k, style: const TextStyle(fontSize: 14, color: TColors.slate500))),
            Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
        );
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardHead('Waitlist', Icons.people_outline, const Color(0xFFFFEDD5), const Color(0xFFEA580C)),
        const SizedBox(height: 10),
        if (w != null && tNum(w['waitingCount']) > 0) ...[
          line('Waiting', '${tNum(w['waitingCount']).toInt()}'),
          line('Notified', '${tNum(w['notifiedCount']).toInt()}'),
          if (w['avgWaitMins'] != null) line('Avg Wait', '${tNum(w['avgWaitMins']).floor()}min'),
          line('Covers', '${tNum(w['totalCovers']).toInt()}'),
        ] else
          _empty('No guests waiting'),
      ]),
    );
  }

  Widget _quickActions() => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Quick Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          twoColumns([
            for (final (href, label, icon, bg, fg) in restaurantQuickActions)
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: TColors.slate200)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _go(href, label),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                        child: Icon(icon, size: 16, color: fg),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151)))),
                    ]),
                  ),
                ),
              ),
          ], gap: 8),
        ]),
      );

  Widget _eightySixed(int n) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(color: const Color(0xFFFFFBEB), border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFFD97706)),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$n', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: " menu item${n != 1 ? 's are' : ' is'} currently 86'd (unavailable)"),
              ]),
              style: const TextStyle(fontSize: 14, color: Color(0xFF92400E)),
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB45309), side: const BorderSide(color: Color(0xFFFCD34D)), visualDensity: VisualDensity.compact),
            onPressed: () => _go('/restaurant-menu', 'Menu Items'),
            child: const Text('View Menu', style: TextStyle(fontSize: 12)),
          ),
        ]),
      );

  Widget _recent(List<Map> active) => TCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Text('Recent Orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFE11D48), visualDensity: VisualDensity.compact),
              onPressed: () => _go('/restaurant-orders', 'All Orders'),
              child: const Text('View All →', style: TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 6),
          if (active.isEmpty)
            _empty('No active orders')
          else
            for (final o in active.take(8)) _orderRow(o),
        ]),
      );

  Widget _orderRow(Map o) {
    final status = tStr(o['status']);
    final color = switch (status) {
      'Placed' => const Color(0xFF3B82F6),
      'Preparing' => const Color(0xFFF59E0B),
      'Ready' => const Color(0xFF22C55E),
      _ => const Color(0xFF6B7280),
    };
    final created = DateTime.tryParse(tStr(o['createdAt']));
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _go('/restaurant-orders?highlight=${o['orderId']}', 'All Orders'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(tStr(o['orderNumber']), style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w700)),
              rBadge(tStr(o['orderType']), bg: Colors.white, border: TColors.slate200),
              rBadge(status, bg: color, fg: Colors.white),
              if (tStr(o['tableNumber']).isNotEmpty) Text('Table ${tStr(o['tableNumber'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(tNum(o['totalAmount']).toStringAsFixed(2), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            if (created != null) Text(DateFormat('HH:mm').format(created.toLocal()), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ]),
      ),
    );
  }
}

/// `/restaurant-dashboard` opened as a page (e.g. from a link).
class RestaurantDashboardScreen extends StatelessWidget {
  const RestaurantDashboardScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, session, company, href: '/restaurant-dashboard');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Dashboard')),
      body: RestaurantDashboardView(session: session, company: company),
    );
  }
}
