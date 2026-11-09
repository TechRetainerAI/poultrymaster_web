// Poultry's money charts on the Home tab (user, 2026-11-09: "graphs laid on the
// profit and loss, expenses, and the cash flow ... let the person know when I'm
// getting a loss or when I am gaining more profit"). An app addition: the web
// dashboard has no graphs.
//
// They read the same server figures as the Profit & Loss and Cash Flow pages,
// so they always agree with them, and write nothing:
// - /api/Poultry/profit-loss (startDate, endDate): totals for one window. The
//   per-period chart asks once per column, at most 4 at a time.
// - /api/Poultry/cash-flow (fromDate, toDate): dated, signed rows plus the
//   opening cash, grouped into the columns here.
// - /api/Poultry/customer-balances/summary and supplier-balances/summary.
//
// Profit and cash are different on purpose (a sale on credit is profit now and
// cash later), so every card says which one it shows.
//
// The cards, each foldable, each following the period picker:
// 1. Profit or loss: the headline, with the margin, the change on the
//    previous period of the same length, and how much of revenue costs took.
// 2. Profit or loss per period: columns above the line (profit) or below it (loss).
// 3. From revenue to profit: the P&L as a waterfall.
// 4. What the costs are: cost lines, largest first.
// 5. Cash in and out: money in above the line, money out below, net marked.
// 6. Cash at hand: the cash balance at the end of each period.
// 7. Who owes whom: what customers owe you and what you owe suppliers.
// A folded card draws nothing and asks for nothing.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../hotel/hotel_dashboard_charts.dart' show HotelChartCard, chartBlue, chartOrange, chartKey;
import '../shared/chart_period.dart';
import 'package:poultrycore_mobile/design/tone.dart';
import 'money/cash_flow_screen.dart' show previousRange;
import 'reports/report_format.dart' show FarmMoney;
import 'trackers/tracker_logic.dart' show tNum, tStr;
import 'trackers/tracker_widgets.dart' show rowsOf;

// Profit and loss: a diverging pair. Red/green alone is weak for colour-blind
// readers (validator: deutan ΔE 6.3), so the sign is also carried by position
// (above / below the line), an arrow and the words Profit / Loss.
const profitGreen = Tone(0xFF12916A), lossRed = Tone(0xFFE5484D);
const _ink = Tone.fg(0xFF0B0B0B), _ink2 = Tone.fg(0xFF52514E), _muted = Tone.fg(0xFF898781);
const _grid = Tone.line(0x140B0B0B), _base = Tone.line(0x400B0B0B);

const _api = '/api/Poultry';

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The P&L figures the charts use, from one /profit-loss answer.
class PlFigures {
  PlFigures(Map? r)
      : revenue = tNum(r?['totalRevenue']),
        direct = tNum(r?['totalDirectCosts']),
        operating = tNum(r?['totalOperatingExpenses']),
        other = tNum(r?['totalOtherCosts']),
        gross = tNum(r?['grossProfit']),
        operatingProfit = tNum(r?['operatingProfit']),
        net = tNum(r?['netProfit']),
        lines = [
          for (final l in (r?['lines'] is List ? r!['lines'] as List : const []))
            if (l is Map) Map<String, dynamic>.from(l),
        ];
  final num revenue, direct, operating, other, gross, operatingProfit, net;
  final List<Map<String, dynamic>> lines;
  num get costs => direct + operating + other;

  /// Cost lines (direct, operating, depreciation & financing costs), largest first.
  List<({String label, num amount})> get costLines {
    final out = <({String label, num amount})>[];
    for (final l in lines) {
      final s = tStr(l['section']);
      if (s != 'DirectCost' && s != 'OperatingExpense' && s != 'OtherCost') continue;
      final a = tNum(l['amount']);
      if (a <= 0) continue;
      out.add((label: tStr(l['lineLabel']).trim().isEmpty ? 'Other' : tStr(l['lineLabel']).trim(), amount: a));
    }
    out.sort((a, b) => b.amount.compareTo(a.amount));
    return out;
  }
}

/// "1.2k", "35k", "1.4M": tick labels.
String compactMoney(num v) {
  final a = v.abs(), s = v < 0 ? '−' : '';
  if (a >= 1e6) return '$s${(a / 1e6).toStringAsFixed(a >= 1e7 ? 0 : 1)}M';
  if (a >= 1e3) return '$s${(a / 1e3).toStringAsFixed(a >= 1e4 ? 0 : 1)}k';
  return '$s${a.toStringAsFixed(0)}';
}

/// Runs [jobs] at most [limit] at a time, answers in order.
Future<List<T>> _pooled<T>(List<Future<T> Function()> jobs, {int limit = 4}) async {
  final out = List<T?>.filled(jobs.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < jobs.length) {
      final i = next++;
      out[i] = await jobs[i]();
    }
  }

  await Future.wait([for (var k = 0; k < math.min(limit, jobs.length); k++) worker()]);
  return out.cast<T>();
}

class PoultryMoneyCharts extends StatefulWidget {
  const PoultryMoneyCharts({super.key, required this.session, required this.company, required this.window, required this.now});
  final Session session;
  final Company company;
  final ChartWindow window;
  final DateTime Function() now;

  @override
  State<PoultryMoneyCharts> createState() => _PoultryMoneyChartsState();
}

class _PoultryMoneyChartsState extends State<PoultryMoneyCharts> {
  FarmMoney _money = const FarmMoney();

  // Each answer asked once per window (re-opening a card or switching back costs nothing).
  final _pl = <String, Future<PlFigures?>>{};
  final _cash = <String, Future<Map?>>{};
  final _trend = <String, Future<List<PlFigures?>>>{};
  Future<(Map?, Map?)>? _owed;

  @override
  void initState() {
    super.initState();
    FarmMoney.load(widget.session, widget.company).then((m) {
      if (mounted) setState(() => _money = m);
    });
  }

  Future<PlFigures?> _plFor(String from, String to) => _pl.putIfAbsent('$from|$to', () async {
        try {
          final r = await widget.session.farmClient
              .get('$_api/profit-loss', query: {'farmId': widget.company.farmId, 'startDate': from, 'endDate': to});
          return r is Map ? PlFigures(r) : null;
        } catch (_) {
          return null;
        }
      });

  Future<Map?> _cashFor(String from, String to) => _cash.putIfAbsent('$from|$to', () async {
        try {
          final r = await widget.session.farmClient
              .get('$_api/cash-flow', query: {'farmId': widget.company.farmId, 'fromDate': from, 'toDate': to});
          return r is Map ? r : null;
        } catch (_) {
          return null;
        }
      });

  Future<(Map?, Map?)> _owedNow() => _owed ??= () async {
        Future<Map?> one(String path) async {
          try {
            final r = await widget.session.farmClient.get('$_api/$path', query: {'farmId': widget.company.farmId});
            return r is Map ? r : null;
          } catch (_) {
            return null;
          }
        }

        final r = await Future.wait([one('customer-balances/summary'), one('supplier-balances/summary')]);
        return (r[0], r[1]);
      }();

  /// The columns, each cut to today (a column wholly after today is dropped).
  List<ChartBucket> _cols(String today) => [
        for (final b in widget.window.buckets(widget.now()))
          if (b.from.compareTo(today) <= 0)
            b.to.compareTo(today) > 0 ? ChartBucket(from: b.from, to: today, short: b.short, long: b.long) : b,
      ];

  @override
  Widget build(BuildContext context) {
    final p = widget.window;
    final today = _iso(widget.now());
    final cols = _cols(today);
    if (cols.isEmpty) return const SizedBox.shrink();
    final from = cols.first.from, to = cols.last.to;
    final prev = previousRange(from, to);
    String money(num v) => _money(v);
    final trendKey = '$from|$to|${cols.length}';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HotelChartCard(
        icon: Icons.trending_up,
        title: 'Profit or loss',
        subtitle: 'From the Profit & Loss, ${p.window}, against the period before it.',
        child: _Loader<(PlFigures?, PlFigures?)>(
          id: '$from|$to',
          load: () async {
            final r = await Future.wait([
              _plFor(from, to),
              if (prev.from != null && prev.to != null) _plFor(prev.from!, prev.to!) else Future.value(null),
            ]);
            return (r[0], r[1]);
          },
          builder: (r) => r.$1 == null ? const _Empty('Profit & Loss is not available right now') : _Headline(now: r.$1!, before: r.$2, money: money),
        ),
      ),
      HotelChartCard(
        icon: Icons.stacked_bar_chart,
        title: 'Profit or loss per period',
        subtitle: 'Net profit ${p.by}, ${p.window}. Above the line is profit, below it a loss. Tap a column.',
        child: _Loader<List<PlFigures?>>(
          id: trendKey,
          load: () => _trend.putIfAbsent(trendKey, () => _pooled([for (final c in cols) () => _plFor(c.from, c.to)])),
          builder: (r) {
            final rows = [for (final f in r) f ?? PlFigures(null)];
            return _SignedColumns(
              labels: [for (final c in cols) c.short],
              longLabels: [for (final c in cols) c.long],
              up: [for (final f in rows) math.max(f.net, 0)],
              down: [for (final f in rows) math.max(-f.net, 0)],
              upColor: profitGreen,
              downColor: lossRed,
              readout: (i) => i == null
                  ? [
                      ('Revenue', money(rows.fold<num>(0, (s, f) => s + f.revenue)), null),
                      ('Costs', money(rows.fold<num>(0, (s, f) => s + f.costs)), null),
                      _result(rows.fold<num>(0, (s, f) => s + f.net), money),
                    ]
                  : [('Revenue', money(rows[i].revenue), null), ('Costs', money(rows[i].costs), null), _result(rows[i].net, money)],
              legend: [chartKey(profitGreen, 'Profit'), chartKey(lossRed, 'Loss')],
            );
          },
        ),
      ),
      HotelChartCard(
        icon: Icons.waterfall_chart,
        title: 'From revenue to profit',
        subtitle: 'How revenue becomes profit, step by step, ${p.window}.',
        child: _Loader<PlFigures?>(
          id: '$from|$to',
          load: () => _plFor(from, to),
          builder: (f) => f == null ? const _Empty('Profit & Loss is not available right now') : _Waterfall(f: f, money: money, inWindow: p.inWindow),
        ),
      ),
      HotelChartCard(
        icon: Icons.receipt_long_outlined,
        title: 'What the costs are',
        subtitle: 'Every cost in the Profit & Loss, largest first, ${p.window}.',
        child: _Loader<PlFigures?>(
          id: '$from|$to',
          load: () => _plFor(from, to),
          builder: (f) => _RankedBars(lines: f?.costLines ?? const [], money: money, emptyText: 'No costs ${p.inWindow}'),
        ),
      ),
      HotelChartCard(
        icon: Icons.swap_vert,
        title: 'Cash in and out',
        subtitle: 'Cash received above the line, cash paid out below, ${p.by}, ${p.window}. Tap a column.',
        child: _Loader<Map?>(
          id: '$from|$to',
          load: () => _cashFor(from, to),
          builder: (r) {
            final rows = rowsOf(r?['rows']);
            final ins = List<num>.filled(cols.length, 0), outs = List<num>.filled(cols.length, 0);
            for (final row in rows) {
              final d = tStr(row['transactionDate']);
              if (d.length < 10) continue;
              final day = d.substring(0, 10);
              for (var i = 0; i < cols.length; i++) {
                if (cols[i].holds(day)) {
                  final a = tNum(row['amount']);
                  if (a >= 0) {
                    ins[i] += a;
                  } else {
                    outs[i] += -a;
                  }
                  break;
                }
              }
            }
            final tin = ins.fold<num>(0, (s, x) => s + x), tout = outs.fold<num>(0, (s, x) => s + x);
            return _SignedColumns(
              labels: [for (final c in cols) c.short],
              longLabels: [for (final c in cols) c.long],
              up: ins,
              down: outs,
              upColor: chartBlue,
              downColor: chartOrange,
              netMarks: true,
              readout: (i) => [
                ('In', money(i == null ? tin : ins[i]), null),
                ('Out', money(i == null ? tout : outs[i]), null),
                _result(i == null ? tin - tout : ins[i] - outs[i], money, gain: 'Net in', lossWord: 'Net out'),
              ],
              legend: [chartKey(chartBlue, 'Cash in'), chartKey(chartOrange, 'Cash out'), chartKey(_ink, 'Net')],
            );
          },
        ),
      ),
      HotelChartCard(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Cash at hand',
        subtitle: 'Cash held at the end of each period, ${p.window}. Tap a point.',
        child: _Loader<Map?>(
          id: '$from|$to',
          load: () => _cashFor(from, to),
          builder: (r) {
            if (r == null) return const _Empty('Cash Flow is not available right now');
            final rows = rowsOf(r['rows']);
            final opening = tNum(r['summary'] is Map ? (r['summary'] as Map)['openingCash'] : 0);
            final net = List<num>.filled(cols.length, 0);
            for (final row in rows) {
              final d = tStr(row['transactionDate']);
              if (d.length < 10) continue;
              for (var i = 0; i < cols.length; i++) {
                if (cols[i].holds(d.substring(0, 10))) {
                  net[i] += tNum(row['amount']);
                  break;
                }
              }
            }
            var run = opening;
            final balances = [for (final n in net) run += n];
            return _BalanceLine(
              labels: [for (final c in cols) c.short],
              longLabels: [for (final c in cols) c.long],
              values: balances,
              opening: opening,
              money: money,
            );
          },
        ),
      ),
      HotelChartCard(
        icon: Icons.handshake_outlined,
        title: 'Who owes whom',
        subtitle: 'Unpaid balances today, all time: what customers owe you and what you owe suppliers.',
        child: _Loader<(Map?, Map?)>(
          id: 'owed',
          load: _owedNow,
          builder: (r) => _Owed(customers: r.$1, suppliers: r.$2, money: money),
        ),
      ),
    ]);
  }
}

(String, String, Color?) _result(num v, String Function(num) money, {String gain = 'Profit', String lossWord = 'Loss'}) =>
    (v < 0 ? lossWord : gain, '${v < 0 ? '− ' : '+ '}${money(v.abs())}', v < 0 ? lossRed : profitGreen);

// ------------------------------------------------------------------ pieces

/// A spinner while the answer is on its way, then [builder]. The request is
/// made only when the card is drawn (a folded card never builds this), and made
/// again only when [id] (the window) changes.
class _Loader<T> extends StatefulWidget {
  const _Loader({required this.id, required this.load, required this.builder});
  final String id;
  final Future<T> Function() load;
  final Widget Function(T value) builder;

  @override
  State<_Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<_Loader<T>> {
  late Future<T> _future = widget.load();

  @override
  void didUpdateWidget(_Loader<T> old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) _future = widget.load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _future,
        builder: (_, s) => s.connectionState != ConnectionState.done
            ? const SizedBox(height: 120, child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))))
            : widget.builder(s.data as T),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: _muted)),
      );
}

// 1. ------------------------------------------------------------- headline

class _Headline extends StatelessWidget {
  const _Headline({required this.now, required this.before, required this.money});
  final PlFigures now;
  final PlFigures? before;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    final loss = now.net < 0;
    final tint = loss ? lossRed : profitGreen;
    final margin = now.revenue > 0 ? now.net / now.revenue * 100 : null;
    final share = now.revenue > 0 ? now.costs / now.revenue : null;
    String? change;
    bool? changeUp;
    if (before != null) {
      final d = now.net - before!.net;
      if (d == 0) {
        change = 'Same as the period before';
      } else {
        change = '${money(d.abs())} ${d > 0 ? 'better' : 'worse'} than the period before';
        changeUp = d > 0;
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: tint.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
          child: Icon(loss ? Icons.south_east : Icons.north_east, color: tint, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(loss ? 'Loss' : 'Profit', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: tint)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(money(now.net.abs()), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _ink, height: 1.15)),
            ),
          ]),
        ),
      ]),
      if (change != null) ...[
        const SizedBox(height: 6),
        Row(children: [
          if (changeUp != null) ...[
            Icon(changeUp ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: changeUp ? profitGreen : lossRed),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(change, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: changeUp == null ? _ink2 : changeUp ? profitGreen : lossRed)),
          ),
        ]),
      ],
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _Figure('Revenue', money(now.revenue))),
        Expanded(child: _Figure('Costs', money(now.costs))),
        Expanded(child: _Figure('Margin', margin == null ? '—' : '${margin.toStringAsFixed(1)}%')),
      ]),
      if (share != null) ...[
        const SizedBox(height: 14),
        // A meter: how much of each unit of revenue the costs took.
        Text(
          share > 1
              ? 'Costs were ${(share * 100).toStringAsFixed(0)}% of revenue: more than came in.'
              : 'Costs took ${(share * 100).toStringAsFixed(0)}% of revenue; ${(100 - share * 100).toStringAsFixed(0)}% was kept.',
          style: const TextStyle(fontSize: 12, color: _ink2),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(children: [
              Expanded(flex: (math.min(share, 1) * 1000).round(), child: Container(color: share > 1 ? lossRed : chartOrange)),
              if (share < 1) const SizedBox(width: 2),
              if (share < 1) Expanded(flex: ((1 - share) * 1000).round(), child: Container(color: profitGreen)),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 14, children: [
          chartKey(share > 1 ? lossRed : chartOrange, 'Costs'),
          if (share < 1) chartKey(profitGreen, 'Kept as profit'),
        ]),
      ],
    ]);
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: _muted)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
        ),
      ]);
}

// 3. ------------------------------------------------------------- waterfall

/// Revenue at the top; each cost group steps down from it; the subtotals
/// (gross, operating, net profit) are full bars from zero. Read top to bottom.
class _Waterfall extends StatelessWidget {
  const _Waterfall({required this.f, required this.money, required this.inWindow});
  final PlFigures f;
  final String Function(num) money;
  final String inWindow;

  @override
  Widget build(BuildContext context) {
    if (f.revenue == 0 && f.costs == 0) return _Empty('No revenue or costs $inWindow');
    // (label, start, end, kind): kind 0 = revenue, 1 = a cost step, 2 = a subtotal.
    final steps = <(String, num, num, int)>[
      ('Revenue', 0, f.revenue, 0),
      ('Direct production costs', f.revenue, f.gross, 1),
      ('Gross profit', 0, f.gross, 2),
      ('Operating expenses', f.gross, f.operatingProfit, 1),
      ('Operating profit', 0, f.operatingProfit, 2),
      ('Depreciation & financing', f.operatingProfit, f.net, 1),
      ('Net profit', 0, f.net, 2),
    ];
    final lo = steps.fold<num>(0, (m, s) => math.min(m, math.min(s.$2, s.$3)));
    final hi = steps.fold<num>(0, (m, s) => math.max(m, math.max(s.$2, s.$3)));
    final span = (hi - lo) == 0 ? 1 : hi - lo;
    return Column(children: [
      for (final s in steps)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(
              width: 112,
              child: Text(
                s.$1,
                maxLines: 2,
                style: TextStyle(fontSize: 11.5, fontWeight: s.$4 == 1 ? FontWeight.w500 : FontWeight.w700, color: s.$4 == 1 ? _ink2 : _ink),
              ),
            ),
            Expanded(
              child: LayoutBuilder(builder: (_, box) {
                final w = box.maxWidth;
                final a = math.min(s.$2, s.$3), z = math.max(s.$2, s.$3);
                final left = (a - lo) / span * w, width = math.max(2.0, (z - a) / span * w);
                final zeroX = (0 - lo) / span * w;
                final color = switch (s.$4) {
                  0 => chartBlue,
                  1 => chartOrange,
                  _ => s.$3 < 0 ? lossRed : profitGreen,
                };
                return SizedBox(
                  height: 22,
                  child: Stack(children: [
                    Positioned(left: zeroX, top: 0, bottom: 0, child: Container(width: 1, color: _base)),
                    Positioned(
                      left: left.toDouble(),
                      width: width.toDouble(),
                      top: 3,
                      bottom: 3,
                      child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                    ),
                  ]),
                );
              }),
            ),
            SizedBox(
              width: 86,
              child: Text(
                s.$4 == 1 ? '− ${money((s.$2 - s.$3).abs())}' : (s.$3 < 0 ? '− ${money(s.$3.abs())}' : money(s.$3)),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: s.$4 == 1 ? FontWeight.w500 : FontWeight.w700,
                  color: s.$4 == 2 && s.$3 < 0 ? lossRed : (s.$4 == 1 ? _ink2 : _ink),
                ),
              ),
            ),
          ]),
        ),
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 4, children: [
        chartKey(chartBlue, 'Revenue'),
        chartKey(chartOrange, 'Costs'),
        chartKey(profitGreen, 'Profit'),
        chartKey(lossRed, 'Loss'),
      ]),
    ]);
  }
}

// 4. ------------------------------------------------------------ ranked bars

class _RankedBars extends StatelessWidget {
  const _RankedBars({required this.lines, required this.money, required this.emptyText});
  final List<({String label, num amount})> lines;
  final String Function(num) money;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return _Empty(emptyText);
    // Seven named lines, the rest folded into "Everything else".
    final shown = lines.take(7).toList();
    final rest = lines.skip(7).fold<num>(0, (s, l) => s + l.amount);
    if (rest > 0) shown.add((label: 'Everything else', amount: rest));
    final total = lines.fold<num>(0, (s, l) => s + l.amount);
    final top = shown.map((l) => l.amount).reduce(math.max);
    return Column(children: [
      for (final l in shown)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(l.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: _ink))),
              Text(money(l.amount), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink)),
              SizedBox(
                width: 44,
                child: Text('${(l.amount / total * 100).toStringAsFixed(0)}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, color: _muted)),
              ),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(children: [
                  Expanded(flex: math.max(1, (l.amount / top * 1000).round()), child: Container(color: chartOrange)),
                  Expanded(flex: math.max(0, 1000 - (l.amount / top * 1000).round()), child: Container(color: const Tone.bg(0xFFF0EFEC))),
                ]),
              ),
            ),
          ]),
        ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerRight,
        child: Text('Total costs ${money(total)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _ink2)),
      ),
    ]);
  }
}

// 7. -------------------------------------------------------------- owed

class _Owed extends StatelessWidget {
  const _Owed({required this.customers, required this.suppliers, required this.money});
  final Map? customers, suppliers;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    if (customers == null && suppliers == null) return const _Empty('Balances are not available right now');
    final them = tNum(customers?['totalBalance']), us = tNum(suppliers?['totalBalance']);
    final top = math.max(them, us);
    final net = them - us;
    Widget row(String label, String note, num v, Color c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink)),
                  Text(note, style: const TextStyle(fontSize: 11.5, color: _muted)),
                ]),
              ),
              Text(money(v), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 10,
                child: Row(children: [
                  if (v > 0) Expanded(flex: math.max(1, (v / top * 1000).round()), child: Container(color: c)),
                  Expanded(flex: math.max(0, 1000 - (top == 0 ? 0 : (v / top * 1000).round())), child: Container(color: const Tone.bg(0xFFF0EFEC))),
                ]),
              ),
            ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row('Customers owe you', '${tNum(customers?['partyCount']).toInt()} customers', them, chartBlue),
      row('You owe suppliers', '${tNum(suppliers?['partyCount']).toInt()} suppliers', us, chartOrange),
      const SizedBox(height: 6),
      Text(
        net == 0
            ? 'What you are owed and what you owe are equal.'
            : net > 0
                ? 'You are owed ${money(net)} more than you owe.'
                : 'You owe ${money(-net)} more than you are owed.',
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: net < 0 ? lossRed : _ink2),
      ),
    ]);
  }
}

// --------------------------------------------------------- tappable charts

typedef _Readout = List<(String, String, Color?)> Function(int? i);

/// The read-out above a chart: totals, or the tapped column.
Widget _readoutBar(String head, List<(String, String, Color?)> items) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: const Tone.bg(0xFFF9F9F7), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(head, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _ink2)),
        const SizedBox(height: 4),
        Row(children: [
          for (final (label, value, color) in items)
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 11, color: color ?? _muted, fontWeight: color == null ? FontWeight.w400 : FontWeight.w700)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color ?? _ink)),
                ),
              ]),
            ),
        ]),
      ]),
    );

/// Columns growing up ([up]) and down ([down]) from one zero line: profit
/// above and loss below, or cash in above and cash out below. [netMarks] adds a
/// short dark tick at up − down on each column.
class _SignedColumns extends StatefulWidget {
  const _SignedColumns({
    required this.labels,
    required this.longLabels,
    required this.up,
    required this.down,
    required this.upColor,
    required this.downColor,
    required this.readout,
    required this.legend,
    this.netMarks = false,
  });
  final List<String> labels, longLabels;
  final List<num> up, down;
  final Color upColor, downColor;
  final _Readout readout;
  final List<Widget> legend;
  final bool netMarks;

  @override
  State<_SignedColumns> createState() => _SignedColumnsState();
}

class _SignedColumnsState extends State<_SignedColumns> {
  int? _picked;
  static const _left = 44.0, _height = 200.0;

  @override
  void didUpdateWidget(_SignedColumns old) {
    super.didUpdateWidget(old);
    if (old.labels.length != widget.labels.length) _picked = null;
  }

  @override
  Widget build(BuildContext context) {
    final i = _picked;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _readoutBar(i == null ? 'Total' : widget.longLabels[i], widget.readout(i)),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (_, box) => GestureDetector(
          onTapDown: (e) {
            final n = widget.labels.length;
            final slot = (box.maxWidth - _left) / n;
            final k = ((e.localPosition.dx - _left) / slot).floor();
            setState(() => _picked = k < 0 || k >= n || _picked == k ? null : k);
          },
          child: TweenAnimationBuilder<double>(
            key: ValueKey('${widget.up}${widget.down}'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, t, _) => CustomPaint(
              size: Size(box.maxWidth, _height),
              painter: _SignedPainter(
                labels: widget.labels,
                up: widget.up,
                down: widget.down,
                upColor: widget.upColor,
                downColor: widget.downColor,
                netMarks: widget.netMarks,
                picked: _picked,
                t: t,
                font: DefaultTextStyle.of(context).style.fontFamily,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 4, children: widget.legend),
    ]);
  }
}

/// A round top for the scale: 1, 2, 2.5 or 5 times a power of ten.
num _niceTop(num v) {
  if (v <= 0) return 1;
  final p = math.pow(10, (math.log(v) / math.ln10).floor());
  for (final m in [1, 2, 2.5, 5, 10]) {
    if (m * p >= v) return m * p;
  }
  return 10 * p;
}

void _paintText(Canvas c, String s, Offset at, {String? font, Color color = _muted, bool centre = false, bool right = false, bool bold = false, double size = 10}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontFamily: font, fontSize: size, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
    textDirection: TextDirection.ltr,
  )..layout();
  final dx = centre ? at.dx - tp.width / 2 : (right ? at.dx - tp.width : at.dx);
  tp.paint(c, Offset(dx, at.dy - tp.height / 2));
}

/// Which column labels to draw: all when there is room, else one in a few.
bool _labelled(int i, int n) => n <= 7 || i % (n / 7).ceil() == 0;

class _SignedPainter extends CustomPainter {
  _SignedPainter({
    required this.labels,
    required this.up,
    required this.down,
    required this.upColor,
    required this.downColor,
    required this.netMarks,
    required this.picked,
    required this.t,
    this.font,
  });
  final String? font;
  final List<String> labels;
  final List<num> up, down;
  final Color upColor, downColor;
  final bool netMarks;
  final int? picked;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const left = _SignedColumnsState._left, bottom = 20.0;
    final n = labels.length;
    final plotH = size.height - bottom - 8;
    final maxUp = up.fold<num>(0, (m, v) => math.max(m, v)), maxDown = down.fold<num>(0, (m, v) => math.max(m, v));
    // One scale for both sides; the zero line sits where the two shares meet.
    final top = _niceTop(math.max(maxUp, 1)), bot = maxDown > 0 ? _niceTop(maxDown) : 0;
    final total = top + bot;
    final zeroY = 4 + plotH * top / total;
    double y(num v) => zeroY - v / total * plotH;

    // Recessive grid: top, zero and bottom, labelled.
    for (final v in [top, if (bot > 0) -bot]) {
      final gy = y(v);
      canvas.drawLine(Offset(left, gy), Offset(size.width, gy), Paint()..color = _grid);
      _paintText(canvas, font: font, compactMoney(v), Offset(left - 6, gy), right: true);
    }
    final half = top / 2;
    canvas.drawLine(Offset(left, y(half)), Offset(size.width, y(half)), Paint()..color = _grid);
    _paintText(canvas, font: font, compactMoney(half), Offset(left - 6, y(half)), right: true);
    canvas.drawLine(Offset(left, zeroY), Offset(size.width, zeroY), Paint()
      ..color = _base
      ..strokeWidth = 1.2);
    _paintText(canvas, font: font, '0', Offset(left - 6, zeroY), right: true);

    final slot = (size.width - left) / n;
    final barW = math.min(22.0, slot - math.min(8.0, slot * .3));
    for (var i = 0; i < n; i++) {
      final cx = left + slot * i + slot / 2;
      if (picked == i) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(left + slot * i + 1, 2, slot - 2, plotH + 8), const Radius.circular(6)),
          Paint()..color = const Tone(0xFFEDE9FE),
        );
      }
      final dim = picked != null && picked != i;
      final u = up[i] * t, d = down[i] * t;
      if (u > 0) {
        final h = math.max(2.0, zeroY - y(u));
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(cx - barW / 2, zeroY - h - 1, barW, h),
              topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
          Paint()..color = upColor.withValues(alpha: dim ? .3 : 1),
        );
      }
      if (d > 0) {
        final h = math.max(2.0, y(-d) - zeroY);
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(cx - barW / 2, zeroY + 1, barW, h),
              bottomLeft: const Radius.circular(4), bottomRight: const Radius.circular(4)),
          Paint()..color = downColor.withValues(alpha: dim ? .3 : 1),
        );
      }
      if (netMarks && (up[i] != 0 || down[i] != 0)) {
        final ny = y((up[i] - down[i]) * t);
        canvas.drawLine(
          Offset(cx - barW / 2 - 3, ny),
          Offset(cx + barW / 2 + 3, ny),
          Paint()
            ..color = _ink.withValues(alpha: dim ? .3 : 1)
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
      }
      if (_labelled(i, n) || picked == i) {
        _paintText(canvas, font: font, labels[i], Offset(cx, size.height - bottom / 2), centre: true, color: picked == i ? _ink : _muted, bold: picked == i);
      }
    }
  }

  @override
  bool shouldRepaint(_SignedPainter o) => o.t != t || o.picked != picked || o.up != up || o.down != down;
}

// 6. ------------------------------------------------------------ balance line

class _BalanceLine extends StatefulWidget {
  const _BalanceLine({required this.labels, required this.longLabels, required this.values, required this.opening, required this.money});
  final List<String> labels, longLabels;
  final List<num> values;
  final num opening;
  final String Function(num) money;

  @override
  State<_BalanceLine> createState() => _BalanceLineState();
}

class _BalanceLineState extends State<_BalanceLine> {
  int? _picked;
  static const _left = 44.0, _height = 180.0;

  @override
  Widget build(BuildContext context) {
    final i = _picked, v = widget.values;
    final end = v.isEmpty ? widget.opening : v.last;
    final change = end - widget.opening;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _readoutBar(i == null ? 'Whole period' : 'End of ${widget.longLabels[i]}', [
        if (i == null) ('At the start', widget.money(widget.opening), null),
        ('Cash at hand', widget.money(i == null ? end : v[i]), (i == null ? end : v[i]) < 0 ? lossRed : null),
        if (i == null) _result(change, widget.money, gain: 'Grew by', lossWord: 'Fell by'),
        if (i != null) _result(v[i] - (i == 0 ? widget.opening : v[i - 1]), widget.money, gain: 'Up', lossWord: 'Down'),
      ]),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (_, box) => GestureDetector(
          onTapDown: (e) {
            final n = v.length;
            if (n == 0) return;
            final slot = (box.maxWidth - _left) / n;
            final k = ((e.localPosition.dx - _left) / slot).floor();
            setState(() => _picked = k < 0 || k >= n || _picked == k ? null : k);
          },
          child: TweenAnimationBuilder<double>(
            key: ValueKey('${widget.values}'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, t, _) => CustomPaint(
              size: Size(box.maxWidth, _height),
              painter: _LinePainter(labels: widget.labels, values: v, picked: _picked, t: t, font: DefaultTextStyle.of(context).style.fontFamily),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.labels, required this.values, required this.picked, required this.t, this.font});
  final String? font;
  final List<String> labels;
  final List<num> values;
  final int? picked;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const left = _BalanceLineState._left, bottom = 20.0;
    final n = values.length;
    if (n == 0) return;
    final plotH = size.height - bottom - 10;
    final hiV = values.fold<num>(0, (m, v) => math.max(m, v)), loV = values.fold<num>(0, (m, v) => math.min(m, v));
    final top = _niceTop(math.max(hiV, 1)), bot = loV < 0 ? _niceTop(-loV) : 0;
    final total = top + bot;
    double y(num v) => 5 + plotH * (top - v) / total;
    final zeroY = y(0);

    for (final g in [top, top / 2, if (bot > 0) -bot]) {
      canvas.drawLine(Offset(left, y(g)), Offset(size.width, y(g)), Paint()..color = _grid);
      _paintText(canvas, font: font, compactMoney(g), Offset(left - 6, y(g)), right: true);
    }
    canvas.drawLine(Offset(left, zeroY), Offset(size.width, zeroY), Paint()
      ..color = _base
      ..strokeWidth = 1.2);
    _paintText(canvas, font: font, '0', Offset(left - 6, zeroY), right: true);

    final slot = (size.width - left) / n;
    Offset pt(int i) => Offset(left + slot * i + slot / 2, y(values[i]));
    // Drawn left to right as t runs 0 → 1.
    final upto = (t * (n - 1)).clamp(0.0, (n - 1).toDouble());
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i <= upto.floor(); i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    final frac = upto - upto.floor();
    Offset tip = pt(upto.floor());
    if (frac > 0 && upto.floor() + 1 < n) {
      tip = Offset.lerp(pt(upto.floor()), pt(upto.floor() + 1), frac)!;
      path.lineTo(tip.dx, tip.dy);
    }
    final area = Path.from(path)
      ..lineTo(tip.dx, zeroY)
      ..lineTo(pt(0).dx, zeroY)
      ..close();
    canvas.drawPath(area, Paint()..color = chartBlue.withValues(alpha: .12));
    canvas.drawPath(
      path,
      Paint()
        ..color = chartBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < n; i++) {
      if (i > upto + .001) break;
      final neg = values[i] < 0;
      final on = picked == i;
      if (on || n <= 14 || neg) {
        canvas.drawCircle(pt(i), on ? 6 : 4, Paint()..color = const Tone.bg(0xFFFFFFFF));
        canvas.drawCircle(pt(i), on ? 4.5 : 3, Paint()..color = neg ? lossRed : chartBlue);
      }
      if (_labelled(i, n) || on) {
        _paintText(canvas, font: font, labels[i], Offset(pt(i).dx, size.height - bottom / 2), centre: true, color: on ? _ink : _muted, bold: on);
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.t != t || o.picked != picked || o.values != values;
}
