// The Poultry dashboard's charts (an app addition the user asked for on
// 2026-11-02, app only: the web dashboard has no graphs). They sit at the top
// of the Home tab and reuse the Hotel chart pieces (hotel_dashboard_charts.dart):
// - Egg collection: eggs collected and broken per day, last 14 days (tap a day: deaths, feed).
// - Money in & out: sales and expenses per day, last 14 days (tap a day: net).
// - Where the money goes: expenses by category, last 30 days.
// - What sells: sales by product, last 30 days.
// Reversed sales and expenses kept out of profit (plSection "Excluded") are
// left out, as the web's own totals do.

import 'package:flutter/material.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../hotel/hotel_dashboard_charts.dart';
import '../shared/chart_period.dart';
import 'trackers/tracker_logic.dart' show tNum, tStr;
import 'trackers/tracker_widgets.dart' show rowsOf;

const _colors = [chartBlue, chartOrange, chartAqua, chartYellow];
const _ink2 = Color(0xFF52514E);
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String dayOf(Object? v) => tStr(v).length >= 10 ? tStr(v).substring(0, 10) : tStr(v);
DateTime parseDay(String iso) => DateTime(int.parse(iso.substring(0, 4)), int.parse(iso.substring(5, 7)), int.parse(iso.substring(8, 10)));
String niceDay(String iso) {
  final d = parseDay(iso);
  return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

Object? fieldOf(Map m, String k) => m[k] ?? m[k.toLowerCase()];

/// The [days] dates ending [today], oldest first.
List<String> lastDays(String today, int days) =>
    [for (var i = days - 1; i >= 0; i--) isoDay(parseDay(today).subtract(Duration(days: i)))];

bool _liveSale(Map s) => tStr(fieldOf(s, 'status')) != 'Reversed';
bool _countedExpense(Map e) => tStr(fieldOf(e, 'plSection')) != 'Excluded';


/// Up to three biggest groups by [key] over the [days] days ending [today], the rest as "Other".
List<ChartSlice> topGroups(Iterable<Map> rows, String today,
    {required String dateKey, required String key, required String amountKey, int days = 30, String? from}) {
  from ??= lastDays(today, days).first;
  final sums = <String, num>{};
  for (final r in rows) {
    final d = dayOf(fieldOf(r, dateKey));
    if (d.compareTo(from) < 0 || d.compareTo(today) > 0) continue;
    final k = tStr(fieldOf(r, key)).trim().isEmpty ? 'Uncategorised' : tStr(fieldOf(r, key)).trim();
    sums[k] = (sums[k] ?? 0) + tNum(fieldOf(r, amountKey));
  }
  final sorted = sums.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
  final top = sorted.take(3).toList();
  final rest = sorted.skip(3).fold<num>(0, (s, e) => s + e.value);
  return [
    for (final (i, e) in top.indexed) (label: e.key, value: e.value, color: _colors[i]),
    if (rest > 0) (label: 'Other', value: rest, color: chartMagenta),
  ];
}

/// The four charts, loading the farm's production records, sales and expenses.
class PoultryDashboardCharts extends StatefulWidget {
  const PoultryDashboardCharts({super.key, required this.session, required this.company, this.now = DateTime.now});
  final Session session;
  final Company company;
  final DateTime Function() now;

  @override
  State<PoultryDashboardCharts> createState() => PoultryDashboardChartsState();
}

class PoultryDashboardChartsState extends State<PoultryDashboardCharts> {
  List<Map> _production = const [], _sales = const [], _expenses = const [];
  bool _loading = true;
  // Opens on the last 12 months, so a business with no entries this fortnight still sees its figures.
  ChartPeriod _period = ChartPeriod.months;

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Called again by the Home tab's pull-to-refresh.
  Future<void> reload() async {
    final api = widget.session.farmClient;
    final q = {'userId': widget.session.tokens.userId, 'farmId': widget.company.farmId};
    // One failing list must not blank the other charts.
    Future<List<Map>> list(String path) => api.get(path, query: q).then(rowsOf).catchError((Object _) => <Map>[]);
    final r = await Future.wait([list('/api/ProductionRecord'), list('/api/Sale'), list('/api/Expense')]);
    if (!mounted) return;
    setState(() {
      _production = r[0];
      _sales = r[1].where(_liveSale).toList();
      _expenses = r[2].where(_countedExpense).toList();
      _loading = false;
    });
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
    String whole(num v) => v.toStringAsFixed(0);
    String short(String k) => b[keys.indexOf(k)].short;
    List<num> sums(List<Map> rows, String dateKey, String key) => bucketSums(b, rows, (r) => dayOf(fieldOf(r, dateKey)), (r) => tNum(fieldOf(r, key)));
    final eggs = sums(_production, 'date', 'totalProduction');
    final broken = sums(_production, 'date', 'brokenEggs');
    final deaths = sums(_production, 'date', 'mortality');
    final feed = sums(_production, 'date', 'feedKg');
    final sold = sums(_sales, 'saleDate', 'totalAmount');
    final spent = sums(_expenses, 'expenseDate', 'amount');
    Widget footer(String text) => Text(text, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: _ink2));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ChartPeriodPicker(value: p, onChanged: (v) => setState(() => _period = v)),
      HotelChartCard(
        icon: Icons.egg_outlined,
        title: 'Egg collection',
        subtitle: 'Eggs collected and broken, ${p.by}, ${p.window}. Tap a column.',
        child: PairedColumns(
          days: keys,
          a: eggs,
          b: broken,
          aLabel: 'Collected',
          bLabel: 'Broken',
          dayLabel: short,
          valueText: whole,
          highlight: keys.last,
          footer: (i) => footer('${b[i].long} · deaths ${whole(deaths[i])} · feed ${feed[i].toStringAsFixed(1)} kg'),
        ),
      ),
      HotelChartCard(
        icon: Icons.bar_chart,
        title: 'Money in & out',
        subtitle: 'Sales and expenses, ${p.by}, ${p.window}. Tap a column.',
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
        icon: Icons.pie_chart_outline,
        title: 'Where the money goes',
        subtitle: 'Expenses by category, ${p.window}. Tap a slice.',
        child: moneyDonut(
          slices: topGroups(_expenses, today, dateKey: 'expenseDate', key: 'category', amountKey: 'amount', from: b.first.from),
          money: fixed,
          caption: 'spent',
          period: p.window,
          emptyText: 'No expenses in the ${p.window}',
        ),
      ),
      HotelChartCard(
        icon: Icons.shopping_cart_outlined,
        title: 'What sells',
        subtitle: 'Sales by product, ${p.window}. Tap a slice.',
        child: moneyDonut(
          slices: topGroups(_sales, today, dateKey: 'saleDate', key: 'product', amountKey: 'totalAmount', from: b.first.from),
          money: fixed,
          caption: 'sold',
          period: p.window,
          emptyText: 'No sales in the ${p.window}',
        ),
      ),
    ]);
  }
}
