// The Restaurant dashboard's charts (an app addition the user asked for on
// 2026-11-02, mobile only: the web's Restaurant dashboard has no graphs). They
// sit at the top of the dashboard and reuse the Hotel chart pieces and the
// Poultry chart helpers:
// - Money in & out: paid takings and expenses per day, last 14 days (tap a day: net).
// - Orders: orders placed and orders cancelled or refunded per day, last 14 days (tap a day: average bill).
// - How orders come in: paid takings by order type (dine-in, takeaway, delivery), last 30 days.
// - Where the money goes: expenses by category, last 30 days.
// Takings count paid orders only, as the dashboard's "Today's revenue" does.
// The orders come from the dashboard; the expenses are loaded here.

import 'package:flutter/material.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../hotel/hotel_dashboard_charts.dart';
import '../shared/chart_period.dart';
import '../poultry/poultry_dashboard_charts.dart' show dayOf, fieldOf, isoDay, lastDays, topGroups;
import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;
import '../poultry/trackers/tracker_widgets.dart' show rowsOf;

const _ink2 = Color(0xFF52514E);
const _dropped = ['Cancelled', 'Refunded'];
const _typeOrder = ['DineIn', 'Takeaway', 'Delivery'];
const _typeLabels = {'DineIn': 'Dine-in', 'Takeaway': 'Takeaway', 'Delivery': 'Delivery'};
const _typeColors = [chartBlue, chartOrange, chartAqua];

/// The local calendar day an order was placed on (createdAt is a UTC timestamp).
String orderDay(Map o) {
  final d = DateTime.tryParse(tStr(fieldOf(o, 'createdAt')));
  return d == null ? '' : isoDay(d.toLocal());
}

bool _paid(Map o) => tStr(fieldOf(o, 'paymentStatus')) == 'Paid' && !_dropped.contains(tStr(fieldOf(o, 'status')));

/// Paid takings by order type over the [days] days ending [today].
List<ChartSlice> orderTypeMix(List<Map> orders, String today, {int days = 30, String? from}) {
  from ??= lastDays(today, days).first;
  final sums = <String, num>{};
  for (final o in orders.where(_paid)) {
    final d = orderDay(o);
    if (d.compareTo(from) < 0 || d.compareTo(today) > 0) continue;
    final t = tStr(fieldOf(o, 'orderType'));
    final key = _typeOrder.contains(t) ? t : 'Other';
    sums[key] = (sums[key] ?? 0) + tNum(fieldOf(o, 'totalAmount'));
  }
  return [
    for (final (i, t) in _typeOrder.indexed)
      if ((sums[t] ?? 0) > 0) (label: _typeLabels[t]!, value: sums[t]!, color: _typeColors[i]),
    if ((sums['Other'] ?? 0) > 0) (label: 'Other', value: sums['Other']!, color: chartMagenta),
  ];
}

class RestaurantDashboardCharts extends StatefulWidget {
  const RestaurantDashboardCharts({super.key, required this.session, required this.company, required this.orders, this.now = DateTime.now});
  final Session session;
  final Company company;
  final List<Map> orders;
  final DateTime Function() now;

  @override
  State<RestaurantDashboardCharts> createState() => _RestaurantDashboardChartsState();
}

class _RestaurantDashboardChartsState extends State<RestaurantDashboardCharts> {
  List<Map> _expenses = const [];
  bool _loading = true;
  // Opens on the last 12 months, so a business with no entries this fortnight still sees its figures.
  ChartPeriod _period = ChartPeriod.months;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final today = isoDay(widget.now());
    // The widest window the picker offers (5 years), loaded once, so switching period needs no new request.
    final q = {'farmId': widget.company.farmId, '_': '1', 'from': ChartPeriod.years.buckets(widget.now()).first.from, 'to': today};
    // A failing expense list leaves those charts empty; the orders charts still draw.
    final r = await widget.session.farmClient.get('/api/Restaurant/expenses', query: q).then(rowsOf).catchError((Object _) => <Map>[]);
    if (!mounted) return;
    setState(() {
      _expenses = r.where((e) => !const ['Cancelled', 'Voided', 'Reversed'].contains(tStr(fieldOf(e, 'status')))).toList();
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
    final orders = widget.orders;
    String fixed(num v) => v.toStringAsFixed(2);
    String short(String k) => b[keys.indexOf(k)].short;
    final paidOrders = orders.where(_paid).toList();
    final takings = bucketSums(b, paidOrders, orderDay, (o) => tNum(fieldOf(o, 'totalAmount')));
    final paidCount = bucketSums(b, paidOrders, orderDay, (_) => 1);
    final spent = bucketSums(b, _expenses, (e) => dayOf(fieldOf(e, 'expenseDate')), (e) => tNum(fieldOf(e, 'amount')));
    final placed = bucketSums(b, orders, orderDay, (_) => 1);
    final dropped = bucketSums(b, orders.where((o) => _dropped.contains(tStr(fieldOf(o, 'status')))), orderDay, (_) => 1);
    Widget footer(String text) => Text(text, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: _ink2));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ChartPeriodPicker(value: p, onChanged: (v) => setState(() => _period = v)),
      HotelChartCard(
        icon: Icons.bar_chart,
        title: 'Money in & out',
        subtitle: 'Paid takings and expenses, ${p.by}, ${p.window}. Tap a column.',
        child: PairedColumns(
          days: keys,
          a: takings,
          b: spent,
          aLabel: 'Takings',
          bLabel: 'Expenses',
          dayLabel: short,
          valueText: fixed,
          highlight: keys.last,
          money: true,
          footer: (i) {
            final net = takings[i] - spent[i];
            return footer('${b[i].long} · net ${net >= 0 ? '+' : ''}${fixed(net)}');
          },
        ),
      ),
      HotelChartCard(
        icon: Icons.receipt_long_outlined,
        title: 'Orders',
        subtitle: 'Orders placed, and those cancelled (refunds included), ${p.by}, ${p.window}. Tap a column.',
        child: PairedColumns(
          days: keys,
          a: placed,
          b: dropped,
          aLabel: 'Placed',
          bLabel: 'Cancelled',
          dayLabel: short,
          valueText: (v) => v.toStringAsFixed(0),
          highlight: keys.last,
          footer: (i) => footer('${b[i].long} · average bill ${paidCount[i] == 0 ? '—' : fixed(takings[i] / paidCount[i])}'),
        ),
      ),
      HotelChartCard(
        icon: Icons.room_service_outlined,
        title: 'How orders come in',
        subtitle: 'Paid takings by order type, ${p.window}. Tap a slice.',
        child: moneyDonut(
          slices: orderTypeMix(orders, today, from: b.first.from),
          money: fixed,
          caption: 'taken',
          period: p.window,
          emptyText: 'No paid orders in the ${p.window}',
        ),
      ),
      HotelChartCard(
        icon: Icons.pie_chart_outline,
        title: 'Where the money goes',
        subtitle: 'Expenses by category, ${p.window}. Tap a slice.',
        child: moneyDonut(
          slices: topGroups(_expenses, today, dateKey: 'expenseDate', key: 'categoryName', amountKey: 'amount', from: b.first.from),
          money: fixed,
          caption: 'spent',
          period: p.window,
          emptyText: 'No expenses in the ${p.window}',
        ),
      ),
    ]);
  }
}
