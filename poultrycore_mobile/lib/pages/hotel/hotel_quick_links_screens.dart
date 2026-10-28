// Hotel → Quick Links: Daily Closing (`app/hotel-daily-closing`), Night Audit
// (`app/hotel-night-audit`) and Shift Handover (`app/hotel-shift-handover`).
// The fourth Quick Link, Bookings, is hotel_front_desk_screens.dart.
// API: /Hotel/reports/daily-closings, /Hotel/night-audit, /Hotel/shift-handovers
// (+ /{id}/acknowledge), and for the live day /Hotel/rooms/status-summary,
// /Hotel/bookings, /Hotel/billing/payments, /Hotel/finance/expenses,
// /Hotel/housekeeping, /Hotel/maintenance, /Hotel/staff.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart';
import '../poultry/reports/report_format.dart';
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import 'hotel_kit.dart';

Object? _v(Map m, String k) => m[k] ?? m[k.toLowerCase()];

/// new Date().toISOString().slice(0, 10): the UTC day, as the web uses.
String _todayIso([DateTime? now]) => (now ?? DateTime.now()).toUtc().toIso8601String().substring(0, 10);

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The web's `nice`: "Tue, 28 Oct 2026".
String hotelNiceDate(Object? iso) {
  final s = tStr(iso);
  final d = s.length >= 10 ? DateTime.tryParse(s.substring(0, 10)) : null;
  if (d == null) return '—';
  return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';
}

String _local(Object? v) {
  final d = DateTime.tryParse(tStr(v))?.toLocal();
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day}/${d.month}/${d.year}, ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

Widget _loadingBox() => const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: hotelViolet)));

Widget _iconTitle(IconData icon, String title, {Widget? trailing}) => Row(children: [
      Icon(icon, size: 24, color: hotelViolet),
      const SizedBox(width: 10),
      Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900))),
      ?trailing,
    ]);

Future<Object?> _soft(ApiClient api, String path, Map<String, String> q) => api.get(path, query: q).then<Object?>((r) => r, onError: (_) => const []);

/// The day as it stands now, from the room summary, bookings, payments and
/// expenses (both pages read the same four lists).
typedef HotelLiveDay = ({
  int totalRooms,
  int occupied,
  int available,
  num revenue,
  num expenses,
  int arrivals,
  int departures,
  int checkedIn,
});

HotelLiveDay hotelLiveDay({required List<Map> roomStatus, required List<Map> bookings, required List<Map> payments, required List<Map> expenses, required String today, bool skipVoid = true}) {
  int count(Map? r) => tNum(r == null ? null : _v(r, 'roomCount')).toInt();
  Map? status(String s) => roomStatus.where((r) => (r['status'] ?? r['Status']) == s).firstOrNull;
  String day(Object? v) => tStr(v).length >= 10 ? tStr(v).substring(0, 10) : tStr(v);
  return (
    totalRooms: roomStatus.fold<int>(0, (s, r) => s + count(r)),
    occupied: count(status('Occupied')),
    available: count(status('Available')),
    revenue: payments
        .where((p) => day(_v(p, 'paymentDate')) == today && (!skipVoid || (p['status'] ?? 'Posted') != 'Void'))
        .fold<num>(0, (s, p) => s + tNum(p['amount'])),
    expenses: expenses.where((e) => day(_v(e, 'expenseDate')) == today).fold<num>(0, (s, e) => s + tNum(e['amount'])),
    arrivals: bookings.where((b) => day(_v(b, 'checkInDate')) == today && b['status'] == 'Confirmed').length,
    departures: bookings.where((b) => day(_v(b, 'checkOutDate')) == today && b['status'] == 'CheckedIn').length,
    checkedIn: bookings.where((b) => b['status'] == 'CheckedIn').length,
  );
}

// ================================================================ Daily Closing

/// A saved closing, read whatever case the API returns.
typedef HotelClosing = ({int id, String date, num revenue, num expenses, num net, num occupancy, int occupied, int rooms, num adr, num revpar, String notes});

HotelClosing hotelClosingOf(Map i) {
  final revenue = tNum(_v(i, 'totalRevenue')), expenses = tNum(_v(i, 'totalExpenses'));
  final date = tStr(_v(i, 'closingDate'));
  return (
    id: tIntOrNull(_v(i, 'hotelDailyClosingId')) ?? 0,
    date: date.length >= 10 ? date.substring(0, 10) : date,
    revenue: revenue,
    expenses: expenses,
    net: revenue - expenses,
    occupancy: tNum(_v(i, 'occupancyRate')),
    occupied: tNum(_v(i, 'roomsOccupied')).toInt(),
    rooms: tNum(_v(i, 'totalRooms')).toInt(),
    adr: tNum(i['adr']),
    revpar: tNum(_v(i, 'revPar')),
    notes: tStr(i['notes']),
  );
}

class HotelDailyClosingScreen extends StatefulWidget {
  const HotelDailyClosingScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelDailyClosingScreen> createState() => _HotelDailyClosingScreenState();
}

class _HotelDailyClosingScreenState extends State<HotelDailyClosingScreen> {
  List<HotelClosing> _history = [];
  HotelLiveDay _live = (totalRooms: 0, occupied: 0, available: 0, revenue: 0, expenses: 0, arrivals: 0, departures: 0, checkedIn: 0);
  bool _loading = true;
  int _page = 1, _size = 20;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {'farmId': widget.company.farmId};
    try {
      final items = hotelRows(await _api.get('/api/Hotel/reports/daily-closings', query: q));
      final r = await Future.wait([
        _soft(_api, '/api/Hotel/rooms/status-summary', q),
        _soft(_api, '/api/Hotel/bookings', q),
        _soft(_api, '/api/Hotel/billing/payments', q),
        _soft(_api, '/api/Hotel/finance/expenses', q),
      ]);
      if (mounted) {
        setState(() {
          _history = items.map(hotelClosingOf).toList()..sort((a, b) => b.date.compareTo(a.date));
          _live = hotelLiveDay(roomStatus: hotelRows(r[0]), bookings: hotelRows(r[1]), payments: hotelRows(r[2]), expenses: hotelRows(r[3]), today: _todayIso());
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _occRate => _live.totalRooms > 0 ? (_live.occupied / _live.totalRooms * 100).round() : 0;
  num get _liveNet => _live.revenue - _live.expenses;
  bool get _todayClosed => _history.any((h) => h.date == _todayIso());

  HotelClosing get _todayAsClosing => (
        id: 0,
        date: _todayIso(),
        revenue: _live.revenue,
        expenses: _live.expenses,
        net: _liveNet,
        occupancy: _occRate,
        occupied: _live.occupied,
        rooms: _live.totalRooms,
        adr: _live.occupied > 0 ? _live.revenue / _live.occupied : 0,
        revpar: _live.totalRooms > 0 ? _live.revenue / _live.totalRooms : 0,
        notes: '',
      );

  Future<void> _openNew() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _NewClosingDialog(session: widget.session, company: widget.company, live: _live, gh: _gh, occRate: _occRate),
    );
    if (done == true) _load();
  }

  Future<void> _view(HotelClosing h) async {
    final closeDay = await showDialog<bool>(context: context, builder: (_) => _ClosingDialog(closing: h, gh: _gh, canClose: h.id == 0 && !_todayClosed));
    if (closeDay == true) _openNew();
  }

  Widget _tile(String label, String value, Color bg, Color border, Color labelColor, Color valueColor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: labelColor)),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: valueColor)),
        ]),
      );

  Widget _fact(String k, String v, {Color? color}) => Text.rich(TextSpan(children: [
        TextSpan(text: '$k ', style: const TextStyle(color: TColors.slate500)),
        TextSpan(text: v, style: TextStyle(fontWeight: FontWeight.w500, color: color)),
      ]), style: const TextStyle(fontSize: 13));

  Widget _today() {
    final closed = _todayClosed;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: TColors.violet50, border: Border.all(color: TColors.violet200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(hotelNiceDate(_todayIso()), style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate900)),
          closed ? hotelBadge('Closed', const Color(0xFFDCFCE7), const Color(0xFF166534)) : hotelBadge('Open', TColors.slate100, TColors.slate700),
        ]),
        const SizedBox(height: 10),
        twoUp([
          _tile('Rooms occupied', '${_live.occupied}/${_live.totalRooms}', TColors.emerald100, TColors.emerald300, TColors.emerald900, TColors.emerald800),
          _tile('Revenue', _gh(_live.revenue), TColors.blue100, TColors.blue300, TColors.blue900, const Color(0xFF1E40AF)),
        ]),
        const SizedBox(height: 8),
        _tile('Net (revenue − expenses)', _gh(_liveNet), TColors.violet100, const Color(0xFFC4B5FD), const Color(0xFF4C1D95),
            _liveNet < 0 ? TColors.rose700 : const Color(0xFF4C1D95)),
        const Divider(height: 20, color: TColors.violet200),
        twoUp([
          _fact('Expenses', _gh(_live.expenses), color: TColors.rose700),
          _fact('Occupancy', '$_occRate%'),
          _fact('In-house', '${_live.checkedIn}'),
          _fact('Arrivals / departures', '${_live.arrivals} / ${_live.departures}'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: Colors.white),
              onPressed: () => _view(_todayAsClosing),
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('Open closing'),
            ),
          ),
          if (!closed) ...[
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 40))),
                onPressed: _openNew,
                icon: const Icon(Icons.lock_outline, size: 16),
                label: const Text('Close this day'),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-daily-closing');
    if ((_page - 1) * _size >= _history.length && _page > 1) _page = 1;
    final page = pageSlice(_history, _page, _size);
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Daily Closing')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Daily Closing', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900)),
                Text('End-of-day rooms, revenue and expenses snapshot.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
              ]),
            ),
            hotelAddButton('New closing', _openNew),
          ]),
          const SizedBox(height: 14),
          if (_loading)
            _loadingBox()
          else ...[
            _today(),
            const SizedBox(height: 16),
            const Text('CLOSED DAYS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: TColors.slate500)),
            const SizedBox(height: 8),
            if (_history.isEmpty)
              TCard(
                child: const Padding(
                  padding: EdgeInsets.all(28),
                  child: Text('No closings yet. Use "New closing" to record today\'s snapshot.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
                ),
              )
            else
              MobileCardList<HotelClosing>(
                striped: true,
                items: page,
                keyOf: (h) => h.id == 0 ? h.date : '${h.id}',
                primary: (h) => hotelNiceDate(h.date),
                trailing: (_) => hotelBadge('Closed', const Color(0xFFDCFCE7), const Color(0xFF166534)),
                secondary: (h) => h.notes,
                highlights: (h) => [
                  Highlight('Rooms occupied', '${h.occupied}/${h.rooms}', accent: Accent.emerald),
                  Highlight('Revenue', _gh(h.revenue), accent: Accent.blue),
                  Highlight('Net (revenue − expenses)', _gh(h.net), accent: Accent.violet, wide: true),
                ],
                details: (h) => [
                  ('Expenses', _gh(h.expenses)),
                  ('Occupancy', '${h.occupancy.toStringAsFixed(1)}%'),
                  ('ADR', _gh(h.adr)),
                  ('RevPAR', _gh(h.revpar)),
                ],
                detailColor: (_, label) => label == 'Expenses' ? TColors.rose700 : null,
                actions: (h) => [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: Colors.white),
                      onPressed: () => _view(h),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('Open closing'),
                    ),
                  ),
                ],
                table: (rows) => TrackerTable(
                  columns: const [
                    TCol('Date', width: 140),
                    TCol('Revenue', right: true, width: 110),
                    TCol('Expenses', right: true, width: 110),
                    TCol('Net', right: true, width: 110),
                    TCol('Occupancy', right: true, width: 90),
                    TCol('Rooms', right: true, width: 70),
                    TCol('ADR', right: true, width: 100),
                    TCol('RevPAR', right: true, width: 100),
                    TCol('Notes', width: 160),
                    TCol('Actions', right: true, width: 70),
                  ],
                  rows: [
                    for (final h in rows)
                      [
                        cellText(hotelNiceDate(h.date), bold: true),
                        cellText(_gh(h.revenue), bold: true, color: TColors.emerald700),
                        cellText(_gh(h.expenses), color: TColors.red600),
                        cellText(_gh(h.net), bold: true, color: h.net >= 0 ? TColors.emerald700 : const Color(0xFFB91C1C)),
                        cellText('${h.occupancy.toStringAsFixed(1)}%'),
                        cellText('${h.occupied}/${h.rooms}'),
                        cellText(_gh(h.adr)),
                        cellText(_gh(h.revpar)),
                        cellText(h.notes, color: TColors.slate500),
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(tooltip: 'Open closing', onPressed: () => _view(h), icon: const Icon(Icons.visibility_outlined, size: 18)),
                        ),
                      ],
                  ],
                ),
                pager: CompactPager(
                  total: _history.length,
                  page: _page,
                  pageSize: _size,
                  onPage: (p) => setState(() => _page = p),
                  onPageSize: (v) => setState(() {
                    _size = v;
                    _page = 1;
                  }),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}

class _NewClosingDialog extends StatefulWidget {
  const _NewClosingDialog({required this.session, required this.company, required this.live, required this.gh, required this.occRate});
  final Session session;
  final Company company;
  final HotelLiveDay live;
  final FarmMoney gh;
  final int occRate;

  @override
  State<_NewClosingDialog> createState() => _NewClosingDialogState();
}

class _NewClosingDialogState extends State<_NewClosingDialog> {
  String _date = _todayIso();
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Hotel/reports/daily-closings', body: {'closingDate': _date, 'notes': _notes.text, 'farmId': widget.company.farmId});
      if (!mounted) return;
      trackerToast(context, 'Day closed successfully');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.live, gh = widget.gh;
    final net = l.revenue - l.expenses;
    Widget fact(String k, String v, {Color? color}) => Text.rich(TextSpan(children: [
          TextSpan(text: '$k: '),
          TextSpan(text: v, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ]), style: const TextStyle(fontSize: 13));
    return AlertDialog(
      scrollable: true,
      title: const Text('New daily closing'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Saves the day\'s snapshot: occupancy, revenue, expenses, ADR and RevPAR.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: TColors.violet50, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
              const Text('Today as it stands:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.violet700)),
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Occupancy: '),
                TextSpan(text: '${widget.occRate}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' (${l.occupied}/${l.totalRooms})'),
              ]), style: const TextStyle(fontSize: 13)),
              fact('Revenue', gh(l.revenue), color: TColors.emerald700),
              fact('Expenses', gh(l.expenses), color: const Color(0xFFB91C1C)),
              fact('Net', gh(net), color: net >= 0 ? TColors.emerald700 : const Color(0xFFB91C1C)),
              fact('In-house guests', '${l.checkedIn}'),
              fact('ADR', gh(l.occupied > 0 ? l.revenue / l.occupied : 0)),
            ]),
          ),
          const SizedBox(height: 12),
          FilterLabel(
            'Closing date',
            AppDateField(value: hotelParseYmd(_date), lastDate: hotelParseYmd(_todayIso()), onChanged: (d) => setState(() => _date = d == null ? '' : hotelYmd(d))),
          ),
          const SizedBox(height: 10),
          FilterLabel('Notes', AppInput(controller: _notes, hintText: 'Optional notes about the day')),
        ]),
      ),
      actions: [
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(style: hotelPrimary, onPressed: _saving ? null : _save, child: const Text('Close the day')),
        ]),
      ],
    );
  }
}

class _ClosingDialog extends StatelessWidget {
  const _ClosingDialog({required this.closing, required this.gh, required this.canClose});
  final HotelClosing closing;
  final FarmMoney gh;
  final bool canClose;

  Widget _tile(String label, String value, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color ?? TColors.slate900)),
        ]),
      );

  static const _head = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: TColors.slate500);

  @override
  Widget build(BuildContext context) {
    final h = closing;
    return AlertDialog(
      scrollable: true,
      title: Text('Closing — ${hotelNiceDate(h.date)}'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('ROOMS', style: _head),
          const SizedBox(height: 6),
          twoUp([
            _tile('Rooms occupied', '${h.occupied}/${h.rooms}'),
            _tile('Occupancy', '${h.occupancy.toStringAsFixed(1)}%'),
            _tile('ADR', gh(h.adr)),
            _tile('RevPAR', gh(h.revpar)),
          ]),
          const SizedBox(height: 14),
          const Text('MONEY', style: _head),
          const SizedBox(height: 6),
          twoUp([
            _tile('Revenue', gh(h.revenue), color: TColors.emerald700),
            _tile('Expenses', gh(-h.expenses), color: TColors.rose700),
            _tile('Net', gh(h.net), color: h.net < 0 ? TColors.rose700 : TColors.emerald700),
          ]),
          const SizedBox(height: 8),
          const Text('Revenue is the guest payments received that day; expenses are the expenses dated that day.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
          if (h.notes.isNotEmpty) ...[const SizedBox(height: 12), Text(h.notes, style: const TextStyle(fontSize: 13, color: TColors.slate600))],
        ]),
      ),
      actions: [
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          if (canClose)
            FilledButton.icon(
              style: hotelPrimary,
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.lock_outline, size: 16),
              label: const Text('Close this day'),
            ),
          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
        ]),
      ],
    );
  }
}

// ================================================================== Night Audit

/// The pre-audit preview: the live day plus the open work and unpaid stays.
typedef HotelAuditPreview = ({HotelLiveDay day, int pendingHousekeeping, int openMaintenance, num outstanding});

HotelAuditPreview hotelAuditPreview({
  required List<Map> roomStatus,
  required List<Map> bookings,
  required List<Map> payments,
  required List<Map> expenses,
  required List<Map> housekeeping,
  required List<Map> maintenance,
  required String today,
}) {
  num outstanding = 0;
  for (final b in bookings.where((b) => b['status'] == 'CheckedIn')) {
    final id = tIntOrNull(_v(b, 'hotelBookingId'));
    final paid = payments.where((p) => tIntOrNull(_v(p, 'hotelBookingId')) == id).fold<num>(0, (s, p) => s + tNum(p['amount']));
    outstanding += math.max(0, tNum(_v(b, 'totalAmount')) - paid);
  }
  return (
    // The audit page counts every payment dated today, voided or not.
    day: hotelLiveDay(roomStatus: roomStatus, bookings: bookings, payments: payments, expenses: expenses, today: today, skipVoid: false),
    pendingHousekeeping: housekeeping.where((h) => (h['status'] ?? h['Status']) == 'Pending').length,
    openMaintenance: maintenance.where((m) => const ['Open', 'InProgress', 'Reported'].contains(m['status'] ?? m['Status'] ?? '')).length,
    outstanding: outstanding,
  );
}

int hotelAuditIssues(HotelAuditPreview p) =>
    (p.outstanding > 0 ? 1 : 0) + (p.pendingHousekeeping > 0 ? 1 : 0) + (p.openMaintenance > 0 ? 1 : 0) + (p.day.arrivals > 0 ? 1 : 0);

const _amber50 = Color(0xFFFFFBEB), _amber200 = Color(0xFFFDE68A), _amber600 = Color(0xFFD97706), _amber700 = Color(0xFFB45309);

class HotelNightAuditScreen extends StatefulWidget {
  const HotelNightAuditScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelNightAuditScreen> createState() => _HotelNightAuditScreenState();
}

class _HotelNightAuditScreenState extends State<HotelNightAuditScreen> {
  List<Map> _audits = [];
  HotelAuditPreview _p = (
    day: (totalRooms: 0, occupied: 0, available: 0, revenue: 0, expenses: 0, arrivals: 0, departures: 0, checkedIn: 0),
    pendingHousekeeping: 0,
    openMaintenance: 0,
    outstanding: 0,
  );
  bool _loading = true;

  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {'farmId': widget.company.farmId};
    final r = await Future.wait([
      for (final p in [
        '/api/Hotel/night-audit',
        '/api/Hotel/rooms/status-summary',
        '/api/Hotel/bookings',
        '/api/Hotel/billing/payments',
        '/api/Hotel/finance/expenses',
        '/api/Hotel/housekeeping',
        '/api/Hotel/maintenance',
      ])
        _soft(_api, p, q),
    ]);
    if (!mounted) return;
    setState(() {
      _audits = hotelRows(r[0]);
      _p = hotelAuditPreview(
        roomStatus: hotelRows(r[1]),
        bookings: hotelRows(r[2]),
        payments: hotelRows(r[3]),
        expenses: hotelRows(r[4]),
        housekeeping: hotelRows(r[5]),
        maintenance: hotelRows(r[6]),
        today: _todayIso(),
      );
      _loading = false;
    });
  }

  int get _occRate => _p.day.totalRooms > 0 ? (_p.day.occupied / _p.day.totalRooms * 100).round() : 0;

  Future<void> _run() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _RunAuditDialog(session: widget.session, company: widget.company, preview: _p, occRate: _occRate),
    );
    if (done == true) _load();
  }

  Widget _card(IconData icon, Color iconColor, String value, Color valueColor, String label, {String? hint, Color? bg, Color? border}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg ?? Colors.white, border: Border.all(color: border ?? TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: valueColor))),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          if (hint != null) Text(hint, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: hotelViolet)),
        ]),
      );

  Widget _alert(IconData icon, Widget text, {bool blue = false}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: blue ? const Color(0xFFEFF6FF) : _amber50, borderRadius: BorderRadius.circular(6)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: blue ? const Color(0xFF2563EB) : _amber600),
          const SizedBox(width: 8),
          Expanded(child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 13), child: text)),
        ]),
      );

  TextSpan _b(String t, {Color? color}) => TextSpan(text: t, style: TextStyle(fontWeight: FontWeight.w700, color: color));

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-night-audit');
    final p = _p, issues = hotelAuditIssues(_p);
    final owed = p.outstanding > 0;
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Night Audit')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          _iconTitle(
            Icons.shield_outlined,
            'Night Audit',
            trailing: FilledButton.icon(style: hotelPrimary, onPressed: _run, icon: const Icon(Icons.play_arrow, size: 18), label: const Text('Run Night Audit')),
          ),
          const SizedBox(height: 14),
          if (_loading)
            _loadingBox()
          else ...[
            twoUp([
              _card(Icons.bed_outlined, hotelViolet, '${p.day.occupied}/${p.day.totalRooms}', TColors.violet700, 'Rooms Occupied', hint: '$_occRate% occupancy'),
              _card(Icons.people_outline, const Color(0xFF2563EB), '${p.day.checkedIn}', const Color(0xFF1D4ED8), 'In-House Guests'),
              _card(Icons.trending_up, const Color(0xFF059669), p.day.revenue.toStringAsFixed(0), TColors.emerald700, "Today's Revenue"),
              _card(Icons.trending_down, TColors.red600, p.day.expenses.toStringAsFixed(0), const Color(0xFFB91C1C), "Today's Expenses"),
              _card(Icons.account_balance_wallet_outlined, _amber600, p.outstanding.toStringAsFixed(0), owed ? _amber700 : TColors.emerald700, 'Outstanding',
                  bg: owed ? _amber50 : null, border: owed ? const Color(0xFFFCD34D) : null),
              _card(
                issues > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                issues > 0 ? _amber600 : const Color(0xFF059669),
                '$issues',
                issues > 0 ? _amber700 : TColors.emerald700,
                issues > 0 ? 'Issues Found' : 'All Clear',
                bg: issues > 0 ? _amber50 : const Color(0xFFECFDF5),
                border: issues > 0 ? const Color(0xFFFCD34D) : const Color(0xFF6EE7B7),
              ),
            ]),
            if (issues > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _amber200), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Row(children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: _amber700),
                    SizedBox(width: 6),
                    Text('Pre-Audit Alerts', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _amber700)),
                  ]),
                  const SizedBox(height: 10),
                  if (p.outstanding > 0)
                    _alert(Icons.account_balance_wallet_outlined,
                        Text.rich(TextSpan(children: [const TextSpan(text: 'Outstanding guest balances: '), _b(p.outstanding.toStringAsFixed(2), color: _amber700)]))),
                  if (p.pendingHousekeeping > 0)
                    _alert(Icons.assignment_outlined, Text.rich(TextSpan(children: [_b('${p.pendingHousekeeping}'), const TextSpan(text: ' pending housekeeping tasks')]))),
                  if (p.openMaintenance > 0)
                    _alert(Icons.build_outlined, Text.rich(TextSpan(children: [_b('${p.openMaintenance}'), const TextSpan(text: ' open maintenance requests')]))),
                  if (p.day.arrivals > 0)
                    _alert(Icons.people_outline,
                        Text.rich(TextSpan(children: [_b('${p.day.arrivals}'), const TextSpan(text: ' potential no-shows (confirmed but not checked in today)')]))),
                  if (p.day.departures > 0)
                    _alert(Icons.door_front_door_outlined, Text.rich(TextSpan(children: [_b('${p.day.departures}'), const TextSpan(text: ' pending check-outs for today')])),
                        blue: true),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            TCard(
              title: 'Audit History',
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: _audits.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No audits yet. Tap "Run Night Audit" to perform your first audit.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
                    )
                  : Column(children: [for (final a in _audits) _auditRow(a)]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _auditRow(Map a) {
    final out = tNum(_v(a, 'outstandingBalances'));
    final issues = tStr(a['issues'] ?? a['Issues']);
    return InkWell(
      onTap: () => showDialog<void>(context: context, builder: (_) => _AuditDetailDialog(audit: a)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate100))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(_day(_v(a, 'auditDate')), style: const TextStyle(fontWeight: FontWeight.w600))),
            _auditStatus(a),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 14, runSpacing: 6, children: [
            _kv('Rooms', '${tNum(_v(a, 'occupiedRooms')).toInt()}/${tNum(_v(a, 'totalRooms')).toInt()}'),
            _kv('Occupancy', '${tNum(_v(a, 'occupancyRate')).toStringAsFixed(1)}%'),
            _kv('Revenue', tNum(_v(a, 'totalRevenue')).toStringAsFixed(2), color: TColors.emerald700, bold: true),
            _kv('Expenses', tNum(_v(a, 'totalExpenses')).toStringAsFixed(2), color: TColors.red600),
            _kv('Outstanding', out.toStringAsFixed(2), color: out > 0 ? _amber700 : TColors.emerald700, bold: true),
            _kv('Check-ins', '${tNum(_v(a, 'checkinCount')).toInt()}'),
            _kv('Check-outs', '${tNum(_v(a, 'checkoutCount')).toInt()}'),
            _kv('No-shows', '${tNum(_v(a, 'noshowCount')).toInt()}'),
          ]),
          const SizedBox(height: 4),
          Text('Issues: ${issues.isEmpty ? 'None' : issues}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
      ),
    );
  }
}

String _day(Object? v) => tStr(v).length >= 10 ? tStr(v).substring(0, 10) : tStr(v);

Widget _kv(String k, String v, {Color? color, bool bold = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(k, style: const TextStyle(fontSize: 11, color: TColors.slate400)),
      Text(v, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : null, color: color)),
    ]);

Widget _auditStatus(Map a) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: const Color(0xFFD1FAE5), border: Border.all(color: const Color(0xFF6EE7B7)), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_outline, size: 12, color: TColors.emerald700),
        const SizedBox(width: 4),
        Text(tStr(a['status']).isEmpty ? 'Completed' : tStr(a['status']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TColors.emerald700)),
      ]),
    );

class _RunAuditDialog extends StatefulWidget {
  const _RunAuditDialog({required this.session, required this.company, required this.preview, required this.occRate});
  final Session session;
  final Company company;
  final HotelAuditPreview preview;
  final int occRate;

  @override
  State<_RunAuditDialog> createState() => _RunAuditDialogState();
}

class _RunAuditDialogState extends State<_RunAuditDialog> {
  bool _running = false;

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      final r = await widget.session.farmClient.post('/api/Hotel/night-audit', body: {'closingDate': _todayIso(), 'farmId': widget.company.farmId});
      final posted = r is Map ? tNum(r['roomchargesposted']) : 0;
      if (!mounted) return;
      trackerToast(context, 'Night audit completed successfully', description: posted > 0 ? '$posted room charge(s) auto-posted' : 'No room charges to post');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      trackerToast(context, 'Night audit failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview, d = p.day, issues = hotelAuditIssues(p);
    Widget fact(String k, String v, {Color? color}) => Text.rich(TextSpan(children: [
          TextSpan(text: '$k: '),
          TextSpan(text: v, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ]), style: const TextStyle(fontSize: 13));
    return AlertDialog(
      scrollable: true,
      title: const Row(children: [Icon(Icons.shield_outlined, color: hotelViolet), SizedBox(width: 8), Flexible(child: Text('Run Night Audit'))]),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
            'The night audit will automatically post nightly room charges for all checked-in guests and record the following for today:',
            style: TextStyle(fontSize: 13, color: TColors.slate600),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: TColors.violet50, borderRadius: BorderRadius.circular(8)),
            child: twoUp([
              fact('Rooms', '${d.occupied}/${d.totalRooms} occupied'),
              fact('Occupancy', '${widget.occRate}%'),
              fact('Revenue', d.revenue.toStringAsFixed(2), color: TColors.emerald700),
              fact('Expenses', d.expenses.toStringAsFixed(2), color: const Color(0xFFB91C1C)),
              fact('Outstanding', p.outstanding.toStringAsFixed(2), color: p.outstanding > 0 ? _amber700 : TColors.emerald700),
              fact('In-house', '${d.checkedIn} guests'),
            ]),
          ),
          if (issues > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _amber50, border: Border.all(color: _amber200), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: _amber700),
                  const SizedBox(width: 4),
                  Flexible(child: Text('$issues issue(s) will be recorded', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _amber700))),
                ]),
                const SizedBox(height: 4),
                const Text("Issues will be logged but won't block the audit.", style: TextStyle(fontSize: 12, color: _amber600)),
              ]),
            ),
          ],
        ]),
      ),
      actions: [
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: _running ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(style: hotelPrimary, onPressed: _running ? null : _run, child: const Text('Run Audit')),
        ]),
      ],
    );
  }
}

class _AuditDetailDialog extends StatelessWidget {
  const _AuditDetailDialog({required this.audit});
  final Map audit;

  Widget _count(String value, String label, {Color? color, Color bg = TColors.slate50}) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Column(children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final a = audit;
    final rev = tNum(_v(a, 'totalRevenue')), exp = tNum(_v(a, 'totalExpenses')), net = rev - exp;
    final issues = tStr(a['issues'] ?? a['Issues']);
    int n(String k) => tNum(_v(a, k)).toInt();
    return AlertDialog(
      scrollable: true,
      title: Text('Audit Details — ${_day(_v(a, 'auditDate'))}'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TColors.violet50, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Occupancy', style: TextStyle(fontSize: 12, color: TColors.slate500)),
              Text('${tNum(_v(a, 'occupancyRate')).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: TColors.violet700)),
              Text('${n('occupiedRooms')} of ${n('totalRooms')} rooms', style: const TextStyle(fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Net Revenue', style: TextStyle(fontSize: 12, color: TColors.slate500)),
              Text(net.toStringAsFixed(2), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: net >= 0 ? TColors.emerald700 : const Color(0xFFB91C1C))),
              Text('Rev: ${rev.toStringAsFixed(2)} | Exp: ${exp.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 10),
          twoUp([
            _count('${n('checkinCount')}', 'Check-ins', color: const Color(0xFF1D4ED8)),
            _count('${n('checkoutCount')}', 'Check-outs', color: TColors.slate700),
            _count('${n('noshowCount')}', 'No-shows', color: _amber700),
            _count('${n('pendingHouseTasks')}', 'Pending Housekeeping'),
            _count('${n('openMaintenance')}', 'Open Maintenance'),
            _count('${tNum(a['roomchargesposted']).toInt()}', 'Room Charges Posted', color: TColors.violet700, bg: TColors.violet50),
          ]),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _amber50, border: Border.all(color: _amber200), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Issues Recorded:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _amber700)),
                const SizedBox(height: 4),
                Text(issues, style: const TextStyle(fontSize: 13, color: Color(0xFF92400E))),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: _auditStatus(a)),
        ]),
      ),
      actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

// =============================================================== Shift Handover

const hotelShiftTypes = ['Morning', 'Afternoon', 'Night'];

const _handoverStatusColors = {
  'Draft': (TColors.slate100, TColors.slate700),
  'Submitted': (Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  'Acknowledged': (Color(0xFFD1FAE5), TColors.emerald700),
};

class HotelShiftHandoverScreen extends StatefulWidget {
  const HotelShiftHandoverScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelShiftHandoverScreen> createState() => _HotelShiftHandoverScreenState();
}

class _HotelShiftHandoverScreenState extends State<HotelShiftHandoverScreen> {
  List<Map> _items = [], _staff = [];
  bool _loading = true;

  ApiClient get _api => widget.session.farmClient;
  String get _username => widget.session.username ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {'farmId': widget.company.farmId};
    try {
      final r = await Future.wait([_api.get('/api/Hotel/shift-handovers', query: q), _soft(_api, '/api/Hotel/staff', q)]);
      if (mounted) {
        setState(() {
          _items = hotelRows(r[0]);
          _staff = [for (final s in hotelRows(r[1])) if (s['isActive'] == true || s['isactive'] == true) s];
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _new() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _HandoverDialog(session: widget.session, company: widget.company, staff: _staff, handoverBy: _username),
    );
    if (done == true) _load();
  }

  Future<void> _acknowledge(Map h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Acknowledge Handover'),
        content: SizedBox(
          width: 420,
          child: Text.rich(TextSpan(children: [
            TextSpan(text: 'You are acknowledging receipt of the ${tStr(h['shifttype'])} shift handover from '),
            TextSpan(text: tStr(h['handoverby']), style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' on ${_day(h['shiftdate'])}.'),
          ]), style: const TextStyle(fontSize: 14, color: TColors.slate600)),
        ),
        actions: [
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Acknowledge'),
            ),
          ]),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.post('/api/Hotel/shift-handovers/${h['hotelshifthandoverid']}/acknowledge',
          body: {'farmId': widget.company.farmId, 'receivedBy': _username.isEmpty ? 'Staff' : _username});
      if (mounted) trackerToast(context, 'Handover acknowledged');
      _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  Widget _note(String label, String text, Color bg) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TColors.slate400)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ]),
      );

  Widget _card(Map h) {
    final acked = h['status'] == 'Acknowledged';
    final to = tStr(h['handoverto']).isNotEmpty ? tStr(h['handoverto']) : tStr(h['receivedby']);
    final c = _handoverStatusColors[h['status']] ?? (Colors.white, TColors.slate700);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: acked ? const Color(0xFF10B981) : const Color(0xFF3B82F6), width: 4),
          top: const BorderSide(color: TColors.slate200),
          right: const BorderSide(color: TColors.slate200),
          bottom: const BorderSide(color: TColors.slate200),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(_day(h['shiftdate']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          hotelBadge('${tStr(h['shifttype'])} Shift', Colors.white, TColors.slate700),
          hotelBadge(tStr(h['status']), c.$1, c.$2),
        ]),
        const SizedBox(height: 4),
        Text.rich(TextSpan(children: [
          const TextSpan(text: 'By: '),
          TextSpan(text: tStr(h['handoverby']), style: const TextStyle(fontWeight: FontWeight.w700)),
          if (to.isNotEmpty) ...[const TextSpan(text: ' → '), TextSpan(text: to, style: const TextStyle(fontWeight: FontWeight.w700))],
        ]), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
        if (tStr(h['keymessages']).isNotEmpty) _note('Key Messages', tStr(h['keymessages']), TColors.slate50),
        if (tStr(h['pendingitems']).isNotEmpty) _note('Pending Items', tStr(h['pendingitems']), _amber50),
        if (tStr(h['vipguests']).isNotEmpty) _note('VIP Guests', tStr(h['vipguests']), TColors.violet50),
        if (tStr(h['incidents']).isNotEmpty) _note('Incidents', tStr(h['incidents']), const Color(0xFFFEF2F2)),
        if (h['cashbalance'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'Cash Balance: '),
              TextSpan(text: tNum(h['cashbalance']).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.violet700)),
            ]), style: const TextStyle(fontSize: 13)),
          ),
        if (h['status'] == 'Submitted')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                onPressed: () => _acknowledge(h),
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Acknowledge'),
              ),
            ),
          ),
        if (tStr(h['acknowledgedat']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Acknowledged at ${_local(h['acknowledgedat'])}', style: const TextStyle(fontSize: 12, color: TColors.slate400)),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-shift-handover');
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Shift Handover')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          _iconTitle(Icons.receipt_long_outlined, 'Shift Handover', trailing: hotelAddButton('New Handover', _new)),
          const SizedBox(height: 14),
          if (_loading)
            _loadingBox()
          else if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Text('No shift handovers yet. Create one to pass notes to the next shift.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
            )
          else
            for (final h in _items) _card(h),
        ]),
      ),
    );
  }
}

String _staffName(Map s) => '${tStr(_v(s, 'firstName'))} ${tStr(_v(s, 'lastName'))}';

class _HandoverDialog extends StatefulWidget {
  const _HandoverDialog({required this.session, required this.company, required this.staff, required this.handoverBy});
  final Session session;
  final Company company;
  final List<Map> staff;
  final String handoverBy;

  @override
  State<_HandoverDialog> createState() => _HandoverDialogState();
}

class _HandoverDialogState extends State<_HandoverDialog> {
  String _date = _todayIso(), _shift = 'Night', _to = '';
  late String _by = widget.handoverBy;
  final _key = TextEditingController(), _pending = TextEditingController(), _vip = TextEditingController(), _incidents = TextEditingController();
  final _cash = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_key, _pending, _vip, _incidents, _cash]) {
      c.dispose();
    }
    super.dispose();
  }

  List<AppSelectItem<String>> _people({String? except}) => [
        const AppSelectItem(value: '', label: 'Select staff'),
        // The signed-in name the form starts with, when it is not a staff row.
        if (except == null && _by.isNotEmpty && !widget.staff.any((s) => _staffName(s) == _by)) AppSelectItem(value: _by, label: _by),
        for (final s in widget.staff)
          if (_staffName(s) != except) AppSelectItem(value: _staffName(s), label: '${_staffName(s)} — ${tStr(s['role'])}'),
      ];

  Future<void> _save() async {
    if (_by.trim().isEmpty) return trackerToast(context, 'Handover by is required', error: true);
    final cash = num.tryParse(_cash.text) ?? 0;
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Hotel/shift-handovers', body: {
        'shiftDate': _date,
        'shiftType': _shift,
        'handoverBy': _by,
        'handoverTo': _to,
        'keyMessages': _key.text,
        'pendingItems': _pending.text,
        'vipGuests': _vip.text,
        'incidents': _incidents.text,
        if (cash != 0) 'cashBalance': cash,
        'farmId': widget.company.farmId,
      });
      if (!mounted) return;
      trackerToast(context, 'Shift handover submitted');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  Widget _section(String title, Color color, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.06), border: Border.all(color: color.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          ...children,
        ]),
      );

  Widget _area(TextEditingController c, String hint, int lines) => AppInput(controller: c, hintText: hint, maxLines: lines, minLines: lines);

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('New Shift Handover'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Pass notes and pending items to the incoming shift', style: TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            _section('Shift Info', const Color(0xFF4F46E5), [
              FilterLabel('Date', AppDateField(value: hotelParseYmd(_date), onChanged: (d) => setState(() => _date = d == null ? '' : hotelYmd(d)))),
              FilterLabel(
                'Shift',
                AppSelect<String>(
                  value: _shift,
                  items: [for (final s in hotelShiftTypes) AppSelectItem(value: s, label: s)],
                  onChanged: (v) => setState(() => _shift = v ?? 'Night'),
                ),
              ),
            ]),
            _section('Handover Details', const Color(0xFFD97706), [
              FilterLabel('Handover By *', AppSelect<String>(value: _by, items: _people(), onChanged: (v) => setState(() => _by = v ?? ''))),
              FilterLabel(
                'Handover To *',
                AppSelect<String>(value: _to, items: _people(except: _by), onChanged: (v) => setState(() => _to = v ?? '')),
              ),
              FilterLabel('Key Messages', _area(_key, 'Important things the next shift needs to know', 3)),
              FilterLabel('Pending Items', _area(_pending, 'Tasks not completed that need follow-up', 2)),
              FilterLabel('VIP Guests', _area(_vip, 'VIP arrivals/departures, special treatment', 2)),
              FilterLabel('Incidents', _area(_incidents, 'Any incidents or issues', 2)),
            ]),
            _section('Cash', const Color(0xFF16A34A), [
              FilterLabel(
                'Cash Balance',
                AppInput(
                  controller: _cash,
                  hintText: 'Cash on hand at end of shift',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*'))],
                ),
              ),
            ]),
          ]),
        ),
        actions: [
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(style: hotelPrimary, onPressed: _saving ? null : _save, child: const Text('Submit Handover')),
          ]),
        ],
      );
}
