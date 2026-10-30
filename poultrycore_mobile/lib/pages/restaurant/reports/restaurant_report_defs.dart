// components/restaurant/reports/registry.tsx: every Restaurant report that is
// not a cash / ledger report, defined as data — what to fetch, the columns,
// the KPI tiles and the panel. The money reports are in
// restaurant_money_report_defs.dart.

import 'package:flutter/material.dart';

import '../../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../../poultry/trackers/tracker_widgets.dart' show TCard, TColors;
import 'restaurant_report_kit.dart';

const _rose = Color(0xFFE11D48);
const _roseLight = Color(0xFFFDA4AF);
const _slate = Color(0xFF64748B);

String _rq(String path) => '/api/Restaurant/reports/$path';
Map<String, dynamic> _fromTo(RRange r) => {'from': r.from, 'to': r.to};

num _n(Map r, String k) => tNum(r[k]);
String _s(Map r, String k) => tStr(r[k]);

/// A label / value pair, for the reports whose answer is a set of figures.
const _metricColumns = [
  RCol('metric', 'Metric', _metric),
  RCol('value', 'Value', _metricValue, numeric: true),
];
String _metric(Map r, RFmt f) => _s(r, 'metric');
String _metricValue(Map r, RFmt f) => _s(r, 'value');

Map<String, String> _m(String metric, String value) => {'metric': metric, 'value': value};

Map? _max(List<Map> rows, String key) => rows.fold<Map?>(null, (b, x) => b == null || _n(x, key) > _n(b, key) ? x : b);

// ===========================================================================
// MONEY
// ===========================================================================

final _pnl = RDef(
  load: (c, r) async {
    final res = await Future.wait([c.map(_rq('pnl'), _fromTo(r)), c.list(_rq('pnl-expenses'), _fromTo(r))]);
    return RLoad(res[1] as List<Map>, res[0]);
  },
  summary: (r, f) {
    final m = r.meta as Map?;
    if (m == null || m.isEmpty) return [];
    return [
      (label: 'Revenue', value: f.money(m['revenue'])),
      (label: 'Cost of goods', value: f.money(m['cogs'])),
      (label: 'Gross profit', value: '${f.money(m['grossProfit'])} (${f.pct(m['grossMarginPct'])})'),
      (label: 'Net profit', value: '${f.money(m['netProfit'])} (${f.pct(m['netMarginPct'])})'),
    ];
  },
  panel: (r, f) {
    final m = r.meta as Map?;
    if (m == null || m.isEmpty) return null;
    final net = _n(m, 'netProfit');
    // The waterfall as plain rows: a P&L is read down a column.
    final lines = [
      ('Revenue (net of tax and service charge)', f.money(m['revenue']), false, false),
      ('Less cost of goods sold', '- ${f.money(m['cogs'])}', false, true),
      ('Gross profit', f.money(m['grossProfit']), true, false),
      ('Less operating expenses', '- ${f.money(m['expensesTotal'])}', false, true),
      ('Net profit', f.money(m['netProfit']), true, false),
    ];
    final food = _n(m, 'foodCostPct'), gross = _n(m, 'grossMarginPct'), netPct = _n(m, 'netMarginPct');
    final ratios = [
      ('Food cost', f.pct(food), food > 35 ? 'bad' : food > 30 ? 'warn' : 'good'),
      ('Gross margin', f.pct(gross), gross >= 60 ? 'good' : 'warn'),
      ('Net margin', f.pct(netPct), netPct >= 10 ? 'good' : netPct >= 0 ? 'warn' : 'bad'),
      ('Orders in period', f.int_(m['orderCount']), 'muted'),
      ('Tips collected', f.money(m['tipsTotal']), 'muted'),
    ];
    Widget row(Widget left, Widget right) => Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: TColors.slate200))),
          child: Row(children: [Expanded(child: left), const SizedBox(width: 8), right]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      reportCard('Profit & loss', null, Column(children: [
        for (final (label, value, strong, negative) in lines)
          row(
            Text(label, style: TextStyle(fontSize: 13, fontWeight: strong ? FontWeight.w600 : null)),
            Text(value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: strong ? FontWeight.w600 : null,
                  color: negative ? red600 : (strong && net < 0 && label.startsWith('Net') ? red700 : null),
                )),
          ),
      ])),
      const SizedBox(height: 12),
      reportCard('Ratios', null, Column(children: [
        for (final (label, value, tone) in ratios) row(Text(label, style: const TextStyle(fontSize: 13)), toneBadge(value, tone)),
      ])),
    ]);
  },
  columns: [
    RCol('cat', 'Expense category', (r, f) => _s(r, 'expenseCategory')),
    RCol('n', 'Entries', (r, f) => f.int_(r['entryCount']), numeric: true, secondary: true),
    RCol('total', 'Total', (r, f) => f.money(r['expenseTotal']), numeric: true),
    RCol('share', 'Share', (r, f) => f.pct(r['sharePct']), numeric: true),
  ],
  tableTitle: 'Operating expenses by category',
  emptyText: 'No expenses recorded in this period. The profit figures above are still correct — they simply have nothing to deduct.',
);

final _salesSummary = RDef(
  load: (c, r) async => RLoad(const [], await c.map(_rq('sales-summary'), _fromTo(r))),
  summary: (r, f) {
    final s = r.meta as Map?;
    if (s == null || s.isEmpty) return [];
    return [
      (label: 'Gross revenue', value: f.money(s['grossRevenue'])),
      (label: 'Completed orders', value: '${f.int_(s['completedOrders'])} of ${f.int_(s['totalOrders'])}'),
      (label: 'Average ticket', value: f.money(s['avgTicket'])),
      (label: 'Covers', value: f.int_(s['coversTotal'])),
    ];
  },
  rows: (meta, f) {
    final s = meta as Map?;
    if (s == null || s.isEmpty || _n(s, 'totalOrders') == 0) return [];
    return [
      _m('Gross revenue', f.money(s['grossRevenue'])),
      _m('Net revenue (excl. tax and service charge)', f.money(s['netRevenue'])),
      _m('Discounts given', f.money(s['discountTotal'])),
      _m('Tax collected', f.money(s['taxTotal'])),
      _m('Service charge collected', f.money(s['serviceChargeTotal'])),
      _m('Tips collected', f.money(s['tipsTotal'])),
      _m('Total orders', f.int_(s['totalOrders'])),
      _m('Completed orders', f.int_(s['completedOrders'])),
      _m('Cancelled orders', f.int_(s['cancelledOrders'])),
      _m('Average ticket', f.money(s['avgTicket'])),
      _m('Covers', f.int_(s['coversTotal'])),
      _m('Revenue per cover', f.money(s['revenuePerCover'])),
      _m('Dine-in orders', '${f.int_(s['dineInCount'])} — ${f.money(s['dineInRevenue'])}'),
      _m('Takeaway orders', '${f.int_(s['takeawayCount'])} — ${f.money(s['takeawayRevenue'])}'),
      _m('Delivery orders', '${f.int_(s['deliveryCount'])} — ${f.money(s['deliveryRevenue'])}'),
      _m('Trading days', f.int_(s['activeDays'])),
      _m('Average daily revenue', f.money(s['avgDailyRevenue'])),
    ];
  },
  columns: _metricColumns,
  tableTitle: 'Every figure for this period',
  emptyText: 'No orders in this period.',
);

final _paymentMethods = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('payment-methods'), _fromTo(r))),
  summary: (r, f) => [
    (label: 'Total taken', value: f.money(sumOf(r.rows, (x) => _n(x, 'amountTotal')))),
    (label: 'Tips included', value: f.money(sumOf(r.rows, (x) => _n(x, 'tipsTotal')))),
    (label: 'Methods used', value: f.int_(r.rows.length)),
    (label: 'Transactions', value: f.int_(sumOf(r.rows, (x) => _n(x, 'txnCount')))),
  ],
  panel: (r, f) => r.rows.isEmpty
      ? null
      : reportCard('Share of take', 'Which methods the money arrives by',
          shareBars([for (final x in r.rows) (_s(x, 'methodName'), _n(x, 'amountTotal'))], fmt: (v) => v.toStringAsFixed(2))),
  columns: [
    RCol('m', 'Method', (r, f) => _s(r, 'methodName')),
    RCol('n', 'Transactions', (r, f) => f.int_(r['txnCount']), numeric: true),
    RCol('amt', 'Amount', (r, f) => f.money(r['amountTotal']), numeric: true),
    RCol('tips', 'Tips', (r, f) => f.money(r['tipsTotal']), numeric: true, secondary: true),
    RCol('avg', 'Average', (r, f) => f.money(r['avgTxn']), numeric: true, secondary: true),
    RCol('share', 'Share', (r, f) => f.pct(r['sharePct']), numeric: true),
  ],
  tableTitle: 'Payments by method',
  emptyText: 'No completed payments in this period.',
);

final _expenses = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('expenses'), _fromTo(r))),
  summary: (r, f) => [
    (label: 'Total spend', value: f.money(sumOf(r.rows, (x) => _n(x, 'expenseTotal')))),
    (label: 'Entries', value: f.int_(sumOf(r.rows, (x) => _n(x, 'entryCount')))),
    (label: 'Categories', value: f.int_({for (final x in r.rows) _s(x, 'expenseCategory')}.length)),
    (label: 'Suppliers', value: f.int_({for (final x in r.rows) _s(x, 'supplierLabel')}.length)),
  ],
  columns: [
    RCol('cat', 'Category', (r, f) => _s(r, 'expenseCategory')),
    RCol('sup', 'Supplier', (r, f) => _s(r, 'supplierLabel'), secondary: true),
    RCol('pm', 'Paid by', (r, f) => _s(r, 'methodLabel'), secondary: true),
    RCol('n', 'Entries', (r, f) => f.int_(r['entryCount']), numeric: true, secondary: true),
    RCol('amt', 'Total', (r, f) => f.money(r['expenseTotal']), numeric: true),
    RCol('share', 'Share', (r, f) => f.pct(r['sharePct']), numeric: true),
  ],
  tableTitle: 'Expenses',
  emptyText: 'No expenses recorded in this period.',
);

final _discounts = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('discounts'), _fromTo(r))),
  summary: (r, f) {
    final given = sumOf(r.rows, (x) => _n(x, 'discountTotal'));
    final gross = sumOf(r.rows, (x) => _n(x, 'grossOnDiscounted'));
    return [
      (label: 'Given away', value: f.money(given)),
      (label: 'On sales of', value: f.money(gross)),
      (label: 'Effective rate', value: gross > 0 ? f.pct(given / gross * 100) : f.pct(0)),
      (label: 'Distinct discounts', value: f.int_(r.rows.length)),
    ];
  },
  columns: [
    RCol('d', 'Discount', (r, f) => _s(r, 'discountLabel')),
    RCol('k', 'Type', (r, f) => _s(r, 'discountKind'), secondary: true),
    RCol('n', 'Times used', (r, f) => f.int_(r['timesApplied']), numeric: true),
    RCol('o', 'Orders', (r, f) => f.int_(r['ordersAffected']), numeric: true, secondary: true),
    RCol('t', 'Given away', (r, f) => f.money(r['discountTotal']), numeric: true),
    RCol('a', 'Average', (r, f) => f.money(r['avgDiscount']), numeric: true, secondary: true),
    RCol('e', 'Effective rate', (r, f) => f.pct(r['effectivePct']), numeric: true),
  ],
  tableTitle: 'Discounts applied',
  tableHint: 'Effective rate is what was actually given away against the value of the orders it was given on.',
  emptyText: 'No discounts were applied to completed orders in this period.',
);

// ===========================================================================
// SALES
// ===========================================================================

final _dailySales = RDef(
  load: (c, r) async => RLoad(const [], await c.map(_rq('daily-sales'), {'date': r.date})),
  summary: (r, f) {
    final d = r.meta as Map?;
    if (d == null || d.isEmpty) return [];
    return [
      (label: 'Revenue', value: f.money(d['totalRevenue'])),
      (label: 'Orders', value: '${f.int_(d['completedOrders'])} of ${f.int_(d['totalOrders'])}'),
      (label: 'Average ticket', value: f.money(d['avgTicket'])),
      (label: 'Covers', value: f.int_(d['totalCovers'])),
    ];
  },
  rows: (meta, f) {
    final d = meta as Map?;
    if (d == null || d.isEmpty || _n(d, 'totalOrders') == 0) return [];
    return [
      _m('Total revenue', f.money(d['totalRevenue'])),
      _m('Net revenue', f.money(d['netRevenue'])),
      _m('Discounts', f.money(d['totalDiscount'])),
      _m('Tax', f.money(d['totalTax'])),
      _m('Service charge', f.money(d['totalServiceCharge'])),
      _m('Total orders', f.int_(d['totalOrders'])),
      _m('Completed orders', f.int_(d['completedOrders'])),
      _m('Cancelled orders', f.int_(d['cancelledOrders'])),
      _m('Average ticket', f.money(d['avgTicket'])),
      _m('Covers', f.int_(d['totalCovers'])),
      _m('Dine-in', '${f.int_(d['dineInCount'])} — ${f.money(d['dineInRevenue'])}'),
      _m('Takeaway', '${f.int_(d['takeawayCount'])} — ${f.money(d['takeawayRevenue'])}'),
      _m('Delivery', '${f.int_(d['deliveryCount'])} — ${f.money(d['deliveryRevenue'])}'),
      _m('Cash', f.money(d['cashAmount'])),
      _m('Card', f.money(d['cardAmount'])),
      _m('Mobile money', f.money(d['mobileAmount'])),
      _m('Other', f.money(d['otherAmount'])),
    ];
  },
  columns: _metricColumns,
  tableTitle: 'The day in full',
  emptyText: 'No orders on this date.',
);

final _revenueTrend = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('revenue-trend'), _fromTo(r))),
  summary: (r, f) {
    final best = _max(r.rows, 'totalRevenue');
    return [
      (label: 'Revenue', value: f.money(sumOf(r.rows, (x) => _n(x, 'totalRevenue')))),
      (label: 'Orders', value: f.int_(sumOf(r.rows, (x) => _n(x, 'orderCount')))),
      (label: 'Trading days', value: f.int_(r.rows.length)),
      (label: 'Best day', value: best == null ? '—' : '${d10(best['reportDate'])} — ${f.money(best['totalRevenue'])}'),
    ];
  },
  panel: (r, f) => r.rows.isEmpty
      ? null
      : reportCard('Revenue and orders by day', 'Revenue on the left axis, order count on the right',
          BarChartRows(items: [for (final x in r.rows) d10(x['reportDate'])], series: [
            ('Revenue', _rose, [for (final x in r.rows) _n(x, 'totalRevenue')], (v) => f.num_(v)),
            ('Orders', _slate, [for (final x in r.rows) _n(x, 'orderCount')], (v) => f.int_(v)),
          ])),
  columns: [
    RCol('d', 'Date', (r, f) => d10(r['reportDate'])),
    RCol('n', 'Orders', (r, f) => f.int_(r['orderCount']), numeric: true),
    RCol('rev', 'Revenue', (r, f) => f.money(r['totalRevenue']), numeric: true),
    RCol('avg', 'Average ticket', (r, f) => f.money(r['avgTicket']), numeric: true),
  ],
  tableTitle: 'Day by day',
  emptyText: 'No completed orders in this period.',
);

final _topItems = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('sales-by-item'), _fromTo(r))),
  summary: (r, f) => [
    (label: 'Items sold', value: f.int_(sumOf(r.rows, (x) => _n(x, 'quantitySold')))),
    (label: 'Revenue', value: f.money(sumOf(r.rows, (x) => _n(x, 'totalRevenue')))),
    (label: 'Distinct items', value: f.int_(r.rows.length)),
    (label: 'Best seller', value: r.rows.isEmpty ? '—' : _s(r.rows.first, 'itemName')),
  ],
  panel: (r, f) => r.rows.isEmpty
      ? null
      : reportCard('Top ten by revenue', 'The items carrying the period',
          BarChartRows(items: [for (final x in r.rows.take(10)) _s(x, 'itemName')], series: [
            ('Revenue', _rose, [for (final x in r.rows.take(10)) _n(x, 'totalRevenue')], (v) => f.num_(v)),
          ])),
  columns: [
    RCol('i', 'Item', (r, f) => _s(r, 'itemName')),
    RCol('q', 'Qty sold', (r, f) => f.int_(r['quantitySold']), numeric: true),
    RCol('o', 'Orders', (r, f) => f.int_(r['orderCount']), numeric: true, secondary: true),
    RCol('p', 'Avg price', (r, f) => f.money(r['avgPrice']), numeric: true, secondary: true),
    RCol('rev', 'Revenue', (r, f) => f.money(r['totalRevenue']), numeric: true),
  ],
  tableTitle: 'All items sold',
  emptyText: 'Nothing was sold in this period.',
);

final _salesByCategory = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('sales-by-category'), _fromTo(r))),
  summary: (r, f) => [
    (label: 'Revenue', value: f.money(sumOf(r.rows, (x) => _n(x, 'totalRevenue')))),
    (label: 'Items sold', value: f.int_(sumOf(r.rows, (x) => _n(x, 'quantitySold')))),
    (label: 'Categories', value: f.int_(r.rows.length)),
    (label: 'Largest', value: r.rows.isEmpty ? '—' : _s(r.rows.first, 'categoryName')),
  ],
  panel: (r, f) => r.rows.isEmpty
      ? null
      : reportCard('Revenue by category', 'Where the money comes from on the menu',
          shareBars([for (final x in r.rows) (_s(x, 'categoryName'), _n(x, 'totalRevenue'))], fmt: (v) => v.toStringAsFixed(2))),
  columns: [
    RCol('c', 'Category', (r, f) => _s(r, 'categoryName')),
    RCol('i', 'Distinct items', (r, f) => f.int_(r['itemCount']), numeric: true, secondary: true),
    RCol('q', 'Qty sold', (r, f) => f.int_(r['quantitySold']), numeric: true),
    RCol('rev', 'Revenue', (r, f) => f.money(r['totalRevenue']), numeric: true),
  ],
  tableTitle: 'Categories',
  emptyText: 'Nothing was sold in this period.',
);

String _hour(Object? h) => '${tNum(h).toInt().toString().padLeft(2, '0')}:00';

final _peakHours = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('sales-by-hour'), {'date': r.date})),
  summary: (r, f) {
    final busiest = _max(r.rows, 'orderCount');
    final richest = _max(r.rows, 'totalRevenue');
    return [
      (label: 'Orders', value: f.int_(sumOf(r.rows, (x) => _n(x, 'orderCount')))),
      (label: 'Revenue', value: f.money(sumOf(r.rows, (x) => _n(x, 'totalRevenue')))),
      (label: 'Busiest hour', value: busiest == null ? '—' : _hour(busiest['hourOfDay'])),
      (label: 'Best hour by revenue', value: richest == null ? '—' : _hour(richest['hourOfDay'])),
    ];
  },
  panel: (r, f) => r.rows.isEmpty
      ? null
      : reportCard('Orders and revenue by hour', 'Where to put the staff',
          BarChartRows(items: [for (final x in r.rows) _hour(x['hourOfDay'])], series: [
            ('Revenue', _rose, [for (final x in r.rows) _n(x, 'totalRevenue')], (v) => f.num_(v)),
            ('Orders', _roseLight, [for (final x in r.rows) _n(x, 'orderCount')], (v) => f.int_(v)),
          ])),
  columns: [
    RCol('h', 'Hour', (r, f) => _hour(r['hourOfDay'])),
    RCol('n', 'Orders', (r, f) => f.int_(r['orderCount']), numeric: true),
    RCol('rev', 'Revenue', (r, f) => f.money(r['totalRevenue']), numeric: true),
    RCol('avg', 'Average ticket', (r, f) => f.money(r['avgTicket']), numeric: true),
  ],
  tableTitle: 'Hour by hour',
  emptyText: 'No completed orders on this date.',
);

// ===========================================================================
// MENU & FOOD
// ===========================================================================

String _classTone(String c) => switch (c) {
      'Star' => 'good',
      'Plowhorse' || 'Puzzle' => 'warn',
      'Dog' => 'bad',
      _ => 'muted',
    };

final _menuEngineering = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('menu-engineering'), _fromTo(r))),
  summary: (r, f) {
    int count(String c) => r.rows.where((x) => _s(x, 'menuClass') == c).length;
    return [
      (label: 'Stars (keep)', value: f.int_(count('Star'))),
      (label: 'Plowhorses (reprice)', value: f.int_(count('Plowhorse'))),
      (label: 'Puzzles (promote)', value: f.int_(count('Puzzle'))),
      (label: 'Dogs (consider cutting)', value: f.int_(count('Dog'))),
    ];
  },
  panel: (r, f) {
    Widget line(String bold, String rest) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: bold, style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: rest),
          ]), style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
        );
    return TCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      line('Star', ' — sells well and earns well. Protect it; never discount it.'),
      line('Plowhorse', ' — sells well, earns little. Reprice it or re-cost the recipe.'),
      line('Puzzle', ' — earns well, sells little. Promote it or move it up the menu.'),
      line('Dog', ' — neither. A candidate to take off.'),
      const SizedBox(height: 4),
      const Text.rich(TextSpan(children: [
        TextSpan(
            text: "Items are compared against this period's own averages, so the classification stays meaningful whatever the "
                'restaurant sells. An item with no costed recipe is shown as'),
        TextSpan(text: ' No recipe', style: TextStyle(fontWeight: FontWeight.w500)),
        TextSpan(text: ' rather than being guessed at.'),
      ]), style: TextStyle(fontSize: 12, color: TColors.slate500)),
    ]));
  },
  columns: [
    RCol('i', 'Item', (r, f) => _s(r, 'itemLabel')),
    RCol('c', 'Category', (r, f) => _s(r, 'categoryLabel'), secondary: true),
    RCol('q', 'Qty sold', (r, f) => f.int_(r['qtySold']), numeric: true),
    RCol('pop', 'Popularity', (r, f) => f.pct(r['popularityPct']), numeric: true, secondary: true),
    RCol('cost', 'Unit cost', (r, f) => f.money(r['unitCost']), numeric: true, secondary: true),
    RCol('m', 'Unit margin', (r, f) => f.money(r['unitMargin']), numeric: true),
    RCol('rev', 'Revenue', (r, f) => f.money(r['revenueTotal']), numeric: true),
    RCol('class', 'Class', (r, f) => _s(r, 'menuClass'), render: (r, f) => toneBadge(_s(r, 'menuClass'), _classTone(_s(r, 'menuClass')))),
  ],
  tableTitle: 'Every item sold, classified',
  emptyText: 'Nothing was sold in this period.',
);

Color _foodCostColor(num p) => p > 35 ? red700 : p > 30 ? amber700 : emerald700;

final _foodCost = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('food-cost'))),
  summary: (r, f) {
    final withCost = [for (final x in r.rows) if (_n(x, 'recipeCost') > 0) x];
    final avg = withCost.isEmpty ? 0 : sumOf(withCost, (x) => _n(x, 'foodCostPercent')) / withCost.length;
    final worst = _max(withCost, 'foodCostPercent');
    return [
      (label: 'Average food cost', value: f.pct(avg)),
      (label: 'Items with a recipe', value: '${f.int_(withCost.length)} of ${f.int_(r.rows.length)}'),
      (label: 'Highest food cost', value: worst == null ? '—' : '${_s(worst, 'itemName')} (${f.pct(worst['foodCostPercent'])})'),
      (label: 'Over 35%', value: f.int_(withCost.where((x) => _n(x, 'foodCostPercent') > 35).length)),
    ];
  },
  columns: [
    RCol('i', 'Item', (r, f) => _s(r, 'itemName')),
    RCol('c', 'Category', (r, f) => _s(r, 'categoryName'), secondary: true),
    RCol('p', 'Selling price', (r, f) => f.money(r['sellingPrice']), numeric: true),
    RCol('rc', 'Recipe cost', (r, f) => f.money(r['recipeCost']), numeric: true),
    RCol('fc', 'Food cost', (r, f) => f.pct(r['foodCostPercent']),
        numeric: true,
        render: (r, f) => coloured(f.pct(r['foodCostPercent']), _foodCostColor(_n(r, 'foodCostPercent')), bold: _n(r, 'foodCostPercent') > 30)),
    RCol('m', 'Margin', (r, f) => f.money(r['margin']), numeric: true),
  ],
  tableTitle: 'Food cost by menu item',
  tableHint: 'Current recipe costs against current prices — a position, not a period.',
  emptyText: 'No menu items yet. Add recipes to menu items to see food cost analysis.',
);

final _waste = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('waste-detail'), _fromTo(r))),
  summary: (r, f) {
    final worst = _max(r.rows, 'costTotal');
    return [
      (label: 'Waste cost', value: f.money(sumOf(r.rows, (x) => _n(x, 'costTotal')))),
      (label: 'Entries logged', value: f.int_(sumOf(r.rows, (x) => _n(x, 'entryCount')))),
      (label: 'Distinct reasons', value: f.int_({for (final x in r.rows) _s(x, 'wasteReason')}.length)),
      (label: 'Biggest single loss', value: worst == null ? '—' : '${_s(worst, 'itemLabel')} — ${f.money(worst['costTotal'])}'),
    ];
  },
  columns: [
    RCol('r', 'Reason', (r, f) => _s(r, 'wasteReason')),
    RCol('i', 'Item', (r, f) => _s(r, 'itemLabel')),
    RCol('q', 'Quantity', (r, f) => '${f.num_(r['qtyTotal'])} ${_s(r, 'wasteUnit')}', numeric: true),
    RCol('n', 'Entries', (r, f) => f.int_(r['entryCount']), numeric: true, secondary: true),
    RCol('c', 'Cost', (r, f) => f.money(r['costTotal']), numeric: true),
    RCol('s', 'Share', (r, f) => f.pct(r['sharePct']), numeric: true),
  ],
  tableTitle: 'Waste logged',
  emptyText: 'No waste was logged in this period.',
);

// ===========================================================================
// OPERATIONS
// ===========================================================================

final _kitchenPerformance = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('kitchen-performance'), _fromTo(r))),
  summary: (r, f) {
    final made = sumOf(r.rows, (x) => _n(x, 'itemsMade'));
    final over = sumOf(r.rows, (x) => _n(x, 'overTargetCount'));
    final slowest = _max(r.rows, 'avgTicketMins');
    final weighted = made > 0 ? sumOf(r.rows, (x) => _n(x, 'avgTicketMins') * _n(x, 'itemsMade')) / made : 0;
    return [
      (label: 'Items made', value: f.int_(made)),
      (label: 'Average ticket time', value: f.mins(weighted)),
      (label: 'Over 15 minutes', value: '${f.int_(over)} (${made > 0 ? f.pct(over / made * 100) : '0.0%'})'),
      (label: 'Slowest station', value: slowest == null ? '—' : '${_s(slowest, 'stationName')} — ${f.mins(slowest['avgTicketMins'])}'),
    ];
  },
  panel: (r, f) => r.rows.isEmpty
      ? null
      : reportCard(
          'Queue against cook time, per station',
          'Queue time is how long the ticket waited before anyone started it; prep time is the cooking itself. They have different fixes.',
          BarChartRows(items: [for (final x in r.rows) _s(x, 'stationName')], series: [
            ('Queue (min)', _roseLight, [for (final x in r.rows) _n(x, 'avgQueueMins')], (v) => '${v.toStringAsFixed(1)}m'),
            ('Prep (min)', _rose, [for (final x in r.rows) _n(x, 'avgPrepMins')], (v) => '${v.toStringAsFixed(1)}m'),
          ])),
  columns: [
    RCol('s', 'Station', (r, f) => _s(r, 'stationName')),
    RCol('n', 'Items', (r, f) => f.int_(r['itemsMade']), numeric: true),
    RCol('q', 'Avg queue', (r, f) => f.mins(r['avgQueueMins']), numeric: true),
    RCol('p', 'Avg prep', (r, f) => f.mins(r['avgPrepMins']), numeric: true),
    RCol('t', 'Avg ticket', (r, f) => f.mins(r['avgTicketMins']),
        numeric: true,
        render: (r, f) => coloured(f.mins(r['avgTicketMins']), _n(r, 'avgTicketMins') > 15 ? red700 : emerald700, bold: _n(r, 'avgTicketMins') > 15)),
    RCol('mx', 'Worst ticket', (r, f) => f.mins(r['maxTicketMins']), numeric: true, secondary: true),
    RCol('o', 'Over 15m', (r, f) => f.int_(r['overTargetCount']), numeric: true, secondary: true),
    RCol('si', 'Slowest item', (r, f) => _s(r, 'slowestItem'), secondary: true),
  ],
  tableTitle: 'Kitchen stations',
  tableHint: 'Only items with both a sent-to-kitchen and a ready timestamp are counted.',
  emptyText: 'No timed kitchen tickets in this period. Items are timed when they are sent to the kitchen and bumped on the KDS.',
);

final _tableTurnover = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('table-turnover'), _fromTo(r))),
  summary: (r, f) {
    final best = _max(r.rows, 'revenueTotal');
    final orders = sumOf(r.rows, (x) => _n(x, 'orderCount'));
    final dwell = orders > 0 ? sumOf(r.rows, (x) => _n(x, 'avgDwellMins') * _n(x, 'orderCount')) / orders : 0;
    return [
      (label: 'Dine-in revenue', value: f.money(sumOf(r.rows, (x) => _n(x, 'revenueTotal')))),
      (label: 'Covers served', value: f.int_(sumOf(r.rows, (x) => _n(x, 'coversServed')))),
      (label: 'Average dwell', value: f.mins(dwell)),
      (label: 'Best table', value: best == null ? '—' : '${_s(best, 'tableLabel')} — ${f.money(best['revenueTotal'])}'),
    ];
  },
  columns: [
    RCol('t', 'Table', (r, f) => _s(r, 'tableLabel')),
    RCol('cap', 'Seats', (r, f) => f.int_(r['seatCapacity']), numeric: true, secondary: true),
    RCol('n', 'Orders', (r, f) => f.int_(r['orderCount']), numeric: true),
    RCol('c', 'Covers', (r, f) => f.int_(r['coversServed']), numeric: true, secondary: true),
    RCol('d', 'Avg dwell', (r, f) => f.mins(r['avgDwellMins']), numeric: true),
    RCol('tp', 'Turns / day', (r, f) => f.num_(r['turnsPerDay']), numeric: true),
    RCol('rpc', 'Revenue / cover', (r, f) => f.money(r['revenuePerCover']), numeric: true, secondary: true),
    RCol('rev', 'Revenue', (r, f) => f.money(r['revenueTotal']), numeric: true),
  ],
  tableTitle: 'Dine-in tables',
  tableHint: 'Turns per day divides by the days that table actually took an order, not calendar days.',
  emptyText: 'No completed dine-in orders in this period.',
);

final _waiterPerformance = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('server-performance'), _fromTo(r))),
  summary: (r, f) => [
    (label: 'Revenue served', value: f.money(sumOf(r.rows, (x) => _n(x, 'totalRevenue')))),
    (label: 'Orders', value: f.int_(sumOf(r.rows, (x) => _n(x, 'orderCount')))),
    (label: 'Covers', value: f.int_(sumOf(r.rows, (x) => _n(x, 'totalCovers')))),
    (label: 'Waiters', value: f.int_(r.rows.length)),
  ],
  columns: [
    RCol('w', 'Waiter', (r, f) => _s(r, 'servedBy')),
    RCol('n', 'Orders', (r, f) => f.int_(r['orderCount']), numeric: true),
    RCol('c', 'Covers', (r, f) => f.int_(r['totalCovers']), numeric: true),
    RCol('a', 'Average ticket', (r, f) => f.money(r['avgTicket']), numeric: true),
    RCol('rev', 'Revenue', (r, f) => f.money(r['totalRevenue']), numeric: true),
  ],
  tableTitle: 'Waiters',
  emptyText: 'No completed orders in this period.',
);

final _tips = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('tips'), _fromTo(r))),
  summary: (r, f) {
    final t = sumOf(r.rows, (x) => _n(x, 'tipsTotal'));
    final rev = sumOf(r.rows, (x) => _n(x, 'revenueTotal'));
    final best = _max(r.rows, 'tipPct');
    return [
      (label: 'Tips collected', value: f.money(t)),
      (label: 'On sales of', value: f.money(rev)),
      (label: 'Overall tip rate', value: rev > 0 ? f.pct(t / rev * 100) : f.pct(0)),
      (label: 'Best tip rate', value: best != null && _n(best, 'tipPct') > 0 ? '${_s(best, 'waiterName')} — ${f.pct(best['tipPct'])}' : '—'),
    ];
  },
  columns: [
    RCol('w', 'Waiter', (r, f) => _s(r, 'waiterName')),
    RCol('n', 'Orders', (r, f) => f.int_(r['orderCount']), numeric: true),
    RCol('tp', 'Tipped orders', (r, f) => f.int_(r['tippedOrders']), numeric: true, secondary: true),
    RCol('rev', 'Revenue served', (r, f) => f.money(r['revenueTotal']), numeric: true, secondary: true),
    RCol('t', 'Tips', (r, f) => f.money(r['tipsTotal']), numeric: true),
    RCol('a', 'Average tip', (r, f) => f.money(r['avgTip']), numeric: true, secondary: true),
    RCol('pct', 'Tip rate', (r, f) => f.pct(r['tipPct']), numeric: true),
  ],
  tableTitle: 'Tips by waiter',
  tableHint: 'Tip rate is tips against the revenue that waiter served, so it compares fairly across sections.',
  emptyText: 'No tips were recorded in this period.',
);

final _voids = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('voids'), _fromTo(r))),
  summary: (r, f) {
    final worst = _max(r.rows, 'valueLost');
    return [
      (label: 'Value lost', value: f.money(sumOf(r.rows, (x) => _n(x, 'valueLost')))),
      (label: 'Orders affected', value: f.int_(sumOf(r.rows, (x) => _n(x, 'voidCount')))),
      (label: 'Covers lost', value: f.int_(sumOf(r.rows, (x) => _n(x, 'coversLost')))),
      (label: 'Biggest reason', value: worst == null ? '—' : '${_s(worst, 'voidReason')} — ${f.money(worst['valueLost'])}'),
    ];
  },
  columns: [
    RCol('k', 'Kind', (r, f) => _s(r, 'voidKind'), render: (r, f) => toneBadge(_s(r, 'voidKind'), _s(r, 'voidKind') == 'Refunded' ? 'warn' : 'bad')),
    RCol('r', 'Reason', (r, f) => _s(r, 'voidReason')),
    RCol('n', 'Orders', (r, f) => f.int_(r['voidCount']), numeric: true),
    RCol('c', 'Covers', (r, f) => f.int_(r['coversLost']), numeric: true, secondary: true),
    RCol('v', 'Value lost', (r, f) => f.money(r['valueLost']), numeric: true),
    RCol('s', 'Share', (r, f) => f.pct(r['sharePct']), numeric: true),
  ],
  tableTitle: 'Cancellations and refunds',
  emptyText: 'Nothing was cancelled or refunded in this period.',
);

String _stockTone(String s) => switch (s) {
      'Out of stock' || 'Reorder now' => 'bad',
      'Below par' => 'warn',
      _ => 'good',
    };

final _stockOnHand = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('stock-on-hand'))),
  summary: (r, f) => [
    (label: 'Stock value', value: f.money(sumOf(r.rows, (x) => _n(x, 'stockValue')))),
    (label: 'Out of stock', value: f.int_(r.rows.where((x) => _s(x, 'stockStatus') == 'Out of stock').length)),
    (label: 'Reorder now', value: f.int_(r.rows.where((x) => _s(x, 'stockStatus') == 'Reorder now').length)),
    (label: 'Ingredients tracked', value: f.int_(r.rows.length)),
  ],
  columns: [
    RCol('i', 'Ingredient', (r, f) => _s(r, 'ingredientName')),
    RCol('c', 'Category', (r, f) => _s(r, 'ingredientCategory'), secondary: true),
    RCol('oh', 'On hand', (r, f) => '${f.num_(r['onHand'], 2)} ${_s(r, 'stockUnit')}', numeric: true),
    RCol('par', 'Par', (r, f) => f.num_(r['parLevel'], 2), numeric: true, secondary: true),
    RCol('rp', 'Reorder at', (r, f) => f.num_(r['reorderPoint'], 2), numeric: true, secondary: true),
    RCol('v', 'Value', (r, f) => f.money(r['stockValue']), numeric: true),
    RCol('sup', 'Supplier', (r, f) => _s(r, 'supplierLabel'), secondary: true),
    RCol('st', 'Status', (r, f) => _s(r, 'stockStatus'), render: (r, f) => toneBadge(_s(r, 'stockStatus'), _stockTone(_s(r, 'stockStatus')))),
  ],
  tableTitle: 'Ingredients, worst first',
  tableHint: 'Sorted so anything needing action is at the top.',
  emptyText: 'No active ingredients. Add ingredients under Inventory to track stock.',
);

// ===========================================================================
// GUESTS & CHANNELS
// ===========================================================================

final _customerRetention = RDef(
  load: (c, r) async => RLoad(const [], await c.map(_rq('customer-retention'), _fromTo(r))),
  summary: (r, f) {
    final s = r.meta as Map?;
    if (s == null || s.isEmpty) return [];
    return [
      (label: 'Identified guests', value: f.int_(s['identifiedCustomers'])),
      (label: 'Returning', value: f.int_(s['returningCustomers'])),
      (label: 'Repeat rate', value: f.pct(s['repeatRatePct'])),
      (label: 'Average spend', value: f.money(s['avgSpend'])),
    ];
  },
  rows: (meta, f) {
    final c = meta as Map?;
    if (c == null || c.isEmpty) return [];
    return [
      _m('Identified guests in period', f.int_(c['identifiedCustomers'])),
      _m('Walk-in orders (no guest record)', f.int_(c['walkinOrders'])),
      _m('First-time guests', f.int_(c['newCustomers'])),
      _m('Returning guests', f.int_(c['returningCustomers'])),
      _m('Repeat rate', f.pct(c['repeatRatePct'])),
      _m('Average visits in period', f.num_(c['avgVisits'])),
      _m('Average spend in period', f.money(c['avgSpend'])),
      _m('Highest single-guest spend', f.money(c['topSpend'])),
      _m('Guests marked VIP (all time)', f.int_(c['vipCustomers'])),
      _m('Guests marked Lapsed (all time)', f.int_(c['lapsedCustomers'])),
    ];
  },
  columns: _metricColumns,
  tableTitle: 'Retention',
  tableHint: 'Walk-in orders carry no customer record, so they are counted separately rather than dragging the ratios down.',
  emptyText: 'No completed orders in this period.',
);

final _feedback = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('feedback'), _fromTo(r))),
  summary: (r, f) {
    final n = sumOf(r.rows, (x) => _n(x, 'responseCount'));
    final weighted = n > 0 ? sumOf(r.rows, (x) => _n(x, 'avgOverall') * _n(x, 'responseCount')) / n : 0;
    final prom = sumOf(r.rows, (x) => _n(x, 'promoterCount'));
    final det = sumOf(r.rows, (x) => _n(x, 'detractorCount'));
    return [
      (label: 'Responses', value: f.int_(n)),
      (label: 'Average rating', value: n > 0 ? '${f.num_(weighted, 2)} / 5' : '—'),
      (label: '4 stars and up', value: '${f.int_(prom)}${n > 0 ? ' (${f.pct(prom / n * 100)})' : ''}'),
      (label: '2 stars and under', value: '${f.int_(det)}${n > 0 ? ' (${f.pct(det / n * 100)})' : ''}'),
    ];
  },
  columns: [
    RCol('s', 'Source', (r, f) => _s(r, 'sourceLabel')),
    RCol('n', 'Responses', (r, f) => f.int_(r['responseCount']), numeric: true),
    RCol('o', 'Overall', (r, f) => f.num_(r['avgOverall'], 2), numeric: true),
    RCol('f', 'Food', (r, f) => f.num_(r['avgFood'], 2), numeric: true, secondary: true),
    RCol('sv', 'Service', (r, f) => f.num_(r['avgService'], 2), numeric: true, secondary: true),
    RCol('a', 'Ambience', (r, f) => f.num_(r['avgAmbience'], 2), numeric: true, secondary: true),
    RCol('p', '4+', (r, f) => f.int_(r['promoterCount']), numeric: true, secondary: true),
    RCol('d', '2-', (r, f) => f.int_(r['detractorCount']), numeric: true, secondary: true),
    RCol('u', 'Unanswered', (r, f) => f.int_(r['unansweredCount']), numeric: true),
  ],
  tableTitle: 'Ratings by source',
  tableHint: 'QR is what guests left themselves from the table; InStore is what staff logged.',
  emptyText: 'No feedback was left in this period.',
);

final _deliveryPerformance = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('delivery-performance'), _fromTo(r))),
  summary: (r, f) {
    final measured = sumOf(r.rows, (x) => _n(x, 'measuredCount'));
    final onTime = sumOf(r.rows, (x) => _n(x, 'onTimePct') / 100 * _n(x, 'measuredCount'));
    return [
      (label: 'Deliveries', value: f.int_(sumOf(r.rows, (x) => _n(x, 'assignmentCount')))),
      (label: 'On time', value: measured > 0 ? '${f.pct(onTime / measured * 100)} of ${f.int_(measured)}' : 'not measured'),
      (label: 'Failed', value: f.int_(sumOf(r.rows, (x) => _n(x, 'failedCount')))),
      (label: 'Delivery fees', value: f.money(sumOf(r.rows, (x) => _n(x, 'feesTotal')))),
    ];
  },
  columns: [
    RCol('d', 'Driver', (r, f) => _s(r, 'driverLabel')),
    RCol('n', 'Assigned', (r, f) => f.int_(r['assignmentCount']), numeric: true),
    RCol('ok', 'Delivered', (r, f) => f.int_(r['deliveredCount']), numeric: true),
    RCol('x', 'Failed', (r, f) => f.int_(r['failedCount']), numeric: true, secondary: true),
    RCol('act', 'Avg actual', (r, f) => f.mins(r['avgActualMins']), numeric: true),
    RCol('est', 'Avg promised', (r, f) => f.mins(r['avgEstimatedMins']), numeric: true, secondary: true),
    // The sample size travels with the percentage.
    RCol('ot', 'On time',
        (r, f) => _n(r, 'measuredCount') > 0 ? '${f.pct(r['onTimePct'])} of ${f.int_(r['measuredCount'])}' : 'not measured',
        numeric: true),
    RCol('km', 'Distance', (r, f) => '${f.num_(r['totalDistanceKm'], 1)} km', numeric: true, secondary: true),
    RCol('rt', 'Rating', (r, f) => _n(r, 'avgRating') > 0 ? f.num_(r['avgRating'], 2) : '—', numeric: true, secondary: true),
  ],
  tableTitle: 'Drivers',
  tableHint: 'On-time counts only deliveries that have both a promised and an actual time.',
  emptyText: 'No delivery assignments in this period.',
);

final _channel = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('channel'), _fromTo(r))),
  summary: (r, f) => [
    (label: 'Gross through platforms', value: f.money(sumOf(r.rows, (x) => _n(x, 'grossTotal')))),
    (label: 'Commission kept', value: f.money(sumOf(r.rows, (x) => _n(x, 'commissionTotal')))),
    (label: 'Platform fees', value: f.money(sumOf(r.rows, (x) => _n(x, 'platformFeeTotal')))),
    (label: 'You received', value: f.money(sumOf(r.rows, (x) => _n(x, 'netTotal')))),
  ],
  columns: [
    RCol('p', 'Platform', (r, f) => _s(r, 'platformLabel')),
    RCol('n', 'Orders', (r, f) => f.int_(r['orderCount']), numeric: true),
    RCol('rj', 'Rejected', (r, f) => f.int_(r['rejectedCount']), numeric: true, secondary: true),
    RCol('g', 'Gross', (r, f) => f.money(r['grossTotal']), numeric: true),
    RCol('c', 'Commission', (r, f) => f.money(r['commissionTotal']), numeric: true),
    RCol('pf', 'Platform fee', (r, f) => f.money(r['platformFeeTotal']), numeric: true, secondary: true),
    RCol('cp', 'Commission rate', (r, f) => f.pct(r['commissionPct']),
        numeric: true,
        render: (r, f) {
          final p = _n(r, 'commissionPct');
          return coloured(f.pct(p), p > 25 ? red700 : p > 15 ? amber700 : TColors.slate900, bold: p > 25);
        }),
    RCol('net', 'Net to you', (r, f) => f.money(r['netTotal']), numeric: true),
  ],
  tableTitle: 'Third-party platforms',
  emptyText: 'No third-party platform orders in this period.',
);

final _events = RDef(
  load: (c, r) async => RLoad(await c.list(_rq('events'), _fromTo(r))),
  summary: (r, f) => [
    (label: 'Contracted value', value: f.money(sumOf(r.rows, (x) => _n(x, 'contractedTotal')))),
    (label: 'Deposits received', value: f.money(sumOf(r.rows, (x) => _n(x, 'depositPaidTotal')))),
    (label: 'Balance outstanding', value: f.money(sumOf(r.rows, (x) => _n(x, 'balanceTotal')))),
    (label: 'Guests booked', value: f.int_(sumOf(r.rows, (x) => _n(x, 'guestTotal')))),
  ],
  columns: [
    RCol('s', 'Status', (r, f) => _s(r, 'eventStatus')),
    RCol('n', 'Events', (r, f) => f.int_(r['eventCount']), numeric: true),
    RCol('g', 'Guests', (r, f) => f.int_(r['guestTotal']), numeric: true),
    RCol('c', 'Contracted', (r, f) => f.money(r['contractedTotal']), numeric: true),
    RCol('dp', 'Deposit paid', (r, f) => f.money(r['depositPaidTotal']), numeric: true, secondary: true),
    RCol('b', 'Balance due', (r, f) => f.money(r['balanceTotal']), numeric: true),
    RCol('ph', 'Per head', (r, f) => f.money(r['avgPerHead']), numeric: true, secondary: true),
  ],
  tableTitle: 'Events by status',
  emptyText: 'No events fall in this period.',
);

/// The non-ledger half of REPORT_REGISTRY.
final restaurantReportDefs = <String, RDef>{
  'pnl': _pnl,
  'sales-summary': _salesSummary,
  'payment-methods': _paymentMethods,
  'expenses': _expenses,
  'discounts': _discounts,
  'daily-sales': _dailySales,
  'revenue-trend': _revenueTrend,
  'top-items': _topItems,
  'sales-by-category': _salesByCategory,
  'peak-hours': _peakHours,
  'menu-engineering': _menuEngineering,
  'food-cost': _foodCost,
  'waste': _waste,
  'kitchen-performance': _kitchenPerformance,
  'table-turnover': _tableTurnover,
  'waiter-performance': _waiterPerformance,
  'tips': _tips,
  'voids': _voids,
  'stock-on-hand': _stockOnHand,
  'customer-retention': _customerRetention,
  'feedback': _feedback,
  'delivery-performance': _deliveryPerformance,
  'channel': _channel,
  'events': _events,
};
