// Restaurant → Dining → Reservations & Waitlist, as
// `app/restaurant-reservations/page.tsx`: the Reservations tab (day stepper,
// the day's figures, New Reservation, a row per booking with its status
// steps) and the Waitlist tab (figures, Add to Waitlist, Notify / Seat at /
// Left), with the reservation and waitlist dialogs.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart' show isoDay;
import 'restaurant_money_kit.dart' show rField, rNumberInput, rDateInput, rDialog, rConfirm, rCancel, rTodayIso;
import 'restaurant_other_select.dart';
import 'restaurant_widgets.dart';

/// STATUS_COLORS: background, text.
const reservationStatusColors = <String, (Color, Color)>{
  'Pending': (Color(0xFFFEF3C7), Color(0xFFB45309)),
  'Confirmed': (Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  'Seated': (Color(0xFFDCFCE7), Color(0xFF15803D)),
  'Completed': (Color(0xFFF3F4F6), Color(0xFF374151)),
  'Cancelled': (Color(0xFFFEE2E2), Color(0xFFB91C1C)),
  'NoShow': (Color(0xFFFECACA), Color(0xFF991B1B)),
};
const reservationOccasions = ['Birthday', 'Anniversary', 'Business', 'Date', 'Celebration'];

/// changeDate: the day [days] away from [iso].
String shiftDay(String iso, int days) {
  final d = DateTime.tryParse(iso) ?? DateTime.now();
  return isoDay(DateTime(d.year, d.month, d.day + days));
}

int _intOr(String v, int fallback) {
  final n = int.tryParse(RegExp(r'^\s*(\d+)').firstMatch(v)?.group(1) ?? '') ?? 0;
  return n == 0 ? fallback : n;
}

/// The web's `<input type="time">`: an "HH:mm" string.
class RTimeBox extends StatelessWidget {
  const RTimeBox({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
          final t = await showTimePicker(
            context: context,
            initialTime: m == null ? const TimeOfDay(hour: 19, minute: 0) : TimeOfDay(hour: int.parse(m.group(1)!), minute: int.parse(m.group(2)!)),
          );
          if (t != null) onChanged('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
        },
        child: InputDecorator(
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.schedule, size: 18)),
          child: Text(value.isEmpty ? '--:--' : value, style: const TextStyle(fontSize: 14)),
        ),
      );
}

class RestaurantReservationsScreen extends StatefulWidget {
  const RestaurantReservationsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantReservationsScreen> createState() => _RestaurantReservationsScreenState();
}

class _RestaurantReservationsScreenState extends State<RestaurantReservationsScreen> {
  bool _loading = true;
  String _tab = 'reservations';
  String _date = rTodayIso();
  List<Map> _reservations = [];
  Map? _resStats;
  List<Map> _waitlist = [];
  Map? _waitStats;
  List<Map> _tables = [];

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  Map<String, dynamic> get _q => {'farmId': _farmId};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  List<Map> _rows(Object? v) => [for (final x in (v is List ? v : const [])) if (x is Map) x];

  void _toast(String title, {String? description, bool error = false}) {
    if (mounted) trackerToast(context, title, description: description, error: error);
  }

  String _err(Object e) => e is ApiException ? e.message : '$e';

  Future<void> _loadAll() async {
    try {
      _tables = _rows(await _api.get('/api/Restaurant/floor/tables', query: {..._q, '_': 1}));
      await _loadReservations();
      await _loadWaitlist();
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadReservations() async {
    try {
      final r = await Future.wait([
        _api.get('/api/Restaurant/reservations', query: {..._q, '_': 1, 'date': _date}),
        _api.get('/api/Restaurant/reservations/stats', query: {..._q, 'date': _date}),
      ]);
      _reservations = _rows(r[0]);
      _resStats = r[1] is Map ? r[1] as Map : null;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _loadWaitlist() async {
    try {
      final r = await Future.wait([
        _api.get('/api/Restaurant/reservations/waitlist', query: {..._q, '_': 1}),
        _api.get('/api/Restaurant/reservations/waitlist/stats', query: _q),
      ]);
      _waitlist = [for (final w in _rows(r[0])) if (const ['Waiting', 'Notified'].contains(tStr(w['status']))) w];
      _waitStats = r[1] is Map ? r[1] as Map : null;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _setDate(String d) {
    setState(() => _date = d);
    _loadReservations();
  }

  Future<void> _openRes([Map? r]) async {
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => _ReservationDialog(session: widget.session, company: widget.company, tables: _tables, date: _date, editing: r),
    );
    if (saved == null) return;
    // Switch to the reservation's date so it's visible, then reload.
    if (saved.isNotEmpty && saved != _date) {
      _setDate(saved);
    } else {
      await _loadReservations();
    }
  }

  Future<void> _resStatus(Map r, String s) async {
    try {
      await _api.patch('/api/Restaurant/reservations/${r['reservationId']}/status', query: _q, body: {'status': s});
      _toast(s);
      _loadReservations();
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  Future<void> _removeRes(Map r) async {
    try {
      await _api.delete('/api/Restaurant/reservations/${r['reservationId']}', query: _q);
      _loadReservations();
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  Future<void> _openWait() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _WaitlistDialog(api: _api, farmId: _farmId));
    if (ok == true) _loadWaitlist();
  }

  Future<void> _waitStatus(Map w, String status, [Map? table]) async {
    try {
      await _api.patch('/api/Restaurant/reservations/waitlist/${w['waitlistId']}/status', query: _q, body: {
        'status': status,
        if (table != null) 'tableId': table['tableId'],
        if (table != null) 'tableNumber': table['tableNumber'],
      });
      _toast(status == 'Seated' ? 'Guest seated!' : status);
      _loadWaitlist();
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  Future<void> _removeWait(Map w) async {
    try {
      await _api.delete('/api/Restaurant/reservations/waitlist/${w['waitlistId']}', query: _q);
      _loadWaitlist();
    } catch (e) {
      _toast('Failed', description: _err(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-reservations');
    final waiting = tNum(_waitStats?['waitingCount']).toInt();
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Reservations & Waitlist')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                const RPageHeader(icon: Icons.calendar_month_outlined, title: 'Reservations & Waitlist', subtitle: 'Manage bookings and walk-in guests'),
                const SizedBox(height: 14),
                RTabs(
                  value: _tab,
                  onChanged: (v) => setState(() => _tab = v),
                  tabs: [
                    ('reservations', Icons.calendar_month_outlined, 'Reservations',
                        _resStats == null ? null : rBadge('${tNum(_resStats!['totalCount']).toInt()}')),
                    ('waitlist', Icons.people_outline, 'Waitlist', waiting > 0 ? rBadge('$waiting', bg: const Color(0xFFF59E0B), fg: Colors.white) : null),
                  ],
                ),
                const SizedBox(height: 14),
                ...(_tab == 'waitlist' ? _waitlistTab() : _reservationsTab()),
              ]),
            ),
    );
  }

  Widget _figure(String n, String label, Color color, {bool bold = false}) => Text.rich(
        TextSpan(children: [TextSpan(text: n, style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: ' $label')]),
        style: TextStyle(fontSize: 14, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
      );

  List<Widget> _reservationsTab() {
    final s = _resStats;
    return [
      Row(children: [
        IconButton.outlined(tooltip: 'Previous day', onPressed: () => _setDate(shiftDay(_date, -1)), icon: const Icon(Icons.chevron_left, size: 18)),
        const SizedBox(width: 6),
        Expanded(child: rDateInput(_date, (d) => d.isEmpty ? null : _setDate(d))),
        const SizedBox(width: 6),
        IconButton.outlined(tooltip: 'Next day', onPressed: () => _setDate(shiftDay(_date, 1)), icon: const Icon(Icons.chevron_right, size: 18)),
        const SizedBox(width: 6),
        OutlinedButton(onPressed: () => _setDate(rTodayIso()), child: const Text('Today')),
      ]),
      if (s != null) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 4, children: [
          _figure('${tNum(s['confirmedCount']).toInt()}', 'Confirmed', const Color(0xFF2563EB)),
          _figure('${tNum(s['seatedCount']).toInt()}', 'Seated', const Color(0xFF16A34A)),
          _figure('${tNum(s['totalCovers']).toInt()}', 'Covers', const Color(0xFF111827)),
          if (tNum(s['noShowCount']) > 0) _figure('${tNum(s['noShowCount']).toInt()}', 'No-Show', const Color(0xFFDC2626)),
        ]),
      ],
      const SizedBox(height: 10),
      roseButton('New Reservation', () => _openRes()),
      const SizedBox(height: 14),
      TCard(
        child: _reservations.isEmpty
            ? REmptyState(
                icon: Icons.calendar_month_outlined,
                title: 'No reservations for this date',
                description: 'Create a reservation or try a different date',
                actionLabel: 'Add Reservation',
                onAction: () => _openRes(),
              )
            : Column(children: [for (final r in _reservations) _resRow(r)]),
      ),
    ];
  }

  Widget _resRow(Map r) {
    final status = tStr(r['status']);
    final (bg, fg) = reservationStatusColors[status] ?? (const Color(0xFFF3F4F6), const Color(0xFF374151));
    const meta = _meta;
    Widget step(String label, Color color, String to, {bool outlined = false}) => outlined
        ? OutlinedButton(style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: () => _resStatus(r, to), child: Text(label))
        : FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color, visualDensity: VisualDensity.compact), onPressed: () => _resStatus(r, to), child: Text(label));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 62,
            child: Column(children: [
              Text(tStr(r['reservationTime']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
              if (tStr(r['endTime']).isNotEmpty) Text('to ${tStr(r['endTime'])}', style: const TextStyle(fontSize: 10, color: TColors.slate500)),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(tStr(r['guestName']), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                if (r['isVip'] == true) rBadge('★ VIP', bg: const Color(0xFFF3E8FF), fg: const Color(0xFF7E22CE)),
                rBadge(status, bg: bg, fg: fg),
              ]),
              const SizedBox(height: 4),
              Wrap(spacing: 12, runSpacing: 2, children: [
                meta(Icons.people_outline, '${tNum(r['partySize']).toInt()}'),
                if (tStr(r['tableNumber']).isNotEmpty) meta(Icons.place_outlined, 'Table ${tStr(r['tableNumber'])}'),
                if (tStr(r['occasion']).isNotEmpty) meta(null, tStr(r['occasion'])),
                if (tStr(r['guestPhone']).isNotEmpty) meta(Icons.phone_outlined, tStr(r['guestPhone'])),
              ]),
              if (tStr(r['specialRequests']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFB45309)),
                    const SizedBox(width: 3),
                    Expanded(child: Text(tStr(r['specialRequests']), style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)))),
                  ]),
                ),
            ]),
          ),
        ]),
        const Divider(height: 20, color: TColors.slate200),
        Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (status == 'Pending') step('Confirm', const Color(0xFF2563EB), 'Confirmed'),
          if (status == 'Confirmed') step('Seat', const Color(0xFF16A34A), 'Seated'),
          if (status == 'Seated') step('Complete', Colors.white, 'Completed', outlined: true),
          if (status == 'Confirmed' || status == 'Pending') ...[
            TextButton(
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626), visualDensity: VisualDensity.compact),
                onPressed: () => _resStatus(r, 'NoShow'),
                child: const Text('No-Show')),
            TextButton(
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444), visualDensity: VisualDensity.compact),
                onPressed: () => _resStatus(r, 'Cancelled'),
                child: const Text('Cancel')),
          ],
          IconButton(tooltip: 'Edit reservation', onPressed: () => _openRes(r), icon: const Icon(Icons.edit_outlined, size: 16)),
          IconButton(
              tooltip: 'Delete reservation', onPressed: () => _removeRes(r), icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444))),
        ]),
      ]),
    );
  }

  List<Widget> _waitlistTab() {
    final s = _waitStats;
    final longest = tNum(s?['longestWaitMins']);
    return [
      if (s != null) ...[
        Wrap(spacing: 16, runSpacing: 4, children: [
          _figure('${tNum(s['waitingCount']).toInt()}', 'Waiting', const Color(0xFFD97706)),
          _figure('${tNum(s['notifiedCount']).toInt()}', 'Notified', const Color(0xFF2563EB)),
          if (s['avgWaitMins'] != null)
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Avg: '),
              TextSpan(text: '${tNum(s['avgWaitMins']).floor()}m', style: const TextStyle(fontWeight: FontWeight.w700)),
            ])),
          if (longest > 0)
            Text('Max: ${longest.floor()}m',
                style: TextStyle(color: longest > 30 ? const Color(0xFFDC2626) : null, fontWeight: longest > 30 ? FontWeight.w700 : null)),
        ]),
        const SizedBox(height: 10),
      ],
      roseButton('Add to Waitlist', _openWait),
      const SizedBox(height: 14),
      TCard(
        child: _waitlist.isEmpty
            ? const REmptyState(
                icon: Icons.people_outline,
                title: 'No guests waiting',
                description: 'Walk-in guests will appear here when added to the waitlist',
              )
            : Column(children: [for (final (i, w) in _waitlist.indexed) _waitRow(i, w)]),
      ),
    ];
  }

  static Widget _meta(IconData? icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: TColors.slate500), const SizedBox(width: 3)],
        Text(text, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
      ]);

  Widget _waitRow(int i, Map w) {
    final status = tStr(w['status']);
    final available = [for (final t in _tables) if (tStr(t['status']) == 'Available') t];
    final actual = w['actualWaitMins'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)),
            child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tStr(w['guestName']), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827))),
              Wrap(spacing: 12, runSpacing: 2, children: [
                _meta(Icons.people_outline, '${tNum(w['partySize']).toInt()}'),
                if (tStr(w['guestPhone']).isNotEmpty) _meta(Icons.phone_outlined, tStr(w['guestPhone'])),
                _meta(Icons.schedule, actual == null ? '—' : '${tNum(actual).floor()}m'),
                if (tNum(w['quotedWaitMins']) != 0)
                  Text('(quoted ${tNum(w['quotedWaitMins']).toInt()}m)', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              ]),
            ]),
          ),
          status == 'Waiting'
              ? rBadge(status, bg: const Color(0xFFFEF3C7), fg: const Color(0xFFB45309))
              : rBadge(status, bg: const Color(0xFFDBEAFE), fg: const Color(0xFF1D4ED8)),
        ]),
        const Divider(height: 20, color: TColors.slate200),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (status == 'Waiting')
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB), visualDensity: VisualDensity.compact),
              onPressed: () => _waitStatus(w, 'Notified'),
              child: const Text('Notify'),
            ),
          if (status == 'Waiting' || status == 'Notified')
            SizedBox(
              width: 150,
              child: AppSelect<int>(
                value: null,
                hintText: 'Seat at...',
                items: [for (final t in available) AppSelectItem(value: tNum(t['tableId']).toInt(), label: 'Table ${tStr(t['tableNumber'])}')],
                onChanged: (v) {
                  final t = available.where((x) => tNum(x['tableId']).toInt() == v).firstOrNull;
                  if (t != null) _waitStatus(w, 'Seated', t);
                },
              ),
            ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444), visualDensity: VisualDensity.compact),
            onPressed: () => _waitStatus(w, 'Left'),
            child: const Text('Left'),
          ),
          IconButton(
              tooltip: 'Remove from waitlist', onPressed: () => _removeWait(w), icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444))),
        ]),
      ]),
    );
  }
}

/// New / Edit Reservation. Pops with the reservation's date once saved.
class _ReservationDialog extends StatefulWidget {
  const _ReservationDialog({required this.session, required this.company, required this.tables, required this.date, this.editing});
  final Session session;
  final Company company;
  final List<Map> tables;
  final String date;
  final Map? editing;
  @override
  State<_ReservationDialog> createState() => _ReservationDialogState();
}

class _ReservationDialogState extends State<_ReservationDialog> {
  final _occasionKey = GlobalKey<RestaurantOtherSelectState>();
  late final Map<String, Object?> _f;
  late final TextEditingController _name, _phone, _party, _requests;
  List<Map> _suggested = [];

  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    final r = widget.editing;
    _f = r == null
        ? {'reservationDate': widget.date, 'reservationTime': '19:00', 'partySize': 2, 'guestName': '', 'source': 'Phone'}
        : {
            'reservationDate': tStr(r['reservationDate']).split('T').first,
            for (final k in const ['reservationTime', 'endTime', 'partySize', 'guestName', 'guestPhone', 'guestEmail', 'tableId', 'tableNumber',
              'specialRequests', 'occasion', 'source', 'isVip', 'notes'])
              k: r[k],
          };
    _name = TextEditingController(text: tStr(_f['guestName']));
    _phone = TextEditingController(text: tStr(_f['guestPhone']));
    _party = TextEditingController(text: '${tNum(_f['partySize']).toInt()}');
    _requests = TextEditingController(text: tStr(_f['specialRequests']));
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _party, _requests]) {
      c.dispose();
    }
    super.dispose();
  }

  void _readBoxes() {
    _f['guestName'] = _name.text;
    if (_f.containsKey('guestPhone') || _phone.text.isNotEmpty) _f['guestPhone'] = _phone.text;
    _f['partySize'] = _intOr(_party.text, 2);
    if (_f.containsKey('specialRequests') || _requests.text.isNotEmpty) _f['specialRequests'] = _requests.text;
  }

  Future<void> _find() async {
    _readBoxes();
    try {
      final r = await _api.get('/api/Restaurant/reservations/auto-assign-table', query: {
        'partySize': _f['partySize'],
        'date': _f['reservationDate'],
        'time': _f['reservationTime'],
        'farmId': widget.company.farmId,
      });
      setState(() => _suggested = [for (final x in (r is List ? r : const [])) if (x is Map) x]);
    } catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e is ApiException ? e.message : '$e', error: true);
    }
  }

  void _pickTable(int? id) {
    final t = widget.tables.where((x) => tNum(x['tableId']).toInt() == id).firstOrNull;
    setState(() {
      _f['tableId'] = id;
      _f['tableNumber'] = t?['tableNumber'];
    });
  }

  Future<void> _save() async {
    _readBoxes();
    if (tStr(_f['guestName']).trim().isEmpty) {
      trackerToast(context, 'Guest name required', error: true);
      return;
    }
    final r = widget.editing;
    final body = {..._f, 'farmId': widget.company.farmId}..removeWhere((k, v) => v == null && (k == 'tableId' || k == 'tableNumber' || k == 'occasion'));
    try {
      if (r != null) {
        await _api.put('/api/Restaurant/reservations/${r['reservationId']}', body: body);
      } else {
        await _api.post('/api/Restaurant/reservations', body: body);
      }
      // An occasion typed under "Other" joins the list only once it saved.
      await _occasionKey.currentState?.remember();
      if (!mounted) return;
      trackerToast(context, r != null ? 'Updated' : 'Reservation created');
      Navigator.pop(context, tStr(_f['reservationDate']));
    } catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e is ApiException ? e.message : '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tableId = _f['tableId'] == null ? null : tNum(_f['tableId']).toInt();
    return rDialog(
      title: widget.editing != null ? 'Edit Reservation' : 'New Reservation',
      description: 'Book a table for your guest',
      children: [
        rField('Guest Name', AppInput(controller: _name), required: true),
        rField('Phone', AppInput(controller: _phone, keyboardType: TextInputType.phone)),
        rField('Date', rDateInput(tStr(_f['reservationDate']), (d) => setState(() => _f['reservationDate'] = d))),
        rField('Time', RTimeBox(value: tStr(_f['reservationTime']), onChanged: (t) => setState(() => _f['reservationTime'] = t))),
        rField('Party Size', rNumberInput(_party)),
        rField(
          'Occasion',
          RestaurantOtherSelect(
            key: _occasionKey,
            session: widget.session,
            company: widget.company,
            listKey: 'ReservationOccasion',
            baseOptions: reservationOccasions,
            value: tStr(_f['occasion']).isEmpty ? null : tStr(_f['occasion']),
            onChanged: (v) => setState(() => _f['occasion'] = v),
            placeholder: 'None',
            includeNone: true,
          ),
        ),
        rField(
          'Table',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: AppSelect<int>(
                  value: tableId ?? -1,
                  items: [
                    const AppSelectItem(value: -1, label: 'Auto-assign'),
                    for (final t in widget.tables)
                      AppSelectItem(value: tNum(t['tableId']).toInt(), label: 'Table ${tStr(t['tableNumber'])} (${tNum(t['capacity']).toInt()})'),
                  ],
                  onChanged: (v) => _pickTable(v == null || v == -1 ? null : v),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _find, child: const Text('Find')),
            ]),
            if (_suggested.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final t in _suggested)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => setState(() {
                      _f['tableId'] = t['tableId'];
                      _f['tableNumber'] = t['tableNumber'];
                    }),
                    child: Text('T${tStr(t['tableNumber'])} (${tNum(t['capacity']).toInt()})', style: const TextStyle(fontSize: 12)),
                  ),
              ]),
            ],
          ]),
        ),
        rField('Special Requests', AppInput(controller: _requests, hintText: 'e.g. Window seat, high chair')),
        AppCheckbox(value: _f['isVip'] == true, onChanged: (v) => setState(() => _f['isVip'] = v), label: 'VIP Guest'),
      ],
      actions: [rCancel(context, 'Cancel'), rConfirm(widget.editing != null ? 'Update' : 'Create Reservation', _save)],
    );
  }
}

/// Add to Waitlist.
class _WaitlistDialog extends StatefulWidget {
  const _WaitlistDialog({required this.api, required this.farmId});
  final ApiClient api;
  final String farmId;
  @override
  State<_WaitlistDialog> createState() => _WaitlistDialogState();
}

class _WaitlistDialogState extends State<_WaitlistDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _party = TextEditingController(text: '2');
  final _wait = TextEditingController(text: '15');
  final _notes = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _phone, _party, _wait, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      trackerToast(context, 'Name required', error: true);
      return;
    }
    try {
      await widget.api.post('/api/Restaurant/reservations/waitlist', body: {
        'guestName': _name.text,
        if (_phone.text.isNotEmpty) 'guestPhone': _phone.text,
        'partySize': _intOr(_party.text, 2),
        'estimatedWaitMins': _intOr(_wait.text, 15),
        if (_notes.text.isNotEmpty) 'notes': _notes.text,
        'farmId': widget.farmId,
      });
      if (!mounted) return;
      trackerToast(context, 'Added to waitlist');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e is ApiException ? e.message : '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: 'Add to Waitlist',
        description: 'Walk-in guest waiting for a table',
        children: [
          rField('Guest Name', AppInput(controller: _name), required: true),
          rField('Phone', AppInput(controller: _phone, keyboardType: TextInputType.phone)),
          rField('Party Size', rNumberInput(_party)),
          rField('Est. Wait (min)', rNumberInput(_wait)),
          rField('Notes', AppInput(controller: _notes)),
        ],
        actions: [rCancel(context, 'Cancel'), rConfirm('Add to Waitlist', _save)],
      );
}
