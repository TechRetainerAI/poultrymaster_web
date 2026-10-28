// Hotel → Operations → Front Desk, part 2: Check-out (`app/hotel-check-out`),
// Availability (`app/hotel-availability`), Guest Folio (`app/hotel-guest-folio`),
// Billing (`app/hotel-billing`), Invoices (`app/hotel-invoices`) and Stay History
// (`app/hotel-stay-history`). Amounts print as plain "0.00", as the web's
// toFixed(2); what the web prints in a new window is a PDF in the share sheet.
// API: /Hotel/bookings, /Hotel/billing/charges, /Hotel/billing/payments,
// /Hotel/billing/invoices(/generate), /Hotel/front-desk/check-out,
// /Hotel/availability, /Hotel/setup/room-types, /Hotel/folio/{bookingId},
// /Hotel/checkin-history, /Hotel/checkout-history, /Hotel/guests.

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
import '../poultry/money/money_widgets.dart' show twoUp;
import '../poultry/reports/report_export.dart';
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr, tIntOrNull;
import '../poultry/trackers/tracker_widgets.dart';
import 'hotel_kit.dart';

Object? _v(Map m, String k) => m[k] ?? m[k.toLowerCase()];
String _money(Object? v) => tNum(v).toStringAsFixed(2);
String _day(Object? v) => tStr(v).length >= 10 ? tStr(v).substring(0, 10) : tStr(v);
int _bookingId(Map b) => tIntOrNull(_v(b, 'hotelBookingId')) ?? 0;
String _guestName(Map b) => '${tStr(_v(b, 'guestFirstName'))} ${tStr(_v(b, 'guestLastName'))}'.trim();

const _green = Color(0xFF047857), _red = Color(0xFFB91C1C);

Widget _title(IconData icon, String title, {Widget? trailing}) => Row(children: [
      Icon(icon, size: 24, color: hotelViolet),
      const SizedBox(width: 10),
      Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900))),
      ?trailing,
    ]);

Widget _loadingBox() => const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: hotelViolet)));

Widget _statCard(String label, String value, Color color, {String? hint}) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
        FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color))),
        if (hint != null) Text(hint, style: const TextStyle(fontSize: 11, color: TColors.slate400)),
      ]),
    );

Widget _moneyField(TextEditingController c, VoidCallback changed) => AppInput(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      onChanged: (_) => changed(),
    );

// ==================================================================== Check-out

/// One in-house guest's bill: the room, the extras, what was paid, the balance.
typedef GuestBill = ({Map booking, List<Map> payments, num roomBill, num extraCharges, num grandTotal, num totalPaid, num balance});

/// The Check-out balance filter (all / paid / owes) and search.
List<GuestBill> filterGuestBills(List<GuestBill> bills, {String balance = 'all', String search = ''}) {
  final q = search.toLowerCase();
  return [
    for (final g in bills)
      if (!(balance == 'paid' && g.balance > 0) &&
          !(balance == 'owes' && g.balance <= 0) &&
          (q.isEmpty ||
              _guestName(g.booking).toLowerCase().contains(q) ||
              tStr(_v(g.booking, 'bookingRef')).toLowerCase().contains(q) ||
              tStr(_v(g.booking, 'roomNumber')).toLowerCase().contains(q)))
        g,
  ];
}

const _payMethods = [('Cash', 'Cash'), ('Card', 'Card'), ('MobileMoney', 'Mobile Money'), ('BankTransfer', 'Bank Transfer')];

class HotelCheckOutScreen extends StatefulWidget {
  const HotelCheckOutScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelCheckOutScreen> createState() => _HotelCheckOutScreenState();
}

class _HotelCheckOutScreenState extends State<HotelCheckOutScreen> {
  List<GuestBill> _bills = [];
  bool _loading = true;
  String _filter = 'all';
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
      final r = await Future.wait([_api.get('/api/Hotel/bookings', query: q), _api.get('/api/Hotel/billing/payments', query: q)]);
      final payments = hotelRows(r[1]);
      final bills = <GuestBill>[];
      for (final b in hotelRows(r[0]).where((b) => b['status'] == 'CheckedIn')) {
        List<Map> charges = [];
        try {
          charges = hotelRows(await _api.get('/api/Hotel/billing/charges', query: {...q, 'bookingId': '${_bookingId(b)}'}));
        } on ApiException {
          charges = [];
        }
        final paid = [for (final p in payments) if (tIntOrNull(_v(p, 'hotelBookingId')) == _bookingId(b)) p];
        final room = tNum(_v(b, 'totalAmount'));
        final extras = charges.fold<num>(0, (s, c) => s + tNum(_v(c, 'totalAmount')));
        final total = paid.fold<num>(0, (s, p) => s + tNum(p['amount']));
        bills.add((booking: b, payments: paid, roomBill: room, extraCharges: extras, grandTotal: room + extras, totalPaid: total, balance: room + extras - total));
      }
      if (mounted) setState(() => _bills = bills);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pay(GuestBill g) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _PaymentDialog(session: widget.session, company: widget.company, bill: g));
    if (done == true) _load();
  }

  Future<void> _checkOut(GuestBill g) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _CheckOutDialog(session: widget.session, company: widget.company, bill: g));
    if (done == true) _load();
  }

  Widget _figure(String label, String value, {Color? color, bool big = false}) => Column(children: [
        Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate400)),
        Text(value, style: TextStyle(fontSize: big ? 16 : 13, fontWeight: big ? FontWeight.w700 : FontWeight.w600, color: color)),
      ]);

  Widget _card(GuestBill g) {
    final b = g.booking;
    final paid = g.balance <= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: paid ? const Color(0xFF10B981) : const Color(0xFFEF4444), width: 4),
          top: const BorderSide(color: TColors.slate200),
          right: const BorderSide(color: TColors.slate200),
          bottom: const BorderSide(color: TColors.slate200),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(_guestName(b), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          hotelBadge('Room ${tStr(_v(b, 'roomNumber'))}', const Color(0xFFECFDF5), _green),
          Text(tStr(_v(b, 'bookingRef')), style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: TColors.slate400)),
        ]),
        const SizedBox(height: 4),
        Text('Check-in: ${_day(_v(b, 'checkInDate'))} | Check-out due: ${_day(_v(b, 'checkOutDate'))} | ${tStr(_v(b, 'roomTypeName'))}',
            style: const TextStyle(fontSize: 13, color: TColors.slate500)),
        const SizedBox(height: 10),
        Wrap(spacing: 18, runSpacing: 8, children: [
          _figure('Room', _money(g.roomBill)),
          if (g.extraCharges > 0) _figure('Extras', _money(g.extraCharges)),
          _figure('Total', _money(g.grandTotal), big: true),
          _figure('Paid', _money(g.totalPaid), color: _green),
          _figure('Balance', paid ? '0.00' : _money(g.balance), color: paid ? _green : _red, big: true),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!paid)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: _red, side: const BorderSide(color: Color(0xFFFCA5A5))),
              onPressed: () => _pay(g),
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 16),
              label: Text('Pay ${_money(g.balance)}'),
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: paid ? hotelViolet : TColors.slate400, foregroundColor: Colors.white),
            onPressed: () => _checkOut(g),
            icon: const Icon(Icons.receipt_long, size: 16),
            label: const Text('Check Out'),
          ),
        ]),
        if (g.payments.isNotEmpty) ...[
          const Divider(height: 22),
          const Text('Payment History', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TColors.slate400)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in g.payments)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(4)),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: _money(p['amount']), style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: ' via ${tStr(_v(p, 'paymentMethod'))} — '),
                  TextSpan(text: tStr(p['reference']).isEmpty ? 'N/A' : tStr(p['reference']), style: const TextStyle(fontFamily: 'monospace')),
                  TextSpan(text: '  ${_day(_v(p, 'paymentDate'))}', style: const TextStyle(color: TColors.slate400)),
                ]), style: const TextStyle(fontSize: 11)),
              ),
          ]),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-check-out');
    final filtered = filterGuestBills(_bills, balance: _filter, search: _q.text);
    if ((_page - 1) * _size >= filtered.length && _page > 1) _page = 1;
    final paid = _bills.where((g) => g.balance <= 0).length;
    final owed = _bills.fold<num>(0, (s, g) => s + math.max(0, g.balance));
    Widget chip(String v, String label, int n) => _filter == v
        ? FilledButton(style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 34))), onPressed: () {}, child: Text('$label ($n)'))
        : OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34)),
            onPressed: () => setState(() {
              _filter = v;
              _page = 1;
            }),
            child: Text('$label ($n)'),
          );
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Check-out')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          _title(Icons.logout, 'Check-out'),
          const SizedBox(height: 12),
          twoUp([
            _statCard('Checked-in Guests', '${_bills.length}', TColors.violet700),
            _statCard('Ready to Check-out', '$paid', _green, hint: 'Balance settled'),
            _statCard('With Outstanding Balance', '${_bills.length - paid}', _red),
            _statCard('Total Outstanding', _money(owed), _red),
          ]),
          const SizedBox(height: 12),
          AppInput(controller: _q, hintText: 'Search guest name, ref, room...', prefixIcon: const Icon(Icons.search, size: 18), onChanged: (_) => setState(() => _page = 1)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            chip('all', 'All', _bills.length),
            chip('paid', 'Paid', paid),
            chip('owes', 'Owes', _bills.length - paid),
          ]),
          const SizedBox(height: 12),
          if (_loading)
            _loadingBox()
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(_q.text.isNotEmpty || _filter != 'all' ? 'No matching guests found.' : 'No guests currently checked in.',
                  textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate400)),
            )
          else ...[
            for (final g in pageSlice(filtered, _page, _size)) _card(g),
            CompactPager(
              total: filtered.length,
              page: _page,
              pageSize: _size,
              onPage: (p) => setState(() => _page = p),
              onPageSize: (v) => setState(() {
                _size = v;
                _page = 1;
              }),
            ),
          ],
        ]),
      ),
    );
  }
}

class _CheckOutDialog extends StatefulWidget {
  const _CheckOutDialog({required this.session, required this.company, required this.bill});
  final Session session;
  final Company company;
  final GuestBill bill;

  @override
  State<_CheckOutDialog> createState() => _CheckOutDialogState();
}

class _CheckOutDialogState extends State<_CheckOutDialog> {
  final _late = TextEditingController(text: '0'), _damage = TextEditingController(text: '0'), _notes = TextEditingController();
  bool _key = true, _saving = false;

  @override
  void dispose() {
    for (final c in [_late, _damage, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  num get _lateNum => num.tryParse(_late.text) ?? 0;
  num get _damageNum => num.tryParse(_damage.text) ?? 0;
  num get _final => widget.bill.balance + _lateNum + _damageNum;

  Future<void> _save() async {
    final b = widget.bill.booking;
    if (_final > 0) {
      return trackerToast(context, 'Guest has an outstanding balance',
          description: 'Balance of ${_money(_final)} must be settled before checkout. Record a payment first.', error: true);
    }
    final room = tIntOrNull(_v(b, 'hotelRoomId'));
    if (room == null) return trackerToast(context, 'No room assigned', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Hotel/front-desk/check-out', body: {
        'farmId': widget.company.farmId,
        'hotelBookingId': _bookingId(b),
        'hotelRoomId': room,
        'lateFee': _lateNum,
        'damageCharges': _damageNum,
        'keyReturned': _key,
        if (_notes.text.isNotEmpty) 'notes': _notes.text,
      });
      if (!mounted) return;
      trackerToast(context, '${_guestName(b)} checked out successfully');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Check-out failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.bill;
    final settled = _final <= 0;
    Widget row(String k, String v, {bool bold = false, Color? color}) => Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : null, color: color))),
          Text(v, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : null, color: color)),
        ]);
    return HotelDialog(
      icon: Icons.logout,
      title: 'Check Out: ${_guestName(g.booking)}',
      saveLabel: 'Confirm Check-out',
      saving: _saving,
      onSave: _save,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            row('Room (${tStr(_v(g.booking, 'roomTypeName'))})', _money(g.roomBill)),
            if (g.extraCharges > 0) row('Additional Charges', _money(g.extraCharges)),
            const Divider(height: 10),
            row('Subtotal', _money(g.grandTotal), bold: true),
            row('Paid', '-${_money(g.totalPaid)}', color: _green),
          ]),
        ),
        FilterLabel('Late Fee', _moneyField(_late, () => setState(() {}))),
        FilterLabel('Damage Charges', _moneyField(_damage, () => setState(() {}))),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: settled ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(settled ? Icons.check_circle_outline : Icons.warning_amber_rounded, color: settled ? const Color(0xFF059669) : TColors.red600),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Final Balance: ${_money(_final)}', style: TextStyle(fontWeight: FontWeight.w700, color: settled ? _green : _red)),
                Text(
                  settled ? 'Balance settled. Ready for checkout.' : 'Guest must settle this balance before checkout. Use the "Pay" button on the guest card.',
                  style: TextStyle(fontSize: 12, color: settled ? const Color(0xFF059669) : TColors.red600),
                ),
              ]),
            ),
          ]),
        ),
        InkWell(
          onTap: () => setState(() => _key = !_key),
          child: Row(children: [
            Checkbox(value: _key, activeColor: hotelViolet, onChanged: (v) => setState(() => _key = v ?? false)),
            const Expanded(child: Text('Key card returned', style: TextStyle(fontSize: 14))),
          ]),
        ),
        FilterLabel('Notes', AppInput(controller: _notes, hintText: 'Optional checkout notes')),
      ],
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.session, required this.company, required this.bill});
  final Session session;
  final Company company;
  final GuestBill bill;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _amount = TextEditingController(text: _plain(math.max(0, widget.bill.balance)));
  String _method = 'Cash';
  bool _saving = false;

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = num.tryParse(_amount.text) ?? 0;
    if (amount <= 0) return;
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Hotel/billing/payments', body: {
        'farmId': widget.company.farmId,
        'hotelBookingId': _bookingId(widget.bill.booking),
        'amount': amount,
        'paymentMethod': _method,
      });
      if (!mounted) return;
      trackerToast(context, 'Payment of ${_money(amount)} recorded');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Payment failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bill.booking;
    return AlertDialog(
      scrollable: true,
      title: Text('Record Payment: ${_guestName(b)}'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Outstanding Balance: '),
                TextSpan(text: _money(widget.bill.balance), style: const TextStyle(fontWeight: FontWeight.w700, color: _red)),
              ]), style: const TextStyle(fontSize: 13)),
              Text('Room ${tStr(_v(b, 'roomNumber'))} | ${tStr(_v(b, 'bookingRef'))}', style: const TextStyle(fontSize: 11, color: TColors.slate500)),
            ]),
          ),
          const SizedBox(height: 12),
          FilterLabel('Payment Amount *', _moneyField(_amount, () => setState(() {}))),
          const SizedBox(height: 10),
          FilterLabel(
            'Payment Method',
            AppSelect<String>(
              value: _method,
              items: [for (final (v, l) in _payMethods) AppSelectItem(value: v, label: l)],
              onChanged: (v) => setState(() => _method = v ?? 'Cash'),
            ),
          ),
          const SizedBox(height: 8),
          const Text('A payment reference code will be generated automatically.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
      ),
      actions: [
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            onPressed: _saving ? null : _save,
            child: const Text('Record Payment'),
          ),
        ]),
      ],
    );
  }
}

// ================================================================== Availability

class HotelAvailabilityScreen extends StatefulWidget {
  const HotelAvailabilityScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelAvailabilityScreen> createState() => _HotelAvailabilityScreenState();
}

class _HotelAvailabilityScreenState extends State<HotelAvailabilityScreen> {
  List<Map> _types = [], _results = [];
  bool _loading = false, _searched = false;
  late String _in = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  late String _out = DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String().substring(0, 10);
  String _type = 'all';

  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    _api.get('/api/Hotel/setup/room-types', query: {'farmId': widget.company.farmId}).then(
      (r) {
        if (mounted) setState(() => _types = hotelRows(r));
      },
      onError: (_) {},
    );
  }

  Future<void> _search() async {
    if (_in.isEmpty || _out.isEmpty) return trackerToast(context, 'Select dates', error: true);
    if (_out.compareTo(_in) <= 0) return trackerToast(context, 'Check-out must be after check-in', error: true);
    setState(() {
      _loading = true;
      _searched = true;
    });
    try {
      final r = await _api.get('/api/Hotel/availability', query: {
        'farmId': widget.company.farmId,
        'checkIn': _in,
        'checkOut': _out,
        if (_type != 'all') 'roomTypeId': _type,
      });
      if (mounted) setState(() => _results = hotelRows(r));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Search failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-availability');
    final floors = <String, List<Map>>{};
    for (final r in _results) {
      floors.putIfAbsent(tStr(r['floorname']).isEmpty ? 'Unassigned' : tStr(r['floorname']), () => []).add(r);
    }
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Availability')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        _title(Icons.search, 'Room Availability'),
        const SizedBox(height: 12),
        TCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FilterLabel('Check-in *', AppDateField(value: hotelParseYmd(_in), onChanged: (d) => setState(() => _in = d == null ? '' : hotelYmd(d)))),
              const SizedBox(height: 10),
              FilterLabel(
                'Check-out *',
                AppDateField(value: hotelParseYmd(_out), firstDate: hotelParseYmd(_in), onChanged: (d) => setState(() => _out = d == null ? '' : hotelYmd(d))),
              ),
              const SizedBox(height: 10),
              FilterLabel(
                'Room Type',
                AppSelect<String>(
                  value: _type,
                  items: [
                    const AppSelectItem(value: 'all', label: 'All Types'),
                    for (final t in _types) AppSelectItem(value: tStr(_v(t, 'hotelRoomTypeId')), label: tStr(t['name'])),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? 'all'),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: hotelPrimary.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 44))),
                onPressed: _loading ? null : _search,
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search, size: 18),
                label: const Text('Search'),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        if (_loading)
          _loadingBox()
        else if (_searched) ...[
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Icon(Icons.bed_outlined, size: 20, color: hotelViolet),
            Text('${_results.length} room(s) available', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text('for $_in to $_out', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          ]),
          const SizedBox(height: 12),
          if (_results.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text('No rooms available for the selected dates and type.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
            )
          else
            for (final f in floors.entries) ...[
              Align(alignment: Alignment.centerLeft, child: hotelBadge(f.key, TColors.violet50, TColors.violet700)),
              const SizedBox(height: 8),
              for (final r in f.value)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text('Room ${tStr(r['roomnumber'])}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                      hotelBadge(tStr(r['status']), const Color(0xFFECFDF5), _green),
                    ]),
                    Text(tStr(r['roomtypename']), style: const TextStyle(fontSize: 13, color: TColors.slate600)),
                    const SizedBox(height: 4),
                    Text('${_money(r['baserate'])} /night', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TColors.violet700)),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: hotelPrimary,
                      onPressed: () => openAppHref(context, widget.session, widget.company, '/hotel-bookings', label: 'Bookings'),
                      icon: const Icon(Icons.bed, size: 16),
                      label: const Text('Book Now'),
                    ),
                  ]),
                ),
              const SizedBox(height: 6),
            ],
        ],
      ]),
    );
  }
}

// =================================================================== Guest Folio

/// The room line's nights, at least one.
int _nights(Object? inDate, Object? outDate) {
  final a = DateTime.tryParse(tStr(inDate)), b = DateTime.tryParse(tStr(outDate));
  if (a == null || b == null) return 1;
  return math.max(1, (b.difference(a).inHours / 24).ceil());
}

class HotelGuestFolioScreen extends StatefulWidget {
  const HotelGuestFolioScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelGuestFolioScreen> createState() => _HotelGuestFolioScreenState();
}

class _HotelGuestFolioScreenState extends State<HotelGuestFolioScreen> {
  List<Map> _bookings = [];
  int? _selected;
  Map? _folio;
  bool _loading = true, _folioLoading = false;

  ApiClient get _api => widget.session.farmClient;

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() => _loading = true);
    try {
      final b = hotelRows(await _api.get('/api/Hotel/bookings', query: {'farmId': widget.company.farmId}));
      if (mounted) setState(() => _bookings = [for (final x in b) if (x['status'] == 'CheckedIn' || x['status'] == 'CheckedOut') x]);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadFolio(int id) async {
    setState(() {
      _selected = id;
      _folioLoading = true;
      _folio = null;
    });
    try {
      final f = await _api.get('/api/Hotel/folio/$id', query: {'farmId': widget.company.farmId});
      if (mounted) setState(() => _folio = f is Map ? f : null);
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed to load folio', description: e.message, error: true);
    }
    if (mounted) setState(() => _folioLoading = false);
  }

  Map get _b => _folio?['booking'] is Map ? _folio!['booking'] as Map : const {};
  Map get _h => _folio?['hotel'] is Map ? _folio!['hotel'] as Map : const {};
  Map get _s => _folio?['summary'] is Map ? _folio!['summary'] as Map : const {};
  List<Map> get _charges => hotelRows(_folio?['charges']);
  List<Map> get _payments => hotelRows(_folio?['payments']);

  /// printFolio: the statement as a PDF for the share sheet.
  Future<void> _print() async {
    final b = _b, h = _h, s = _s;
    final doc = pw.Document();
    pw.Widget cell(String t, {bool right = false, bool bold = false, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(t, textAlign: right ? pw.TextAlign.right : pw.TextAlign.left, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : null, color: color)),
        );
    pw.TableRow head(List<String> cols, Set<int> right) => pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [for (final (i, c) in cols.indexed) cell(c, right: right.contains(i), bold: true)],
        );
    final nights = _nights(b['checkindate'], b['checkoutdate']);
    pw.Widget sum(String k, num v, {bool bold = false, PdfColor? color}) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(k, style: pw.TextStyle(fontSize: bold ? 12 : 10, fontWeight: bold ? pw.FontWeight.bold : null)),
          pw.Text(v.toStringAsFixed(2), style: pw.TextStyle(fontSize: bold ? 12 : 10, fontWeight: bold ? pw.FontWeight.bold : null, color: color)),
        ]);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Center(child: pw.Text(tStr(h['name']), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple))),
        pw.Center(child: pw.Text('${tStr(h['address'])}\n${tStr(h['phone'])} | ${tStr(h['email'])}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9))),
        pw.Divider(color: PdfColors.deepPurple, thickness: 2),
        pw.Text('Guest Folio / Statement', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('Guest: ${tStr(b['firstname'])} ${tStr(b['lastname'])}    Ref: ${tStr(b['bookingref'])}', style: const pw.TextStyle(fontSize: 10)),
        pw.Text('Room: ${tStr(b['roomnumber']).isEmpty ? '-' : tStr(b['roomnumber'])} (${tStr(b['roomtypename'])})    Status: ${tStr(b['status'])}',
            style: const pw.TextStyle(fontSize: 10)),
        pw.Text('Check-in: ${_day(b['checkindate'])}    Check-out: ${_day(b['checkoutdate'])}', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 10),
        pw.Text('Charges', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
        pw.Table(children: [
          head(['Date', 'Type', 'Description', 'Qty', 'Rate', 'Total'], {3, 4, 5}),
          pw.TableRow(children: [
            cell(_day(b['checkindate'])),
            cell('Room'),
            cell('${tStr(b['roomtypename'])} ($nights nights)'),
            cell('1', right: true),
            cell(_money(b['nightlyrate']), right: true),
            cell(_money(b['totalamount']), right: true, bold: true),
          ]),
          for (final c in _charges)
            pw.TableRow(children: [
              cell(_day(c['chargedate'])),
              cell(tStr(c['chargetype'])),
              cell(tStr(c['description'])),
              cell(tStr(c['quantity']).isEmpty ? '1' : tStr(c['quantity']), right: true),
              cell(_money(c['unitprice']), right: true),
              cell(_money(c['totalamount']), right: true, bold: true),
            ]),
        ]),
        pw.SizedBox(height: 10),
        pw.Text('Payments', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
        pw.Table(children: [
          head(['Date', 'Method', 'Reference', 'Amount'], {3}),
          if (_payments.isEmpty)
            pw.TableRow(children: [cell(''), cell('No payments', color: PdfColors.grey), cell(''), cell('')])
          else
            for (final p in _payments)
              pw.TableRow(children: [
                cell(_day(p['paymentdate'])),
                cell(tStr(p['paymentmethod'])),
                cell(tStr(p['reference'])),
                cell(_money(p['amount']), right: true, bold: true, color: PdfColors.green700),
              ]),
        ]),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          color: PdfColors.grey100,
          child: pw.Column(children: [
            sum('Room Total', tNum(s['roomTotal'])),
            sum('Additional Charges', tNum(s['chargesTotal'])),
            sum('Grand Total', tNum(s['grandTotal']), bold: true),
            sum('Total Paid', tNum(s['paymentsTotal']), color: PdfColors.green700),
            sum('Balance Due', tNum(s['balance']), bold: true, color: tNum(s['balance']) <= 0 ? PdfColors.green700 : PdfColors.red700),
          ]),
        ),
        pw.SizedBox(height: 16),
        pw.Center(child: pw.Text('Thank you for staying at ${tStr(h['name'])}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey))),
      ],
    ));
    await ReportExport.sharer('Folio_${tStr(b['bookingref'])}.pdf', await doc.save(), 'application/pdf', 'Guest Folio');
  }

  Widget _field(String label, Widget value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        value,
      ]);

  Widget _folioView() {
    final b = _b, h = _h, s = _s;
    final balance = tNum(s['balance']);
    final adults = tStr(b['adults']), children = tIntOrNull(b['children']) ?? 0;
    Widget bold(String t, {bool mono = false}) => Text(t, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: mono ? 'monospace' : null));
    Widget sumRow(String k, num v, {bool big = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(k, style: TextStyle(fontSize: big ? 17 : 13, fontWeight: big ? FontWeight.w700 : null, color: color ?? (big ? null : TColors.slate500)))),
            Text(v.toStringAsFixed(2), style: TextStyle(fontSize: big ? 17 : 13, fontWeight: big ? FontWeight.w700 : null, color: color)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.violet200), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(tStr(h['name']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: TColors.violet700)),
          Text(tStr(h['address']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          Text('${tStr(h['phone'])} | ${tStr(h['email'])}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
        ]),
      ),
      const SizedBox(height: 12),
      TCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: twoUp([
            _field('Guest', bold('${tStr(b['firstname'])} ${tStr(b['lastname'])}')),
            _field('Ref', bold(tStr(b['bookingref']), mono: true)),
            _field('Room', bold('${tStr(b['roomnumber']).isEmpty ? '—' : tStr(b['roomnumber'])} (${tStr(b['roomtypename'])})')),
            _field(
              'Status',
              Align(
                alignment: Alignment.centerLeft,
                child: b['status'] == 'CheckedIn'
                    ? hotelBadge(tStr(b['status']), const Color(0xFFD1FAE5), _green)
                    : hotelBadge(tStr(b['status']), TColors.slate100, TColors.slate700),
              ),
            ),
            _field('Check-in', Text(_day(b['checkindate']))),
            _field('Check-out', Text(_day(b['checkoutdate']))),
            _field('Guests', Text('$adults adults${children > 0 ? ', $children children' : ''}')),
            _field('Nightly Rate', bold(_money(b['nightlyrate']))),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      TCard(
        title: 'Charges',
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: TrackerTable(
          columns: const [
            TCol('Date', width: 100),
            TCol('Type', width: 100),
            TCol('Description', width: 160),
            TCol('Qty', right: true, width: 50),
            TCol('Rate', right: true, width: 90),
            TCol('Total', right: true, width: 100),
          ],
          rows: [
            [
              cellText(_day(b['checkindate'])),
              cellText('Room'),
              cellText(tStr(b['roomtypename'])),
              cellText('1'),
              cellText(_money(b['nightlyrate'])),
              cellText(_money(b['totalamount']), bold: true),
            ],
            for (final c in _charges)
              [
                cellText(_day(c['chargedate'])),
                cellText(tStr(c['chargetype'])),
                cellText(tStr(c['description'])),
                cellText(tStr(c['quantity']).isEmpty ? '1' : tStr(c['quantity'])),
                cellText(_money(c['unitprice'])),
                cellText(_money(c['totalamount']), bold: true),
              ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      TCard(
        title: 'Payments',
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: _payments.isEmpty
            ? const Padding(padding: EdgeInsets.all(14), child: Text('No payments', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)))
            : TrackerTable(
                columns: const [TCol('Date', width: 100), TCol('Method', width: 110), TCol('Reference', width: 150), TCol('Amount', right: true, width: 110)],
                rows: [
                  for (final p in _payments)
                    [
                      cellText(_day(p['paymentdate'])),
                      cellText(tStr(p['paymentmethod'])),
                      Text(tStr(p['reference']).isEmpty ? '—' : tStr(p['reference']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      cellText(_money(p['amount']), bold: true, color: _green),
                    ],
                ],
              ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.violet200), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          sumRow('Room Total', tNum(s['roomTotal'])),
          sumRow('Additional Charges', tNum(s['chargesTotal'])),
          const Divider(height: 14),
          sumRow('Grand Total', tNum(s['grandTotal']), big: true),
          sumRow('Total Paid', tNum(s['paymentsTotal']), color: _green),
          sumRow('Balance Due', balance, big: true, color: balance <= 0 ? _green : _red),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-guest-folio');
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Guest Folio')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        _title(
          Icons.receipt_long_outlined,
          'Guest Folio',
          trailing: _folio == null ? null : OutlinedButton.icon(onPressed: _print, icon: const Icon(Icons.print_outlined, size: 16), label: const Text('Print Folio')),
        ),
        const SizedBox(height: 12),
        TCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: FilterLabel(
              'Select Booking',
              AppSelect<int>(
                value: _selected,
                hintText: 'Pick a booking...',
                items: [
                  for (final b in _bookings)
                    AppSelectItem(value: _bookingId(b), label: '${tStr(_v(b, 'bookingRef'))} — ${_guestName(b)} (${tStr(b['status'])})'),
                ],
                onChanged: (v) {
                  if (v != null) _loadFolio(v);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (_folioLoading)
          _loadingBox()
        else if (_folio != null)
          _folioView()
        else if (!_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text('Select a booking above to view the guest folio.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
          ),
      ]),
    );
  }
}

// ======================================================================= Billing

/// fmtDateTime for a date: "28/10/2026".
String _dmy(Object? v) {
  final s = tStr(v);
  final d = s.length >= 10 ? DateTime.tryParse(s.substring(0, 10)) : null;
  return d == null ? '—' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// toLocaleString for an instant: "28/10/2026, 14:05:00".
String _local(Object? v) {
  final d = DateTime.tryParse(tStr(v))?.toLocal();
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day}/${d.month}/${d.year}, ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

String _dash(Object? v) => tStr(v).isEmpty ? '—' : tStr(v);

const hotelChargeTypes = ['Room', 'RoomService', 'Minibar', 'Laundry', 'Damage', 'Restaurant', 'Spa', 'Transport', 'Telephone', 'Other'];

class HotelBillingScreen extends StatefulWidget {
  const HotelBillingScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelBillingScreen> createState() => _HotelBillingScreenState();
}

class _HotelBillingScreenState extends State<HotelBillingScreen> {
  List<GuestBill> _bills = [];
  int? _selectedId;
  bool _loading = true;
  final _detailKey = GlobalKey();

  ApiClient get _api => widget.session.farmClient;
  GuestBill? get _selected => _bills.where((b) => _bookingId(b.booking) == _selectedId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = {'farmId': widget.company.farmId};
    try {
      final r = await Future.wait([_api.get('/api/Hotel/bookings', query: q), _api.get('/api/Hotel/billing/payments', query: q)]);
      final payments = hotelRows(r[1]);
      final bills = <GuestBill>[];
      final charges = <int, List<Map>>{};
      for (final b in hotelRows(r[0]).where((b) => b['status'] == 'CheckedIn' || b['status'] == 'Confirmed')) {
        List<Map> c = [];
        try {
          c = hotelRows(await _api.get('/api/Hotel/billing/charges', query: {...q, 'bookingId': '${_bookingId(b)}'}));
        } on ApiException {
          c = [];
        }
        charges[_bookingId(b)] = c;
        final paid = [for (final p in payments) if (tIntOrNull(_v(p, 'hotelBookingId')) == _bookingId(b)) p];
        final room = tNum(_v(b, 'totalAmount'));
        final extras = c.fold<num>(0, (s, x) => s + tNum(_v(x, 'totalAmount')));
        final total = paid.fold<num>(0, (s, p) => s + tNum(p['amount']));
        bills.add((booking: b, payments: paid, roomBill: room, extraCharges: extras, grandTotal: room + extras, totalPaid: total, balance: room + extras - total));
      }
      if (mounted) {
        setState(() {
          _bills = bills;
          _charges = charges;
          if (_selected == null) _selectedId = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Map<int, List<Map>> _charges = {};

  void _select(GuestBill g) {
    setState(() => _selectedId = _bookingId(g.booking));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _detailKey.currentContext;
      if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 250));
    });
  }

  Future<void> _addCharge(GuestBill g) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _AddChargeDialog(session: widget.session, company: widget.company, booking: g.booking));
    if (done == true) _load();
  }

  Future<void> _recordPayment(GuestBill g) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _BillingPaymentDialog(session: widget.session, company: widget.company, bill: g));
    if (done == true) _load();
  }

  Future<void> _generateInvoice(GuestBill g) async {
    try {
      await _api.post('/api/Hotel/billing/invoices/generate', body: {'hotelBookingId': _bookingId(g.booking), 'farmId': widget.company.farmId});
      if (mounted) trackerToast(context, 'Invoice generated');
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  Widget _guestTile(GuestBill g) {
    final b = g.booking;
    final on = _bookingId(b) == _selectedId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: on ? TColors.violet50 : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: on ? const Color(0xFFA78BFA) : TColors.slate200)),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _select(g),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(_guestName(b), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                g.balance <= 0
                    ? hotelBadge('Paid', const Color(0xFFD1FAE5), _green)
                    : hotelBadge('Owes ${_money(g.balance)}', const Color(0xFFFEE2E2), _red),
              ]),
              const SizedBox(height: 4),
              Text('Room ${tStr(_v(b, 'roomNumber')).isEmpty ? 'TBD' : tStr(_v(b, 'roomNumber'))} | ${tStr(_v(b, 'bookingRef'))} | ${tStr(b['status'])}',
                  style: const TextStyle(fontSize: 12, color: TColors.slate500)),
              Text('Total: ${_money(g.grandTotal)} | Paid: ${_money(g.totalPaid)}', style: const TextStyle(fontSize: 12, color: TColors.slate400)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _detail(GuestBill g) {
    final b = g.booking;
    final charges = _charges[_bookingId(b)] ?? const [];
    Widget line(String k, String v, {bool bold = false, Color? color, double size = 13}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(k, style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.w700 : null, color: color))),
            Text(v, style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.w700 : null, color: color)),
          ]),
        );
    final checkedIn = b['status'] == 'CheckedIn';
    return Container(
      key: _detailKey,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_guestName(b), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(
                'Room ${tStr(_v(b, 'roomNumber')).isEmpty ? 'TBD' : tStr(_v(b, 'roomNumber'))} | ${tStr(_v(b, 'bookingRef'))} | '
                '${_dmy(_v(b, 'checkInDate'))} to ${_dmy(_v(b, 'checkOutDate'))}',
                style: const TextStyle(fontSize: 13, color: TColors.slate500),
              ),
            ]),
          ),
          checkedIn
              ? hotelBadge(tStr(b['status']), const Color(0xFFECFDF5), _green)
              : hotelBadge(tStr(b['status']), const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(style: hotelPrimary, onPressed: () => _addCharge(g), icon: const Icon(Icons.add, size: 16), label: const Text('Add Charge')),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: _green, side: const BorderSide(color: Color(0xFF6EE7B7))),
            onPressed: () => _recordPayment(g),
            icon: const Icon(Icons.credit_card, size: 16),
            label: const Text('Record Payment'),
          ),
          OutlinedButton.icon(onPressed: () => _generateInvoice(g), icon: const Icon(Icons.description_outlined, size: 16), label: const Text('Generate Invoice')),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                const TextSpan(text: 'Room Charge', style: TextStyle(fontWeight: FontWeight.w500)),
                TextSpan(text: '  (${tStr(_v(b, 'roomTypeName'))})', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
              ])),
            ),
            Text(_money(g.roomBill), style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
        if (charges.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Additional Charges', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate500)),
          const SizedBox(height: 6),
          TrackerTable(
            columns: const [
              TCol('Type', width: 110),
              TCol('Description', width: 160),
              TCol('Qty', right: true, width: 50),
              TCol('Price', right: true, width: 90),
              TCol('Total', right: true, width: 100),
            ],
            rows: [
              for (final c in charges)
                [
                  Align(alignment: Alignment.centerLeft, child: hotelBadge(tStr(_v(c, 'chargeType')), Colors.white, TColors.slate700)),
                  cellText(tStr(c['description'])),
                  cellText(tStr(c['quantity'])),
                  cellText(_money(_v(c, 'unitPrice'))),
                  cellText(_money(_v(c, 'totalAmount')), bold: true),
                ],
            ],
          ),
        ],
        if (g.payments.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Payments Received', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate500)),
          const SizedBox(height: 6),
          for (final p in g.payments)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                Expanded(
                  child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    hotelBadge(tStr(_v(p, 'paymentMethod')), const Color(0xFFD1FAE5), _green),
                    Text(_dash(p['reference']), style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: TColors.slate400)),
                    Text(_day(_v(p, 'paymentDate')), style: const TextStyle(fontSize: 11, color: TColors.slate400)),
                  ]),
                ),
                Text(_money(p['amount']), style: const TextStyle(fontWeight: FontWeight.w600, color: _green)),
              ]),
            ),
        ],
        const Divider(height: 22),
        line('Room Total', _money(g.roomBill)),
        if (g.extraCharges > 0) line('Additional Charges', _money(g.extraCharges)),
        const Divider(height: 8),
        line('Grand Total', _money(g.grandTotal), bold: true),
        if (g.totalPaid > 0) line('Total Paid', '-${_money(g.totalPaid)}', color: _green),
        const Divider(height: 8),
        line('Balance Due', g.balance <= 0 ? '0.00 (Paid)' : _money(g.balance), bold: true, size: 17, color: g.balance <= 0 ? _green : _red),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-billing');
    final collected = _bills.fold<num>(0, (s, b) => s + b.totalPaid);
    final outstanding = _bills.fold<num>(0, (s, b) => s + math.max(0, b.balance));
    final sel = _selected;
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Billing')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          _title(Icons.receipt, 'Billing'),
          const SizedBox(height: 12),
          _statCard('Active Stays', '${_bills.length}', TColors.violet700),
          const SizedBox(height: 8),
          twoUp([
            _statCard('Total Collected', _money(collected), _green),
            _statCard('Outstanding', _money(outstanding), outstanding > 0 ? _red : _green),
          ]),
          const SizedBox(height: 14),
          if (_loading)
            _loadingBox()
          else ...[
            const Text('SELECT A GUEST', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.slate500)),
            const SizedBox(height: 8),
            for (final g in _bills) _guestTile(g),
            if (_bills.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No active stays', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400))),
            const SizedBox(height: 8),
            if (sel == null)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
                child: const Text('Select a guest to view their bill', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
              )
            else
              _detail(sel),
          ],
        ]),
      ),
    );
  }
}

class _AddChargeDialog extends StatefulWidget {
  const _AddChargeDialog({required this.session, required this.company, required this.booking});
  final Session session;
  final Company company;
  final Map booking;

  @override
  State<_AddChargeDialog> createState() => _AddChargeDialogState();
}

class _AddChargeDialogState extends State<_AddChargeDialog> {
  String _type = 'Room';
  final _desc = TextEditingController(), _qty = TextEditingController(text: '1'), _price = TextEditingController(text: '0');
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_desc, _qty, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  num get _q => num.tryParse(_qty.text) ?? 0;
  num get _p => num.tryParse(_price.text) ?? 0;

  Future<void> _save() async {
    if (_desc.text.trim().isEmpty) return trackerToast(context, 'Description required', error: true);
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Hotel/billing/charges', body: {
        'hotelBookingId': _bookingId(widget.booking),
        'chargeType': _type,
        'description': _desc.text,
        'quantity': _q,
        'unitPrice': _p,
        'farmId': widget.company.farmId,
        'totalAmount': _q * _p,
      });
      if (!mounted) return;
      trackerToast(context, 'Charge added');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => HotelDialog(
        icon: Icons.add,
        title: 'Add Charge — ${_guestName(widget.booking)}',
        saveLabel: 'Add Charge',
        saving: _saving,
        onSave: _save,
        children: [
          FilterLabel(
            'Charge Type',
            AppSelect<String>(
              value: _type,
              items: [for (final t in hotelChargeTypes) AppSelectItem(value: t, label: t)],
              onChanged: (v) => setState(() => _type = v ?? 'Room'),
            ),
          ),
          FilterLabel('Description *', AppInput(controller: _desc, hintText: 'e.g. Minibar drinks, Room service dinner')),
          FilterLabel('Quantity', _moneyField(_qty, () => setState(() {}))),
          FilterLabel('Unit Price', _moneyField(_price, () => setState(() {}))),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: TColors.violet50, borderRadius: BorderRadius.circular(6)),
            child: Text('Charge Total: ${(_q * _p).toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColors.violet700)),
          ),
        ],
      );
}

class _BillingPaymentDialog extends StatefulWidget {
  const _BillingPaymentDialog({required this.session, required this.company, required this.bill});
  final Session session;
  final Company company;
  final GuestBill bill;

  @override
  State<_BillingPaymentDialog> createState() => _BillingPaymentDialogState();
}

class _BillingPaymentDialogState extends State<_BillingPaymentDialog> {
  late final _amount = TextEditingController(text: _PaymentDialogState._plain(math.max(0, widget.bill.balance)));
  final _ref = TextEditingController(), _notes = TextEditingController();
  String _method = 'Cash';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_amount, _ref, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final amount = num.tryParse(_amount.text) ?? 0;
    if (amount <= 0) return;
    setState(() => _saving = true);
    try {
      await widget.session.farmClient.post('/api/Hotel/billing/payments', body: {
        'hotelBookingId': _bookingId(widget.bill.booking),
        'amount': amount,
        'paymentMethod': _method,
        if (_ref.text.isNotEmpty) 'reference': _ref.text,
        if (_notes.text.isNotEmpty) 'notes': _notes.text,
        'farmId': widget.company.farmId,
      });
      if (!mounted) return;
      trackerToast(context, 'Payment of ${_money(amount)} recorded');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      trackerToast(context, 'Failed', description: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.bill;
    Widget row(String k, String v, {bool bold = false, Color? color}) => Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : null, color: color))),
          Text(v, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w600, color: color)),
        ]);
    return AlertDialog(
      scrollable: true,
      title: Text('Record Payment — ${_guestName(g.booking)}'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TColors.slate50, borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              row('Grand Total', _money(g.grandTotal)),
              row('Already Paid', _money(g.totalPaid), color: _green),
              const Divider(height: 10),
              row('Balance', _money(g.balance), bold: true, color: g.balance <= 0 ? _green : _red),
            ]),
          ),
          const SizedBox(height: 12),
          FilterLabel('Payment Amount *', _moneyField(_amount, () => setState(() {}))),
          const SizedBox(height: 10),
          FilterLabel(
            'Payment Method',
            AppSelect<String>(
              value: _method,
              items: [for (final (v, l) in _payMethods) AppSelectItem(value: v, label: l)],
              onChanged: (v) => setState(() => _method = v ?? 'Cash'),
            ),
          ),
          const SizedBox(height: 10),
          FilterLabel('Reference (optional)', AppInput(controller: _ref, hintText: 'Auto-generated if empty')),
          const SizedBox(height: 10),
          FilterLabel('Notes', AppInput(controller: _notes)),
          const SizedBox(height: 8),
          const Text('A payment reference code will be generated automatically if not provided.', style: TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
      ),
      actions: [
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            onPressed: _saving ? null : _save,
            child: const Text('Record Payment'),
          ),
        ]),
      ],
    );
  }
}

// ====================================================================== Invoices

const _invoiceStatusColors = {
  'Draft': (TColors.slate100, TColors.slate700),
  'Issued': (Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  'Paid': (Color(0xFFD1FAE5), _green),
  'PartiallyPaid': (Color(0xFFFEF3C7), Color(0xFFB45309)),
  'Void': (Color(0xFFFEE2E2), _red),
};

/// Poultry's wording for a part-paid document; the stored value stays PartiallyPaid.
String hotelInvoiceStatusLabel(String s) => s == 'PartiallyPaid' ? 'Partially paid' : s;

String _dmyToday() {
  final d = DateTime.now();
  return '${d.day}/${d.month}/${d.year}';
}

class HotelInvoicesScreen extends StatefulWidget {
  const HotelInvoicesScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelInvoicesScreen> createState() => _HotelInvoicesScreenState();
}

class _HotelInvoicesScreenState extends State<HotelInvoicesScreen> {
  List<Map> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await widget.session.farmClient.get('/api/Hotel/billing/invoices', query: {'farmId': widget.company.farmId});
      if (mounted) setState(() => _items = hotelRows(r));
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _status(Map i) {
    final s = tStr(i['status']);
    final c = _invoiceStatusColors[s] ?? (Colors.white, TColors.slate700);
    return hotelBadge(hotelInvoiceStatusLabel(s), c.$1, c.$2);
  }

  Future<void> _preview(Map i) => showDialog<void>(context: context, builder: (_) => _InvoicePreview(invoice: i, hotelName: widget.company.name));

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-invoices');
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Invoices')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          _title(
            Icons.description_outlined,
            'Invoices',
            trailing: Text('(${_items.length})', style: const TextStyle(fontSize: 14, color: TColors.slate500)),
          ),
          const SizedBox(height: 8),
          const Text('Invoices are generated from the Billing page. Tap an invoice to preview and print.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          const SizedBox(height: 12),
          if (_loading)
            _loadingBox()
          else if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text('No invoices yet. Generate one from the Billing page.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate400)),
            )
          else
            for (final i in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: TColors.slate200)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _preview(i),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(
                            child: Text(tStr(_v(i, 'invoiceNumber')), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                          ),
                          _status(i),
                        ]),
                        Text(_day(_v(i, 'issuedDate')), style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 16, runSpacing: 6, children: [
                          _kv('Subtotal', _money(_v(i, 'subTotal'))),
                          _kv('Tax', _money(_v(i, 'taxAmount'))),
                          _kv('Total', _money(_v(i, 'totalAmount')), bold: true),
                          _kv('Paid', _money(_v(i, 'amountPaid')), color: _green),
                          _kv('Balance', _money(i['balance']), bold: true, color: tNum(i['balance']) > 0 ? _red : _green),
                        ]),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(onPressed: () => _preview(i), icon: const Icon(Icons.print_outlined, size: 16), label: const Text('Print')),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
        ]),
      ),
    );
  }
}

Widget _kv(String k, String v, {bool bold = false, Color? color}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(k, style: const TextStyle(fontSize: 11, color: TColors.slate400)),
      Text(v, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
    ]);

class _InvoicePreview extends StatelessWidget {
  const _InvoicePreview({required this.invoice, required this.hotelName});
  final Map invoice;
  final String hotelName;

  List<(String, String, bool, Color?)> get _lines {
    final i = invoice;
    final bal = tNum(i['balance']);
    return [
      ('Subtotal', _money(_v(i, 'subTotal')), false, null),
      ('Tax (${tNum(_v(i, 'taxRate'))}%)', _money(_v(i, 'taxAmount')), false, null),
      ('Discount', '-${_money(_v(i, 'discountAmount'))}', false, null),
      ('Total Due', _money(_v(i, 'totalAmount')), true, null),
      ('Amount Paid', '-${_money(_v(i, 'amountPaid'))}', false, _green),
      ('Balance', _money(bal), true, bal > 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A)),
    ];
  }

  Future<void> _print() async {
    final i = invoice;
    final doc = pw.Document();
    final number = tStr(_v(i, 'invoiceNumber'));
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(hotelName, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple)),
            pw.Text('Hotel Management System', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('INVOICE', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text(number, style: const pw.TextStyle(fontSize: 13)),
            pw.Text('Date: ${_day(_v(i, 'issuedDate'))}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
          ]),
        ]),
        pw.Divider(color: PdfColors.deepPurple, thickness: 2),
        pw.SizedBox(height: 12),
        for (final (k, v, bold, color) in _lines)
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(k, style: pw.TextStyle(fontSize: bold ? 13 : 11, fontWeight: bold ? pw.FontWeight.bold : null)),
              pw.Text(v,
                  style: pw.TextStyle(
                    fontSize: bold ? 13 : 11,
                    fontWeight: bold ? pw.FontWeight.bold : null,
                    color: color == null ? null : PdfColor.fromInt(color.toARGB32()),
                  )),
            ]),
          ),
        pw.SizedBox(height: 24),
        pw.Center(child: pw.Text('Thank you for staying with us!', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey))),
        pw.Center(child: pw.Text('$hotelName - Generated on ${_dmyToday()}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey))),
      ]),
    ));
    await ReportExport.sharer('Invoice_$number.pdf', await doc.save(), 'application/pdf', 'Invoice $number');
  }

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    return AlertDialog(
      scrollable: true,
      title: const Text('Invoice Preview'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 8, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hotelName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.violet700)),
              const Text('Hotel Management System', style: TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('INVOICE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(tStr(_v(i, 'invoiceNumber')), style: const TextStyle(fontSize: 15, fontFamily: 'monospace')),
              Text('Date: ${_day(_v(i, 'issuedDate'))}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
            ]),
          ]),
          const Divider(color: hotelViolet, thickness: 2, height: 24),
          for (final (k, v, bold, color) in _lines)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate100))),
              child: Row(children: [
                Expanded(child: Text(k, style: TextStyle(fontSize: bold ? 16 : 13, fontWeight: bold ? FontWeight.w700 : null, color: color ?? (bold ? null : TColors.slate500)))),
                Text(v, style: TextStyle(fontSize: bold ? 16 : 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w600, color: color)),
              ]),
            ),
          const SizedBox(height: 16),
          const Text('Thank you for staying with us!', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: TColors.slate400)),
          Text('$hotelName — Generated on ${_dmyToday()}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: TColors.slate400)),
        ]),
      ),
      actions: [
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton.icon(style: hotelPrimary, onPressed: _print, icon: const Icon(Icons.print_outlined, size: 16), label: const Text('Print Invoice')),
        ]),
      ],
    );
  }
}

// ================================================================= Stay History

/// The Stay History search: guest name, booking ref or room.
List<Map> filterStayHistory(List<Map> rows, String search) {
  final q = search.toLowerCase();
  if (q.isEmpty) return rows;
  return [
    for (final r in rows)
      if ('${tStr(r['firstname'])} ${tStr(r['lastname'])}'.toLowerCase().contains(q) ||
          tStr(r['bookingref']).toLowerCase().contains(q) ||
          tStr(r['roomnumber']).toLowerCase().contains(q))
        r,
  ];
}

class HotelStayHistoryScreen extends StatefulWidget {
  const HotelStayHistoryScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelStayHistoryScreen> createState() => _HotelStayHistoryScreenState();
}

class _HotelStayHistoryScreenState extends State<HotelStayHistoryScreen> {
  List<Map> _checkins = [], _checkouts = [], _guests = [], _bookings = [];
  bool _loading = true, _outTab = false;
  final _q = TextEditingController();
  int _page = 1, _size = 10;

  ApiClient get _api => widget.session.farmClient;

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
    final q = {'farmId': widget.company.farmId};
    Future<Object?> soft(String p) => _api.get(p, query: q).then<Object?>((r) => r, onError: (_) => const []);
    try {
      final r = await Future.wait([
        _api.get('/api/Hotel/checkin-history', query: q),
        _api.get('/api/Hotel/checkout-history', query: q),
        soft('/api/Hotel/guests'),
        soft('/api/Hotel/bookings'),
      ]);
      if (mounted) {
        setState(() {
          _checkins = hotelRows(r[0]);
          _checkouts = hotelRows(r[1]);
          _guests = hotelRows(r[2]);
          _bookings = hotelRows(r[3]);
        });
      }
    } on ApiException catch (e) {
      if (mounted) trackerToast(context, 'Failed', description: e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _openGuest(Map item) {
    final id = tIntOrNull(_v(item, 'hotelGuestId'));
    final guest = _guests.where((g) => tIntOrNull(_v(g, 'hotelGuestId')) == id).firstOrNull ??
        {
          'hotelGuestId': id ?? 0,
          'firstName': tStr(item['firstname']),
          'lastName': tStr(item['lastname']),
          'email': item['email'] ?? item['guestemail'],
          'phone': item['phone'] ?? item['guestphone'],
          'idType': item['idtype'],
          'idNumber': item['idnumber'],
          'nationality': item['nationality'],
          'address': item['address'],
          'isVIP': item['isvip'] ?? false,
          'totalStays': 0,
          'createdAt': '',
        };
    bool mine(Map r) => id != null && tIntOrNull(_v(r, 'hotelGuestId')) == id;
    showDialog<void>(
      context: context,
      builder: (_) => _StayGuestDialog(
        guest: guest,
        bookings: [for (final b in _bookings) if (mine(b)) b],
        checkins: [for (final c in _checkins) if (mine(c)) c],
        checkouts: [for (final c in _checkouts) if (mine(c)) c],
      ),
    );
  }

  Widget _row(Map r, {required bool out}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: TColors.slate200)),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openGuest(r),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text('${tStr(r['firstname'])} ${tStr(r['lastname'])}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: TColors.violet700)),
                  ),
                  hotelBadge(_dash(r['roomnumber']), Colors.white, TColors.slate700),
                ]),
                Text(tStr(r['bookingref']), style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: TColors.slate500)),
                const SizedBox(height: 6),
                Wrap(spacing: 16, runSpacing: 6, children: out
                    ? [
                        _kv('Check-out Time', _local(r['checkouttime'])),
                        _kv('Final Bill', _money(r['finalbillamount']), bold: true),
                        _kv('Late Fee', _money(r['latefee'])),
                      ]
                    : [
                        _kv('Check-in Time', _local(r['checkintime'])),
                        _kv('Key Card', _dash(r['keycardnumber'])),
                        _kv('Deposit', _money(r['depositamount'])),
                      ]),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-stay-history');
    final ci = filterStayHistory(_checkins, _q.text), co = filterStayHistory(_checkouts, _q.text);
    final rows = _outTab ? co : ci;
    Widget tab(String label, bool out) => Expanded(
          child: _outTab == out
              ? FilledButton(style: hotelPrimary, onPressed: () {}, child: Text(label))
              : OutlinedButton(onPressed: () => setState(() => _outTab = out), child: Text(label)),
        );
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Stay History')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          _title(Icons.history, 'Stay History'),
          const SizedBox(height: 12),
          AppInput(controller: _q, hintText: 'Search guest, ref, room...', prefixIcon: const Icon(Icons.search, size: 18), onChanged: (_) => setState(() => _page = 1)),
          const SizedBox(height: 12),
          if (_loading)
            _loadingBox()
          else ...[
            Row(children: [tab('Check-ins (${ci.length})', false), const SizedBox(width: 8), tab('Check-outs (${co.length})', true)]),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(_outTab ? 'No check-out history.' : 'No check-in history.', textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate400)),
              )
            else
              for (final r in pageSlice(rows, _page, _size)) _row(r, out: _outTab),
            CompactPager(
              total: rows.length,
              page: _page,
              pageSize: _size,
              onPage: (p) => setState(() => _page = p),
              onPageSize: (v) => setState(() {
                _size = v;
                _page = 1;
              }),
            ),
          ],
        ]),
      ),
    );
  }
}

class _StayGuestDialog extends StatelessWidget {
  const _StayGuestDialog({required this.guest, required this.bookings, required this.checkins, required this.checkouts});
  final Map guest;
  final List<Map> bookings, checkins, checkouts;

  Widget _section(String title, Widget child) => Container(
        margin: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TColors.slate500)),
          ),
          child,
        ]),
      );

  Widget _info(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: TColors.slate400),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );

  static Widget _status(Object? s) => switch (tStr(s)) {
        'CheckedIn' => hotelBadge('CheckedIn', const Color(0xFFECFDF5), _green),
        'CheckedOut' => hotelBadge('CheckedOut', TColors.slate100, TColors.slate600),
        'Confirmed' => hotelBadge('Confirmed', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
        'Cancelled' => hotelBadge('Cancelled', const Color(0xFFFEF2F2), _red),
        final x => hotelBadge(x, TColors.slate50, TColors.slate700),
      };

  @override
  Widget build(BuildContext context) {
    final g = guest;
    final contacts = [
      if (tStr(g['phone']).isNotEmpty) _info(Icons.phone_outlined, tStr(g['phone'])),
      if (tStr(g['email']).isNotEmpty) _info(Icons.mail_outline, tStr(g['email'])),
      if (tStr(g['nationality']).isNotEmpty) _info(Icons.public, tStr(g['nationality'])),
      if (tStr(g['address']).isNotEmpty) _info(Icons.place_outlined, tStr(g['address'])),
    ];
    final vip = g['isVIP'] == true || g['isvip'] == true;
    return AlertDialog(
      scrollable: true,
      title: Row(children: [
        const CircleAvatar(radius: 20, backgroundColor: TColors.violet100, child: Icon(Icons.person_outline, color: TColors.violet700)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text('${tStr(_v(g, 'firstName'))} ${tStr(_v(g, 'lastName'))}', style: const TextStyle(fontSize: 18))),
              if (vip) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.star, size: 16, color: Color(0xFFF59E0B))),
            ]),
            Text('${tNum(_v(g, 'totalStays'))} stay(s)', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
          ]),
        ),
      ]),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _section('Contact Information', Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 6), child: Column(children: contacts))),
          if (tStr(_v(g, 'idType')).isNotEmpty)
            _section(
              'Identification',
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(children: [
                  const Icon(Icons.credit_card, size: 16, color: TColors.slate400),
                  const SizedBox(width: 8),
                  Text(tStr(_v(g, 'idType')), style: const TextStyle(fontWeight: FontWeight.w500)),
                  if (tStr(_v(g, 'idNumber')).isNotEmpty)
                    Flexible(child: Text(' — ${tStr(_v(g, 'idNumber'))}', style: const TextStyle(fontFamily: 'monospace', color: TColors.slate600))),
                ]),
              ),
            ),
          if (bookings.isNotEmpty)
            _section(
              'Booking History (${bookings.length})',
              TrackerTable(
                columns: const [TCol('Ref', width: 130), TCol('Room', width: 60), TCol('Dates', width: 190), TCol('Status', width: 100), TCol('Amount', right: true, width: 90)],
                rows: [
                  for (final b in bookings)
                    [
                      Text(tStr(_v(b, 'bookingRef')), style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                      cellText(_dash(_v(b, 'roomNumber'))),
                      cellText('${_day(_v(b, 'checkInDate'))} → ${_day(_v(b, 'checkOutDate'))}'),
                      Align(alignment: Alignment.centerLeft, child: _status(b['status'])),
                      cellText(_money(_v(b, 'totalAmount')), bold: true),
                    ],
                ],
              ),
            ),
          if (checkins.isNotEmpty)
            _section(
              'Check-in History (${checkins.length})',
              TrackerTable(
                columns: const [TCol('Date', width: 170), TCol('Room', width: 60), TCol('Key Card', width: 100), TCol('Deposit', right: true, width: 90)],
                rows: [
                  for (final c in checkins)
                    [cellText(_local(c['checkintime'])), cellText(_dash(c['roomnumber'])), cellText(_dash(c['keycardnumber'])), cellText(_money(c['depositamount']))],
                ],
              ),
            ),
          if (checkouts.isNotEmpty)
            _section(
              'Check-out History (${checkouts.length})',
              TrackerTable(
                columns: const [TCol('Date', width: 170), TCol('Room', width: 60), TCol('Final Bill', right: true, width: 100), TCol('Late Fee', right: true, width: 90)],
                rows: [
                  for (final c in checkouts)
                    [
                      cellText(_local(c['checkouttime'])),
                      cellText(_dash(c['roomnumber'])),
                      cellText(_money(c['finalbillamount']), bold: true),
                      cellText(_money(c['latefee'])),
                    ],
                ],
              ),
            ),
          const Divider(height: 24),
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 4, children: [
            Text('First registered: ${tStr(_v(g, 'createdAt')).isEmpty ? '—' : _local(_v(g, 'createdAt'))}', style: const TextStyle(fontSize: 11, color: TColors.slate400)),
            if (tStr(_v(g, 'lastStayDate')).isNotEmpty) Text('Last stay: ${_dmy(_v(g, 'lastStayDate'))}', style: const TextStyle(fontSize: 11, color: TColors.slate400)),
          ]),
        ]),
      ),
      actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
