import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../design/ui/buttons.dart';
import '../../../design/ui/inputs.dart';
import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../../widgets/module_sidebar.dart';
import '../../lookup_loader.dart';
import '../../poultry/money/cash_flow_screen.dart' show withRunningBalance, cashFlowBuckets, previousRange;
import '../../poultry/reports/money_reports.dart';
import '../../poultry/reports/poultry_report_screen.dart' show generatedNow;
import '../../poultry/reports/profit_loss_screen.dart' show PlSectionCard, PlInfoCard;
import '../../poultry/reports/report_export.dart';
import '../../poultry/reports/report_format.dart';
import '../../poultry/reports/report_routes.dart' show openAppHref;
import '../../poultry/reports/report_shell.dart';
import '../../poultry/reports/report_widgets.dart';
import '../../shared/business_dates.dart';
import 'water_report_kit.dart';
import 'water_reports_catalog_screen.dart';

// Water → Reports: the pages that are more than one table — Cash Movement,
// Cash Flow Detail, Cash Account Report, Money Movement, Daily Business
// Summary, the Operational dashboard and Profit & Loss.

Widget _catalog(Session s, Company c) => WaterReportsCatalogScreen(session: s, company: c);

/// The Water rail of the shared Cash Account / Money Movement reports.
const waterMoneyRail = MoneyRail(
  api: '/api/Water',
  idPrefix: 'water',
  cashAccountsHref: '/water-reports/cash-accounts',
  moneyHref: '/water-reports/money-movement',
  cashTitle: 'Water Cash Account Report',
  cashFilename: 'water-cash-accounts',
  cashFlowHref: '/water-cash-flow',
  reconcileHref: '/water-cash-reconciliation',
  entity: 'company',
  catalog: _catalog,
);

Widget waterCashAccountsReport(Session s, Company c) => CashAccountReportScreen(session: s, company: c, rail: waterMoneyRail);

Widget waterMoneyMovementReport(Session s, Company c) => MoneyMovementScreen(session: s, company: c, rail: waterMoneyRail);

// =========================================================================
// Cash Movement and Cash Flow Detail (GET /api/Water/cash-flow)
// =========================================================================

/// The document behind a row, so a figure can be traced back to what caused it.
String _reference(Map r) {
  if (r['sourceId'] == null) return '—';
  final id = wstr(r['sourceId']);
  return switch ('${r['rowSource'] ?? ''}') {
    'Receipt' => 'Payment · sale #$id',
    'SaleResidual' => 'Sale #$id',
    'Expense' => 'Expense #$id',
    'Adjustment' => 'Adjustment #$id',
    _ => '#$id',
  };
}

const _cashNote = 'These figures come from sales, payments, approved expenses and capital records, not from cash '
    'account balances. Closing cash is not expected to match what the accounts hold — comparing '
    'the two is what reconciliation is for.';

Future<(Map, List<Map>)> _cashFlow(Session s, Company c, String from, String to) async {
  final raw = await s.farmClient.get('/api/Water/cash-flow', query: {'farmId': c.farmId, 'fromDate': from, 'toDate': to});
  final summary = raw is Map && raw['summary'] is Map ? Map.of(raw['summary'] as Map) : <String, dynamic>{};
  final rows = [
    for (final r in (raw is Map && raw['rows'] is List ? raw['rows'] as List : const []))
      if (r is Map) {...r, 'category': r['category'] ?? 'Other'},
  ];
  return (summary, rows);
}

class WaterCashMovementScreen extends StatefulWidget {
  const WaterCashMovementScreen({super.key, required this.session, required this.company, this.detail = false});
  final Session session;
  final Company company;

  /// Cash Flow Detail rather than Cash Movement.
  final bool detail;

  @override
  State<WaterCashMovementScreen> createState() => _WaterCashMovementScreenState();
}

class _WaterCashMovementScreenState extends State<WaterCashMovementScreen> {
  late String _from = defaultReportRange().from, _to = defaultReportRange().to;
  Map _summary = const {};
  Map _prev = const {};
  List<Map> _rows = const [];
  bool _busy = true;
  String? _error;
  FarmMoney _money = const FarmMoney();
  int _seq = 0;

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
      final cur = await _cashFlow(widget.session, widget.company, _from, _to);
      Map prev = const {};
      if (widget.detail) {
        // A missing comparison period is a degraded report, not a failed one.
        final p = previousRange(_from, _to);
        if (p.from != null && p.to != null) {
          try {
            prev = (await _cashFlow(widget.session, widget.company, p.from!, p.to!)).$1;
          } catch (_) {}
        }
      }
      if (!mounted || seq != _seq) return;
      setState(() {
        _summary = cur.$1;
        _rows = cur.$2;
        _prev = prev;
      });
    } on ApiException catch (e) {
      if (mounted && seq == _seq) {
        setState(() {
          _error = e.message;
          _rows = const [];
          _summary = const {};
        });
      }
    } finally {
      if (mounted && seq == _seq) setState(() => _busy = false);
    }
  }

  num _s(String k) => toNum(_summary[k]);

  @override
  Widget build(BuildContext context) {
    final m = _money;
    // Newest first; the running balance travels with its row.
    final visible = withRunningBalance(_rows, _s('openingCash')).reversed.toList();
    String inCell(Map r) => toNum(r['amount']) > 0 ? m(toNum(r['amount'])) : '—';
    String outCell(Map r) => toNum(r['amount']) < 0 ? m(-toNum(r['amount'])) : '—';
    final detail = widget.detail;
    final columns = detail
        ? [col('Date'), col('Type'), col('Category'), col('Reference'), col('Description'), rcol('In'), rcol('Out'), rcol('Running cash')]
        : [
            col('Date'), col('Type'), col('Category'), col('Source'), col('Reference'), col('Description'),
            rcol('Inflow'), rcol('Outflow'), rcol('Balance'),
          ];
    final rows = [
      for (final r in visible)
        [
          wday(r['transactionDate']),
          flowGroupLabel(r['flowGroup']),
          categoryLabel(r['category']),
          if (!detail) '${r['sourceType'] ?? ''}'.isEmpty ? '—' : '${r['sourceType']}',
          _reference(r),
          wdash(r['description']),
          inCell(r),
          outCell(r),
          m(toNum(r['running'])),
        ],
    ];
    final net = _s('netCashFlow');
    final fromTrading = ((_s('operatingIn') - _s('operatingOut')) * 100).round() / 100;
    final tiles = detail
        ? [
            tile('Opening cash', m(_s('openingCash'))),
            tile('Money in', m(_s('moneyIn')), 'green'),
            tile('Money out', m(_s('moneyOut')), 'rose'),
            tile('Closing cash', m(_s('closingCash')), 'indigo'),
            tile('From trading', m(fromTrading), fromTrading >= 0 ? 'green' : 'rose'),
          ]
        : [
            tile('Opening cash balance', m(_s('openingCash'))),
            tile('Total inflows', m(_s('moneyIn')), 'green'),
            tile('Total outflows', m(_s('moneyOut')), 'rose'),
            tile('Net cash movement', m(net), net >= 0 ? 'green' : 'rose'),
            tile('Closing cash', m(_s('closingCash')), 'indigo'),
          ];
    final pdfCards = detail
        ? <ReportCardOut>[
            (label: 'Opening cash', value: m(_s('openingCash')), accent: null, note: 'Start of period'),
            (label: 'Money in', value: m(_s('moneyIn')), accent: 'green', note: null),
            (label: 'Money out', value: m(_s('moneyOut')), accent: 'rose', note: null),
            (label: 'Closing cash', value: m(_s('closingCash')), accent: null, note: 'Not your account balances'),
            (
              label: 'From trading',
              value: m(fromTrading),
              accent: fromTrading >= 0 ? 'green' : 'rose',
              note: 'Operating only, excludes capital',
            ),
          ]
        : <ReportCardOut>[
            (label: 'Opening cash balance', value: m(_s('openingCash')), accent: null, note: null),
            (label: 'Total inflows', value: m(_s('moneyIn')), accent: 'green', note: null),
            (label: 'Total outflows', value: m(_s('moneyOut')), accent: 'rose', note: null),
            (label: 'Net cash movement', value: m(net), accent: net >= 0 ? 'green' : 'rose', note: null),
            (label: 'Closing cash', value: m(_s('closingCash')), accent: null, note: 'Not your account balances'),
          ];

    final ins = cashFlowBuckets(_rows, true), outs = cashFlowBuckets(_rows, false);
    final analysis = detail
        ? buildCashFlowAnalysis({
            ..._summary,
            'cashAtHand': _summary['closingCash'],
            'offLedgerIn': 0,
            'offLedgerOut': 0,
            'transferVolume': 0,
            'daysInPeriod': previousRange(_from, _to).days,
            'previousMoneyIn': _prev['moneyIn'] ?? 0,
            'previousMoneyOut': _prev['moneyOut'] ?? 0,
            'previousNetCashFlow': _prev['netCashFlow'] ?? 0,
            'moneyInByCategory': [for (final b in ins) {'label': b.label, 'amount': b.amount, 'sharePercent': b.percent}],
            'moneyOutByCategory': [for (final b in outs) {'label': b.label, 'amount': b.amount, 'sharePercent': b.percent}],
          }, m.call)
        : const <AnalysisItem>[];

    return ReportShellScreen(
      session: widget.session,
      company: widget.company,
      href: detail ? '/water-reports/cash-flow-detail' : '/water-reports/cash-movement',
      catalog: _catalog,
      title: detail ? 'Cash Flow Detail' : 'Cash Movement',
      description: detail
          ? 'Where cash came from, what it went on, and how the period compares with the one before it.'
          : 'Every movement of cash in the period, oldest balance forward. Built from sales, customer payments, approved expenses and capital — not from cash account balances.',
      busy: _busy,
      error: _error,
      onClearError: () => setState(() => _error = null),
      fromDate: _from,
      toDate: _to,
      onRangeChanged: (f, t) {
        setState(() {
          _from = f;
          _to = t;
        });
        _load();
      },
      tiles: tiles,
      recordCount: rows.length,
      onRefresh: _load,
      document: () => ReportDocument(
        title: detail ? 'Water Cash Flow Detail' : 'Water Cash Movement Report',
        filename: detail ? 'water-cash-flow-detail' : 'water-cash-movement',
        farmName: widget.company.name,
        landscape: true,
        cards: pdfCards,
        sections: [ReportSection(columns: columns, rows: rows)],
      ),
      body: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: detail
              ? const Text.rich(TextSpan(style: TextStyle(fontSize: 12, color: slate500), children: [
                  TextSpan(text: '$_cashNote '),
                  TextSpan(text: 'From trading', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' excludes capital, so it is what the business itself earned rather than what owners and lenders put in.'),
                ]))
              : const Text(
                  '$_cashNote Transfers between your own accounts are excluded: they move money without the business earning or spending any.',
                  style: TextStyle(fontSize: 12, color: slate500),
                ),
        ),
        if (detail) ...[
          _BreakdownPanel(
            title: 'Money in by source',
            green: true,
            total: m(_s('moneyIn')),
            empty: 'No money came in during this period.',
            items: [for (final b in ins) (b.label, m(b.amount), b.percent)],
          ),
          const SizedBox(height: 12),
          _BreakdownPanel(
            title: 'Money out by category',
            green: false,
            total: m(_s('moneyOut')),
            empty: 'Nothing was paid out during this period.',
            items: [for (final b in outs) (b.label, m(b.amount), b.percent)],
          ),
          ReportAnalysis(title: 'Analysis', items: analysis),
          const ShellHeading('Every movement'),
        ],
        ShellCards(
          columns: columns,
          rows: rows,
          empty: 'No cash moved in this period.',
          valueColor: (ri, ci) {
            final inCol = detail ? 5 : 6;
            if (ci == inCol && rows[ri][ci] != '—') return emerald700;
            if (ci == inCol + 1 && rows[ri][ci] != '—') return rose700;
            return null;
          },
        ),
      ],
    );
  }
}

/// CashBreakdownPanel: title and total, then one bar per bucket.
class _BreakdownPanel extends StatelessWidget {
  const _BreakdownPanel({required this.title, required this.green, required this.total, required this.empty, required this.items});
  final String title;
  final bool green;
  final String total;
  final String empty;
  final List<(String, String, num)> items;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(border: Border.all(color: slate200), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: slate800))),
            Text(total, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: slate900)),
          ]),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(empty, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: slate500)),
            )
          else
            for (final (label, value, pct) in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: slate600)),
                    ),
                    Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: slate800), children: [
                      TextSpan(text: value),
                      TextSpan(text: ' (${pct.toStringAsFixed(1)}%)', style: const TextStyle(color: slate400)),
                    ])),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: pct.clamp(0, 100) / 100,
                      minHeight: 8,
                      color: green ? emerald500 : rose500,
                      backgroundColor: slate100,
                    ),
                  ),
                ]),
              ),
        ]),
      );
}

// =========================================================================
// Daily Business Summary — its own page, not the report shell
// =========================================================================

class WaterDailySummaryScreen extends StatefulWidget {
  const WaterDailySummaryScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterDailySummaryScreen> createState() => _WaterDailySummaryScreenState();
}

class _WaterDailySummaryScreenState extends State<WaterDailySummaryScreen> {
  String _date = isoDay(DateTime.now());
  bool _busy = false;
  Map<String, dynamic>? _s;
  FarmMoney _money = const FarmMoney();
  late final String _generated = generatedNow();

  WaterReportQuery get _q => WaterReportQuery(widget.session, widget.company, _date, _date, const {});

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final q = _q;
    final date = _date;
    bool onDate(Object? d) => '${d ?? ''}'.startsWith(date);
    try {
      final batches = await q.listOrEmpty('/api/Water/production-batches');
      final expenses = await q.listOrEmpty('/api/Water/expenses');
      final closings = await q.listOrEmpty('/api/Water/daily-closings');
      final losses = await q.listOrEmpty('/api/Water/production-losses', {'fromDate': date, 'toDate': date});
      final purchases = await q.listOrEmpty('/api/Water/raw-material-purchases');
      final returns = await q.listOrEmpty('/api/Water/driver-returns', {'fromDate': date, 'toDate': date});

      final day = batches.where((b) => onDate(b['productionDate']) && b['status'] == 'Approved');
      final good = day.fold<num>(0, (t, b) => t + (b['goodBags'] != null ? wn(b['goodBags']) : wn(b['bagsProduced']) - wn(b['damagedBags'])));
      final cost = day.fold<num>(
          0, (t, b) => t + (b['allInCost'] != null ? wn(b['allInCost']) : wn(b['totalProductionCost']) + wn(b['rawMaterialCost'])));
      final dayExpenses = expenses.where((e) => onDate(e['expenseDate']) && e['status'] == 'Approved');
      final byCat = <String, num>{};
      for (final e in dayExpenses) {
        final k = '${e['categoryName'] ?? 'Uncategorised'}';
        byCat[k] = (byCat[k] ?? 0) + wn(e['amount']);
      }
      final raw = purchases
          .where((p) => '${p['purchaseDate'] ?? ''}'.startsWith(date))
          .fold<num>(0, (t, p) => t + (p['totalCost'] != null ? wn(p['totalCost']) : wn(p['quantity']) * wn(p['unitCost'])));
      final closing = closings.where((c) => '${c['closingDate'] ?? ''}'.startsWith(date)).firstOrNull;
      final dayReturns = [
        for (final r in returns)
          if (onDate(r['returnDate']) && (r['status'] == 'Approved' || r['status'] == 'Draft')) r,
      ];
      num sumR(String k) => dayReturns.fold<num>(0, (t, r) => t + wn(r[k]));
      final income = closing != null
          ? {
              'total': wn(closing['totalIncome']),
              'cash': wn(closing['cashAtHand']) < 0 ? 0 : wn(closing['cashAtHand']),
              'moMo': wn(closing['moMoBalance']),
              'bank': wn(closing['bankBalance']),
              'creditSales': wn(closing['creditSales']),
              'customerCollections': wn(closing['customerCollections']),
              'bagsSold': wn(closing['bagsSold']),
              'driverShortages': wn(closing['driverShortagesTotal'] ?? closing['driverShortages']),
              'source': 'closing',
            }
          : dayReturns.isNotEmpty
              ? {
                  'total': sumR('cashCollected') + sumR('moMoCollected') + sumR('bankCollected') + sumR('creditSalesAmount'),
                  'cash': sumR('cashCollected'),
                  'moMo': sumR('moMoCollected'),
                  'bank': sumR('bankCollected'),
                  'creditSales': sumR('creditSalesAmount'),
                  'customerCollections': 0,
                  'bagsSold': sumR('bagsSold'),
                  'driverShortages': sumR('shortageAmount'),
                  'source': 'returns',
                }
              : {
                  'total': 0, 'cash': 0, 'moMo': 0, 'bank': 0, 'creditSales': 0,
                  'customerCollections': 0, 'bagsSold': 0, 'driverShortages': 0, 'source': 'none',
                };
      if (!mounted || date != _date) return;
      setState(() => _s = {
            'good': good,
            'cost': cost,
            'raw': raw,
            'expenses': dayExpenses.fold<num>(0, (t, e) => t + wn(e['amount'])),
            'byCat': byCat,
            'losses': losses.fold<num>(0, (t, l) => t + wn(l['totalValue'])),
            'closingStatus': closing?['status'],
            'income': income,
          });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load daily summary. $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<(String, String, String?)> _incomeCards(Map inc) {
    final m = _money;
    return [
      ('Total income', m(wn(inc['total'])), 'green'),
      ('Cash', m(wn(inc['cash'])), null),
      ('MoMo', m(wn(inc['moMo'])), null),
      ('Bank', m(wn(inc['bank'])), null),
      ('Credit sales', m(wn(inc['creditSales'])), null),
      ('Customer collections', m(wn(inc['customerCollections'])), null),
      ('Bags sold', wloc(inc['bagsSold']), null),
      ('Driver shortages', m(wn(inc['driverShortages'])), wn(inc['driverShortages']) != 0 ? 'rose' : null),
    ];
  }

  List<(String, String, String?)> _otherCards(Map s) {
    final m = _money;
    return [
      ('Good bags produced', wloc(s['good']), null),
      ('Production cost', m(wn(s['cost'])), null),
      ('Raw material purchases', m(wn(s['raw'])), null),
      ('Approved expenses', m(wn(s['expenses'])), null),
      ('Loss value', m(wn(s['losses'])), 'rose'),
      ('Closing status', '${s['closingStatus'] ?? 'Not closed'}', null),
    ];
  }

  Future<void> _pdf() async {
    final s = _s;
    if (s == null) return;
    final byCat = (s['byCat'] as Map<String, num>).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    await ReportExport.sharePdf(ReportDocument(
      title: 'Daily Business Summary',
      filename: 'water-daily-summary',
      farmName: widget.company.name,
      fromDate: _date,
      toDate: _date,
      currencyLabel: _money.label,
      cards: [
        for (final (l, v, a) in [..._incomeCards(s['income'] as Map), ..._otherCards(s)]) (label: l, value: v, accent: a, note: null),
      ],
      sections: [
        ReportSection(
          heading: 'Expense breakdown',
          columns: [col('Category'), rcol('Amount')],
          rows: [for (final e in byCat) [e.key, _money(e.value)]],
        ),
      ],
      notes: ['Generated from approved production, expense, loss and closing rows for $_date. Cash totals require a closing for the day.'],
    ));
  }

  Widget _card(String label, String value, String? accent) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10.5, letterSpacing: .5, color: slate500)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: accent == 'rose' ? rose700 : accent == 'green' ? emerald700 : slate900,
              )),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-reports/daily-summary');
    final s = _s;
    final m = _money;
    final meta = TextStyle(fontSize: 13, color: slate500.withValues(alpha: 1));
    Widget line(String k, String v) => Text.rich(TextSpan(style: meta, children: [
          TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          TextSpan(text: v),
        ]));
    return Scaffold(
      backgroundColor: slate50,
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Daily Business Summary')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.spaceBetween, children: [
            AppButton(
              label: 'Reports',
              icon: Icons.arrow_back,
              variant: AppButtonVariant.outline,
              size: AppButtonSize.sm,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _catalog(widget.session, widget.company))),
            ),
            AppButton(label: 'Export PDF', icon: Icons.print_outlined, size: AppButtonSize.sm, onPressed: s == null ? null : _pdf),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.only(bottom: 12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: slate200))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Daily Business Summary', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: slate900)),
                  const SizedBox(height: 4),
                  line('Company', widget.company.name.isEmpty ? '—' : widget.company.name),
                  line('Date', _date),
                  line('Currency', m.label),
                  line('Generated', _generated),
                ]),
              ),
              const Text('Date', style: TextStyle(fontSize: 12, color: slate600)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: AppDateField(
                    value: businessDateAsDateTime(_date),
                    firstDate: DateTime(2000),
                    onChanged: (d) {
                      if (d == null) return;
                      setState(() => _date = isoDay(d));
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(label: 'Refresh', variant: AppButtonVariant.outline, size: AppButtonSize.sm, onPressed: _busy ? null : _load),
              ]),
              const SizedBox(height: 14),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Row(children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Loading…', style: TextStyle(fontSize: 13, color: slate500)),
                  ]),
                )
              else if (s == null)
                const Text('No data for this date.', style: TextStyle(fontSize: 13, color: slate500))
              else ...[
                const ShellHeading('Income'),
                twoColumns([for (final (l, v, a) in _incomeCards(s['income'] as Map)) _card(l, v, a)]),
                const SizedBox(height: 8),
                Text(
                  switch ((s['income'] as Map)['source']) {
                    'closing' => "Income figures are taken from the day's closing (storefront + delivery sales combined).",
                    'returns' =>
                      "No closing for this day yet — income is computed from the day's driver returns. Create the closing for the full picture.",
                    _ => 'No sales, driver returns, or closing recorded for this date.',
                  },
                  style: const TextStyle(fontSize: 12, color: slate500),
                ),
                const SizedBox(height: 14),
                twoColumns([for (final (l, v, a) in _otherCards(s)) _card(l, v, a)]),
                const ShellHeading('Expense breakdown'),
                if ((s['byCat'] as Map).isEmpty)
                  const Text('No approved expenses on this date.', style: TextStyle(fontSize: 13, color: slate500))
                else
                  WaterMiniTable(
                    columns: [col('Category'), rcol('Amount')],
                    rows: [
                      for (final e in ((s['byCat'] as Map<String, num>).entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                        [e.key, m(e.value)],
                    ],
                  ),
                const Divider(height: 24, color: slate200),
                Text(
                  'Generated from approved production, expense, loss and closing rows for $_date. Cash totals require a closing for the day.',
                  style: const TextStyle(fontSize: 12, color: slate500),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// Operational dashboard ("Water reports") — its own page, four tabs
// =========================================================================

class WaterOperationalScreen extends StatefulWidget {
  const WaterOperationalScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  State<WaterOperationalScreen> createState() => _WaterOperationalScreenState();
}

class _WaterOperationalScreenState extends State<WaterOperationalScreen> {
  late String _from = defaultReportRange('last7').from, _to = defaultReportRange('last7').to;
  Map? _pnl;
  List<Map<String, dynamic>> _routes = const [], _drivers = const [], _variance = const [];
  bool _loading = true;
  FarmMoney _money = const FarmMoney();
  int _seq = 0;

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
    setState(() => _loading = true);
    final q = WaterReportQuery(widget.session, widget.company, _from, _to, const {});
    Object? err;
    Future<T?> settle<T>(Future<T> f) async {
      try {
        return await f;
      } catch (e) {
        err ??= e;
        return null;
      }
    }

    // Each report independent, so one failure does not blank the page.
    final pnl = await settle(q.get('/api/Water/reports/period-pnl', q.period));
    final routes = await settle(q.list('/api/Water/reports/route-profitability', q.period));
    final drivers = await settle(q.list('/api/Water/reports/driver-reconciliation', q.period));
    final variance = await settle(q.list('/api/Water/reports/raw-material-variance', q.period));
    if (!mounted || seq != _seq) return;
    setState(() {
      _pnl = pnl is Map ? pnl : null;
      _routes = routes ?? const [];
      _drivers = drivers ?? const [];
      _variance = variance ?? const [];
      _loading = false;
    });
    // Only when every report failed (an auth or backend problem).
    if (pnl == null && routes == null && drivers == null && variance == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not load reports. ${err is ApiException ? (err as ApiException).message : 'Reports could not be loaded'}')));
    }
  }

  void _range(int days) {
    setState(() {
      _from = isoDay(DateTime.now().subtract(Duration(days: days)));
      _to = isoDay(DateTime.now());
    });
    _load();
  }

  void _setRange(String f, String t) {
    setState(() {
      _from = f;
      _to = t;
    });
    _load();
  }

  Widget _stat(String label, String value, [String? accent]) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: slate500)),
          Text(value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: accent == 'green' ? const Color(0xFF15803D) : accent == 'rose' ? const Color(0xFFE11D48) : slate900,
              )),
        ]),
      );

  Widget _date(String label, String value, void Function(String) onPick) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: slate600)),
        const SizedBox(height: 4),
        AppDateField(
          value: businessDateAsDateTime(value),
          firstDate: DateTime(2000),
          onChanged: (d) {
            if (d != null) onPick(isoDay(d));
          },
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/water-reports/operational');
    final gh = _money;
    final p = _pnl;
    String day(Object? v) => '${v ?? ''}'.split('T').first;
    Widget tab(List<ReportColumn> cols, List<List<String>> rows, String empty) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
          children: [
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Text(empty, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: slate500)),
              )
            else
              ShellCards(columns: cols, rows: rows),
          ],
        );
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: slate50,
        appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Water reports')),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const Icon(Icons.bar_chart, color: Color(0xFF0284C7)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Water reports', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: slate900)),
                    ),
                    AppButton(
                      label: 'Refresh',
                      icon: Icons.refresh,
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.sm,
                      onPressed: _loading ? null : _load,
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: slate200), borderRadius: BorderRadius.circular(10)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('Period', style: TextStyle(fontSize: 12, color: slate600)),
                      const SizedBox(height: 4),
                      AppSelect<String>(
                        value: rangeToPeriod(_from, _to),
                        items: [
                          for (final (group, opts) in periodGroups)
                            for (final (k, l) in opts) AppSelectItem(value: k, label: '$l  ·  $group'),
                        ],
                        onChanged: (k) {
                          final r = k == null ? null : periodToRange(k);
                          if (r != null) _setRange(r.from, r.to);
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _date('From', _from, (v) => _setRange(v, _to))),
                        const SizedBox(width: 8),
                        Expanded(child: _date('To', _to, (v) => _setRange(_from, v))),
                      ]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: [
                        for (final d in [7, 30, 90])
                          AppButton(label: '${d}d', variant: AppButtonVariant.outline, size: AppButtonSize.sm, onPressed: () => _range(d)),
                        AppButton(label: 'Apply', size: AppButtonSize.sm, onPressed: _load),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  if (!_loading)
                    TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [
                        const Tab(text: 'Period P&L'),
                        Tab(text: 'Route profitability (${_routes.length})'),
                        Tab(text: 'Driver reconciliation (${_drivers.length})'),
                        Tab(text: 'Raw material variance (${_variance.length})'),
                      ],
                    ),
                ]),
              ),
            ),
          ],
          body: _loading
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Loading reports…', style: TextStyle(fontSize: 13, color: slate500)),
                  ]),
                )
              : TabBarView(children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
                    children: [
                      if (p == null)
                        const Padding(
                          padding: EdgeInsets.all(28),
                          child: Text('No P&L data for this period.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: slate500)),
                        )
                      else
                        twoColumns([
                          _stat('Period', '${day(p['periodStart'])} → ${day(p['periodEnd'])}'),
                          _stat('Bags produced', wstr(p['bagsProduced'] ?? 0)),
                          _stat('Bags sold', wstr(p['bagsSold'] ?? 0)),
                          _stat('Total income', gh(wn(p['totalIncome'])), 'green'),
                          _stat('Raw materials & supplies', gh(wn(p['rawMaterialCost'])), 'rose'),
                          _stat('Production cost', gh(wn(p['productionCost'])), 'rose'),
                          _stat('Total expenses', gh(wn(p['totalExpenses'])), 'rose'),
                          _stat('Net profit', gh(wn(p['netProfit'])), wn(p['netProfit']) >= 0 ? 'green' : 'rose'),
                          _stat('Profit margin', '${wn(p['profitMarginPct']).toStringAsFixed(1)}%',
                              wn(p['profitMarginPct']) >= 0 ? 'green' : 'rose'),
                          _stat('Avg profit per bag', gh(wn(p['avgProfitPerBag'])), wn(p['avgProfitPerBag']) >= 0 ? 'green' : 'rose'),
                        ]),
                    ],
                  ),
                  tab(
                    [col('Route'), rcol('Loaded'), rcol('Sold'), rcol('Revenue'), rcol('Shortages'), rcol('Net')],
                    [
                      for (final r in _routes)
                        [
                          '${r['routeName'] ?? ''}', wstr(r['totalBagsLoaded']), wstr(r['totalBagsSold']),
                          gh(wn(r['totalRevenue'])), gh(wn(r['totalShortages'])), gh(wn(r['netRouteIncome'])),
                        ],
                    ],
                    'No route data.',
                  ),
                  tab(
                    [col('Driver'), rcol('Loaded'), rcol('Sold'), rcol('Expected'), rcol('Accounted'), rcol('Shortages')],
                    [
                      for (final d in _drivers)
                        [
                          '${d['driverName'] ?? ''}', wstr(d['totalBagsLoaded']), wstr(d['totalBagsSold']),
                          gh(wn(d['expectedRevenue'])), gh(wn(d['actualAccountedFor'])), gh(wn(d['totalShortages'])),
                        ],
                    ],
                    'No driver data.',
                  ),
                  tab(
                    [col('Item'), col('Category'), rcol('Expected'), rcol('Actual'), rcol('Variance'), rcol('Usage count')],
                    [
                      for (final v in _variance)
                        [
                          '${v['itemName'] ?? ''}', '${v['category'] ?? ''}', wstr(v['totalExpected']),
                          wstr(v['totalActual']), wstr(v['totalVariance']), wstr(v['usageCount']),
                        ],
                    ],
                    'No usage data.',
                  ),
                ]),
        ),
      ),
    );
  }
}

// =========================================================================
// Profit & Loss (components/water-reports/water-profit-loss-view.tsx)
// =========================================================================

/// waterDrilldownKindFor.
String? waterDrillKind(String section, String lineKey) {
  if (section == 'Revenue') return 'revenue';
  if (section == 'DirectCost') return 'directcost';
  if (section == 'Loss') return 'loss';
  if (section == 'Financing') return 'financing';
  if (section == 'CapitalInvestment') return 'capital';
  if (lineKey == 'Depreciation') return 'depreciation';
  if (section == 'OperatingExpense' || section == 'OtherCost') return 'expense';
  return null;
}

/// waterPlSectionLabel.
String waterPlSectionLabel(String s) => switch (s) {
      'Revenue' => 'Revenue',
      'DirectCost' => 'Direct Costs',
      'OperatingExpense' => 'Operating Expenses',
      'OtherCost' => 'Other Costs',
      'Loss' => 'Losses',
      'Financing' => 'Financing & Owner Activity',
      _ => 'Capital Investments',
    };

const _bands = [
  ('Revenue', 'emerald', false),
  ('DirectCost', 'rose', true),
  ('OperatingExpense', 'amber', true),
  ('OtherCost', 'violet', true),
  ('Loss', 'violet', true),
];

const _drillBlurb = {
  'revenue':
      'Storefront sales and the driver returns behind delivery collections. The returns are COLLECTIONS, not sale rows — which is how the two are kept from double-counting.',
  'directcost': 'Raw material purchases at what was PAID for them, and approved production batches at their recorded cost.',
  'expense': 'Approved water expenses, and the delivery expenses recorded against driver returns.',
  'loss': 'Damaged or rejected stock, and cash a driver came up short.',
  'financing': 'Owner money and borrowing. None of it is revenue or expense — the cash moved and the profit did not.',
  'capital': 'What was capitalised into the asset register. Reaches profit later, through depreciation.',
  'depreciation': 'Depreciation posted against the asset register. It reduces profit and moves no money.',
};

// lib/water/financial-classification.ts — Water's own copy.
const _profitVsCashTitle = 'Profit is not the same as cash flow';
const _profitVsCashBody =
    'Profit measures the revenue and costs that belong to the selected period. Cash Flow measures the money that actually entered and left the company. They are both right, and they can differ.';
const _cashNotProfit = [
  'Buying film or bags you will use later — the cash leaves now, the cost lands as you use it',
  'Drilling a borehole or buying a machine — the cash leaves now, the cost spreads over its useful life',
  'Repaying loan principal — money you are giving back, not a cost',
  'Owner draws — the owner taking money out, not a business cost',
];
const _profitNotCash = [
  'Depreciation — a real cost of this period that moves no money',
  'Stock bought earlier and used now — the cost lands now, the cash left months ago',
  'A bill you have received but not yet paid — the cost is yours the day it is incurred',
];

class WaterProfitLossScreen extends StatefulWidget {
  const WaterProfitLossScreen({super.key, required this.session, required this.company, this.page = false});
  final Session session;
  final Company company;

  /// `/water-profit-loss` (chrome="page"): the Money page. Same statement,
  /// plain page frame, no Reports back button.
  final bool page;

  @override
  State<WaterProfitLossScreen> createState() => _WaterProfitLossScreenState();
}

class _WaterProfitLossScreenState extends State<WaterProfitLossScreen> {
  late String _from = defaultReportRange().from, _to = defaultReportRange().to;
  Map? _data;
  bool _busy = true;
  String? _error;
  FarmMoney _money = const FarmMoney();
  int _seq = 0;

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
      final d = await widget.session.farmClient
          .get('/api/Water/profit-loss', query: {'farmId': widget.company.farmId, 'startDate': _from, 'endDate': _to});
      if (mounted && seq == _seq) setState(() => _data = d is Map ? d : null);
    } on ApiException catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e.message);
    } finally {
      if (mounted && seq == _seq) setState(() => _busy = false);
    }
  }

  List<Map> get _lines => [for (final l in (_data?['lines'] is List ? _data!['lines'] as List : const [])) if (l is Map) l];

  void _open(Map line) {
    final kind = waterDrillKind('${line['section']}', '${line['lineKey']}');
    if (kind == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _WaterDrillPage(
        line: line,
        blurb: _drillBlurb[kind] ?? '',
        gh: _money,
        load: () async {
          final res = await widget.session.farmClient.get('/api/Water/profit-loss/detail', query: {
            'farmId': widget.company.farmId,
            'kind': kind,
            if ('${line['lineKey'] ?? ''}'.isNotEmpty) 'lineKey': line['lineKey'],
            'startDate': _from,
            'endDate': _to,
          });
          return [for (final r in LookupLoader.rowsIn(res)) if (r is Map) r];
        },
      ),
    ));
  }

  void _link(String href, String label) => openAppHref(context, widget.session, widget.company, href, label: label);

  @override
  Widget build(BuildContext context) {
    final gh = _money;
    final s = _data?['summary'] is Map ? _data!['summary'] as Map : null;
    num v(String k) => toNum(s?[k]);
    final lines = _lines;
    final informational = [for (final l in lines) if (l['isInformational'] == true) l];
    final owner = [for (final l in informational) if (l['lineKey'] == 'OwnerContributions' || l['lineKey'] == 'OwnerDraws') l];
    final loans = [for (final l in informational) if (l['lineKey'] == 'LoansReceived' || l['lineKey'] == 'LoanPrincipalRepaid') l];
    final capital = [for (final l in informational) if (l['section'] == 'CapitalInvestment') l];
    String? acc(num n) => n >= 0 ? 'green' : 'rose';
    final tiles = s == null
        ? const <SummaryCardData>[]
        : [
            tile('Revenue', gh(v('totalRevenue')), 'green'),
            tile('Gross profit', gh(v('grossProfit')), acc(v('grossProfit'))),
            tile('Operating profit', gh(v('operatingProfit')), acc(v('operatingProfit'))),
            tile('Net profit', gh(v('netProfit')), acc(v('netProfit'))),
          ];
    const small = TextStyle(fontSize: 11, color: slate500);
    const strong = TextStyle(fontWeight: FontWeight.w700, color: slate700);
    return ReportShellScreen(
      session: widget.session,
      company: widget.company,
      href: widget.page ? '/water-profit-loss' : '/water-reports/profit-loss',
      catalog: _catalog,
      page: widget.page,
      pageIcon: Icons.trending_up,
      title: 'Profit & Loss',
      description: 'Did the business make money from its operations this period?',
      busy: _busy,
      error: _error,
      onClearError: () => setState(() => _error = null),
      fromDate: _from,
      toDate: _to,
      onRangeChanged: (f, t) {
        setState(() {
          _from = f;
          _to = t;
        });
        _load();
      },
      tiles: tiles,
      recordCount: s == null ? null : lines.length,
      onRefresh: _load,
      document: s == null
          ? null
          : () => ReportDocument(
                title: 'Profit & Loss',
                filename: 'water-profit-loss',
                farmName: widget.company.name,
                cards: [for (final t in tiles) (label: t.label, value: t.value, accent: t.accent, note: null)],
                sections: [
                  ReportSection(
                    columns: [col('Line'), rcol('Amount')],
                    rows: [
                      for (final l in lines) ['${l['isInformational'] == true ? '(not in profit) ' : ''}${l['lineLabel']}', gh(toNum(l['amount']))],
                    ],
                  ),
                ],
              ),
      body: s == null
          ? const [Text('No P&L data for this period.', style: TextStyle(fontSize: 13, color: slate500))]
          : [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.info_outline, size: 14, color: slate500)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text.rich(TextSpan(style: small, children: [
                    TextSpan(text: '${gh(v('totalRevenue'))} revenue − ${gh(v('totalDirectCosts'))} direct costs = '),
                    TextSpan(text: gh(v('grossProfit')), style: strong),
                    TextSpan(text: ' gross · − ${gh(v('totalOperatingExpenses') + v('totalOtherCosts'))} expenses = '),
                    TextSpan(text: gh(v('operatingProfit')), style: strong),
                    TextSpan(text: ' operating · − ${gh(v('totalLosses'))} losses = '),
                    TextSpan(text: gh(v('netProfit')), style: strong.copyWith(color: slate900)),
                    TextSpan(text: ' net${v('netMarginPercent') != 0 ? ' (${wstr(v('netMarginPercent'))}% margin)' : ''}'),
                  ])),
                ),
              ]),
              const SizedBox(height: 12),
              if (v('capitalInExpenses') > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: amber50, border: Border.all(color: amber200), borderRadius: BorderRadius.circular(6)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFF78350F))),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "${gh(v('capitalInExpenses'))} of capital asset purchases is being charged to this period's profit. A major purchase is money the company still owns and normally reaches profit gradually, through depreciation. The water P&L counts it as an expense; the poultry one does not.",
                        style: const TextStyle(fontSize: 12, color: Color(0xFF78350F)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              for (final (section, tone, negative) in _bands)
                if (lines.any((l) => l['section'] == section))
                  () {
                    final band = [for (final l in lines) if (l['section'] == section) l];
                    return PlSectionCard(
                      title: waterPlSectionLabel(section),
                      tone: tone,
                      lines: band,
                      totalLabel: 'Total ${waterPlSectionLabel(section).toLowerCase()}',
                      total: band.fold<num>(0, (t, l) => t + toNum(l['amount'])),
                      onOpen: _open,
                      gh: gh.call,
                      negative: negative,
                    );
                  }(),
              if (informational.isNotEmpty) ...[
                const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.info_outline, size: 14, color: slate500)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Below the line on purpose. Owner money, borrowing and capital purchases move cash without being revenue or expense, so none of them is inside the profit above — a loan received is not income, and a borehole bought is not a cost.',
                      style: small,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                PlInfoCard(
                  icon: Icons.payments_outlined,
                  title: 'Owner Contributions & Draws',
                  subtitle: 'Excluded from profit',
                  note: "Money the owner put in or took out. It changes the cash in the bank and what the company owes its owner — never what it earned.",
                  rule: '',
                  lines: owner,
                  onOpen: _open,
                  gh: gh.call,
                  footer: ('Net owner funding', gh(v('netOwnerFunding'))),
                  links: const [('/water-owner-money', 'View Owner Money'), ('/water-cash-flow', 'View Cash Flow')],
                  onLink: _link,
                ),
                PlInfoCard(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Loans (Financing)',
                  subtitle: 'Excluded from profit',
                  note: 'Borrowing received and principal repaid. Neither is income or cost — only the interest and fees on a loan reach profit, and those sit in Other Costs above.',
                  rule: '',
                  lines: loans,
                  onOpen: _open,
                  gh: gh.call,
                  footer: ('Net borrowing', gh(v('netBorrowing'))),
                  links: const [('/water-loans', 'View Loans'), ('/water-cash-flow', 'View Cash Flow')],
                  onLink: _link,
                ),
                PlInfoCard(
                  icon: Icons.business_outlined,
                  title: 'Capital Investments',
                  subtitle: 'Excluded from immediate operating expenses',
                  note: 'Major purchases the company still owns. Their cost reaches profit gradually, through depreciation, rather than all at once in the month they were bought.',
                  rule: '',
                  lines: capital,
                  onOpen: _open,
                  gh: gh.call,
                  footer: ('Total invested', gh(v('totalCapitalInvestments'))),
                  links: const [('/water-assets', 'View Capital Investments/Assets')],
                  onLink: _link,
                ),
              ],
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.info_outline, size: 16, color: Color(0xFF0369A1))),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_profitVsCashTitle, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0C4A6E))),
                        SizedBox(height: 4),
                        Text(_profitVsCashBody, style: TextStyle(fontSize: 12, color: Color(0xFF0C4A6E))),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  for (final (head, items) in [
                    ("Cash out that is not this period's cost", _cashNotProfit),
                    ('Costs that did not move cash this period', _profitNotCash),
                  ]) ...[
                    Text(head, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF0C4A6E))),
                    for (final x in items)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Text('•  $x', style: const TextStyle(fontSize: 12, color: Color(0xFF0C4A6E))),
                      ),
                    const SizedBox(height: 8),
                  ],
                  Wrap(spacing: 12, children: [
                    for (final (href, label) in const [('/water-cash-flow', 'View Cash Flow'), ('/water-expenses', 'View Expenses')])
                      InkWell(
                        onTap: () => _link(href, label),
                        child: Text(label,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF075985), decoration: TextDecoration.underline)),
                      ),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              Text(
                'Revenue counts storefront sales plus what drivers collected on delivery runs. Raw materials are counted as PAID rather than as invoiced. ${wloc(v('entryCount'))} source record(s) are behind this statement — open any figure to see them.',
                style: small,
              ),
            ],
    );
  }
}

/// The drilldown, full screen on a phone: title, the kind's blurb, a filter,
/// the rows stacked (date + amount, reference · party, detail), and a total
/// that says when it is filtered.
class _WaterDrillPage extends StatefulWidget {
  const _WaterDrillPage({required this.line, required this.blurb, required this.gh, required this.load});
  final Map line;
  final String blurb;
  final FarmMoney gh;
  final Future<List<Map>> Function() load;

  @override
  State<_WaterDrillPage> createState() => _WaterDrillPageState();
}

class _WaterDrillPageState extends State<_WaterDrillPage> {
  List<Map>? _rows;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.load().then((r) {
      if (mounted) setState(() => _rows = r);
    }).catchError((Object _) {
      // The web closes the dialog when the detail cannot load.
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gh = widget.gh;
    final all = _rows;
    final q = _q.text.trim().toLowerCase();
    final shown = all == null || q.isEmpty
        ? all
        : [
            for (final r in all)
              if ([r['reference'], r['party'], r['detail']].any((v) => '${v ?? ''}'.toLowerCase().contains(q))) r,
          ];
    num sum(List<Map>? l) => (l ?? const []).fold<num>(0, (s, r) => s + toNum(r['amount']));
    final filtered = q.isNotEmpty && (shown?.length ?? 0) != (all?.length ?? 0);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.line['lineLabel'] ?? ''}', overflow: TextOverflow.ellipsis)),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(widget.blurb, style: const TextStyle(fontSize: 13, color: slate500)),
        ),
        Expanded(
          child: all == null
              ? const Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Loading…', style: TextStyle(fontSize: 13, color: slate500)),
                  ]),
                )
              : all.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nothing behind this figure for the selected period.', style: TextStyle(fontSize: 13, color: slate500)),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: AppInput(
                          controller: _q,
                          hintText: 'Filter by reference, party or detail',
                          prefixIcon: const Icon(Icons.search, size: 18, color: slate400),
                          suffixIcon: _q.text.isEmpty
                              ? null
                              : IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(_q.clear)),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                          itemCount: shown!.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final r = shown[i];
                            final date = '${r['entryDate'] ?? ''}';
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: slate200),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Expanded(
                                    child: Text(date.isEmpty ? '—' : date.replaceFirst('T', ' ').split('.').first,
                                        style: const TextStyle(fontSize: 14, color: slate900)),
                                  ),
                                  Text(gh(toNum(r['amount'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                ]),
                                Text.rich(TextSpan(style: const TextStyle(fontSize: 11, color: slate500), children: [
                                  TextSpan(text: wdash(r['reference']), style: const TextStyle(fontFamily: 'monospace')),
                                  if ('${r['party'] ?? ''}'.isNotEmpty) TextSpan(text: ' · ${r['party']}'),
                                ])),
                                if ('${r['detail'] ?? ''}'.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text('${r['detail']}', style: const TextStyle(fontSize: 11, color: slate600)),
                                  ),
                              ]),
                            );
                          },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: slate200))),
                        child: SafeArea(
                          top: false,
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Text('${wloc(shown.length)} record(s)', style: const TextStyle(fontSize: 13, color: slate600))),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(gh(sum(shown)),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: toNum(widget.line['amount']) < 0 ? const Color(0xFFDC2626) : slate900,
                                  )),
                              if (filtered) Text('filtered · ${gh(sum(all))} in full', style: const TextStyle(fontSize: 11, color: slate500)),
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
