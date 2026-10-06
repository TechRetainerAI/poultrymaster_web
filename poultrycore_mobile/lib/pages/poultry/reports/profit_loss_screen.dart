import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/buttons.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../lookup_loader.dart';
import '../../shared/business_dates.dart';
import 'poultry_report_screen.dart';
import 'report_defs.dart';
import 'report_export.dart';
import 'report_format.dart';
import 'report_routes.dart';
import 'report_widgets.dart';
import 'reports_catalog_screen.dart';

// The wording of `lib/poultry/financial-classification.ts`.
const profitVsCashTitle = 'Profit is not the same as cash flow';
const profitVsCashBody =
    'Profit measures the revenue and costs that belong to the selected period. Cash Flow measures the money that actually entered and left the company. They are both right, and they can differ.';
const cashNotProfitExamples = [
  'Buying stock you will use later — the cash leaves now, the cost lands as you use it',
  'Buying a building or machine — the cash leaves now, the cost spreads over its useful life',
  'Repaying loan principal — money you are giving back, not a cost',
  'Owner draws — the owner taking money out, not a business cost',
];
const profitNotCashExamples = [
  'Depreciation — a real cost of this period that moves no money',
  'Stock bought earlier and used now — the cost lands now, the cash left months ago',
  'A bill you have received but not yet paid — the cost is yours the day it is incurred',
];
const ownerSectionRule = 'putting money in is not income, and taking it out is not an expense.';
const ownerSectionNote = 'Money the owner puts in or takes out. It changes company cash but is never profit: $ownerSectionRule';
const borrowingSectionRule = 'Borrowing is not income and repaying principal is not an expense';
const borrowingSectionNote =
    'Money borrowed and principal repaid. $borrowingSectionRule — only the interest and fees are a cost of borrowing, and those are already in the expenses above.';
const capitalSectionRule = 'Their cost is recognised over time through depreciation.';
const capitalSectionNote =
    'Capital investments affect cash but are not charged against profit in the period they are bought. $capitalSectionRule';
const plMethodNote =
    'Profit & Loss uses structured revenue, expense, inventory-cost, depreciation and financing classifications. Cash movements such as owner funding, loan principal, inventory bought under consumption costing, and capital investments may affect Cash Flow without affecting profit.';
const itemOverrideTooltip = 'Some inventory items use their own treatment instead of the farm default.';

String? legacyNote(num legacy, num classified) {
  if (legacy <= 0) return null;
  final total = legacy + classified;
  return '${fmtNum(legacy, 0)} of ${fmtNum(total, 0)} cost record${total == 1 ? '' : 's'} in this period predate structured classification and are placed by their category. Newer records carry their classification explicitly.';
}

String recognitionSummaryLine(Object? method, bool hasOverrides) {
  final base = method == 'EXPENSE_WHEN_CONSUMED' ? 'Expense when consumed' : 'Expense when purchased';
  return hasOverrides ? '$base (farm default)' : base;
}

/// drilldownKindFor.
String drilldownKindFor(String section, String lineKey) {
  if (section == 'Revenue') return 'revenue';
  if (section == 'CapitalInvestment') return 'capital';
  if (section == 'Financing') return 'financing';
  if (lineKey == 'Depreciation') return 'depreciation';
  if (lineKey == 'LoanInterest' || lineKey == 'LoanFees') return 'financing';
  if (lineKey == 'Feed' || lineKey == 'Medication') return 'inventory';
  return 'expenses';
}

/// DRILL_COLUMNS: what the two text columns hold, per kind.
const drillColumns = {
  'revenue': (mid: 'Product', right: 'Customer', blurb: 'Every sale behind this figure.'),
  'inventory': (mid: 'Item', right: 'Source', blurb: 'Every stock movement behind this figure, and when its cost was recognised.'),
  'depreciation': (mid: 'Asset', right: 'Category', blurb: "Each asset's depreciation for the period."),
  'financing': (mid: 'Detail', right: 'Party', blurb: 'Every entry behind this figure. None of it is profit.'),
  'capital': (mid: 'Asset', right: 'Detail', blurb: 'What was bought. It is an asset, not an expense.'),
  'expenses': (mid: 'Description', right: 'Supplier', blurb: 'Every expense behind this figure.'),
};

/// DRILL_TONES: the dialog wears the colour of the card it opened from.
typedef DrillTone = ({Color band, Color bandText, Color border, Color amount, Color rail, String label});
const drillTones = <String, DrillTone>{
  'revenue': (band: Color(0xFFECFDF5), bandText: Color(0xFF064E3B), border: Color(0xFFA7F3D0), amount: Color(0xFF047857), rail: Color(0xFF34D399), label: 'Money in'),
  'inventory': (band: Color(0xFFFFF1F2), bandText: Color(0xFF881337), border: Color(0xFFFECDD3), amount: Color(0xFFBE123C), rail: Color(0xFFFB7185), label: 'Direct cost'),
  'expenses': (band: Color(0xFFFFFBEB), bandText: Color(0xFF78350F), border: Color(0xFFFDE68A), amount: Color(0xFFB45309), rail: Color(0xFFFBBF24), label: 'Running cost'),
  'depreciation': (band: Color(0xFFF5F3FF), bandText: Color(0xFF4C1D95), border: Color(0xFFDDD6FE), amount: Color(0xFF6D28D9), rail: Color(0xFFA78BFA), label: 'Depreciation'),
  'financing': (band: Color(0xFFF5F3FF), bandText: Color(0xFF4C1D95), border: Color(0xFFDDD6FE), amount: Color(0xFF6D28D9), rail: Color(0xFFA78BFA), label: 'Not profit'),
  'capital': (band: Color(0xFFF0F9FF), bandText: Color(0xFF0C4A6E), border: Color(0xFFBAE6FD), amount: Color(0xFF0369A1), rail: Color(0xFF38BDF8), label: 'Not an expense'),
};

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// drillDate: "2026-09-02" → "2 Sep 2026", "2026-09" → "Sep 2026".
String drillDate(String v) {
  final m = RegExp(r'^(\d{4})-(\d{2})(?:-(\d{2}))?$').firstMatch(v);
  if (m == null) return v.isEmpty ? '—' : v;
  final month = _months[int.parse(m.group(2)!) - 1];
  return m.group(3) != null ? '${int.parse(m.group(3)!)} $month ${m.group(1)}' : '$month ${m.group(1)}';
}

typedef DrillRow = ({String left, String? mid, String? right, num amount, String? note});

String _day(Object? v) => '${v ?? ''}'.split('T').first;

/// Poultry → Reports → Profit & Loss (Company), as the web's
/// `PoultryProfitLossView` in its report skin (migration 272): a STATEMENT —
/// Revenue, Direct Production Costs, Operating Expenses, Depreciation &
/// Financing — with the owner money, borrowing and capital investments shown
/// beside it and never inside it. Every line opens the records behind it.
class ProfitLossScreen extends StatefulWidget {
  const ProfitLossScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  final ReportFilterValue _filter = ReportFilterValue.initial();
  FarmMoney _money = const FarmMoney();
  Map<String, dynamic>? _data;
  bool _busy = true;
  String? _error;
  bool _downloading = false;
  late final String _generatedAt = generatedNow();
  int _seq = 0;

  ApiClient get _client => widget.session.farmClient;
  Map<String, String> get _range => {'farmId': widget.company.farmId, 'startDate': _filter.fromDate, 'endDate': _filter.toDate};

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _client.get('/api/Poultry/profit-loss', query: _range);
      if (mounted && seq == _seq) setState(() => _data = r is Map ? Map<String, dynamic>.from(r) : null);
    } on ApiException catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e.message);
    } finally {
      if (mounted && seq == _seq) setState(() => _busy = false);
    }
  }

  String _gh(num? n) => _money(n ?? 0);
  num _n(String k) => toNum(_data?[k]);

  List<Map> _section(String s) {
    final lines = [for (final l in (_data?['lines'] is List ? _data!['lines'] as List : const [])) if (l is Map && l['section'] == s) l];
    lines.sort((a, b) => toNum(a['sortOrder']).compareTo(toNum(b['sortOrder'])));
    return lines;
  }

  List<Map> get _ownerLines => [
        for (final l in _section('Financing'))
          if (l['lineKey'] == 'OwnerContributions' || l['lineKey'] == 'OwnerDraws') l,
      ];

  List<Map> get _borrowingLines => [
        for (final l in _section('Financing'))
          if (l['lineKey'] != 'OwnerContributions' && l['lineKey'] != 'OwnerDraws') l,
      ];

  /// Every cost in the period: revenue minus this IS net profit.
  num get _totalExpenses => _n('totalDirectCosts') + _n('totalOperatingExpenses') + _n('totalOtherCosts');

  // ------------------------------------------------------------- drilldown

  Future<List<DrillRow>> _drillRows(Map line, String kind) async {
    final q = {..._range};
    final key = '${line['lineKey']}';
    List rows(Object? r) => LookupLoader.rowsIn(r);
    switch (kind) {
      case 'revenue':
        return [
          for (final r in rows(await _client.get('/api/Poultry/profit-loss/revenue', query: {...q, 'lineKey': key})))
            if (r is Map)
              (left: _day(r['saleDate']), mid: '${r['product'] ?? '—'}', right: '${r['customerName'] ?? '—'}', amount: toNum(r['totalAmount']), note: null),
        ];
      case 'inventory':
        return [
          for (final r in rows(await _client.get('/api/Poultry/profit-loss/inventory', query: {...q, 'lineKey': key})))
            if (r is Map)
              (
                left: _day(r['expenseDate']),
                mid: '${r['itemName'] ?? r['description'] ?? '—'}',
                right: '${r['sourceLabel'] ?? '—'}',
                amount: toNum(r['amount']),
                note: [
                  if (r['recognition'] != null) '${r['recognition']}',
                  if (r['quantity'] != null) '${fmtNum(toNum(r['quantity']), 3)} ${r['unitOfMeasure'] ?? ''}'.trim(),
                  if (toNum(r['costLayers']) > 0) '${toNum(r['costLayers'])} cost layer${toNum(r['costLayers']) == 1 ? '' : 's'}',
                ].join(' · '),
              ),
        ];
      case 'depreciation':
        return [
          for (final r in rows(await _client.get('/api/Poultry/profit-loss/depreciation', query: q)))
            if (r is Map)
              (
                left: _day(r['periodStart']).length >= 7 ? _day(r['periodStart']).substring(0, 7) : '—',
                mid: '${r['assetName'] ?? '—'}',
                right: '${r['categoryName'] ?? '—'}',
                amount: toNum(r['amount']),
                note: [
                  if (r['originalCost'] != null) 'Cost ${_gh(toNum(r['originalCost']))}',
                  if (r['bookValueAfter'] != null) 'Book value ${_gh(toNum(r['bookValueAfter']))}',
                  if (r['sourceType'] != null && r['sourceType'] != 'Scheduled') '${r['sourceType']}',
                ].join(' · '),
              ),
        ];
      case 'financing':
        return [
          for (final r in rows(await _client.get('/api/Poultry/profit-loss/financing', query: {...q, 'lineKey': key})))
            if (r is Map)
              (
                left: _day(r['entryDate']),
                mid: '${r['description'] ?? '—'}',
                right: '${r['party'] ?? '—'}',
                amount: toNum(r['amount']),
                note: r['reference'] == null ? null : '${r['reference']}',
              ),
        ];
      case 'capital':
        return [
          for (final r in rows(await _client.get('/api/Poultry/profit-loss/capital-investments', query: q)))
            if (r is Map && '${r['categoryName'] ?? 'Other Assets'}' == key)
              (
                left: _day(r['costDate']),
                mid: '${r['assetName'] ?? '—'}',
                right: '${r['description'] ?? r['costCategory'] ?? '—'}',
                amount: toNum(r['amount']),
                note: 'Book value now ${_gh(toNum(r['currentBookValue']))}',
              ),
        ];
      default:
        return [
          for (final r in rows(await _client.get('/api/Poultry/profit-loss/expenses', query: {...q, 'lineKey': key})))
            if (r is Map)
              (
                left: _day(r['expenseDate']),
                mid: '${r['description'] ?? r['category'] ?? '—'}',
                right: '${r['supplierName'] ?? r['sourceLabel'] ?? '—'}',
                amount: toNum(r['amount']),
                note: r['isLegacy'] == true ? 'Placed by category (legacy record)' : null,
              ),
        ];
    }
  }

  void _openDrill(Map line) {
    final kind = drilldownKindFor('${line['section']}', '${line['lineKey']}');
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _DrilldownPage(
        line: line,
        kind: kind,
        load: () => _drillRows(line, kind),
        gh: _gh,
        period: '${drillDate(_filter.fromDate)} – ${drillDate(_filter.toDate)}',
      ),
    ));
  }

  // ---------------------------------------------------------------- export

  ReportDocument? _document() {
    final d = _data;
    if (d == null) return null;
    final rows = <List<String>>[];
    void push(String label, num? amount, [String kind = '']) =>
        rows.add([kind, label, amount == null ? '' : fixed2(amount)]);
    push('REVENUE', null, 'Section');
    for (final l in _section('Revenue')) {
      push('${l['lineLabel']}', toNum(l['amount']));
    }
    push('Total Revenue', _n('totalRevenue'), 'Total');
    push('DIRECT PRODUCTION COSTS', null, 'Section');
    for (final l in _section('DirectCost')) {
      push('${l['lineLabel']}', toNum(l['amount']));
    }
    push('Total Direct Production Costs', _n('totalDirectCosts'), 'Total');
    push('GROSS PROFIT', _n('grossProfit'), 'Result');
    push('OPERATING EXPENSES', null, 'Section');
    for (final l in _section('OperatingExpense')) {
      push('${l['lineLabel']}', toNum(l['amount']));
    }
    push('Total Operating Expenses', _n('totalOperatingExpenses'), 'Total');
    push('OPERATING PROFIT', _n('operatingProfit'), 'Result');
    push('DEPRECIATION & FINANCING', null, 'Section');
    for (final l in _section('OtherCost')) {
      push('${l['lineLabel']}', toNum(l['amount']));
    }
    push('Total Depreciation & Financing', _n('totalOtherCosts'), 'Total');
    push('NET PROFIT', _n('netProfit'), 'Result');
    push('FINANCING & OWNER ACTIVITY (excluded from profit)', null, 'Excluded');
    for (final l in _section('Financing')) {
      push('${l['lineLabel']}', toNum(l['amount']), 'Excluded');
    }
    push('CAPITAL INVESTMENTS (excluded from profit)', null, 'Excluded');
    for (final l in _section('CapitalInvestment')) {
      push('${l['lineLabel']}', toNum(l['amount']), 'Excluded');
    }
    push('Total Capital Investments', _n('totalCapitalInvestments'), 'Excluded');
    final overrides = d['hasItemOverrides'] == true;
    return ReportDocument(
      title: 'Profit & Loss',
      filename: 'poultry-profit-loss',
      farmName: widget.company.name,
      fromDate: _filter.fromDate,
      toDate: _filter.toDate,
      generatedBy: reportUser(widget.session),
      currencyLabel: _money.label,
      landscape: false,
      subtitle: 'Cost recognition — Feed: ${recognitionSummaryLine(d['feedRecognitionMethod'], overrides)}; '
          'Medication: ${recognitionSummaryLine(d['medicationRecognitionMethod'], overrides)}; Capital assets: depreciation',
      cards: [
        (label: 'Total Revenue', value: _gh(_n('totalRevenue')), accent: null, note: null),
        (label: 'Gross Profit', value: _gh(_n('grossProfit')), accent: null, note: null),
        (label: 'Operating Profit', value: _gh(_n('operatingProfit')), accent: null, note: null),
        (label: 'Net Profit', value: _gh(_n('netProfit')), accent: null, note: null),
      ],
      notes: const [plMethodNote],
      sections: [
        ReportSection(
          columns: const [ReportColumn('Kind'), ReportColumn('Line'), ReportColumn('Amount', right: true)],
          rows: rows,
        ),
      ],
    );
  }

  /// The web's P&L CSV: Kind, Line, Amount, every cell quoted, no preamble.
  Future<void> _csv() async {
    final d = _document();
    if (d == null) return;
    final csv = [
      ['Kind', 'Line', 'Amount'],
      ...d.sections.first.rows,
    ].map((r) => r.map((c) => '"$c"').join(',')).join('\n');
    await ReportExport.sharer('poultry-profit-loss.csv', utf8.encode(csv), 'text/csv', d.title);
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
      await ReportExport.email(_client, d, [to]);
      _toast('Report sent. $to');
    } on ApiException catch (e) {
      _toast('Could not send. ${e.message}');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _link(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  // ---------------------------------------------------------------- render

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry/reports/profit-loss');
    final d = _data;
    return Scaffold(
      backgroundColor: slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Profit & Loss')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
          children: [
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.spaceBetween, children: [
              AppButton(
                label: 'Poultry reports',
                icon: Icons.arrow_back,
                variant: AppButtonVariant.outline,
                size: AppButtonSize.sm,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PoultryReportsCatalogScreen(session: widget.session, company: widget.company),
                )),
              ),
              ReportExportButtons(onCsv: _csv, onEmail: _email, onPdf: _pdf, busy: _downloading, disabled: d == null),
            ]),
            const SizedBox(height: 12),
            ReportCard(children: [
              ReportLetterhead(
                farmName: widget.company.name.isEmpty ? 'Poultry farm' : widget.company.name,
                title: 'Profit & Loss',
                description: 'Did the business make money from its operations this period?',
                lines: [
                  ('Period', '${_filter.fromDate} → ${_filter.toDate}'),
                  ('Currency', _money.label),
                  ('Generated', _generatedAt),
                ],
              ),
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
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Loading…', style: TextStyle(fontSize: 13, color: slate500)),
                  ]),
                ),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    border: Border.all(color: const Color(0xFFFECACA)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B))),
                ),
              if (d != null && !_busy) ..._statement(d),
            ]),
          ],
        ),
      ),
    );
  }

  List<Widget> _statement(Map d) {
    final net = _n('netProfit');
    final overrides = d['hasItemOverrides'] == true;
    final legacy = legacyNote(_n('legacyExpenses'), _n('classifiedExpenses'));
    return [
      twoColumns([
        _Kpi(
          label: 'Total revenue',
          value: _gh(_n('totalRevenue')),
          tone: 'slate',
          term: 'Everything sold this period',
          tip: 'Eggs, birds, manure and feed sold in this period, whether or not the customer has paid yet. Money a customer still owes you is revenue; money they paid for a sale in an earlier period is not.',
          hint: const Text('Eggs, birds, manure and feed sold', style: TextStyle(fontSize: 11, color: slate500)),
        ),
        _Kpi(
          label: 'Total expenses',
          value: _gh(_totalExpenses),
          tone: 'red',
          term: 'Everything taken off revenue',
          tip: 'Every cost in this period: the direct cost of what you produced (feed, medication, birds, direct labour), the cost of running the business (payroll, utilities, transport, repairs, admin) and depreciation plus the interest and fees on borrowing. Revenue minus this figure is Net profit. It does NOT include owner draws, loan principal or capital purchases — those are money moving, not costs.',
          hint: _Formula(op: '+', money: _money, terms: [
            ('Direct costs', _n('totalDirectCosts'), _direct),
            ('Operating expenses', _n('totalOperatingExpenses'), _operating),
            ('Depreciation & financing', _n('totalOtherCosts'), _other),
          ]),
        ),
        _Kpi(
          label: 'Gross profit',
          value: _gh(_n('grossProfit')),
          tone: _n('grossProfit') >= 0 ? 'emerald' : 'red',
          term: d['grossMarginPercent'] != null ? '${d['grossMarginPercent']}% of sales' : 'No sales this period',
          tip: 'What the FARMING made, before any of the cost of running a business. Revenue minus the direct cost of producing what you sold: feed, medication, the birds themselves and direct labour. Negative here means the flock cost more to feed than its output sold for.',
          hint: _Formula(op: '−', money: _money, terms: [
            ('Revenue', _n('totalRevenue'), _revenue),
            ('Direct costs', _n('totalDirectCosts'), _direct),
          ]),
        ),
        _Kpi(
          label: 'Operating profit',
          value: _gh(_n('operatingProfit')),
          tone: _n('operatingProfit') >= 0 ? 'emerald' : 'red',
          term: 'Before depreciation and financing',
          tip: 'What the BUSINESS made. Gross profit minus the cost of running it: payroll, utilities, transport, repairs, admin and marketing. It stops short of wear on assets and the cost of borrowing, so it answers whether the operation itself pays for itself.',
          hint: _Formula(op: '−', money: _money, terms: [
            ('Gross profit', _n('grossProfit'), _subtotal),
            ('Operating expenses', _n('totalOperatingExpenses'), _operating),
          ]),
        ),
        _Kpi(
          label: net < 0 ? 'Net loss' : 'Net profit',
          value: _gh(net),
          tone: net > 0 ? 'emerald' : net < 0 ? 'red' : 'slate',
          strong: true,
          term: d['netMarginPercent'] != null ? '${d['netMarginPercent']}% of sales' : '${d['status'] ?? ''}',
          tip: 'What is actually left. Operating profit minus depreciation — the wear on buildings, machines and equipment — and the interest and fees on borrowing. Owner money, loan principal and capital purchases are NOT in this figure; they are money moving, not profit, and they are shown separately below.',
          hint: _Formula(op: '−', money: _money, terms: [
            ('Operating profit', _n('operatingProfit'), _subtotal),
            ('Depreciation & financing', _n('totalOtherCosts'), _other),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      // How the costs were recognised.
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(10)),
        child: Wrap(spacing: 16, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('COST RECOGNITION', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .5, color: slate500)),
          _kv('Feed:', recognitionSummaryLine(d['feedRecognitionMethod'], overrides)),
          _kv('Medication:', recognitionSummaryLine(d['medicationRecognitionMethod'], overrides)),
          _kv('Capital assets:', 'Depreciation'),
          if (overrides)
            Tooltip(
              message: itemOverrideTooltip,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(border: Border.all(color: const Color(0xFF6EE7B7)), borderRadius: BorderRadius.circular(6)),
                child: const Text('Some item overrides active', style: TextStyle(fontSize: 10.5, color: emerald700)),
              ),
            ),
          InkWell(
            onTap: () => _link('/poultry-financial-settings', 'Financial Settings'),
            child: const Text('Settings', style: TextStyle(fontSize: 12, color: Color(0xFF0369A1), decoration: TextDecoration.underline)),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      _SectionCard(title: 'Revenue', tone: 'emerald', lines: _section('Revenue'), totalLabel: 'Total Revenue', total: _n('totalRevenue'), onOpen: _openDrill, gh: _gh),
      _SectionCard(
          title: 'Direct Production Costs', tone: 'rose', negative: true, lines: _section('DirectCost'), totalLabel: 'Total Direct Production Costs', total: _n('totalDirectCosts'), onOpen: _openDrill, gh: _gh),
      _SectionCard(
          title: 'Operating Expenses', tone: 'amber', negative: true, lines: _section('OperatingExpense'), totalLabel: 'Total Operating Expenses', total: _n('totalOperatingExpenses'), onOpen: _openDrill, gh: _gh),
      _SectionCard(
          title: 'Depreciation & Financing Costs', tone: 'violet', negative: true, lines: _section('OtherCost'), totalLabel: 'Total Depreciation & Financing', total: _n('totalOtherCosts'), onOpen: _openDrill, gh: _gh),
      _InfoSection(
        icon: Icons.payments_outlined,
        title: 'Owner Contributions & Draws',
        subtitle: 'Excluded from profit',
        note: ownerSectionNote,
        rule: ownerSectionRule,
        lines: _ownerLines,
        onOpen: _openDrill,
        gh: _gh,
        footer: ('Net owner funding', _gh(_n('netOwnerFunding'))),
        links: [('/poultry-owner-money', 'View Owner Money'), ('/cash-flow', 'View Cash Flow')],
        onLink: _link,
      ),
      _InfoSection(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Loans (Financing)',
        subtitle: 'Excluded from profit',
        note: borrowingSectionNote,
        rule: borrowingSectionRule,
        lines: _borrowingLines,
        onOpen: _openDrill,
        gh: _gh,
        footer: ('Net borrowing', _gh(_n('netBorrowing'))),
        links: [('/poultry-loans', 'View Loans'), ('/cash-flow', 'View Cash Flow')],
        onLink: _link,
      ),
      _InfoSection(
        icon: Icons.business_outlined,
        title: 'Capital Investments',
        subtitle: 'Excluded from immediate operating expenses',
        note: capitalSectionNote,
        rule: capitalSectionRule,
        lines: _section('CapitalInvestment'),
        onOpen: _openDrill,
        gh: _gh,
        footer: ('Total capital investments', _gh(_n('totalCapitalInvestments'))),
        links: [('/poultry-assets', 'View Capital Investments/Assets')],
        onLink: _link,
      ),
      // Why the two numbers differ.
      Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFF0F9FF), border: Border.all(color: const Color(0xFFBAE6FD)), borderRadius: BorderRadius.circular(10)),
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 12, color: Color(0xFF0C4A6E)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 16, color: Color(0xFF0369A1)),
              SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(profitVsCashTitle, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text(profitVsCashBody),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            const Text("Cash out that is not this period's cost", style: TextStyle(fontWeight: FontWeight.w500)),
            for (final x in cashNotProfitExamples) Text('•  $x'),
            const SizedBox(height: 8),
            const Text('Costs that did not move cash this period', style: TextStyle(fontWeight: FontWeight.w500)),
            for (final x in profitNotCashExamples) Text('•  $x'),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _link('/cash-flow', 'Cash Flow'),
              child: const Text('View Cash Flow', style: TextStyle(decoration: TextDecoration.underline)),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      const Text(plMethodNote, style: TextStyle(fontSize: 11, color: slate500)),
      if (legacy != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_rounded, size: 14, color: amber700),
            const SizedBox(width: 6),
            Expanded(child: Text(legacy, style: const TextStyle(fontSize: 11, color: amber700))),
          ]),
        ),
    ];
  }

  Widget _kv(String k, String v) => Text.rich(TextSpan(style: const TextStyle(fontSize: 12), children: [
        TextSpan(text: '$k ', style: const TextStyle(color: slate500)),
        TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w500)),
      ]));
}

// ---------------------------------------------------------------- pieces

// FORMULA_TONES: each term wears the colour of the card that holds it.
const _revenue = Color(0xFF047857);
const _direct = Color(0xFFBE123C);
const _operating = Color(0xFFB45309);
const _other = Color(0xFF6D28D9);
const _subtotal = Color(0xFF334155);

/// A tile's arithmetic, names over numbers; a negative term is bracketed.
class _Formula extends StatelessWidget {
  const _Formula({required this.op, required this.terms, required this.money});
  final String op;
  final List<(String, num, Color)> terms;
  final FarmMoney money;

  @override
  Widget build(BuildContext context) {
    String amount(num n) {
      final t = money(n, withSymbol: false);
      return n < 0 ? '($t)' : t;
    }

    TextSpan row(String Function((String, num, Color)) cell, {bool bold = false}) => TextSpan(children: [
          for (final (i, t) in terms.indexed) ...[
            if (i > 0) TextSpan(text: ' $op ', style: const TextStyle(color: slate400)),
            TextSpan(text: cell(t), style: TextStyle(color: t.$3, fontWeight: bold ? FontWeight.w500 : FontWeight.w400)),
          ],
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(row((t) => t.$1), style: const TextStyle(fontSize: 11, height: 1.3)),
      Text.rich(row((t) => amount(t.$2), bold: true), style: const TextStyle(fontSize: 11, height: 1.3)),
    ]);
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.tone, this.term, this.tip, this.hint, this.strong = false});
  final String label;
  final String value;
  final String tone;
  final String? term;
  final String? tip;
  final Widget? hint;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final ring = tone == 'emerald' ? const Color(0xFFA7F3D0) : tone == 'red' ? const Color(0xFFFECACA) : slate200;
    final text = tone == 'emerald' ? emerald700 : tone == 'red' ? const Color(0xFFB91C1C) : slate900;
    // The meaning is a tooltip on the web; on a phone it is a tap.
    return InkWell(
      onTap: tip == null
          ? null
          : () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(label),
                  content: Text(tip!, style: const TextStyle(fontSize: 13)),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                ),
              ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: strong ? slate300 : ring, width: strong ? 1.5 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: .4,
                color: slate500,
                decoration: tip != null ? TextDecoration.underline : null,
                decorationStyle: TextDecorationStyle.dotted,
              )),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: text)),
          if (hint != null) Padding(padding: const EdgeInsets.only(top: 2), child: hint!),
          if (term != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(term!, style: const TextStyle(fontSize: 10, color: slate400))),
        ]),
      ),
    );
  }
}

const _sectionTones = {
  'emerald': (head: Color(0xFFECFDF5), headText: Color(0xFF065F46), total: Color(0x99ECFDF5), border: Color(0xFFA7F3D0)),
  'rose': (head: Color(0xFFFFF1F2), headText: Color(0xFF9F1239), total: Color(0x99FFF1F2), border: Color(0xFFFECDD3)),
  'amber': (head: Color(0xFFFFFBEB), headText: Color(0xFF92400E), total: Color(0x99FFFBEB), border: Color(0xFFFDE68A)),
  'violet': (head: Color(0xFFF5F3FF), headText: Color(0xFF5B21B6), total: Color(0x99F5F3FF), border: Color(0xFFDDD6FE)),
};

/// One band of the statement; costs print in brackets. Every line opens the
/// records behind it.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.tone,
    required this.lines,
    required this.totalLabel,
    required this.total,
    required this.onOpen,
    required this.gh,
    this.negative = false,
  });
  final String title;
  final String tone;
  final List<Map> lines;
  final String totalLabel;
  final num total;
  final void Function(Map) onOpen;
  final String Function(num?) gh;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final t = _sectionTones[tone]!;
    String money(num n) => negative ? '(${gh(n)})' : gh(n);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: t.border), borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: t.head,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(title.toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .5, color: t.headText)),
        ),
        if (lines.isEmpty)
          const Padding(padding: EdgeInsets.all(14), child: Text('None this period', style: TextStyle(fontSize: 13, color: slate400)))
        else
          for (final (i, l) in lines.indexed)
            InkWell(
              onTap: () => onOpen(l),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: slate100))),
                child: Row(children: [
                  Expanded(
                    child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 2, children: [
                      Text('${l['lineLabel']}', style: const TextStyle(fontSize: 14, color: slate900)),
                      const Icon(Icons.chevron_right, size: 15, color: slate400),
                      if (toNum(l['entryCount']) > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: slate100, borderRadius: BorderRadius.circular(99)),
                          child: Text('${toNum(l['entryCount'])} ${toNum(l['entryCount']) == 1 ? 'entry' : 'entries'}',
                              style: const TextStyle(fontSize: 11, color: slate500)),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Text(money(toNum(l['amount'])), style: const TextStyle(fontSize: 14, color: slate900)),
                ]),
              ),
            ),
        Container(
          decoration: BoxDecoration(color: t.total, border: Border(top: BorderSide(color: t.border))),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Expanded(child: Text(totalLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: slate900))),
            Text(money(total), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: slate900)),
          ]),
        ),
      ]),
    );
  }
}

/// PlInfoSection: dashed, "Excluded from profit", with the rule highlighted
/// in sky and links to where the money lives.
class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.note,
    required this.rule,
    required this.lines,
    required this.onOpen,
    required this.gh,
    required this.footer,
    required this.links,
    required this.onLink,
  });
  final IconData icon;
  final String title, subtitle, note, rule;
  final List<Map> lines;
  final void Function(Map) onOpen;
  final String Function(num?) gh;
  final (String, String) footer;
  final List<(String, String)> links;
  final void Function(String href, String label) onLink;

  @override
  Widget build(BuildContext context) {
    final at = note.indexOf(rule);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: slate300, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(10),
      ),
      foregroundDecoration: const _DashedBorder(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: slate500)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: slate900)),
              Text(subtitle.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .4, color: amber700)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Text.rich(
          at < 0
              ? TextSpan(text: note)
              : TextSpan(children: [
                  TextSpan(text: note.substring(0, at)),
                  TextSpan(
                    text: rule,
                    style: const TextStyle(backgroundColor: Color(0xFFE0F2FE), color: Color(0xFF0C4A6E), fontWeight: FontWeight.w500),
                  ),
                  TextSpan(text: note.substring(at + rule.length)),
                ]),
          style: const TextStyle(fontSize: 12, color: slate600),
        ),
        const SizedBox(height: 8),
        if (lines.isEmpty)
          const Text('None this period.', style: TextStyle(fontSize: 13, color: slate400))
        else
          for (final l in lines)
            InkWell(
              onTap: () => onOpen(l),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(
                    child: Row(children: [
                      Flexible(child: Text('${l['lineLabel']}', style: const TextStyle(fontSize: 14))),
                      const Icon(Icons.chevron_right, size: 15, color: slate400),
                    ]),
                  ),
                  Text(gh(toNum(l['amount'])), style: const TextStyle(fontSize: 14)),
                ]),
              ),
            ),
        const SizedBox(height: 6),
        Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: slate600), children: [
          TextSpan(text: '${footer.$1} '),
          TextSpan(text: footer.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
        ])),
        const SizedBox(height: 6),
        Wrap(spacing: 12, runSpacing: 4, children: [
          for (final (href, label) in links)
            InkWell(
              onTap: () => onLink(href, label),
              child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF0369A1), decoration: TextDecoration.underline)),
            ),
        ]),
      ]),
    );
  }
}

/// The informational cards' dashed outline.
class _DashedBorder extends Decoration {
  const _DashedBorder();
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _DashedPainter();
}

class _DashedPainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final rect = RRect.fromRectAndRadius(offset & size, const Radius.circular(10));
    final paint = Paint()
      ..color = slate300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }
}

/// The drilldown, full screen on a phone: the section's colour band, a filter
/// over every column, one record per block, and a total that says when it is
/// filtered.
class _DrilldownPage extends StatefulWidget {
  const _DrilldownPage({required this.line, required this.kind, required this.load, required this.gh, required this.period});
  final Map line;
  final String kind;
  final Future<List<DrillRow>> Function() load;
  final String Function(num?) gh;
  final String period;

  @override
  State<_DrilldownPage> createState() => _DrilldownPageState();
}

class _DrilldownPageState extends State<_DrilldownPage> {
  List<DrillRow>? _rows;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.load().then((r) {
      if (mounted) setState(() => _rows = r);
    }).catchError((Object e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the details. ${e is ApiException ? e.message : e}')));
      Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = drillTones[widget.kind]!;
    final cols = drillColumns[widget.kind]!;
    final all = _rows;
    final q = _q.text.trim().toLowerCase();
    final shown = all == null || q.isEmpty
        ? all
        : [for (final r in all) if ([r.left, r.mid, r.right, r.note].any((v) => (v ?? '').toLowerCase().contains(q))) r];
    final filtered = q.isNotEmpty;
    num sum(List<DrillRow>? l) => (l ?? const []).fold<num>(0, (s, r) => s + r.amount);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: tone.band,
        foregroundColor: tone.bandText,
        title: Text('${widget.line['lineLabel']}', overflow: TextOverflow.ellipsis),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: tone.band,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .6),
                  border: Border.all(color: tone.amount.withValues(alpha: .3)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(tone.label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: tone.amount)),
              ),
              const Spacer(),
              Text(widget.gh(toNum(widget.line['amount'])),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tone.amount)),
            ]),
            const SizedBox(height: 4),
            Text('${cols.blurb} ${widget.period}', style: TextStyle(fontSize: 12, color: tone.bandText.withValues(alpha: .8))),
          ]),
        ),
        Divider(height: 1, color: tone.border),
        Expanded(
          child: all == null
              ? const Center(child: CircularProgressIndicator())
              : all.isEmpty
                  ? const Center(
                      child: Text('Nothing behind this figure in the selected period.', style: TextStyle(fontSize: 13, color: slate500)))
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: AppInput(
                          controller: _q,
                          hintText: 'Filter these ${all.length} records…',
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      if (filtered && shown!.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('Nothing here matches “${_q.text.trim()}”.',
                              textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: slate500)),
                        ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          itemCount: shown!.length,
                          separatorBuilder: (_, _) => Divider(height: 1, color: tone.border),
                          itemBuilder: (_, i) {
                            final r = shown[i];
                            return Container(
                              padding: const EdgeInsets.fromLTRB(10, 12, 0, 12),
                              decoration: BoxDecoration(border: Border(left: BorderSide(color: tone.rail, width: 2))),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(drillDate(r.left).toUpperCase(),
                                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, letterSpacing: .4, color: slate500)),
                                  ),
                                  Text(widget.gh(r.amount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tone.amount)),
                                ]),
                                if ((r.mid ?? '').isNotEmpty)
                                  Padding(padding: const EdgeInsets.only(top: 4), child: Text(r.mid!, style: const TextStyle(fontSize: 14, color: slate900))),
                                if ((r.note ?? '').isNotEmpty) Text(r.note!, style: const TextStyle(fontSize: 11, color: slate500)),
                                if ((r.right ?? '').isNotEmpty && r.right != '—')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: slate500), children: [
                                      TextSpan(text: '${cols.right}: ', style: const TextStyle(color: slate400)),
                                      TextSpan(text: r.right),
                                    ])),
                                  ),
                              ]),
                            );
                          },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: tone.border))),
                        child: SafeArea(
                          top: false,
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: Text(
                                filtered ? '${shown.length} of ${all.length} records' : '${all.length} ${all.length == 1 ? 'record' : 'records'}',
                                style: const TextStyle(fontSize: 13, color: slate500),
                              ),
                            ),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(widget.gh(sum(shown)), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tone.amount)),
                              if (filtered)
                                Text('filtered · ${widget.gh(sum(all))} in full', style: const TextStyle(fontSize: 11, color: slate500)),
                            ]),
                          ]),
                        ),
                      ),
                    ]),
        ),
      ]),
    );
  }
}
