// Hotel → Operations → Guest Services: Guest Log (`app/hotel-communications`),
// Requests (`app/hotel-guest-requests`) and Lost & Found (`app/hotel-lost-found`).
// The lists answer with lower-case keys (r.firstname, r.roomnumber), as the
// web reads them. Subjects, request types and lost-item categories typed under
// "Other" are remembered (HotelOtherSelect).
// API: /Hotel/communications, /Hotel/guest-requests, /Hotel/lost-and-found
// (each + /{id}/status), /Hotel/guests, /Hotel/bookings, /Hotel/rooms,
// /Hotel/staff, /Hotel/setup/comm-subjects, /Hotel/setup/request-types.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/money/money_widgets.dart' show MobileCardList, twoUp;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager;
import '../poultry/trackers/tracker_logic.dart' show tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import 'hotel_kit.dart';
import 'hotel_other_select.dart';

Object? _v(Map m, String k) => m[k] ?? m[k.toLowerCase()];
String _day(Object? v) => tStr(v).length >= 10 ? tStr(v).substring(0, 10) : tStr(v);
String _dash(Object? v) => tStr(v).isEmpty ? '—' : tStr(v);
String _staffName(Map s) => '${tStr(_v(s, 'firstName'))} ${tStr(_v(s, 'lastName'))}';
bool _active(Map s) => _v(s, 'isActive') == true;

String _local(Object? v) {
  final d = DateTime.tryParse(tStr(v))?.toLocal();
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day}/${d.month}/${d.year}, ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

const _amber = (Color(0xFFFEF3C7), Color(0xFFB45309));
const _blue = (Color(0xFFDBEAFE), Color(0xFF1D4ED8));
const _green = (Color(0xFFD1FAE5), Color(0xFF047857));
const _slate = (TColors.slate100, TColors.slate700);
const _red = (Color(0xFFFEE2E2), Color(0xFFB91C1C));

Widget _badge(String text, (Color, Color)? tone) => hotelBadge(text, (tone ?? _slate).$1, (tone ?? _slate).$2);

Widget _filterChip(String label, bool on, VoidCallback tap) => on
    ? FilledButton(style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 34))), onPressed: tap, child: Text(label))
    : OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34)), onPressed: tap, child: Text(label));

Widget _header(IconData icon, String title, {String? subtitle}) => Row(children: [
      Icon(icon, size: 24, color: hotelViolet),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900)),
          if (subtitle != null) Text(subtitle, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
        ]),
      ),
    ]);

Widget _loadingBox() => const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: hotelViolet)));

Widget _empty(String text) => TCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate400)),
      ),
    );

/// PATCH /{id}/status with {farmId, status, ...extra}.
Future<bool> _patchStatus(BuildContext context, ApiClient api, String farmId, String path, String status, String toast, [Map<String, Object?> extra = const {}]) async {
  try {
    await api.patch(path, body: {'farmId': farmId, 'status': status, ...extra});
    if (context.mounted) trackerToast(context, toast);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    return false;
  }
}

/// A list's search box.
Widget _search(TextEditingController c, String hint, VoidCallback changed) => AppInput(
      controller: c,
      hintText: hint,
      prefixIcon: const Icon(Icons.search, size: 18),
      onChanged: (_) => changed(),
    );

CompactPager _pager(int total, int page, int size, ValueChanged<int> onPage, ValueChanged<int> onSize) =>
    CompactPager(total: total, page: page, pageSize: size, onPage: onPage, onPageSize: onSize);

// ===================================================================== Guest Log

const commTypes = ['Note', 'Complaint', 'Request', 'Compliment', 'Incident'];
const commPriorities = ['Low', 'Normal', 'High', 'Urgent'];
const _priorityTone = {'Low': (TColors.slate100, TColors.slate600), 'Normal': _blue, 'High': _amber, 'Urgent': _red};
const _commStatusTone = {'Open': _amber, 'InProgress': _blue, 'Resolved': _green, 'Closed': _slate};

/// The Guest Log's status filter and search.
List<Map> filterGuestLog(List<Map> rows, {String status = 'ALL', String search = ''}) {
  final q = search.toLowerCase();
  return [
    for (final r in rows)
      if ((status == 'ALL' || tStr(r['status']) == status) &&
          (q.isEmpty ||
              '${tStr(r['firstname'])} ${tStr(r['lastname'])} ${tStr(r['subject'])} ${tStr(r['message'])} ${tStr(r['roomnumber'])}'.toLowerCase().contains(q)))
        r,
  ];
}

class HotelGuestLogScreen extends StatefulWidget {
  const HotelGuestLogScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelGuestLogScreen> createState() => _HotelGuestLogScreenState();
}

class _HotelGuestLogScreenState extends State<HotelGuestLogScreen> {
  List<Map> _items = [], _guests = [], _subjects = [], _staff = [];
  bool _loading = true;
  String _status = 'ALL';
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
    Future<Object?> soft(String p) async {
      try {
        return await _api.get(p, query: q);
      } on ApiException {
        return const [];
      }
    }

    try {
      final r = await Future.wait([
        _api.get('/api/Hotel/communications', query: q),
        _api.get('/api/Hotel/guests', query: q),
        _api.get('/api/Hotel/bookings', query: q),
        soft('/api/Hotel/setup/comm-subjects'),
        soft('/api/Hotel/staff'),
      ]);
      if (!mounted) return;
      setState(() {
        _items = hotelRows(r[0]);
        _guests = hotelRows(r[1]);
        _subjects = hotelRows(r[3]);
        _staff = [for (final s in hotelRows(r[4])) if (_active(s)) s];
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _log() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _LogDialog(
        session: widget.session,
        company: widget.company,
        guests: _guests,
        subjects: [for (final s in _subjects) tStr(s['description'])],
        staff: _staff,
      ),
    );
    if (done == true) _load();
  }

  Future<void> _set(Map r, String status) async {
    if (await _patchStatus(context, _api, _farmId, '/api/Hotel/communications/${tStr(r['hotelguestcommid'])}/status', status, 'Status → $status')) _load();
  }

  List<Widget> _actions(Map r) {
    final st = tStr(r['status']);
    return [
      if (st == 'Open') IconButton(tooltip: 'Start', onPressed: () => _set(r, 'InProgress'), icon: const Icon(Icons.play_arrow, size: 18, color: Color(0xFF2563EB))),
      if (st == 'Open' || st == 'InProgress')
        IconButton(tooltip: 'Resolve', onPressed: () => _set(r, 'Resolved'), icon: const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF059669))),
      if (st == 'Resolved') IconButton(tooltip: 'Close', onPressed: () => _set(r, 'Closed'), icon: const Icon(Icons.cancel_outlined, size: 18, color: TColors.slate500)),
    ];
  }

  Widget _count(String label, int n, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          Text('$n', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-communications');
    final filtered = filterGuestLog(_items, status: _status, search: _q.text);
    if ((_page - 1) * _size >= filtered.length && _page > 1) _page = 1;
    int n(String s) => _items.where((r) => r['status'] == s).length;
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Guest Log')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          _header(Icons.chat_bubble_outline, 'Guest Communication Log'),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: hotelAddButton('Log Entry', _log)),
          const SizedBox(height: 12),
          twoUp([
            _count('Open', n('Open'), const Color(0xFFB45309)),
            _count('In Progress', n('InProgress'), const Color(0xFF1D4ED8)),
            _count('Resolved', n('Resolved'), const Color(0xFF047857)),
            _count('Total', _items.length, TColors.slate900),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (s, l) in const [('ALL', 'All'), ('Open', 'Open'), ('InProgress', 'In Progress'), ('Resolved', 'Resolved'), ('Closed', 'Closed')])
              _filterChip(l, _status == s, () => setState(() {
                    _status = s;
                    _page = 1;
                  })),
          ]),
          const SizedBox(height: 10),
          _search(_q, 'Search guest, subject, message...', () => setState(() => _page = 1)),
          const SizedBox(height: 12),
          if (_loading)
            _loadingBox()
          else if (filtered.isEmpty)
            _empty('No communications logged.')
          else
            MobileCardList<Map>(
              striped: true,
              items: pageSlice(filtered, _page, _size),
              keyOf: (r) => tStr(r['hotelguestcommid']),
              primary: (r) => '${tStr(r['firstname'])} ${tStr(r['lastname'])}'.trim(),
              secondary: (r) => '${_day(r['createdat'])} · Room ${_dash(r['roomnumber'])} · ${tStr(r['commtype'])}',
              trailing: (r) => _badge(tStr(r['status']), _commStatusTone[tStr(r['status'])]),
              details: (r) => [
                ('Subject', tStr(r['subject']).isNotEmpty ? tStr(r['subject']) : (tStr(r['message']).isEmpty ? '—' : tStr(r['message']).substring(0, tStr(r['message']).length.clamp(0, 50)))),
                ('Priority', tStr(r['priority'])),
                ('Assigned', _dash(r['assignedto'])),
              ],
              actions: _actions,
              table: (items) => TrackerTable(
                columns: const [
                  TCol('Date', width: 100),
                  TCol('Guest', width: 140),
                  TCol('Room', width: 70),
                  TCol('Type', width: 100),
                  TCol('Subject', width: 180),
                  TCol('Priority', width: 90),
                  TCol('Status', width: 100),
                  TCol('Assigned', width: 120),
                  TCol('Actions', right: true, width: 120),
                ],
                rows: [
                  for (final r in items)
                    [
                      cellText(_day(r['createdat'])),
                      cellText('${tStr(r['firstname'])} ${tStr(r['lastname'])}', bold: true),
                      cellText(_dash(r['roomnumber'])),
                      Align(alignment: Alignment.centerLeft, child: _badge(tStr(r['commtype']), (Colors.white, TColors.slate700))),
                      cellText(tStr(r['subject']).isNotEmpty ? tStr(r['subject']) : _dash(r['message'])),
                      Align(alignment: Alignment.centerLeft, child: _badge(tStr(r['priority']), _priorityTone[tStr(r['priority'])])),
                      Align(alignment: Alignment.centerLeft, child: _badge(tStr(r['status']), _commStatusTone[tStr(r['status'])])),
                      cellText(_dash(r['assignedto'])),
                      Wrap(alignment: WrapAlignment.end, children: _actions(r)),
                    ],
                ],
              ),
              pager: _pager(filtered.length, _page, _size, (p) => setState(() => _page = p), (v) => setState(() {
                    _size = v;
                    _page = 1;
                  })),
            ),
        ]),
      ),
    );
  }
}

/// AppSelect over the active staff: "Unassigned", then "First Last — Role".
AppSelect<String> _staffSelect(List<Map> staff, String value, ValueChanged<String> on, {bool department = false, bool other = false}) => AppSelect<String>(
      value: value,
      hintText: 'Select staff',
      items: [
        const AppSelectItem(value: '', label: 'Unassigned'),
        for (final s in staff)
          AppSelectItem(
            value: _staffName(s),
            label: '${_staffName(s)} — ${tStr(s['role'])}${department && tStr(s['department']).isNotEmpty ? ' (${tStr(s['department'])})' : ''}',
          ),
        if (other) const AppSelectItem(value: '__other__', label: 'Other (type name)'),
      ],
      onChanged: (v) => on(v ?? ''),
    );

class _LogDialog extends StatefulWidget {
  const _LogDialog({required this.session, required this.company, required this.guests, required this.subjects, required this.staff});
  final Session session;
  final Company company;
  final List<Map> guests, staff;
  final List<String> subjects;

  @override
  State<_LogDialog> createState() => _LogDialogState();
}

class _LogDialogState extends State<_LogDialog> {
  late int _guest = widget.guests.isEmpty ? 0 : tIntOrNull(_v(widget.guests.first, 'hotelGuestId')) ?? 0;
  String _type = 'Note', _priority = 'Normal', _subject = '', _assigned = '';
  final _message = TextEditingController();
  final _subjectOther = GlobalKey<HotelOtherSelectState>();
  bool _saving = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_guest == 0) return trackerToast(context, 'Select a guest', error: true);
    if (_message.text.trim().isEmpty) return trackerToast(context, 'Message required', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Hotel/communications', body: {
        'farmId': widget.company.farmId,
        'hotelGuestId': _guest,
        'hotelBookingId': null,
        'commType': _type,
        'subject': _subject,
        'message': _message.text,
        'priority': _priority,
        'assignedTo': _assigned,
      });
      await _subjectOther.currentState?.remember();
      if (!mounted) return;
      trackerToast(context, 'Communication logged');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => HotelDialog(
        icon: Icons.chat_bubble_outline,
        title: 'Log Guest Communication',
        saveLabel: 'Log',
        saving: _saving,
        onSave: _save,
        children: [
          FilterLabel(
            'Guest *',
            AppSelect<int>(
              value: _guest == 0 ? null : _guest,
              hintText: 'Select guest',
              items: [
                for (final g in widget.guests)
                  AppSelectItem(value: tIntOrNull(_v(g, 'hotelGuestId')) ?? 0, label: '${tStr(_v(g, 'firstName'))} ${tStr(_v(g, 'lastName'))}'),
              ],
              onChanged: (v) => setState(() => _guest = v ?? 0),
            ),
          ),
          FilterLabel(
            'Type',
            AppSelect<String>(
              value: _type,
              items: [for (final t in commTypes) AppSelectItem(value: t, label: t)],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
          ),
          FilterLabel(
            'Priority',
            AppSelect<String>(
              value: _priority,
              items: [for (final p in commPriorities) AppSelectItem(value: p, label: p)],
              onChanged: (v) => setState(() => _priority = v ?? _priority),
            ),
          ),
          FilterLabel(
            'Subject',
            HotelOtherSelect(
              key: _subjectOther,
              session: widget.session,
              company: widget.company,
              listKey: 'CommSubject',
              baseOptions: widget.subjects,
              value: _subject,
              onChanged: (v) => setState(() => _subject = v ?? ''),
              placeholder: 'Select subject',
              includeNone: true,
              otherLabel: 'Other (type subject)',
            ),
          ),
          FilterLabel('Message *', AppInput(controller: _message, minLines: 3, maxLines: 6)),
          FilterLabel('Assigned To', _staffSelect(widget.staff, _assigned, (v) => setState(() => _assigned = v))),
        ],
      );
}

// ===================================================================== Requests

const _requestStatusTone = {'Pending': _amber, 'InProgress': _blue, 'Completed': _green, 'Cancelled': _red};

/// The Requests' status filter and search.
List<Map> filterGuestRequests(List<Map> rows, {String status = 'ALL', String search = ''}) {
  final q = search.toLowerCase();
  return [
    for (final r in rows)
      if ((status == 'ALL' || tStr(r['status']) == status) &&
          (q.isEmpty ||
              '${tStr(r['firstname'])} ${tStr(r['lastname'])} ${tStr(r['roomnumber'])} ${tStr(r['requesttype'])} ${tStr(r['description'])}'.toLowerCase().contains(q)))
        r,
  ];
}

class HotelGuestRequestsScreen extends StatefulWidget {
  const HotelGuestRequestsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelGuestRequestsScreen> createState() => _HotelGuestRequestsScreenState();
}

class _HotelGuestRequestsScreenState extends State<HotelGuestRequestsScreen> {
  List<Map> _items = [], _bookings = [], _rooms = [], _types = [], _staff = [];
  bool _loading = true;
  String _status = 'ALL';
  final _q = TextEditingController();
  int _page = 1, _size = 20;

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
      final r = await Future.wait([
        _api.get('/api/Hotel/guest-requests', query: q),
        _api.get('/api/Hotel/bookings', query: q),
        _api.get('/api/Hotel/rooms', query: q),
        soft('/api/Hotel/setup/request-types'),
        soft('/api/Hotel/staff'),
      ]);
      if (!mounted) return;
      setState(() {
        _items = hotelRows(r[0]);
        _bookings = [for (final b in hotelRows(r[1])) if (_v(b, 'status') == 'CheckedIn') b];
        _rooms = hotelRows(r[2]);
        _types = hotelRows(r[3]);
        _staff = [for (final s in hotelRows(r[4])) if (_active(s)) s];
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _create() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _RequestDialog(
        session: widget.session,
        company: widget.company,
        bookings: _bookings,
        rooms: _rooms,
        types: [for (final t in _types) tStr(t['description'])],
        staff: _staff,
      ),
    );
    if (done == true) _load();
  }

  Future<void> _act(Map r, String status) async {
    if (await _patchStatus(context, _api, _farmId, '/api/Hotel/guest-requests/${tStr(r['hotelguestrequestid'])}/status', status, 'Request ${status.toLowerCase()}')) {
      _load();
    }
  }

  List<Widget> _actions(Map r) {
    final st = tStr(r['status']);
    return [
      if (st == 'Pending') IconButton(tooltip: 'Start', onPressed: () => _act(r, 'InProgress'), icon: const Icon(Icons.play_arrow, size: 18, color: Color(0xFF2563EB))),
      if (st == 'Pending' || st == 'InProgress')
        IconButton(tooltip: 'Complete', onPressed: () => _act(r, 'Completed'), icon: const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF059669))),
      if (st != 'Completed' && st != 'Cancelled')
        IconButton(tooltip: 'Cancel', onPressed: () => _act(r, 'Cancelled'), icon: const Icon(Icons.cancel_outlined, size: 18, color: Color(0xFFEF4444))),
    ];
  }

  Future<void> _detail(Map r) => showDialog<void>(
        context: context,
        builder: (ctx) {
          final st = tStr(r['status']);
          Widget field(String label, String value, {bool bold = false, bool mono = false}) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                  Text(value, style: TextStyle(fontSize: mono ? 12 : 14, fontWeight: bold ? FontWeight.w600 : null, fontFamily: mono ? 'monospace' : null)),
                ]),
              );
          Widget block(String label, String text) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, color: TColors.slate500)),
                  const SizedBox(height: 4),
                  Text(text, style: const TextStyle(fontSize: 14)),
                ]),
              );
          void go(String s) {
            Navigator.pop(ctx);
            _act(r, s);
          }

          return AlertDialog(
            scrollable: true,
            title: Wrap(spacing: 8, runSpacing: 4, children: [
              _badge(tStr(r['requesttype']), (TColors.violet50, TColors.violet700)),
              _badge(st, _requestStatusTone[st]),
            ]),
            content: SizedBox(
              width: 440,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                field('Guest', tStr(r['firstname']).isNotEmpty ? '${tStr(r['firstname'])} ${tStr(r['lastname'])}' : '—', bold: true),
                field('Room', _dash(r['roomnumber']), bold: true),
                field('Created', _local(r['createdat'])),
                field('Scheduled', _local(r['scheduledtime'])),
                field('Assigned To', tStr(r['assignedto']).isEmpty ? 'Unassigned' : tStr(r['assignedto']), bold: true),
                field('Booking Ref', _dash(r['bookingref']), mono: true),
                if (tStr(r['description']).isNotEmpty) block('Description', tStr(r['description'])),
                if (tStr(r['notes']).isNotEmpty) block('Notes', tStr(r['notes'])),
                if (st != 'Completed' && st != 'Cancelled') ...[
                  const Divider(),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (st == 'Pending')
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                        onPressed: () => go('InProgress'),
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text('Start'),
                      ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                      onPressed: () => go('Completed'),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Complete'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: TColors.red600),
                      onPressed: () => go('Cancelled'),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Cancel'),
                    ),
                  ]),
                ],
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
          );
        },
      );

  Widget _card(String status, String label, int n, Color color) => InkWell(
        onTap: () => setState(() {
          _status = status;
          _page = 1;
        }),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _status == status ? color.withValues(alpha: .45) : TColors.slate200, width: _status == status ? 1.5 : 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-guest-requests');
    final filtered = filterGuestRequests(_items, status: _status, search: _q.text);
    if ((_page - 1) * _size >= filtered.length && _page > 1) _page = 1;
    int n(String s) => _items.where((r) => r['status'] == s).length;
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Guest Requests')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          HotelPageHeader(icon: Icons.notifications_none, title: 'Guest Requests', description: '${_items.length} total requests'),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: hotelAddButton('New Request', _create)),
          const SizedBox(height: 12),
          twoUp([
            _card('ALL', 'All', _items.length, TColors.violet700),
            _card('Pending', 'Pending', n('Pending'), const Color(0xFFB45309)),
            _card('InProgress', 'In Progress', n('InProgress'), const Color(0xFF1D4ED8)),
            _card('Completed', 'Completed', n('Completed'), const Color(0xFF047857)),
            _card('Cancelled', 'Cancelled', n('Cancelled'), const Color(0xFFB91C1C)),
          ]),
          const SizedBox(height: 12),
          _search(_q, 'Search guest, room, type...', () => setState(() => _page = 1)),
          const SizedBox(height: 12),
          if (_loading)
            _loadingBox()
          else if (filtered.isEmpty)
            _empty('No requests found.')
          else
            MobileCardList<Map>(
              striped: true,
              items: pageSlice(filtered, _page, _size),
              keyOf: (r) => tStr(r['hotelguestrequestid']),
              primary: (r) => tStr(r['firstname']).isNotEmpty ? '${tStr(r['firstname'])} ${tStr(r['lastname'])}' : '—',
              onPrimary: _detail,
              secondary: (r) => '${_day(r['createdat'])} · Room ${_dash(r['roomnumber'])} · ${tStr(r['requesttype'])}',
              trailing: (r) => _badge(tStr(r['status']), _requestStatusTone[tStr(r['status'])]),
              details: (r) => [('Description', _dash(r['description'])), ('Assigned', _dash(r['assignedto']))],
              actions: (r) => [
                OutlinedButton.icon(onPressed: () => _detail(r), icon: const Icon(Icons.visibility_outlined, size: 16), label: const Text('Details')),
                ..._actions(r),
              ],
              table: (items) => TrackerTable(
                columns: const [
                  TCol('Date', width: 100),
                  TCol('Room', width: 70),
                  TCol('Guest', width: 140),
                  TCol('Type', width: 120),
                  TCol('Description', width: 180),
                  TCol('Assigned', width: 120),
                  TCol('Status', width: 100),
                  TCol('Actions', right: true, width: 130),
                ],
                rows: [
                  for (final r in items)
                    [
                      InkWell(onTap: () => _detail(r), child: cellText(_day(r['createdat']))),
                      Align(alignment: Alignment.centerLeft, child: _badge(_dash(r['roomnumber']), (Colors.white, TColors.slate700))),
                      InkWell(
                        onTap: () => _detail(r),
                        child: cellText(tStr(r['firstname']).isNotEmpty ? '${tStr(r['firstname'])} ${tStr(r['lastname'])}' : '—', bold: true),
                      ),
                      Align(alignment: Alignment.centerLeft, child: _badge(tStr(r['requesttype']), (TColors.violet50, TColors.violet700))),
                      cellText(_dash(r['description'])),
                      cellText(_dash(r['assignedto'])),
                      Align(alignment: Alignment.centerLeft, child: _badge(tStr(r['status']), _requestStatusTone[tStr(r['status'])])),
                      Wrap(alignment: WrapAlignment.end, children: _actions(r)),
                    ],
                ],
              ),
              pager: _pager(filtered.length, _page, _size, (p) => setState(() => _page = p), (v) => setState(() {
                    _size = v;
                    _page = 1;
                  })),
            ),
        ]),
      ),
    );
  }
}

class _RequestDialog extends StatefulWidget {
  const _RequestDialog({required this.session, required this.company, required this.bookings, required this.rooms, required this.types, required this.staff});
  final Session session;
  final Company company;
  final List<Map> bookings, rooms, staff;
  final List<String> types;

  @override
  State<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends State<_RequestDialog> {
  int? _booking, _room;
  String _type = '', _assignedSel = '', _date = '';
  TimeOfDay? _time;
  final _desc = TextEditingController(), _custom = TextEditingController(), _notes = TextEditingController();
  final _typeOther = GlobalKey<HotelOtherSelectState>();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_desc, _custom, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Map? get _bookingRow => widget.bookings.where((b) => tIntOrNull(_v(b, 'hotelBookingId')) == _booking).firstOrNull;

  /// The web's datetime-local value: "2026-10-27T14:30", or "" when no date is set.
  String get _scheduled {
    if (_date.isEmpty) return '';
    final t = _time ?? const TimeOfDay(hour: 0, minute: 0);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${_date}T${two(t.hour)}:${two(t.minute)}';
  }

  String get _assigned => _assignedSel == '__other__' ? _custom.text : _assignedSel;

  Future<void> _save() async {
    if (_type.isEmpty) return trackerToast(context, 'Select a request type', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Hotel/guest-requests', body: {
        'farmId': widget.company.farmId,
        'hotelBookingId': _booking,
        'hotelRoomId': _room,
        'requestType': _type,
        'description': _desc.text,
        'scheduledTime': _scheduled,
        'assignedTo': _assigned,
        'notes': _notes.text,
      });
      await _typeOther.currentState?.remember();
      if (!mounted) return;
      trackerToast(context, 'Request created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _bookingRow;
    return HotelDialog(
      icon: Icons.notifications_none,
      title: 'New Guest Request',
      saveLabel: 'Create',
      saving: _saving,
      onSave: _save,
      children: [
        FilterLabel(
          'Booking (optional)',
          AppSelect<int>(
            value: _booking ?? 0,
            items: [
              const AppSelectItem(value: 0, label: 'None'),
              for (final x in widget.bookings)
                AppSelectItem(
                  value: tIntOrNull(_v(x, 'hotelBookingId')) ?? 0,
                  label: '${tStr(_v(x, 'guestFirstName'))} ${tStr(_v(x, 'guestLastName'))} - ${tStr(_v(x, 'roomNumber')).isNotEmpty ? tStr(_v(x, 'roomNumber')) : tStr(_v(x, 'bookingRef'))}',
                ),
            ],
            onChanged: (v) => setState(() {
              if (v == null || v == 0) {
                _booking = null;
                _room = null;
              } else {
                _booking = v;
                _room = tIntOrNull(_v(_bookingRow ?? const {}, 'hotelRoomId'));
              }
            }),
          ),
        ),
        if (_booking == null)
          FilterLabel(
            'Room',
            AppSelect<int>(
              value: _room ?? 0,
              items: [
                const AppSelectItem(value: 0, label: 'None'),
                for (final r in widget.rooms) AppSelectItem(value: tIntOrNull(_v(r, 'hotelRoomId')) ?? 0, label: 'Room ${tStr(_v(r, 'roomNumber'))}'),
              ],
              onChanged: (v) => setState(() => _room = v == null || v == 0 ? null : v),
            ),
          )
        else if (b != null && tStr(_v(b, 'roomNumber')).isNotEmpty)
          FilterLabel(
            'Room',
            Container(
              height: 44,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: TColors.slate50, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(6)),
              child: Text('Room ${tStr(_v(b, 'roomNumber'))}', style: const TextStyle(fontWeight: FontWeight.w600, color: TColors.violet700)),
            ),
          ),
        FilterLabel(
          'Type *',
          HotelOtherSelect(
            key: _typeOther,
            session: widget.session,
            company: widget.company,
            listKey: 'RequestType',
            baseOptions: widget.types,
            value: _type,
            onChanged: (v) => setState(() => _type = v ?? ''),
            placeholder: 'Select type',
            includeNone: true,
            noneLabel: 'Select type',
            otherLabel: 'Other (type request)',
          ),
        ),
        FilterLabel(
          'Scheduled Time',
          Row(children: [
            Expanded(
              child: AppDateField(
                value: hotelParseYmd(_date),
                hintText: 'dd/mm/yyyy',
                onChanged: (d) => setState(() => _date = d == null ? '' : hotelYmd(d)),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
                if (t != null) setState(() => _time = t);
              },
              icon: const Icon(Icons.schedule, size: 16),
              label: Text(_time == null ? '--:--' : _time!.format(context)),
            ),
          ]),
        ),
        FilterLabel('Description', AppInput(controller: _desc, minLines: 3, maxLines: 6)),
        FilterLabel(
          'Assigned To',
          _staffSelect(widget.staff, _assignedSel, (v) => setState(() {
                _assignedSel = v;
                if (v != '__other__') _custom.clear();
              }), department: true, other: true),
        ),
        if (_assignedSel == '__other__') FilterLabel('Staff Name', AppInput(controller: _custom, hintText: 'Type staff name')),
        FilterLabel('Notes', AppInput(controller: _notes, hintText: 'Internal notes')),
      ],
    );
  }
}

// ================================================================= Lost & Found

/// The built-in categories; HotelOtherSelect adds its own "Other".
const lostFoundCategories = ['Electronics', 'Clothing', 'Documents', 'Jewelry', 'Personal'];
const _lostStatusTone = {'Found': _amber, 'Claimed': _green, 'Stored': _blue, 'Disposed': _slate};

/// Lost & Found's status filter and search.
List<Map> filterLostFound(List<Map> rows, {String status = 'ALL', String search = ''}) {
  final q = search.toLowerCase();
  return [
    for (final r in rows)
      if ((status == 'ALL' || tStr(r['status']) == status) &&
          (q.isEmpty ||
              '${tStr(r['itemdescription'])} ${tStr(r['roomnumber'])} ${tStr(r['foundby'])} ${tStr(r['foundlocation'])} ${tStr(r['category'])}'.toLowerCase().contains(q)))
        r,
  ];
}

class HotelLostFoundScreen extends StatefulWidget {
  const HotelLostFoundScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelLostFoundScreen> createState() => _HotelLostFoundScreenState();
}

class _HotelLostFoundScreenState extends State<HotelLostFoundScreen> {
  List<Map> _items = [], _rooms = [];
  bool _loading = true;
  String _status = 'ALL';
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
      final r = await Future.wait([_api.get('/api/Hotel/lost-and-found', query: q), _api.get('/api/Hotel/rooms', query: q)]);
      if (!mounted) return;
      setState(() {
        _items = hotelRows(r[0]);
        _rooms = hotelRows(r[1]);
      });
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _logItem() async {
    final done = await showDialog<bool>(context: context, builder: (_) => _LostItemDialog(session: widget.session, company: widget.company, rooms: _rooms));
    if (done == true) _load();
  }

  Future<void> _set(Map r, String status, [String? claimedBy]) async {
    final ok = await _patchStatus(context, _api, _farmId, '/api/Hotel/lost-and-found/${tStr(r['hotellostandfoundid'])}/status', status, 'Item marked as $status',
        {'claimedBy': claimedBy});
    if (ok) _load();
  }

  Future<void> _claim(Map r) async {
    final name = TextEditingController();
    final who = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Mark Item as Claimed'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Item: '),
                TextSpan(text: tStr(r['itemdescription']), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              style: const TextStyle(fontSize: 13, color: TColors.slate600),
            ),
            const SizedBox(height: 12),
            FilterLabel('Claimed By *', AppInput(controller: name, hintText: 'Guest/person name')),
          ]),
        ),
        actions: [
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
              onPressed: () {
                if (name.text.trim().isEmpty) return trackerToast(ctx, 'Enter name', error: true);
                Navigator.pop(ctx, name.text);
              },
              child: const Text('Confirm Claimed'),
            ),
          ]),
        ],
      ),
    );
    if (who != null) await _set(r, 'Claimed', who);
  }

  List<Widget> _actions(Map r) {
    final st = tStr(r['status']);
    return [
      if (st == 'Found' || st == 'Stored') TextButton(onPressed: () => _claim(r), child: const Text('Claim')),
      if (st == 'Found') TextButton(onPressed: () => _set(r, 'Stored'), child: const Text('Store')),
      if (st == 'Stored') TextButton(onPressed: () => _set(r, 'Disposed'), child: const Text('Dispose')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-lost-found');
    final filtered = filterLostFound(_items, status: _status, search: _q.text);
    if ((_page - 1) * _size >= filtered.length && _page > 1) _page = 1;
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Lost & Found')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          _header(Icons.inventory_2_outlined, 'Lost & Found'),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: hotelAddButton('Log Item', _logItem)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in const ['ALL', 'Found', 'Claimed', 'Stored', 'Disposed'])
              _filterChip(s == 'ALL' ? 'All' : s, _status == s, () => setState(() {
                    _status = s;
                    _page = 1;
                  })),
          ]),
          const SizedBox(height: 10),
          _search(_q, 'Search item, room, location...', () => setState(() => _page = 1)),
          const SizedBox(height: 12),
          if (_loading)
            _loadingBox()
          else if (filtered.isEmpty)
            _empty('No items found.')
          else
            MobileCardList<Map>(
              striped: true,
              items: pageSlice(filtered, _page, _size),
              keyOf: (r) => tStr(r['hotellostandfoundid']),
              primary: (r) => tStr(r['itemdescription']),
              secondary: (r) => '${_day(r['founddate'])} · Room ${_dash(r['roomnumber'])} · ${_dash(r['category'])}',
              trailing: (r) => _badge(tStr(r['status']), _lostStatusTone[tStr(r['status'])]),
              details: (r) => [
                ('Found By', _dash(r['foundby'])),
                ('Location', _dash(r['foundlocation'])),
                ('Storage', _dash(r['storagelocation'])),
              ],
              actions: _actions,
              table: (items) => TrackerTable(
                columns: const [
                  TCol('Date', width: 100),
                  TCol('Room', width: 70),
                  TCol('Item', width: 180),
                  TCol('Category', width: 110),
                  TCol('Found By', width: 110),
                  TCol('Location', width: 130),
                  TCol('Storage', width: 130),
                  TCol('Status', width: 100),
                  TCol('Actions', right: true, width: 150),
                ],
                rows: [
                  for (final r in items)
                    [
                      cellText(_day(r['founddate'])),
                      cellText(_dash(r['roomnumber'])),
                      cellText(tStr(r['itemdescription']), bold: true),
                      Align(alignment: Alignment.centerLeft, child: _badge(tStr(r['category']), (Colors.white, TColors.slate700))),
                      cellText(_dash(r['foundby'])),
                      cellText(_dash(r['foundlocation'])),
                      cellText(_dash(r['storagelocation'])),
                      Align(alignment: Alignment.centerLeft, child: _badge(tStr(r['status']), _lostStatusTone[tStr(r['status'])])),
                      Wrap(alignment: WrapAlignment.end, children: _actions(r)),
                    ],
                ],
              ),
              pager: _pager(filtered.length, _page, _size, (p) => setState(() => _page = p), (v) => setState(() {
                    _size = v;
                    _page = 1;
                  })),
            ),
        ]),
      ),
    );
  }
}

class _LostItemDialog extends StatefulWidget {
  const _LostItemDialog({required this.session, required this.company, required this.rooms});
  final Session session;
  final Company company;
  final List<Map> rooms;

  @override
  State<_LostItemDialog> createState() => _LostItemDialogState();
}

class _LostItemDialogState extends State<_LostItemDialog> {
  int? _room;
  String _category = '', _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final _item = TextEditingController(), _by = TextEditingController(), _where = TextEditingController(), _storage = TextEditingController();
  final _categoryOther = GlobalKey<HotelOtherSelectState>();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_item, _by, _where, _storage]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_item.text.trim().isEmpty) return trackerToast(context, 'Item description required', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Hotel/lost-and-found', body: {
        'farmId': widget.company.farmId,
        'hotelRoomId': _room,
        'itemDescription': _item.text,
        'foundDate': _date,
        'foundBy': _by.text,
        'foundLocation': _where.text,
        'category': _category,
        'storageLocation': _storage.text,
        'notes': '',
      });
      await _categoryOther.currentState?.remember();
      if (!mounted) return;
      trackerToast(context, 'Item logged');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => HotelDialog(
        icon: Icons.inventory_2_outlined,
        title: 'Log Lost Item',
        saveLabel: 'Log Item',
        saving: _saving,
        onSave: _save,
        children: [
          FilterLabel('Item Description *', AppInput(controller: _item)),
          FilterLabel(
            'Room',
            AppSelect<int>(
              value: _room ?? 0,
              items: [
                const AppSelectItem(value: 0, label: 'None'),
                for (final r in widget.rooms) AppSelectItem(value: tIntOrNull(_v(r, 'hotelRoomId')) ?? 0, label: 'Room ${tStr(_v(r, 'roomNumber'))}'),
              ],
              onChanged: (v) => setState(() => _room = v == null || v == 0 ? null : v),
            ),
          ),
          FilterLabel(
            'Category',
            HotelOtherSelect(
              key: _categoryOther,
              session: widget.session,
              company: widget.company,
              listKey: 'LostFoundCategory',
              baseOptions: lostFoundCategories,
              value: _category,
              onChanged: (v) => setState(() => _category = v ?? ''),
              placeholder: 'Select category',
              otherLabel: 'Other (type category)',
            ),
          ),
          FilterLabel(
            'Found Date',
            AppDateField(value: hotelParseYmd(_date), hintText: 'dd/mm/yyyy', onChanged: (d) => setState(() => _date = d == null ? '' : hotelYmd(d))),
          ),
          FilterLabel('Found By', AppInput(controller: _by)),
          FilterLabel('Found Location', AppInput(controller: _where, hintText: 'e.g. Room 201 bathroom')),
          FilterLabel('Storage Location', AppInput(controller: _storage, hintText: 'e.g. Front desk drawer 3')),
        ],
      );
}
