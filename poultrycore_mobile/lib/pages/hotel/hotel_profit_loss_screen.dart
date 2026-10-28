// Hotel → Sales, Expenses & Money → Money → Profit & Loss, as `app/hotel-profit-loss/page.tsx`:
// laid out like Poultry's page through the Restaurant's copy (CSV / Email / PDF,
// Period + From / To, five KPI tiles that print their own arithmetic, the
// statement as coloured section cards), violet where Poultry is emerald. One
// call, GET /Hotel/profit-loss; its lines map onto Poultry's bands (Revenue;
// the supply lines → Direct costs; other OperatingExpense → Operating
// expenses; OtherCost → Depreciation & financing). Tap a line to see the
// entries behind it (/profit-loss/revenue or /profit-loss/expenses).

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/reports/poultry_report_screen.dart' show defaultEmailRecipient;
import '../poultry/reports/profit_loss_screen.dart' show PlKpi, PlFormula;
import '../poultry/reports/report_defs.dart';
import '../poultry/reports/report_export.dart';
import '../poultry/reports/report_format.dart';
import '../poultry/reports/report_routes.dart';
import '../poultry/reports/report_widgets.dart';
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart' show TColors, rowsOf;
import 'hotel_kit.dart';

const _revenueTone = Color(0xFF047857);
const _directTone = Color(0xFFBE123C);
const _operatingTone = Color(0xFFB45309);
const _otherTone = Color(0xFF6D28D9);
const _subtotalTone = Color(0xFF334155);

/// The supply lines (migration 334): the cost of what guests used.
const hotelDirectCostKeys = {'SuppliesPurchased', 'SuppliesUsed'};

typedef HotelPnlBands = ({List<Map> revenue, List<Map> direct, List<Map> operating, List<Map> other});
typedef HotelPnlTotals = ({num revenue, num direct, num operating, num other, num total, num gross, num operatingProfit, num net});

/// The four bands; cost lines come back as positive amounts.
HotelPnlBands hotelPnlBands(Map? report) {
  final lines = [for (final l in rowsOf(report?['lines'])) if (tNum(l['amount']) != 0) l];
  bool direct(Map l) => hotelDirectCostKeys.contains(tStr(l['lineKey']));
  return (
    revenue: [for (final l in lines) if (l['section'] == 'Revenue') l],
    direct: [for (final l in lines) if (l['section'] == 'OperatingExpense' && direct(l)) l],
    operating: [for (final l in lines) if (l['section'] == 'OperatingExpense' && !direct(l)) l],
    other: [for (final l in lines) if (l['section'] == 'OtherCost') l],
  );
}

HotelPnlTotals hotelPnlTotals(Map? report, HotelPnlBands b) {
  num sum(List<Map> ls) => ls.fold<num>(0, (a, l) => a + tNum(l['amount']));
  num? f(String k) => report?[k] == null ? null : tNum(report![k]);
  final revenue = f('totalRevenue') ?? sum(b.revenue);
  final direct = sum(b.direct);
  final operating = (f('totalExpenses') ?? direct + sum(b.operating)) - direct;
  final other = f('totalOtherCosts') ?? sum(b.other);
  final gross = revenue - direct;
  final operatingProfit = gross - operating;
  final net = f('netProfit') ?? operatingProfit - other;
  return (
    revenue: revenue,
    direct: direct,
    operating: operating,
    other: other,
    total: direct + operating + other,
    gross: gross,
    operatingProfit: operatingProfit,
    net: net,
  );
}

/// A number as JavaScript's String(n) prints it: 75, not 75.0.
String _js(num n) => n == n.roundToDouble() && n.abs() < 1e15 ? n.toInt().toString() : '$n';

class HotelProfitLossScreen extends StatefulWidget {
  const HotelProfitLossScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<HotelProfitLossScreen> createState() => _HotelProfitLossScreenState();
}

class _HotelProfitLossScreenState extends State<HotelProfitLossScreen> {
  final ReportFilterValue _filter = ReportFilterValue.initial();
  FarmMoney _money = const FarmMoney();
  Map? _report;
  bool _loading = true, _downloading = false;
  String _error = '';
  int _seq = 0;

  ApiClient get _api => widget.session.farmClient;

  /// canViewCashLedger on the web; Staff are the ones refused on the phone.
  bool get _canView => (widget.company.role ?? '').toLowerCase() != 'staff';

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    if (_canView) _load();
  }

  Future<void> _load() async {
    if (_filter.fromDate.isEmpty || _filter.toDate.isEmpty) return;
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final r = await _api.get('/api/Hotel/profit-loss',
          query: {'farmId': widget.company.farmId, 'startDate': _filter.fromDate, 'endDate': _filter.toDate});
      if (!mounted || seq != _seq) return;
      setState(() => _report = r is Map ? r : null);
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e.message;
        _report = null;
      });
    }
    if (mounted && seq == _seq) setState(() => _loading = false);
  }

  String _gh(num n) => _money(n);

  // ---------------------------------------------------------------- export

  ReportDocument? _document() {
    final r = _report;
    if (r == null) return null;
    final b = hotelPnlBands(r);
    final t = hotelPnlTotals(r, b);
    final rows = <List<String>>[];
    void push(String label, num? amount, [String kind = '']) => rows.add([kind, label, amount == null ? '' : _js(amount)]);
    void band(String head, List<Map> lines, String total, num amount) {
      push(head, null, 'Section');
      for (final l in lines) {
        push(tStr(l['lineLabel']), tNum(l['amount']));
      }
      push(total, amount, 'Total');
    }

    band('REVENUE', b.revenue, 'Total Revenue', t.revenue);
    band('DIRECT COSTS (SUPPLIES)', b.direct, 'Total Direct Costs', t.direct);
    push('GROSS PROFIT', t.gross, 'Result');
    band('OPERATING EXPENSES', b.operating, 'Total Operating Expenses', t.operating);
    push('OPERATING PROFIT', t.operatingProfit, 'Result');
    band('DEPRECIATION & FINANCING', b.other, 'Total Depreciation & Financing', t.other);
    push('NET PROFIT', t.net, 'Result');
    return ReportDocument(
      title: 'Profit & Loss',
      filename: 'hotel-profit-loss',
      farmName: widget.company.name,
      fromDate: _filter.fromDate,
      toDate: _filter.toDate,
      currencyLabel: _money.label,
      landscape: false,
      cards: [
        (label: 'Total Revenue', value: _gh(t.revenue), accent: null, note: null),
        (label: 'Gross Profit', value: _gh(t.gross), accent: null, note: null),
        (label: 'Operating Profit', value: _gh(t.operatingProfit), accent: null, note: null),
        (label: 'Net Profit', value: _gh(t.net), accent: null, note: null),
      ],
      sections: [
        ReportSection(columns: const [ReportColumn(''), ReportColumn('Line'), ReportColumn('Amount', right: true)], rows: rows),
      ],
    );
  }

  /// The web's CSV: Kind, Line, Amount, every cell quoted.
  Future<void> _csv() async {
    final d = _document();
    if (d == null) return;
    final csv = [
      ['Kind', 'Line', 'Amount'],
      ...d.sections.first.rows,
    ].map((r) => r.map((c) => '"$c"').join(',')).join('\n');
    await ReportExport.sharer('hotel-profit-loss.csv', utf8.encode(csv), 'text/csv', d.title);
  }

  Future<void> _pdf() async {
    final d = _document();
    if (d == null) return;
    setState(() => _downloading = true);
    try {
      await ReportExport.sharePdf(d);
    } catch (e) {
      _toast('PDF failed. $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// The web emails straight to the signed-in address, without asking.
  Future<void> _email() async {
    final d = _document();
    if (d == null) return;
    final to = defaultEmailRecipient(widget.session, widget.company);
    if (!to.contains('@')) {
      _toast('Could not send. No recipient email found. Sign in with an email address or pass an explicit `to`.');
      return;
    }
    setState(() => _downloading = true);
    try {
      await ReportExport.email(_api, d, [to]);
      _toast('Report sent. $to');
    } on ApiException catch (e) {
      _toast('Email failed. ${e.message}');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _go(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  Future<void> _drill(Map line) => showDialog<void>(
        context: context,
        builder: (_) => _DrillDialog(api: _api, farmId: widget.company.farmId, from: _filter.fromDate, to: _filter.toDate, line: line, gh: _gh),
      );

  // ---------------------------------------------------------------- render

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/hotel-profit-loss');
    final body = <Widget>[];
    if (!_canView) {
      body.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text('You do not have access to Profit & Loss.', style: TextStyle(color: TColors.slate600))),
      ));
    } else {
      body.addAll([
        const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 40,
            height: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(color: TColors.violet100, borderRadius: BorderRadius.all(Radius.circular(8))),
              child: Icon(Icons.trending_up, size: 20, color: hotelViolet),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Profit & Loss', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
              Text('Did the hotel make money from its operations this period?', style: TextStyle(fontSize: 13, color: TColors.slate600)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        ReportExportButtons(onCsv: _csv, onEmail: _email, onPdf: _pdf, busy: _downloading, disabled: _report == null),
        const SizedBox(height: 12),
        ReportFilterPanel(
          value: _filter,
          onChanged: () {
            setState(() {});
            _load();
          },
          onReset: () {
            final r = defaultReportRange();
            _filter
              ..fromDate = r.from
              ..toDate = r.to;
            setState(() {});
            _load();
          },
          show: const ReportFilters(),
        ),
        const SizedBox(height: 12),
        if (_error.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(8)),
            child: Text(_error, style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B))),
          ),
          const SizedBox(height: 12),
        ],
        if (_loading)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(12)),
            child: const Center(child: Text('Loading…', style: TextStyle(color: TColors.slate600))),
          )
        else if (_report != null)
          ..._statement(_report!),
      ]);
    }
    return Scaffold(
      backgroundColor: TColors.slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Profit & Loss')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 32), children: body),
      ),
    );
  }

  List<Widget> _statement(Map r) {
    final b = hotelPnlBands(r);
    final t = hotelPnlTotals(r, b);
    String? pct(num n) => t.revenue > 0 ? '${_js((n / t.revenue * 1000).round() / 10)}% of revenue' : null;
    final netTone = t.net > 0 ? TColors.emerald800 : t.net < 0 ? TColors.rose800 : TColors.slate800;
    return [
      twoColumns([
        PlKpi(
          label: 'Total revenue',
          value: _gh(t.revenue),
          tone: 'slate',
          term: 'Everything earned this period',
          tip: 'Room revenue (guest payments received), walk-in restaurant sales and interest on staff loans. Refundable guest deposits are money held for the guest, not revenue.',
          hint: const Text('Rooms, restaurant and other income', style: TextStyle(fontSize: 11, color: TColors.slate500)),
        ),
        PlKpi(
          label: 'Total expenses',
          value: _gh(t.total),
          tone: 'red',
          term: 'Everything taken off revenue',
          tip: 'Every cost in this period: supplies guests used, the cost of running the hotel (wages, utilities, laundry, repairs) and depreciation plus the interest and fees on borrowing. Revenue minus this is Net profit. Owner drawings, loan principal and capital purchases are not costs.',
          hint: PlFormula(op: '+', money: _money, terms: [
            ('Direct costs', t.direct, _directTone),
            ('Operating expenses', t.operating, _operatingTone),
            ('Depreciation & financing', t.other, _otherTone),
          ]),
        ),
        PlKpi(
          label: 'Gross profit',
          value: _gh(t.gross),
          tone: t.gross >= 0 ? 'emerald' : 'red',
          term: pct(t.gross) ?? 'No revenue this period',
          tip: 'Revenue minus the supplies that went into serving guests (amenities, linen, cleaning and kitchen stock).',
          hint: PlFormula(op: '−', money: _money, terms: [
            ('Revenue', t.revenue, _revenueTone),
            ('Direct costs', t.direct, _directTone),
          ]),
        ),
        PlKpi(
          label: 'Operating profit',
          value: _gh(t.operatingProfit),
          tone: t.operatingProfit >= 0 ? 'emerald' : 'red',
          term: 'Before depreciation and financing',
          tip: 'What the business made: gross profit minus the cost of running the hotel. It stops short of wear on assets and the cost of borrowing.',
          hint: PlFormula(op: '−', money: _money, terms: [
            ('Gross profit', t.gross, _subtotalTone),
            ('Operating expenses', t.operating, _operatingTone),
          ]),
        ),
        PlKpi(
          label: t.net < 0 ? 'Net loss' : 'Net profit',
          value: _gh(t.net),
          strong: true,
          tone: t.net > 0 ? 'emerald' : t.net < 0 ? 'red' : 'slate',
          term: pct(t.net),
          tip: 'What is actually left: operating profit minus depreciation and the interest and fees on borrowing. Owner money, loan principal and capital purchases are not in this figure.',
          hint: PlFormula(op: '−', money: _money, terms: [
            ('Operating profit', t.operatingProfit, _subtotalTone),
            ('Depreciation & financing', t.other, _otherTone),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: t.net > 0 ? TColors.emerald50 : t.net < 0 ? TColors.rose50 : TColors.slate50,
          border: Border.all(color: t.net > 0 ? TColors.emerald200 : t.net < 0 ? TColors.rose200 : TColors.slate200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          t.net > 0
              ? 'The hotel made a profit of ${_gh(t.net)} this period.'
              : t.net < 0
                  ? 'The hotel made a loss of ${_gh(t.net.abs())} this period.'
                  : 'The hotel broke even this period.',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: netTone),
        ),
      ),
      const SizedBox(height: 12),
      _section('Revenue', 'emerald', b.revenue, 'Total revenue', t.revenue),
      _section('Direct costs', 'rose', b.direct, 'Total direct costs', t.direct, negative: true),
      _section('Operating expenses', 'amber', b.operating, 'Total operating expenses', t.operating, negative: true),
      _section('Depreciation & financing', 'violet', b.other, 'Total depreciation & financing', t.other, negative: true),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Wrap(spacing: 12, runSpacing: 10, children: [
          for (final (k, v) in [
            ('Room revenue', _gh(tNum(r['roomRevenue']))),
            ('Restaurant / F&B', _gh(tNum(r['restaurantRevenue']))),
            ('Net margin', r['netMarginPercent'] != null ? '${r['netMarginPercent'] is num ? _js(r['netMarginPercent'] as num) : tStr(r['netMarginPercent'])}%' : '—'),
            ('Deposits held (not revenue)', _gh(tNum(r['depositsNet']))),
          ])
            SizedBox(
              width: 140,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TColors.slate900)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Profit is not cash', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: TColors.slate900)),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(children: [
              const TextSpan(
                  text: 'Room revenue is counted when guests pay; restaurant sales when they are paid at the till. Expenses count when '
                      'they are approved, whether or not the supplier has been paid yet. Supplies expensed when consumed reach profit as '
                      'they are used (Internal Use). Owner money and loan principal never touch profit; loan interest and fees do. A '
                      'capital investment is not charged in the month it is bought — its cost reaches profit over time as depreciation, '
                      'which moves no cash. For the cash actually received and spent, see '),
              _spanLink('Cash Flow', '/hotel-cash-flow'),
              const TextSpan(text: '; for why the two differ, see '),
              _spanLink('Financial Activity', '/hotel-financial-activity'),
              const TextSpan(text: '.'),
            ]),
            style: const TextStyle(fontSize: 12, color: TColors.slate600),
          ),
        ]),
      ),
    ];
  }

  InlineSpan _spanLink(String text, String href) => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => _go(href, text),
          child: Text(text, style: const TextStyle(fontSize: 12, color: TColors.slate600, decoration: TextDecoration.underline)),
        ),
      );

  static const _tones = {
    'emerald': (head: Color(0xFFECFDF5), headText: Color(0xFF065F46), total: Color(0x99ECFDF5), border: Color(0xFFA7F3D0)),
    'rose': (head: Color(0xFFFFF1F2), headText: Color(0xFF9F1239), total: Color(0x99FFF1F2), border: Color(0xFFFECDD3)),
    'amber': (head: Color(0xFFFFFBEB), headText: Color(0xFF92400E), total: Color(0x99FFFBEB), border: Color(0xFFFDE68A)),
    'violet': (head: Color(0xFFF5F3FF), headText: Color(0xFF5B21B6), total: Color(0x99F5F3FF), border: Color(0xFFDDD6FE)),
  };

  /// One band; Hotel cost lines are positive, so a cost band prints them in brackets. Tap a line for its entries.
  Widget _section(String title, String tone, List<Map> lines, String totalLabel, num total, {bool negative = false}) {
    final t = _tones[tone]!;
    String money(num n) => negative ? '(${_gh(n)})' : _gh(n);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: t.border), borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: t.head,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(title.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: t.headText)),
        ),
        if (lines.isEmpty)
          const Padding(padding: EdgeInsets.all(14), child: Text('None this period', style: TextStyle(fontSize: 13, color: TColors.slate400)))
        else
          for (final (i, l) in lines.indexed)
            InkWell(
              onTap: () => _drill(l),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: TColors.slate100))),
                child: Row(children: [
                  Flexible(child: Text(tStr(l['lineLabel']), style: const TextStyle(fontSize: 14, color: TColors.slate900))),
                  const SizedBox(width: 6),
                  Text(tStr(l['entryCount']), style: const TextStyle(fontSize: 10, color: TColors.slate400)),
                  const Spacer(),
                  Text(money(tNum(l['amount'])), style: const TextStyle(fontSize: 14, color: TColors.slate900)),
                  const Icon(Icons.chevron_right, size: 16, color: TColors.slate400),
                ]),
              ),
            ),
        Container(
          decoration: BoxDecoration(color: t.total, border: Border(top: BorderSide(color: t.border))),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(child: Text(totalLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate900))),
            Text(money(total), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TColors.slate900)),
          ]),
        ),
      ]),
    );
  }
}

/// The drilldown: the entries behind one line, with a search.
class _DrillDialog extends StatefulWidget {
  const _DrillDialog({required this.api, required this.farmId, required this.from, required this.to, required this.line, required this.gh});
  final ApiClient api;
  final String farmId, from, to;
  final Map line;
  final String Function(num) gh;

  @override
  State<_DrillDialog> createState() => _DrillDialogState();
}

class _DrillDialogState extends State<_DrillDialog> {
  List<Map> _rows = [];
  bool _loading = true;
  final _search = TextEditingController();

  bool get _revenue => widget.line['section'] == 'Revenue';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = tStr(widget.line['lineKey']);
    try {
      final r = await widget.api.get(_revenue ? '/api/Hotel/profit-loss/revenue' : '/api/Hotel/profit-loss/expenses', query: {
        'farmId': widget.farmId,
        'startDate': widget.from,
        'endDate': widget.to,
        // Staff wages are every payroll expense, so its drilldown is unfiltered.
        if (_revenue || key != 'StaffWages') 'lineKey': key,
      });
      if (mounted) setState(() => _rows = rowsOf(r));
    } on ApiException {
      if (mounted) setState(() => _rows = []);
    }
    if (mounted) setState(() => _loading = false);
  }

  static String _day(Object? v) => tStr(v).split('T').first;
  static String _source(Object? s) => switch (tStr(s)) {
        'GuestPayment' => 'Guest payment',
        'RestaurantOrder' => 'Restaurant order',
        _ => 'Staff loan interest',
      };

  @override
  Widget build(BuildContext context) {
    final q = _search.text.toLowerCase();
    final rows = q.isEmpty
        ? _rows
        : [
            for (final r in _rows)
              if (tStr(r['description']).toLowerCase().contains(q) ||
                  tStr(r['category'] ?? r['method']).toLowerCase().contains(q) ||
                  tStr(r['vendor']).toLowerCase().contains(q))
                r,
          ];
    final n = tNum(widget.line['entryCount']).toInt();
    return AlertDialog(
      scrollable: true,
      title: Text.rich(
        TextSpan(children: [
          TextSpan(text: '${tStr(widget.line['lineLabel'])} — ${widget.gh(tNum(widget.line['amount']))}'),
          TextSpan(text: '  ($n ${n == 1 ? 'entry' : 'entries'})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: TColors.slate500)),
        ]),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(onPressed: () => setState(_search.clear), icon: const Icon(Icons.close, size: 16, color: TColors.slate400)),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 28), child: Text('Loading…', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)))
          else if (rows.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 28), child: Text('No entries found.', textAlign: TextAlign.center, style: TextStyle(color: TColors.slate500)))
          else
            for (final r in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate100))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tStr(r['description']).isEmpty ? '—' : tStr(r['description']), style: const TextStyle(fontSize: 13, color: TColors.slate900)),
                      Text(
                        _revenue
                            ? '${_day(r['entryDate'])} · ${_source(r['sourceType'])} · ${tStr(r['method']).isEmpty ? '—' : tStr(r['method'])}'
                            : '${_day(r['expenseDate'])} · ${tStr(r['category']).isEmpty ? '—' : tStr(r['category'])} · ${tStr(r['vendor']).isEmpty ? '—' : tStr(r['vendor'])}',
                        style: const TextStyle(fontSize: 11, color: TColors.slate500),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Text(widget.gh(tNum(r['amount'])), style: TextStyle(fontSize: 13, color: _revenue ? TColors.emerald700 : TColors.rose600)),
                ]),
              ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
