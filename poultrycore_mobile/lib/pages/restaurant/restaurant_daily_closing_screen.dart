// Restaurant → Quick Links → Daily Closing, as `app/restaurant-daily-closing/page.tsx`:
// the day under review (a date box, the Orders / Net sales / Cash in − out
// tiles, money in / out, takings, over / short), Open closing (its full
// figures) and Close this day; warnings for open tills and unfinished or
// unpaid orders; and the closed days, newest first, with Reopen on the most
// recent. Closing a day locks it and every earlier day (migration 323).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/reports/report_format.dart' show FarmMoney;
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/sales/balances_logic.dart' show pageSlice;
import '../poultry/sales/balances_widgets.dart' show CompactPager, LoadingLine;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/reason_select.dart' show ReasonSelect, reopenReasons;
import 'restaurant_money_kit.dart' show rField, rFin, rDateInput, rDialog, rCancel, rTodayIso;
import 'restaurant_roles.dart' show restaurantRose;
import 'restaurant_widgets.dart';

/// `nice`: "Tue, 21 Oct 2026", or "—".
String closingNice(Object? iso) {
  final s = tStr(iso);
  final d = s.length >= 10 ? DateTime.tryParse(s.substring(0, 10)) : null;
  return d == null ? '—' : DateFormat('EEE, d MMM yyyy').format(d);
}

const closingStatusColors = <String, (Color, Color)>{
  'Open': (Color(0xFFF1F5F9), Color(0xFF334155)),
  'Closed': (Color(0xFFDCFCE7), Color(0xFF166534)),
  'Reopened': (Color(0xFFFEF3C7), Color(0xFF92400E)),
};

Widget closingBadge(String status) {
  final (bg, fg) = closingStatusColors[status] ?? (const Color(0xFFF3F4F6), const Color(0xFF374151));
  return rBadge(status, bg: bg, fg: fg);
}

/// Every way the day was paid, together.
num dayTakings(Map p) => tNum(p['takingsCash']) + tNum(p['takingsCard']) + tNum(p['takingsMobile']) + tNum(p['takingsGiftCard']) + tNum(p['takingsOther']);

class RestaurantDailyClosingScreen extends StatefulWidget {
  const RestaurantDailyClosingScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantDailyClosingScreen> createState() => _RestaurantDailyClosingScreenState();
}

class _RestaurantDailyClosingScreenState extends State<RestaurantDailyClosingScreen> {
  bool _loading = true;
  String _date = rTodayIso();
  Map? _preview;
  List<Map> _history = [];
  int _page = 1, _size = 20;
  FarmMoney _gh = const FarmMoney();

  ApiClient get _api => widget.session.farmClient;
  String get _farmId => widget.company.farmId;
  bool get _canView => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _gh = m);
    });
    if (_canView) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<Object?>([
        _api.get(rFin('/daily-closing/preview', _farmId, {'date': _date})),
        _api.get(rFin('/daily-closing', _farmId, {'limit': 60})),
      ]);
      _preview = r[0] is Map ? r[0] as Map : null;
      _history = [for (final x in (r[1] is List ? r[1] as List : const [])) if (x is Map) x];
    } catch (e) {
      if (mounted) trackerToast(context, 'Could not load the day', description: e is ApiException ? e.message : '$e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _setDate(String d) {
    if (d.isEmpty) return;
    setState(() => _date = d.substring(0, 10));
    _load();
  }

  Future<void> _newClosing() async {
    final day = await showDialog<String>(context: context, builder: (_) => const _NewClosingDialog());
    if (day == null || !mounted) return;
    _setDate(day);
    await _load();
    if (mounted) _openClosing();
  }

  Future<void> _openClosing([String? day]) async {
    if (day != null && day.substring(0, 10) != _date) {
      setState(() => _date = day.substring(0, 10));
      await _load();
    }
    if (!mounted || _preview == null) return;
    final close = await showDialog<bool>(context: context, builder: (_) => _ViewDialog(date: _date, p: _preview!, gh: _gh));
    if (close == true) await _close();
  }

  Future<void> _close() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _CloseDayDialog(api: _api, farmId: _farmId, date: _date));
    if (ok == true) await _load();
  }

  Future<void> _reopen(Map h) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _ReopenDialog(api: _api, farmId: _farmId, closing: h));
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-daily-closing');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Daily Closing')),
      body: !_canView
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: TCard(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('You do not have access to Daily Closing.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate600)),
                ),
              ),
            )
          : _loading
              ? const Padding(padding: EdgeInsets.all(20), child: LoadingLine('Loading…'))
              : RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final p = _preview;
    final latestClosed = _history.where((h) => tStr(h['status']) == 'Closed').firstOrNull;
    final rows = pageSlice(_history, _page, _size);
    return ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
      Row(children: [
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Daily Closing', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text('End-of-day orders, sales and cash snapshot. Closing a day locks it.', style: TextStyle(fontSize: 13, color: TColors.slate500)),
          ]),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: restaurantRose),
          onPressed: _newClosing,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('New closing'),
        ),
      ]),
      const SizedBox(height: 14),
      if (p != null) _dayCard(p),
      if (p != null &&
          p['isClosed'] != true &&
          (tNum(p['openShifts']) > 0 || tNum(p['openOrders']) > 0 || tNum(p['unpaidOrders']) > 0)) ...[
        const SizedBox(height: 12),
        _warnings(p),
      ],
      const SizedBox(height: 16),
      const Text('CLOSED DAYS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: .8, color: TColors.slate500)),
      const SizedBox(height: 8),
      if (_history.isEmpty)
        const TCard(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No closings yet.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)),
          ),
        )
      else ...[
        for (final (i, h) in rows.indexed) _closedCard(h, striped: i.isOdd, latest: latestClosed != null && tNum(latestClosed['closingId']) == tNum(h['closingId'])),
        CompactPager(
          total: _history.length,
          page: _page,
          pageSize: _size,
          onPage: (v) => setState(() => _page = v),
          onPageSize: (v) => setState(() {
            _size = v;
            _page = 1;
          }),
        ),
      ],
    ]);
  }

  Widget _tile(String label, String value, Color bg, Color border, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: fg)),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: fg)),
        ]),
      );

  Widget _dayTiles(num orders, String sales, String cash) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _tile('Orders', '${orders.toInt()}', const Color(0xFFD1FAE5), const Color(0xFF6EE7B7), const Color(0xFF065F46))),
          const SizedBox(width: 8),
          Expanded(child: _tile('Net sales', sales, const Color(0xFFDBEAFE), const Color(0xFF93C5FD), const Color(0xFF1E40AF))),
        ]),
        const SizedBox(height: 8),
        _tile('Cash in − out', cash, const Color(0xFFEDE9FE), const Color(0xFFC4B5FD), const Color(0xFF4C1D95)),
      ]);

  Widget _pair(String k, String v, {Color? color}) => Text.rich(
        TextSpan(children: [
          TextSpan(text: '$k ', style: const TextStyle(color: TColors.slate500)),
          TextSpan(text: v, style: TextStyle(fontWeight: FontWeight.w500, color: color)),
        ]),
        style: const TextStyle(fontSize: 13),
      );

  Widget _dayCard(Map p) {
    final closed = p['isClosed'] == true;
    final last = tStr(p['lastClosedDate']);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFF1F2), border: Border.all(color: const Color(0xFFFECDD3)), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(closingNice(p['closingDate']), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
          closingBadge(closed ? 'Closed' : 'Open'),
        ]),
        const SizedBox(height: 8),
        Container(color: Colors.white, child: rDateInput(_date, _setDate, max: rTodayIso())),
        const SizedBox(height: 10),
        _dayTiles(tNum(p['orderCount']), _gh(tNum(p['netSales'])), _gh(tNum(p['moneyIn']) - tNum(p['moneyOut']))),
        const Divider(height: 18, color: Color(0xFFFECDD3)),
        Row(children: [
          Expanded(child: _pair('Money in', _gh(tNum(p['moneyIn'])), color: const Color(0xFF047857))),
          Expanded(child: _pair('Money out', _gh(tNum(p['moneyOut'])), color: const Color(0xFFBE123C))),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: _pair('Takings', _gh(dayTakings(p)))),
          Expanded(
              child: _pair('Over / short', _gh(tNum(p['cashVariance'])), color: tNum(p['cashVariance']) < 0 ? const Color(0xFFBE123C) : null)),
        ]),
        const SizedBox(height: 8),
        Text(
          closed
              ? 'The books are locked up to ${closingNice(last)}.'
              : 'Closing it locks this day${last.isNotEmpty ? ' and everything since ${closingNice(last)}' : ' and every earlier day'}.',
          style: const TextStyle(fontSize: 12, color: TColors.slate600),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(42)),
              onPressed: () => _openClosing(),
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('Open closing'),
            ),
          ),
          if (!closed) ...[
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: restaurantRose, minimumSize: const Size.fromHeight(42)),
                onPressed: tNum(p['openShifts']) > 0 ? null : _close,
                icon: const Icon(Icons.lock_outline, size: 16),
                label: const Text('Close this day'),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _warnings(Map p) {
    final shifts = tNum(p['openShifts']).toInt();
    final orders = tNum(p['openOrders']).toInt();
    final unpaid = tNum(p['unpaidOrders']).toInt();
    const style = TextStyle(fontSize: 13, color: Color(0xFF78350F));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFFBEB), border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB45309)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (shifts > 0)
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('$shifts till shift${shifts == 1 ? ' is' : 's are'} still open. ', style: style.copyWith(fontWeight: FontWeight.w700)),
                Text('Close ${shifts == 1 ? 'it' : 'them'} on ', style: style),
                GestureDetector(
                  onTap: () => openAppHref(context, widget.session, widget.company, '/restaurant-tills', label: 'Tills & Shifts'),
                  child: Text('Tills & Shifts', style: style.copyWith(decoration: TextDecoration.underline)),
                ),
                const Text(' before closing the day.', style: style),
              ]),
            if (orders > 0)
              Text('$orders order${orders == 1 ? ' is' : 's are'} not finished. Payments taken on them later will count on the day they are taken.',
                  style: style),
            if (unpaid > 0) Text('$unpaid order${unpaid == 1 ? ' has' : 's have'} money still owing.', style: style),
          ]),
        ),
      ]),
    );
  }

  Widget _closedCard(Map h, {required bool striped, required bool latest}) {
    final status = tStr(h['status']);
    Widget detail(String k, Widget v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(k, style: const TextStyle(fontSize: 13, color: TColors.slate500))),
            v,
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: striped ? const Color(0xFFF8FAFC) : Colors.white,
        border: Border.all(color: TColors.slate200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(closingNice(h['closingDate']), style: const TextStyle(fontWeight: FontWeight.w600)),
          closingBadge(status),
        ]),
        if (status == 'Reopened' && tStr(h['reopenReason']).isNotEmpty)
          Text('Reopened: ${tStr(h['reopenReason'])}', style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        const SizedBox(height: 8),
        _dayTiles(tNum(h['orderCount']), _gh(tNum(h['netSales'])), _gh(tNum(h['moneyIn']) - tNum(h['moneyOut']))),
        const SizedBox(height: 8),
        detail('Money in', Text(_gh(tNum(h['moneyIn'])), style: const TextStyle(fontSize: 13, color: Color(0xFF047857)))),
        detail('Money out', Text(_gh(tNum(h['moneyOut'])), style: const TextStyle(fontSize: 13, color: Color(0xFFBE123C)))),
        detail('Over / short',
            Text(_gh(tNum(h['cashVariance'])), style: TextStyle(fontSize: 13, color: tNum(h['cashVariance']) < 0 ? const Color(0xFFBE123C) : null))),
        detail('Closed by', Text(tStr(h['closedBy']).isEmpty ? '—' : tStr(h['closedBy']), style: const TextStyle(fontSize: 13))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(42)),
              onPressed: () => _openClosing(tStr(h['closingDate'])),
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('Open closing'),
            ),
          ),
          if (latest) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(42)),
                onPressed: () => _reopen(h),
                icon: const Icon(Icons.lock_open_outlined, size: 16),
                label: const Text('Reopen'),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}

class _NewClosingDialog extends StatefulWidget {
  const _NewClosingDialog();
  @override
  State<_NewClosingDialog> createState() => _NewClosingDialogState();
}

class _NewClosingDialogState extends State<_NewClosingDialog> {
  String _day = rTodayIso();

  @override
  Widget build(BuildContext context) => rDialog(
        title: 'New daily closing',
        description: 'Pick the day to review. Nothing is locked until you press Close this day.',
        children: [rField('Closing date', rDateInput(_day, (d) => setState(() => _day = d), max: rTodayIso()))],
        actions: [
          rCancel(context, 'Cancel'),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: restaurantRose),
            onPressed: _day.isEmpty ? null : () => Navigator.pop(context, _day),
            child: const Text('Review day'),
          ),
        ],
      );
}

/// Open closing: the day's full figures. Pops true for "Close this day".
class _ViewDialog extends StatelessWidget {
  const _ViewDialog({required this.date, required this.p, required this.gh});
  final String date;
  final Map p;
  final FarmMoney gh;

  Widget _tile(String label, String value, {String? accent}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: TColors.slate500)),
          Text(value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: switch (accent) {
                  'green' => const Color(0xFF047857),
                  'rose' => const Color(0xFFBE123C),
                  _ => const Color(0xFF0F172A),
                },
              )),
        ]),
      );

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .8, color: TColors.slate500)),
      );

  @override
  Widget build(BuildContext context) {
    final closed = p['isClosed'] == true;
    return AlertDialog(
      scrollable: true,
      title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Closing — ${closingNice(date)}'),
        closingBadge(closed ? 'Closed' : 'Open'),
      ]),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _heading('SALES'),
          twoColumns([
            _tile('Net sales (${tNum(p['orderCount']).toInt()} orders)', gh(tNum(p['netSales'])), accent: 'green'),
            _tile('Discounts given', gh(tNum(p['discounts']))),
            _tile('Service charge', gh(tNum(p['serviceCharge']))),
            _tile('Delivery fees', gh(tNum(p['deliveryFees']))),
            _tile('Tax collected (owed)', gh(tNum(p['taxCollected']))),
            _tile('Tips received', gh(tNum(p['tips']))),
            _tile('Refunds given', gh(-tNum(p['refunds'])), accent: 'rose'),
          ], gap: 8),
          const SizedBox(height: 14),
          _heading('MONEY'),
          twoColumns([
            _tile('Cash', gh(tNum(p['takingsCash']))),
            _tile('Card', gh(tNum(p['takingsCard']))),
            _tile('Mobile money', gh(tNum(p['takingsMobile']))),
            _tile('Gift cards (no cash)', gh(tNum(p['takingsGiftCard']))),
            if (tNum(p['takingsOther']) > 0) _tile('Other', gh(tNum(p['takingsOther']))),
            _tile('Total takings', gh(dayTakings(p)), accent: 'green'),
            _tile('Expenses dated this day', gh(-tNum(p['expenses'])), accent: 'rose'),
            _tile('Money in', gh(tNum(p['moneyIn'])), accent: 'green'),
            _tile('Money out', gh(tNum(p['moneyOut'])), accent: 'rose'),
            _tile('Cash over / short', gh(tNum(p['cashVariance']))),
          ], gap: 8),
          const SizedBox(height: 8),
          const Text("Money in and out are every account's ledger for the day (transfers between your own accounts excluded).",
              style: TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
      ),
      actions: [
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
          if (!closed)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: restaurantRose),
              onPressed: tNum(p['openShifts']) > 0 ? null : () => Navigator.pop(context, true),
              icon: const Icon(Icons.lock_outline, size: 16),
              label: const Text('Close this day'),
            ),
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ]),
      ],
    );
  }
}

class _CloseDayDialog extends StatefulWidget {
  const _CloseDayDialog({required this.api, required this.farmId, required this.date});
  final ApiClient api;
  final String farmId;
  final String date;
  @override
  State<_CloseDayDialog> createState() => _CloseDayDialogState();
}

class _CloseDayDialogState extends State<_CloseDayDialog> {
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await widget.api.post(rFin('/daily-closing', widget.farmId), body: {'closingDate': widget.date, 'notes': _notes.text.isEmpty ? null : _notes.text});
      if (!mounted) return;
      trackerToast(context, '${closingNice(widget.date)} closed', description: 'Nothing dated on or before this day can be changed now.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        trackerToast(context, 'Could not close the day', description: e is ApiException ? e.message : '$e', error: true);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: 'Close ${closingNice(widget.date)}?',
        description: 'After this, no payment, refund, expense, transfer, owner-money or loan entry can be dated on or before this day. '
            'Corrections made later are dated the day they are made.',
        children: [rField('Notes (optional)', AppInput(controller: _notes))],
        actions: [
          rCancel(context, 'Cancel', busy: _saving),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: restaurantRose),
            onPressed: _saving ? null : _submit,
            child: const Text('Close the day'),
          ),
        ],
      );
}

class _ReopenDialog extends StatefulWidget {
  const _ReopenDialog({required this.api, required this.farmId, required this.closing});
  final ApiClient api;
  final String farmId;
  final Map closing;
  @override
  State<_ReopenDialog> createState() => _ReopenDialogState();
}

class _ReopenDialogState extends State<_ReopenDialog> {
  String _reason = '';
  bool _saving = false;

  Future<void> _submit() async {
    if (_reason.trim().isEmpty) return;
    setState(() => _saving = true);
    final day = tStr(widget.closing['closingDate']);
    try {
      await widget.api.post(rFin('/daily-closing/reopen', widget.farmId),
          body: {'closingDate': day.length >= 10 ? day.substring(0, 10) : day, 'reason': _reason.trim()});
      if (!mounted) return;
      trackerToast(context, '${closingNice(day)} reopened');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        trackerToast(context, 'Could not reopen', description: e is ApiException ? e.message : '$e', error: true);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => rDialog(
        title: 'Reopen ${closingNice(widget.closing['closingDate'])}?',
        description: 'Entries dated this day can be changed again until it is closed once more. The reason is kept on record.',
        children: [rField('Reason', ReasonSelect(options: reopenReasons, value: _reason, onChanged: (v) => setState(() => _reason = v)))],
        actions: [
          rCancel(context, 'Cancel', busy: _saving),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: restaurantRose),
            onPressed: _saving || _reason.trim().isEmpty ? null : _submit,
            child: const Text('Reopen'),
          ),
        ],
      );
}
