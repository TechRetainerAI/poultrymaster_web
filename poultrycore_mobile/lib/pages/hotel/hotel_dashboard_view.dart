// Hotel → Dashboard, as `app/hotel-dashboard/page.tsx`: Room Status, Today,
// Operations, then In-House Guests, Expected Arrivals, Expected Departures and
// Recent Payments, and the staff count. Refreshes itself every 30 seconds, as
// the web does (keeping the figures on screen while it reloads). Below the
// cards sit four charts the web does not have (hotel_dashboard_charts.dart),
// added at the user's request on 2026-10-28.
// API: /Hotel/rooms/status-summary, /Hotel/bookings, /Hotel/billing/payments,
// /Hotel/staff, /Hotel/housekeeping, /Hotel/maintenance,
// /Hotel/restaurant/orders, /Hotel/finance/expenses, /Hotel/billing/charges.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart' show twoUp;
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import 'hotel_dashboard_charts.dart';
import 'hotel_kit.dart';

Object? _v(Map m, String k) => m[k] ?? m[k.toLowerCase()];
String _day(Object? v) => tStr(v).length >= 10 ? tStr(v).substring(0, 10) : tStr(v);

/// One in-house guest's balance: room bill + stay charges − payments.
typedef HotelGuestBalance = ({String guest, String room, num balance, String ref});

/// The dashboard's figures, worked out the web's way.
class HotelDashboardFigures {
  HotelDashboardFigures({
    required this.statusSummary,
    required this.bookings,
    required this.payments,
    required this.balances,
    required List<Map> staff,
    required List<Map> housekeeping,
    required List<Map> maintenance,
    required List<Map> orders,
    required this.expenses,
    required this.today,
  })  : staffCount = staff.length,
        pendingHousekeeping = housekeeping.where((t) => t['status'] == 'Pending' || t['Status'] == 'Pending').length,
        openMaintenance = maintenance.where((m) => const ['Open', 'InProgress'].contains(m['status'] ?? m['Status'])).length,
        activeOrders = orders.where((o) => o['status'] == 'Placed' || o['status'] == 'Preparing').length,
        todayExpenses = expenses.where((e) => _day(_v(e, 'expenseDate')) == today).fold<num>(0, (s, e) => s + tNum(e['amount'])),
        todayArrivals = [for (final b in bookings) if (b['status'] == 'Confirmed' && _day(_v(b, 'checkInDate')) == today) b],
        todayDepartures = [for (final b in bookings) if (b['status'] == 'CheckedIn' && _day(_v(b, 'checkOutDate')) == today) b],
        todayPayments = [for (final p in payments) if (_day(_v(p, 'paymentDate')) == today) p];

  final List<Map> statusSummary, bookings, payments, expenses;

  /// The UTC day the figures are for, as the web's toISOString().
  final String today;
  final List<HotelGuestBalance> balances;
  final int staffCount, pendingHousekeeping, openMaintenance, activeOrders;
  final num todayExpenses;
  final List<Map> todayArrivals, todayDepartures, todayPayments;

  int status(String s) => tNum(statusSummary.where((x) => x['status'] == s).firstOrNull?['roomCount']).toInt();
  int get totalRooms => statusSummary.fold<int>(0, (s, x) => s + tNum(x['roomCount']).toInt());
  int get occupied => status('Occupied');
  int get occupancyRate => totalRooms > 0 ? (occupied / totalRooms * 100).round() : 0;
  int get checkedIn => bookings.where((b) => b['status'] == 'CheckedIn').length;
  num get todayRevenue => todayPayments.fold<num>(0, (s, p) => s + tNum(p['amount']));
  List<HotelGuestBalance> get owing => [for (final b in balances) if (b.balance > 0) b];
  num get totalOutstanding => owing.fold<num>(0, (s, b) => s + b.balance);
}

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// toLocaleDateString("en-GB", { weekday, year, month: "long", day }).
String hotelLongDate(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}';

String _clock(DateTime d) => [d.hour, d.minute, d.second].map((n) => n.toString().padLeft(2, '0')).join(':');

// The web's StatCard colours: (tint, foreground, border).
const _tones = {
  'violet': (Color(0xFFF5F3FF), Color(0xFF7C3AED), Color(0xFFDDD6FE)),
  'emerald': (Color(0xFFECFDF5), Color(0xFF059669), Color(0xFFA7F3D0)),
  'blue': (Color(0xFFEFF6FF), Color(0xFF2563EB), Color(0xFFBFDBFE)),
  'amber': (Color(0xFFFFFBEB), Color(0xFFD97706), Color(0xFFFDE68A)),
  'orange': (Color(0xFFFFF7ED), Color(0xFFEA580C), Color(0xFFFED7AA)),
  'red': (Color(0xFFFEF2F2), Color(0xFFDC2626), Color(0xFFFECACA)),
};

class HotelDashboardView extends StatefulWidget {
  const HotelDashboardView({super.key, required this.session, required this.company, this.now, this.autoRefresh = true});
  final Session session;
  final Company company;

  /// The clock, for tests.
  final DateTime Function()? now;
  final bool autoRefresh;

  @override
  State<HotelDashboardView> createState() => _HotelDashboardViewState();
}

class _HotelDashboardViewState extends State<HotelDashboardView> {
  HotelDashboardFigures? _f;
  bool _loading = true;
  String _lastRefresh = '';
  Timer? _timer;

  ApiClient get _api => widget.session.farmClient;
  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.autoRefresh) _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<List<Map>> _rows(String path, [Map<String, String>? extra]) async {
    try {
      return hotelRows(await _api.get(path, query: {'farmId': widget.company.farmId, ...?extra}));
    } on ApiException {
      return [];
    }
  }

  Future<void> _load() async {
    if (_f == null) setState(() => _loading = true);
    final first = await Future.wait([_rows('/api/Hotel/rooms/status-summary'), _rows('/api/Hotel/bookings'), _rows('/api/Hotel/billing/payments')]);
    final extra = await Future.wait([
      _rows('/api/Hotel/staff'),
      _rows('/api/Hotel/housekeeping'),
      _rows('/api/Hotel/maintenance'),
      _rows('/api/Hotel/restaurant/orders'),
      _rows('/api/Hotel/finance/expenses'),
    ]);
    final bookings = first[1], payments = first[2];
    final balances = <HotelGuestBalance>[];
    for (final b in bookings.where((b) => b['status'] == 'CheckedIn')) {
      final id = tIntOrNull(_v(b, 'hotelBookingId'));
      final charges = (await _rows('/api/Hotel/billing/charges', {'bookingId': '$id'})).fold<num>(0, (s, x) => s + tNum(_v(x, 'totalAmount')));
      final paid = payments.where((p) => tIntOrNull(_v(p, 'hotelBookingId')) == id).fold<num>(0, (s, p) => s + tNum(p['amount']));
      balances.add((
        guest: '${tStr(_v(b, 'guestFirstName'))} ${tStr(_v(b, 'guestLastName'))}',
        room: tStr(_v(b, 'roomNumber')).isEmpty ? '—' : tStr(_v(b, 'roomNumber')),
        balance: tNum(_v(b, 'totalAmount')) + charges - paid,
        ref: tStr(_v(b, 'bookingRef')),
      ));
    }
    if (!mounted) return;
    final now = _now();
    setState(() {
      _f = HotelDashboardFigures(
        statusSummary: first[0],
        bookings: bookings,
        payments: payments,
        balances: balances,
        staff: extra[0],
        housekeeping: extra[1],
        maintenance: extra[2],
        orders: extra[3],
        expenses: extra[4],
        today: now.toUtc().toIso8601String().substring(0, 10),
      );
      _lastRefresh = _clock(now);
      _loading = false;
    });
  }

  void _go(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  Widget _stat(String title, Object value, IconData icon, {String? href, String color = 'violet', String? sub}) {
    final t = _tones[color] ?? _tones['violet']!;
    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.$1, border: Border.all(color: t.$3), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), border: Border.all(color: t.$3), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 20, color: t.$2),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900))),
            Text(title, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            if (sub != null) Text(sub, style: const TextStyle(fontSize: 11, color: TColors.slate400)),
          ]),
        ),
      ]),
    );
    if (href == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => _go(href, title), child: card),
    );
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: TColors.slate400)),
      );

  Widget _panel(IconData icon, Color iconColor, String title, String empty, List<Widget> rows) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Text(empty, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: TColors.slate400)))
          else
            ...rows,
        ]),
      );

  Widget _row(String title, String sub, Widget trailing, Color bg, Color border, {Color? titleColor}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: titleColor)),
              Text(sub, style: const TextStyle(fontSize: 12, color: TColors.slate400)),
            ]),
          ),
          const SizedBox(width: 8),
          trailing,
        ]),
      );

  Widget _owes(num balance) => balance > 0
      ? hotelBadge('Owes ${balance.toStringAsFixed(2)}', const Color(0xFFFEE2E2), const Color(0xFFB91C1C))
      : hotelBadge('Paid', const Color(0xFFD1FAE5), const Color(0xFF047857));

  @override
  Widget build(BuildContext context) {
    final f = _f;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.apartment, size: 24, color: hotelViolet)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Hotel Dashboard', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900)),
              Text('${widget.company.name} — ${hotelLongDate(_now())}', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            ]),
          ),
          if (_lastRefresh.isNotEmpty)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Auto-refreshes every 30s', style: TextStyle(fontSize: 11, color: TColors.slate400)),
              Text('Last: $_lastRefresh', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
            ]),
        ]),
        const SizedBox(height: 14),
        if (_loading || f == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: hotelViolet)))
        else ...[
          _heading('Room Status'),
          twoUp([
            _stat('Total Rooms', f.totalRooms, Icons.door_front_door_outlined, href: '/hotel-rooms'),
            _stat('Available', f.status('Available'), Icons.door_front_door_outlined, href: '/hotel-rooms', color: 'emerald'),
            _stat('Occupied', f.occupied, Icons.people_outline),
            _stat('Reserved', f.status('Reserved'), Icons.calendar_today_outlined, href: '/hotel-bookings', color: 'blue'),
            _stat('Cleaning', f.status('Cleaning'), Icons.auto_awesome_outlined, href: '/hotel-housekeeping', color: 'orange'),
            _stat('Maintenance', f.status('Maintenance'), Icons.build_outlined, href: '/hotel-maintenance', color: 'amber'),
          ]),
          const SizedBox(height: 14),
          _heading('Today'),
          twoUp([
            _stat('Occupancy Rate', '${f.occupancyRate}%', Icons.trending_up),
            _stat("Today's Revenue", f.todayRevenue.toStringAsFixed(2), Icons.account_balance_wallet_outlined,
                href: '/hotel-payments', color: 'emerald', sub: '${f.todayPayments.length} payment(s)'),
            _stat("Today's Expenses", f.todayExpenses.toStringAsFixed(2), Icons.account_balance_wallet_outlined, href: '/hotel-expenses', color: 'red'),
            _stat('Outstanding Balances', f.totalOutstanding.toStringAsFixed(2), Icons.warning_amber_rounded,
                href: '/hotel-check-out', color: f.totalOutstanding > 0 ? 'red' : 'emerald', sub: '${f.owing.length} guest(s) owe'),
          ]),
          const SizedBox(height: 14),
          _heading('Operations'),
          twoUp([
            _stat('Arrivals Today', f.todayArrivals.length, Icons.login, href: '/hotel-check-in', color: 'blue'),
            _stat('Departures Today', f.todayDepartures.length, Icons.logout, href: '/hotel-check-out', color: 'amber'),
            _stat('Pending Housekeeping', f.pendingHousekeeping, Icons.auto_awesome_outlined,
                href: '/hotel-housekeeping', color: f.pendingHousekeeping > 0 ? 'orange' : 'emerald'),
            _stat('Active Orders', f.activeOrders, Icons.shopping_cart_outlined, href: '/hotel-restaurant', color: f.activeOrders > 0 ? 'amber' : 'emerald'),
            _stat('Open Maintenance', f.openMaintenance, Icons.build_outlined, href: '/hotel-maintenance', color: f.openMaintenance > 0 ? 'red' : 'emerald'),
          ]),
          const SizedBox(height: 18),
          _heading('Insights'),
          HotelDashboardCharts(statusSummary: f.statusSummary, bookings: f.bookings, payments: f.payments, expenses: f.expenses, today: f.today),
          const SizedBox(height: 4),
          _panel(Icons.people_outline, hotelViolet, 'In-House Guests (${f.checkedIn})', 'No guests currently checked in', [
            for (final g in f.balances) _row(g.guest, 'Room ${g.room} | ${g.ref}', _owes(g.balance), TColors.slate50, TColors.slate200),
          ]),
          _panel(Icons.login, const Color(0xFF2563EB), 'Expected Arrivals (${f.todayArrivals.length})', 'No arrivals today', [
            for (final a in f.todayArrivals)
              _row(
                '${tStr(_v(a, 'guestFirstName'))} ${tStr(_v(a, 'guestLastName'))}',
                '${tStr(_v(a, 'roomTypeName'))} | ${tStr(_v(a, 'roomNumber')).isEmpty ? 'Unassigned' : tStr(_v(a, 'roomNumber'))}',
                hotelBadge(tStr(_v(a, 'bookingRef')), const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)),
                const Color(0xFFEFF6FF),
                const Color(0xFFDBEAFE),
              ),
          ]),
          _panel(Icons.logout, const Color(0xFFD97706), 'Expected Departures (${f.todayDepartures.length})', 'No departures today', [
            for (final d in f.todayDepartures)
              _row(
                '${tStr(_v(d, 'guestFirstName'))} ${tStr(_v(d, 'guestLastName'))}',
                'Room ${tStr(_v(d, 'roomNumber'))} | ${tNum(_v(d, 'totalAmount')).toStringAsFixed(2)}',
                _owes(f.balances.where((b) => b.ref == tStr(_v(d, 'bookingRef'))).firstOrNull?.balance ?? 0),
                const Color(0xFFFFFBEB),
                const Color(0xFFFEF3C7),
              ),
          ]),
          _panel(Icons.credit_card, const Color(0xFF059669), 'Recent Payments', 'No payments yet', [
            for (final p in f.payments.take(6))
              _row(
                tNum(p['amount']).toStringAsFixed(2),
                '${tStr(_v(p, 'paymentMethod'))} | ${_day(_v(p, 'paymentDate'))}',
                Text(tStr(p['reference']).isEmpty ? '—' : tStr(p['reference']), style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: TColors.slate400)),
                const Color(0xFFECFDF5),
                const Color(0xFFD1FAE5),
                titleColor: const Color(0xFF047857),
              ),
          ]),
          const SizedBox(height: 4),
          Text('${f.staffCount} staff members registered', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: TColors.slate400)),
        ],
      ]),
    );
  }
}

/// `/hotel-dashboard` opened as a page (e.g. from a link).
class HotelDashboardScreen extends StatelessWidget {
  const HotelDashboardScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, session, company, href: '/hotel-dashboard');
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Dashboard')),
      body: HotelDashboardView(session: session, company: company),
    );
  }
}
