// The Water dashboard's charts (an app addition the user asked for on
// 2026-11-02, mobile only: the web's Water dashboard has no graphs). They sit
// at the top of the Home tab and reuse the Hotel chart pieces and the Poultry
// chart helpers:
// - Bags produced: good and damaged bags per day, last 14 days (tap a day: rejected sachets).
// - Money in & out: sales and approved expenses per day, last 14 days (tap a day: net).
// - Where the money goes: approved expenses by category, last 30 days.
// - What sells: sale lines by product, last 30 days.
// Left out, as the web's own totals do: cancelled sales, expenses that are not
// Approved, and reversed or cancelled production records.

import 'package:flutter/material.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../hotel/hotel_dashboard_charts.dart';
import '../shared/chart_period.dart';
import 'package:poultrycore_mobile/design/tone.dart';
import '../poultry/poultry_dashboard_charts.dart' show dayOf, fieldOf, isoDay, topGroups;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart' show rowsOf;

const _ink2 = Tone.fg(0xFF52514E);


/// Each sale line as its own row, carrying the sale's date, for "What sells".
List<Map> saleLines(Iterable<Map> sales) => [
      for (final s in sales)
        for (final it in rowsOf(fieldOf(s, 'items')))
          {
            'saleDate': fieldOf(s, 'saleDate'),
            'productName': fieldOf(it, 'productName'),
            'amount': fieldOf(it, 'lineTotal') != null
                ? tNum(fieldOf(it, 'lineTotal'))
                : tNum(fieldOf(it, 'quantity')) * tNum(fieldOf(it, 'unitPrice')),
          },
    ];

class WaterDashboardCharts extends StatefulWidget {
  const WaterDashboardCharts({super.key, required this.session, required this.company, this.now = DateTime.now});
  final Session session;
  final Company company;
  final DateTime Function() now;

  @override
  State<WaterDashboardCharts> createState() => _WaterDashboardChartsState();
}

class _WaterDashboardChartsState extends State<WaterDashboardCharts> {
  List<Map> _production = const [], _sales = const [], _expenses = const [];
  bool _loading = true;
  // Opens on the last 12 months, so a business with no entries this fortnight still sees its figures.
  ChartWindow _period = const ChartWindow.preset(ChartPeriod.months);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = widget.session.farmClient;
    final q = {'farmId': widget.company.farmId};
    // One failing list must not blank the other charts.
    Future<List<Map>> list(String path) => api.get(path, query: q).then(rowsOf).catchError((Object _) => <Map>[]);
    final r = await Future.wait([list('/api/Water/daily-productions'), list('/api/Water/sales'), list('/api/Water/expenses')]);
    if (!mounted) return;
    setState(() {
      _production = r[0].where((p) => !const ['Reversed', 'Cancelled'].contains(tStr(fieldOf(p, 'status')))).toList();
      _sales = r[1].where((s) => tStr(fieldOf(s, 'status')) != 'Cancelled').toList();
      _expenses = r[2].where((e) => tStr(fieldOf(e, 'status')) == 'Approved').toList();
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
    List<num> sums(List<Map> rows, String dateKey, num Function(Map r) amount) => bucketSums(b, rows, (r) => dayOf(fieldOf(r, dateKey)), amount);
    num damaged(Map r) => tNum(fieldOf(r, 'damagedBags'));
    final good = sums(_production, 'productionDate', (r) => tNum(fieldOf(r, 'bagsProduced')) - damaged(r));
    final bad = sums(_production, 'productionDate', damaged);
    final rejected = sums(_production, 'productionDate', (r) => tNum(fieldOf(r, 'rejectedSachets')));
    final sold = sums(_sales, 'saleDate', (r) => tNum(fieldOf(r, 'totalAmount')));
    final spent = sums(_expenses, 'expenseDate', (r) => tNum(fieldOf(r, 'amount')));
    Widget footer(String text) => Text(text, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: _ink2));

    return ChartCardScope(name: 'water', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ChartPeriodPicker(value: p, now: widget.now(), onChanged: (v) => setState(() => _period = v)),
      HotelChartCard(
        icon: Icons.water_drop_outlined,
        title: 'Bags produced',
        subtitle: 'Good and damaged bags, ${p.by}, ${p.window}. Tap a column.',
        child: PairedColumns(
          days: keys,
          a: good,
          b: bad,
          aLabel: 'Good bags',
          bLabel: 'Damaged',
          dayLabel: short,
          valueText: whole,
          highlight: bucketHolding(b, today),
          footer: (i) => footer('${b[i].long} · rejected sachets ${whole(rejected[i])}'),
        ),
      ),
      HotelChartCard(
        icon: Icons.bar_chart,
        title: 'Money in & out',
        subtitle: 'Sales and approved expenses, ${p.by}, ${p.window}. Tap a column.',
        child: PairedColumns(
          days: keys,
          a: sold,
          b: spent,
          aLabel: 'Sales',
          bLabel: 'Expenses',
          dayLabel: short,
          valueText: fixed,
          highlight: bucketHolding(b, today),
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
        subtitle: 'Approved expenses by category, ${p.window}. Tap a slice.',
        child: moneyDonut(
          slices: topGroups(_expenses, windowEnd(b, today), dateKey: 'expenseDate', key: 'categoryName', amountKey: 'amount', from: b.first.from),
          money: fixed,
          caption: 'spent',
          period: p.window,
          emptyText: 'No approved expenses ${p.inWindow}',
        ),
      ),
      HotelChartCard(
        icon: Icons.shopping_cart_outlined,
        title: 'What sells',
        subtitle: 'Sales by product, ${p.window}. Tap a slice.',
        child: moneyDonut(
          slices: topGroups(saleLines(_sales), windowEnd(b, today), dateKey: 'saleDate', key: 'productName', amountKey: 'amount', from: b.first.from),
          money: fixed,
          caption: 'sold',
          period: p.window,
          emptyText: 'No sales ${p.inWindow}',
        ),
      ),
    ]));
  }
}
