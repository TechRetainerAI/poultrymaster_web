// Hotel → Operations → Front Desk: Bookings (`app/hotel-bookings`, with the
// web's BookingCalendar), Guests (`app/hotel-guests`, with the loyalty
// programme) and Check-in (`app/hotel-check-in`). Amounts print as plain
// "0.00", as the web's toFixed(2).
//
// The calendar is a 14-day room-by-date chart. On the web a bar is dragged
// with the mouse; on a phone a plain drag scrolls the chart, so a bar is held
// and then dragged (its right edge stretches the stay). The booking
// confirmation the web prints in a new window is a PDF in the share sheet.
//
// API: /Hotel/bookings (+ /{id}, /{id}/cancel), /Hotel/guests (+ /search,
// /{id}), /Hotel/setup/room-types, /rooms, /profile, /id-types,
// /Hotel/billing/payments, /charges, /Hotel/front-desk/check-in,
// /Hotel/loyalty/guest/{id}, /enroll, /points, /{memberId}/transactions.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart' show MobileCardList, twoUp;
import '../poultry/reports/report_export.dart';
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import 'hotel_kit.dart';

Object? _v(Map m, String k) => m[k] ?? m[k.toLowerCase()];
String _dash(Object? v) => tStr(v).isEmpty ? '—' : tStr(v);
String _money(Object? v) => tNum(v).toStringAsFixed(2);
String _day(Object? v) => tStr(v).length >= 10 ? tStr(v).substring(0, 10) : tStr(v);
int _bookingId(Map b) => tIntOrNull(_v(b, 'hotelBookingId')) ?? 0;
String _guestName(Map b) => '${tStr(_v(b, 'guestFirstName'))} ${tStr(_v(b, 'guestLastName'))}'.trim();

/// The date part of a "2026-10-28T…" value, at midnight.
DateTime? _date(Object? v) {
  final s = _day(v);
  return s.length == 10 ? DateTime.tryParse(s) : null;
}

/// Nights between check-in and check-out, at least one.
int bookingNights(Object? checkIn, Object? checkOut) {
  final a = _date(checkIn), b = _date(checkOut);
  if (a == null || b == null) return 1;
  return math.max(1, (b.difference(a).inHours / 24).ceil());
}

String _local(Object? v) {
  final d = DateTime.tryParse(tStr(v))?.toLocal();
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day}/${d.month}/${d.year}, ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

/// fmtDateTime for a date: "28/10/2026".
String _dmy(Object? v) {
  final d = _date(v);
  return d == null ? '—' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _ymd(DateTime d) => hotelYmd(d);

Widget _title(IconData icon, String title) => Row(children: [
      Icon(icon, size: 24, color: hotelViolet),
      const SizedBox(width: 10),
      Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900))),
    ]);

Widget _loadingBox() => const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: hotelViolet)));

Widget _chip(String label, bool on, VoidCallback tap, {Color? color}) => on
    ? FilledButton(
        style: FilledButton.styleFrom(backgroundColor: color ?? hotelViolet, foregroundColor: Colors.white, minimumSize: const Size(0, 34)),
        onPressed: tap,
        child: Text(label),
      )
    : OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34)), onPressed: tap, child: Text(label));

Widget _numberCard(String label, String value, Color color, {VoidCallback? onTap}) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color))),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
      ),
    );

// ===================================================================== Bookings

const bookingStatuses = [
  ('Confirmed', 'Confirmed'),
  ('CheckedIn', 'Checked In'),
  ('CheckedOut', 'Checked Out'),
  ('Cancelled', 'Cancelled'),
  ('NoShow', 'No Show'),
];

/// STATUS_COLORS: (bg, fg).
const _bookingTone = {
  'Confirmed': (Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  'CheckedIn': (Color(0xFFD1FAE5), Color(0xFF047857)),
  'CheckedOut': (TColors.slate100, TColors.slate700),
  'Cancelled': (Color(0xFFFEE2E2), Color(0xFFB91C1C)),
  'NoShow': (Color(0xFFFEF3C7), Color(0xFFB45309)),
};

Widget bookingStatusBadge(Object? s) {
  final (bg, fg) = _bookingTone[tStr(s)] ?? (TColors.slate100, TColors.slate700);
  return hotelBadge(tStr(s), bg, fg);
}

/// The Bookings status filter and search (guest name, ref, room).
List<Map> filterBookings(List<Map> rows, {String status = 'all', String search = ''}) {
  final q = search.toLowerCase();
  return [
    for (final b in rows)
      if ((status == 'all' || tStr(b['status']) == status) &&
          (q.isEmpty ||
              _guestName(b).toLowerCase().contains(q) ||
              tStr(_v(b, 'bookingRef')).toLowerCase().contains(q) ||
              tStr(_v(b, 'roomNumber')).toLowerCase().contains(q)))
        b,
  ];
}

/// The booking reference the web gives a new booking: BK-YYYYMMDD-NNN.
String newBookingRef([DateTime? now, math.Random? rnd]) {
  final d = (now ?? DateTime.now()).toUtc();
  final n = (rnd ?? math.Random()).nextInt(999) + 1;
  return 'BK-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}-${n.toString().padLeft(3, '0')}';
}

class HotelBookingsScreen extends StatefulWidget {
  const HotelBookingsScreen({super.key, required this.session, required this.company, this.openNew = false, this.editId});
  final Session session;
  final Company company;

  /// `?new=1` (Sales → New Booking): the form opens once the lists load.
  final bool openNew;

  /// `?edit=<bookingId>` (Sales → Edit on a stay).
  final int? editId;

  @override
  State<HotelBookingsScreen> createState() => _HotelBookingsScreenState();
}

class _HotelBookingsScreenState extends State<HotelBookingsScreen> {
  List<Map> _bookings = [], _guests = [], _types = [], _rooms = [];
  Map? _profile;
  bool _loading = true, _calendar = false;
  String _status = 'all';
  final _q = TextEditingController();
  int _page = 1, _size = 10;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (!mounted) return;
      if (widget.openNew) _form();
      if (widget.editId != null) {
        final b = _bookings.where((x) => _bookingId(x) == widget.editId).firstOrNull;
        b == null ? trackerToast(context, 'Booking not found', error: true) : _form(b);
      }
    });
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {'farmId': _farmId};
    try {
      Map? profile;
      try {
        final p = await _api.get('/api/Hotel/setup/profile', query: q);
        profile = p is Map ? p : null;
      } on ApiException {
        profile = null;
      }
      final r = await Future.wait([
        _api.get('/api/Hotel/bookings', query: q),
        _api.get('/api/Hotel/guests', query: q),
        _api.get('/api/Hotel/setup/room-types', query: q),
        _api.get('/api/Hotel/rooms', query: q),
      ]);
      if (!mounted) return;
      setState(() {
        _bookings = hotelRows(r[0]);
        _guests = hotelRows(r[1]);
        _types = hotelRows(r[2]);
        _rooms = hotelRows(r[3]);
        if (profile != null) _profile = profile;
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _form([Map? editing]) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _BookingDialog(session: widget.session, company: widget.company, editing: editing, guests: _guests, types: _types, rooms: _rooms),
    );
    if (done == true) _load();
  }

  Future<void> _cancel(Map b) async {
    final ok = await hotelConfirmDelete(
      context,
      title: 'Cancel booking ${tStr(_v(b, 'bookingRef'))}?',
      message: 'Cancel booking ${tStr(_v(b, 'bookingRef'))}?',
      onConfirm: () => _api.post('/api/Hotel/bookings/${_bookingId(b)}/cancel', query: {'farmId': _farmId}),
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Booking cancelled');
    _load();
  }

  /// handleBookingMove: the calendar moved a booking to another room or other dates.
  Future<void> _move(Map b, int roomId, DateTime inDate, DateTime outDate) async {
    final nights = math.max(1, outDate.difference(inDate).inDays);
    try {
      await _api.put('/api/Hotel/bookings/${_bookingId(b)}', body: {
        'farmId': _farmId,
        'hotelGuestId': _v(b, 'hotelGuestId'),
        'hotelRoomTypeId': _v(b, 'hotelRoomTypeId'),
        'hotelRoomId': roomId,
        'checkInDate': _ymd(inDate),
        'checkOutDate': _ymd(outDate),
        'nightlyRate': tNum(_v(b, 'nightlyRate')),
        'totalAmount': nights * tNum(_v(b, 'nightlyRate')),
        'numberOfGuests': _v(b, 'numberOfGuests'),
        'adults': b['adults'],
        'children': b['children'],
        'source': b['source'],
        'specialRequests': _v(b, 'specialRequests'),
      });
      if (!mounted) return;
      final room = _rooms.where((r) => tIntOrNull(_v(r, 'hotelRoomId')) == roomId).firstOrNull;
      trackerToast(context, 'Booking ${tStr(_v(b, 'bookingRef'))} updated',
          description: roomId != tIntOrNull(_v(b, 'hotelRoomId'))
              ? 'Moved to room ${room == null ? roomId : tStr(_v(room, 'roomNumber'))}'
              : 'Dates: ${_ymd(inDate)} → ${_ymd(outDate)}');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Move failed', description: e.message, error: true);
    }
  }

  Future<void> _receipt(Map b) => showDialog<void>(
        context: context,
        builder: (_) => _ReceiptDialog(booking: b, guests: _guests, types: _types, profile: _profile),
      );

  List<Widget> _actions(Map b) => [
        IconButton(tooltip: 'Print Receipt', onPressed: () => _receipt(b), icon: const Icon(Icons.print_outlined, size: 18)),
        IconButton(tooltip: 'Edit', onPressed: () => _form(b), icon: const Icon(Icons.edit_outlined, size: 18)),
        if (tStr(b['status']) == 'Confirmed')
          IconButton(tooltip: 'Cancel booking', onPressed: () => _cancel(b), icon: const Icon(Icons.close, size: 18, color: TColors.red600)),
      ];

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-bookings');
    final filtered = filterBookings(_bookings, status: _status, search: _q.text);
    if ((_page - 1) * _size >= filtered.length && _page > 1) _page = 1;
    int n(String s) => _bookings.where((b) => b['status'] == s).length;
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Bookings')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          _title(Icons.calendar_month, 'Bookings'),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: hotelAddButton('New Booking', () => _form())),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _chip('All (${_bookings.length})', _status == 'all', () => setState(() => _status = 'all')),
            for (final (s, l) in bookingStatuses) _chip('$l (${n(s)})', _status == s, () => setState(() => _status = s)),
          ]),
          const SizedBox(height: 10),
          AppInput(controller: _q, hintText: 'Search guest name or ref...', onChanged: (_) => setState(() => _page = 1)),
          const SizedBox(height: 8),
          AppSelect<String>(
            value: _status,
            items: [const AppSelectItem(value: 'all', label: 'All statuses'), for (final (s, l) in bookingStatuses) AppSelectItem(value: s, label: l)],
            onChanged: (v) => setState(() => _status = v ?? 'all'),
          ),
          const SizedBox(height: 12),
          if (_loading)
            _loadingBox()
          else ...[
            Wrap(spacing: 6, children: [
              _chip('Table View', !_calendar, () => setState(() => _calendar = false)),
              _chip('Calendar View', _calendar, () => setState(() => _calendar = true)),
            ]),
            const SizedBox(height: 12),
            if (_calendar)
              HotelBookingCalendar(bookings: _bookings, rooms: _rooms, onBookingTap: _form, onBookingMove: _move)
            else if (filtered.isEmpty)
              TCard(
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text('No bookings found.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
                ),
              )
            else
              MobileCardList<Map>(
                striped: true,
                items: pageSlice(filtered, _page, _size),
                keyOf: (b) => '${_bookingId(b)}',
                primary: (b) => _guestName(b),
                secondary: (b) => '${tStr(_v(b, 'bookingRef'))} · ${tStr(_v(b, 'roomNumber')).isNotEmpty ? tStr(_v(b, 'roomNumber')) : tStr(_v(b, 'roomTypeName'))}',
                trailing: (b) => bookingStatusBadge(b['status']),
                details: (b) => [
                  ('Booked On', _local(_v(b, 'createdAt'))),
                  ('Check-in', _day(_v(b, 'checkInDate'))),
                  ('Check-out', _day(_v(b, 'checkOutDate'))),
                  ('Nights', '${bookingNights(_v(b, 'checkInDate'), _v(b, 'checkOutDate'))}'),
                  ('Amount', _money(_v(b, 'totalAmount'))),
                ],
                actions: _actions,
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Ref', width: 140),
                    TCol('Guest', width: 140),
                    TCol('Room', width: 90),
                    TCol('Booked On', width: 160),
                    TCol('Check-in', width: 100),
                    TCol('Check-out', width: 100),
                    TCol('Nights', width: 60),
                    TCol('Amount', right: true, width: 100),
                    TCol('Status', width: 100),
                    TCol('Actions', right: true, width: 140),
                  ],
                  rows: [
                    for (final b in items)
                      [
                        Text(tStr(_v(b, 'bookingRef')), style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600)),
                        cellText(_guestName(b)),
                        cellText(tStr(_v(b, 'roomNumber')).isNotEmpty ? tStr(_v(b, 'roomNumber')) : tStr(_v(b, 'roomTypeName'))),
                        cellText(_local(_v(b, 'createdAt'))),
                        cellText(_day(_v(b, 'checkInDate'))),
                        cellText(_day(_v(b, 'checkOutDate'))),
                        cellText('${bookingNights(_v(b, 'checkInDate'), _v(b, 'checkOutDate'))}'),
                        cellText(_money(_v(b, 'totalAmount')), bold: true),
                        Align(alignment: Alignment.centerLeft, child: bookingStatusBadge(b['status'])),
                        Wrap(alignment: WrapAlignment.end, children: _actions(b)),
                      ],
                  ],
                ),
                pager: CompactPager(
                  total: filtered.length,
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

class _BookingDialog extends StatefulWidget {
  const _BookingDialog({required this.session, required this.company, required this.editing, required this.guests, required this.types, required this.rooms});
  final Session session;
  final Company company;
  final Map? editing;
  final List<Map> guests, types, rooms;

  @override
  State<_BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<_BookingDialog> {
  late final Map? e = widget.editing;
  late int _guest, _type;
  int? _room;
  late String _in, _out, _source;
  late final TextEditingController _rate, _adults, _children, _requests;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b = e;
    if (b != null) {
      _guest = tIntOrNull(_v(b, 'hotelGuestId')) ?? 0;
      _type = tIntOrNull(_v(b, 'hotelRoomTypeId')) ?? 0;
      _room = tIntOrNull(_v(b, 'hotelRoomId'));
      _in = _day(_v(b, 'checkInDate'));
      _out = _day(_v(b, 'checkOutDate'));
      _source = tStr(b['source']).isEmpty ? 'WalkIn' : tStr(b['source']);
      _rate = TextEditingController(text: _plain(tNum(_v(b, 'nightlyRate'))));
      _adults = TextEditingController(text: tStr(b['adults']).isEmpty ? '1' : tStr(b['adults']));
      _children = TextEditingController(text: tStr(b['children']).isEmpty ? '0' : tStr(b['children']));
      _requests = TextEditingController(text: tStr(_v(b, 'specialRequests')));
    } else {
      final now = DateTime.now().toUtc();
      _guest = widget.guests.isEmpty ? 0 : tIntOrNull(_v(widget.guests.first, 'hotelGuestId')) ?? 0;
      _type = widget.types.isEmpty ? 0 : tIntOrNull(_v(widget.types.first, 'hotelRoomTypeId')) ?? 0;
      _in = now.toIso8601String().substring(0, 10);
      _out = now.add(const Duration(days: 1)).toIso8601String().substring(0, 10);
      _source = 'WalkIn';
      _rate = TextEditingController(text: widget.types.isEmpty ? '0' : _plain(tNum(_v(widget.types.first, 'baseRate'))));
      _adults = TextEditingController(text: '1');
      _children = TextEditingController(text: '0');
      _requests = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in [_rate, _adults, _children, _requests]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';
  num get _rateNum => num.tryParse(_rate.text) ?? 0;
  int get _adultsNum => int.tryParse(_adults.text) ?? 0;
  int get _childrenNum => int.tryParse(_children.text) ?? 0;

  /// calcTotal: nights × rate.
  num get _total => bookingNights(_in, _out) * _rateNum;

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = <String, Object?>{
      'farmId': widget.company.farmId,
      'hotelGuestId': _guest,
      'hotelRoomTypeId': _type,
      'hotelRoomId': _room,
      'checkInDate': _in,
      'checkOutDate': _out,
      'nightlyRate': _rateNum,
      'totalAmount': _total,
      'numberOfGuests': _adultsNum + _childrenNum,
      'adults': _adultsNum,
      'children': _childrenNum,
      'source': _source,
      if (e != null || _requests.text.isNotEmpty) 'specialRequests': _requests.text,
    };
    try {
      final api = widget.session.farmClient;
      if (e != null) {
        await api.put('/api/Hotel/bookings/${_bookingId(e!)}', body: body);
        if (mounted) trackerToast(context, 'Booking updated');
      } else {
        await api.post('/api/Hotel/bookings', body: {...body, 'bookingRef': newBookingRef(), 'status': 'Confirmed'});
        if (mounted) trackerToast(context, 'Booking created');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (x) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Save failed', description: x.message, error: true);
    }
  }

  Widget _readOnly(String v) => Container(
        height: 44,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
        child: Text(v),
      );

  Widget _numberField(TextEditingController c) => AppInput(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final freeRooms = [
      for (final r in widget.rooms)
        if (tStr(r['status']) == 'Available' && tIntOrNull(_v(r, 'hotelRoomTypeId')) == _type) r,
    ];
    return HotelDialog(
      icon: Icons.calendar_month,
      title: e != null ? 'Edit Booking ${tStr(_v(e!, 'bookingRef'))}' : 'New Booking',
      saveLabel: e != null ? 'Update' : 'Create',
      saving: _saving,
      onSave: _save,
      children: [
        FilterLabel(
          'Guest',
          AppSelect<int>(
            value: widget.guests.any((g) => tIntOrNull(_v(g, 'hotelGuestId')) == _guest) ? _guest : null,
            items: [
              for (final g in widget.guests)
                AppSelectItem(value: tIntOrNull(_v(g, 'hotelGuestId')) ?? 0, label: '${tStr(_v(g, 'firstName'))} ${tStr(_v(g, 'lastName'))}'),
            ],
            onChanged: (v) => setState(() => _guest = v ?? _guest),
          ),
        ),
        FilterLabel(
          'Room Type',
          AppSelect<int>(
            value: widget.types.any((t) => tIntOrNull(_v(t, 'hotelRoomTypeId')) == _type) ? _type : null,
            items: [for (final t in widget.types) AppSelectItem(value: tIntOrNull(_v(t, 'hotelRoomTypeId')) ?? 0, label: tStr(t['name']))],
            onChanged: (v) => setState(() {
              _type = v ?? _type;
              final rt = widget.types.where((t) => tIntOrNull(_v(t, 'hotelRoomTypeId')) == _type).firstOrNull;
              if (rt != null) _rate.text = _plain(tNum(_v(rt, 'baseRate')));
            }),
          ),
        ),
        FilterLabel(
          'Room (optional)',
          AppSelect<int>(
            value: freeRooms.any((r) => tIntOrNull(_v(r, 'hotelRoomId')) == _room) ? _room : null,
            hintText: 'Assign later',
            items: [for (final r in freeRooms) AppSelectItem(value: tIntOrNull(_v(r, 'hotelRoomId')) ?? 0, label: tStr(_v(r, 'roomNumber')))],
            onChanged: (v) => setState(() => _room = v),
          ),
        ),
        FilterLabel('Check-in', AppDateField(value: hotelParseYmd(_in), onChanged: (d) => setState(() => _in = d == null ? _in : _ymd(d)))),
        FilterLabel('Check-out', AppDateField(value: hotelParseYmd(_out), onChanged: (d) => setState(() => _out = d == null ? _out : _ymd(d)))),
        FilterLabel(
          'Nightly Rate',
          AppInput(
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
            onChanged: (_) => setState(() {}),
          ),
        ),
        FilterLabel('Total', _readOnly(_plain(_total))),
        FilterLabel(
          'Source',
          AppSelect<String>(
            value: _source,
            items: const [
              AppSelectItem(value: 'WalkIn', label: 'Walk-in'),
              AppSelectItem(value: 'Phone', label: 'Phone'),
              AppSelectItem(value: 'Online', label: 'Online'),
              AppSelectItem(value: 'Agent', label: 'Agent'),
            ],
            onChanged: (v) => setState(() => _source = v ?? 'WalkIn'),
          ),
        ),
        FilterLabel('Adults', _numberField(_adults)),
        FilterLabel('Children', _numberField(_children)),
        FilterLabel('Total Guests', _readOnly('${_adultsNum + _childrenNum}')),
        FilterLabel('Special Requests', AppInput(controller: _requests, hintText: 'Any special requirements...')),
      ],
    );
  }
}

/// The Booking Confirmation, as the web's receipt dialog; Print hands a PDF to the share sheet.
class _ReceiptDialog extends StatelessWidget {
  const _ReceiptDialog({required this.booking, required this.guests, required this.types, required this.profile});
  final Map booking;
  final List<Map> guests, types;
  final Map? profile;

  Map? get _guest => guests.where((g) => tIntOrNull(_v(g, 'hotelGuestId')) == tIntOrNull(_v(booking, 'hotelGuestId'))).firstOrNull;
  Map? get _type => types.where((t) => tIntOrNull(_v(t, 'hotelRoomTypeId')) == tIntOrNull(_v(booking, 'hotelRoomTypeId'))).firstOrNull;

  /// Every line the receipt shows, so the screen and the PDF say the same.
  List<(String, List<(String, String)>)> _sections() {
    final b = booking, g = _guest, rt = _type;
    final nights = bookingNights(_v(b, 'checkInDate'), _v(b, 'checkOutDate'));
    final adults = tIntOrNull(b['adults']) ?? 1, children = tIntOrNull(b['children']) ?? 0;
    return [
      (
        'Guest Details',
        [
          ('Name', '${tStr(_v(g ?? b, g == null ? 'guestFirstName' : 'firstName'))} ${tStr(_v(g ?? b, g == null ? 'guestLastName' : 'lastName'))}'.trim()),
          ('Phone', _dash(g?['phone'] ?? _v(b, 'guestPhone'))),
          ('Email', _dash(g?['email'] ?? _v(b, 'guestEmail'))),
          if (g != null && tStr(_v(g, 'idType')).isNotEmpty) ('ID', '${tStr(_v(g, 'idType'))}: ${tStr(_v(g, 'idNumber'))}'),
        ]
      ),
      (
        'Reservation Details',
        [
          ('Room Type', rt != null ? tStr(rt['name']) : tStr(_v(b, 'roomTypeName'))),
          ('Room', tStr(_v(b, 'roomNumber')).isEmpty ? 'To be assigned' : tStr(_v(b, 'roomNumber'))),
          ('Check-in', _dmy(_v(b, 'checkInDate'))),
          ('Check-out', _dmy(_v(b, 'checkOutDate'))),
          ('Nights', '$nights'),
          ('Guests', '$adults Adult${adults > 1 ? 's' : ''}${children > 0 ? ', $children Child${children > 1 ? 'ren' : ''}' : ''}'),
          ('Source', tStr(b['source'])),
          ('Status', tStr(b['status'])),
        ]
      ),
    ];
  }

  String get _hotelName => tStr(profile?['hotelName']).isEmpty ? 'Hotel' : tStr(profile!['hotelName']);
  String get _address {
    final p = profile;
    if (p == null || tStr(p['address']).isEmpty) return '';
    return '${tStr(p['address'])}${tStr(p['city']).isNotEmpty ? ', ${tStr(p['city'])}' : ''}${tStr(p['country']).isNotEmpty ? ', ${tStr(p['country'])}' : ''}';
  }

  String get _contact {
    final p = profile;
    if (p == null || tStr(p['phone']).isEmpty) return '';
    return 'Tel: ${tStr(p['phone'])}${tStr(p['email']).isNotEmpty ? ' | ${tStr(p['email'])}' : ''}';
  }

  List<String> get _footer => [
        'Check-in time: ${tStr(profile?['checkInTime']).isEmpty ? '14:00' : tStr(profile!['checkInTime'])} | Check-out time: ${tStr(profile?['checkOutTime']).isEmpty ? '12:00' : tStr(profile!['checkOutTime'])}',
        'Booked on: ${_local(_v(booking, 'createdAt'))}',
        'Thank you for choosing ${tStr(profile?['hotelName']).isEmpty ? 'our hotel' : tStr(profile!['hotelName'])}!',
      ];

  Future<void> _print() async {
    final doc = pw.Document();
    final b = booking;
    final nights = bookingNights(_v(b, 'checkInDate'), _v(b, 'checkOutDate'));
    pw.Widget row(String k, String v, {bool bold = false}) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(k, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text(v, style: pw.TextStyle(fontSize: bold ? 12 : 9, fontWeight: bold ? pw.FontWeight.bold : null)),
        ]);
    doc.addPage(pw.Page(
      pageFormat: const PdfPageFormat(100 * PdfPageFormat.mm, double.infinity, marginAll: 6 * PdfPageFormat.mm),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Text(_hotelName, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple)),
        if (_address.isNotEmpty) pw.Text(_address, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8)),
        if (_contact.isNotEmpty) pw.Text(_contact, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 4),
        pw.Text('BOOKING CONFIRMATION', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple)),
        pw.Divider(),
        row('Booking Ref:', tStr(_v(b, 'bookingRef')), bold: true),
        for (final (title, lines) in _sections()) ...[
          pw.SizedBox(height: 6),
          pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          for (final (k, v) in lines) row('$k:', v),
        ],
        pw.Divider(),
        pw.Text('Pricing', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        row('Nightly Rate:', _money(_v(b, 'nightlyRate'))),
        row('Number of Nights:', '$nights'),
        row('Total Amount:', _money(_v(b, 'totalAmount')), bold: true),
        if (tStr(_v(b, 'specialRequests')).isNotEmpty) ...[
          pw.Divider(),
          pw.Text('Special Requests', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text(tStr(_v(b, 'specialRequests')), style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic)),
        ],
        pw.Divider(),
        for (final f in _footer) pw.Text(f, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey)),
      ]),
    ));
    await ReportExport.sharer('Booking_${tStr(_v(b, 'bookingRef'))}.pdf', await doc.save(), 'application/pdf', 'Booking Confirmation - ${tStr(_v(b, 'bookingRef'))}');
  }

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final nights = bookingNights(_v(b, 'checkInDate'), _v(b, 'checkOutDate'));
    Widget line(String k, Widget v) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$k: ', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            Expanded(child: v),
          ]),
        );
    Widget strong(String v) => Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700));
    return AlertDialog(
      scrollable: true,
      title: const Row(children: [
        Icon(Icons.print_outlined, color: hotelViolet, size: 20),
        SizedBox(width: 8),
        Flexible(child: Text('Booking Confirmation')),
      ]),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_hotelName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: TColors.violet700)),
          if (_address.isNotEmpty) Text(_address, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          if (_contact.isNotEmpty) Text(_contact, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          const SizedBox(height: 6),
          const Text('BOOKING CONFIRMATION', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: hotelViolet)),
          const Divider(),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: TColors.violet50, borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              const Expanded(child: Text('Booking Ref:', style: TextStyle(color: TColors.slate600))),
              Text(tStr(_v(b, 'bookingRef')), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, color: TColors.violet700)),
            ]),
          ),
          for (final (title, lines) in _sections()) ...[
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.slate700)),
            const SizedBox(height: 4),
            for (final (k, v) in lines) line(k, k == 'Status' ? Align(alignment: Alignment.centerLeft, child: bookingStatusBadge(v)) : strong(v)),
          ],
          const Divider(height: 20),
          const Text('Pricing', style: TextStyle(fontWeight: FontWeight.w600, color: TColors.slate700)),
          const SizedBox(height: 4),
          Row(children: [const Expanded(child: Text('Nightly Rate:', style: TextStyle(fontSize: 12))), Text(_money(_v(b, 'nightlyRate')), style: const TextStyle(fontSize: 12))]),
          Row(children: [const Expanded(child: Text('Number of Nights:', style: TextStyle(fontSize: 12))), Text('$nights', style: const TextStyle(fontSize: 12))]),
          const Divider(height: 10),
          Row(children: [
            const Expanded(child: Text('Total Amount:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            Text(_money(_v(b, 'totalAmount')), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: TColors.violet700)),
          ]),
          if (tStr(_v(b, 'specialRequests')).isNotEmpty) ...[
            const Divider(height: 20),
            const Text('Special Requests', style: TextStyle(fontWeight: FontWeight.w600, color: TColors.slate700)),
            Text(tStr(_v(b, 'specialRequests')), style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: TColors.slate600)),
          ],
          const Divider(height: 20),
          for (final f in _footer) Text(f, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: TColors.slate400)),
        ]),
      ),
      actions: [
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton.icon(style: hotelPrimary, onPressed: _print, icon: const Icon(Icons.print_outlined, size: 16), label: const Text('Print')),
        ]),
      ],
    );
  }
}

// ============================================================ BookingCalendar

/// The bars' STATUS_COLORS: (bg, border, text).
const _barTone = {
  'Confirmed': (Color(0xFFBFDBFE), Color(0xFF60A5FA), Color(0xFF1E3A8A)),
  'CheckedIn': (Color(0xFFA7F3D0), Color(0xFF34D399), Color(0xFF064E3B)),
  'CheckedOut': (TColors.slate200, TColors.slate400, TColors.slate700),
  'Cancelled': (Color(0xFFFEE2E2), Color(0xFFFCA5A5), Color(0xFFB91C1C)),
  'NoShow': (Color(0xFFFDE68A), Color(0xFFFBBF24), Color(0xFF78350F)),
};

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// `components/hotel/booking-calendar.tsx`: 14 days across, rooms down (grouped
/// by floor), each booking a bar. Tap a bar to edit it; hold a bar and drag to
/// move it (sideways for dates, up or down for the room); hold its right edge
/// and drag to change the check-out.
class HotelBookingCalendar extends StatefulWidget {
  const HotelBookingCalendar({super.key, required this.bookings, required this.rooms, required this.onBookingTap, required this.onBookingMove, this.today});
  final List<Map> bookings, rooms;
  final void Function(Map booking) onBookingTap;
  final Future<void> Function(Map booking, int roomId, DateTime checkIn, DateTime checkOut) onBookingMove;

  /// Today, at midnight (tests pass a fixed one).
  final DateTime? today;

  static const days = 14;
  static const dayWidth = 56.0, roomWidth = 112.0, rowHeight = 40.0;

  @override
  State<HotelBookingCalendar> createState() => _HotelBookingCalendarState();
}

class _HotelBookingCalendarState extends State<HotelBookingCalendar> {
  late final DateTime _today = _midnight(widget.today ?? DateTime.now());
  late DateTime _start = _today;

  // The drag in progress: the booking, move or resize, and how far.
  Map? _drag;
  bool _resize = false;
  int _dragDays = 0, _dragRows = 0;

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);
  static int _between(DateTime a, DateTime b) => (b.difference(a).inHours / 24).round();

  String _floorOf(Map r) => tStr(_v(r, 'floorName')).isNotEmpty
      ? tStr(_v(r, 'floorName'))
      : (_v(r, 'floorNumber') != null ? tStr(_v(r, 'floorNumber')) : 'Unassigned');

  List<Map> get _ordered => [...widget.rooms]..sort((a, b) {
      final fa = tStr(_v(a, 'floorName')).isNotEmpty ? tStr(_v(a, 'floorName')) : (_v(a, 'floorNumber') != null ? tStr(_v(a, 'floorNumber')) : 'Z');
      final fb = tStr(_v(b, 'floorName')).isNotEmpty ? tStr(_v(b, 'floorName')) : (_v(b, 'floorNumber') != null ? tStr(_v(b, 'floorNumber')) : 'Z');
      if (fa != fb) return fa.compareTo(fb);
      final na = int.tryParse(tStr(_v(a, 'roomNumber'))), nb = int.tryParse(tStr(_v(b, 'roomNumber')));
      return na != null && nb != null ? na.compareTo(nb) : tStr(_v(a, 'roomNumber')).compareTo(tStr(_v(b, 'roomNumber')));
    });

  bool _canDrag(Map b) => b['status'] == 'Confirmed' || b['status'] == 'CheckedIn';

  /// Where a bar sits, in days from the first column, after any drag.
  (int, int)? _span(Map b, {int offset = 0, int resize = 0}) {
    var s = _date(_v(b, 'checkInDate')), e = _date(_v(b, 'checkOutDate'));
    if (s == null || e == null) return null;
    s = s.add(Duration(days: offset));
    e = e.add(Duration(days: offset + resize));
    final end = _start.add(const Duration(days: HotelBookingCalendar.days));
    final vs = s.isAfter(_start) ? s : _start, ve = e.isBefore(end) ? e : end;
    final left = _between(_start, vs), width = _between(vs, ve);
    return width <= 0 ? null : (left, width);
  }

  Future<void> _finish(Map b, List<Map> rows) async {
    final days = _dragDays, rowsMoved = _dragRows, resize = _resize;
    setState(() {
      _drag = null;
      _dragDays = 0;
      _dragRows = 0;
    });
    final inDate = _date(_v(b, 'checkInDate')), outDate = _date(_v(b, 'checkOutDate'));
    if (inDate == null || outDate == null) return;
    if (resize) {
      if (days == 0) return;
      final stay = _between(inDate, outDate);
      final d = math.max(-stay + 1, days);
      await widget.onBookingMove(b, tIntOrNull(_v(b, 'hotelRoomId')) ?? 0, inDate, outDate.add(Duration(days: d)));
      return;
    }
    final at = rows.indexWhere((r) => tIntOrNull(_v(r, 'hotelRoomId')) == tIntOrNull(_v(b, 'hotelRoomId')));
    final target = at < 0 ? null : rows[(at + rowsMoved).clamp(0, rows.length - 1)];
    final roomId = tIntOrNull(_v(target ?? b, 'hotelRoomId')) ?? 0;
    if (days == 0 && roomId == tIntOrNull(_v(b, 'hotelRoomId'))) return;
    await widget.onBookingMove(b, roomId, inDate.add(Duration(days: days)), outDate.add(Duration(days: days)));
  }

  Widget _bar(Map b, List<Map> rows) {
    final dragging = identical(_drag, b);
    final span = _span(b, offset: dragging && !_resize ? _dragDays : 0, resize: dragging && _resize ? _dragDays : 0);
    if (span == null) return const SizedBox.shrink();
    final (bg, border, text) = _barTone[tStr(b['status'])] ?? _barTone['Confirmed']!;
    final name = _guestName(b).isEmpty ? tStr(_v(b, 'bookingRef')) : _guestName(b);
    final canDrag = _canDrag(b);
    const dw = HotelBookingCalendar.dayWidth;

    void start(bool resize) => setState(() {
          _drag = b;
          _resize = resize;
          _dragDays = 0;
          _dragRows = 0;
        });
    void update(Offset o) => setState(() {
          _dragDays = (o.dx / dw).round();
          if (!_resize) _dragRows = (o.dy / HotelBookingCalendar.rowHeight).round();
        });

    return Positioned(
      left: span.$1 * dw,
      width: span.$2 * dw,
      top: 4,
      bottom: 4,
      child: Transform.translate(
        offset: Offset(0, dragging && !_resize ? _dragRows * HotelBookingCalendar.rowHeight : 0),
        child: GestureDetector(
          onTap: () => widget.onBookingTap(b),
          onLongPressStart: canDrag ? (_) => start(false) : null,
          onLongPressMoveUpdate: canDrag ? (d) => update(d.offsetFromOrigin) : null,
          onLongPressEnd: canDrag ? (_) => _finish(b, rows) : null,
          // The web's hover title; a tooltip would claim the hold the drag needs.
          child: Semantics(
            label: '$name | ${tStr(_v(b, 'bookingRef'))} | ${_day(_v(b, 'checkInDate'))} → ${_day(_v(b, 'checkOutDate'))}',
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                border: Border.all(color: dragging ? hotelViolet : border, width: dragging ? 2 : 1),
                borderRadius: BorderRadius.circular(6),
                boxShadow: dragging ? const [BoxShadow(color: Color(0x33000000), blurRadius: 6)] : null,
              ),
              child: Row(children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: text)),
                  ),
                ),
                if (canDrag)
                  GestureDetector(
                    onLongPressStart: (_) => start(true),
                    onLongPressMoveUpdate: (d) => update(d.offsetFromOrigin),
                    onLongPressEnd: (_) => _finish(b, rows),
                    child: Container(width: 14, alignment: Alignment.center, child: Container(width: 2, height: 12, color: text.withValues(alpha: .3))),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime d, {bool year = false}) => '${_months[d.month - 1]} ${d.day}${year ? ', ${d.year}' : ''}';

  @override
  Widget build(BuildContext context) {
    const days = HotelBookingCalendar.days, dw = HotelBookingCalendar.dayWidth, rw = HotelBookingCalendar.roomWidth;
    final dates = [for (var i = 0; i < days; i++) _start.add(Duration(days: i))];
    final rows = _ordered;
    final floors = <String, List<Map>>{};
    for (final r in rows) {
      floors.putIfAbsent(_floorOf(r), () => []).add(r);
    }
    final end = _start.add(const Duration(days: days));
    List<Map> barsFor(Map room) => [
          for (final b in widget.bookings)
            if (tIntOrNull(_v(b, 'hotelRoomId')) == tIntOrNull(_v(room, 'hotelRoomId')) && b['status'] != 'Cancelled')
              if (() {
                final s = _date(_v(b, 'checkInDate')), e = _date(_v(b, 'checkOutDate'));
                return s != null && e != null && s.isBefore(end) && e.isAfter(_start);
              }())
                b,
        ];

    Color? dayTint(DateTime d) => d == _today ? TColors.violet50 : (d.weekday >= 6 ? TColors.slate50 : null);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        IconButton.outlined(tooltip: 'Previous 14 days', onPressed: () => setState(() => _start = _start.subtract(const Duration(days: days))), icon: const Icon(Icons.chevron_left, size: 18)),
        OutlinedButton(onPressed: () => setState(() => _start = _today), child: const Text('Today')),
        IconButton.outlined(tooltip: 'Next 14 days', onPressed: () => setState(() => _start = _start.add(const Duration(days: days))), icon: const Icon(Icons.chevron_right, size: 18)),
        Text('${_fmt(_start)} — ${_fmt(dates.last, year: true)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.slate700)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final e in _barTone.entries)
          if (e.key != 'Cancelled')
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: e.value.$1, border: Border.all(color: e.value.$2), borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 4),
              Text(e.key, style: const TextStyle(fontSize: 11, color: TColors.slate600)),
            ]),
        const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.drag_indicator, size: 12, color: hotelViolet),
          SizedBox(width: 2),
          Text('Hold and drag to move/resize', style: TextStyle(fontSize: 11, color: hotelViolet)),
        ]),
      ]),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          // The 1 px border on each side sits outside the columns.
          width: rw + dw * days + 2,
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: TColors.slate50,
              child: Row(children: [
                const SizedBox(
                  width: rw,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Row(children: [
                      Icon(Icons.calendar_today, size: 12, color: TColors.slate500),
                      SizedBox(width: 4),
                      Text('Room', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TColors.slate500)),
                    ]),
                  ),
                ),
                for (final d in dates)
                  Container(
                    width: dw,
                    color: d == _today ? TColors.violet100 : (d.weekday >= 6 ? TColors.slate100 : null),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(children: [
                      Text(_weekdays[d.weekday - 1].toUpperCase(),
                          style: TextStyle(fontSize: 10, color: d == _today ? TColors.violet700 : TColors.slate400, fontWeight: d == _today ? FontWeight.w700 : null)),
                      Text('${d.day}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: d == _today ? TColors.violet700 : TColors.slate600)),
                    ]),
                  ),
              ]),
            ),
            if (floors.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No rooms configured. Add rooms in Hotel Setup first.', style: TextStyle(color: TColors.slate400)),
              )
            else
              for (final f in floors.entries) ...[
                Container(
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: TColors.slate200))),
                  padding: const EdgeInsets.all(6),
                  alignment: Alignment.centerLeft,
                  child: hotelBadge(f.key, TColors.violet50, TColors.violet700),
                ),
                for (final room in f.value)
                  Container(
                    height: HotelBookingCalendar.rowHeight,
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: TColors.slate200))),
                    child: Row(children: [
                      SizedBox(
                        width: rw,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(children: [
                            Text(tStr(_v(room, 'roomNumber')), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate700)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(tStr(_v(room, 'roomTypeName')), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: TColors.slate400)),
                            ),
                          ]),
                        ),
                      ),
                      SizedBox(
                        width: dw * days,
                        child: Stack(clipBehavior: Clip.none, children: [
                          Row(children: [
                            for (final d in dates)
                              Container(width: dw, decoration: BoxDecoration(color: dayTint(d), border: const Border(left: BorderSide(color: TColors.slate100)))),
                          ]),
                          for (final b in barsFor(room)) _bar(b, rows),
                        ]),
                      ),
                    ]),
                  ),
              ],
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        '${widget.rooms.length} rooms · ${widget.bookings.where((b) => b['status'] != 'Cancelled').length} active bookings · Hold and drag Confirmed/CheckedIn bookings to move or resize',
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 11, color: TColors.slate400),
      ),
    ]);
  }
}

// ===================================================================== Guests

class HotelGuestsScreen extends StatefulWidget {
  const HotelGuestsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelGuestsScreen> createState() => _HotelGuestsScreenState();
}

class _HotelGuestsScreenState extends State<HotelGuestsScreen> {
  List<Map> _guests = [], _bookings = [], _payments = [], _idTypes = [];
  bool _loading = true, _vip = false;
  final _q = TextEditingController();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {'farmId': _farmId};
    Future<Object?> soft(String p) async {
      try {
        return await _api.get(p, query: q);
      } on ApiException {
        return const [];
      }
    }

    try {
      final search = _q.text.trim();
      final r = await Future.wait([
        search.isEmpty ? _api.get('/api/Hotel/guests', query: q) : _api.get('/api/Hotel/guests/search', query: {...q, 'q': search}),
        soft('/api/Hotel/bookings'),
        soft('/api/Hotel/billing/payments'),
        soft('/api/Hotel/setup/id-types'),
      ]);
      if (!mounted) return;
      setState(() {
        _guests = hotelRows(r[0]);
        _bookings = hotelRows(r[1]);
        _payments = hotelRows(r[2]);
        _idTypes = hotelRows(r[3]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load guests', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _gid(Map g) => tIntOrNull(_v(g, 'hotelGuestId')) ?? 0;
  String _name(Map g) => '${tStr(_v(g, 'firstName'))} ${tStr(_v(g, 'lastName'))}';
  bool _isVip(Map g) => _v(g, 'isVIP') == true || g['isVip'] == true || g['isvip'] == true;
  String _id(Map g) => tStr(_v(g, 'idType')).isNotEmpty ? '${tStr(_v(g, 'idType'))}: ${tStr(_v(g, 'idNumber'))}' : '—';

  Future<void> _form([Map? editing]) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _GuestDialog(session: widget.session, company: widget.company, editing: editing, idTypes: [for (final t in _idTypes) tStr(t['description'])]),
    );
    if (done == true) _load();
  }

  Future<void> _delete(Map g) async {
    final ok = await hotelConfirmDelete(
      context,
      title: 'Delete ${_name(g)}?',
      message: 'Delete ${_name(g)}?',
      onConfirm: () => _api.delete('/api/Hotel/guests/${_gid(g)}', query: {'farmId': _farmId}),
    );
    if (!ok || !mounted) return;
    trackerToast(context, 'Guest deleted');
    _load();
  }

  Future<void> _profile(Map g) async {
    final edit = await showDialog<bool>(
      context: context,
      builder: (_) => _GuestProfileDialog(
        session: widget.session,
        company: widget.company,
        guest: g,
        bookings: [for (final b in _bookings) if (tIntOrNull(_v(b, 'hotelGuestId')) == _gid(g)) b],
        payments: _payments,
        vip: _isVip(g),
      ),
    );
    if (edit == true) _form(g);
  }

  List<Widget> _actions(Map g) => [
        IconButton(tooltip: 'View', onPressed: () => _profile(g), icon: const Icon(Icons.visibility_outlined, size: 18)),
        IconButton(tooltip: 'Edit', onPressed: () => _form(g), icon: const Icon(Icons.edit_outlined, size: 18)),
        IconButton(tooltip: 'Delete', onPressed: () => _delete(g), icon: const Icon(Icons.delete_outline, size: 18, color: TColors.red600)),
      ];

  Widget _vipBadge() => hotelBadge('★ VIP', const Color(0xFFFEF3C7), const Color(0xFFB45309));

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-guests');
    final filtered = [for (final g in _guests) if (!_vip || _isVip(g)) g];
    final revenue = _payments.fold<num>(0, (s, p) => s + tNum(p['amount']));
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Guests')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          _title(Icons.people_outline, 'Guests'),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: hotelAddButton('Add Guest', () => _form())),
          const SizedBox(height: 12),
          twoUp([
            _numberCard('Total Guests', '${_guests.length}', TColors.violet700),
            _numberCard('VIP Guests', '${_guests.where(_isVip).length}', const Color(0xFFB45309), onTap: () => setState(() => _vip = !_vip)),
            _numberCard('Total Bookings', '${_bookings.length}', const Color(0xFF1D4ED8)),
            _numberCard('Total Revenue', revenue.toStringAsFixed(0), const Color(0xFF047857)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search guests...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _chip('★ VIP Only', _vip, () => setState(() => _vip = !_vip), color: const Color(0xFFD97706)),
          ]),
          const SizedBox(height: 12),
          if (_loading)
            _loadingBox()
          else if (filtered.isEmpty)
            TCard(
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text('No guests found.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
              ),
            )
          else
            MobileCardList<Map>(
              striped: true,
              items: filtered,
              keyOf: (g) => '${_gid(g)}',
              primary: _name,
              onPrimary: _profile,
              secondary: (g) => '${_dash(g['phone'])} · ${_dash(g['email'])}',
              trailing: (g) => _isVip(g) ? _vipBadge() : const SizedBox.shrink(),
              details: (g) => [
                ('ID', _id(g)),
                ('Nationality', _dash(g['nationality'])),
                ('Stays', tStr(_v(g, 'totalStays')).isEmpty ? '0' : tStr(_v(g, 'totalStays'))),
                ('Last Stay', tStr(_v(g, 'lastStayDate')).isEmpty ? 'Never' : _day(_v(g, 'lastStayDate'))),
              ],
              actions: _actions,
              table: (items) => TrackerTable(
                columns: const [
                  TCol('Name', width: 170),
                  TCol('Phone', width: 120),
                  TCol('Email', width: 170),
                  TCol('ID', width: 140),
                  TCol('Nationality', width: 100),
                  TCol('Stays', width: 60),
                  TCol('Last Stay', width: 100),
                  TCol('Actions', right: true, width: 140),
                ],
                rows: [
                  for (final g in items)
                    [
                      InkWell(
                        onTap: () => _profile(g),
                        child: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(_name(g), style: const TextStyle(fontWeight: FontWeight.w500)),
                          if (_isVip(g)) _vipBadge(),
                        ]),
                      ),
                      cellText(_dash(g['phone'])),
                      cellText(_dash(g['email'])),
                      cellText(_id(g)),
                      cellText(_dash(g['nationality'])),
                      cellText(tStr(_v(g, 'totalStays'))),
                      cellText(tStr(_v(g, 'lastStayDate')).isEmpty ? 'Never' : _day(_v(g, 'lastStayDate'))),
                      Wrap(alignment: WrapAlignment.end, children: _actions(g)),
                    ],
                ],
              ),
            ),
        ]),
      ),
    );
  }
}

class _GuestDialog extends StatefulWidget {
  const _GuestDialog({required this.session, required this.company, required this.editing, required this.idTypes});
  final Session session;
  final Company company;
  final Map? editing;
  final List<String> idTypes;

  @override
  State<_GuestDialog> createState() => _GuestDialogState();
}

class _GuestDialogState extends State<_GuestDialog> {
  late final Map? e = widget.editing;
  late final _first = TextEditingController(text: tStr(e == null ? null : _v(e!, 'firstName')));
  late final _last = TextEditingController(text: tStr(e == null ? null : _v(e!, 'lastName')));
  late final _phone = TextEditingController(text: tStr(e?['phone']));
  late final _email = TextEditingController(text: tStr(e?['email']));
  late final _idNumber = TextEditingController(text: tStr(e == null ? null : _v(e!, 'idNumber')));
  late final _nationality = TextEditingController(text: tStr(e?['nationality']));
  late final _address = TextEditingController(text: tStr(e?['address']));
  late final String _existingId = tStr(e == null ? null : _v(e!, 'idType'));

  /// The ID type picked; "Other" when the guest's saved type is not in the list.
  late String _idSel = _existingId.isEmpty ? '' : (widget.idTypes.contains(_existingId) ? _existingId : 'Other');
  late final _customId = TextEditingController(text: widget.idTypes.contains(_existingId) ? '' : _existingId);
  late bool _vip = e != null && (_v(e!, 'isVIP') == true || e!['isVip'] == true || e!['isvip'] == true);
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _email, _idNumber, _nationality, _address, _customId]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _idType => _idSel == 'Other' ? _customId.text : _idSel;

  Future<void> _save() async {
    if (_first.text.trim().isEmpty || _last.text.trim().isEmpty) return trackerToast(context, 'Name is required', error: true);
    setState(() => _saving = true);
    final body = {
      'farmId': widget.company.farmId,
      'firstName': _first.text,
      'lastName': _last.text,
      'email': _email.text,
      'phone': _phone.text,
      'idType': _idType,
      'idNumber': _idNumber.text,
      'nationality': _nationality.text,
      'address': _address.text,
      'isVIP': _vip,
    };
    try {
      final api = widget.session.farmClient;
      if (e != null) {
        await api.put('/api/Hotel/guests/${tStr(_v(e!, 'hotelGuestId'))}', body: body);
        if (mounted) trackerToast(context, 'Guest updated');
      } else {
        await api.post('/api/Hotel/guests', body: body);
        if (mounted) trackerToast(context, 'Guest created');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (x) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Save failed', description: x.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => HotelDialog(
        icon: Icons.person_outline,
        title: e != null ? 'Edit Guest' : 'Add Guest',
        saveLabel: e != null ? 'Update' : 'Create',
        saving: _saving,
        onSave: _save,
        children: [
          FilterLabel('First Name *', AppInput(controller: _first)),
          FilterLabel('Last Name *', AppInput(controller: _last)),
          FilterLabel('Phone', AppInput(controller: _phone, keyboardType: TextInputType.phone)),
          FilterLabel('Email', AppInput(controller: _email, keyboardType: TextInputType.emailAddress)),
          FilterLabel(
            'ID Type',
            AppSelect<String>(
              value: _idSel == '' || widget.idTypes.contains(_idSel) ? _idSel : null,
              hintText: 'Select ID type',
              items: [const AppSelectItem(value: '', label: 'None'), for (final t in widget.idTypes) AppSelectItem(value: t, label: t)],
              onChanged: (v) => setState(() {
                _idSel = v ?? '';
                _customId.clear();
              }),
            ),
          ),
          FilterLabel('ID Number', AppInput(controller: _idNumber)),
          if (_idSel == 'Other')
            FilterLabel('Specify ID Type *', AppInput(controller: _customId, hintText: 'e.g. Company Badge, Travel Document')),
          FilterLabel('Nationality', AppInput(controller: _nationality)),
          InkWell(
            onTap: () => setState(() => _vip = !_vip),
            child: Row(children: [
              Checkbox(value: _vip, activeColor: hotelViolet, onChanged: (v) => setState(() => _vip = v ?? false)),
              const Icon(Icons.star, size: 16, color: Color(0xFFF59E0B)),
              const SizedBox(width: 4),
              const Text('VIP Guest', style: TextStyle(fontSize: 14)),
            ]),
          ),
          FilterLabel('Address', AppInput(controller: _address)),
        ],
      );
}

/// Tier colours and the points each tier starts at.
const _tierTone = {
  'Bronze': (Color(0xFFFFEDD5), Color(0xFFC2410C)),
  'Silver': (TColors.slate200, TColors.slate700),
  'Gold': (Color(0xFFFEF3C7), Color(0xFFB45309)),
  'Platinum': (TColors.violet100, TColors.violet700),
};
const _tierFrom = {'Bronze': 0, 'Silver': 2000, 'Gold': 5000, 'Platinum': 10000};

/// The tier after [tier], or null at the top.
String? nextLoyaltyTier(String tier) => switch (tier) {
      'Platinum' => null,
      'Gold' => 'Platinum',
      'Silver' => 'Gold',
      _ => 'Silver',
    };

/// "1,234" (toLocaleString).
String _grouped(num n) {
  final s = n.round().abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

class _GuestProfileDialog extends StatefulWidget {
  const _GuestProfileDialog({
    required this.session,
    required this.company,
    required this.guest,
    required this.bookings,
    required this.payments,
    required this.vip,
  });
  final Session session;
  final Company company;
  final Map guest;
  final List<Map> bookings, payments;
  final bool vip;

  @override
  State<_GuestProfileDialog> createState() => _GuestProfileDialogState();
}

class _GuestProfileDialogState extends State<_GuestProfileDialog> {
  Map? _member;
  List<Map> _txns = [];
  bool _enrolling = false;

  ApiClient get _api => widget.session.farmClient;
  Map<String, String> get _q => {'farmId': widget.company.farmId};
  int get _gid => tIntOrNull(_v(widget.guest, 'hotelGuestId')) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadLoyalty();
  }

  Future<void> _loadLoyalty() async {
    try {
      final data = await _api.get('/api/Hotel/loyalty/guest/$_gid', query: _q);
      if (data is! Map || data['enrolled'] == false) {
        if (mounted) setState(() => _member = null);
        return;
      }
      List<Map> t = [];
      try {
        t = hotelRows(await _api.get('/api/Hotel/loyalty/${tStr(data['hotelloyaltymemberid'])}/transactions', query: _q));
      } on ApiException {
        t = [];
      }
      if (mounted) {
        setState(() {
          _member = data;
          _txns = t;
        });
      }
    } on ApiException {
      if (mounted) setState(() => _member = null);
    }
  }

  Future<void> _enroll() async {
    setState(() => _enrolling = true);
    try {
      final m = await _api.post('/api/Hotel/loyalty/enroll', body: {'hotelGuestId': _gid, 'farmId': widget.company.farmId});
      if (mounted) {
        setState(() => _member = m is Map ? m : null);
        trackerToast(context, 'Guest enrolled in loyalty program!');
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Enrollment failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _enrolling = false);
  }

  Future<void> _points(String type) async {
    final m = _member;
    if (m == null) return;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _PointsDialog(session: widget.session, company: widget.company, member: m, type: type),
    );
    if (done == true) await _loadLoyalty();
  }

  Widget _loyalty() {
    final m = _member;
    if (m == null) {
      return Column(children: [
        const Text('Not enrolled in loyalty program', style: TextStyle(fontSize: 12, color: TColors.slate400)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _enrolling ? null : _enroll,
          icon: _enrolling
              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.workspace_premium_outlined, size: 14),
          label: const Text('Enroll Now'),
        ),
      ]);
    }
    final tier = tStr(m['tier']).isEmpty ? 'Bronze' : tStr(m['tier']);
    final next = nextLoyaltyTier(tier);
    final need = next == null ? 0 : _tierFrom[next]!;
    final lifetime = tNum(m['lifetimepoints']);
    final progress = next == null ? 1.0 : math.min(1.0, lifetime / need);
    final (tbg, tfg) = _tierTone[tier] ?? _tierTone['Bronze']!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [TColors.violet50, Color(0xFFFFFBEB)]),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              hotelBadge(tier, tbg, tfg),
              const SizedBox(height: 4),
              Text('#${tStr(m['membershipnumber'])}', style: const TextStyle(fontSize: 10, color: TColors.slate500)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_grouped(tNum(m['totalpoints'])), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.violet700)),
            const Text('Available Points', style: TextStyle(fontSize: 10, color: TColors.slate500)),
          ]),
        ]),
      ),
      if (next != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('${_grouped(lifetime)} lifetime pts', style: const TextStyle(fontSize: 11, color: TColors.slate500))),
          Text('${_grouped(need)} for $next', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: progress, minHeight: 6, color: hotelViolet, backgroundColor: TColors.slate200),
        ),
      ],
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: () => _points('Earn'), icon: const Icon(Icons.trending_up, size: 14), label: const Text('Add Points'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: () => _points('Redeem'), icon: const Icon(Icons.card_giftcard, size: 14), label: const Text('Redeem'))),
      ]),
      for (final t in _txns.take(5))
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(4)),
          child: Row(children: [
            Expanded(child: Text(tStr(t['description']).isEmpty ? tStr(t['transactiontype']) : tStr(t['description']), style: const TextStyle(fontSize: 11, color: TColors.slate600))),
            Text(
              '${t['transactiontype'] == 'Redeem' ? '-' : '+'}${tNum(t['points']).abs().toInt()} pts',
              style: TextStyle(fontSize: 11, color: t['transactiontype'] == 'Redeem' ? TColors.red600 : const Color(0xFF059669)),
            ),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.guest;
    final ids = {for (final b in widget.bookings) tIntOrNull(_v(b, 'hotelBookingId'))};
    final spent = widget.payments.where((p) => ids.contains(tIntOrNull(_v(p, 'hotelBookingId')))).fold<num>(0, (s, p) => s + tNum(p['amount']));
    Widget line(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$k: ', style: const TextStyle(color: TColors.slate500)),
            TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]), style: const TextStyle(fontSize: 13)),
        );
    return AlertDialog(
      scrollable: true,
      title: const Text('Guest Profile'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${tStr(_v(g, 'firstName'))} ${tStr(_v(g, 'lastName'))}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                if (widget.vip) hotelBadge('★ VIP Guest', const Color(0xFFFEF3C7), const Color(0xFFB45309)),
              ]),
            ),
            Column(children: [
              Text(tStr(_v(g, 'totalStays')).isEmpty ? '0' : tStr(_v(g, 'totalStays')),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.violet700)),
              const Text('Total Stays', style: TextStyle(fontSize: 11, color: TColors.slate500)),
            ]),
          ]),
          const SizedBox(height: 12),
          line('Phone', _dash(g['phone'])),
          line('Email', _dash(g['email'])),
          line('ID', tStr(_v(g, 'idType')).isNotEmpty ? '${tStr(_v(g, 'idType'))}: ${tStr(_v(g, 'idNumber'))}' : '—'),
          line('Nationality', _dash(g['nationality'])),
          line('Address', _dash(g['address'])),
          line('Last Stay', tStr(_v(g, 'lastStayDate')).isEmpty ? 'Never' : _dmy(_v(g, 'lastStayDate'))),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TColors.violet50, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Expanded(child: Text('Lifetime Value', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: TColors.violet700))),
              Text(_money(spent), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TColors.violet700)),
            ]),
          ),
          const SizedBox(height: 12),
          Text('Stay History (${widget.bookings.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate500)),
          const SizedBox(height: 6),
          if (widget.bookings.isEmpty)
            const Text('No booking history', style: TextStyle(fontSize: 13, color: TColors.slate400))
          else
            for (final b in widget.bookings)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${tStr(_v(b, 'bookingRef'))} — Room ${tStr(_v(b, 'roomNumber')).isEmpty ? 'TBD' : tStr(_v(b, 'roomNumber'))}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      Text('${_dmy(_v(b, 'checkInDate'))} to ${_dmy(_v(b, 'checkOutDate'))} | ${tStr(_v(b, 'roomTypeName'))}',
                          style: const TextStyle(fontSize: 11, color: TColors.slate400)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_money(_v(b, 'totalAmount')), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    bookingStatusBadge(b['status']),
                  ]),
                ]),
              ),
          const Divider(height: 24),
          const Row(children: [
            Icon(Icons.workspace_premium_outlined, size: 16, color: TColors.slate500),
            SizedBox(width: 4),
            Text('Loyalty Program', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate500)),
          ]),
          const SizedBox(height: 8),
          _loyalty(),
          const Divider(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Edit Guest'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close'))),
          ]),
        ]),
      ),
    );
  }
}

class _PointsDialog extends StatefulWidget {
  const _PointsDialog({required this.session, required this.company, required this.member, required this.type});
  final Session session;
  final Company company;
  final Map member;
  final String type;

  @override
  State<_PointsDialog> createState() => _PointsDialogState();
}

class _PointsDialogState extends State<_PointsDialog> {
  final _points = TextEditingController(text: '100'), _desc = TextEditingController();
  bool _saving = false;

  bool get _redeem => widget.type == 'Redeem';
  num get _n => num.tryParse(_points.text) ?? 0;
  num get _available => tNum(widget.member['totalpoints']);
  bool get _short => _redeem && _n > _available;

  @override
  void dispose() {
    _points.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Hotel/loyalty/points', body: {
        'farmId': widget.company.farmId,
        'hotelLoyaltyMemberId': widget.member['hotelloyaltymemberid'],
        'transactionType': widget.type,
        'points': _n,
        'description': _desc.text.isEmpty ? '${widget.type} points' : _desc.text,
      });
      if (!mounted) return;
      trackerToast(context, '${_points.text} points ${_redeem ? 'redeemed' : 'added'}');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(_redeem ? 'Redeem Points' : 'Add Points'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Current balance: '),
              TextSpan(text: '${_grouped(_available)} pts', style: const TextStyle(fontWeight: FontWeight.w700, color: TColors.violet700)),
            ]), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            const SizedBox(height: 12),
            FilterLabel(
              'Points',
              AppInput(controller: _points, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (_) => setState(() {})),
            ),
            const SizedBox(height: 10),
            FilterLabel(
              'Description',
              AppInput(controller: _desc, hintText: _redeem ? 'e.g. Room discount, Free breakfast' : 'e.g. Stay bonus, Referral, Promotion'),
            ),
            if (_short)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Insufficient points (available: ${_available.toInt()})', style: const TextStyle(fontSize: 12, color: TColors.red600)),
              ),
          ]),
        ),
        actions: [
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton.icon(
              style: hotelPrimary,
              onPressed: _saving || _short ? null : _save,
              icon: Icon(_redeem ? Icons.card_giftcard : Icons.trending_up, size: 16),
              label: Text(_redeem ? 'Redeem' : 'Add Points'),
            ),
          ]),
        ],
      );
}

// ===================================================================== Check-in

/// One in-house guest's bill: the room, the extras charged, what was paid.
typedef InHouseBalance = ({Map booking, num charges, num payments, num grandTotal, num balance});

class HotelCheckInScreen extends StatefulWidget {
  const HotelCheckInScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelCheckInScreen> createState() => _HotelCheckInScreenState();
}

class _HotelCheckInScreenState extends State<HotelCheckInScreen> {
  List<Map> _confirmed = [], _rooms = [];
  List<InHouseBalance> _inHouse = [];
  bool _loading = true, _house = false;
  final _q = TextEditingController();
  int _page = 1, _size = 10;

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {'farmId': _farmId};
    try {
      final r = await Future.wait([
        _api.get('/api/Hotel/bookings', query: q),
        _api.get('/api/Hotel/rooms', query: q),
        _api.get('/api/Hotel/billing/payments', query: q),
      ]);
      final bookings = hotelRows(r[0]), payments = hotelRows(r[2]);
      final house = <InHouseBalance>[];
      for (final b in bookings.where((b) => b['status'] == 'CheckedIn')) {
        num charges = 0;
        try {
          final c = hotelRows(await _api.get('/api/Hotel/billing/charges', query: {...q, 'bookingId': '${_bookingId(b)}'}));
          charges = c.fold<num>(0, (s, x) => s + tNum(_v(x, 'totalAmount')));
        } on ApiException {
          charges = 0;
        }
        final paid = payments.where((p) => tIntOrNull(_v(p, 'hotelBookingId')) == _bookingId(b)).fold<num>(0, (s, p) => s + tNum(p['amount']));
        final grand = tNum(_v(b, 'totalAmount')) + charges;
        house.add((booking: b, charges: charges, payments: paid, grandTotal: grand, balance: grand - paid));
      }
      if (!mounted) return;
      setState(() {
        _rooms = [for (final x in hotelRows(r[1])) if (x['status'] == 'Available') x];
        _confirmed = [for (final b in bookings) if (b['status'] == 'Confirmed') b];
        _inHouse = house;
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _match(Map b, {bool room = false}) {
    final q = _q.text.toLowerCase();
    if (q.isEmpty) return true;
    return _guestName(b).toLowerCase().contains(q) ||
        tStr(_v(b, 'bookingRef')).toLowerCase().contains(q) ||
        tStr(_v(b, room ? 'roomNumber' : 'roomTypeName')).toLowerCase().contains(q);
  }

  Future<void> _checkIn(Map b) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _CheckInDialog(session: widget.session, company: widget.company, booking: b, rooms: _rooms));
    if (done == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-check-in');
    final awaiting = [for (final b in _confirmed) if (_match(b)) b];
    final house = [for (final g in _inHouse) if (_match(g.booking, room: true)) g];
    if ((_page - 1) * _size >= house.length && _page > 1) _page = 1;
    final outstanding = _inHouse.fold<num>(0, (s, g) => s + math.max(0, g.balance));
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Check-in')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          _title(Icons.login, 'Front Desk'),
          const SizedBox(height: 12),
          twoUp([
            _numberCard('Awaiting Check-in', '${_confirmed.length}', const Color(0xFF1D4ED8)),
            _numberCard('Currently Checked In', '${_inHouse.length}', const Color(0xFF047857)),
            _numberCard('Total Outstanding', _money(outstanding), const Color(0xFFB91C1C)),
            _numberCard('Available Rooms', '${_rooms.length}', TColors.violet700),
          ]),
          const SizedBox(height: 12),
          AppInput(controller: _q, hintText: 'Search guest name, ref, room...', prefixIcon: const Icon(Icons.search, size: 18), onChanged: (_) => setState(() => _page = 1)),
          const SizedBox(height: 12),
          if (_loading)
            _loadingBox()
          else ...[
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip('Awaiting Check-in (${awaiting.length})', !_house, () => setState(() {
                    _house = false;
                    _page = 1;
                  })),
              _chip('In-House Guests (${house.length})', _house, () => setState(() {
                    _house = true;
                    _page = 1;
                  })),
            ]),
            const SizedBox(height: 12),
            if (!_house)
              if (awaiting.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(_q.text.isNotEmpty ? 'No matching bookings found.' : 'No confirmed bookings awaiting check-in.',
                      textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate400)),
                )
              else
                for (final b in awaiting)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(_guestName(b), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text.rich(TextSpan(children: [
                        const TextSpan(text: 'Ref: '),
                        TextSpan(text: tStr(_v(b, 'bookingRef')), style: const TextStyle(fontFamily: 'monospace')),
                      ]), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
                      Text('Room Type: ${tStr(_v(b, 'roomTypeName'))}', style: const TextStyle(fontSize: 13)),
                      Text('Guests: ${tStr(b['adults'])} adults${(tIntOrNull(b['children']) ?? 0) > 0 ? ', ${tStr(b['children'])} children' : ''}',
                          style: const TextStyle(fontSize: 13)),
                      Text('Stay: ${_dmy(_v(b, 'checkInDate'))} to ${_dmy(_v(b, 'checkOutDate'))}', style: const TextStyle(fontSize: 13)),
                      Text('Total: ${_money(_v(b, 'totalAmount'))}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      FilledButton.icon(style: hotelPrimary, onPressed: () => _checkIn(b), icon: const Icon(Icons.key, size: 16), label: const Text('Check In')),
                    ]),
                  )
            else if (house.isEmpty)
              TCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(_q.text.isNotEmpty ? 'No matching guests found.' : 'No guests currently checked in.',
                      textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate400)),
                ),
              )
            else
              MobileCardList<InHouseBalance>(
                striped: true,
                items: pageSlice(house, _page, _size),
                keyOf: (g) => '${_bookingId(g.booking)}',
                primary: (g) => _guestName(g.booking),
                secondary: (g) => 'Room ${_dash(_v(g.booking, 'roomNumber'))} · ${tStr(_v(g.booking, 'bookingRef'))}',
                trailing: (g) => g.balance <= 0
                    ? hotelBadge('Paid', const Color(0xFFD1FAE5), const Color(0xFF047857))
                    : hotelBadge('Owes ${_money(g.balance)}', const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
                details: (g) => [
                  ('Check-in', _day(_v(g.booking, 'checkInDate'))),
                  ('Check-out', _day(_v(g.booking, 'checkOutDate'))),
                  ('Room Bill', _money(_v(g.booking, 'totalAmount'))),
                  ('Extras', g.charges > 0 ? _money(g.charges) : '—'),
                  ('Total', _money(g.grandTotal)),
                  ('Paid', g.payments > 0 ? _money(g.payments) : '—'),
                  ('Balance', g.balance <= 0 ? '0.00' : _money(g.balance)),
                ],
                table: (items) => TrackerTable(
                  columns: const [
                    TCol('Guest', width: 150),
                    TCol('Room', width: 70),
                    TCol('Ref', width: 140),
                    TCol('Check-in', width: 100),
                    TCol('Check-out', width: 100),
                    TCol('Room Bill', right: true, width: 100),
                    TCol('Extras', right: true, width: 90),
                    TCol('Total', right: true, width: 100),
                    TCol('Paid', right: true, width: 100),
                    TCol('Balance', right: true, width: 100),
                    TCol('Status', width: 130),
                  ],
                  rows: [
                    for (final g in items)
                      [
                        cellText(_guestName(g.booking), bold: true),
                        Align(alignment: Alignment.centerLeft, child: hotelBadge(_dash(_v(g.booking, 'roomNumber')), const Color(0xFFECFDF5), const Color(0xFF047857))),
                        Text(tStr(_v(g.booking, 'bookingRef')), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        cellText(_day(_v(g.booking, 'checkInDate'))),
                        cellText(_day(_v(g.booking, 'checkOutDate'))),
                        cellText(_money(_v(g.booking, 'totalAmount'))),
                        cellText(g.charges > 0 ? _money(g.charges) : '—'),
                        cellText(_money(g.grandTotal), bold: true),
                        cellText(g.payments > 0 ? _money(g.payments) : '—', color: const Color(0xFF047857)),
                        cellText(g.balance <= 0 ? '0.00' : _money(g.balance), bold: true, color: g.balance <= 0 ? const Color(0xFF047857) : const Color(0xFFB91C1C)),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: g.balance <= 0
                              ? hotelBadge('Paid', const Color(0xFFD1FAE5), const Color(0xFF047857))
                              : hotelBadge('Owes ${_money(g.balance)}', const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
                        ),
                      ],
                  ],
                ),
                pager: CompactPager(
                  total: house.length,
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

class _CheckInDialog extends StatefulWidget {
  const _CheckInDialog({required this.session, required this.company, required this.booking, required this.rooms});
  final Session session;
  final Company company;
  final Map booking;
  final List<Map> rooms;

  @override
  State<_CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends State<_CheckInDialog> {
  late int? _room = tIntOrNull(_v(widget.booking, 'hotelRoomId'));
  final _key = TextEditingController(), _deposit = TextEditingController(text: '0');
  String _method = 'Cash';
  bool _saving = false;

  static const _methods = [('Cash', 'Cash'), ('Card', 'Card'), ('MobileMoney', 'Mobile Money'), ('BankTransfer', 'Bank Transfer')];

  num get _depositNum => num.tryParse(_deposit.text) ?? 0;

  @override
  void dispose() {
    _key.dispose();
    _deposit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final roomId = _room ?? tIntOrNull(_v(widget.booking, 'hotelRoomId'));
    if (roomId == null) return trackerToast(context, 'Please select a room', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Hotel/front-desk/check-in', body: {
        'farmId': widget.company.farmId,
        'hotelBookingId': _bookingId(widget.booking),
        'hotelRoomId': roomId,
        if (_key.text.isNotEmpty) 'keyCardNumber': _key.text,
        'depositAmount': _depositNum,
        'depositMethod': _method,
      });
      if (!mounted) return;
      trackerToast(context, '${_guestName(widget.booking)} checked in');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Check-in failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    return HotelDialog(
      icon: Icons.key,
      title: 'Check In: ${_guestName(b)}',
      saveLabel: 'Confirm Check-in',
      saving: _saving,
      onSave: _save,
      children: [
        Text('${tStr(_v(b, 'roomTypeName'))} | ${_day(_v(b, 'checkInDate'))} to ${_day(_v(b, 'checkOutDate'))} | Total: ${_money(_v(b, 'totalAmount'))}',
            style: const TextStyle(fontSize: 13, color: TColors.slate500)),
        FilterLabel(
          'Assign Room *',
          AppSelect<int>(
            value: widget.rooms.any((r) => tIntOrNull(_v(r, 'hotelRoomId')) == _room) ? _room : null,
            hintText: 'Select available room',
            items: [
              for (final r in widget.rooms)
                AppSelectItem(value: tIntOrNull(_v(r, 'hotelRoomId')) ?? 0, label: 'Room ${tStr(_v(r, 'roomNumber'))} — ${tStr(_v(r, 'roomTypeName'))}'),
            ],
            onChanged: (v) => setState(() => _room = v),
          ),
        ),
        FilterLabel('Key Card Number', AppInput(controller: _key, hintText: 'Optional')),
        FilterLabel(
          'Deposit Amount',
          AppInput(
            controller: _deposit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
            onChanged: (_) => setState(() {}),
          ),
        ),
        FilterLabel(
          'Deposit Method',
          AppSelect<String>(
            value: _method,
            items: [for (final (v, l) in _methods) AppSelectItem(value: v, label: l)],
            onChanged: (v) => setState(() => _method = v ?? 'Cash'),
          ),
        ),
        if (_depositNum > 0)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: TColors.violet50, borderRadius: BorderRadius.circular(6)),
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'A payment of '),
              TextSpan(text: _money(_depositNum), style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' via $_method will be recorded automatically.'),
            ]), style: const TextStyle(fontSize: 13, color: TColors.violet700)),
          ),
      ],
    );
  }
}
