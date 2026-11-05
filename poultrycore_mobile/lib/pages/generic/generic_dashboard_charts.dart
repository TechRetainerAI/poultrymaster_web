// The Generic dashboard's charts (an app addition the user asked for on
// 2026-11-02, mobile only: the web's Generic dashboard has no graphs). They
// sit at the top of the Home tab and reuse the Hotel chart pieces and the
// Poultry chart helpers:
// - Money in & out: approved sales and approved expenses per day, last 14 days (tap a day: net).
// - Paid & still owed: what approved sales collected and what is still owed, per sale day, last 14 days.
// - What sells: revenue by product, last 30 days (the Sales by product report).
// - Where the money goes: approved expenses by category, last 30 days.
// Only Approved sales and expenses count, as the web's reports do; drafts,
// cancelled and refunded sales, and unapproved expenses are left out.

import 'package:flutter/material.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../hotel/hotel_dashboard_charts.dart';
import '../shared/chart_period.dart';
import 'package:poultrycore_mobile/design/tone.dart';
import '../poultry/poultry_dashboard_charts.dart' show dayOf, fieldOf, isoDay, topGroups;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart' show rowsOf;
import 'generic_kit.dart' show genericBase;

const _ink2 = Tone.fg(0xFF52514E);
const _colors = [chartBlue, chartOrange, chartAqua, chartYellow];

bool _approved(Map r) => tStr(fieldOf(r, 'status')) == 'Approved';

/// The three best products by revenue from the Sales by product report rows, the rest as "Other".
List<ChartSlice> productMix(List<Map> rows) {
  final sorted = [
    for (final r in rows)
      if (tNum(fieldOf(r, 'totalRevenue')) > 0)
        (name: tStr(fieldOf(r, 'productName')).trim().isEmpty ? 'Unnamed' : tStr(fieldOf(r, 'productName')).trim(), value: tNum(fieldOf(r, 'totalRevenue'))),
  ]..sort((a, b) => b.value.compareTo(a.value));
  final rest = sorted.skip(3).fold<num>(0, (s, x) => s + x.value);
  return [
    for (final (i, x) in sorted.take(3).indexed) (label: x.name, value: x.value, color: _colors[i]),
    if (rest > 0) (label: 'Other', value: rest, color: chartMagenta),
  ];
}

class GenericDashboardCharts extends StatefulWidget {
  const GenericDashboardCharts({super.key, required this.session, required this.company, this.now = DateTime.now});
  final Session session;
  final Company company;
  final DateTime Function() now;

  @override
  State<GenericDashboardCharts> createState() => _GenericDashboardChartsState();
}

class _GenericDashboardChartsState extends State<GenericDashboardCharts> {
  List<Map> _sales = const [], _expenses = const [];
  bool _loading = true;
  // Opens on the last 12 months, so a business with no entries this fortnight still sees its figures.
  ChartPeriod _period = ChartPeriod.months;

  /// The Sales by product report for each period already asked for (it is a dated report, so one per window).
  final _products = <ChartPeriod, List<Map>>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = widget.session.farmClient;
    final base = genericBase(widget.company);
    // One failing list must not blank the other charts.
    Future<List<Map>> list(String path, [Map<String, dynamic>? q]) =>
        api.get('$base$path', query: q).then(rowsOf).catchError((Object _) => <Map>[]);
    final r = await Future.wait([
      list('/sales', {'status': 'Approved'}),
      list('/expenses', {'status': 'Approved'}),
      _productsFor(_period),
    ]);
    if (!mounted) return;
    setState(() {
      // The status filter is asked of the server and checked again here.
      _sales = r[0].where(_approved).toList();
      _expenses = r[1].where(_approved).toList();
      _products[_period] = r[2];
      _loading = false;
    });
  }

  Future<List<Map>> _productsFor(ChartPeriod p) => widget.session.farmClient
      .get('${genericBase(widget.company)}/reports/sales-by-product',
          query: {'fromDate': p.buckets(widget.now()).first.from, 'toDate': isoDay(widget.now())})
      .then(rowsOf)
      .catchError((Object _) => <Map>[]);

  Future<void> _pick(ChartPeriod p) async {
    setState(() => _period = p);
    if (_products.containsKey(p)) return;
    final rows = await _productsFor(p);
    if (mounted) setState(() => _products[p] = rows);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator()));
    }
    final today = isoDay(widget.now());
    final p = _period;
    final b = p.buckets(widget.now());
    final keys = [for (final x in b) x.from];
    String fixed(num v) => v.toStringAsFixed(2);
    String short(String k) => b[keys.indexOf(k)].short;
    List<num> sums(List<Map> rows, String dateKey, num Function(Map r) amount) => bucketSums(b, rows, (r) => dayOf(fieldOf(r, dateKey)), amount);
    final sold = sums(_sales, 'saleDate', (r) => tNum(fieldOf(r, 'totalAmount')));
    final spent = sums(_expenses, 'expenseDate', (r) => tNum(fieldOf(r, 'amount')));
    final paid = sums(_sales, 'saleDate', (r) => tNum(fieldOf(r, 'amountPaid')));
    final owed = sums(_sales, 'saleDate', (r) => tNum(fieldOf(r, 'balance')));
    final count = sums(_sales, 'saleDate', (_) => 1);
    final products = _products[p];
    Widget footer(String text) => Text(text, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: _ink2));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ChartPeriodPicker(value: p, onChanged: _pick),
      HotelChartCard(
        icon: Icons.bar_chart,
        title: 'Money in & out',
        subtitle: 'Approved sales and expenses, ${p.by}, ${p.window}. Tap a column.',
        child: PairedColumns(
          days: keys,
          a: sold,
          b: spent,
          aLabel: 'Sales',
          bLabel: 'Expenses',
          dayLabel: short,
          valueText: fixed,
          highlight: keys.last,
          money: true,
          footer: (i) {
            final net = sold[i] - spent[i];
            return footer('${b[i].long} · net ${net >= 0 ? '+' : ''}${fixed(net)}');
          },
        ),
      ),
      HotelChartCard(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Paid & still owed',
        subtitle: 'For the sales of each period: what has been paid and what is still owed, ${p.window}. Tap a column.',
        child: PairedColumns(
          days: keys,
          a: paid,
          b: owed,
          aLabel: 'Paid',
          bLabel: 'Owed',
          dayLabel: short,
          valueText: fixed,
          highlight: keys.last,
          money: true,
          footer: (i) => footer('${b[i].long} · ${count[i].toStringAsFixed(0)} sale(s)'),
        ),
      ),
      HotelChartCard(
        icon: Icons.shopping_bag_outlined,
        title: 'What sells',
        subtitle: 'Revenue by product, ${p.window}. Tap a slice.',
        child: products == null
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator()))
            : moneyDonut(
                slices: productMix(products),
                money: fixed,
                caption: 'sold',
                period: p.window,
                emptyText: 'No product sales in the ${p.window}',
              ),
      ),
      HotelChartCard(
        icon: Icons.pie_chart_outline,
        title: 'Where the money goes',
        subtitle: 'Approved expenses by category, ${p.window}. Tap a slice.',
        child: moneyDonut(
          slices: topGroups(_expenses, today, dateKey: 'expenseDate', key: 'categoryName', amountKey: 'amount', from: b.first.from),
          money: fixed,
          caption: 'spent',
          period: p.window,
          emptyText: 'No approved expenses in the ${p.window}',
        ),
      ),
    ]);
  }
}
