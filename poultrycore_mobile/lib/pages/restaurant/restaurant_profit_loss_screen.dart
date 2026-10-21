// Restaurant → Money → Profit & Loss, as `app/restaurant-profit-loss/page.tsx`:
// laid out like Poultry's page (CSV / Email / PDF, Period + From / To, five KPI
// tiles that print their own arithmetic, then the statement as coloured
// section cards), in rose. KPIs from GET /Restaurant/reports/pnl, the
// statement from GET /Restaurant/finance/pnl-lines (profit-signed lines).

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

const _revenueTone = Color(0xFF047857);
const _directTone = Color(0xFFBE123C);
const _operatingTone = Color(0xFFB45309);
const _otherTone = Color(0xFF6D28D9);
const _subtotalTone = Color(0xFF334155);

/// The statement's totals; costs as positive figures (the lines are profit-signed).
typedef RestaurantPnlTotals = ({num revenue, num direct, num operating, num other, num total, num gross, num operatingProfit, num net});

RestaurantPnlTotals restaurantPnlTotals(List<Map> lines, Map? summary) {
  num sum(String s) => lines.where((l) => l['section'] == s).fold<num>(0, (a, l) => a + tNum(l['amount']));
  final revenue = summary?['revenue'] != null ? tNum(summary!['revenue']) : sum('Revenue');
  final direct = -sum('CostOfSales');
  final operating = -sum('Expenses');
  final other = -sum('Other');
  final gross = revenue - direct;
  final operatingProfit = gross - operating;
  final net = summary?['netProfit'] != null ? tNum(summary!['netProfit']) : operatingProfit - other;
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

class RestaurantProfitLossScreen extends StatefulWidget {
  const RestaurantProfitLossScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<RestaurantProfitLossScreen> createState() => _RestaurantProfitLossScreenState();
}

class _RestaurantProfitLossScreenState extends State<RestaurantProfitLossScreen> {
  final ReportFilterValue _filter = ReportFilterValue.initial();
  FarmMoney _money = const FarmMoney();
  Map? _summary;
  List<Map> _lines = [];
  bool _loading = true;
  bool _downloading = false;
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
    final q = {'farmId': widget.company.farmId, 'from': _filter.fromDate, 'to': _filter.toDate};
    try {
      final r = await Future.wait([
        _api.get('/api/Restaurant/reports/pnl', query: q),
        _api.get('/api/Restaurant/finance/pnl-lines', query: q),
      ]);
      if (!mounted || seq != _seq) return;
      setState(() {
        _summary = r[0] is Map ? r[0] as Map : null;
        _lines = rowsOf(r[1]);
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e.message;
        _summary = null;
        _lines = [];
      });
    }
    if (mounted && seq == _seq) setState(() => _loading = false);
  }

  String _gh(num n) => _money(n);
  List<Map> _bySection(String s) => [for (final l in _lines) if (l['section'] == s && tNum(l['amount']) != 0) l];
  String _pct(Object? v) => '${v is num ? _js(v) : tStr(v)}%';

  // ---------------------------------------------------------------- export

  ReportDocument? _document() {
    final s = _summary;
    if (s == null) return null;
    final t = restaurantPnlTotals(_lines, s);
    final rows = <List<String>>[];
    void push(String label, num? amount, [String kind = '']) => rows.add([kind, label, amount == null ? '' : _js(amount)]);
    push('REVENUE', null, 'Section');
    for (final l in _bySection('Revenue')) {
      push(tStr(l['label']), tNum(l['amount']));
    }
    push('Total Revenue', t.revenue, 'Total');
    push('DIRECT COSTS (COST OF SALES)', null, 'Section');
    for (final l in _bySection('CostOfSales')) {
      push(tStr(l['label']), -tNum(l['amount']));
    }
    push('Total Direct Costs', t.direct, 'Total');
    push('GROSS PROFIT', t.gross, 'Result');
    push('OPERATING EXPENSES', null, 'Section');
    for (final l in _bySection('Expenses')) {
      push(tStr(l['label']), -tNum(l['amount']));
    }
    push('Total Operating Expenses', t.operating, 'Total');
    push('OPERATING PROFIT', t.operatingProfit, 'Result');
    push('DEPRECIATION & FINANCING', null, 'Section');
    for (final l in _bySection('Other')) {
      push(tStr(l['label']), -tNum(l['amount']));
    }
    push('Total Depreciation & Financing', t.other, 'Total');
    push('NET PROFIT', t.net, 'Result');
    return ReportDocument(
      title: 'Profit & Loss',
      filename: 'restaurant-profit-loss',
      farmName: widget.company.name,
      fromDate: _filter.fromDate,
      toDate: _filter.toDate,
      currencyLabel: _money.label,
      landscape: false,
      rose: true,
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
    await ReportExport.sharer('restaurant-profit-loss.csv', utf8.encode(csv), 'text/csv', d.title);
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

  // ---------------------------------------------------------------- render

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/restaurant-profit-loss');
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
              decoration: BoxDecoration(color: Color(0xFFFFE4E6), borderRadius: BorderRadius.all(Radius.circular(8))),
              child: Icon(Icons.trending_up, size: 20, color: Color(0xFFE11D48)),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Profit & Loss', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TColors.slate900)),
              Text('Did the restaurant make money from its operations this period?', style: TextStyle(fontSize: 13, color: TColors.slate600)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        ReportExportButtons(onCsv: _csv, onEmail: _email, onPdf: _pdf, busy: _downloading, disabled: _summary == null),
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
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              border: Border.all(color: const Color(0xFFFECACA)),
              borderRadius: BorderRadius.circular(8),
            ),
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
        else if (_summary != null)
          ..._statement(_summary!),
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

  List<Widget> _statement(Map s) {
    final t = restaurantPnlTotals(_lines, s);
    final sales = t.revenue > 0;
    final netTone = t.net > 0 ? TColors.emerald800 : t.net < 0 ? TColors.rose800 : TColors.slate800;
    return [
      twoColumns([
        PlKpi(
          label: 'Total revenue',
          value: _gh(t.revenue),
          tone: 'slate',
          term: 'Everything sold this period',
          tip: 'What completed orders sold in this period, after discounts and partial refunds, plus service charge and delivery fees — whether or not a pay-later customer has paid yet. Tax is not revenue.',
          hint: const Text('Food, drinks, service charge and delivery fees', style: TextStyle(fontSize: 11, color: TColors.slate500)),
        ),
        PlKpi(
          label: 'Total expenses',
          value: _gh(t.total),
          tone: 'red',
          term: 'Everything taken off revenue',
          tip: 'Every cost in this period: the cost of what was sold (stock charged when purchased or used), the cost of running the restaurant (wages, rent, utilities, gas, repairs) and depreciation plus the interest and fees on borrowing. Revenue minus this is Net profit. Owner drawings, loan principal and capital purchases are not costs.',
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
          term: sales ? '${_pct(s['grossMarginPct'])} of sales' : 'No sales this period',
          tip: 'What the kitchen and bar made: revenue minus the cost of the food, drinks and supplies that went into it.',
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
          tip: 'What the business made: gross profit minus the cost of running the restaurant. It stops short of wear on equipment and the cost of borrowing.',
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
          term: sales ? '${_pct(s['netMarginPct'])} of sales' : null,
          tip: 'What is actually left: operating profit minus depreciation and the interest and fees on borrowing (and cash over / short). Owner money, loan principal and capital purchases are not in this figure.',
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
              ? 'The restaurant made a profit of ${_gh(t.net)} this period.'
              : t.net < 0
                  ? 'The restaurant made a loss of ${_gh(t.net.abs())} this period.'
                  : 'The restaurant broke even this period.',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: netTone),
        ),
      ),
      const SizedBox(height: 12),
      _section('Revenue', 'emerald', _bySection('Revenue'), 'Total revenue', t.revenue),
      _section('Direct costs', 'rose', _bySection('CostOfSales'), 'Total direct costs', t.direct, negative: true),
      _section('Operating expenses', 'amber', _bySection('Expenses'), 'Total operating expenses', t.operating, negative: true),
      _section('Depreciation & financing', 'violet', _bySection('Other'), 'Total depreciation & financing', t.other, negative: true),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: TColors.slate200), borderRadius: BorderRadius.circular(10)),
        child: Wrap(spacing: 12, runSpacing: 10, children: [
          for (final (k, v) in [
            ('Food cost', _pct(s['foodCostPct'])),
            ('Gross margin', _pct(s['grossMarginPct'])),
            ('Net margin', _pct(s['netMarginPct'])),
            ('Completed orders', s['orderCount'] is num ? _js(s['orderCount'] as num) : tStr(s['orderCount'])),
            ('Tips collected', _gh(tNum(s['tipsTotal']))),
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
                  text: 'Revenue counts what completed orders sold, after discounts and partial refunds, plus service charge and delivery fees. '
                      'Tax is left out — it is owed to the tax office. Gift-card sales are not revenue until the card pays for an order. '
                      'Owner money and loan principal never touch profit; loan interest and fees do. '
                      'A capital investment is not charged in the month it is bought — its cost reaches profit over time as depreciation, which moves no cash. '
                      'For the cash actually received and spent, see '),
              _spanLink('Cash Flow', '/restaurant-cash-flow'),
              const TextSpan(text: '; for why the two differ, see '),
              _spanLink('Financial Activity', '/restaurant-financial-activity'),
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

  /// One band of the statement; a cost band prints its lines as costs in brackets.
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: TColors.slate100))),
              child: Row(children: [
                Expanded(child: Text(tStr(l['label']), style: const TextStyle(fontSize: 14, color: TColors.slate900))),
                const SizedBox(width: 8),
                Text(money(negative ? -tNum(l['amount']) : tNum(l['amount'])), style: const TextStyle(fontSize: 14, color: TColors.slate900)),
              ]),
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
