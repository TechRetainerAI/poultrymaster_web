// Restaurant → Growth → Events & Catering, as `app/restaurant-events/page.tsx`:
// New Event, four stat cards, the status filter pills with counts, and an event
// card each with the next status steps and delete.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/sales/balances_widgets.dart' show LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/business_dates.dart' show fmtDateTime;
import '../shared/company_clock.dart';
import 'restaurant_setup_screen.dart' show RestaurantTimeField;
import 'restaurant_widgets.dart';

const eventTypes = ['Corporate', 'Wedding', 'Birthday', 'HolidayParty', 'Buffet', 'Cocktail', 'Other'];
const eventStatuses = ['All', 'Inquiry', 'Confirmed', 'Deposit', 'InProgress', 'Completed', 'Cancelled'];

/// STATUS_COLORS: bg, fg.
const eventStatusColors = <String, (Color, Color)>{
  'Inquiry': (Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  'Confirmed': (Color(0xFFDCFCE7), Color(0xFF15803D)),
  'Deposit': (Color(0xFFFEF3C7), Color(0xFFB45309)),
  'InProgress': (Color(0xFFF3E8FF), Color(0xFF7E22CE)),
  'Completed': (Color(0xFFF3F4F6), Color(0xFF374151)),
  'Cancelled': (Color(0xFFFEE2E2), Color(0xFFB91C1C)),
};

/// NEXT_STATUS.
const eventNextStatus = <String, List<String>>{
  'Inquiry': ['Confirmed', 'Cancelled'],
  'Confirmed': ['Deposit', 'Cancelled'],
  'Deposit': ['InProgress', 'Cancelled'],
  'InProgress': ['Completed', 'Cancelled'],
  'Completed': [],
  'Cancelled': [],
};

String _statusLabel(String s) => s == 'InProgress' ? 'In Progress' : s;
String _typeLabel(String t) => t == 'HolidayParty' ? 'Holiday Party' : t;
final _money2 = NumberFormat('#,##0.00', 'en_US');

class RestaurantEventsScreen extends StatefulWidget {
  const RestaurantEventsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantEventsScreen> createState() => _RestaurantEventsScreenState();
}

class _RestaurantEventsScreenState extends State<RestaurantEventsScreen> {
  bool _loading = true;
  List<Map> _events = [];
  String _filter = 'All';
  Duration _offset = Duration.zero;

  ApiClient get _api => widget.session.farmClient;
  Map<String, dynamic> get _q => {'farmId': widget.company.farmId};

  @override
  void initState() {
    super.initState();
    CompanyClock.load(widget.session, widget.company).then((c) {
      if (mounted) setState(() => _offset = c.offset);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.get('/api/Restaurant/events', query: _q);
      _events = [for (final x in (r is List ? r : const [])) if (x is Map) x];
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load events', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _create() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _EventForm(api: _api, farmId: widget.company.farmId),
    ));
    if (saved == true) _load();
  }

  Future<void> _setStatus(Map ev, String status) async {
    try {
      await _api.patch('/api/Restaurant/events/${ev['eventId']}/status', query: _q, body: {'status': status});
      if (mounted) trackerToast(context, 'Status updated to $status');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to update status', description: e.message, error: true);
    }
  }

  Future<void> _delete(Map ev) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Delete this event? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.delete('/api/Restaurant/events/${ev['eventId']}', query: _q);
      if (mounted) trackerToast(context, 'Event deleted');
      await _load();
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to delete event', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-events');
    final now = DateTime.now();
    final filtered = _filter == 'All' ? _events : [for (final e in _events) if (tStr(e['status']) == _filter) e];
    final upcoming = _events.where((e) {
      final d = DateTime.tryParse(tStr(e['eventDate']));
      return d != null && !d.isBefore(now) && tStr(e['status']) != 'Cancelled' && tStr(e['status']) != 'Completed';
    }).length;
    final revenue = _events.where((e) => tStr(e['status']) != 'Cancelled').fold<num>(0, (s, e) => s + tNum(e['totalAmount']));
    final avgGuests = _events.isEmpty ? 0 : (_events.fold<num>(0, (s, e) => s + tNum(e['guestCount'])) / _events.length).round();
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Events & Catering')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
                RPageHeader(
                  icon: Icons.celebration_outlined,
                  title: 'Events & Catering',
                  subtitle: 'Manage private events, banquets, and catering orders',
                  actions: [roseButton('New Event', _create)],
                ),
                const SizedBox(height: 14),
                twoColumns([
                  RStatCard(label: 'Total Events', value: '${_events.length}', icon: Icons.celebration_outlined, color: 'rose'),
                  RStatCard(label: 'Upcoming', value: '$upcoming', icon: Icons.calendar_month_outlined, color: 'blue'),
                  RStatCard(label: 'Total Revenue', value: _money2.format(revenue), icon: Icons.attach_money, color: 'green'),
                  RStatCard(label: 'Avg Guests', value: '$avgGuests', icon: Icons.groups_outlined, color: 'amber'),
                ]),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in eventStatuses)
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => setState(() => _filter = s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _filter == s ? const Color(0xFFE11D48) : Colors.white,
                          border: Border.all(color: _filter == s ? const Color(0xFFE11D48) : TColors.slate200),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: _statusLabel(s)),
                          if (s != 'All')
                            TextSpan(
                                text: ' (${_events.where((e) => tStr(e['status']) == s).length})',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
                        ]), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _filter == s ? Colors.white : const Color(0xFF4B5563))),
                      ),
                    ),
                ]),
                const SizedBox(height: 14),
                if (filtered.isEmpty)
                  TCard(
                    child: REmptyState(
                      icon: Icons.celebration_outlined,
                      title: _filter == 'All' ? 'No events yet' : 'No $_filter events',
                      description: 'Create events for birthdays, weddings, corporate functions, and more',
                      actionLabel: 'Create First Event',
                      onAction: _create,
                    ),
                  )
                else
                  for (final ev in filtered) ...[_eventCard(ev), const SizedBox(height: 12)],
              ]),
            ),
    );
  }

  Widget _info(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: const Color(0xFF4B5563)),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)))),
      ]);

  Widget _eventCard(Map ev) {
    final status = tStr(ev['status']);
    final (sbg, sfg) = eventStatusColors[status] ?? (const Color(0xFFF3F4F6), const Color(0xFF374151));
    final start = tStr(ev['startTime']), end = tStr(ev['endTime']);
    final pph = tNum(ev['pricePerHead']), total = tNum(ev['totalAmount']), deposit = tNum(ev['depositAmount']);
    return TCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(tStr(ev['name']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          if (tStr(ev['eventNumber']).isNotEmpty)
            Text('#${tStr(ev['eventNumber'])}', style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: TColors.slate500)),
          rBadge(_statusLabel(status), bg: sbg, fg: sfg),
        ]),
        const SizedBox(height: 2),
        Text(_typeLabel(tStr(ev['eventType'])), style: const TextStyle(fontSize: 13, color: TColors.slate500)),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _info(Icons.calendar_month_outlined, fmtDateTime(ev['eventDate'], ev, _offset)),
          if (start.isNotEmpty || end.isNotEmpty) _info(Icons.schedule, '$start${start.isNotEmpty && end.isNotEmpty ? ' - ' : ''}$end'),
          _info(Icons.groups_outlined, '${tNum(ev['guestCount']).toInt()} guests'),
          if (tStr(ev['venue']).isNotEmpty) _info(Icons.place_outlined, tStr(ev['venue'])),
        ]),
        if (tStr(ev['contactName']).isNotEmpty || tStr(ev['contactPhone']).isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 16, runSpacing: 4, children: [
            if (tStr(ev['contactName']).isNotEmpty)
              Text(tStr(ev['contactName']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4B5563))),
            if (tStr(ev['contactPhone']).isNotEmpty) _info(Icons.phone_outlined, tStr(ev['contactPhone'])),
            if (tStr(ev['contactEmail']).isNotEmpty) _info(Icons.mail_outline, tStr(ev['contactEmail'])),
          ]),
        ],
        if (pph > 0 || total > 0 || deposit > 0) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 16, runSpacing: 4, children: [
            if (pph > 0)
              Text.rich(TextSpan(children: [
                TextSpan(text: '\$${pph.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w500)),
                const TextSpan(text: '/head'),
              ]), style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563))),
            if (total > 0)
              Text('Total: ${_money2.format(total)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF15803D))),
            if (deposit > 0)
              Text('Deposit: ${deposit.toStringAsFixed(2)}${ev['depositPaid'] == true ? ' (Paid)' : ' (Unpaid)'}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFFB45309))),
          ]),
        ],
        if (tStr(ev['specialRequests']).isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(left: 10),
            decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFFFECDD3), width: 2))),
            child: Text(tStr(ev['specialRequests']),
                style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: TColors.slate500)),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final ns in eventNextStatus[status] ?? const <String>[])
            OutlinedButton(
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => _setStatus(ev, ns),
              child: Text(ns == 'InProgress' ? 'Start' : ns, style: const TextStyle(fontSize: 12)),
            ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
            onPressed: () => _delete(ev),
          ),
        ]),
      ]),
    );
  }
}

/// New Event.
class _EventForm extends StatefulWidget {
  const _EventForm({required this.api, required this.farmId});
  final ApiClient api;
  final String farmId;
  @override
  State<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<_EventForm> {
  final _name = TextEditingController();
  String _type = 'Corporate';
  // EMPTY_FORM's eventDate is today in UTC (new Date().toISOString()).
  String _date = DateTime.now().toUtc().toIso8601String().split('T').first;
  final _guests = TextEditingController(text: '50');
  String _start = '18:00', _end = '22:00';
  final _contactName = TextEditingController();
  final _contactPhone = TextEditingController();
  final _contactEmail = TextEditingController();
  final _pph = TextEditingController();
  final _deposit = TextEditingController();
  String _venue = 'InHouse';
  final _requests = TextEditingController();
  final _dietary = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _guests, _contactName, _contactPhone, _contactEmail, _pph, _deposit, _requests, _dietary]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return trackerToast(context, 'Event name is required', error: true);
    if (_date.isEmpty) return trackerToast(context, 'Event date is required', error: true);
    setState(() => _saving = true);
    try {
      await widget.api.post('/api/Restaurant/events', body: {
        'name': _name.text,
        'eventType': _type,
        'eventDate': _date,
        'startTime': _start,
        'endTime': _end,
        'guestCount': int.tryParse(_guests.text) ?? 0,
        'contactName': _contactName.text,
        'contactPhone': _contactPhone.text,
        'contactEmail': _contactEmail.text,
        'pricePerHead': ?double.tryParse(_pph.text),
        'depositAmount': ?double.tryParse(_deposit.text),
        'venue': _venue,
        'specialRequests': _requests.text,
        'dietaryNotes': _dietary.text,
        'farmId': widget.farmId,
      });
      if (!mounted) return;
      trackerToast(context, 'Event created successfully');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        trackerToast(context, 'Failed to create event', description: e.message, error: true);
      }
    }
  }

  Widget _money(TextEditingController c) => AppInput(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('New Event')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
          const Text('Book a private event or catering order', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 16),
          rLabel('Event Name', required: true),
          AppInput(controller: _name, hintText: 'e.g. Smith Wedding Reception'),
          const SizedBox(height: 12),
          rLabel('Type'),
          AppSelect<String>(
            value: _type,
            items: [for (final t in eventTypes) AppSelectItem(value: t, label: _typeLabel(t))],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          rLabel('Date', required: true),
          AppDateField(
            value: DateTime.tryParse(_date),
            hintText: 'dd/mm/yyyy',
            onChanged: (d) => setState(() => _date = d == null
                ? ''
                : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'),
          ),
          const SizedBox(height: 12),
          rLabel('Guest Count'),
          AppInput(controller: _guests, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
          const SizedBox(height: 12),
          rLabel('Start Time'),
          RestaurantTimeField(value: _start, onChanged: (v) => setState(() => _start = v)),
          const SizedBox(height: 12),
          rLabel('End Time'),
          RestaurantTimeField(value: _end, onChanged: (v) => setState(() => _end = v)),
          const SizedBox(height: 12),
          rLabel('Contact Name'),
          AppInput(controller: _contactName),
          const SizedBox(height: 12),
          rLabel('Contact Phone'),
          AppInput(controller: _contactPhone, keyboardType: TextInputType.phone),
          const SizedBox(height: 12),
          rLabel('Contact Email'),
          AppInput(controller: _contactEmail, hintText: 'email@example.com', keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 12),
          rLabel(r'Price per Head ($)'),
          _money(_pph),
          const SizedBox(height: 12),
          rLabel(r'Deposit Amount ($)'),
          _money(_deposit),
          const SizedBox(height: 12),
          rLabel('Venue'),
          AppSelect<String>(
            value: _venue,
            items: const [AppSelectItem(value: 'InHouse', label: 'In-House'), AppSelectItem(value: 'Offsite', label: 'Offsite')],
            onChanged: (v) => setState(() => _venue = v ?? _venue),
          ),
          const SizedBox(height: 12),
          rLabel('Special Requests'),
          AppTextarea(controller: _requests, hintText: 'Menu preferences, decorations, AV needs...', rows: 2),
          const SizedBox(height: 12),
          rLabel('Dietary Notes'),
          AppTextarea(controller: _dietary, hintText: 'Allergies, vegetarian count, halal requirements...', rows: 2),
          const SizedBox(height: 20),
          rDialogActions(context, _saving ? 'Creating...' : 'Create Event', _saving ? null : _save),
        ]),
      );
}
