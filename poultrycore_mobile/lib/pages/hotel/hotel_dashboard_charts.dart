// The Hotel dashboard's charts (an app addition the user asked for on
// 2026-10-28; the web dashboard has none). Drawn with CustomPainter, so no
// chart package. Every chart reads data the dashboard already loads:
// - Room mix: a donut of rooms by status, occupancy in the middle.
// - Money in & out: revenue (payments) and expenses per day, last 14 days.
// - Arrivals & departures: stays starting and ending per day, next 7 days.
// - How guests pay: payments by method, last 30 days, as one stacked bar.
// Colours are the validated categorical order (blue, orange, aqua, yellow,
// magenta); each entity keeps its colour, and every mark has a text label
// beside it, since three of the five sit below 3:1 on white.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../poultry/trackers/tracker_logic.dart' show tNum, tStr;

const chartBlue = Color(0xFF2A78D6), chartOrange = Color(0xFFEB6834), chartAqua = Color(0xFF1BAF7A);
const chartYellow = Color(0xFFEDA100), chartMagenta = Color(0xFFE87BA4);
const _series = [chartBlue, chartOrange, chartAqua, chartYellow, chartMagenta];
const _ink = Color(0xFF0B0B0B), _ink2 = Color(0xFF52514E), _muted = Color(0xFF898781);
const _grid = Color(0xFFE1E0D9), _baseline = Color(0xFFC3C2B7);

Object? _v(Map m, String k) => m[k] ?? m[k.toLowerCase()];
String _day(Object? v) => tStr(v).length >= 10 ? tStr(v).substring(0, 10) : tStr(v);
String _iso(DateTime d) => d.toIso8601String().substring(0, 10);
DateTime _parse(String iso) => DateTime.utc(int.parse(iso.substring(0, 4)), int.parse(iso.substring(5, 7)), int.parse(iso.substring(8, 10)));

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _nice(String iso) {
  final d = _parse(iso);
  return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

/// 1234 → "1.2k", for axis ticks.
String compactMoney(num n) {
  final a = n.abs();
  if (a >= 1e6) return '${(n / 1e6).toStringAsFixed(a >= 1e7 ? 0 : 1)}M';
  if (a >= 1e3) return '${(n / 1e3).toStringAsFixed(a >= 1e4 ? 0 : 1)}k';
  return n.toStringAsFixed(0);
}

// ------------------------------------------------------------------ the data

/// The statuses the room board uses, in their fixed colour order. Anything
/// else folds into "Other".
const roomStatusOrder = ['Available', 'Occupied', 'Reserved', 'Cleaning', 'Maintenance'];

typedef ChartSlice = ({String label, num value, Color color});

List<ChartSlice> roomMix(List<Map> statusSummary) {
  num count(String s) => statusSummary.where((r) => r['status'] == s).fold<num>(0, (a, r) => a + tNum(r['roomCount']));
  final other = statusSummary.where((r) => !roomStatusOrder.contains(r['status'])).fold<num>(0, (a, r) => a + tNum(r['roomCount']));
  return [
    for (final (i, s) in roomStatusOrder.indexed) (label: s, value: count(s), color: _series[i]),
    if (other > 0) (label: 'Other', value: other, color: _muted),
  ];
}

typedef MoneyDay = ({String day, num revenue, num expenses});

/// Revenue (payments) and expenses for each of the [days] days ending [today].
List<MoneyDay> dailyMoney(List<Map> payments, List<Map> expenses, String today, {int days = 14}) {
  final end = _parse(today);
  return [
    for (var i = days - 1; i >= 0; i--)
      () {
        final d = _iso(end.subtract(Duration(days: i)));
        return (
          day: d,
          revenue: payments.where((p) => _day(_v(p, 'paymentDate')) == d).fold<num>(0, (s, p) => s + tNum(p['amount'])),
          expenses: expenses.where((e) => _day(_v(e, 'expenseDate')) == d).fold<num>(0, (s, e) => s + tNum(e['amount'])),
        );
      }(),
  ];
}

typedef MovementDay = ({String day, int arrivals, int departures});

/// Stays starting and ending on each of the next [days] days from [today]
/// (cancelled, no-show and finished stays left out).
List<MovementDay> movementsAhead(List<Map> bookings, String today, {int days = 7}) {
  final live = bookings.where((b) => b['status'] == 'Confirmed' || b['status'] == 'CheckedIn').toList();
  final start = _parse(today);
  return [
    for (var i = 0; i < days; i++)
      () {
        final d = _iso(start.add(Duration(days: i)));
        return (
          day: d,
          arrivals: live.where((b) => b['status'] == 'Confirmed' && _day(_v(b, 'checkInDate')) == d).length,
          departures: live.where((b) => _day(_v(b, 'checkOutDate')) == d).length,
        );
      }(),
  ];
}

const _methodOrder = ['Cash', 'Card', 'MobileMoney', 'BankTransfer'];
const _methodLabels = {'Cash': 'Cash', 'Card': 'Card', 'MobileMoney': 'Mobile Money', 'BankTransfer': 'Bank Transfer'};

/// Payments by method over the [days] days ending [today].
List<ChartSlice> paymentMix(List<Map> payments, String today, {int days = 30}) {
  final from = _iso(_parse(today).subtract(Duration(days: days - 1)));
  final recent = payments.where((p) {
    final d = _day(_v(p, 'paymentDate'));
    return d.compareTo(from) >= 0 && d.compareTo(today) <= 0;
  });
  final sums = <String, num>{};
  for (final p in recent) {
    final m = tStr(_v(p, 'paymentMethod'));
    final key = _methodOrder.contains(m) ? m : 'Other';
    sums[key] = (sums[key] ?? 0) + tNum(p['amount']);
  }
  return [
    for (final (i, m) in _methodOrder.indexed)
      if ((sums[m] ?? 0) > 0) (label: _methodLabels[m]!, value: sums[m]!, color: _series[i]),
    if ((sums['Other'] ?? 0) > 0) (label: 'Other', value: sums['Other']!, color: chartMagenta),
  ];
}

// ------------------------------------------------------------ the card shell

class HotelChartCard extends StatelessWidget {
  const HotelChartCard({super.key, required this.title, required this.subtitle, required this.child, this.icon});
  final String title, subtitle;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x1A0B0B0B)),
          boxShadow: const [BoxShadow(color: Color(0x0F1E1B4B), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: const Color(0xFF7C3AED)),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: _ink2)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          child,
        ]),
      );
}

/// A colour key: a rounded swatch and its label in text ink, never series ink.
Widget chartKey(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, color: _ink2)),
    ]);

/// Runs 0 → 1 on first show, and again from the old figures to the new ones
/// whenever they change (the dashboard refreshes every 30 seconds).
mixin _Grow<T extends StatefulWidget> on State<T>, SingleTickerProviderStateMixin<T> {
  late final AnimationController grow = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  late final Animation<double> eased = CurvedAnimation(parent: grow, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    grow.dispose();
    super.dispose();
  }
}

// ----------------------------------------------------------- 1. the room donut

class RoomMixDonut extends StatefulWidget {
  const RoomMixDonut({super.key, required this.slices});
  final List<ChartSlice> slices;

  @override
  State<RoomMixDonut> createState() => _RoomMixDonutState();
}

class _RoomMixDonutState extends State<RoomMixDonut> with SingleTickerProviderStateMixin, _Grow {
  int? _picked;

  num get _total => widget.slices.fold<num>(0, (s, x) => s + x.value);

  @override
  void didUpdateWidget(RoomMixDonut old) {
    super.didUpdateWidget(old);
    if ([for (final s in old.slices) s.value].join() != [for (final s in widget.slices) s.value].join()) grow.forward(from: 0);
  }

  void _tap(Offset p, Size size) {
    final c = size.center(Offset.zero);
    final d = p - c;
    final r = d.distance, outer = size.shortestSide / 2;
    if (r < outer * .55 || r > outer + 8 || _total <= 0) return setState(() => _picked = null);
    var a = math.atan2(d.dy, d.dx) + math.pi / 2;
    if (a < 0) a += 2 * math.pi;
    var acc = 0.0;
    for (final (i, s) in widget.slices.indexed) {
      acc += s.value / _total * 2 * math.pi;
      if (a <= acc) return setState(() => _picked = _picked == i ? null : i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final occupied = widget.slices.where((s) => s.label == 'Occupied').fold<num>(0, (a, s) => a + s.value);
    final pick = _picked != null && _picked! < widget.slices.length ? widget.slices[_picked!] : null;
    final centreValue = pick == null ? (total > 0 ? '${(occupied / total * 100).round()}%' : '—') : '${pick.value}';
    final centreLabel = pick == null ? 'occupied' : pick.label.toLowerCase();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: SizedBox(
          width: 190,
          height: 190,
          child: GestureDetector(
            onTapDown: (e) => _tap(e.localPosition, const Size(190, 190)),
            child: AnimatedBuilder(
              animation: eased,
              builder: (_, _) => CustomPaint(
                painter: _DonutPainter(slices: widget.slices, t: eased.value, picked: _picked),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(centreValue, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: _ink, height: 1.1)),
                    Text(centreLabel, style: const TextStyle(fontSize: 12, color: _ink2)),
                    Text('of $total rooms', style: const TextStyle(fontSize: 11, color: _muted)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      for (final (i, s) in widget.slices.indexed)
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _picked = _picked == i ? null : i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: _picked == i ? const Color(0xFFF4F4F2) : null, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 10),
              Expanded(child: Text(s.label, style: const TextStyle(fontSize: 13, color: _ink))),
              Text('${s.value}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
              SizedBox(
                width: 48,
                child: Text(total > 0 ? '${(s.value / total * 100).round()}%' : '0%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: _muted)),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.t, required this.picked});
  final List<ChartSlice> slices;
  final double t;
  final int? picked;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<num>(0, (s, x) => s + x.value);
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 10;
    const stroke = 26.0;
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0xFFF0EFEC));
    if (total <= 0) return;
    final sweepAll = 2 * math.pi * t;
    var start = -math.pi / 2;
    final live = slices.where((s) => s.value > 0).length;
    // A 2px surface gap between segments, as an angle at the ring's radius.
    final gap = live > 1 ? 2.5 / r : 0.0;
    for (final (i, s) in slices.indexed) {
      if (s.value <= 0) continue;
      final full = s.value / total * 2 * math.pi;
      final sweep = math.min(full, math.max(0.0, sweepAll - (start + math.pi / 2)));
      if (sweep > gap) {
        final on = picked == i;
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: on ? r + 3 : r),
          start + gap / 2,
          sweep - gap,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = on ? stroke + 8 : stroke
            ..strokeCap = StrokeCap.butt
            ..color = picked == null || on ? s.color : s.color.withValues(alpha: .35),
        );
      }
      start += full;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter o) => o.t != t || o.picked != picked || o.slices != slices;
}

// ------------------------------------------------- 2 & 3. the paired columns

/// Two series side by side per day, growing from the baseline. Tap a day to
/// read its figures above the chart.
class PairedColumns extends StatefulWidget {
  const PairedColumns({
    super.key,
    required this.days,
    required this.a,
    required this.b,
    required this.aLabel,
    required this.bLabel,
    required this.dayLabel,
    required this.valueText,
    this.highlight,
    this.money = false,
    this.footer,
  });

  final List<String> days;
  final List<num> a, b;
  final String aLabel, bLabel;
  final String Function(String day) dayLabel;
  final String Function(num v) valueText;

  /// The day drawn as "today".
  final String? highlight;
  final bool money;
  final Widget Function(int i)? footer;

  @override
  State<PairedColumns> createState() => _PairedColumnsState();
}

class _PairedColumnsState extends State<PairedColumns> with SingleTickerProviderStateMixin, _Grow {
  int? _picked;

  @override
  void didUpdateWidget(PairedColumns old) {
    super.didUpdateWidget(old);
    if ('${old.a}${old.b}' != '${widget.a}${widget.b}') grow.forward(from: 0);
  }

  static const _left = 40.0, _bottom = 22.0, _height = 190.0;

  void _tap(Offset p, double width) {
    final n = widget.days.length;
    final slot = (width - _left) / n;
    final i = ((p.dx - _left) / slot).floor();
    setState(() => _picked = i < 0 || i >= n || _picked == i ? null : i);
  }

  @override
  Widget build(BuildContext context) {
    final i = _picked;
    final sumA = widget.a.fold<num>(0, (s, x) => s + x), sumB = widget.b.fold<num>(0, (s, x) => s + x);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // The read-out: totals, or the tapped day.
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Container(
          key: ValueKey(i),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFF9F9F7), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Expanded(
              child: Text(i == null ? 'Total' : widget.dayLabel(widget.days[i]),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _ink2)),
            ),
            _readout(chartBlue, widget.aLabel, widget.valueText(i == null ? sumA : widget.a[i])),
            const SizedBox(width: 14),
            _readout(chartOrange, widget.bLabel, widget.valueText(i == null ? sumB : widget.b[i])),
          ]),
        ),
      ),
      if (i != null && widget.footer != null) Padding(padding: const EdgeInsets.only(top: 6), child: widget.footer!(i)),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (_, box) => GestureDetector(
          onTapDown: (e) => _tap(e.localPosition, box.maxWidth),
          child: AnimatedBuilder(
            animation: eased,
            builder: (_, _) => CustomPaint(
              size: Size(box.maxWidth, _height),
              painter: _ColumnsPainter(
                days: widget.days,
                a: widget.a,
                b: widget.b,
                t: eased.value,
                picked: _picked,
                highlight: widget.highlight,
                tick: widget.money ? compactMoney : (n) => n.toStringAsFixed(0),
                xLabel: widget.dayLabel,
                font: DefaultTextStyle.of(context).style.fontFamily,
                integer: !widget.money,
                left: _left,
                bottom: _bottom,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 16, runSpacing: 6, children: [chartKey(chartBlue, widget.aLabel), chartKey(chartOrange, widget.bLabel)]),
    ]);
  }

  Widget _readout(Color c, String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
        ]),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
      ]);
}

class _ColumnsPainter extends CustomPainter {
  _ColumnsPainter({
    required this.days,
    required this.a,
    required this.b,
    required this.t,
    required this.picked,
    required this.highlight,
    required this.tick,
    required this.xLabel,
    required this.font,
    required this.integer,
    required this.left,
    required this.bottom,
  });

  final List<String> days;
  final List<num> a, b;
  final double t, left, bottom;
  final int? picked;
  final String? highlight;
  final String Function(num) tick;
  final String Function(String) xLabel;
  final String? font;
  final bool integer;

  /// A round top for the axis (1, 2, 2.5 or 5 × 10ⁿ) and how many equal
  /// steps reach it, so every tick is a round number.
  static (double, int) niceScale(num v) {
    if (v <= 0) return (5, 5);
    final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final (m, steps) in [(1, 5), (2, 4), (2.5, 5), (5, 5), (10, 5)]) {
      if (m * p >= v) return (m * p, steps);
    }
    return (10 * p, 5);
  }

  void _text(Canvas canvas, String s, Offset at, {Color color = _muted, double size = 10, bool right = false, bool centre = false, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: font, fontSize: size, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = right ? at.dx - tp.width : centre ? at.dx - tp.width / 2 : at.dx;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = days.length;
    if (n == 0) return;
    // Counts never get fractional ticks: their axis is at least 0–5.
    final peak = [...a, ...b].fold<num>(0, math.max);
    final (top, steps) = niceScale(integer ? math.max(peak, 5) : peak);
    final plotH = size.height - bottom - 6;
    double y(num v) => 6 + plotH - (v / top) * plotH;

    // Recessive grid: hairlines at round steps, and a baseline.
    for (var k = 0; k <= steps; k++) {
      final v = top * k / steps;
      final gy = y(v);
      canvas.drawLine(Offset(left, gy), Offset(size.width, gy), Paint()
        ..color = k == 0 ? _baseline : _grid
        ..strokeWidth = 1);
      _text(canvas, tick(v), Offset(left - 6, gy), right: true);
    }

    final slot = (size.width - left) / n;
    final barW = math.min(14.0, (slot - 6) / 2);
    for (var i = 0; i < n; i++) {
      final cx = left + slot * i + slot / 2;
      if (picked == i || days[i] == highlight) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(left + slot * i + 1, 4, slot - 2, plotH + 4), const Radius.circular(6)),
          Paint()..color = picked == i ? const Color(0xFFEDE9FE) : const Color(0xFFF6F5F2),
        );
      }
      // Each day starts a little after the one before, so the bars ripple in.
      final local = ((t * (1 + n * .04)) - i * .04).clamp(0.0, 1.0);
      final dim = picked != null && picked != i;
      for (final (j, v) in [a[i], b[i]].indexed) {
        if (v <= 0) continue;
        final h = (v / top) * plotH * local;
        final x = j == 0 ? cx - barW - 1 : cx + 1;
        final base = 6 + plotH;
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(x, base - h, barW, h), topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
          Paint()..color = (j == 0 ? chartBlue : chartOrange).withValues(alpha: dim ? .3 : 1),
        );
      }
      // Day labels: every one when there is room, else every other, and
      // never one that would crowd "Today" beside it.
      final crowdsToday = n > 7 && i + 1 < n && days[i + 1] == highlight;
      if ((n <= 7 || i.isEven || days[i] == highlight) && !crowdsToday) {
        _text(canvas, xLabel(days[i]), Offset(cx, size.height - bottom / 2 + 2),
            centre: true, color: days[i] == highlight ? _ink : _muted, bold: days[i] == highlight);
      }
    }
  }

  @override
  bool shouldRepaint(_ColumnsPainter o) => o.t != t || o.picked != picked || o.a != a || o.b != b;
}

// ------------------------------------------------------ 4. the payment mix bar

class PaymentMixBar extends StatefulWidget {
  const PaymentMixBar({super.key, required this.slices, required this.money});
  final List<ChartSlice> slices;
  final String Function(num) money;

  @override
  State<PaymentMixBar> createState() => _PaymentMixBarState();
}

class _PaymentMixBarState extends State<PaymentMixBar> with SingleTickerProviderStateMixin, _Grow {
  @override
  void didUpdateWidget(PaymentMixBar old) {
    super.didUpdateWidget(old);
    if ([for (final s in old.slices) s.value].join() != [for (final s in widget.slices) s.value].join()) grow.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.slices.fold<num>(0, (s, x) => s + x.value);
    if (total <= 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text('No payments in the last 30 days', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: _muted)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.money(total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _ink)),
      const Text('received in the last 30 days', style: TextStyle(fontSize: 12, color: _ink2)),
      const SizedBox(height: 12),
      AnimatedBuilder(
        animation: eased,
        builder: (_, _) => ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 18,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, s) in widget.slices.indexed) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(flex: math.max(1, (s.value / total * 1000 * eased.value).round()), child: ColoredBox(color: s.color)),
              ],
              // The rest of the track until the bar has grown.
              if (eased.value < 1) Expanded(flex: math.max(1, (1000 * (1 - eased.value)).round()), child: const ColoredBox(color: Color(0xFFF0EFEC))),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 12),
      for (final s in widget.slices)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 10),
            Expanded(child: Text(s.label, style: const TextStyle(fontSize: 13, color: _ink))),
            Text(widget.money(s.value), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
            SizedBox(width: 48, child: Text('${(s.value / total * 100).round()}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: _muted))),
          ]),
        ),
    ]);
  }
}

// ------------------------------------------------------------- the section

/// The four charts, as the dashboard shows them.
class HotelDashboardCharts extends StatelessWidget {
  const HotelDashboardCharts({
    super.key,
    required this.statusSummary,
    required this.bookings,
    required this.payments,
    required this.expenses,
    required this.today,
  });

  final List<Map> statusSummary, bookings, payments, expenses;
  final String today;

  @override
  Widget build(BuildContext context) {
    final money = dailyMoney(payments, expenses, today);
    final moves = movementsAhead(bookings, today);
    String fixed(num v) => v.toStringAsFixed(2);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HotelChartCard(
        icon: Icons.donut_large,
        title: 'Room mix',
        subtitle: 'Every room by its status right now. Tap a colour to single it out.',
        child: RoomMixDonut(slices: roomMix(statusSummary)),
      ),
      HotelChartCard(
        icon: Icons.bar_chart,
        title: 'Money in & out',
        subtitle: 'Payments received and expenses, day by day, last 14 days. Tap a day.',
        child: PairedColumns(
          days: [for (final d in money) d.day],
          a: [for (final d in money) d.revenue],
          b: [for (final d in money) d.expenses],
          aLabel: 'Revenue',
          bLabel: 'Expenses',
          dayLabel: (d) => d == today ? 'Today' : '${_parse(d).day}',
          valueText: fixed,
          highlight: today,
          money: true,
          footer: (i) {
            final net = money[i].revenue - money[i].expenses;
            return Text('${_nice(money[i].day)} · net ${net >= 0 ? '+' : ''}${fixed(net)}',
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: _ink2));
          },
        ),
      ),
      HotelChartCard(
        icon: Icons.swap_vert,
        title: 'Arrivals & departures',
        subtitle: 'Stays starting and ending each day, next 7 days. Tap a day.',
        child: PairedColumns(
          days: [for (final d in moves) d.day],
          a: [for (final d in moves) d.arrivals],
          b: [for (final d in moves) d.departures],
          aLabel: 'Arrivals',
          bLabel: 'Departures',
          dayLabel: (d) => d == today ? 'Today' : _weekdays[_parse(d).weekday - 1],
          valueText: (v) => v.toStringAsFixed(0),
          highlight: today,
        ),
      ),
      HotelChartCard(
        icon: Icons.payments_outlined,
        title: 'How guests pay',
        subtitle: 'Payments by method, last 30 days.',
        child: PaymentMixBar(slices: paymentMix(payments, today), money: fixed),
      ),
    ]);
  }
}
